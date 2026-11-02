import Foundation
import TsukiCore

/// Builders of display-list commands (quads in strip order TL, TR, BL, BR).
public enum Quads {
    /// Packs a vertex colour as the contract stores it (R in bits 0-7 .. A in 24-31).
    public static func rgba(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8) -> UInt32 {
        UInt32(r) | (UInt32(g) << 8) | (UInt32(b) << 16) | (UInt32(a) << 24)
    }

    /// White with alpha `a`.
    public static func white(_ a: UInt8 = 255) -> UInt32 {
        rgba(255, 255, 255, a)
    }

    /// A textured quad on the rectangle (x0, y0)-(x1, y1) with texture coordinates (u0, v0)-(u1, v1).
    public static func textured(
        _ texture: TextureRef,
        _ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float,
        _ u0: Float, _ v0: Float, _ u1: Float, _ v1: Float,
        _ rgba: UInt32,
        _ word: Int,
        blendState: Int? = nil,
        target: UInt8 = 0,
        clip: PixelRect? = nil,
        fx: QuadFx = QuadFx()
    ) -> DrawCommand {
        DrawCommand(
            kind: .texturedQuad,
            target: target,
            texture: texture,
            v0: Vertex(x: x0, y: y0, u: u0, v: v0, rgba: rgba),
            v1: Vertex(x: x1, y: y0, u: u1, v: v0, rgba: rgba),
            v2: Vertex(x: x0, y: y1, u: u0, v: v1, rgba: rgba),
            v3: Vertex(x: x1, y: y1, u: u1, v: v1, rgba: rgba),
            effectWord: Int16(truncatingIfNeeded: word),
            blendState: UInt8(blendState ?? DrawEffect.blendStateOf(word)),
            clip: clip,
            fx: fx
        )
    }

    /// An untextured fill on the rectangle (x0, y0)-(x1, y1).
    public static func fill(
        _ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float,
        _ rgba: UInt32,
        _ word: Int,
        blendState: Int? = nil,
        target: UInt8 = 0,
        clip: PixelRect? = nil
    ) -> DrawCommand {
        DrawCommand(
            kind: .fillQuad,
            target: target,
            texture: .none,
            v0: Vertex(x: x0, y: y0, u: 0, v: 0, rgba: rgba),
            v1: Vertex(x: x1, y: y0, u: 0, v: 0, rgba: rgba),
            v2: Vertex(x: x0, y: y1, u: 0, v: 1, rgba: rgba),
            v3: Vertex(x: x1, y: y1, u: 0, v: 1, rgba: rgba),
            effectWord: Int16(truncatingIfNeeded: word),
            blendState: UInt8(blendState ?? DrawEffect.blendStateOf(word)),
            clip: clip
        )
    }

    /// Copy target `target` into capture surface `surface` (record type 6).
    public static func capture(_ surface: Int, target: UInt8 = 0) -> DrawCommand {
        DrawCommand(
            kind: .capture,
            target: target,
            texture: TextureRef.capture(surface)
        )
    }
}

/// The commands of `_FADS(type, ms, rule)` (compositing 7).
public enum FadsCommands {
    // 0x6B910 jump table 0x209FF0: these types also capture into nexl_Capture[15]
    private static let capture15Types: Set<Int> = [
        2, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
        29, 30, 31, 32, 46, 49, 52, 53, 70
    ]

    /// True when the transition start of `kind` also captures into surface 15.
    public static func capturesSurface15(_ kind: Int) -> Bool {
        capture15Types.contains(kind)
    }

    /// `compose.fads_capture`: the capture surface the per-frame draw of `kind` reads (0 or 15), or nil when it draws nothing.
    public static func captureSurfaceOf(_ kind: Int) -> Int? {
        if kind == 1 || kind == 49 {
            return nil
        }
        if kind == 2 {
            return 15
        }
        if kind == 18 || (kind >= 20 && kind <= 24) || (kind >= 68 && kind <= 70) || kind < 0 || kind > 70 {
            return nil
        }
        return 0
    }

