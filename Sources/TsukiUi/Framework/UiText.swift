import Foundation
import TsukiCore
import TsukiEngine

/// How a block of UI text is laid out and where its coordinates live (docs/research/text_vertical_scale.md 1): the canvas that maps text units to
/// pixels, the layout arguments of `Text_Layout`, and the draw flags of the block draw.
public struct TextStyle: Hashable, Sendable {
    public var canvasW: Double
    public var canvasH: Double
    public var sx: Double
    public var sy: Double
    public var width: Int
    public var height: Int
    public var leading: Int
    public var spacing: Int
    public var colour: Int
    public var drawFlags: Int

    public var CanvasW: Double { canvasW }
    public var CanvasH: Double { canvasH }
    public var Sx: Double { sx }
    public var Sy: Double { sy }
    public var Width: Int { width }
    public var Height: Int { height }
    public var Leading: Int { leading }
    public var Spacing: Int { spacing }
    public var Colour: Int { colour }
    public var DrawFlags: Int { drawFlags }

    public init(
        canvasW: Double = 640,
        canvasH: Double = 448,
        sx: Double = 0.74,
        sy: Double = 0.74,
        width: Int = 474,
        height: Int = 220,
        leading: Int = 9,
        spacing: Int = 0,
        colour: Int = 0xFFFF,
        drawFlags: Int = BlockDraw.always | BlockDraw.outline
    ) {
        self.canvasW = canvasW
        self.canvasH = canvasH
        self.sx = sx
        self.sy = sy
        self.width = width
        self.height = height
        self.leading = leading
        self.spacing = spacing
        self.colour = colour
        self.drawFlags = drawFlags
    }

    /// RGB565 white.
    public static let white: Int = 0xFFFF
    public static let White: Int = white

    /// RGB565 of the choice cursor line (112, 248, 248).
    public static let cyan: Int = 0x77FF
    public static let Cyan: Int = cyan

    /// RGB565 black.
    public static let black: Int = 0x0000
    public static let Black: Int = black

    /// The RGB565 word of an 8-bit colour.
    public static func rgb565(_ r: Int, _ g: Int, _ b: Int) -> Int {
        ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
    }
    public static func Rgb565(_ r: Int, _ g: Int, _ b: Int) -> Int { rgb565(r, g, b) }

    /// A style for text on a 640 x 448 canvas from knife's slot scale (a, b).
    public static func slot(_ a: Double, _ b: Double) -> TextStyle {
        TextStyle(canvasW: 640, canvasH: 448, sx: a, sy: b * (448.0 / 360.0), width: 474, height: 220, leading: 9, spacing: 0, colour: white, drawFlags: BlockDraw.always | BlockDraw.outline)
    }
    public static func Slot(_ a: Double, _ b: Double) -> TextStyle { slot(a, b) }

    /// A square-glyph style (`slot` with equal factors).
    public static func menu(_ a: Double) -> TextStyle {
        slot(a, a)
    }
    public static func Menu(_ a: Double) -> TextStyle { menu(a) }
}

private struct TextCacheKey: Hashable {
    let text: String
    let language: Language
    let style: TextStyle
}

/// Draws `ui_text` strings with the game's glyph pages: the bit-exact `TextLayout` and `BlockDraw` of the message
/// window, converted to quads of the display list. Layouts are cached per string and style.
public final class UiText {
    private let assets: UiAssets
    private let lock = NSLock()
    private var cache: [TextCacheKey: TextBlock] = [:]

    /// Creates a text drawer over `assets` (the fonts come from its tables).
    public init(_ assets: UiAssets) {
        self.assets = assets
    }

    /// Lays out `text` (`^` breaks lines).
    public func layout(_ text: String, _ style: TextStyle) -> TextBlock {
        lock.lock()
        let key = TextCacheKey(text: text, language: assets.language, style: style)
        if let block = cache[key] {
            lock.unlock()
            return block
        }
        if cache.count > 512 {
            cache.removeAll()
        }
        lock.unlock()

        let p = LayoutParams(
            width: style.width,
            height: style.height,
            spacing: style.spacing,
            leading: style.leading,
            color: style.colour,
            flags: 0,
            sx: style.sx,
            sy: style.sy,
            block: 100
        )
        let bytes = Array(text.utf8)
        let block = (try? TextLayout.layout(bytes, assets.language, assets.tables.fonts, p)) ?? TextBlock(
            n: 0, widthArg: style.width, height: style.height, flags: 0, spacing: style.spacing, leading: style.leading,
            boxWidth: style.width, sx: Float(style.sx), sy: Float(style.sy), nLines: 0, lastGlyphLine: 0,
            lineGlyphs: [], lineWidth: [], lineHeight: [], records: [], classes: [], wordLen: [], endCtr: 0, empty: true
        )

        lock.lock()
        cache[key] = block
        lock.unlock()
        return block
    }
    public func Layout(_ text: String, _ style: TextStyle) -> TextBlock {
        layout(text, style)
    }

