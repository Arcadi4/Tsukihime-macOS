import Foundation
import TsukiCore
import TsukiEngine

/// The image archives by the engine's archive id (docs/formats/archives_ui_movies.md 2.1).
public enum ImageArchive: UInt8, CaseIterable, Sendable {
    /// allpac0: id 0, searched last.
    case allpac0 = 0
    /// allpac1: id 1.
    case allpac1 = 1
    /// allpac1_2: id 2, the continuation of allpac1.
    case allpac1_2 = 2
    /// allpac2: id 3, the 1/12.8 copies; never searched by name.
    case allpac2 = 3
    /// allpac3: id 4, UI sheets and rules.
    case allpac3 = 4
    /// allpac4: id 5, late additions, searched first.
    case allpac4 = 5

    /// The archive's base name (`allpac1_2`).
    public var archiveName: String {
        switch self {
        case .allpac0: return "allpac0"
        case .allpac1: return "allpac1"
        case .allpac1_2: return "allpac1_2"
        case .allpac2: return "allpac2"
        case .allpac3: return "allpac3"
        case .allpac4: return "allpac4"
        }
    }
}

/// A picture file: its archive and NAM index. The engine packs it as `archive << 16 | index`.
public struct ImageId: Equatable, Hashable, Sendable, CustomStringConvertible {
    public let archive: ImageArchive
    public let index: Int

    public init(archive: ImageArchive, index: Int) {
        self.archive = archive
        self.index = index
    }

    /// The packed id of the engine (VA 0xC3270).
    public var packed: Int { Int(archive.rawValue) << 16 | index }

    /// The archive's base name (`allpac1_2`).
    public var archiveName: String { archive.archiveName }

    /// Splits a packed id; the archive id is the 4 bits at bit 16.
    /// - Throws: `TsukiError.bounds` when the archive id is not 0..5.
    public static func unpack(_ packed: Int) throws -> ImageId {
        let archive = (packed >> 16) & 0xF
        guard archive <= 5, let match = ImageArchive(rawValue: UInt8(archive)) else {
            throw TsukiError.bounds("archive id \(archive) of 0x\(String(packed, radix: 16)) is not 0..5")
        }
        return ImageId(archive: match, index: packed & 0xFFFF)
    }

    public var description: String { archiveName + "#" + String(index) }
}

/// One record of the engine's image table (data VA 0x671900 + 0x48 * k; docs/formats/images.md 8,
/// archives_ui_movies.md 4). Record k describes allpac2 entry k. Merges `tsuki.image_catalog.CatalogEntry` and
/// `tsuki.catalog_eboot.ImageRecord`.
public struct CatalogEntry: Sendable {
    /// Record number = picture id = allpac2 entry.
    public let index: Int
    /// File offset of the record in eboot.bin.
    public let fileOffset: Int
    /// Base or full image MZP name (text VA +0x08), mixed case, with extension.
    public let name0: String
    /// Face layer drawn over `name0` (+0x10), or nil.
    public let name1: String?
    /// Position of the face relative to the base (+0x18); 0 in every record.
    public let layerX: Int
    /// See `layerX` (+0x1C).
    public let layerY: Int
    /// floor(width / 3) (+0x2C).
    public let w3: Int
    /// floor(height * 362 / 1080) (+0x2E).
    public let h3: Int
    /// Logical width; one language band for pictures with bands (+0x30).
    public let width: Int
    /// Logical height (+0x32).
    public let height: Int
    /// Anchor in the w3 / h3 scale (+0x34).
    public let anchorX: Int
    /// Anchor y (+0x38); -1 in empty slots.
    public let anchorY: Int
    /// +0x3C, 0x0B in every record.
    public let kind: Int
    /// +0x3D, 3 only for the seven solid colours.
    public let drawFlags: Int
    /// +0x3E, 0 in every record.
    public let drawParam: Int
    /// +0x3F: bit 0 = an `_HH_VV` variant, bit 1 = four language bands.
    public let picFlags: Int
    /// +0x40, the character id of a sprite record, else 0.
    public let charId: Int
    /// +0x42, the sprite size letter A / L / M / S as 0..3.
    public let scaleClass: Int

    /// Row distance between language bands is rounded up to a multiple of this (VA 0xC26A1).
    public static let bandAlign = 254

