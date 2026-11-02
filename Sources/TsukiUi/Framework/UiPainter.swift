import Foundation
import TsukiCore
import TsukiEngine

/// Appends the quads of the menus to a `DisplayList` (ARCHITECTURE 9.1): sprites cut from UI sheets (split along the sheet's tiles),
/// fills, and the global alpha and scissor that knife's `fade_quads` and `q.clip` apply to a group of quads. Coordinates are canvas
/// pixels of the 1920 x 1080 frame; helpers in `UiMetrics` convert the 640 x 448 units.
public final class UiPainter {
    private static let blendStates: [Int] = buildBlendStates()

    private var _clips: [PixelRect] = []
    private var _guideHits: [GuideHit] = []
    private var _alpha: Float = 1.0

    /// Creates a painter over the sheets of `assets`.
    public init(_ assets: UiAssets) {
        self.assets = assets
    }

    /// The sheets and tables.
    public let assets: UiAssets
    public var Assets: UiAssets { assets }

    /// How the button prompts are drawn this frame.
    public var promptStyle: PromptStyle = .playStation
    public var PromptStyleVal: PromptStyle { get { promptStyle } set { promptStyle = newValue } }

    private var _keyText: UiText?
    private var _labelText: UiText?

    /// The glyph text drawer of the key caps and the Latin words of the prompts: always the English glyph pages.
    public var keyText: UiText {
        if let t = _keyText { return t }
        let t = UiText(UiAssets(data: assets.data, language: .en))
        _keyText = t
        return t
    }
    public var KeyText: UiText { keyText }

    /// The glyph text drawer of the words of the prompts that are translated: the UI language's own glyph pages.
    public var labelText: UiText {
        if let t = _labelText { return t }
        let t = UiText(assets)
        _labelText = t
        return t
    }
    public var LabelText: UiText { labelText }

    /// The clickable words of the button guide lines drawn since `begin`.
    public var guideHits: [GuideHit] { _guideHits }
    public var GuideHits: [GuideHit] { guideHits }

    public func addGuideHit(_ hit: GuideHit) {
        _guideHits.append(hit)
    }
    public func AddGuideHit(_ hit: GuideHit) { addGuideHit(hit) }

    /// The list being filled.
    public private(set) var list: DisplayList = DisplayList()
    public var List: DisplayList { list }

    /// Quads appended since `begin`.
    public private(set) var quadCount: Int = 0
    public var QuadCount: Int { quadCount }

    /// The factor every draw's alpha is multiplied by.
    public var alpha: Float { _alpha }
    public var Alpha: Float { alpha }

    /// Starts filling `list`: alpha 1, no scissor.
    public func begin(_ list: DisplayList) {
        self.list = list
        _alpha = 1.0
        _clips.removeAll()
        _guideHits.removeAll()
        quadCount = 0
    }
    public func Begin(_ list: DisplayList) { begin(list) }

    @discardableResult
    public func pushAlpha(_ alpha: Float) -> Float {
        let prev = _alpha
        _alpha *= min(max(alpha, 0.0), 1.0)
        return prev
    }

    public func popAlpha(_ prev: Float) {
        _alpha = prev
    }

    public func withAlpha<R>(_ alpha: Float, _ body: () throws -> R) rethrows -> R {
        let prev = pushAlpha(alpha)
        defer { popAlpha(prev) }
        return try body()
    }
    public func WithAlpha<R>(_ alpha: Float, _ body: () throws -> R) rethrows -> R {
        try withAlpha(alpha, body)
    }

    @discardableResult
    public func pushClip(_ rect: RectF) -> Int {
        let count = _clips.count
        var r = PixelRect(
            x: Int(floor(rect.x)),
            y: Int(floor(rect.y)),
            width: Int(ceil(rect.w)),
            height: Int(ceil(rect.h))
        )
        if let o = _clips.last {
            let x0 = max(r.x, o.x)
            let y0 = max(r.y, o.y)
            let x1 = min(r.x + r.width, o.x + o.width)
            let y1 = min(r.y + r.height, o.y + o.height)
            r = PixelRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
        }
        _clips.append(r)
        return count
    }

    public func popClip(_ count: Int) {
        if _clips.count > count {
            _clips.removeSubrange(count..<_clips.count)
        }
    }

