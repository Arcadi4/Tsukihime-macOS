import Foundation
import TsukiCore

/// The glyph chosen for one character or `[tag]` (reduced to what the layout reads).
public struct Glyph: Sendable {
    /// UTF-8 bytes consumed; 0 for an invalid lead byte (the engine consumes nothing).
    public let consumed: Int
    /// Texture slot (font page = slot - 0x21).
    public let tex: Int
    /// Atlas rectangle left.
    public let x: Int
    /// Atlas rectangle top.
    public let y: Int
    /// Atlas rectangle width (signed, like the engine's s16).
    public let w: Int
    /// Atlas rectangle height.
    public let h: Int
    /// Pen/draw x adjustment, already multiplied by the scale (a double, narrowed to float by the
    /// caller).
    public let adj: Double

    public init(consumed: Int, tex: Int, x: Int, y: Int, w: Int, h: Int, adj: Double) {
        self.consumed = consumed
        self.tex = tex
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.adj = adj
    }
}

/// Glyph lookup of one language: a character (or `[tag]`) at a byte offset plus the style to its
/// rectangle in a font page, and the joined-dash pieces. Mirrors eboot VA 0x10810 / 0x11150 / 0x11750 /
/// 0x11B80 / 0x11ED0 as ported in tools/tsuki/font.py `Font` (docs/formats/fonts.md 5, 6).
public final class LanguageGlyphs {
    /// Glyph cell size of the fixed grids.
    public static let cell = 73

    private static let gridCols = 14
    private static let perPage = gridCols * 7
    private static let fallbackSlot = 0x22

    private let tables: FontTables
    private let lang: Int
    private let narrow: GlyphLookupTable
    private let wide: GlyphLookupTable
    private let s1: GlyphLookupTable
    private let s2: GlyphLookupTable
    private let recordsByStyle: [GlyphRecordTable?]

    init(tables: FontTables, language lang: Int) {
        self.tables = tables
        self.lang = lang
        let name = FontTables.langNames[lang]
        narrow = tables.lookup("narrow")
        wide = tables.lookup(name + "_wide")
        s1 = tables.lookup(name + "_s1")
        s2 = tables.lookup(name + "_s2")
        recordsByStyle = (0..<6).map { tables.records(Self.recordTableName(lang, $0)) as GlyphRecordTable? }
    }

    /// Name of the 10-byte record table for (language, style) (VA 0x112E7 jump table).
    public static func recordTableName(_ lang: Int, _ style: Int) -> String {
        let name = FontTables.langNames[lang]
        switch lang {
        case 0:
            return style == 0 ? "ja_s0" : style == 2 ? "ja_s2" : "ja_s1"
        case 1:
            switch style {
            case 0: return "en_s0"
            case 2: return "en_s2"
            case 3: return "en_s3"
            case 4: return "en_s4"
            case 5: return "en_s5"
            default: return "en_s1"
            }
        case 3:
            return style == 0 ? "zt_s0" : "zt_s1"
        default:
            return style == 0 ? name + "_s0" : style == 2 ? name + "_s2" : name + "_s1"
        }
    }

    /// The glyph of the character or `[tag]` at `b[pos]` (VA 0x11750). `consumed == 0` marks a NUL
    /// byte, the end of `b` or an invalid lead byte; callers must handle it.
    public func charGlyph(_ b: ByteSpan, _ pos: Int, _ style: Int, _ kind: Int, _ scale: Double) throws -> Glyph {
        if pos >= b.count || b[pos] == 0 {
            return Glyph(consumed: 0, tex: 0xFFFF, x: 0, y: 0, w: Self.cell, h: Self.cell, adj: 0.0)
        }

        if b[pos] == 0x5B {
            let tags = tables.tags
            for k in tags.indices where Self.hasPrefix(b, pos, tags[k]) {
                return tagGlyph(k, tags[k].count, kind, scale)
            }
        }

        let (key, n) = Self.decodeKey(b, pos)
        if n == 0 {
            return Glyph(consumed: 0, tex: 0xFFFF, x: 0, y: 0, w: 0, h: 0, adj: 0.0)
        }

        if let glyph = try tryGetGlyph(key, style, scale, n) {
            return glyph
        }

        return Glyph(consumed: n, tex: Self.fallbackSlot, x: 0, y: 0,
                     w: n <= 2 ? 42 : Self.cell, h: Self.cell, adj: 0.0)
    }

    /// Joined-dash piece for the character at `pos` (VA 0x11B80): 0..8, or -1 to draw the normal
    /// glyph. `prevPos` is the start of the previous parse element, or -1.
    public static func dashVariantAt(_ b: ByteSpan, _ pos: Int, _ prevPos: Int,
                                     _ lineStart: Bool, _ lineEnd: Bool, _ flagB: Bool) -> Int {
        let key = key3At(b, pos)
        let baseVariant: Int
        switch key {
        case 0xE296A0: baseVariant = 0
        case 0xE28095: baseVariant = 3
        case 0xE29480: baseVariant = 6
        default: return -1
        }

        let hasPrev = key3At(b, prevPos) == key && !lineStart
        let hasNext = key3At(b, pos + 3) == key && !lineEnd
        if hasPrev && hasNext {
            return baseVariant + 1
        }
        if hasPrev {
            return baseVariant + (flagB ? 0 : 2)
        }
        if hasNext {
            return baseVariant + (flagB ? 2 : 0)
        }
        return -1
    }