    /// The thumbnail scale 1/12.8 (VA 0xC2730).
    public static let thumbScale = 0.078125

    public init(index: Int, fileOffset: Int, name0: String, name1: String?, layerX: Int, layerY: Int,
                w3: Int, h3: Int, width: Int, height: Int, anchorX: Int, anchorY: Int,
                kind: Int, drawFlags: Int, drawParam: Int, picFlags: Int, charId: Int, scaleClass: Int) {
        self.index = index
        self.fileOffset = fileOffset
        self.name0 = name0
        self.name1 = name1
        self.layerX = layerX
        self.layerY = layerY
        self.w3 = w3
        self.h3 = h3
        self.width = width
        self.height = height
        self.anchorX = anchorX
        self.anchorY = anchorY
        self.kind = kind
        self.drawFlags = drawFlags
        self.drawParam = drawParam
        self.picFlags = picFlags
        self.charId = charId
        self.scaleClass = scaleClass
    }

    /// VA of the record in the verified build (in another build's located table the record sits at `fileOffset` instead).
    public var va: Int { EbootAddresses.imageTable + EbootAddresses.imageRecordSize * index }

    /// The script-visible name: the face when there is one, else the file. Equals the allpac2 NAM name.
    public var name: String { name1 ?? name0 }

    /// The allpac2 NAM name, upper case.
    public var thumbName: String { name.uppercased() }

    /// The layers to draw, upper case: `name0`, then `name1` if any.
    public var layers: [String] {
        if let name1 { return [name0.uppercased(), name1.uppercased()] }
        return [name0.uppercased()]
    }

    /// True when the record draws a body (`name0`) plus a face (`name1`).
    public var paired: Bool { name1 != nil }

    /// pic_flags bit 0: the name ends in `_HH_VV`, a variant of another picture.
    public var isVariant: Bool { picFlags & 1 != 0 }

    /// pic_flags bit 1: the picture stores the ja / en / zc / zt versions stacked vertically.
    public var hasLanguageBands: Bool { picFlags & 2 != 0 }

    /// Row distance between language bands in the full-size picture; 0 without bands.
    public var bandStride: Int {
        hasLanguageBands ? (height + Self.bandAlign - 1) / Self.bandAlign * Self.bandAlign : 0
    }

    /// The part of the full-size picture the engine draws (displayed pixels): the logical size from the top-left, or
    /// for a picture with language bands the band of `language` (0 ja, 1 en, 2 zc, 3 zt).
    public func sourceRect(language: Int) throws -> PixelRect {
        guard hasLanguageBands else { return PixelRect(x: 0, y: 0, width: width, height: height) }
        return PixelRect(x: 0, y: try ImageCatalog.languageIndex(language) * bandStride, width: width, height: height)
    }

    /// The part of the allpac2 thumbnail the engine draws (VA 0xC2730).
    public func thumbRect(language: Int) throws -> PixelRect {
        let tw = Int(Double(width) * Self.thumbScale + 0.5)
        let th = Int(Double(height) * Self.thumbScale + 0.5)
        guard hasLanguageBands else { return PixelRect(x: 0, y: 0, width: tw, height: th) }
        return PixelRect(x: 0, y: try ImageCatalog.languageIndex(language) * th, width: tw, height: th)
    }
}

/// The engine's image catalog: 14,744 records and 31 empty slots (14,775 = the engine's bound) in the data segment of
/// eboot.bin. A port of `tsuki.image_catalog` (the table) and `tsuki.catalog_eboot.Eboot.image_table`.
public struct ImageCatalog: Sendable {
    /// The used records, index = record number.
    public let entries: [CatalogEntry]
    /// Empty slots after the used records (31 in v01.01).
    public let emptySlots: Int
    /// File offset of record 0 (0x3D78A0 in v01.01).
    public let fileOffset: Int

    public init(entries: [CatalogEntry], emptySlots: Int, fileOffset: Int) {
        self.entries = entries
        self.emptySlots = emptySlots
        self.fileOffset = fileOffset
    }

    /// Number of used records.
    public var count: Int { entries.count }

    /// The record `k`.
    public subscript(k: Int) -> CatalogEntry { entries[k] }

