import Foundation

/// Kind of a draw command: the PS4 display-list record types (docs/formats/compositing.md 6).
/// Draw-mode, nested-list and projection records are folded into each command, which carries its
/// own effect word, resolved blend state and already projected vertices.
public enum DrawKind: UInt8, Sendable {
    case texturedQuad = 1
    /// Copies the whole current render target into capture surface `texture.a` without switching targets.
    case capture = 6
    case fillQuad = 7
    /// Clears `target` to the colour of `v0.rgba`; not a PS4 record (offscreen mask/scratch clears).
    case clear = 8
}

/// Shader variants that are additive to the PS4 record set (package K7).
public enum QuadPass: UInt8, Sendable {
    case none = 0
    /// STRA heat haze: uv displaced by two waves along v. `a0..a3` are x terms, `b0..b3` y terms;
    /// wave coordinate is `a3 + b3 * uv.y`.
    case haze = 1
    /// Rule-mask transition; `a0, a1, a2` = lo, hi, invert.
    case rule = 2
    /// One separable gaussian blur pass: uv + (a0, a1) * k for k in -a3...a3, `a2` = sigma in taps.
    case blur = 3
}

/// Optional shader inputs of a quad. The default changes nothing.
public struct QuadFx: Equatable, Sendable {
    public var pass: QuadPass
    /// 0 for none, else the render target whose alpha multiplies the quad's alpha.
    public var mask: UInt8
    public var nearest: Bool
    public var a0: Float
    public var a1: Float
    public var a2: Float
    public var a3: Float
    public var b0: Float
    public var b1: Float
    public var b2: Float
    public var b3: Float

    public init(pass: QuadPass = .none, mask: UInt8 = 0, nearest: Bool = false,
                a0: Float = 0, a1: Float = 0, a2: Float = 0, a3: Float = 0,
                b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0) {
        self.pass = pass
        self.mask = mask
        self.nearest = nearest
        self.a0 = a0
        self.a1 = a1
        self.a2 = a2
        self.a3 = a3
        self.b0 = b0
        self.b1 = b1
        self.b2 = b2
        self.b3 = b3
    }

    public static func forRule(lo: Float, hi: Float, invert: Float, mask: UInt8 = 0) -> QuadFx {
        QuadFx(pass: .rule, mask: mask, a0: lo, a1: hi, a2: invert)
    }

    public static func masked(_ target: UInt8) -> QuadFx {
        QuadFx(mask: target)
    }
}

/// What a `TextureRef` points at. Addresses are game ids, resolved by the producer.
public enum TextureKind: UInt8, Sendable {
    case none = 0
    /// a = archive, b = entry, c = tile, d = colour-effect key.
    case pictureTile = 1
    /// a = UI set, b = language, c = child, d = tile.
    case uiTile = 2
    /// a = language, b = page.
    case glyphPage = 3
    /// a = capture surface 0..15.
    case capture = 4
    /// a = movie slot.
    case movieFrame = 5
    /// a = save slot, b = version.
    case thumbnail = 6
    /// a = composed picture id, b = language, c = version.
    case uiComposed = 7
}

public struct TextureRef: Equatable, Sendable {
    public var kind: TextureKind
    public var a: Int32
    public var b: Int32
    public var c: Int32
    public var d: Int32

    public init(kind: TextureKind = .none, a: Int32 = 0, b: Int32 = 0, c: Int32 = 0, d: Int32 = 0) {
        self.kind = kind
        self.a = a
        self.b = b
        self.c = c
        self.d = d
    }

    public static let none = TextureRef()

    public static func pictureTile(archive: Int, entry: Int, tile: Int, colourEffect: Int = 0) -> TextureRef {
        TextureRef(kind: .pictureTile, a: Int32(archive), b: Int32(entry), c: Int32(tile), d: Int32(colourEffect))
    }

    public static func uiTile(set: Int, language: Int, child: Int, tile: Int) -> TextureRef {
        TextureRef(kind: .uiTile, a: Int32(set), b: Int32(language), c: Int32(child), d: Int32(tile))
    }

    public static func glyphPage(language: Int, page: Int) -> TextureRef {
        TextureRef(kind: .glyphPage, a: Int32(language), b: Int32(page))
    }

