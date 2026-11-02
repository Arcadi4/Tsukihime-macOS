import Foundation
import TsukiCore

/// The textual view of a statement's arguments: the arguments cut at `,` until the first `)` or `;`,
/// the bytes between `)` and `;` (ignored by the engine), and the keyword tags.
public enum ArgumentList {
    /// Offset in `Statement.args` of the first argument of an ordinary command.
    public static let commandStartInArgs = 1

    /// Offset in `Statement.args` of the first argument of a `Z` marker: `_ZMbbbss(` is nine
    /// characters long, so the arguments start four bytes after the separator position.
    public static let markerStartInArgs = 4

    /// Where the textual arguments of `statement` start inside `args`.
    public static func startIn(_ statement: Statement) -> Int {
        let start = statement.name.first == UInt8(ascii: "Z") ? markerStartInArgs : commandStartInArgs
        return min(start, statement.args.count)
    }

    /// Splits `data[start...]` at `,` until a `)` or `;` (or the end). `()` gives no arguments;
    /// `(,)` gives two empty ones. Returns the index of the terminator (or `data.count`).
    public static func split(_ data: ByteSpan, _ start: Int, into ranges: inout [ArgRange]) -> Int {
        var cur = start
        var i = start
        var added = 0
        while i < data.count {
            let c = data[i]
            if c == UInt8(ascii: ",") {
                ranges.append(ArgRange(start: cur, end: i))
                added += 1
                cur = i + 1
            } else if c == UInt8(ascii: ")") || c == UInt8(ascii: ";") {
                break
            }
            i += 1
        }
        if added > 0 || i > cur {
            ranges.append(ArgRange(start: cur, end: i))
        }
        return i
    }

    /// The bytes after the first `)` up to the terminating `;`, which the engine ignores.
    public static func trailer(_ data: ByteSpan, _ close: Int) -> ByteSpan {
        guard close < data.count, data[close] == UInt8(ascii: ")") else { return ByteSpan([]) }
        let stop = data.count > 0 && data[data.count - 1] == UInt8(ascii: ";") ? data.count - 1 : data.count
        return close + 1 <= stop ? data.slice(close + 1, stop - close - 1) : ByteSpan([])
    }

    /// The keyword tag `` `NNN: `` (backtick, three decimal digits, colon) at the start of an argument.
    public static func tag(_ arg: ByteSpan) -> Int? {
        guard arg.count >= 5, arg[0] == UInt8(ascii: "`"),
              isDigit(arg[1]), isDigit(arg[2]), isDigit(arg[3]), arg[4] == UInt8(ascii: ":") else {
            return nil
        }
        return Int(arg[1] - UInt8(ascii: "0")) * 100
            + Int(arg[2] - UInt8(ascii: "0")) * 10
            + Int(arg[3] - UInt8(ascii: "0"))
    }

    /// The argument without its tag: the first five bytes are dropped when it starts with a backtick.
    public static func untagged(_ arg: ByteSpan) -> ByteSpan {
        guard arg.count > 0 && arg[0] == UInt8(ascii: "`") else { return arg }
        return arg.count >= 5 ? arg.slice(5, arg.count - 5) : ByteSpan([])
    }

    private static func isDigit(_ b: UInt8) -> Bool {
        b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9")
    }
}
