import Foundation

/// How plain-text rendering shows a ruby group.
public enum RubyRendering: Sendable {
    /// The base only.
    case drop
    /// `base(reading)`.
    case paren
    /// The source markup `<base|reading>`.
    case markup
}

/// A markup token of a text line (docs/formats/text.md 6). All text stays as the UTF-8 bytes the
/// tokenizer saw, because the engine counts bytes and a code's parameter can split a multi-byte
/// character (never the case in the retail data).
public indirect enum MarkupToken: Equatable, Sendable {
    case text(TextToken)
    case ruby(RubyToken)
    /// A `^` line break.
    case newline
    case icon(IconToken)
    case code(CodeToken)
    case ref(RefToken)
}

/// Plain text. `raw` differs from `text` only for the escapes `@1X` and `@2X`.
public struct TextToken: Equatable, Sendable {
    /// The glyph text.
    public let text: [UInt8]
    /// The source bytes.
    public let raw: [UInt8]

    /// A token whose source bytes are its text.
    public init(_ text: [UInt8]) {
        self.init(text: text, raw: text)
    }

    public init(text: [UInt8], raw: [UInt8]) {
        self.text = text
        self.raw = raw
    }

    /// The text decoded as UTF-8; invalid bytes become U+FFFD.
    public var textString: String { String(decoding: text, as: UTF8.self) }
}

/// A ruby group `<base|reading>` (not parsed for English).
public struct RubyToken: Equatable, Sendable {
    /// Glyph text of the base part (the text tokens inside it, joined).
    public let base: [UInt8]
    /// Glyph text of the reading.
    public let reading: [UInt8]
    /// The group's source bytes.
    public let raw: [UInt8]
    /// Every token inside the base part (codes, newlines and icons are processed inside groups by the engine).
    public let baseTokens: [MarkupToken]
    /// Every token inside the reading.
    public let readingTokens: [MarkupToken]
    /// False when the string ended inside the group.
    public let closed: Bool

    public init(base: [UInt8], reading: [UInt8], raw: [UInt8],
                baseTokens: [MarkupToken], readingTokens: [MarkupToken], closed: Bool) {
        self.base = base
        self.reading = reading
        self.raw = raw
        self.baseTokens = baseTokens
        self.readingTokens = readingTokens
        self.closed = closed
    }
}

/// An inline icon `[name]`.
public struct IconToken: Equatable, Sendable {
    /// The icon name without brackets.
    public let name: String
    /// The icon number (index into `TextRules.iconNames`).
    public let index: Int
    /// The source bytes `[name]`.
    public let raw: [UInt8]

    public init(name: String, index: Int, raw: [UInt8]) {
        self.name = name
        self.index = index
        self.raw = raw
    }
}

/// An `@` control code. `arg` is the parameter text (digits, a number, or a parenthesised group),
/// or nil.
public struct CodeToken: Equatable, Sendable {
    /// The code letter as bytes (empty for a lone `@` at the end, `>` for a swallowed stray close).
    public let code: [UInt8]
    /// The parameter bytes, nil when the code has none.
    public let arg: [UInt8]?
    /// The source bytes.
    public let raw: [UInt8]

    public init(code: [UInt8], arg: [UInt8]?, raw: [UInt8]) {
        self.code = code
        self.arg = arg
        self.raw = raw
    }

    /// The code letter when it is one ASCII character, else the empty string.
    public var letter: String {
        code.count == 1 && code[0] < 0x80 ? String(UnicodeScalar(code[0])) : ""
    }
}

/// A script-level `$NNNNNN` reference (only in script mode).
public struct RefToken: Equatable, Sendable {
    /// The six-digit id.
    public let lineId: Int
    /// The source bytes.
    public let raw: [UInt8]

    public init(lineId: Int, raw: [UInt8]) {
        self.lineId = lineId
        self.raw = raw
    }
}

/// Style state of a run after the control codes before it (docs/formats/text.md 6.2).
public struct MarkupStyle: Equatable, Sendable {
    /// The u16 colour word, nil for the caller's default.
    public var color: Int?
    /// `@c6..@c9` value (glyph field +0x0A).
    public var colorExt: Int
    /// 0 normal, 1 g, 2 z, 3 italic, 4 g and italic, 5 z and italic.
    public var style: Int
    /// `@b`.
    public var flagB: Bool
    /// `@aN`.
    public var anim: Int
    /// `@o` until `@p`.
    public var noWrap: Bool
    /// Width multiplier, nil for the default.
    public var scaleW: Double?
    /// Height multiplier, nil for the default.
    public var scaleH: Double?
    /// `@fN`.
    public var fontMetric: Int?

    public init(color: Int? = nil, colorExt: Int = 0, style: Int = 0, flagB: Bool = false,
                anim: Int = 0, noWrap: Bool = false, scaleW: Double? = nil, scaleH: Double? = nil,
                fontMetric: Int? = nil) {
        self.color = color
        self.colorExt = colorExt
        self.style = style
        self.flagB = flagB
        self.anim = anim
        self.noWrap = noWrap
        self.scaleW = scaleW
        self.scaleH = scaleH
        self.fontMetric = fontMetric
    }
}

/// A styled run (`tsuki.text.Run`).
public struct MarkupRun: Equatable, Sendable {
    /// text, ruby, icon, newline, wait, seq, pos or ref.
    public let kind: String
    /// Run text (a ruby run's base, an icon's name, a pos run's code letter, a ref's source).
    public let text: [UInt8]
    /// The reading of a ruby run.
    public let ruby: [UInt8]
    /// The style in force.
    public let style: MarkupStyle
    /// Icon index, ref id, sequence value or x/y value.
    public let value: Int?
    /// Typewriter sequence index of the first glyph.
    public let seq: Int

    public init(kind: String, text: [UInt8], ruby: [UInt8], style: MarkupStyle, value: Int?, seq: Int) {
        self.kind = kind
        self.text = text
        self.ruby = ruby
        self.style = style
        self.value = value
        self.seq = seq
    }
}
