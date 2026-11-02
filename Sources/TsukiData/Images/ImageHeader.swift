import Foundation
import TsukiCore
import TsukiEngine

/// The four pixel formats of the retail image MZPs (docs/formats/images.md 1).
public enum PixelFormat: Equatable, Sendable {
    /// `bmp_type` 1, depth code 0: 16 x RGBA palette in the header, 4 bits per pixel (images.md 3.2).
    case pal4

    /// `bmp_type` 1, depth code 1: 256 x RGBA palette in the header in PS2 CSM1 order, 8 bits per pixel
    /// (images.md 3.1).
    case pal8

    /// `bmp_type` 12, depth code 1: per-tile "HEP" block with its own palette (images.md 4).
    case hep8

    /// `bmp_type` 11, depth code 4: planar u16 RGB565, u8 low bits, u8 alpha (images.md 5).
    case rgb565LoA
}

extension PixelFormat: CustomStringConvertible {
    public var description: String {
        switch self {
        case .pal4: return "Pal4"
        case .pal8: return "Pal8"
        case .hep8: return "Hep8"
        case .rgb565LoA: return "Rgb565LoA"
        }
    }
}

/// Section 0 of an image MZP: 16 bytes, an optional palette and one flag byte per tile
/// (docs/formats/images.md 2). A port of `tsuki.image.parse_header`.
public struct ImageHeader: Sendable {
    /// The longest tile edge or tile size in pixels the parser accepts (256 MiB of RGBA); retail tiles
    /// are at most 1024 x 1024.
    public static let maxTilePixels = 1 << 26

    /// Bytes of the HEP tile header (images.md 4.1).
    public static let hepHeaderSize = 0x20

    /// Stored width (u16 at 0); includes 2 pixels per tile column when ``border`` is 1.
    public let width: Int

    /// Stored height (u16 at 2).
    public let height: Int

    /// Stored tile width, border included.
    public let tileWidth: Int

    /// Stored tile height, border included.
    public let tileHeight: Int

    /// Tile columns, `ceil(width / tileWidth)`.
    public let tilesX: Int

    /// Tile rows, `ceil(height / tileHeight)`.
    public let tilesY: Int

    /// `bmp_type` as stored (u16 at 0x0C).
    public let bmpType: Int

    /// `depth` as stored (u8 at 0x0E); the low nibble is the pixel size code.
    public let depth: Int

    /// `attr` as stored (u8 at 0x0F); bit 0 means every tile carries a 1-pixel border.
    public let attr: Int

    /// The pixel format.
    public let format: PixelFormat

    /// The header palette as the engine uses it, RGBA packed little-endian into u32 (CSM1 order fixed
    /// for 256 colours, alpha fixed): 16 entries for ``PixelFormat/pal4``, 256 for
    /// ``PixelFormat/pal8``, else nil.
    public let palette: [UInt32]?

    /// One flag byte per tile: 0 empty, 1 may be transparent, 2 opaque hint (images.md 2.3).
    public let tileFlags: [UInt8]

    /// Size of section 0 in bytes.
    public let headerSize: Int

    private init(
        width: Int, height: Int, tileWidth: Int, tileHeight: Int, tilesX: Int, tilesY: Int,
        bmpType: Int, depth: Int, attr: Int, format: PixelFormat, palette: [UInt32]?,
        tileFlags: [UInt8], headerSize: Int
    ) {
        self.width = width
        self.height = height
        self.tileWidth = tileWidth
        self.tileHeight = tileHeight
        self.tilesX = tilesX
        self.tilesY = tilesY
        self.bmpType = bmpType
        self.depth = depth
        self.attr = attr
        self.format = format
        self.palette = palette
        self.tileFlags = tileFlags
        self.headerSize = headerSize
    }

    /// Number of tiles, `tilesX * tilesY`.
    public var tiles: Int { tilesX * tilesY }

    /// 1 when every tile carries a 1-pixel border copied from its neighbours (attr bit 0), else 0.
    public var border: Int { attr & 1 }

    /// Displayed pixels per tile column.
    public var innerWidth: Int { tileWidth - (2 * border) }

    /// Displayed pixels per tile row.
    public var innerHeight: Int { tileHeight - (2 * border) }

    /// Displayed width (engine VA 0xD8C4F: the border pixels are dropped when attr bit 0 is set and the
    /// width is at least 8).
    public var displayWidth: Int { border != 0 && width >= 8 ? width - (2 * tilesX) : width }

    /// Displayed height.
    public var displayHeight: Int { border != 0 && height >= 8 ? height - (2 * tilesY) : height }

    /// Pixels of one stored tile.
    public var tilePixels: Int { tileWidth * tileHeight }

    /// Bytes of one stored tile as RGBA8.
    public var tileRgbaBytes: Int { 4 * tilePixels }

    /// The decompressed size of one tile stream (images.md 3.2, 4.1, 5).
    public var tileBytes: Int {
        switch format {
        case .pal4: return tilePixels / 2
        case .pal8: return tilePixels
        case .hep8: return Self.hepHeaderSize + tilePixels + (256 * 4)
        case .rgb565LoA: return 4 * tilePixels
        }
    }

    /// The tile flag of tile `t` is not 0.
    public func isLive(_ t: Int) -> Bool { tileFlags[t] != 0 }

