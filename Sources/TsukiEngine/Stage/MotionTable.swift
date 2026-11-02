/// The motion tables of the eboot as the stage reads them (docs/formats/layers.md 8.1): the duration
/// and end index of each of 24,192 motions, 71,905 keyframes of 27 fields, the field-enable word of
/// each motion and the loop point of each motion. The data layer implements it over the eboot tables
/// (text VA 0x245130 for the flag words) and the loop switch (VA 0xC1C70, package K1b).
/// Implementations are immutable; ``MotionTable`` adds the session edits of `_SGMA`.
public protocol MotionTables: AnyObject {
    /// Number of motions (ids 1..motionCount); 24,192.
    var motionCount: Int { get }

    /// Number of keyframes (the end index of the last motion); 71,905.
    var keyCount: Int { get }

    /// Duration of motion `id` (1..motionCount) in milliseconds.
    func duration(_ id: Int) -> Int

    /// Exclusive end index of the keyframes of motion `id` (1..motionCount); motion id uses
    /// `[keyEnd(id - 1), keyEnd(id))`.
    func keyEnd(_ id: Int) -> Int

    /// Time in milliseconds of keyframe `index`.
    func keyTime(_ index: Int) -> Int

    /// Field `field` (1..27) of keyframe `index`; -32767 (-100001 for field 8) = not animated.
    func keyField(_ index: Int, _ field: Int) -> Int

    /// The field-enable word of motion `id` (table 0x245130, indexed by id).
    func fieldMask(_ id: Int) -> UInt64

    /// The loop point of motion `id` (VA 0xC1C70): 0 no loop, 1 loop the whole motion, n greater than
    /// 1 loop from n ms.
    func loopPoint(_ id: Int) -> Int
}

/// A ``MotionTables`` over plain arrays (tests, golden data, adapters).
public final class ArrayMotionTables: MotionTables {
    private let durationValues: [Int]
    private let endValues: [Int]
    private let times: [Int]
    private let fields: [Int]
    private let masks: [UInt64]
    private let loops: [Int]

    /// Creates the tables.
    /// - Parameters:
    ///   - duration: Duration of motion id at index id - 1.
    ///   - end: Exclusive end key of motion id at index id - 1.
    ///   - times: Time of each key.
    ///   - fields: 27 fields per key, flat (field f of key i at `27 * i + f - 1`).
    ///   - masks: Field-enable word of motion id at index id - 1.
    ///   - loops: Loop point of motion id at index id - 1.
    public init(duration: [Int], end: [Int], times: [Int], fields: [Int], masks: [UInt64], loops: [Int]) {
        precondition(end.count == duration.count && masks.count == duration.count && loops.count == duration.count,
                     "duration, end, masks and loops need one entry per motion")
        precondition(fields.count == times.count * MotionTable.fieldCount,
                     "27 fields per key are required")
        durationValues = duration
        endValues = end
        self.times = times
        self.fields = fields
        self.masks = masks
        self.loops = loops
    }

    public var motionCount: Int { durationValues.count }

    public var keyCount: Int { times.count }

    public func duration(_ id: Int) -> Int { durationValues[id - 1] }

    public func keyEnd(_ id: Int) -> Int { id < 1 ? 0 : endValues[id - 1] }

    public func keyTime(_ index: Int) -> Int { times[index] }

    public func keyField(_ index: Int, _ field: Int) -> Int { fields[MotionTable.fieldCount * index + field - 1] }

    public func fieldMask(_ id: Int) -> UInt64 { masks[id - 1] }

    public func loopPoint(_ id: Int) -> Int { loops[id - 1] }
}

/// One motion: keyframe records `[start, end)` of the global table.
public struct MotionRef: Sendable {
    /// Motion id.
    public let id: Int
    /// Duration in milliseconds.
    public let duration: Int
    /// First key.
    public let start: Int
    /// One past the last key.
    public let end: Int

    public init(id: Int, duration: Int, start: Int, end: Int) {
        self.id = id
        self.duration = duration
        self.start = start
        self.end = end
    }
}

/// The motion tables of one game session: the engine's in-memory keyframe table, which `_SGMA` edits
/// for the rest of the session (layers.md 4.3), over immutable eboot data. Port of `MotionTable` in
/// the oracle: ``val(_:_:)`` is the accessor VA 0xC2190 (field 0 = time), ``flags(_:)`` VA 0xC1C40
/// and ``get(_:)`` the duration / end accessors 0xC2150 / 0xC2170.
public final class MotionTable {
    /// Fields per keyframe after the time (1..27).
    public static let fieldCount = 27

    /// The i16 "not animated" marker.
    public static let unset = -32767

    /// The i16 "hold the previous value" marker.
    public static let hold = -32766

    /// The "not animated" marker of the i64 rotation field 8.
    public static let unset8 = -100001

    /// The "hold" marker of field 8.
    public static let hold8 = -100000

    private struct EditKey: Hashable {
        let index: Int
        let field: Int
    }

    private let source: MotionTables
    private var edits: [EditKey: Int] = [:]

    /// Creates a session table over `source`.
    public init(_ source: MotionTables) {
        self.source = source
    }

    /// Number of keyframes.
    public var keyCount: Int { source.keyCount }

    /// Number of motions.
    public var motionCount: Int { source.motionCount }

    /// Field `f` of keyframe `i` (0 = time); -32767 outside the table (VA 0xC2190).
    public func val(_ i: Int, _ f: Int) -> Int {
        guard i >= 0, i < source.keyCount, f >= 0, f <= Self.fieldCount else {
            return Self.unset
        }
        if f == 0 {
            return source.keyTime(i)
        }
        if !edits.isEmpty, let value = edits[EditKey(index: i, field: f)] {
            return value
        }
        return source.keyField(i, f)
    }

    /// Time of keyframe `i`.
    public func time(_ i: Int) -> Int { val(i, 0) }

    /// Changes field `f` (1..27) of keyframe `i` as `_SGMA` does.
    public func setVal(_ i: Int, _ f: Int, _ value: Int) {
        edits[EditKey(index: i, field: f)] = value
    }

    /// The field-enable word of motion `id`; 0 outside 1..24192 (VA 0xC1C40).
    public func flags(_ id: Int) -> UInt64 {
        id >= 1 && id <= source.motionCount ? source.fieldMask(id) : 0
    }

    /// The loop point of motion `id` (VA 0xC1C70).
    public func loop(_ id: Int) -> Int {
        id >= 1 && id <= source.motionCount ? source.loopPoint(id) : 0
    }

    /// The motion `id`, or nil for ids outside 1..24192 (no motion).
    public func get(_ id: Int) -> MotionRef? {
        guard id >= 1, id <= source.motionCount else { return nil }
        return MotionRef(id: id, duration: source.duration(id),
                         start: source.keyEnd(id - 1), end: source.keyEnd(id))
    }
}