    /// Transition start (0x6B910): effect 56 fill (state 11: alpha := max(1, da)) over the whole target,
    /// then the capture into surface 0 and, for the CAPTURE15 types, into surface 15.
    public static func begin(_ list: DisplayList, _ kind: Int, width: Int = 1920, height: Int = 1080) {
        list.add(Quads.fill(0, 0, Float(width), Float(height), Quads.white(), DrawEffect.alphaUnion))
        list.add(Quads.capture(0))
        if capturesSurface15(kind) {
            list.add(Quads.capture(15))
        }
    }

    /// One frame of the transition at remaining progress `progress`.
    public static func frame(
        _ list: DisplayList,
        _ kind: Int,
        _ progress: Float,
        _ rule: TextureRef?,
        width: Int = 1920,
        height: Int = 1080,
        rand: (() -> Int)? = nil
    ) -> TransitionParams? {
        if kind == 1 || progress <= 0 {
            return nil
        }

        if TransitionScreens.handles(kind) {
            let rng = rand ?? { Int.random(in: 0...Int(Int32.max)) }
            TransitionScreens.frame(list, kind, progress, rule, rng)
            return nil
        }

        guard let surface = captureSurfaceOf(kind) else {
            return nil
        }

        let capture = TextureRef.capture(surface)
        if kind == 2, let r = rule {
            list.add(Quads.textured(r, 0, 0, Float(width), Float(height), 0, 0, 1, 1, Quads.white(), DrawEffect.alphaSet))
            list.add(Quads.textured(capture, 0, 0, Float(width), Float(height), 0, 0, 1, 1, Quads.white(), DrawEffect.throughDstAlpha))
            return TransitionParams.forRule(progress)
        }

        list.add(Quads.textured(capture, 0, 0, Float(width), Float(height), 0, 0, 1, 1, Quads.white(Fads.crossfadeAlphaByte(progress)), DrawEffect.normal))
        return nil
    }
}

/// The per-frame draw of the `_FADS` types that only the engine's own screens could start.
public enum TransitionScreens {
    private static let unitX: Float = 4.0
    private static let unitY: Float = 1080.0 / 272.0
    private static let captureWidth: Float = 1920.0
    private static let captureHeight: Float = 1080.0

    /// True for the types this class draws.
    public static func handles(_ kind: Int) -> Bool {
        kind == 18 || (kind >= 20 && kind <= 24) || (kind >= 68 && kind <= 70)
    }

    /// Appends one frame of transition `kind` at remaining progress `progress`.
    public static func frame(_ list: DisplayList, _ kind: Int, _ progress: Float, _ rule: TextureRef?, _ rand: () -> Int) {
        if progress <= 0 {
            return
        }

        switch kind {
        case 18:
            mosaic(list, progress)
        case 20:
            scanLines(list, progress, rand)
        case 21...24:
            slide(list, kind, progress)
        case 69:
            whiteOut(list, progress, rule)
        case 70:
            zoomOut(list, progress)
        default:
            break
        }
    }

    private static func slide(_ list: DisplayList, _ kind: Int, _ p: Float) {
        list.add(Quads.capture(0))
        let h: Float = 480.0
        let old = 1.0 - p
        let (dxo, dyo, dxn, dyn): (Float, Float, Float, Float) = {
            switch kind {
            case 21: return (0, -272.0 * old, 0, 272.0 * p)
            case 22: return (0, 272.0 * old, 0, -272.0 * p)
            case 23: return (old * h, 0, -p * h, 0)
            default: return (-old * h, 0, p * h, 0)
            }
        }()
        rect(list, 15, dxo, dyo, 0, 0, 960, 544, nearest: false)
        rect(list, 0, dxn, dyn, 0, 0, 960, 544, nearest: false)
    }

    private static func scanLines(_ list: DisplayList, _ p: Float, _ rand: () -> Int) {
        list.add(Quads.textured(TextureRef.capture(0), 0, 0, 1920, 1080, 0, 0, 1, 1, fads255(p), 0))
        list.add(Quads.capture(0))
        list.add(Quads.fill(0, 0, 1920, 1080, color(0, 0, 0, 255), 0))
        let amplitude = min(1.0, p * 1.1111)
        for i in 0..<544 {
            let x = Float(Int(Float((rand() & 0x1F) - 12) * amplitude))
            let y = Float(Int(Float(i) * 0.5))
            rect(list, 0, x, y, 0, i, 960, i + 1, nearest: false)
        }
    }

