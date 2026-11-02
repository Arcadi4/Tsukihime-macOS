import Foundation
import TsukiCore

/// A half-open byte range `[start, end)` of one argument inside a buffer.
public struct ArgRange: Sendable, Equatable {
    public var start: Int
    public var end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }

    public var length: Int { end - start }

    public func slice(_ buf: ByteSpan) -> ByteSpan { buf.slice(start, end - start) }
}

/// How `ObjectParser.split` ended.
public enum SplitStatus: UInt8, Sendable {
    case ok = 0
    /// An argument has no `,` `)` or `;` after it: the engine's `strpbrk` would return NULL.
    case noTerminator = 1
    /// A quoted argument has no closing quote: the engine's `strchr` would run past the statement.
    case unterminatedQuote = 2
}

/// Argument reader 2: the object argument parser of the PS4 interpreter (text VA 0xD690 split, 0xD8C0
/// "has", 0xE310 / 0xE3C0 strtol getters; docs/formats/script.md 3.3a), used by the 52 commands of
/// `ObjectCommands`.
public enum ObjectParser {
    /// The parser keeps at most this many arguments (VA 0xD690).
    public static let maxArguments = 20

    /// Offset in `Statement.args` of the separator byte.
    public static let separatorInArgs = 0

    /// VA 0xD690: splits the argument list. `buf[sep]` is the separator byte after the four name bytes.
    /// `ranges` must have room for `maxArguments` entries. Returns the number of ranges in `count`.
    public static func split(_ buf: ByteSpan, _ sep: Int, into ranges: inout [ArgRange]) -> (SplitStatus, Int) {
        precondition(ranges.count >= maxArguments, "room for \(maxArguments) ranges is required")
        var count = 0
        if at(buf, sep + 1) == UInt8(ascii: ")") || at(buf, sep + 1) == UInt8(ascii: ";") {
            return (.ok, 0)
        }

        var q = sep + 1
        while true {
            let start: Int
            let e: Int
            if at(buf, q) == UInt8(ascii: "\"") {
                start = q + 1
                e = indexFrom(buf, start, [UInt8(ascii: "\"")])
                if e < 0 { return (.unterminatedQuote, count) }
            } else {
                start = q
                e = indexFrom(buf, start, [UInt8(ascii: ","), UInt8(ascii: ")"), UInt8(ascii: ";")])
                if e < 0 { return (.noTerminator, count) }
            }

            ranges[count] = ArgRange(start: start, end: e)
            count += 1
            let skip = at(buf, e) == UInt8(ascii: "\"") ? 1 : 0
            if at(buf, e + skip) == UInt8(ascii: ")") || at(buf, e + skip) == UInt8(ascii: ";")
                || count == maxArguments {
                return (.ok, count)
            }
            q = e + skip + 1
        }
    }

    /// Splits the arguments of a statement (the separator is `args[0]`).
    public static func split(_ statement: Statement, into ranges: inout [ArgRange]) -> (SplitStatus, Int) {
        split(statement.args, separatorInArgs, into: &ranges)
    }

    /// VA 0xD8C0: argument `i` exists and is not empty.
    public static func has(_ ranges: [ArgRange], _ count: Int, _ i: Int) -> Bool {
        i < count && ranges[i].end > ranges[i].start
    }

    /// VA 0xE310 / 0xE3C0: `strtol(arg, &end, 10)` on a copy of the argument (1..15 bytes). The value
    /// when the whole argument was consumed (leading white space and one sign are accepted), else nil.
    public static func strictInt(_ arg: ByteSpan) -> Int? {
        guard arg.count >= 1 && arg.count <= 15 else { return nil }
        guard let (consumed, value) = strtol(arg), consumed == arg.count else { return nil }
        return value
    }

    /// The value VA 0xE3C0 stores even when it reports failure: `strtol` of the leading part (0 when
    /// there is no number); nil when the argument is empty or longer than 15 bytes. Used by TOMP.
    public static func partialInt(_ arg: ByteSpan) -> Int? {
        guard arg.count >= 1 && arg.count <= 15 else { return nil }
        return strtol(arg)?.value ?? 0
    }

    /// `[ \t\n\v\f\r]*[+-]?[0-9]+` at the start of `s`. The magnitude saturates at `LONG_MAX`
    /// (`LONG_MAX + 1` for a minus sign) and the result keeps the low 32 bits.
    private static func strtol(_ s: ByteSpan) -> (consumed: Int, value: Int)? {
        var i = 0
        while i < s.count, s[i] == 0x20 || s[i] == 0x09 || s[i] == 0x0A || s[i] == 0x0B || s[i] == 0x0C || s[i] == 0x0D {
            i += 1
        }

        var negative = false
        if i < s.count && (s[i] == UInt8(ascii: "+") || s[i] == UInt8(ascii: "-")) {
            negative = s[i] == UInt8(ascii: "-")
            i += 1
        }

        let digits = i
        var magnitude: UInt64 = 0
        let cap: UInt64 = negative ? UInt64(Int64.max) + 1 : UInt64(Int64.max)
        while i < s.count, s[i] >= UInt8(ascii: "0"), s[i] <= UInt8(ascii: "9") {
            let d = UInt64(s[i] - UInt8(ascii: "0"))
            if magnitude <= (cap &- d) / 10 {
                magnitude = magnitude * 10 + d
            } else {
                magnitude = cap
            }
            i += 1
        }

        guard i != digits else { return nil }
        let signedValue: Int64 = negative ? (0 &- Int64(bitPattern: magnitude)) : Int64(bitPattern: magnitude)
        return (i, Int(Int32(truncatingIfNeeded: signedValue)))
    }

    private static func at(_ buf: ByteSpan, _ i: Int) -> UInt8 {
        i >= 0 && i < buf.count ? buf[i] : 0
    }

    /// Index of the first byte of `any` at or after `from`, or -1.
    private static func indexFrom(_ buf: ByteSpan, _ from: Int, _ any: [UInt8]) -> Int {
        guard from >= 0 && from < buf.count else { return -1 }
        for i in from..<buf.count where any.contains(buf[i]) {
            return i
        }
        return -1
    }
}