    public func withClip<R>(_ rect: RectF, _ body: () throws -> R) rethrows -> R {
        let count = pushClip(rect)
        defer { popClip(count) }
        return try body()
    }
    public func WithClip<R>(_ rect: RectF, _ body: () throws -> R) rethrows -> R {
        try withClip(rect, body)
    }

    /// Draws the part `src` (sheet texels) of `sheet` into `dst` (canvas pixels).
    @discardableResult
    public func sprite(_ sheet: UiSheet, _ src: RectF, _ dst: RectF, alpha: Float = 1.0, blend: UiBlend = .alpha, flipX: Bool = false) -> Bool {
        guard let g = assets.geometry(sheet) else {
            return false
        }
        return drawTiles(g, source: TileSource(set: sheet.set, language: assets.language, a: sheet.child, b: 0, ui: true), src: src, dst: dst, alpha: alpha, blend: blend, flipX: flipX)
    }
    @discardableResult
    public func Sprite(_ sheet: UiSheet, _ src: RectF, _ dst: RectF, _ alpha: Float = 1.0, _ blend: UiBlend = .alpha, _ flipX: Bool = false) -> Bool {
        sprite(sheet, src, dst, alpha: alpha, blend: blend, flipX: flipX)
    }
    @discardableResult
    public func sprite(_ sheet: UiSheet, _ src: RectF, _ dst: RectF, _ alpha: Float, _ blend: UiBlend = .alpha, _ flipX: Bool = false) -> Bool {
        sprite(sheet, src, dst, alpha: alpha, blend: blend, flipX: flipX)
    }
    @discardableResult
    public func sprite(_ sheet: UiSheet, _ dst: RectF, _ alpha: Float, _ blend: UiBlend = .alpha) -> Bool {
        sprite(sheet, dst, alpha: alpha, blend: blend)
    }
    @discardableResult
    public func sprite(_ sheet: UiSheet, _ src: RectF, _ dst: RectF, _ alpha: Float, _ blend: UiBlend = .alpha, flipX: Bool) -> Bool {
        sprite(sheet, src, dst, alpha: alpha, blend: blend, flipX: flipX)
    }

    /// Draws the part `src` of a picture of an image archive into `dst`.
    @discardableResult
    public func picture(_ pic: UiPicture, _ src: RectF, _ dst: RectF, alpha: Float = 1.0, blend: UiBlend = .alpha) -> Bool {
        guard let g = assets.geometry(pic) else {
            return false
        }
        return drawTiles(g, source: TileSource(set: .confParts, language: .ja, a: pic.archive, b: pic.entry, ui: false), src: src, dst: dst, alpha: alpha, blend: blend, flipX: false)
    }
    @discardableResult
    public func Picture(_ pic: UiPicture, _ src: RectF, _ dst: RectF, _ alpha: Float = 1.0, _ blend: UiBlend = .alpha) -> Bool {
        picture(pic, src, dst, alpha: alpha, blend: blend)
    }
    @discardableResult
    public func picture(_ pic: UiPicture, _ src: RectF, _ dst: RectF, _ alpha: Float, _ blend: UiBlend = .alpha) -> Bool {
        picture(pic, src, dst, alpha: alpha, blend: blend)
    }

    /// Draws the whole picture stretched into `dst`.
    @discardableResult
    public func picture(_ pic: UiPicture, _ dst: RectF, alpha: Float = 1.0, blend: UiBlend = .alpha) -> Bool {
        guard let g = assets.geometry(pic) else {
            return false
        }
        return drawTiles(g, source: TileSource(set: .confParts, language: .ja, a: pic.archive, b: pic.entry, ui: false), src: RectF(0, 0, Float(g.width), Float(g.height)), dst: dst, alpha: alpha, blend: blend, flipX: false)
    }
    @discardableResult
    public func Picture(_ pic: UiPicture, _ dst: RectF, _ alpha: Float = 1.0, _ blend: UiBlend = .alpha) -> Bool {
        picture(pic, dst, alpha: alpha, blend: blend)
    }
    @discardableResult
    public func picture(_ pic: UiPicture, _ dst: RectF, _ alpha: Float, _ blend: UiBlend = .alpha) -> Bool {
        picture(pic, dst, alpha: alpha, blend: blend)
    }

    private struct TileSource {
        let set: UiSet
        let language: Language
        let a: Int
        let b: Int
        let ui: Bool

