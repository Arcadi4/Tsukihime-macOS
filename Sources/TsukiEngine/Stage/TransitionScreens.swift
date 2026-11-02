import Foundation
import TsukiCore

/// The per-frame draw of the `_FADS` types that only the engine's own screens could start: 18 (mosaic), 20 (scan-line jitter), 21..24 (slides),
/// 68 (shatter, dead code), 69 (white-out then rule dissolve) and 70 (zoom-out of the old frame). They come from the cases 0x67A7C, 0x67AF5, 0x67895,
/// 0x67CB2, 0x67CC4 and 0x67E90 of the draw callback 0x67820 (docs/status/knife/K7.md; recompiled from the disassembly and checked by emulating the
/// callback at five progress values). No script uses them (the census has types 0, 1 and 2 only) and no engine screen of the PS4 build starts
/// them: the only other caller of the type store 0x42480 is a dead timeline player. They are kept so the transition table is complete.
///
/// The cases were written for the 960 x 544 layout of the Vita build and ported to the 1920 x 1080 captures unchanged: their source rectangles are
/// 960 x 544 texels (one texel is one pixel) at the top-left, so on the PS4 the slides, the zoom and the mosaic act on that crop of the capture only.
/// This class reproduces what the engine draws (`docs/status/knife/K7.md` lists the geometry of each type); it does not "fix" the crop.
/// All numbers are in the 480 x 272 units of the callback (4 px per unit in x, 1080 / 272 px per unit in y).
public enum TransitionScreens {
    private static let unitX: Float = 4.0
    private static let unitY: Float = 1080.0 / 272.0
    private static let captureWidth: Float = 1920.0
    private static let captureHeight: Float = 1080.0

    /// True for the types this class draws.
    public static func handles(_ kind: Int) -> Bool {
        kind == 18 || (kind >= 20 && kind <= 24) || (kind >= 68 && kind <= 70)
    }