    /// Top-left of tile `t`'s displayed area in the picture (images.md 2.2).
    public func tileOrigin(_ t: Int) -> (x: Int, y: Int) {
        (t % tilesX * innerWidth, t / tilesX * innerHeight)
    }

    /// The part of stored tile `t` that is displayed: inner rectangle, clipped to the picture; width or
    /// height 0 when the tile lies outside.
    public func tileWindow(_ t: Int) -> (sx: Int, sy: Int, width: Int, height: Int, x: Int, y: Int) {
        let (x0, y0) = tileOrigin(t)
        let w = max(0, min(innerWidth, displayWidth - x0))
        let h = max(0, min(innerHeight, displayHeight - y0))
        return (border, border, w, h, x0, y0)
    }

    /// Parses section 0 of an image MZP.
    public static func parse(_ section: ByteSpan) throws -> ImageHeader {
        guard section.count >= 16 else {
            throw TsukiError.format("image header too short (\(section.count) bytes)")
        }

        let w = Int(section.u16(0))
        let h = Int(section.u16(2))
        let tw = Int(section.u16(4))
        let th = Int(section.u16(6))
        let tx = Int(section.u16(8))
        let ty = Int(section.u16(10))
        let bt = Int(section.u16(12))
        let depth = Int(section[14])
        let attr = Int(section[15])
        guard w != 0, h != 0, tw != 0, th != 0, tx != 0, ty != 0 else {
            throw TsukiError.format("zero dimension in image header \(hexLower(section.slice(0, 16)))")
        }

        guard tx == (w + tw - 1) / tw, ty == (h + th - 1) / th else {
            throw TsukiError.format("tile counts \(tx)x\(ty) inconsistent with \(w)x\(h) / \(tw)x\(th)")
        }

        guard tw * th <= maxTilePixels else {
            throw TsukiError.format("tile of \(tw)x\(th) pixels is larger than any retail tile")
        }

        // Engine VA 0xD8DC7..0xD8DFB: a header palette exists only for bmp_type 1 and 2; depth code 0
        // gives 16 colours, codes 1 and 7 give 256, any other code none (the flags then follow at 0x10).
        let code = depth & 0x0F
        let type = bt & 0xFF
        let paletteEntries: Int
        if type == 1 || type == 2 {
            paletteEntries = code == 0 ? 16 : (code == 1 || code == 7 ? 256 : 0)
        } else {
            paletteEntries = 0
        }

        let needed = 16 + (4 * paletteEntries) + (tx * ty)
        guard section.count == needed else {
            throw TsukiError.format(
                "header is \(section.count) bytes, expected 16 + \(4 * paletteEntries) + \(tx * ty) = \(needed)")
        }

        let format: PixelFormat
        switch (type, code) {
        case (1, 0): format = .pal4
        case (1, 1): format = .pal8
        case (12, 1): format = .hep8
        case (11, 4): format = .rgb565LoA
        default:
            throw TsukiError.format(
                "unsupported image type: bmp_type=\(String(bt, radix: 16)) depth=\(String(depth, radix: 16))")
        }

        var palette: [UInt32]?
        if format == .pal4 || format == .pal8 {
            palette = type1Palette(section.slice(16, 4 * paletteEntries), count: paletteEntries)
        }

        let flags = section.slice(16 + (4 * paletteEntries), tx * ty).toArray()
        return ImageHeader(
            width: w, height: h, tileWidth: tw, tileHeight: th, tilesX: tx, tilesY: ty, bmpType: bt,
            depth: depth, attr: attr, format: format, palette: palette, tileFlags: flags,
            headerSize: section.count)
    }

    /// Header palette of a `bmp_type` 1 image as the engine uses it (images.md 3.1): CSM1 unswizzle for
    /// 256 colours (entries 8..15 and 16..23 of every block of 32 exchanged) and alpha `a` to 0xFF if
    /// `a == 0x80` else `(2a) & 0xFF`.
    static func type1Palette(_ raw: ByteSpan, count n: Int) -> [UInt32] {
        var palette = [UInt32](repeating: 0, count: n)
        for i in 0..<n {
            let source = n == 256 && (((i >> 3) ^ (i >> 4)) & 1) != 0 ? i ^ 0x18 : i
            let r = UInt32(raw[4 * source])
            let g = UInt32(raw[(4 * source) + 1])
            let b = UInt32(raw[(4 * source) + 2])
            var a = UInt32(raw[(4 * source) + 3])
            a = a == 0x80 ? 0xFF : (2 * a) & 0xFF
            palette[i] = r | (g << 8) | (b << 16) | (a << 24)
        }
        return palette
    }

    /// One line in the style of `ImageHeader.describe` of the Python reference.
    public func describe() -> String {
        var f0 = 0
        var f1 = 0
        var f2 = 0
        for flag in tileFlags {
            if flag == 0 {
                f0 += 1
            } else if flag == 1 {
                f1 += 1
            } else if flag == 2 {
                f2 += 1
            }
        }

        return "\(width)x\(height) (shown \(displayWidth)x\(displayHeight)) tiles \(tilesX)x\(tilesY) "
            + "of \(tileWidth)x\(tileHeight) type=\(String(bmpType, radix: 16)) "
            + "depth=\(String(format: "%02x", depth)) attr=\(String(format: "%02x", attr)) "
            + "format=\(format) border=\(border) flags={0:\(f0),1:\(f1),2:\(f2)}"
    }
}