    /// The game language index (0 ja, 1 en, 2 zc, 3 zt) of a band language.
    /// - Throws: `TsukiError.bounds` when it is not 0..3.
    public static func languageIndex(_ language: Int) throws -> Int {
        guard language >= 0 && language <= 3 else {
            throw TsukiError.bounds("language index \(language) not in 0..3")
        }
        return language
    }

    /// The language index of `ja en zc zt` (case-insensitive).
    /// - Throws: `TsukiError.format` when it is not one of the four.
    public static func languageIndex(_ language: String) throws -> Int {
        let codes = ["ja", "en", "zc", "zt"]
        let lower = language.lowercased()
        guard let index = codes.firstIndex(of: lower) else {
            throw TsukiError.format("unknown language \"\(language)\" (expected ja, en, zc or zt)")
        }
        return index
    }

    /// Reads the table where `EbootReader.layout` puts it (VA 0x671900 in the verified build): every slot up to the bound, the used
    /// records contiguous from 0, the rest empty. Checks the pointers, the file names and the count: the layout's by default (-1),
    /// `expectedRecords` when given, none for nil.
    /// - Throws: `TsukiError.format` when a record or the count differs from the analysed build.
    public static func read(_ eb: EbootReader, expectedRecords: Int? = -1) throws -> ImageCatalog {
        let layout = eb.layout
        var wanted = expectedRecords
        if wanted == -1 {
            wanted = layout.imageRecords  // the layout's count; nil means no count check
        }

        var list: [CatalogEntry] = []
        list.reserveCapacity(layout.imageRecords)
        var empty = 0
        guard let tableFile = eb.fileOffset(layout.imageTable) else {
            throw TsukiError.format("image table VA 0x\(String(layout.imageTable, radix: 16)) is not file-backed")
        }
        let dataFile = tableFile - layout.imageTable
        for k in 0..<layout.imageSlots {
            let va = layout.imageTable + EbootAddresses.imageRecordSize * k
            let raw = try eb.read(va, EbootAddresses.imageRecordSize)
            let pname = raw.u64(0)
            let pfile = raw.u64(8)
            let pov = raw.u64(16)
            if pfile == 0 {
                if pov != 0 || raw.i32(0x20) != -1 {
                    throw TsukiError.format("image slot \(k) is neither a record nor empty")
                }
                empty += 1
                continue
            }

            if empty > 0 {
                throw TsukiError.format("image slot \(k) is used after an empty slot")
            }

            if pname != 0 {
                throw TsukiError.format("image slot \(k): name pointer is not 0 (different eboot version?)")
            }

            if !eb.isTextPointer(Int(pfile)) || (pov != 0 && !eb.isTextPointer(Int(pov))) {
                throw TsukiError.format("image slot \(k): pointer outside the text segment")
            }

            let file = eb.cString(Int(pfile), limit: 48)
            let overlay = pov != 0 ? eb.cString(Int(pov), limit: 48) : nil
            for n in [file, overlay] {
                if let n, !isFileName(n) {
                    throw TsukiError.format("image slot \(k): unexpected file name \"\(n)\"")
                }
            }

            list.append(fromRecord(k, va + dataFile, file, overlay, raw))
        }

        guard let first = list.first, first.name0.lowercased() == "black.mzp" else {
            throw TsukiError.format("image table not found at 0x\(String(layout.imageTable, radix: 16))")
        }

        if let want = wanted, list.count != want {
            throw TsukiError.format("image table has \(list.count) records, expected \(want)")
        }

        return ImageCatalog(entries: list, emptySlots: empty, fileOffset: first.fileOffset)
    }

