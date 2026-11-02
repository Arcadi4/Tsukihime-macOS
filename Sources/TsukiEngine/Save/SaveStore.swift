import Foundation
import TsukiCore

/// An image the app attaches to a slot (the thumbnail of the save list). The engine stores the bytes as given.
public struct SlotThumbnail: Equatable, Sendable {
    /// A format id chosen by the caller (the engine does not interpret it), 1..65535.
    public let format: UInt16

    /// The image bytes.
    public let data: [UInt8]

    public init(format: UInt16, data: [UInt8]) {
        self.format = format
        self.data = data
    }
}

/// All persistent save state in memory: the `SystemData`, the 140 save slots and their thumbnails
/// (docs/formats/adv_state.md 7). Slots 0..99 are manual saves, 100..138 an auto-save FIFO (newest at 100), slot 139
/// the quick save. `SaveFile` reads and writes it.
public final class SaveStore {
    /// Number of slots (0x8C).
    public static let slotCount = 140

    /// Manual slots are 0..99.
    public static let manualSlotCount = 100

    /// First auto-save slot (the newest auto save).
    public static let autoSaveFirst = 100

    /// Last auto-save slot (the oldest one that is kept).
    public static let autoSaveLast = 138

    /// The quick-save slot.
    public static let quickSlot = 139

    private var slots: [SlotImage?] = [SlotImage?](repeating: nil, count: SaveStore.slotCount)
    private var thumbnails: [SlotThumbnail?] = [SlotThumbnail?](repeating: nil, count: SaveStore.slotCount)

    /// Creates an empty store with fresh system data.
    public init() {
        self.systemData = SystemData()
    }

    /// Creates an empty store over existing system data.
    public init(_ systemData: SystemData) {
        self.systemData = systemData
    }

    /// The system data (config, global flags, unlock bits, read-text table).
    public let systemData: SystemData

    /// True when slot `slot` holds a save.
    public func hasSave(_ slot: Int) -> Bool {
        slots[check(slot)]?.isStored == true
    }

    /// The slot's image, or nil when it holds no save. Do not modify the returned object.
    public func getSlot(_ slot: Int) -> SlotImage? {
        guard let s = slots[check(slot)], s.isStored else { return nil }
        return s
    }

    /// The slot's thumbnail, or nil.
    public func getThumbnail(_ slot: Int) -> SlotThumbnail? {
        thumbnails[check(slot)]
    }

    /// The slot's date, or nil when it holds no save.
    public func getDate(_ slot: Int) -> SlotDate? {
        getSlot(slot)?.date
    }

    /// Slot indices that hold a save, ascending.
    public func storedSlots() -> [Int] {
        var result: [Int] = []
        for i in 0..<SaveStore.slotCount {
            if hasSave(i) {
                result.append(i)
            }
        }
        return result
    }

    /// Replaces a slot with an image read from a file (used by `SaveFile`).
    func setSlot(_ slot: Int, _ image: SlotImage, _ thumbnail: SlotThumbnail?) {
        slots[check(slot)] = image
        thumbnails[slot] = thumbnail
    }

    /// Slot_Store (VA 0x737D0): stores the staging as a manual save in slot 0..99 (the menu accepts 0..138), marking the
    /// page with F1118, and updates the latest slot.
    ///
    /// - Returns: False when the staging holds no snapshot yet.
    @discardableResult
    public func saveManual(_ slot: Int, _ staging: SlotImage, _ date: SlotDate, _ thumbnail: SlotThumbnail? = nil) -> Bool {
        precondition(slot >= 0 && slot <= SaveStore.autoSaveLast, "manual saves use slots 0..138, got \(slot)")
        if staging.used == 0 {
            return false
        }

        put(slot, staging, date, markSaved: true, thumbnail: thumbnail)
        updateLatestSlot()
        return true
    }

    /// QuickSave_Store (VA 0x73A70): stores the staging in slot 139 *without* the F1118 bit and without touching the
    /// latest slot. A quick save is refused for 300 frames after the last one on the PS4; that cooldown is the caller's.
    ///
    /// - Returns: False when the staging holds no snapshot yet.
    @discardableResult
    public func quickSave(_ staging: SlotImage, _ date: SlotDate, _ thumbnail: SlotThumbnail? = nil) -> Bool {
        if staging.used == 0 {
            return false
        }

        put(SaveStore.quickSlot, staging, date, markSaved: false, thumbnail: thumbnail)
        return true
    }

    /// The auto save (VA 0x73B70): slots 100..137 move to 101..138 (the oldest is dropped), the staging becomes slot 100
    /// (marked with F1118) and the latest slot is updated.
    ///
    /// - Returns: False when the staging holds no snapshot yet.
    @discardableResult
    public func autoSave(_ staging: SlotImage, _ date: SlotDate, _ thumbnail: SlotThumbnail? = nil) -> Bool {
        if staging.used == 0 {
            return false
        }

        for i in stride(from: SaveStore.autoSaveLast, to: SaveStore.autoSaveFirst, by: -1) {
            slots[i] = slots[i - 1]
            thumbnails[i] = thumbnails[i - 1]
        }

        slots[SaveStore.autoSaveFirst] = nil
        thumbnails[SaveStore.autoSaveFirst] = nil
        put(SaveStore.autoSaveFirst, staging, date, markSaved: true, thumbnail: thumbnail)
        updateLatestSlot()
        return true
    }

    /// Deletes a save (not a PS4 feature; the slot is emptied).
    public func delete(_ slot: Int) {
        let s = check(slot)
        slots[s] = nil
        thumbnails[s] = nil
        if slot < SaveStore.quickSlot {
            updateLatestSlot()
        }
    }

    /// Loads a stored slot into the history and the live variables (`AdvHistory.loadSlot`).
    public func load(_ slot: Int, _ history: AdvHistory, _ live: AdvLiveState) throws -> SceneRestoreResult {
        guard let image = getSlot(slot) else {
            throw TsukiError.state("slot \(slot) holds no save")
        }
        return try history.loadSlot(image, live)
    }

    /// SaveImage_Commit mode 2 (VA 0x6FEC0): the latest slot is the slot with the newest date among 0..138 (a strictly
    /// newer date wins, so the lowest index wins a tie); 0 when none is stored.
    public func updateLatestSlot() {
        var best = 0
        var bestDate: SlotDate? = nil
        for i in 0...SaveStore.autoSaveLast {
            if let s = getSlot(i) {
                let d = s.date
                if bestDate == nil || d > bestDate! {
                    best = i
                    bestDate = d
                }
            }
        }
        systemData.block.latestSlot = UInt16(best)
    }

    private func put(_ slot: Int, _ staging: SlotImage, _ date: SlotDate, markSaved: Bool, thumbnail: SlotThumbnail?) {
        let image: SlotImage
        if let existing = slots[slot], existing !== staging {
            image = existing
        } else {
            image = SlotImage()
        }
        image.storeFrom(staging, date, markSaved)
        slots[slot] = image
        thumbnails[slot] = thumbnail
    }

    @discardableResult
    private func check(_ slot: Int) -> Int {
        precondition(slot >= 0 && slot < SaveStore.slotCount, "slot must be in 0..\(SaveStore.slotCount - 1), got \(slot)")
        return slot
    }
}