    private static func mosaic(_ list: DisplayList, _ p: Float) {
        list.add(Quads.capture(0))
        let v: Float = p > 0.45 ? ((p - 0.45) * -2.2222) + 1.0 : p * 2.2222
        let n = Int(min(1.0, v) * 16.0)
        let tile = n >= 3 ? n : 2
        let w = captureWidth * (1.0 / (6.0 * Float(tile))) * unitX
        let h = captureHeight * (0.2074074 / Float(tile)) * unitY
        list.add(Quads.textured(TextureRef.capture(0), 0, 0, w, h, 0, 0, 1, 1, color(255, 255, 255, 255), 0))
        list.add(Quads.capture(0))
        let right = Int(1280.0 / Float(tile))
        let bottom = Int(896.0 / Float(tile))
        list.add(Quads.textured(
            TextureRef.capture(0),
            0, 0, Float(right * tile), Float(bottom * tile),
            0, 0, Float(right) / captureWidth, Float(bottom) / captureHeight,
            color(255, 255, 255, 255), 0,
            fx: QuadFx(nearest: true)
        ))
    }

    private static func whiteOut(_ list: DisplayList, _ p: Float, _ rule: TextureRef?) {
        list.add(Quads.capture(0))
        list.add(Quads.fill(0, 0, 1920, 1080, color(255, 255, 255, 255), 0))
        if p > 0.25 || rule == nil {
            return
        }

        let r = rule!
        let (lo, hi) = ruleWindow(1.0 - (4.0 * p))
        list.add(Quads.textured(r, 0, 0, 1920, 1080, 0, 0, 1, 1, color(255, 255, 255, 255), 58, fx: QuadFx.forRule(lo: lo, hi: hi, invert: 0)))
        list.add(Quads.textured(TextureRef.capture(0), 0, 0, 1920, 1080, 0, 0, 1, 1, color(255, 255, 255, 255), 26))
    }

    private static func zoomOut(_ list: DisplayList, _ p: Float) {
        let angle = Float(Int((1.0 - p) * 32768.0 * 8.0)) * 9.5873e-5
        let sx = (0.1 * cos(angle)) + p
        let sy = (0.1 * sin(angle)) + p
        let w = 960.0 * sx
        let h = 544.0 * sy
        list.add(Quads.textured(
            TextureRef.capture(15),
            960.0 - (w / 2.0), 540.0 - (h / 2.0),
            960.0 + (w / 2.0), 540.0 + (h / 2.0),
            0, 0, 960.0 / captureWidth, 544.0 / captureHeight,
            color(255, 255, 255, 255), 0
        ))
    }

    /// The rule window of 0xD73B0 for a remaining progress.
    public static func ruleWindow(_ progress: Float) -> (lo: Float, hi: Float) {
        let a = 256 - Int(progress * 256.0)
        let x0 = Float(a) * 0.0078125
        return (max(-1.0, x0 + (256.0 * -0.00390625)), min(2.0, x0))
    }

    private static func color(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8) -> UInt32 {
        Quads.rgba(r, g, b, a)
    }

    private static func fads255(_ p: Float) -> UInt32 {
        color(255, 255, 255, UInt8(clamping: min(255, Int(max(0.0, p) * 255.0))))
    }

    private static func rect(
        _ list: DisplayList,
        _ surface: Int,
        _ ux: Float, _ uy: Float,
        _ l: Int, _ t: Int, _ r: Int, _ b: Int,
        nearest: Bool
    ) {
        let x = ux * unitX
        let y = uy * unitY
        list.add(Quads.textured(
            TextureRef.capture(surface),
            x, y, x + Float(r - l), y + Float(b - t),
            Float(l) / captureWidth, Float(t) / captureHeight,
            Float(r) / captureWidth, Float(b) / captureHeight,
            color(255, 255, 255, 255), 0,
            fx: QuadFx(nearest: nearest)
        ))
    }
}