    /// Locates the table by content in the whole file (record 0 names `BLACK.mzp`, record 1 `BLUE.mzp`) and returns
    /// the file offset of record 0, the used records and the empty slots after them (port of `find_catalog`).
    /// - Throws: `TsukiError.format` when there is no such pair or the table is malformed.
    public static func locate(_ data: ByteSpan) throws -> (offset: Int, used: Int, empty: Int) {
        let textStart = EbootAddresses.textFileOffset
        let textEnd = EbootAddresses.textFileOffset + EbootAddresses.textSize
        let black = Array("BLACK.mzp".utf8) + [0]
        var start = -1
        let searchEnd = min(textEnd, data.count)
        var s = indexOf(data, black, from: textStart, to: searchEnd)
        while s >= 0 && start < 0 {
            let pointer = littleEndianBytes(UInt64(s - textStart))
            var pos = indexOf(data, pointer, from: textEnd, to: data.count)
            while pos >= 0 {
                let rec = pos - 8
                if isRecordStart(data, rec) && isRecordStart(data, rec + EbootAddresses.imageRecordSize) {
                    let n1 = data.u64(rec + EbootAddresses.imageRecordSize + 8)
                    if try textCString(data, n1).lowercased() == "blue.mzp" {
                        start = rec
                        break
                    }
                }

                pos = indexOf(data, pointer, from: pos + 1, to: data.count)
            }

            s = indexOf(data, black, from: s + 1, to: searchEnd)
        }

        guard start >= 0 else {
            throw TsukiError.format("image catalog not found (no BLACK.mzp/BLUE.mzp record pair)")
        }

        var n = 0
        while true {
            let off = start + n * EbootAddresses.imageRecordSize
            if off + EbootAddresses.imageRecordSize > data.count {
                throw TsukiError.format("image catalog runs past the end of the file")
            }

            if data.u64(off + 8) == 0 {
                break
            }

            if !isRecordStart(data, off) {
                throw TsukiError.format("malformed catalog record \(n) at file 0x\(String(off, radix: 16))")
            }

            n += 1
        }

        var empty = 0
        while true {
            let off = start + (n + empty) * EbootAddresses.imageRecordSize
            if off + EbootAddresses.imageRecordSize > data.count {
                break
            }

            let f = data.slice(off, EbootAddresses.imageRecordSize)
            if f.u64(8) != 0 || f.u64(16) != 0 || f.i32(0x20) != -1 {
                break
            }

            empty += 1
        }

        guard empty > 0 else {
            throw TsukiError.format("no empty terminator slot after catalog record \(n - 1)")
        }
        return (start, n, empty)
    }

    /// Reads the table found by `locate` (port of `load_catalog`); names are decoded as ASCII.
    public static func readByContent(_ data: ByteSpan) throws -> ImageCatalog {
        let (start, n, empty) = try locate(data)
        var entries: [CatalogEntry] = []
        entries.reserveCapacity(n)
        for i in 0..<n {
            let off = start + i * EbootAddresses.imageRecordSize
            let raw = data.slice(off, EbootAddresses.imageRecordSize)
            let p0 = raw.u64(8)
            let p1 = raw.u64(16)
            entries.append(fromRecord(i, off, try textCString(data, p0),
                                      p1 != 0 ? try textCString(data, p1) : nil, raw))
        }

        return ImageCatalog(entries: entries, emptySlots: empty, fileOffset: start)
    }

    private static func fromRecord(_ index: Int, _ fileOffset: Int, _ name0: String, _ name1: String?,
                                   _ raw: ByteSpan) -> CatalogEntry {
        CatalogEntry(index: index, fileOffset: fileOffset, name0: name0, name1: name1,
                     layerX: Int(raw.i32(0x18)), layerY: Int(raw.i32(0x1C)),
                     w3: Int(raw.u16(0x2C)), h3: Int(raw.u16(0x2E)),
                     width: Int(raw.u16(0x30)), height: Int(raw.u16(0x32)),
                     anchorX: Int(raw.i32(0x34)), anchorY: Int(raw.i32(0x38)),
                     kind: Int(raw[0x3C]), drawFlags: Int(raw[0x3D]), drawParam: Int(raw[0x3E]),
                     picFlags: Int(raw[0x3F]), charId: Int(raw.u16(0x40)), scaleClass: Int(raw.i16(0x42)))
    }

    /// `[A-Za-z0-9_]+\.(mzp|MZP|mrg|MRG)`: the names the engine table holds.
    public static func isFileName(_ n: String) -> Bool {
        guard let dot = n.lastIndex(of: ".") else { return false }
        let dotOffset = n.distance(from: n.startIndex, to: dot)
        if dotOffset < 1 { return false }

        for scalar in n[..<dot].unicodeScalars {
            let c = scalar.value
            let letter = (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A)
            let digit = c >= 0x30 && c <= 0x39
            if !(letter || digit || c == 0x5F) { return false }
        }

        let ext = String(n[n.index(after: dot)...])
        return ext == "mzp" || ext == "MZP" || ext == "mrg" || ext == "MRG"
    }

