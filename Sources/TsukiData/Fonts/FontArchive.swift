import Foundation
import TsukiCore
import TsukiEngine

/// One decoded glyph page of `ft_<lang>.mrg` before it becomes pixels: the header fields, the palette in pixel-index order and the
/// 8-bit palette indices (docs/formats/fonts.md 3; `tsuki.font.FontPage`).
public struct FontPageData: Sendable {
    /// The section number (0..64); the page is texture slot `FontArchive.firstSlot` + section.
    public let section: Int
    /// Page width: 256 for the blank page 0, 1024 for the others.
    public let width: Int
    /// Page height.
    public let height: Int
    /// The eight header words: width, height, tile width, tile height, tiles x, tiles y, type a, type b.
    public let header: [UInt16]
    /// The byte after the palette: 1 for a page with glyphs, 0 for a blank page, -1 when the header ends before it.
    public let flag: Int
    /// 256 RGBA entries in pixel-index order (the PS2 CSM1 swizzle undone); alpha is the PS2 value 0..0x80.
    public let palette: [UInt8]
    /// Width x Height palette indices, row-major, top-down.
    public let indices: [UInt8]

    public init(section: Int, width: Int, height: Int, header: [UInt16], flag: Int, palette: [UInt8], indices: [UInt8]) {
        self.section = section
        self.width = width
        self.height = height
        self.header = header
        self.flag = flag
        self.palette = palette
        self.indices = indices
    }

    /// The texture slot the engine uploads this page to.
    public var slot: Int { FontArchive.firstSlot + section }

    /// The engine's palette alpha conversion (VA 0xD90B0..0xD90CE): 0x80 becomes 0xFF, anything else `(2 * a) & 0xFF`.
    public static func alpha8(_ ps2Alpha: UInt8) -> UInt8 {
        ps2Alpha == 0x80 ? 0xFF : ps2Alpha &* 2
    }

    /// Straight-alpha RGBA8 of the whole page, top-down: each pixel takes its palette entry with the alpha converted.
    public func toRgba() -> [UInt8] {
        var lut = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            lut[i] = packRGBA8(palette[4 * i], palette[4 * i + 1], palette[4 * i + 2],
                               Self.alpha8(palette[4 * i + 3]))
        }

        var rgba = [UInt8](repeating: 0, count: indices.count * 4)
        lut.withUnsafeBufferPointer { table in
            rgba.withUnsafeMutableBytes { raw in
                for i in 0..<indices.count {
                    raw.storeBytes(of: table[Int(indices[i])].littleEndian, toByteOffset: 4 * i, as: UInt32.self)
                }
            }
        }
        return rgba
    }

    /// The 8-bit coverage plane (the converted alpha of every pixel).
    public func toCoverage() -> [UInt8] {
        var alpha = [UInt8](repeating: 0, count: 256)
        for i in 0..<256 {
            alpha[i] = Self.alpha8(palette[4 * i + 3])
        }

        var coverage = [UInt8](repeating: 0, count: indices.count)
        for i in 0..<coverage.count {
            coverage[i] = alpha[Int(indices[i])]
        }
        return coverage
    }
}

/// `image/ft_<lang>.mrg`: a standalone mrgd00 of 65 sections, each a nested two-section image container (docs/formats/fonts.md 3):
/// a 1041-byte header with the palette and an MZX0 plane of palette indices. Section 0 is a blank 256 x 256 page, sections 1..64 are
/// 1024 x 1024 pages that the font loader (VA 0xC6980) uploads as texture slots 0x21 + section. A port of `tsuki.font.FontPages`.
///
/// The file (1.2 .. 10.8 MB) is not read whole: the section table is read when it is opened, a page when it is asked for.
public final class FontArchive {
    /// Texture slot of section 0 (VA 0xC69F4).
    public static let firstSlot = 0x21

    /// Sections in the file.
    public static let pageCount = 65

    /// Bytes of palette header up to and including the flag byte.
    public static let headerBytes = 1041

    private let readSection: (Int) throws -> [UInt8]

    private init(language: Language, readSection: @escaping (Int) throws -> [UInt8]) {
        self.language = language
        self.readSection = readSection
    }

    /// The language of the file.
    public let language: Language