    public static func capture(_ surface: Int) -> TextureRef {
        TextureRef(kind: .capture, a: Int32(surface))
    }

    public static func movieFrame(_ slot: Int) -> TextureRef {
        TextureRef(kind: .movieFrame, a: Int32(slot))
    }

    public static func thumbnail(slot: Int, version: Int) -> TextureRef {
        TextureRef(kind: .thumbnail, a: Int32(slot), b: Int32(version))
    }

    public static func uiComposed(id: Int, language: Int, version: Int = 0) -> TextureRef {
        TextureRef(kind: .uiComposed, a: Int32(id), b: Int32(language), c: Int32(version))
    }
}

/// One quad vertex: position in 1920 x 1080 pixels, uv, and packed RGBA (r in bits 0-7, a in 24-31).
public struct Vertex: Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var u: Float
    public var v: Float
    public var rgba: UInt32

    public init(x: Float, y: Float, u: Float, v: Float, rgba: UInt32) {
        self.x = x
        self.y = y
        self.u = u
        self.v = v
        self.rgba = rgba
    }
}

/// One display-list command (ARCHITECTURE 3.2, 6.1; docs/formats/compositing.md 4-6).
public struct DrawCommand: Equatable, Sendable {
    public var kind: DrawKind
    /// 0 is the 1920 x 1080 frame; other values are offscreen surfaces.
    public var target: UInt8
    public var texture: TextureRef
    public var v0: Vertex
    public var v1: Vertex
    public var v2: Vertex
    public var v3: Vertex
    public var effectWord: Int16
    /// Fixed-function blend state 0..13, resolved from the effect word (compositing.md 4.1, 5.1).
    public var blendState: UInt8
    public var clip: PixelRect?
    public var fx: QuadFx

    public init(kind: DrawKind, target: UInt8 = 0, texture: TextureRef = .none,
                v0: Vertex = Vertex(x: 0, y: 0, u: 0, v: 0, rgba: 0xFFFFFFFF),
                v1: Vertex = Vertex(x: 0, y: 0, u: 0, v: 0, rgba: 0xFFFFFFFF),
                v2: Vertex = Vertex(x: 0, y: 0, u: 0, v: 0, rgba: 0xFFFFFFFF),
                v3: Vertex = Vertex(x: 0, y: 0, u: 0, v: 0, rgba: 0xFFFFFFFF),
                effectWord: Int16 = 0, blendState: UInt8 = 0,
                clip: PixelRect? = nil, fx: QuadFx = QuadFx()) {
        self.kind = kind
        self.target = target
        self.texture = texture
        self.v0 = v0
        self.v1 = v1
        self.v2 = v2
        self.v3 = v3
        self.effectWord = effectWord
        self.blendState = blendState
        self.clip = clip
        self.fx = fx
    }
}

/// The commands of one 60 Hz step in PS4 order. Filled by its producer, then sealed; a sealed list
/// is immutable.
public final class DisplayList {
    public private(set) var frame: Int64 = -1
    public private(set) var isSealed = false
    public private(set) var commands: [DrawCommand] = []
    private var capacity: Int

    public init(capacity: Int = 256) {
        precondition(capacity >= 1)
        self.capacity = capacity
        commands.reserveCapacity(capacity)
    }

    public func reset(frame: Int64) {
        commands.removeAll(keepingCapacity: true)
        self.frame = frame
        isSealed = false
    }

    public func add(_ command: DrawCommand) {
        precondition(!isSealed, "the display list is sealed")
        commands.append(command)
    }

    public func seal() {
        isSealed = true
    }
}

/// Double buffer of display lists: the logic step fills the back list and publishes it; the
/// executor draws the newest published list. Both run on the main thread.
public final class DisplayListBuffer {
    private var front = DisplayList()
    private var back = DisplayList()

    public init() {
        front.seal()
    }

    public var current: DisplayList { front }

    public func beginFrame(_ frame: Int64) -> DisplayList {
        back.reset(frame: frame)
        return back
    }

    public func publish() {
        back.seal()
        swap(&front, &back)
    }
}
