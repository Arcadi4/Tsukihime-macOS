import Foundation

/// What the quad draw 0xD2BE0 and DisplaySurface_Draw 0xF12F0 derive from a draw-mode word:
/// effect id, 0x100 flag, shader mode (+0x608), strength (+0x60C), blend state (+0x518) and P2 (+0x604).
public struct DrawEffect: Equatable, Sendable {
    public let e: Int
    public let flag: Bool
    public let shaderMode: Int
    public let strength: Float
    public let blendState: Int
    public let p2: Float

    // 0x2D5978, index e-1 (shader mode)
    private static let effectMode: [Int] = [
        1, 2, 0, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25,
        0, 1, 2, 0, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25,
    ]

    // 0x2D55E0, index e (blend state): 26 x 1, 6, 1, 1, 6, 22 x 1, then effects 52..67
    private static let effectBlendState: [Int] = buildBlendState()

    // 0xA1A800286A0: effects whose 0x100 flag turns blending off (0xD9FB9)
    private static let flagSet: UInt64 = 0xA1A800286A0

    /// Effect 0: normal alpha-over (state 1).
    public static let normal = 0

    /// Effect 26: basic shader through the target alpha (state 6), the rule wipe's capture pass.
    public static let throughDstAlpha = 26

    /// Effect 52: additive (state 2).
    public static let add = 52

    /// Effect 55: alpha := 0 (state 10).
    public static let alphaClear = 55

    /// Effect 56: alpha := max(sa, da) (state 11), the transition start fill.
    public static let alphaUnion = 56

    /// Effect 57: alpha := min(sa, da) (state 5).
    public static let alphaMin = 57

    /// Effect 58: alpha := sa (state 4), the rule mask pass.
    public static let alphaSet = 58

    public init(e: Int, flag: Bool, shaderMode: Int, strength: Float, blendState: Int, p2: Float) {
        self.e = e
        self.flag = flag
        self.shaderMode = shaderMode
        self.strength = strength
        self.blendState = blendState
        self.p2 = p2
    }

    /// True for the blend shaders, which read the backdrop D (every shader mode except 0 and 3).
    public var readsBackdrop: Bool {
        CompositorShaders.readsBackdrop(shaderMode)
    }

    /// `compose.effect(word)`.
    public static func decode(_ word: Int) -> DrawEffect {
        let low = word & 0xFF
        let e = low < 0x44 ? low : 0
        let rest = word & ~0x100
        let flag = (word & 0x100) != 0 && rest >= 0 && rest <= 0x2B && ((flagSet >> UInt64(rest)) & 1) != 0
        var mode = 0
        var strength: Float = 0
        if e >= 1 && e <= 51 {
            mode = effectMode[e - 1]
            strength = (e >= 27 && e != 29) ? 1.0 : 0.0
        }

        let state = flag ? 0 : effectBlendState[e]
        return DrawEffect(e: e, flag: flag, shaderMode: mode, strength: strength, blendState: state, p2: p2For(mode: mode, blendState: state))
    }

    /// The blend state of a word (`compose.effect(word).blend_state`).
    public static func blendStateOf(_ word: Int) -> Int {
        decode(word).blendState
    }

    /// P2 for the blend state actually used: 0 for modes 5, 7, 9, 10 when blending is off, else 1.
    public static func p2For(mode: Int, blendState: Int) -> Float {
        (mode == 5 || mode == 7 || mode == 9 || mode == 10) && blendState == 0 ? 0.0 : 1.0
    }

    /// SelectShader 0xF0E70 (compositing 3).
    public static func selectShader(textured: Bool, shaderMode: Int, hasTransitionParams: Bool) -> Int {
        if !textured {
            return CompositorShaders.modeSolid
        }
        if shaderMode == 0 {
            return hasTransitionParams ? CompositorShaders.modeTransition : CompositorShaders.modeBasic
        }
        return (shaderMode == 3 || shaderMode > 25) ? CompositorShaders.modeBasic : shaderMode
    }

    private static func buildBlendState() -> [Int] {
        var b = [Int]()
        b.append(contentsOf: repeatElement(1, count: 26))
        b.append(contentsOf: [6, 1, 1, 6])
        b.append(contentsOf: repeatElement(1, count: 22))
        b.append(contentsOf: [2, 7, 1, 10, 11, 5, 4, 9, 1, 1, 1, 2, 1, 13, 1, 1])
        return b
    }
}

/// Transition parameters of a texture: smoothstep lower and upper edges and invert flag.
public struct TransitionParams: Equatable, Sendable {
    public var lo: Float
    public var hi: Float
    public var invert: Float

    public init(lo: Float, hi: Float, invert: Float = 0) {
        self.lo = lo
        self.hi = hi
        self.invert = invert
    }

    /// `compose.rule_params` for remaining progress `progress`, generalised to a vague width `vague`.
    public static func forRule(_ progress: Float, vague: Int = 256) -> TransitionParams {
        let a = 256 - Int(progress * 256.0)
        let x0 = Float(a) * 0.0078125
        let x1 = x0 + (Float(vague) * -0.00390625)
        return TransitionParams(lo: max(-1.0, x1), hi: min(2.0, x0), invert: 0)
    }
}

/// The _FADS numbers of compositing 7.2 and 7.4.
public enum Fads {
    /// `compose.fads_step`: per-frame progress increment of a transition of `ms` milliseconds.
    public static func step(ms: Int, kind: Int = 0) -> Float {
        var duration = ms
        if (kind == 12 || kind == 49) && duration > 0 {
            duration += 100
        }
        return duration <= 0 ? -1.0 : -1.0 / (Float(duration) / 16.666)
    }

    /// `compose.fads_vertex_alpha` as the vertex-colour byte of the cross-fade: trunc(max(0, p) * 255).
    public static func crossfadeAlphaByte(_ progress: Float) -> UInt8 {
        UInt8(clamping: min(255, Int(max(0.0, progress) * 255.0)))
    }
}
