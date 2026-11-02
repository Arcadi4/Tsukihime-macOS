import Foundation
import TsukiCore

/// The local date and time stored in a save slot (slot +0x70C0..+0x70C6; Rtc_LocalTime 0xEAD50).
public struct SlotDate: Comparable, Equatable, Hashable, CustomStringConvertible, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int
    public var hour: Int
    public var minute: Int
    public var second: Int

    public init(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) {
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
    }

    /// The date of a local `Date`.
    public static func from(date: Date) -> SlotDate {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return SlotDate(
            year: c.year ?? 2000,
            month: c.month ?? 1,
            day: c.day ?? 1,
            hour: c.hour ?? 0,
            minute: c.minute ?? 0,
            second: c.second ?? 0
        )
    }

    /// True when the fields describe a real date (the save checker of adv_state.md 7.7: 2000..2100).
    public var isPlausible: Bool {
        year >= 2000 && year <= 2100 &&
            month >= 1 && month <= 12 &&
            day >= 1 && day <= 31 &&
            hour >= 0 && hour < 24 &&
            minute >= 0 && minute < 60 &&
            second >= 0 && second < 60
    }

    /// The date as a `Date`, or nil when the fields are not a calendar date.
    public func toDate() -> Date? {
        guard isPlausible else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = hour
        c.minute = minute
        c.second = second
        guard let d = cal.date(from: c) else { return nil }
        let check = cal.dateComponents([.day], from: d)
        if check.day != day { return nil }
        return d
    }

    public static func < (lhs: SlotDate, rhs: SlotDate) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        if lhs.day != rhs.day { return lhs.day < rhs.day }
        if lhs.hour != rhs.hour { return lhs.hour < rhs.hour }
        if lhs.minute != rhs.minute { return lhs.minute < rhs.minute }
        return lhs.second < rhs.second
    }

    public var description: String {
        String(format: "%04d-%02d-%02d %02d:%02d:%02d", year, month, day, hour, minute, second)
    }
}

/// One save slot as the PS4 stores it (0x7108 bytes; adv_state.md 7.4, tools/eboot/savedata.py SLOT_FIELDS): magic and
/// used flag, whether state B follows, state A (the newest page-start history record), state B (the first 0x36A8
/// bytes of the scene-stack top record), the date and the end marker. The same layout is the slot staging
/// (RAM 0x12031E0) that the history code keeps current while the game runs.
public final class SlotImage: StateBlock {
    /// Size of a slot in bytes.
    public static let size = 0x7108

    /// Size of state B (the first part of a history record).
    public static let stateBSize = 0x36A8

    /// Offset of state A.
    public static let stateAOffset = 8

    /// Offset of state B.
    public static let stateBOffset = 0x3A18

    /// Offset of the date (u16 year, then month, day, hour, minute, second).
    public static let dateOffset = 0x70C0

    /// Offset of the end marker (u16 0x2AF8).
    public static let endMarkerOffset = 0x70C8

    /// The magic word 0x2AF8 at +0 and at the end marker.
    public static let magic: UInt16 = 0x2AF8

    private var _stateA: HistoryRecord?

    /// Creates an empty slot (all zero).
    public init() {
        super.init(size: SlotImage.size)
    }

    /// Wraps `bytes` (exactly `size` bytes, not copied).
    public init(bytes: [UInt8]) {
        precondition(bytes.count == SlotImage.size, "a slot is 0x\(String(SlotImage.size, radix: 16)) bytes, got 0x\(String(bytes.count, radix: 16))")
        super.init(storage: ByteStorage(bytes), offset: 0, length: SlotImage.size)
    }

    /// Wraps `storage` at `offset`.
    public init(storage: ByteStorage, offset: Int = 0) {
        super.init(storage: storage, offset: offset, length: SlotImage.size)
    }

    /// u16 at +0 (0x2AF8 in a stored slot).
    public var magicWord: UInt16 {
        get { readU16(0) }
        set { writeU16(0, newValue) }
    }

    /// u16 at +2: non-zero when the slot holds a save (the staging sets it to 1 with its first snapshot).
    public var used: UInt16 {
        get { readU16(2) }
        set { writeU16(2, newValue) }
    }

    /// i32 at +4: 1 when state B follows; 0 (or less) when the scene stack was empty.
    public var hasStateB: Int32 {
        get { readI32(4) }
        set { writeI32(4, newValue) }
    }

