import Foundation
import TsukiCore
import TsukiEngine

/// The two HED record layouts.
public enum HedFormat: String, Equatable {
    /// 8-byte records with an exact size (allpac*, parts, bgm, vse, vag).
    case hed8
    /// 4-byte records, sector-rounded size only (voice, voice2).
    case hed4

    public var recordSize: Int { self == .hed8 ? 8 : 4 }
}

/// One decoded HED record.
public struct HedEntry: Equatable {
    public let index: Int
    /// The record bytes as stored (8 bytes for HED8, the low 4 for HED4).
    public let rawRecord: UInt64
    /// The 20 stored bits of the sector offset.
    public let storedOffset: Int
    /// The stored 20 bits plus the bank.
    public let sectorOffset: Int
    /// Sectors the entry occupies.
    public let sizeSectors: Int
    /// Low 16 bits of the exact size (HED8 only; -1 for HED4).
    public let sizeLow: Int

    public var sizeExact: Bool { sizeLow >= 0 }
    public var offset: Int { sectorOffset * Mzp.sector }
    public var span: Int { sizeSectors * Mzp.sector }
    public var size: Int { sizeExact ? Mzp.decodeSize(sectors: sizeSectors, low: sizeLow) : span }

    public var rawHex: String {
        var writer = ByteWriter()
        writer.u64(rawRecord)
        return hexLower(writer.bytes[0..<8])
    }
}

/// A parsed .hed file.
public struct HedTable {
    public static let maxBankSwitches = 11
    private static let offsetBits = 20

    public let format: HedFormat
    public let entries: [HedEntry]
    /// The run of all-0xFF records after the last entry.
    public let terminator: ByteSpan
    /// Anything after the terminator.
    public let trailing: ByteSpan
    /// True when every entry starts where the previous one ended.
    public let contiguous: Bool
    /// Entry indexes at which bank 1, 2, ... start.
    public let bankStarts: [Int]

    public var count: Int { entries.count }

    /// HED8 when the size is a multiple of 8 and bits 16...27 of the first u32 of every record
    /// before the first all-0xFF record are zero, else HED4.
    public static func detect(_ data: ByteSpan) throws -> HedFormat {
        if data.count % 8 == 0 {
            var ok = true
            var offset = 0
            while offset < data.count {
                let record = data.slice(offset, 8)
                if isAllFF(record) { break }
                if record.u32(0) & 0x0FFF_0000 != 0 {
                    ok = false
                    break
                }
                offset += 8
            }
            if ok { return .hed8 }
        }
        if data.count % 4 == 0 { return .hed4 }
        throw TsukiError.format("HED size \(data.count) matches no known layout")
    }