        func tile(_ index: Int) -> TextureRef {
            ui ? TextureRef.uiTile(set: Int(set.rawValue), language: Int(language.rawValue), child: a, tile: index) : TextureRef.pictureTile(archive: a, entry: b, tile: index)
        }
    }

    private func drawTiles(_ g: SheetGeometry, source: TileSource, src: RectF, dst: RectF, alpha: Float, blend: UiBlend, flipX: Bool) -> Bool {
        let a = min(max(alpha, 0.0), 1.0) * _alpha
        if src.isEmpty || dst.isEmpty || a <= 0.0 {
            return true
        }

        let color = Self.pack(a)
        let sx = dst.w / src.w
        let sy = dst.h / src.h

        for t in g.tiles {
            let ix0 = max(src.x, Float(t.x))
            let iy0 = max(src.y, Float(t.y))
            let ix1 = min(src.right, Float(t.x + t.w))
            let iy1 = min(src.bottom, Float(t.y + t.h))
            if ix1 <= ix0 || iy1 <= iy0 {
                continue
            }

            var u0 = (Float(t.sourceX) + (ix0 - Float(t.x))) / Float(t.storedWidth)
            var u1 = (Float(t.sourceX) + (ix1 - Float(t.x))) / Float(t.storedWidth)
            let v0 = (Float(t.sourceY) + (iy0 - Float(t.y))) / Float(t.storedHeight)
            let v1 = (Float(t.sourceY) + (iy1 - Float(t.y))) / Float(t.storedHeight)
            var x0 = dst.x + ((ix0 - src.x) * sx)
            var x1 = dst.x + ((ix1 - src.x) * sx)
            let y0 = dst.y + ((iy0 - src.y) * sy)
            let y1 = dst.y + ((iy1 - src.y) * sy)

            if flipX {
                let newX0 = dst.x + dst.w - (x1 - dst.x)
                let newX1 = dst.x + dst.w - (x0 - dst.x)
                x0 = newX0
                x1 = newX1
                swap(&u0, &u1)
            }

            add(source.tile(t.index), x0: x0, y0: y0, x1: x1, y1: y1, u0: u0, v0: v0, u1: u1, v1: v1, rgba: color, blend: blend)
        }
        return true
    }

    /// Draws a one-tile sheet turned by `radians` about its centre.
    @discardableResult
    public func spriteRotated(_ sheet: UiSheet, _ src: RectF, _ dst: RectF, radians: Float, alpha: Float = 1.0, blend: UiBlend = .alpha) -> Bool {
        guard let g = assets.geometry(sheet) else {
            return false
        }
        let a = min(max(alpha, 0.0), 1.0) * _alpha
        if g.tiles.count != 1 || a <= 0.0 {
            return sprite(sheet, src, dst, alpha: alpha, blend: blend)
        }

        let t = g.tiles[0]
        let u0 = (Float(t.sourceX) + (src.x - Float(t.x))) / Float(t.storedWidth)
        let u1 = (Float(t.sourceX) + (src.right - Float(t.x))) / Float(t.storedWidth)
        let v0 = (Float(t.sourceY) + (src.y - Float(t.y))) / Float(t.storedHeight)
        let v1 = (Float(t.sourceY) + (src.bottom - Float(t.y))) / Float(t.storedHeight)
        let cx = dst.x + (dst.w / 2.0)
        let cy = dst.y + (dst.h / 2.0)
        let cs = cos(radians)
        let sn = sin(radians)

        func vertex(_ dx: Float, _ dy: Float, _ u: Float, _ v: Float) -> Vertex {
            Vertex(x: cx + (dx * cs) - (dy * sn), y: cy + (dx * sn) + (dy * cs), u: u, v: v, rgba: Self.pack(a))
        }

        let hw = dst.w / 2.0
        let hh = dst.h / 2.0
        let effect = Int(blend.rawValue)
        let cmd = DrawCommand(
            kind: .texturedQuad,
            target: 0,
            texture: TextureRef.uiTile(set: Int(sheet.set.rawValue), language: Int(assets.language.rawValue), child: sheet.child, tile: t.index),
            v0: vertex(-hw, -hh, u0, v0),
            v1: vertex(hw, -hh, u1, v0),
            v2: vertex(-hw, hh, u0, v1),
            v3: vertex(hw, hh, u1, v1),
            effectWord: Int16(effect),
            blendState: UInt8(Self.blendStates[effect]),
            clip: _clips.last
        )
        list.add(cmd)
        quadCount += 1
        return true
    }
    @discardableResult
    public func SpriteRotated(_ sheet: UiSheet, _ src: RectF, _ dst: RectF, _ radians: Float, _ alpha: Float = 1.0, _ blend: UiBlend = .alpha) -> Bool {
        spriteRotated(sheet, src, dst, radians: radians, alpha: alpha, blend: blend)
    }
    @discardableResult
    public func spriteRotated(_ sheet: UiSheet, _ src: RectF, _ dst: RectF, _ radians: Float, _ alpha: Float = 1.0, _ blend: UiBlend = .alpha) -> Bool {
        spriteRotated(sheet, src, dst, radians: radians, alpha: alpha, blend: blend)
    }