    /// u16 at the end marker (0x2AF8 in a stored slot).
    public var endMarker: UInt16 {
        get { readU16(SlotImage.endMarkerOffset) }
        set { writeU16(SlotImage.endMarkerOffset, newValue) }
    }

    /// State A as a history record (a view of the slot's bytes).
    public var stateA: HistoryRecord {
        if let s = _stateA { return s }
        let s = HistoryRecord(storage: storage, offset: offset + SlotImage.stateAOffset)
        _stateA = s
        return s
    }

    /// State B writable window: the first `stateBSize` bytes of a history record.
    public var stateBWindow: ByteWindow {
        slice(SlotImage.stateBOffset, SlotImage.stateBSize)
    }

    /// State B: the first `stateBSize` bytes of a history record.
    public var stateB: ByteSpan {
        stateBWindow.span
    }

    /// True when the slot holds a save: magic, used flag and end marker are all present.
    public var isStored: Bool {
        magicWord == SlotImage.magic && used != 0 && endMarker == SlotImage.magic
    }

    /// F22 of state A: the scene number the save list shows as the slot's title (text id F22 + 0x18C, gallery.md 9; the list and the
    /// system menu read `F022 + 0x18C`).
    public var sceneVariable: Int {
        if let idx = HistoryRecord.fU16Indices.firstIndex(of: 22) {
            return Int(stateA.getFU16(idx))
        }
        return 0
    }

    /// The slot's date.
    public var date: SlotDate {
        get {
            let yr = Int(readU16(SlotImage.dateOffset))
            let mo = Int(readU8(SlotImage.dateOffset + 2))
            let da = Int(readU8(SlotImage.dateOffset + 3))
            let hr = Int(readU8(SlotImage.dateOffset + 4))
            let mi = Int(readU8(SlotImage.dateOffset + 5))
            let se = Int(readU8(SlotImage.dateOffset + 6))
            return SlotDate(year: yr, month: mo, day: da, hour: hr, minute: mi, second: se)
        }
        set {
            writeU16(SlotImage.dateOffset, UInt16(clamping: newValue.year))
            writeU8(SlotImage.dateOffset + 2, UInt8(clamping: newValue.month))
            writeU8(SlotImage.dateOffset + 3, UInt8(clamping: newValue.day))
            writeU8(SlotImage.dateOffset + 4, UInt8(clamping: newValue.hour))
            writeU8(SlotImage.dateOffset + 5, UInt8(clamping: newValue.minute))
            writeU8(SlotImage.dateOffset + 6, UInt8(clamping: newValue.second))
        }
    }

    /// A copy of the slot.
    public func clone() -> SlotImage {
        let copy = SlotImage()
        copy.copy(from: self)
        return copy
    }

    /// Staging_SetSnapshot (VA 0x73980): copies `record` over state A, sets used = 1 and the state-B flag
    /// to `min(n, 1)`, and copies the first 0x36A8 bytes of `stackTop` over state B when
    /// `n` > 0 and the record is given.
    public func setSnapshot(_ record: HistoryRecord, _ n: Int, _ stackTop: HistoryRecord?) {
        slice(SlotImage.stateAOffset, HistoryRecord.size).copy(from: record.bytes)
        used = 1
        hasStateB = Int32(n > 0 ? 1 : n)
        if n > 0, let stackTop = stackTop {
            stateBWindow.copy(from: stackTop.bytes.slice(0, SlotImage.stateBSize))
        }
    }

    /// Stores the staging into a slot the way Slot_Store (0x737D0) and QuickSave_Store (0x73A70) do: the whole staging is
    /// copied, the first dword becomes 0x12AF8 (magic + used = 1), the date and the end marker are written, and for a
    /// manual or auto save (`markSaved`) the F1118 bit of state A is set.
    public func storeFrom(_ staging: SlotImage, _ date: SlotDate, _ markSaved: Bool) {
        copy(from: staging)
        writeU32(0, 0x12AF8)
        self.date = date
        endMarker = SlotImage.magic
        if markSaved {
            if let k = HistoryRecord.fBoolIndices.firstIndex(of: AdvLiveState.FIndex.savedMarker) {
                stateA.setFBoolBit(k, true)
            }
        }
    }
}
