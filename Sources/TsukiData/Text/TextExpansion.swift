import Foundation
import TsukiCore
import TsukiEngine

/// The `$NNNNNN` expansion of a script message (engine routine VA 0x76040, docs/formats/text.md
/// 5.3).
public enum TextExpansion {
    /// Returns the engine's line for an id (the bytes `TextTable.engineLine` gives).
    public typealias LineFetch = (Int) throws -> ByteSpan

    /// Expands the references of `message` against `table` with the engine's cap of
    /// `TextRules.engineExpandMax` bytes.
    /// - Parameters:
    ///   - message: The raw message bytes (the argument of a text command, markup intact).
    ///   - table: The language table the references are read from.
    ///   - srcLen: The source length passed to the routine; nil is the whole message, 0 or less gives an empty result.
    ///   - expand: False is the engine's mode 0: a plain copy of `srcLen` bytes up to the first NUL.
    public static func expand(_ message: ByteSpan, table: TextTable, srcLen: Int? = nil,
                              expand: Bool = true) throws -> [UInt8] {
        try Self.expand(message, fetch: { try table.engineLine($0) },
                   limit: TextRules.engineExpandMax, srcLen: srcLen, expand: expand)
    }

    /// The routine with a caller-supplied line source and output cap. A `$` takes the 6 bytes after
    /// it as decimal digits *without checking them* (`id = sum((b - 0x30) * 10^k)`) and skips 7 bytes;
    /// a negative id inserts nothing, otherwise the line is appended, cut to the room left under
    /// `limit`; any other byte is copied. The loop stops when the output reaches `limit`, after
    /// copying a NUL, or when the source length is reached. Bytes past the end of the message read as
    /// NUL (the engine reads whatever follows in its buffer). The result ends at its first NUL.
    public static func expand(_ message: ByteSpan, fetch: LineFetch, limit: Int = TextRules.engineExpandMax,
                              srcLen: Int? = nil, expand: Bool = true) throws -> [UInt8] {
        let n = srcLen ?? message.count
        if !expand {
            let take = clamp(n, 0, message.count)
            let copy = take > 0 ? message.slice(0, take) : ByteSpan()
            if let nul = copy.firstIndex(of: 0) {
                return copy.slice(0, nul).toArray()
            }
            return copy.toArray()
        }

        if n <= 0 {
            return []
        }

        var output: [UInt8] = []
        output.reserveCapacity(max(0, min(limit, 0x400)))
        var i = 0
        while true {
            let c = at(message, i)
            if c == 0x24 {
                var value: Int64 = 0
                for k in 1...6 {
                    value = (value * 10) + Int64(at(message, i + k))
                }
                value -= 0x30 * 111_111
                i += 6
                if value >= 0 {
                    let line = try fetch(Int(value))
                    let room = max(limit - output.count, 0)
                    output.append(contentsOf: line.prefix(min(room, line.count)))
                }
            } else {
                output.append(c)
            }

            if output.count >= limit || c == 0 {
                break
            }

            i += 1
            if i >= n {
                break
            }
        }

        if let nul = output.firstIndex(of: 0) {
            output.removeSubrange(nul..<output.count)
        }
        return output
    }

    private static func at(_ message: ByteSpan, _ index: Int) -> UInt8 {
        index >= 0 && index < message.count ? message[index] : 0
    }
}