    /// Draws the whole `sheet` stretched into `dst`.
    @discardableResult
    public func sprite(_ sheet: UiSheet, _ dst: RectF, alpha: Float = 1.0, blend: UiBlend = .alpha) -> Bool {
        guard let g = assets.geometry(sheet) else {
            return false
        }
        return sprite(sheet, RectF(0, 0, Float(g.width), Float(g.height)), dst, alpha: alpha, blend: blend)
    }
    @discardableResult
    public func Sprite(_ sheet: UiSheet, _ dst: RectF, _ alpha: Float = 1.0, _ blend: UiBlend = .alpha) -> Bool {
        sprite(sheet, dst, alpha: alpha, blend: blend)
    }

    /// Draws a cell of a sheet at (x, y) in its own size.
    @discardableResult
    public func spriteAt(_ sheet: UiSheet, _ src: RectF, _ x: Float, _ y: Float, alpha: Float = 1.0, blend: UiBlend = .alpha) -> Bool {
        sprite(sheet, src, RectF(x, y, src.w, src.h), alpha: alpha, blend: blend)
    }
    @discardableResult
    public func SpriteAt(_ sheet: UiSheet, _ src: RectF, _ x: Float, _ y: Float, _ alpha: Float = 1.0, _ blend: UiBlend = .alpha) -> Bool {
        spriteAt(sheet, src, x, y, alpha: alpha, blend: blend)
    }

    /// Draws the whole sheet at (x, y) in its own size.
    @discardableResult
    public func spriteAt(_ sheet: UiSheet, _ x: Float, _ y: Float, alpha: Float = 1.0, blend: UiBlend = .alpha) -> Bool {
        guard let g = assets.geometry(sheet) else {
            return false
        }
        return sprite(sheet, RectF(0, 0, Float(g.width), Float(g.height)), RectF(x, y, Float(g.width), Float(g.height)), alpha: alpha, blend: blend)
    }
    @discardableResult
    public func SpriteAt(_ sheet: UiSheet, _ x: Float, _ y: Float, _ alpha: Float = 1.0, _ blend: UiBlend = .alpha) -> Bool {
        spriteAt(sheet, x, y, alpha: alpha, blend: blend)
    }

    /// The size of a picture in texels, or (0, 0) when it does not exist.
    public func sizeOf(_ pic: UiPicture) -> (w: Int, h: Int) {
        guard let g = assets.geometry(pic) else { return (0, 0) }
        return (g.width, g.height)
    }
    public func SizeOf(_ pic: UiPicture) -> (w: Int, h: Int) { sizeOf(pic) }

    /// The size of a sheet in texels, or (0, 0) when it does not exist.
    public func sizeOf(_ sheet: UiSheet) -> (w: Int, h: Int) {
        guard let g = assets.geometry(sheet) else { return (0, 0) }
        return (g.width, g.height)
    }
    public func SizeOf(_ sheet: UiSheet) -> (w: Int, h: Int) { sizeOf(sheet) }

    /// Fills `dst` with a colour (components 0..1) at alpha `a`.
    public func fill(_ dst: RectF, r: Float, g: Float, b: Float, a: Float, blend: UiBlend = .alpha) {
        let al = min(max(a, 0.0), 1.0) * _alpha
        if dst.isEmpty || al <= 0.0 {
            return
        }

        let bgr = (UInt32(round(min(max(b, 0.0), 1.0) * 255.0)) << 16) | (UInt32(round(min(max(g, 0.0), 1.0) * 255.0)) << 8) | UInt32(round(min(max(r, 0.0), 1.0) * 255.0))
        add(.none, x0: dst.x, y0: dst.y, x1: dst.right, y1: dst.bottom, u0: 0, v0: 0, u1: 0, v1: 0, rgba: Self.pack(al, bgr: bgr), blend: blend)
    }
    public func Fill(_ dst: RectF, _ r: Float, _ g: Float, _ b: Float, _ a: Float, _ blend: UiBlend = .alpha) {
        fill(dst, r: r, g: g, b: b, a: a, blend: blend)
    }