    public static func parse(_ data: ByteSpan, format: HedFormat? = nil) throws -> HedTable {
        let layout = try format ?? detect(data)
        let recordSize = layout.recordSize
        guard data.count % recordSize == 0 else {
            throw TsukiError.format("HED size \(data.count) is not a multiple of \(recordSize)")
        }

        var entries: [HedEntry] = []
        entries.reserveCapacity(data.count / recordSize)
        var bankStarts: [Int] = []
        var terminatorOffset = data.count
        var previousEnd = 0
        var contiguous = true
        var bank = 0
        var previousNibbleNonZero = false

        var offset = 0
        var index = 0
        while offset < data.count {
            let record = data.slice(offset, recordSize)
            if isAllFF(record) {
                terminatorOffset = offset
                break
            }

            let stored: Int
            let sizeSectors: Int
            let sizeLow: Int
            let raw: UInt64
            if layout == .hed8 {
                let field = record.u32(0)
                sizeSectors = Int(record.u16(4))
                sizeLow = Int(record.u16(6))
                raw = record.u64(0)
                guard field & 0x0FFF_0000 == 0 else {
                    throw TsukiError.format("HED8 record \(index): reserved offset bits set (0x\(String(field, radix: 16)))")
                }
                stored = Int(field & 0xFFFF) | (Int(field >> 28) << 16)
            } else {
                let low16 = Int(record.u16(0))
                let packed = Int(record.u16(2))
                raw = UInt64(record.u32(0))
                stored = low16 | ((packed >> 12) << 16)
                sizeSectors = packed & 0x0FFF
                sizeLow = -1
            }

            if stored >> 16 != 0 {
                previousNibbleNonZero = true
            } else {
                if previousNibbleNonZero {
                    bank += 1
                    bankStarts.append(index)
                }
                previousNibbleNonZero = false
            }

            let full = stored | (bank << offsetBits)
            if full != previousEnd { contiguous = false }
            entries.append(HedEntry(index: index, rawRecord: raw, storedOffset: stored,
                                    sectorOffset: full, sizeSectors: sizeSectors, sizeLow: sizeLow))
            previousEnd = full + sizeSectors
            offset += recordSize
            index += 1
        }

        guard bank <= maxBankSwitches else {
            throw TsukiError.format("\(bank) bank switches; the engine supports at most \(maxBankSwitches)")
        }

        let tail = data.suffix(from: terminatorOffset)
        var terminatorLength = 0
        while terminatorLength + recordSize <= tail.count,
              isAllFF(tail.slice(terminatorLength, recordSize)) {
            terminatorLength += recordSize
        }

        return HedTable(
            format: layout,
            entries: entries,
            terminator: tail.slice(0, terminatorLength),
            trailing: tail.suffix(from: terminatorLength),
            contiguous: contiguous,
            bankStarts: bankStarts
        )
    }

    private static func isAllFF(_ record: ByteSpan) -> Bool {
        record.allSatisfy { $0 == 0xFF }
    }
}

/// A name table: NAM32 (allpac*.nam, allscr.mrg section 0, se_nam.mrg sections) or NAM8
/// (voice.nam, voice2.nam). Record i names entry i.
public struct NamTable {
    public let recordSize: Int
    public let names: [String]
    /// The optional 2-character tag at bytes 28..29 of a NAM32 record; "" when absent.
    public let tags: [String]
    /// True when an all-zero record ended the table.
    public let terminator: Bool
    public let trailing: ByteSpan

    public var count: Int { names.count }
    public subscript(index: Int) -> String { names[index] }

    public static func looksLikeNam32(_ data: ByteSpan) -> Bool {
        guard !data.isEmpty, data.count % 32 == 0 else { return false }
        var offset = 0
        while offset < data.count {
            let record = data.slice(offset, 32)
            if record[30] == 0x0D && record[31] == 0x0A {
                offset += 32
                continue
            }
            if offset == data.count - 32 && isAllZero(record) {
                offset += 32
                continue
            }
            return false
        }
        return true
    }

    public static func parse(_ data: ByteSpan) throws -> NamTable {
        looksLikeNam32(data) ? try parseNam32(data) : try parseNam8(data)
    }

    public static func parseNam32(_ data: ByteSpan) throws -> NamTable {
        guard data.count % 32 == 0 else {
            throw TsukiError.format("NAM32 size \(data.count) is not a multiple of 32")
        }
        var names: [String] = []
        var tags: [String] = []
        var terminator = false
        var trailing = ByteSpan()
        var offset = 0
        while offset < data.count {
            let record = data.slice(offset, 32)
            if isAllZero(record) {
                terminator = true
                trailing = data.suffix(from: offset + 32)
                break
            }
            guard record[30] == 0x0D && record[31] == 0x0A else {
                throw TsukiError.format("NAM32 record at 0x\(String(offset, radix: 16)) does not end with CRLF")
            }
            let body = record.slice(0, 30)
            var nul: Int? = nil
            for i in 0..<30 where body[i] == 0 { nul = i; break }
            let nameEnd = nul ?? 30
            let name = try decodeAscii(body.slice(0, nameEnd))

            var tag = ""
            if let nul, nul <= 28, body.slice(nul, 28 - nul).allSatisfy({ $0 == 0 }),
               !body.slice(28, 2).allSatisfy({ $0 == 0 }) {
                tag = try decodeAscii(body.slice(28, 2))
            }
            names.append(name)
            tags.append(tag)
            offset += 32
        }
        return NamTable(recordSize: 32, names: names, tags: tags, terminator: terminator, trailing: trailing)
    }

