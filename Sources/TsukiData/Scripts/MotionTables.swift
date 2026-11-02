import Foundation
import TsukiCore
import TsukiEngine

/// One keyframe of a layer motion (docs/formats/layers.md; `script_tables.Keyframe`).
public struct MotionKeyframe: Sendable {
    /// Field 0: milliseconds from the motion start (an i64 at +0).
    public let time: Int64
    /// Fields 1..27: 7 i16 at +8..+0x14, the i64 at +0x18, then 19 i16 at +0x20..+0x44;
    /// `MotionTables.notAnimated` (-32767) marks a field that is not animated.
    public let fields: [Int64]

    public init(time: Int64, fields: [Int64]) {
        self.time = time
        self.fields = fields
    }
}

/// The layer motions `_STMA` / `_SGMA` play, compiled into the eboot as three tables (accessors at
/// VA 0xC2150, 0xC2170 and 0xC2190; consumer VA 0xBE4C0): the duration of each of 24,192 motions
/// (i64[24192], text VA 0x274538), the exclusive end index of each motion's keyframes (i64[24192],
/// text VA 0x2A3938) and 71,905 keyframes of 72 bytes (data VA 0x873FF0). Motion `id` (1-based, as
/// the script writes it) owns the keyframes from the end index of motion `id - 1` (0 for id 1) up to
/// its own end index. The loop points (a compiled switch at VA 0xC1C70) and the field-mask words are
/// not part of it.
public final class MotionTables {
    /// Motions: ids 1..24192 (the accessor compares `id - 1` with 0x5E7F).
    public static let motionCount = 0x5E80

    /// Text VA of the duration table.
    public static let durationVa = 0x274538

    /// Text VA of the end-index table.
    public static let endVa = 0x2A3938

    /// Data VA of the first keyframe.
    public static let keysVa = 0x873FF0

    /// Bytes of a keyframe.
    public static let keySize = 72

    /// The highest valid keyframe index (VA 0xC2197).
    public static let maxKey = 0x118E0

    /// Number of fields after the time (1..27).
    public static let fieldCount = 27

    /// The i16 marker of a field that is not animated.
    public static let notAnimated: Int16 = -32767

    private let durationValues: [Int64]
    private let endValues: [Int64]
    private let times: [Int64]
    private let fieldValues: [Int64]

    private init(duration: [Int64], end: [Int64], times: [Int64], fields: [Int64]) {
        self.durationValues = duration
        self.endValues = end
        self.times = times
        self.fieldValues = fields
    }

    /// Number of keyframes (the end index of the last motion).
    public var keyframeCount: Int { times.count }

    /// Motions in this table (24,192 in the verified build).
    public var count: Int { durationValues.count }

    /// Reads the three tables from the eboot.
    public static func read(_ eboot: EbootReader) throws -> MotionTables {
        let layout = eboot.layout
        let motions = layout.motionCount
        let maxKeys = layout.keyframeCount
        guard motions > 0 else {
            throw TsukiError.format("motion table is empty")
        }

        let duration = try readInt64s(eboot, layout.motionDurations, motions)
        let end = try readInt64s(eboot, layout.motionEnds, motions)
        var previous: Int64 = 0
        for k in 0..<motions {
            if end[k] < previous || end[k] > Int64(maxKeys) {
                throw TsukiError.format("motion \(k + 1): end index \(end[k]) (previous \(previous), at most \(maxKeys))")
            }
            previous = end[k]
        }

        let keyCount64 = end[motions - 1]
        guard keyCount64 >= 0, keyCount64 <= Int64(Int.max) else {
            throw TsukiError.format("motion table end index \(keyCount64) is out of range")
        }
        let keys = Int(keyCount64)
        var times = [Int64](repeating: 0, count: keys)
        var fields = [Int64](repeating: 0, count: keys * fieldCount)
        let raw = try eboot.read(layout.motionKeys, keySize * keys)
        for i in 0..<keys {
            let record = raw.slice(keySize * i, keySize)
            times[i] = record.i64(0)
            let base = fieldCount * i
            for j in 0..<7 {
                fields[base + j] = Int64(record.i16(8 + (2 * j)))
            }
            fields[base + 7] = record.i64(0x18)
            for j in 0..<19 {
                fields[base + 8 + j] = Int64(record.i16(0x20 + (2 * j)))
            }
        }

        return MotionTables(duration: duration, end: end, times: times, fields: fields)
    }

    /// The duration in milliseconds of motion `id` (1-based).
    public func duration(_ id: Int) throws -> Int64 {
        durationValues[try checkId(id)]
    }

    /// The keyframes of motion `id` (1-based) as the half-open range of keyframe indices.
    public func keyRange(_ id: Int) throws -> (first: Int, end: Int) {
        let k = try checkId(id)
        let first = k == 0 ? 0 : Int(endValues[k - 1])
        return (first, Int(endValues[k]))
    }

    /// The number of keyframes of motion `id`.
    public func keyframeCountOf(_ id: Int) throws -> Int {
        let range = try keyRange(id)
        return max(range.end - range.first, 0)
    }

    /// Keyframe `index` (0-based, over all motions).
    public func keyframe(_ index: Int) throws -> MotionKeyframe {
        guard index >= 0 && index < times.count else {
            throw TsukiError.bounds("keyframe index out of range 0..\(times.count - 1)")
        }
        let base = Self.fieldCount * index
        return MotionKeyframe(time: times[index],
                              fields: Array(fieldValues[base..<(base + Self.fieldCount)]))
    }

    /// The keyframes of motion `id` in order.
    public func keyframes(_ id: Int) throws -> [MotionKeyframe] {
        let range = try keyRange(id)
        var result: [MotionKeyframe] = []
        result.reserveCapacity(max(range.end - range.first, 0))
        for i in range.first..<range.end {
            result.append(try keyframe(i))
        }
        return result
    }

    private func checkId(_ id: Int) throws -> Int {
        guard id >= 1 && id <= durationValues.count else {
            throw TsukiError.bounds("motion id out of range 1..\(durationValues.count)")
        }
        return id - 1
    }

    private static func readInt64s(_ eboot: EbootReader, _ textVa: Int, _ count: Int) throws -> [Int64] {
        let raw = try eboot.read(textVa, 8 * count)
        var values = [Int64](repeating: 0, count: count)
        for i in 0..<count {
            values[i] = raw.i64(8 * i)
        }
        return values
    }
}