    /// Lays out raw message bytes (with their markup) in text block slot `block`.
    public func layout(_ text: [UInt8], _ style: TextStyle, block: Int) -> TextBlock {
        let p = LayoutParams(
            width: style.width,
            height: style.height,
            spacing: style.spacing,
            leading: style.leading,
            color: style.colour,
            flags: 0,
            sx: style.sx,
            sy: style.sy,
            block: block
        )
        return (try? TextLayout.layout(text, assets.language, assets.tables.fonts, p)) ?? TextBlock(
            n: 0, widthArg: style.width, height: style.height, flags: 0, spacing: style.spacing, leading: style.leading,
            boxWidth: style.width, sx: Float(style.sx), sy: Float(style.sy), nLines: 0, lastGlyphLine: 0,
            lineGlyphs: [], lineWidth: [], lineHeight: [], records: [], classes: [], wordLen: [], endCtr: 0, empty: true
        )
    }
    public func layout(_ text: [UInt8], _ style: TextStyle, _ block: Int) -> TextBlock {
        layout(text, style, block: block)
    }
    public func Layout(_ text: [UInt8], _ style: TextStyle, _ block: Int) -> TextBlock {
        layout(text, style, block: block)
    }

    /// The pen width in units of the widest line of `text`.
    public func width(_ text: String, _ style: TextStyle) -> Float {
        let b = layout(text, style)
        var w: Float = 0.0
        for i in 0..<min(b.nLines, TextBlock.lineSlots) {
            if i < b.lineWidth.count {
                w = max(w, b.lineWidth[i])
            }
        }
        return w
    }
    public func Width(_ text: String, _ style: TextStyle) -> Float {
        width(text, style)
    }

    /// The horizontal extent of the glyph quads that drawing `text` with `style` at x = 0 emits, in canvas pixels.
    public func inkSpan(_ text: String, _ style: TextStyle) -> (left: Float, right: Float) {
        let block = layout(text, style)
        if block.empty {
            return (0.0, 0.0)
        }

        let quads = BlockDraw.blockQuads(block, 0.0, 0.0, drawFlags: style.drawFlags, alpha: 1.0, head: BlockDraw.revealAll, tail: BlockDraw.revealAll, textFade: 1.0, outlineOption: true, instantOption: false, lang: assets.language)
        let kx = Float(UiMetrics.width / Float(style.canvasW))
        var left = Float.greatestFiniteMagnitude
        var right = -Float.greatestFiniteMagnitude
        for q in quads {
            if q.tex - 0x21 < 0 {
                continue
            }
            let px = Float(q.x) * kx
            left = min(left, px)
            right = max(right, px + Float(q.u1 - q.u0 + 1) * Float(q.sx) * kx)
        }
        return left > right ? (0.0, 0.0) : (left, right)
    }
    public func InkSpan(_ text: String, _ style: TextStyle) -> (left: Float, right: Float) {
        inkSpan(text, style)
    }

    /// The height in units of the laid-out lines (line heights plus leading).
    public func height(_ text: String, _ style: TextStyle) -> Float {
        let b = layout(text, style)
        var h: Float = 0.0
        for i in 0..<min(b.nLines, TextBlock.lineSlots) {
            if i < b.lineHeight.count {
                h += b.lineHeight[i] + Float(b.leading)
            }
        }
        return h
    }
    public func Height(_ text: String, _ style: TextStyle) -> Float {
        height(text, style)
    }

    /// Draws `text` with its first line's top-left at (x, y) in units of the style's canvas.
    @discardableResult
    public func draw(_ p: UiPainter, _ text: String, _ style: TextStyle, _ x: Float, _ y: Float, _ alpha: Float = 1.0, _ head: Double = BlockDraw.revealAll, _ tail: Double = BlockDraw.revealAll) -> Int {
        if text.isEmpty || alpha <= 0.0 {
            return 0
        }
        return drawBlock(p, layout(text, style), style, x, y, alpha, head, tail)
    }
    @discardableResult
    public func Draw(_ p: UiPainter, _ text: String, _ style: TextStyle, _ x: Float, _ y: Float, _ alpha: Float = 1.0, _ head: Double = BlockDraw.revealAll, _ tail: Double = BlockDraw.revealAll) -> Int {
        draw(p, text, style, x, y, alpha, head, tail)
    }
    @discardableResult
    public func draw(_ p: UiPainter, _ text: String, _ style: TextStyle, _ x: Float, _ y: Float, _ alpha: Float = 1.0, count: Float, edge: Float) -> Int {
        draw(p, text, style, x, y, alpha, Double(count), Double(edge))
    }

