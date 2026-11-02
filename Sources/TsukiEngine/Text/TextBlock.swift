import Foundation

/// One 0x30-byte glyph record of a laid-out text block (record i = element i), as the engine writes it
/// (docs/formats/textbox.md 4; tools/tsuki/textbox.py `GlyphRec`).
public struct GlyphRecord: Sendable, Equatable {
    /// Element index.
    public let index: Int
    /// Bit 0 used, bit 1 ruby reading, bit 2 style 1, bit 3 `@a`, bit 16 `@b`, bits 20..22 style.
    public let flags: Int
    /// RGB565 colour word.
    public let color: Int
    /// The `@c6..@c9` value (outline colour selector).
    public let ext: Int
    /// Line index (a ruby reading carries the line of its base).
    public let line: Int
    /// Texture slot (font page = slot - 0x21).
    public let tex: Int
    /// Atlas rectangle left.
    public let x: Int
    /// Atlas rectangle top.
    public let y: Int
    /// Atlas rectangle right, inclusive (`x + w - 1`, 16 bit).
    public let x2: Int
    /// Atlas rectangle bottom, inclusive.
    public let y2: Int
    /// Reveal counter (typewriter position).
    public let ctr: Int
    /// x in the block, canvas units.
    public let dx: Float
    /// y offset from the line top (a ruby reading: -7.04).
    public let dy: Float
    /// Horizontal scale, canvas units per texel.
    public let sx: Float
    /// Vertical scale, canvas units per texel.
    public let sy: Float

    /// Width of the atlas rectangle.
    public var w: Int { x2 - x + 1 }

    /// Height of the atlas rectangle.
    public var h: Int { y2 - y + 1 }

    /// True for a ruby (furigana) reading glyph.
    public var isRuby: Bool { (flags & 2) != 0 }

    public init(
        index: Int,
        flags: Int,
        color: Int,
        ext: Int,
        line: Int,
        tex: Int,
        x: Int,
        y: Int,
        x2: Int,
        y2: Int,
        ctr: Int,
        dx: Float,
        dy: Float,
        sx: Float,
        sy: Float
    ) {
        self.index = index
        self.flags = flags
        self.color = color
        self.ext = ext
        self.line = line
        self.tex = tex
        self.x = x
        self.y = y
        self.x2 = x2
        self.y2 = y2
        self.ctr = ctr
        self.dx = dx
        self.dy = dy
        self.sx = sx
        self.sy = sy
    }
}

/// Result of one `Text_Layout` call: the 0x190-byte block the engine keeps per text block
/// (textbox.md 4; tools/tsuki/textbox.py `TextBlock`).
public final class TextBlock: @unchecked Sendable {
    /// Lines the engine tracks per block (+0x22 / +0x80 / +0x100 arrays).
    public static let lineSlots = 32

    /// Elements (glyphs and controls) found by pass 1, at most 1200.
    public let n: Int
    /// Width argument (+0x02).
    public let widthArg: Int
    /// Height limit (+0x04): drawing stops below y + height.
    public let height: Int
    /// Caller flags (+0x08).
    public let flags: Int
    /// Extra advance per glyph (+0x16).
    public let spacing: Int
    /// Extra space between lines (+0x18).
    public let leading: Int
    /// Effective box width W (VA 0x538F0 or `@f`).
    public let boxWidth: Int
    /// Base glyph scale x (argument / 3, +0x70).
    public let sx: Float
    /// Base glyph scale y (+0x74).
    public let sy: Float
    /// Number of lines (+0x14).
    public let nLines: Int
    /// Line of the last base glyph (+0x20).
    public let lastGlyphLine: Int
    /// Glyph count per line (+0x22, u16 x 32).
    public let lineGlyphs: [UInt16]
    /// Pen position after the last glyph of each line (+0x80, f32 x 32).
    public let lineWidth: [Float]
    /// Height of each line (+0x100, f32 x 32).
    public let lineHeight: [Float]
    /// The glyph records (base glyphs and ruby readings).
    public let records: [GlyphRecord]
    /// Break class of every pass-1 element (1200 bytes, VA 0x178C100).
    public let classes: [UInt8]
    /// English word-length table (1200 entries, VA 0x178C5B0).
    public let wordLen: [UInt16]
    /// Typewriter counter after the text (VA 0x178BB50[block]); -1 for an empty text.
    public let endCtr: Int
    /// The `@y` value (+0x1E).
    public let yField: Int
    /// True when pass 1 found no element: the engine returns 0 and leaves the block untouched.
    public let empty: Bool

    public init(
        n: Int,
        widthArg: Int,
        height: Int,
        flags: Int,
        spacing: Int,
        leading: Int,
        boxWidth: Int,
        sx: Float,
        sy: Float,
        nLines: Int,
        lastGlyphLine: Int,
        lineGlyphs: [UInt16],
        lineWidth: [Float],
        lineHeight: [Float],
        records: [GlyphRecord],
        classes: [UInt8],
        wordLen: [UInt16],
        endCtr: Int,
        yField: Int = 0,
        empty: Bool = false
    ) {
        self.n = n
        self.widthArg = widthArg
        self.height = height
        self.flags = flags
        self.spacing = spacing
        self.leading = leading
        self.boxWidth = boxWidth
        self.sx = sx
        self.sy = sy
        self.nLines = nLines
        self.lastGlyphLine = lastGlyphLine
        self.lineGlyphs = lineGlyphs
        self.lineWidth = lineWidth
        self.lineHeight = lineHeight
        self.records = records
        self.classes = classes
        self.wordLen = wordLen
        self.endCtr = endCtr
        self.yField = yField
        self.empty = empty
    }
}

/// Arguments of `Text_Layout` (VA 0xC6C20); the defaults are those of the ordinary ADV message.
public struct LayoutParams: Sendable, Equatable {
    /// Width argument (474; VA 0x538F0 may widen it).
    public var width: Int
    /// Height limit (220).
    public var height: Int
    /// Extra advance per glyph.
    public var spacing: Int
    /// Extra space between lines (9).
    public var leading: Int
    /// Initial RGB565 colour word.
    public var color: Int
    /// Caller flags: bit 20 starts in style 2 (speech bubbles); 0x40, 0x2000, 0x4000, 0x8000, 0x20000 change the markup handling.
    public var flags: Int
    /// Glyph scale argument x (0.74, divided by 3 by the engine).
    public var sx: Double
    /// Glyph scale argument y.
    public var sy: Double
    /// Text block slot (4..8 and 79..89 are the message slots).
    public var block: Int
    /// F1105 / F1109 window index: 42 selects width 600, below 3 is the "normal window".
    public var window: Int
    /// The `@x` continue position (global VA 0x178BE20).
    public var savedX: Double
    /// Overrides the normal-window predicate (VA 0x53860); nil = window < 3.
    public var normalWindow: Bool?

    public init(
        width: Int = 474,
        height: Int = 220,
        spacing: Int = 0,
        leading: Int = 9,
        color: Int = 0xFFFF,
        flags: Int = 0,
        sx: Double = 0.74,
        sy: Double = 0.74,
        block: Int = 4,
        window: Int = 0,
        savedX: Double = 0.0,
        normalWindow: Bool? = nil
    ) {
        self.width = width
        self.height = height
        self.spacing = spacing
        self.leading = leading
        self.color = color
        self.flags = flags
        self.sx = sx
        self.sy = sy
        self.block = block
        self.window = window
        self.savedX = savedX
        self.normalWindow = normalWindow
    }
}
