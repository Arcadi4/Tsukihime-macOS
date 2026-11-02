import Foundation
import TsukiCore

/// The label table of one script (allscr section 1, child k; docs/formats/script.md 2.4): records of
/// exactly 32 ASCII bytes, `name` padded with spaces to 21 bytes, the 3 hex digits of the defining
/// marker's block id, `,`, the 5 hex digits of the marker's byte offset, `\r\n`.
public final class LabelTable {
    public static let recordSize = 32
    public static let maxRecords = 1000
    public static let maxName = 32

    private static let nameField = 21
    private static let offsetField = 25

    private let records: [UInt8]

    /// Wraps raw label records (a multiple of 32 bytes; the content is not validated, as in the engine).
    public init(records: [UInt8]) {
        precondition(records.count % Self.recordSize == 0,
                     "a label table is a multiple of \(Self.recordSize) bytes, not \(records.count)")
        self.records = records
    }

    public var count: Int { records.count / Self.recordSize }
    public var rawRecords: ByteSpan { ByteSpan(records) }

    /// Builds the 32-byte records of (name, block, offset) labels.
    public static func fromLabels(_ labels: [(name: String, block: Int, offset: Int)]) throws -> LabelTable {
        var bytes: [UInt8] = []
        for label in labels {
            guard label.name.utf8.count <= nameField, label.block >= 0, label.block <= 0xFFF,
                  label.offset >= 0, label.offset <= 0xFFFFF else {
                throw TsukiError.format("label \(label.name) (\(label.block), \(label.offset)) does not fit a record")
            }
            var name = label.name
            while name.utf8.count < nameField { name += " " }
            bytes.append(contentsOf: name.utf8)
            bytes.append(contentsOf: String(format: "%03x,%05x\r\n", label.block, label.offset).utf8)
        }
        return LabelTable(records: bytes)
    }

    /// The engine's lookup (VA 0x794D0): the wanted name is cut at NUL, TAB, LF, CR or `.` (at most 32
    /// bytes); the first of at most 1000 records whose name, compared up to its first byte <= 0x20,
    /// equals it gives the 5 hex digits at +25. Returns the byte offset, or -1 when no record matches.
    public func find(_ wanted: ByteSpan) -> Int {
        var n = 0
        while n < wanted.count && n < Self.maxName,
              wanted[n] != 0, wanted[n] != 0x09, wanted[n] != 0x0A, wanted[n] != 0x0D, wanted[n] != 0x2E {
            n += 1
        }
        let name = wanted.slice(0, n)
        let limit = min(count, Self.maxRecords)
        for r in 0..<limit {
            let base = r * Self.recordSize
            var len = 0
            while len < Self.nameField && records[base + len] > 0x20 { len += 1 }
            if ByteSpan(Array(records[base..<base + len])).elementsEqual(name) {
                return Self.parseOffset(ByteSpan(Array(records[base + Self.offsetField..<base + Self.offsetField + 5])))
            }
        }
        return -1
    }

    /// Looks up an ASCII name.
    public func find(_ name: String) -> Int {
        find(ByteSpan(Array(name.utf8)))
    }

    private static func parseOffset(_ hex: ByteSpan) -> Int {
        var v = 0
        for c in hex {
            v = (v * 16) + (c < UInt8(ascii: "a") ? Int(c) - Int(UInt8(ascii: "0"))
                               : Int(c) - Int(UInt8(ascii: "a")) + 10)
        }
        return v
    }
}