    /// Draws a one-line label of the game's glyph font centred on a point, with a soft glow.
    @discardableResult
    public func drawGlowLabel(
        _ p: UiPainter,
        _ text: String,
        _ style: TextStyle,
        _ centreX: Float,
        _ topY: Float,
        _ fill: (r: Int, g: Int, b: Int),
        _ glow: (r: Int, g: Int, b: Int),
        _ alpha: Float,
        _ glowAlpha: Float
    ) -> Int {
        let block = layout(text, style)
        if block.empty || alpha <= 0.0 {
            return 0
        }

        let kx = Float(UiMetrics.width / Float(style.canvasW))
        let ky = Float(UiMetrics.height / Float(style.canvasH))
        let (left, right) = inkSpan(text, style)
        let shift = centreX - ((left + right) / 2.0)
        let quads = BlockDraw.blockQuads(block, 0.0, 0.0, drawFlags: BlockDraw.always, alpha: 1.0, head: BlockDraw.revealAll, tail: BlockDraw.revealAll, textFade: 1.0, outlineOption: true, instantOption: false, lang: assets.language)

        var around: [(dx: Float, dy: Float)] = [(0.0, 0.0)]
        for radius: Float in [2.0, 4.0, 6.0] {
            for k in 0..<8 {
                let angle = Float(k) * .pi / 4.0
                around.append((radius * cos(angle), radius * sin(angle)))
            }
        }

        let glowColour = UInt32(glow.r | (glow.g << 8) | (glow.b << 16))
        let fillColour = UInt32(fill.r | (fill.g << 8) | (fill.b << 16))
        var n = 0

        for glowPass in [true, false] {
            for q in quads {
                let page = q.tex - 0x21
                if page < 0 || q.kind != .fill {
                    continue
                }

                let w = Float(q.u1 - q.u0 + 1) * Float(q.sx) * kx
                let h = Float(q.v1 - q.v0 + 1) * Float(q.sy) * ky
                let px = (Float(q.x) * kx) + shift
                let py = (Float(q.y) * ky) + topY
                let tex = TextureRef.glyphPage(language: Int(assets.language.rawValue), page: page)
                let u0 = Float(q.u0) / 1024.0
                let v0 = Float(q.v0) / 1024.0
                let u1 = Float(q.u1 + 1) / 1024.0
                let v1 = Float(q.v1 + 1) / 1024.0

                if glowPass {
                    let rgba = UiPainter.pack(glowAlpha * alpha, bgr: glowColour)
                    for offset in around {
                        p.quad(tex, px + offset.dx, py + offset.dy, px + offset.dx + w, py + offset.dy + h, u0, v0, u1, v1, rgba)
                        n += 1
                    }
                } else {
                    p.quad(tex, px, py, px + w, py + h, u0, v0, u1, v1, UiPainter.pack(alpha, bgr: fillColour))
                    n += 1
                }
            }
        }

        return n
    }
    @discardableResult
    public func DrawGlowLabel(
        _ p: UiPainter,
        _ text: String,
        _ style: TextStyle,
        _ centreX: Float,
        _ topY: Float,
        _ fill: (r: Int, g: Int, b: Int),
        _ glow: (r: Int, g: Int, b: Int),
        _ alpha: Float,
        _ glowAlpha: Float
    ) -> Int {
        drawGlowLabel(p, text, style, centreX, topY, fill, glow, alpha, glowAlpha)
    }

    /// Draws a laid-out block with its first line's top-left at (x, y) in units of the style's canvas.
    @discardableResult
    public func drawBlock(_ p: UiPainter, _ block: TextBlock, _ style: TextStyle, _ x: Float, _ y: Float, _ alpha: Float = 1.0, _ head: Double = BlockDraw.revealAll, _ tail: Double = BlockDraw.revealAll) -> Int {
        if block.empty || alpha <= 0.0 {
            return 0
        }

        let quads = BlockDraw.blockQuads(block, x, y, drawFlags: style.drawFlags, alpha: Double(alpha), head: head, tail: tail, textFade: 1.0, outlineOption: true, instantOption: false, lang: assets.language)
        let kx = Float(UiMetrics.width / Float(style.canvasW))
        let ky = Float(UiMetrics.height / Float(style.canvasH))
        var n = 0
        for q in quads {
            let page = q.tex - 0x21
            if page < 0 {
                continue
            }

            let w = Float(q.u1 - q.u0 + 1) * Float(q.sx) * kx
            let h = Float(q.v1 - q.v0 + 1) * Float(q.sy) * ky
            let px = Float(q.x) * kx
            let py = Float(q.y) * ky
            let rgba = UiPainter.pack(Float(min(max(q.alpha, 0.0), 1.0)), bgr: UInt32(q.r | (q.g << 8) | (q.b << 16)))
            p.quad(
                TextureRef.glyphPage(language: Int(assets.language.rawValue), page: page),
                px, py, px + w, py + h,
                Float(q.u0) / 1024.0, Float(q.v0) / 1024.0, Float(q.u1 + 1) / 1024.0, Float(q.v1 + 1) / 1024.0,
                rgba
            )
            n += 1
        }
        return n
    }
    @discardableResult
    public func DrawBlock(_ p: UiPainter, _ block: TextBlock, _ style: TextStyle, _ x: Float, _ y: Float, _ alpha: Float = 1.0, _ head: Double = BlockDraw.revealAll, _ tail: Double = BlockDraw.revealAll) -> Int {
        drawBlock(p, block, style, x, y, alpha, head, tail)
    }
}