    private static func indexOf(_ data: ByteSpan, _ pattern: [UInt8], from start: Int, to end: Int) -> Int {
        guard !pattern.isEmpty else { return -1 }
        let begin = max(0, start)
        let limit = min(end, data.count) - pattern.count
        guard begin <= limit else { return -1 }
        return data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            let first = pattern[0]
            var i = begin
            while i <= limit {
                if bytes[i] == first {
                    var j = 1
                    while j < pattern.count && bytes[i + j] == pattern[j] { j += 1 }
                    if j == pattern.count { return i }
                }
                i += 1
            }
            return -1
        }
    }

    private static func littleEndianBytes(_ value: UInt64) -> [UInt8] {
        var writer = ByteWriter(reserving: 8)
        writer.u64(value)
        return writer.bytes
    }

    private static func textCString(_ data: ByteSpan, _ va: UInt64) throws -> String {
        guard va != 0 && va < UInt64(EbootAddresses.textSize) else {
            throw TsukiError.format("name pointer 0x\(String(va, radix: 16)) outside the text segment")
        }

        let o = EbootAddresses.textFileOffset + Int(va)
        guard o >= 0, o <= data.count else {
            throw TsukiError.format("name pointer 0x\(String(va, radix: 16)) outside the file")
        }
        let window = data.slice(o, min(96, data.count - o))
        guard let nul = window.firstIndex(of: 0) else {
            throw TsukiError.format("unterminated name at text VA 0x\(String(va, radix: 16))")
        }

        let name = window.slice(0, nul)
        if name.contains(where: { $0 >= 0x80 }) {
            throw TsukiError.format("non-ASCII name at text VA 0x\(String(va, radix: 16))")
        }
        return String(decoding: name, as: UTF8.self)
    }

    private static func isRecordStart(_ data: ByteSpan, _ off: Int) -> Bool {
        guard off >= 0, off + EbootAddresses.imageRecordSize <= data.count else { return false }
        let f = data.slice(off, EbootAddresses.imageRecordSize)
        if f.u64(0) != 0 || f.i32(0x20) != -1 || f.i32(0x24) != -1 { return false }

        let p0 = f.u64(8)
        if p0 == 0 { return false }

        guard let name = try? textCString(data, p0) else { return false }
        return name.lowercased().hasSuffix(".mzp")
    }
}

/// The embedded picture-name lists (32-byte records: NUL-padded upper-case name without extension, bytes 30..31 CR LF,
/// a 0xFF byte after the last record). Name k is the name of image-table record k (archives_ui_movies.md 2.4).
public enum PictureNameLists {
    /// Names in the list at data VA 0x7F6800 including the empty record 14,744 (14,745).
    public static let records = EbootAddresses.imageTableRecords + 1

    /// Every record before the 0xFF terminator, including the final empty one, so index k is the engine index k
    /// (port of `Eboot.name_list`).
    /// - Throws: `TsukiError.format` when there is no terminator within `limit` records.
    public static func readList(_ eb: EbootReader, _ va: Int, limit: Int = 0x8000) throws -> [String] {
        var names: [String] = []
        names.reserveCapacity(min(limit, 16_384))
        for k in 0..<limit {
            let rec = try eb.read(va + EbootAddresses.nameRecordSize * k, EbootAddresses.nameRecordSize)
            if rec[0] == 0xFF {
                return names
            }

            let nul = rec.firstIndex(of: 0) ?? rec.count
            names.append(EbootReader.latin1(rec.slice(0, nul)))
        }

        throw TsukiError.format("name list at 0x\(String(va, radix: 16)) has no 0xFF terminator within \(limit) records")
    }

    /// The script-name list at data VA 0x7F6800 (14,745 records; the last is empty); entry 0 must be `BLACK`.
    public static func read(_ eb: EbootReader) throws -> [String] {
        let names = try readList(eb, eb.layout.imageNames)
        guard let first = names.first, first == "BLACK" else {
            throw TsukiError.format("image name list not found at 0x\(String(eb.layout.imageNames, radix: 16))")
        }
        return names
    }

    /// The old list at data VA 0x7A8B10: the first 9,958 names and an empty record; empty when the eboot has no such list.
    public static func readOld(_ eb: EbootReader) throws -> [String] {
        eb.layout.oldImageNames == 0 ? [] : try readList(eb, eb.layout.oldImageNames)
    }
}
