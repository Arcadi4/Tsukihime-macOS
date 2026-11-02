import Foundation
import TsukiCore

/// One segment of a decoded script: the bytes the interpreter scans per statement.
public struct ScriptSegment: Sendable {
    /// Offset of the first byte (just after the previous `;`).
    public let start: Int
    /// Offset just after the terminating `;`, or after 0x300 bytes, or the script end.
    public let end: Int
    /// Offset of the first `_` when the four name bytes after it lie inside the segment, else -1.
    public let underscore: Int
    /// True when the first name byte is `A`..`Z`: the engine dispatches on the name.
    public let isCommand: Bool
    /// True when the segment is not `;`-terminated although the script goes on. Never true in retail data.
    public let truncated: Bool

    public init(start: Int, end: Int, underscore: Int, isCommand: Bool, truncated: Bool) {
        self.start = start
        self.end = end
        self.underscore = underscore
        self.isCommand = isCommand
        self.truncated = truncated
    }

    public var length: Int { end - start }
    public var hasName: Bool { underscore >= 0 }
    /// Offset of the first name byte (just after the `_`).
    public var nameStart: Int { underscore + 1 }
    /// Offset of the byte after the four name bytes (the separator, normally `(`).
    public var argsStart: Int { underscore + 5 }
}

/// The tokenizer of the main interpreter (ScriptStep, eboot text VA 0x95E60; docs/formats/script.md 3.1):
/// cuts a decoded script into segments and finds each segment's command name.
public enum ScriptSegmenter {
    public static let maxSegmentBytes = Statement.maxSegmentBytes

    private static let semicolon: UInt8 = UInt8(ascii: ";")
    private static let underscoreChar: UInt8 = UInt8(ascii: "_")

    /// Reads the segment that starts at `start`, which must lie inside the script.
    public static func read(_ script: ByteSpan, _ start: Int) throws -> ScriptSegment {
        guard start >= 0 && start < script.count else {
            throw TsukiError.bounds("the segment start must lie inside the script")
        }

        let n = script.count
        let limit = n - start > maxSegmentBytes ? start + maxSegmentBytes : n
        var semi = -1
        for i in start..<limit where script[i] == semicolon {
            semi = i
            break
        }

        let end: Int
        var truncated = false
        if semi >= 0 {
            end = semi + 1
        } else {
            end = limit
            truncated = limit < n
        }

        var us = -1
        for i in start..<end where script[i] == underscoreChar {
            us = i
            break
        }
        if us < 0 || us + 5 > end {
            return ScriptSegment(start: start, end: end, underscore: -1, isCommand: false, truncated: truncated)
        }

        let first = script[us + 1]
        return ScriptSegment(start: start, end: end, underscore: us,
                             isCommand: first >= UInt8(ascii: "A") && first <= UInt8(ascii: "Z"),
                             truncated: truncated)
    }

    /// The start offset of every segment, ascending (the first one is 0).
    public static func segmentStarts(_ script: ByteSpan) -> [Int] {
        var starts: [Int] = []
        starts.reserveCapacity(max(4, script.count / 18))
        var pos = 0
        while pos < script.count {
            starts.append(pos)
            guard let segment = try? read(script, pos) else { break }
            pos = segment.end
        }
        return starts
    }

    public static func countSegments(_ script: ByteSpan) -> Int {
        var count = 0
        var pos = 0
        while pos < script.count {
            count += 1
            guard let segment = try? read(script, pos) else { break }
            pos = segment.end
        }
        return count
    }

    /// Builds the `ScriptImage` that the data layer returns: decoded bytes plus segment starts.
    public static func createImage(_ index: Int, _ script: [UInt8]) -> ScriptImage {
        ScriptImage(index: index, bytes: script, segmentStarts: segmentStarts(ByteSpan(script)))
    }

    /// Turns a command segment into the statement the host dispatches. Nil for a skipped segment.
    public static func statement(_ scriptIndex: Int, _ script: ByteSpan, _ segment: ScriptSegment) -> Statement? {
        guard segment.isCommand else { return nil }
        guard let name = try? CommandName.fromBytes(script.slice(segment.nameStart, 4)) else { return nil }
        return Statement(script: scriptIndex, offset: segment.start, end: segment.end, name: name,
                         args: script.slice(segment.argsStart, segment.end - segment.argsStart))
    }

    /// Decodes the block and sub id of a `_Z...` marker the way the engine does. False when the name does
    /// not start with `Z` or fewer than five bytes remain.
    public static func readMarkerId(_ script: ByteSpan, _ segment: ScriptSegment) -> (block: Int, sub: Int)? {
        guard segment.isCommand, script[segment.nameStart] == UInt8(ascii: "Z") else { return nil }
        let at = segment.underscore + 3
        guard script.count - at >= 5 else { return nil }
        return (MarkerId.hex(script.slice(at, 3)), MarkerId.hex(script.slice(at + 3, 2)))
    }
}

/// Marker ids `_Z<k><bbb><ss>` (docs/formats/script.md 3.7).
public enum MarkerId {
    /// Marker id digits as the Z handler decodes them (VA 0x9665A..0x966E3). Only lower-case hex decodes
    /// correctly: "00A" gives 0x11, not 10.
    public static func hex(_ chars: ByteSpan) -> Int {
        var v: Int32 = 0
        for c in chars {
            v = v &* 16 &+ (c < 0x61 ? Int32(c) - 0x30 : Int32(c) - 0x57)
        }
        return Int(Int16(truncatingIfNeeded: v))
    }
}