    public static func parseNam8(_ data: ByteSpan) throws -> NamTable {
        let full = data.count / 8 * 8
        var names: [String] = []
        names.reserveCapacity(full / 8)
        var terminator = false
        var trailing = data.suffix(from: full)
        var offset = 0
        while offset < full {
            let record = data.slice(offset, 8)
            if isAllZero(record) {
                terminator = true
                trailing = data.suffix(from: offset)
                break
            }
            var nul = 8
            for i in 0..<8 where record[i] == 0 { nul = i; break }
            names.append(try decodeAscii(record.slice(0, nul)))
            offset += 8
        }
        return NamTable(recordSize: 8, names: names, tags: Array(repeating: "", count: names.count),
                        terminator: terminator, trailing: trailing)
    }

    private static func isAllZero(_ span: ByteSpan) -> Bool {
        span.allSatisfy { $0 == 0 }
    }

    private static func decodeAscii(_ bytes: ByteSpan) throws -> String {
        guard bytes.allSatisfy({ $0 < 0x80 }) else {
            throw TsukiError.format("non-ASCII name bytes in a name table")
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

/// One entry of a HED/NAM/MRG triplet.
public struct MrgEntry: Equatable {
    public let index: Int
    public let name: String?
    public let offset: Int
    public let size: Int
    public let sizeExact: Bool
    public let sectorOffset: Int
    public let sizeSectors: Int
    public let sizeLow: Int
    public let hedRaw: String

    public var end: Int { offset + size }
    /// Bytes the entry occupies in the .mrg, padding included.
    public var span: Int { sizeSectors * Mzp.sector }
}

/// The entry table and names of a HED/NAM/MRG triplet, without the data file.
public final class ArchiveIndex {
    public let name: String
    public let hed: HedTable
    public let nam: NamTable?
    public let mrgLength: Int
    public let entries: [MrgEntry]
    private let nameIndex: NameIndex

    public var count: Int { entries.count }
    public var format: HedFormat { hed.format }
    public var namesAligned: Bool { nam.map { $0.count == entries.count } ?? false }

    private init(name: String, hed: HedTable, nam: NamTable?, mrgLength: Int, entries: [MrgEntry]) {
        self.name = name
        self.hed = hed
        self.nam = nam
        self.mrgLength = mrgLength
        self.entries = entries
        var index = NameIndex()
        for entry in entries {
            if let entryName = entry.name {
                index.add(entryName, index: entry.index)
            }
        }
        self.nameIndex = index
    }

    public static func load(_ files: GameFiles, base: String, format: HedFormat? = nil) throws -> ArchiveIndex {
        let name = (base as NSString).lastPathComponent
        let hedBytes = try files.readAll(base + ".hed")
        let nam: NamTable? = files.exists(base + ".nam") ? try NamTable.parse(try files.readAll(base + ".nam")) : nil
        let mrgLength = try files.length(of: base + ".mrg")
        return try create(name: name, hed: hedBytes, nam: nam, mrgLength: mrgLength, format: format)
    }

    public static func create(name: String, hed hedBytes: ByteSpan, nam: NamTable?, mrgLength: Int, format: HedFormat? = nil) throws -> ArchiveIndex {
        let table = try HedTable.parse(hedBytes, format: format)
        var entries: [MrgEntry] = []
        entries.reserveCapacity(table.entries.count)
        for record in table.entries {
            let entryName = nam.flatMap { record.index < $0.count ? $0[record.index] : nil }
            entries.append(MrgEntry(
                index: record.index,
                name: entryName,
                offset: record.offset,
                size: record.size,
                sizeExact: record.sizeExact,
                sectorOffset: record.sectorOffset,
                sizeSectors: record.sizeSectors,
                sizeLow: record.sizeLow,
                hedRaw: record.rawHex
            ))
        }
        return ArchiveIndex(name: name, hed: table, nam: nam, mrgLength: mrgLength, entries: entries)
    }

    public func find(_ name: String) -> Int? {
        nameIndex.find(name)
    }

    /// Structural checks; empty for every retail archive.
    public func validate() -> [String] {
        var issues: [String] = []
        var previousEnd = 0
        for entry in entries {
            if entry.offset + entry.span > mrgLength {
                issues.append("entry \(entry.index): extent 0x\(String(entry.offset, radix: 16))+0x\(String(entry.span, radix: 16)) beyond file size")
            }
            if entry.sectorOffset != previousEnd {
                issues.append("entry \(entry.index): sector \(entry.sectorOffset) != previous end \(previousEnd)")
            }
            if entry.sizeExact && !(entry.span - Mzp.sector < entry.size && entry.size <= entry.span) {
                issues.append("entry \(entry.index): exact size 0x\(String(entry.size, radix: 16)) inconsistent with \(entry.sizeSectors) sectors")
            }
            previousEnd = entry.sectorOffset + entry.sizeSectors
        }
        if previousEnd * Mzp.sector != mrgLength {
            issues.append("last entry ends at 0x\(String(previousEnd * Mzp.sector, radix: 16)), file size 0x\(String(mrgLength, radix: 16))")
        }
        if let nam, nam.count != entries.count {
            issues.append("NAM has \(nam.count) names for \(entries.count) entries")
        }
        return issues
    }
}

/// A HED/NAM/MRG triplet with its data file memory-mapped. Entries are zero-copy windows onto
/// the mapping, so reading one entry of a 24 GB archive touches only that entry's pages.
public final class Archive {
    public let index: ArchiveIndex
    private let file: MappedFile

    public var count: Int { index.count }
    public var entries: [MrgEntry] { index.entries }
    public var mappedLength: Int { file.length }

    private init(index: ArchiveIndex, file: MappedFile) {
        self.index = index
        self.file = file
    }

    public static func open(basePath: String, format: HedFormat? = nil) throws -> Archive {
        var path = basePath
        let ext = (path as NSString).pathExtension.lowercased()
        if ext == "hed" || ext == "mrg" || ext == "nam" {
            path = (path as NSString).deletingPathExtension
        }
        let directory = (path as NSString).deletingLastPathComponent
        let name = (path as NSString).lastPathComponent
        let files = DirectoryGameFiles(root: directory.isEmpty ? "." : directory)
        let index = try ArchiveIndex.load(files, base: name, format: format)
        guard let mrgPath = files.resolveFile(name + ".mrg") else {
            throw TsukiError.io("\(name).mrg not found in \(directory)")
        }
        return Archive(index: index, file: try MappedFile(path: mrgPath))
    }

    public static func open(index: ArchiveIndex, file: MappedFile) -> Archive {
        Archive(index: index, file: file)
    }

    public func find(_ name: String) -> Int? { index.find(name) }

    /// Exact bytes of entry `i` (HED4: the whole sector span), as a window onto the mapping.
    public func entry(_ i: Int) -> ByteSpan {
        let e = index.entries[i]
        return (try? file.span(offset: e.offset, length: e.size)) ?? ByteSpan()
    }

    /// The entry's whole sector span, packer padding included.
    public func sectorSpan(_ i: Int) -> ByteSpan {
        let e = index.entries[i]
        return (try? file.span(offset: e.offset, length: e.span)) ?? ByteSpan()
    }

    public func read(_ i: Int) -> [UInt8] { entry(i).toArray() }

    public func container(_ i: Int) throws -> MzpContainer {
        try MzpContainer.parse(entry(i))
    }

    public func dispose() {
        file.dispose()
    }

    public func trimResident(_ trim: (UnsafeMutableRawPointer, Int) -> Void) {
        file.trimResident(trim)
    }
}