    /// Rectangle of a joined-dash piece on page 61 (VA 0x11ED0).
    public func dashGlyph(_ variant: Int, _ style: Int, _ kind: Int, _ scale: Double) -> Glyph {
        let y: Int
        switch lang {
        case 0: y = style == 2 ? 146 : 73
        case 2: y = 219
        case 3: y = 292
        default: y = 73
        }
        let xb = (lang == 1 || lang == 4) && (style == 3 || style == 4 || style == 5) ? 511 : 0
        let part = variant % 3
        let x = xb + variant / 3 * 146 + (part == 0 ? 0 : part == 1 ? 41 : 78)
        let w = part == 0 ? 73 : 68
        let adj = part == 0 ? 0.0 : scale * (kind < 2 ? 5.0 : -0.5)
        return Glyph(consumed: 3, tex: 0x5E, x: x, y: y, w: w, h: Self.cell, adj: adj)
    }

    /// Engine UTF-8 decode (VA 0x11B00 / 0x11750): the packed key and its length; length 0 = invalid
    /// lead.
    static func decodeKey(_ b: ByteSpan, _ pos: Int) -> (key: UInt64, length: Int) {
        let c = Int(b[pos])
        if c < 0x80 {
            return (UInt64(c), 1)
        }

        let n: Int
        if c & 0xE0 == 0xC0 {
            n = 2
        } else if c & 0xF0 == 0xE0 {
            n = 3
        } else if c & 0xF8 == 0xF0 {
            n = 4
        } else {
            return (UInt64(c), 0)
        }

        var key: UInt64 = 0
        for i in 0..<n {
            key = (key << 8) | UInt64(pos + i < b.count ? b[pos + i] : 0)
        }
        return (key, n)
    }

    private static func key3At(_ b: ByteSpan, _ pos: Int) -> UInt64 {
        guard pos >= 0, pos < b.count, (b[pos] & 0xF0) == 0xE0 else { return 0 }
        var key: UInt64 = 0
        for i in 0..<3 {
            key = (key << 8) | UInt64(pos + i < b.count ? b[pos + i] : 0)
        }
        return key
    }

    private static func hasPrefix(_ b: ByteSpan, _ pos: Int, _ prefix: [UInt8]) -> Bool {
        guard pos >= 0, pos + prefix.count <= b.count else { return false }
        for i in 0..<prefix.count where b[pos + i] != prefix[i] {
            return false
        }
        return true
    }

    private func tagGlyph(_ k: Int, _ length: Int, _ kind: Int, _ scale: Double) -> Glyph {
        let adjFar = scale * (kind < 2 ? 5.0 : -0.5)
        if k >= 38 {
            return Glyph(consumed: length, tex: 0x61, x: 0, y: 219, w: 68, h: 73, adj: adjFar)
        }
        if k >= 7 {
            let j = k - 7
            return Glyph(consumed: length, tex: 0x5F, x: j % 14 * 68, y: j / 14 * 73,
                         w: 68, h: 73, adj: adjFar)
        }
        if k == 4 {
            return Glyph(consumed: length, tex: 0x5E, x: 307, y: 0, w: 46, h: 73, adj: 0.0)
        }
        return Glyph(consumed: length, tex: 0x5E, x: 73 * k, y: 0, w: 73, h: 73, adj: 0.0)
    }

    private func lookupTableFor(_ key: UInt64, _ style: Int) -> GlyphLookupTable {
        switch style {
        case 0: return key >= 0x10000 ? wide : narrow
        case 2: return s2
        default: return s1
        }
    }

    private func tryGetGlyph(_ key: UInt64, _ style: Int, _ scale: Double, _ consumed: Int) throws -> Glyph? {
        var style = style
        var idx = lookupTableFor(key, style).get(key)
        if style != 0 && idx < 0 {
            idx = lookupTableFor(key, 0).get(key)
            style = 0
        }

        if idx < 0 {
            return nil
        }

        if key >= 0x10000 && style == 0 {
            let tex = tables.wideBase[lang] + idx / Self.perPage
            var x = idx % Self.gridCols * Self.cell
            let y = idx % Self.perPage / Self.gridCols * Self.cell
            var w = Self.cell
            var wideAdj = 0.0
            if lang == 0 && key >= 0xEFBDA1 && key <= 0xEFBE9F {
                x += 15
                w = 42
                if (key & ~1) == 0xEFBE9E {
                    wideAdj = -2.0 * scale
                }
            }
            return Glyph(consumed: consumed, tex: tex, x: x, y: y, w: w, h: Self.cell, adj: wideAdj)
        }

        guard let table = recordsByStyle[style] else {
            preconditionFailure("no record table for style \(style)")
        }
        let r = try table.get(idx)
        var adj = 0.0
        if lang == 1 && (style == 3 || style == 4 || style == 5) {
            // Italic: keep the upright advance (VA 0x11531).
            var w2: Int?
            if style == 3 {
                let i2 = tables.lookup(key >= 0x10000 ? "en_wide" : "narrow").get(key)
                if i2 >= 0 {
                    w2 = key > 0xFFFF ? Self.cell : (try tables.records("en_s0").get(i2).w)
                }
            } else if style == 4 {
                let i2 = tables.lookup("en_s1").get(key)
                if i2 >= 0 {
                    w2 = try tables.records("en_s1").get(i2).w
                }
            } else {
                let i2 = tables.lookup("en_s2").get(key)
                if i2 >= 0 {
                    w2 = try tables.records("en_s2").get(i2).w
                }
            }

            if let upright = w2 {
                adj = Double(upright - r.w) * scale
            }
        }

        return Glyph(consumed: consumed, tex: r.tex, x: r.x, y: r.y, w: r.w, h: r.h, adj: adj)
    }
}
