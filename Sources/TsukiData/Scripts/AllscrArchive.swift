import Foundation
import TsukiCore
import TsukiEngine

/// One record of a label table (docs/formats/script.md 2.4).
public struct ScriptLabel: Equatable, Sendable {
    /// The label name (the 21-byte field without its trailing spaces).
    public let name: String
    /// The block id of the `_ZZ` / `_ZY` marker that defines it.
    public let block: Int
    /// The byte offset of that marker in the decoded script.
    public let offset: Int

    public init(name: String, block: Int, offset: Int) {
        self.name = name
        self.block = block
        self.offset = offset
    }
}

/// `image/allscr.mrg`: a standalone mrgd00 container of 552 sections (docs/formats/script.md 2):
/// section 0 the NAM32 script names, section 1 a nested container with one label table per script,
/// section 2 an unreferenced picture, and sections 3.. the scripts (MZX0, then XOR 0xFF). The names
/// and the label tables (a few hundred KB) are read when the file is opened; a script is read and
/// decoded on request, so no more than one script has to be resident.
public final class AllscrArchive {
    /// The first script section: script k is section k + 3 (VA 0x7917A).
    public static let scriptSectionBase = 3

    /// Bytes of a label record.
    public static let labelRecordSize = LabelTable.recordSize

    /// The archive this type opens by default.
    public static let defaultPath = "image/allscr.mrg"

    private let readSection: (Int) throws -> [UInt8]
    private let labelContainer: MzpContainer

    /// The script names, by script index (section 0).
    public let names: [String]

    /// The parsed name table (section 0).
    public let nameTable: NamTable

    private init(readSection: @escaping (Int) throws -> [UInt8], nameTable: NamTable, labels: MzpContainer) {
        self.readSection = readSection
        self.nameTable = nameTable
        self.labelContainer = labels
        self.names = nameTable.names
    }

    /// Number of scripts (549 in the retail data).
    public var count: Int { names.count }

    /// Opens `image/allscr.mrg` of a game folder view.
    public static func open(_ files: GameFiles, path: String = defaultPath) throws -> AllscrArchive {
        let length = try files.length(of: path)
        let top = ByteSpan(try files.readRange(path, offset: 0, count: min(length, 8)))
        guard Mzp.isContainer(top) else {
            throw TsukiError.format("\(path): not an mrgd00 container")
        }

        let tableBytes = 8 + (8 * Int(top.u16(6)))
        let head = ByteSpan(try files.readRange(path, offset: 0, count: min(length, tableBytes)))
        let sections = try MzpContainer.readTable(head, totalLength: length)
        return try create(sections: sections) { i in
            try files.readRange(path, offset: sections[i].offset, count: sections[i].size)
        }
    }

    /// Opens a container that is already in memory.
    public static func fromMemory(_ file: ByteSpan) throws -> AllscrArchive {
        let container = try MzpContainer.parse(file)
        return try create(sections: container.sections) { container.section($0).toArray() }
    }

    /// The decoded script k: the MZX0 stream of section k + 3 decoded and XORed with 0xFF
    /// (docs/formats/script.md 2.2).
    public func scriptBytes(_ k: Int) throws -> ByteSpan {
        try checkIndex(k)
        let stream = ByteSpan(try readSection(k + Self.scriptSectionBase))
        let size = try Mzx.declaredSize(stream)
        var output = [UInt8](repeating: 0, count: Mzx.bufferSize(size))
        _ = try Mzx.decode(stream, into: &output, invert: true)
        return ByteSpan(output, offset: 0, count: size)
    }

    /// The decoded script k with its segment offsets.
    public func script(_ k: Int) throws -> ScriptImage {
        ScriptSegmenter.createImage(k, try scriptBytes(k).toArray())
    }

    /// The raw records of the label table of script k (a multiple of 32 bytes, no header, no
    /// terminator).
    public func labelRecords(_ k: Int) throws -> ByteSpan {
        try checkIndex(k)
        return labelContainer.section(k)
    }

    /// The label table of script k as the engine's lookup (VA 0x794D0) sees it.
    public func labelLookup(_ k: Int) throws -> LabelTable {
        LabelTable(records: try labelRecords(k).toArray())
    }

    /// The labels of script k, parsed and checked.
    public func labels(_ k: Int) throws -> [ScriptLabel] {
        try Self.parseLabels(try labelRecords(k))
    }

    /// Parses a label table: 32-byte records `name(21, space padded) block(3 hex) , offset(5 hex) CR LF`.
    public static func parseLabels(_ data: ByteSpan) throws -> [ScriptLabel] {
        guard data.count % labelRecordSize == 0 else {
            throw TsukiError.format("label table size \(data.count) is not a multiple of \(labelRecordSize)")
        }

        var labels: [ScriptLabel] = []
        labels.reserveCapacity(data.count / labelRecordSize)
        var offset = 0
        while offset < data.count {
            let record = data.slice(offset, labelRecordSize)
            if record[24] != 0x2C || record[30] != 0x0D || record[31] != 0x0A {
                throw TsukiError.format("bad label record \(offset / labelRecordSize): \(hexLower(record))")
            }
            let index = offset / labelRecordSize
            labels.append(ScriptLabel(
                name: try asciiName(record.slice(0, 21)),
                block: try parseHex(record.slice(21, 3), index),
                offset: try parseHex(record.slice(25, 5), index)
            ))
            offset += labelRecordSize
        }
        return labels
    }

    private static func create(sections: [MzpSection], readSection: @escaping (Int) throws -> [UInt8]) throws -> AllscrArchive {
        guard sections.count >= scriptSectionBase else {
            throw TsukiError.format("allscr.mrg has \(sections.count) sections; names, label tables and scripts need at least \(scriptSectionBase)")
        }

        let names = try NamTable.parseNam32(ByteSpan(try readSection(0)))
        let labels = try MzpContainer.parse(ByteSpan(try readSection(1)))
        guard names.count + scriptSectionBase == sections.count, labels.count == names.count else {
            throw TsukiError.format(
                "allscr.mrg layout: \(names.count) names, \(labels.count) label tables and \(sections.count - scriptSectionBase) scripts do not line up")
        }
        return AllscrArchive(readSection: readSection, nameTable: names, labels: labels)
    }

    private static func asciiName(_ field: ByteSpan) throws -> String {
        var chars: [Character] = []
        chars.reserveCapacity(field.count)
        for byte in field {
            guard byte < 0x80 else {
                throw TsukiError.format("non-ASCII byte 0x\(hexLower([byte])) in a label name")
            }
            chars.append(Character(UnicodeScalar(byte)))
        }
        while chars.last == " " { chars.removeLast() }
        return String(chars)
    }

    private static func parseHex(_ digits: ByteSpan, _ record: Int) throws -> Int {
        var value = 0
        for byte in digits {
            let digit: Int
            switch byte {
            case 0x30...0x39: digit = Int(byte) - 0x30
            case 0x61...0x66: digit = Int(byte) - 0x61 + 10
            case 0x41...0x46: digit = Int(byte) - 0x41 + 10
            default:
                throw TsukiError.format("bad hex digit 0x\(hexLower([byte])) in label record \(record)")
            }
            value = (value * 16) + digit
        }
        return value
    }

    private func checkIndex(_ k: Int) throws {
        guard k >= 0 && k < count else {
            throw TsukiError.bounds("script index out of range 0..\(count - 1)")
        }
    }
}