    /// Fills a rectangle with rounded corners of `radius` pixels.
    public func fillRounded(_ dst: RectF, radius: Float, r: Float, g: Float, b: Float, a: Float, smooth: Bool = true) {
        let al = min(max(a, 0.0), 1.0) * _alpha
        if dst.isEmpty || al <= 0.0 {
            return
        }

        let x0 = round(dst.x)
        let y0 = round(dst.y)
        let w = max(1.0, round(dst.right) - x0)
        let h = max(1.0, round(dst.bottom) - y0)
        let rad = Int(min(round(radius), floor(min(w, h) / 2.0)))
        let bgr = (UInt32(round(min(max(b, 0.0), 1.0) * 255.0)) << 16) | (UInt32(round(min(max(g, 0.0), 1.0) * 255.0)) << 8) | UInt32(round(min(max(r, 0.0), 1.0) * 255.0))

        func span(_ sx: Float, _ sy: Float, _ sw: Float, _ sh: Float, _ coverage: Float) {
            if sw > 0.0 && sh > 0.0 && coverage > 0.0 {
                add(.none, x0: sx, y0: sy, x1: sx + sw, y1: sy + sh, u0: 0, v0: 0, u1: 0, v1: 0, rgba: Self.pack(al * coverage, bgr: bgr), blend: .alpha)
            }
        }

        if rad <= 0 {
            span(x0, y0, w, h, 1.0)
            return
        }

        // the middle rows between the two corner bands
        span(x0, y0 + Float(rad), w, h - Float(2 * rad), 1.0)

        for i in 0..<rad {
            let dy = Float(rad - i) - 0.5
            let inset = Float(rad) - sqrt(max(0.0, Float(rad * rad) - (dy * dy)))
            var whole = smooth ? ceil(inset) : round(inset)
            var edge = smooth ? whole - inset : 0.0
            if edge >= 0.85 {
                whole -= 1.0
                edge = 0.0
            } else if edge < 0.15 {
                edge = 0.0
            }

            func row(_ y: Float) {
                span(x0 + whole, y, w - (2.0 * whole), 1.0, 1.0)
                if edge > 0.0 {
                    span(x0 + whole - 1.0, y, 1.0, 1.0, edge)
                    span(x0 + w - whole, y, 1.0, 1.0, edge)
                }
            }

            row(y0 + Float(i))
            row(y0 + h - 1.0 - Float(i))
        }
    }
    public func FillRounded(_ dst: RectF, _ radius: Float, _ r: Float, _ g: Float, _ b: Float, _ a: Float, _ smooth: Bool = true) {
        fillRounded(dst, radius: radius, r: r, g: g, b: b, a: a, smooth: smooth)
    }

    /// Covers the whole frame with `gray` at alpha `a`.
    public func cover(_ a: Float, gray: Float = 0.0) {
        fill(UiMetrics.screen, r: gray, g: gray, b: gray, a: a)
    }
    public func Cover(_ a: Float, _ gray: Float = 0.0) { cover(a, gray: gray) }
    public func cover(_ a: Float, _ gray: Float) { cover(a, gray: gray) }

    /// Appends a quad with final canvas positions.
    public func quad(_ texture: TextureRef, _ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, _ u0: Float, _ v0: Float, _ u1: Float, _ v1: Float, _ rgba: UInt32, blend: UiBlend = .alpha) {
        let a = UInt32(round(Float(rgba >> 24) * _alpha))
        add(texture, x0: x0, y0: y0, x1: x1, y1: y1, u0: u0, v0: v0, u1: u1, v1: v1, rgba: (rgba & 0xFFFFFF) | (a << 24), blend: blend)
    }
    public func Quad(_ texture: TextureRef, _ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, _ u0: Float, _ v0: Float, _ u1: Float, _ v1: Float, _ rgba: UInt32, _ blend: UiBlend = .alpha) {
        quad(texture, x0, y0, x1, y1, u0, v0, u1, v1, rgba, blend: blend)
    }