    /// The palette-index unswizzle of PS2 CSM1 order: bits 3 and 4 of the index swapped.
    public static func unswizzleCsm1(_ i: Int) -> Int {
        (i & 0xE7) | ((i & 0x08) << 1) | ((i & 0x10) >> 1)
    }

    /// Opens `image/ft_<lang>.mrg` of a game folder view.
    /// - Throws: `TsukiError.format` when the file does not follow the layout.
    public static func open(_ files: GameFiles, language: Language) throws -> FontArchive {
        let path = "image/ft_\(language.code).mrg"
        let length = try files.length(of: path)
        let top = try files.read(path, offset: 0, count: min(length, 8))
        guard Mzp.isContainer(top) else {
            throw TsukiError.format("\(path): not an mrgd00 container")
        }

        let tableBytes = 8 + 8 * Int(top.u16(6))
        let sections = try MzpContainer.readTable(try files.read(path, offset: 0, count: min(length, tableBytes)),
                                                  totalLength: length)
        return try create(language, sections, { i in
            try files.readRange(path, offset: sections[i].offset, count: sections[i].size)
        }, path)
    }

    /// Opens a font container that is already in memory.
    public static func fromMemory(_ language: Language, _ file: ByteSpan) throws -> FontArchive {
        let container = try MzpContainer.parse(file)
        return try create(language, container.sections, { i in container.section(i).toArray() },
                          "ft_\(language.code)")
    }

    /// Decodes page `page` to palette and indices.
    /// - Throws: `TsukiError.bounds` when the page is not 0..64, `TsukiError.format` when the page does not follow the layout.
    public func readPageData(_ page: Int) throws -> FontPageData {
        guard page >= 0 && page < Self.pageCount else {
            throw TsukiError.bounds("font pages are 0..\(Self.pageCount - 1), not \(page)")
        }

        let child = try MzpContainer.parse(ByteSpan(try readSection(page)))
        guard child.count == 2 else {
            throw TsukiError.format("page \(page): \(child.count) sections, expected 2")
        }

        let hdr = child.section(0)
        guard hdr.count >= 16 + 1024 else {
            throw TsukiError.format("font page header too short (\(hdr.count) bytes)")
        }

        var fields = [UInt16](repeating: 0, count: 8)
        for i in 0..<8 {
            fields[i] = hdr.u16(2 * i)
        }

        var palette = [UInt8](repeating: 0, count: 1024)
        for i in 0..<256 {
            let at = 16 + 4 * Self.unswizzleCsm1(i)
            palette[4 * i] = hdr[at]
            palette[4 * i + 1] = hdr[at + 1]
            palette[4 * i + 2] = hdr[at + 2]
            palette[4 * i + 3] = hdr[at + 3]
        }

        let flag = hdr.count > Self.headerBytes - 1 ? Int(hdr[Self.headerBytes - 1]) : -1
        let w = Int(fields[0])
        let h = Int(fields[1])
        guard fields[2] == fields[0], fields[3] == fields[1], fields[4] == 1, fields[5] == 1 else {
            throw TsukiError.format("page \(page): unexpected tiling (\(fields.map(String.init).joined(separator: ", ")))")
        }

        let decoded = try Mzx.decompress(child.section(1))
        guard decoded.length == w * h else {
            throw TsukiError.format("page \(page): \(decoded.length) pixel bytes for \(w)x\(h)")
        }

        return FontPageData(section: page, width: w, height: h, header: fields, flag: flag,
                            palette: palette, indices: decoded.toArray())
    }

    /// Decodes page `page` to the straight-alpha RGBA the renderer uploads.
    public func readPage(_ page: Int) throws -> FontPage {
        let data = try readPageData(page)
        return FontPage(language: language, page: page, width: data.width, height: data.height, rgba: data.toRgba())
    }

    private static func create(
        _ language: Language, _ sections: [MzpSection], _ readSection: @escaping (Int) throws -> [UInt8], _ name: String
    ) throws -> FontArchive {
        guard sections.count == pageCount else {
            throw TsukiError.format("\(name): \(sections.count) sections, expected \(pageCount)")
        }

        return FontArchive(language: language, readSection: readSection)
    }
}
