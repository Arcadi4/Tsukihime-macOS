import Foundation
import TsukiCore

/// Argument reader 1: the inline integer readers of the PS4 interpreter (text VA 0x76690 for 16 bits,
/// 0x76780 for 32 bits, 0x76860 for "present"; docs/formats/script.md 3.3).
///
/// The readers work on raw statement bytes and a start offset `p0`, the byte after the separator that
/// follows the four name bytes (for a `Statement` that is `args[1]`). Argument `index` is reached by
/// skipping `index` commas (at most 500 bytes each); a `)` or `;` on the way means the argument is
/// missing (-1 / not present). A leading backtick then skips 5 bytes blindly (a keyword tag), and at
/// most 16 bytes are read: digits accumulate a decimal number, `+` and `-` close the current term and
/// set the sign of the next one, `,` `)` `;` end the value, every other byte is ignored. So `()` index 0
/// is 0, `(5)` index 1 is -1, `242.25` is 24225 and `258-18` is 240.
public enum InlineReader {
    /// Offset in `Statement.args` of the first argument byte: the byte after the separator.
    public static let startInArgs = 1

    private static let maxTermBytes = 16
    private static let maxSkipBytes = 500

    /// Reads argument `index` as a signed integer of `bits` (16 or 32) bits; -1 when the argument does
    /// not exist. `index` is the engine's i16, so at most 32767.
    public static func readInt(_ buf: ByteSpan, _ p0: Int, _ index: Int, bits: Int = 16) -> Int {
        precondition(bits == 16 || bits == 32, "the inline readers exist for 16 and 32 bits")
        guard let p = skip(buf, p0, index) else { return -1 }
        let v = readValue(buf, p)
        return bits == 16 ? Int(Int16(truncatingIfNeeded: v)) : Int(Int32(truncatingIfNeeded: v))
    }

    public static func readInt16(_ buf: ByteSpan, _ p0: Int, _ index: Int) -> Int {
        readInt(buf, p0, index, bits: 16)
    }

    public static func readInt32(_ buf: ByteSpan, _ p0: Int, _ index: Int) -> Int {
        readInt(buf, p0, index, bits: 32)
    }

    /// VA 0x76860: argument `index` exists and its first byte (after an optional tag) is not `,`, `)`
    /// or `;`.
    public static func isPresent(_ buf: ByteSpan, _ p0: Int, _ index: Int) -> Bool {
        guard var p = skip(buf, p0, index) else { return false }
        if p < buf.count && buf[p] == UInt8(ascii: "`") { p += 5 }
        let c = at(buf, p)
        return c != UInt8(ascii: ")") && c != UInt8(ascii: ",") && c != UInt8(ascii: ";")
    }

    public static func readInt16(_ statement: Statement, _ index: Int) -> Int {
        readInt(statement.args, startInArgs, index, bits: 16)
    }

    public static func readInt32(_ statement: Statement, _ index: Int) -> Int {
        readInt(statement.args, startInArgs, index, bits: 32)
    }

    public static func isPresent(_ statement: Statement, _ index: Int) -> Bool {
        isPresent(statement.args, startInArgs, index)
    }

    /// Value of a single argument text under the inline reader, e.g. "258-18" is 240.
    public static func readText(_ raw: ByteSpan, bits: Int = 16) -> Int {
        var tmp = [UInt8](raw)
        tmp.append(UInt8(ascii: ")"))
        return readInt(ByteSpan(tmp), 0, 0, bits: bits)
    }

    private static func at(_ buf: ByteSpan, _ i: Int) -> UInt8 {
        i >= 0 && i < buf.count ? buf[i] : 0
    }

    /// The skip loop shared by the three routines: position of argument `index`, or nil when missing.
    private static func skip(_ buf: ByteSpan, _ p: Int, _ index: Int) -> Int? {
        precondition(index <= Int(Int16.max), "the engine's argument index is an i16")
        var p = p
        for _ in 0..<index {
            var found = false
            for k in 0..<maxSkipBytes {
                let c = at(buf, p + k)
                if c == UInt8(ascii: ")") || c == UInt8(ascii: ";") { return nil }
                if c == UInt8(ascii: ",") {
                    p += k + 1
                    found = true
                    break
                }
            }
            if !found { p += maxSkipBytes }
        }
        return p
    }

    /// The value loop of VA 0x76690 / 0x76780 starting at `buf[p]`; at most 16 bytes are read.
    private static func readValue(_ buf: ByteSpan, _ start: Int) -> Int64 {
        var p = start
        if p < buf.count && buf[p] == UInt8(ascii: "`") { p += 5 }

        var total: Int64 = 0
        var num: Int64 = 0
        var sign: Int64 = 1
        for i in 0..<maxTermBytes {
            let c = at(buf, p + i)
            if c == UInt8(ascii: ")") || c == UInt8(ascii: ",") || c == UInt8(ascii: ";") { break }
            if c == UInt8(ascii: "+") {
                total += sign * num
                num = 0
                sign = 1
            } else if c == UInt8(ascii: "-") {
                total += sign * num
                num = 0
                sign = -1
            } else if c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9") {
                num = num * 10 + Int64(c - UInt8(ascii: "0"))
            }
        }
        return total + sign * num
    }
}
