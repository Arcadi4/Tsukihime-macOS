import Foundation
import TsukiCore
import TsukiEngine
import TsukiUi

extension AppServices: UiSaveServices {
    public var savingDisabled: Bool {
        host.f(25) != 0 || !storyActive || host.phase != .running
    }

    public var slots: [UiSlot] {
        if cachedVersion != slotsVersion || slotList.count != SaveStore.slotCount {
            slotList = buildSlots()
            cachedVersion = slotsVersion
        }
        return slotList
    }

    private func buildSlots() -> [UiSlot] {
        var list = [UiSlot]()
        list.reserveCapacity(SaveStore.slotCount)
        for i in 0..<SaveStore.slotCount {
            guard let image = store.getSlot(i) else {
                list.append(UiSlot(index: i, used: false, date: Date(timeIntervalSince1970: 0), phase: 0, sceneTitle: 0, notes: ""))
                continue
            }
            let a = image.stateA
            let phase = AdvHistory.recordF8(a, 23)
            let date = image.date.toDate() ?? Date(timeIntervalSince1970: 0)
            list.append(UiSlot(index: i, used: true, date: date, phase: max(0, min(37, phase)), sceneTitle: image.sceneVariable, notes: Self.notes(a)))
        }
        return list
    }

    public static func notes(_ record: HistoryRecord) -> String {
        let raw = record.messageText
        let nul = raw.firstIndex(of: 0) ?? raw.count
        let slice = raw[0..<nul]
        let text = String(decoding: slice, as: UTF8.self)
        var result = ""
        result.reserveCapacity(text.count)

        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if c == "@" {
                let next = text.index(after: i)
                if next < text.endIndex {
                    i = text.index(after: next)
                    continue
                }
            }
            if c == "\n" || c == "\r" {
                result.append("^")
            } else if c >= " " {
                result.append(c)
            }
            i = text.index(after: i)
        }
        return result
    }

    func slotsChanged() {
        slotsVersion += 1
    }

    public func thumbnail(_ slot: Int) -> UiThumbnail? {
        guard slot >= 0 && slot < SaveStore.slotCount else {
            return nil
        }

        guard let stored = store.getThumbnail(slot) else {
            thumbnails.removeValue(forKey: slot)
            return nil
        }

        if let cached = thumbnails[slot], cached.source == stored {
            return cached.thumbnail
        }

        var ui: UiThumbnail?
        if let t = ThumbnailCodec.decode(stored) {
            thumbVersion += 1
            ui = UiThumbnail(width: t.width, height: t.height, version: thumbVersion, rgba: t.rgba)
        }

        thumbnails[slot] = (ui, stored)
        return ui
    }

    public func save(_ slot: Int) -> Bool {
        guard !savingDisabled, slot >= 0 && slot < SaveStore.autoSaveFirst else {
            return false
        }
        guard let history = host.history else {
            return false
        }

        var ok = store.saveManual(slot, history.staging, date(), captureThumbnail())
        if ok {
            slotsChanged()
            ok = commit()
        }
        return ok
    }

    public func load(_ slot: Int) -> Bool {
        guard slot >= 0 && slot < SaveStore.slotCount && store.hasSave(slot) else {
            return false
        }

        do {
            stopMenuAudio()
            stopIntroMovie()
            stopTitleMovie()
            try host.loadSlot(store, slot: slot)
            storyActive = true
            host.setSkipLatch(false)
            return true
        } catch {
            log("slot \(slot) could not be loaded: \(error.localizedDescription)")
            return false
        }
    }

    public func delete(_ slot: Int) -> Bool {
        guard slot >= 0 && slot < SaveStore.autoSaveFirst && store.hasSave(slot) else {
            return false
        }

        store.delete(slot)
        thumbnails.removeValue(forKey: slot)
        slotsChanged()
        return commit()
    }

    public func copy(_ slot: Int) -> Bool {
        guard let image = store.getSlot(slot) else {
            return false
        }

        for free in 0..<SaveStore.manualSlotCount {
            if !store.hasSave(free) {
                let thumb = store.getThumbnail(slot)
                if !store.saveManual(free, image.clone(), image.date, thumb) {
                    return false
                }
                slotsChanged()
                return commit()
            }
        }
        return false
    }

    public func quickSave() -> Bool {
        guard !savingDisabled, frameCounter - lastQuickSave >= quickSaveCooldownFrames else {
            return false
        }
        guard let history = host.history else {
            return false
        }

        guard store.quickSave(history.staging, date(), captureThumbnail()) else {
            return false
        }

        lastQuickSave = frameCounter
        slotsChanged()
        return commit()
    }

    public func quickLoad() -> Bool {
        load(SaveStore.quickSlot)
    }

    public var hasQuickSave: Bool {
        store.hasSave(SaveStore.quickSlot)
    }

    public func noteStoryStep() {
        if host.historySink?.store != nil && store.hasSave(SaveStore.autoSaveFirst) {
            if let s = store.getSlot(SaveStore.autoSaveFirst) {
                if s !== lastAutoSlot || s.date != lastAutoDate {
                    lastAutoSlot = s
                    lastAutoDate = s.date
                    slotsChanged()
                }
            }
        }
    }

    private static func samePoint(_ a: HistoryRecord, _ b: HistoryRecord) -> Bool {
        a.script == b.script && a.cmdOffset == b.cmdOffset && a.resumeOffset == b.resumeOffset && a.kind == b.kind
    }

    public func autoSaveForTitle() -> Bool {
        guard !savingDisabled, let history = host.history, history.staging.used != 0 else {
            return false
        }

        if let newest = store.getSlot(SaveStore.autoSaveFirst), Self.samePoint(newest.stateA, history.staging.stateA) {
            return false
        }

        guard store.autoSave(history.staging, date(), captureThumbnail()) else {
            return false
        }

        slotsChanged()
        return commit()
    }
}