    /// Appends one frame of transition `kind` at remaining progress `progress` (1 at the start, 0 at the end) after the
    /// new scene. Type 69 needs the rule picture of the transition (nil: the white-out stays); type 20 draws one random offset per scan line from
    /// `rand` (the shared libc `rand()`).
    public static func frame(
        _ list: DisplayList,
        _ kind: Int,
        _ progress: Float,
        _ rule: TextureRef?,
        _ rand: () -> Int
    ) {
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
            break // 68: the particle table is never filled, nothing is drawn
        }
    }

    // 0x67895: the old frame (capture 15) and the new scene (capture 0, taken here) slide by the same distance in opposite directions
    private static func slide(_ list: DisplayList, _ kind: Int, _ p: Float) {
        capture(list, 0)
        let h: Float = 480.0 // (R - L) / 2 of the full 960 x 544 rectangle
        let old = 1.0 - p
        let dxo: Float
        let dyo: Float
        let dxn: Float
        let dyn: Float
        switch kind {
        case 21:
            dxo = 0
            dyo = -272.0 * old
            dxn = 0
            dyn = 272.0 * p
        case 22:
            dxo = 0
            dyo = 272.0 * old
            dxn = 0
            dyn = -272.0 * p
        case 23:
            dxo = old * h
            dyo = 0
            dxn = -p * h
            dyn = 0
        default:
            dxo = -old * h
            dyo = 0
            dxn = p * h
            dyn = 0
        }
        rect(list, 15, dxo, dyo, 0, 0, 960, 544, nearest: false)
        rect(list, 0, dxn, dyn, 0, 0, 960, 544, nearest: false)
    }

    // 0x67AF5: cross-fade the old frame in, capture the result, then redraw it line by line with a random horizontal offset over black
    private static func scanLines(_ list: DisplayList, _ p: Float, _ rand: () -> Int) {
        list.add(textured(
            tex: .capture(0),
            x0: 0, y0: 0, x1: 1920, y1: 1080,
            u0: 0, v0: 0, u1: 1, v1: 1,
            rgba: fads255(p)
        ))
        capture(list, 0)
        list.add(fill(0, 0, 1920, 1080, color(0, 0, 0, 255)))
        let amplitude = min(1.0 as Float, p * 1.1111)
        for i in 0..<544 {
            let x = Float(Int(Float((rand() & 0x1F) - 12) * amplitude))
            let y = Float(Int(Float(i) * 0.5))
            rect(list, 0, x, y, 0, i, 960, i + 1, nearest: false)
        }
    }

    // 0x67A7C: the new scene is shrunk by N into the corner, captured and magnified back with nearest-texel sampling
    private static func mosaic(_ list: DisplayList, _ p: Float) {
        capture(list, 0)
        let v: Float = p > 0.45 ? ((p - 0.45) * -2.2222) + 1.0 : p * 2.2222
        let n = Int(min(1.0 as Float, v) * 16.0)
        let tile = n >= 3 ? n : 2
        let w = captureWidth * (1.0 / (6.0 * Float(tile))) * unitX
        let h = captureHeight * (0.2074074 / Float(tile)) * unitY
        list.add(textured(
            tex: .capture(0),
            x0: 0, y0: 0, x1: w, y1: h,
            u0: 0, v0: 0, u1: 1, v1: 1,
            rgba: color(255, 255, 255, 255)
        ))
        capture(list, 0)
        let right = Int(1280.0 / Float(tile))
        let bottom = Int(896.0 / Float(tile))
        list.add(textured(
            tex: .capture(0),
            x0: 0, y0: 0,
            x1: Float(right * tile),
            y1: Float(bottom * tile),
            u0: 0, v0: 0,
            u1: Float(right) / captureWidth,
            v1: Float(bottom) / captureHeight,
            rgba: color(255, 255, 255, 255),
            nearest: true
        ))
    }

    // 0x67CC4: the whole screen turns white, then the new scene dissolves in through the rule picture during the last quarter
    private static func whiteOut(_ list: DisplayList, _ p: Float, _ rule: TextureRef?) {
        capture(list, 0)
        list.add(fill(0, 0, 1920, 1080, color(255, 255, 255, 255)))
        guard p <= 0.25, let r = rule else {
            return
        }

        let (lo, hi) = ruleWindow(1.0 - (4.0 * p))
        list.add(textured(
            tex: r,
            x0: 0, y0: 0, x1: 1920, y1: 1080,
            u0: 0, v0: 0, u1: 1, v1: 1,
            rgba: color(255, 255, 255, 255),
            word: 58,
            fx: QuadFx.forRule(lo: lo, hi: hi, invert: 0)
        ))
        list.add(textured(
            tex: .capture(0),
            x0: 0, y0: 0, x1: 1920, y1: 1080,
            u0: 0, v0: 0, u1: 1, v1: 1,
            rgba: color(255, 255, 255, 255),
            word: 26
        ))
    }

    // 0x67E90: the old frame (capture 15, rectangle 960 x 544) shrinks towards the screen centre while turning through 4 full circles in its scale
    private static func zoomOut(_ list: DisplayList, _ p: Float) {
        let angle = Float(Int((1.0 - p) * 32768.0 * 8.0)) * 9.5873e-5
        let sx = (0.1 * cos(angle)) + p
        let sy = (0.1 * sin(angle)) + p
        let w = 960.0 * sx
        let h = 544.0 * sy
        list.add(textured(
            tex: .capture(15),
            x0: 960.0 - (w / 2.0),
            y0: 540.0 - (h / 2.0),
            x1: 960.0 + (w / 2.0),
            y1: 540.0 + (h / 2.0),
            u0: 0, v0: 0,
            u1: 960.0 / captureWidth,
            v1: 544.0 / captureHeight,
            rgba: color(255, 255, 255, 255)
        ))
    }

    /// The rule window of 0xD73B0 for a remaining progress (a = 256 - trunc(256 progress), width 256): (lo, hi).
    public static func ruleWindow(_ progress: Float) -> (lo: Float, hi: Float) {
        let a = 256 - Int(progress * 256.0)
        let x0 = Float(a) * 0.0078125
        return (max(-1.0, x0 + (256.0 * -0.00390625)), min(2.0, x0))
    }

    private static func color(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8) -> UInt32 {
        UInt32(r) | (UInt32(g) << 8) | (UInt32(b) << 16) | (UInt32(a) << 24)
    }

    private static func fads255(_ p: Float) -> UInt32 {
        let a = UInt8(clamping: min(255, Int(max(0.0 as Float, p) * 255.0)))
        return color(255, 255, 255, a)
    }

    private static func capture(_ list: DisplayList, _ surface: Int) {
        list.add(DrawCommand(kind: .capture, texture: .capture(surface)))
    }

    // a texel rectangle (l, t, r, b) of a capture at the unit position (ux, uy), one texel per pixel (picture scale 0.25 x 0.2518519)
    private static func rect(
        _ list: DisplayList,
        _ surface: Int,
        _ ux: Float,
        _ uy: Float,
        _ l: Int,
        _ t: Int,
        _ r: Int,
        _ b: Int,
        nearest: Bool
    ) {
        let x = ux * unitX
        let y = uy * unitY
        list.add(textured(
            tex: .capture(surface),
            x0: x,
            y0: y,
            x1: x + Float(r - l),
            y1: y + Float(b - t),
            u0: Float(l) / captureWidth,
            v0: Float(t) / captureHeight,
            u1: Float(r) / captureWidth,
            v1: Float(b) / captureHeight,
            rgba: color(255, 255, 255, 255),
            nearest: nearest
        ))
    }

    private static func fill(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, _ rgba: UInt32) -> DrawCommand {
        DrawCommand(
            kind: .fillQuad,
            v0: Vertex(x: x0, y: y0, u: 0, v: 0, rgba: rgba),
            v1: Vertex(x: x1, y: y0, u: 0, v: 0, rgba: rgba),
            v2: Vertex(x: x0, y: y1, u: 0, v: 0, rgba: rgba),
            v3: Vertex(x: x1, y: y1, u: 0, v: 0, rgba: rgba),
            effectWord: 0,
            blendState: UInt8(truncatingIfNeeded: DrawEffectTables.blendStateOf(0))
        )
    }

    private static func textured(
        tex: TextureRef,
        x0: Float,
        y0: Float,
        x1: Float,
        y1: Float,
        u0: Float,
        v0: Float,
        u1: Float,
        v1: Float,
        rgba: UInt32,
        word: Int = 0,
        nearest: Bool = false,
        fx: QuadFx = QuadFx()
    ) -> DrawCommand {
        var quadFx = fx
        if nearest {
            quadFx.nearest = true
        }
        return DrawCommand(
            kind: .texturedQuad,
            texture: tex,
            v0: Vertex(x: x0, y: y0, u: u0, v: v0, rgba: rgba),
            v1: Vertex(x: x1, y: y0, u: u1, v: v0, rgba: rgba),
            v2: Vertex(x: x0, y: y1, u: u0, v: v1, rgba: rgba),
            v3: Vertex(x: x1, y: y1, u: u1, v: v1, rgba: rgba),
            effectWord: Int16(truncatingIfNeeded: word),
            blendState: UInt8(truncatingIfNeeded: DrawEffectTables.blendStateOf(word)),
            fx: quadFx
        )
    }
}