    /// Draws the thumbnail of save slot `slot` into `dst`.
    public func thumbnail(_ slot: Int, version: Int, dst: RectF, alpha: Float = 1.0) {
        let a = min(max(alpha, 0.0), 1.0) * _alpha
        if !dst.isEmpty && a > 0.0 {
            add(TextureRef.thumbnail(slot: slot, version: version), x0: dst.x, y0: dst.y, x1: dst.right, y1: dst.bottom, u0: 0.0, v0: 0.0, u1: 1.0, v1: 1.0, rgba: Self.pack(a), blend: .alpha)
        }
    }
    public func Thumbnail(_ slot: Int, _ version: Int, _ dst: RectF, _ alpha: Float = 1.0) {
        thumbnail(slot, version: version, dst: dst, alpha: alpha)
    }

    /// Draws the part `src` of the run-time picture `id` into `dst`.
    @discardableResult
    public func composed(_ id: Int, src: RectF, dst: RectF, alpha: Float = 1.0, blend: UiBlend = .alpha) -> Bool {
        guard let pic = assets.composed(id) else {
            return false
        }
        let a = min(max(alpha, 0.0), 1.0) * _alpha
        if src.isEmpty || dst.isEmpty || a <= 0.0 {
            return true
        }
        add(
            TextureRef.uiComposed(id: id, language: Int(assets.language.rawValue)),
            x0: dst.x, y0: dst.y, x1: dst.right, y1: dst.bottom,
            u0: src.x / Float(pic.width), v0: src.y / Float(pic.height),
            u1: src.right / Float(pic.width), v1: src.bottom / Float(pic.height),
            rgba: Self.pack(a), blend: blend
        )
        return true
    }
    @discardableResult
    public func composed(_ id: Int, _ src: RectF, _ dst: RectF, _ alpha: Float = 1.0, _ blend: UiBlend = .alpha) -> Bool {
        composed(id, src: src, dst: dst, alpha: alpha, blend: blend)
    }
    @discardableResult
    public func Composed(_ id: Int, _ src: RectF, _ dst: RectF, _ alpha: Float = 1.0, _ blend: UiBlend = .alpha) -> Bool {
        composed(id, src: src, dst: dst, alpha: alpha, blend: blend)
    }

    /// Packs alpha (0..1) and 0xBBGGRR colour bytes into a vertex colour.
    public static func pack(_ alpha: Float, bgr: UInt32 = 0xFFFFFF) -> UInt32 {
        (UInt32(round(min(max(alpha, 0.0), 1.0) * 255.0)) << 24) | (bgr & 0xFFFFFF)
    }
    public static func Pack(_ alpha: Float, _ bgr: UInt32 = 0xFFFFFF) -> UInt32 {
        pack(alpha, bgr: bgr)
    }

    private func add(_ texture: TextureRef, x0: Float, y0: Float, x1: Float, y1: Float, u0: Float, v0: Float, u1: Float, v1: Float, rgba: UInt32, blend: UiBlend) {
        let effect = Int(blend.rawValue)
        let cmd = DrawCommand(
            kind: texture.kind == .none ? .fillQuad : .texturedQuad,
            target: 0,
            texture: texture,
            v0: Vertex(x: x0, y: y0, u: u0, v: v0, rgba: rgba),
            v1: Vertex(x: x1, y: y0, u: u1, v: v0, rgba: rgba),
            v2: Vertex(x: x0, y: y1, u: u0, v: v1, rgba: rgba),
            v3: Vertex(x: x1, y: y1, u: u1, v: v1, rgba: rgba),
            effectWord: Int16(effect),
            blendState: UInt8(Self.blendStates[effect]),
            clip: _clips.last
        )
        list.add(cmd)
        quadCount += 1
    }

    private static func buildBlendStates() -> [Int] {
        var b = [Int](repeating: 1, count: 26)
        b.append(contentsOf: [6, 1, 1, 6])
        b.append(contentsOf: [Int](repeating: 1, count: 22))
        b.append(contentsOf: [2, 7, 1, 10, 11, 5, 4, 9, 1, 1, 1, 2, 1, 13, 1, 1])
        return b
    }
}

public extension TextureRef {
    static func forMovieFrame(_ slot: UInt8) -> TextureRef {
        movieFrame(Int(slot))
    }
    static func forMovieFrame(_ slot: Int) -> TextureRef {
        movieFrame(slot)
    }
}
