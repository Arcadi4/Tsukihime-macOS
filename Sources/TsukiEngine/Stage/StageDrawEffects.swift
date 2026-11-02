// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Ported from knife (https://github.com/AuroraWright/knife) by AuroraWright: knife/src/stage.rs (Haze::params, Stage::noise_pass)
import Foundation
import TsukiCore

// The passes K2 left undrawn (docs/status/knife/K2.md open issue 3), as display-list commands: the offscreen alpha mask of a window layer and of a
// rule fade (STCH mask, STTR), the STRA haze and the STNS noise. The PS4 documents give the state (layers.md 4.2, 9) but not the picture, so the
// shapes follow knife's stage.rs (Haze::params, noise_pass, the group / rule paths of Stage::draws) and the PS4 numbers where we have them
// (compositing.md 2.4: the rule window; layers.md 9: the group pass draws the window layer at alpha 1 and masks the layers that name it).
extension StageRuntime {
    /// The render target that holds the alpha mask of the group being drawn (cleared at the start of each group; targets 2..7 belong to the screen effects).
    public static let maskTarget: UInt8 = 1

    /// The rule number (1..49) and the mirror bits (1 = x, 2 = y) of a layer's `_STTR`, or null when it has none.
    static func ruleOf(_ r: LayerRecord) -> (rule: Int, flip: Int)? {
        if r.sttr < 0 {
            return nil
        }
        let n = (Int(r.sttr) & 0xFFF) + 1
        return (n >= 1 && n <= 49) ? (n, (Int(r.sttr) >> 12) & 3) : nil
    }

    static func clearTarget(_ target: UInt8) -> DrawCommand {
        DrawCommand(kind: .clear, target: target, v0: Vertex(x: 0, y: 0, u: 0, v: 0, rgba: 0))
    }

    /// Appends the mask of a layer that has a rule fade: the rule picture drawn full screen into the mask target with the rule window of the layer's
    /// alpha (the layer fades by wiping through the rule, dark rule values first; effect 58 = alpha := the quad's alpha, the engine's own mask pass).
    func addRuleMask(_ list: DisplayList, _ rule: (rule: Int, flip: Int), alpha: Float) {
        let (lo, hi) = TransitionScreens.ruleWindow(1.0 - alpha)
        let u0: Float = (rule.flip & 1) != 0 ? 1.0 : 0.0
        let u1 = 1.0 - u0
        let v0: Float = (rule.flip & 2) != 0 ? 1.0 : 0.0
        let v1 = 1.0 - v0
        var q = Self.textured(
            tex: .pictureTile(archive: 4, entry: 85 + rule.rule, tile: 0),
            x0: 0, y0: 0, x1: 1920, y1: 1080,
            u0: u0, v0: v0, u1: u1, v1: v1,
            rgba: Self.white(),
            word: 58
        )
        q.target = Self.maskTarget
        q.fx = QuadFx.forRule(lo: lo, hi: hi, invert: 1.0)
        list.add(q)
    }

    /// The silhouette of a layer's quads in the mask target: replaces the mask's alpha (state 4) or multiplies it (extension state).
    func addSilhouette(_ list: DisplayList, multiply: Bool) {
        for q in quads {
            var s = q
            s.target = Self.maskTarget
            s.fx = QuadFx()
            if multiply {
                s.effectWord = 0
                s.blendState = 0x80 // BlendStates.MaskMultiply: the target alpha times the quad alpha, colour kept
                s.v0.rgba |= 0xFF000000
                s.v1.rgba |= 0xFF000000
                s.v2.rgba |= 0xFF000000
                s.v3.rgba |= 0xFF000000
            } else {
                s.effectWord = 58
                s.blendState = UInt8(truncatingIfNeeded: DrawEffectTables.blendStateOf(58))
            }
            list.add(s)
        }
    }

    /// The STRA haze of a layer as the quad inputs of one tile (knife `Haze::params`, the PS4 table values): two waves along the picture's v axis
    /// displace the texture coordinates, x by a sine, y by a cosine. The wave coordinate is the picture-space v, so tiles of one picture agree.
    static func hazeFx(_ h: HazeState, _ layout: PictureLayout, _ file: PictureFileLayout, _ t: TileQuad, _ mask: UInt8) -> QuadFx {
        let e = h.entry
        let pictureW = max(1.0 as Float, Float(layout.width))
        let pictureH = max(1.0 as Float, Float(layout.height))
        let seconds = Float(h.phase) / 60.0
        let amplitude: Float
        if h.fadeIn != 0 && e[9] > 0 {
            let ms = min(1000 * h.phase / 60, Int(e[9]))
            amplitude = Float(Int(Float(ms) * 1000.0 / e[9]))
        } else if h.fadeTotal >= 1 {
            amplitude = Float(Int(Float(h.fadeLeft) * 1000.0 / Float(h.fadeTotal)))
        } else {
            amplitude = 1000.0
        }

        let scale = 1920.0 * 0.00097656 * 0.001 * amplitude
        let ax = scale * e[6] * e[2]
        let ay = scale * e[6] * e[5]
        let waveX = (e[0] + (e[7] * 0.1)) * (pictureH / 1080.0) * 0.5
        let waveY = (e[3] + (e[7] * 0.1)) * (pictureW / 1920.0) * 0.5
        let phaseX = fract(e[8] * 0.33333 * (seconds + e[1]))
        let phaseY = fract(e[8] * 0.33333 * (seconds + e[4]))
        let tileW = t.x1 - t.x0
        let tileH = t.y1 - t.y0
        let du = t.u1 - t.u0
        let dv = t.v1 - t.v0
        let axUv = tileW > 0 ? ax * du / tileW : 0
        let ayUv = tileH > 0 ? ay * dv / tileH : 0
        let rowsPerV = abs(dv) > 1e-9 ? tileH / dv : 0
        let sScale = rowsPerV / pictureH
        let sOffset = (file.offsetY + t.y0 - (t.v0 * rowsPerV)) / pictureH
        return QuadFx(
            pass: .haze,
            mask: mask,
            nearest: false,
            a0: axUv,
            a1: waveX,
            a2: phaseX,
            a3: sOffset,
            b0: ayUv,
            b1: waveY,
            b2: phaseY,
            b3: sScale
        )
    }

    private static func fract(_ x: Float) -> Float {
        x - floor(x)
    }

    /// The STNS noise of a layer (knife `noise_pass`): the layer shows the NOISE_PARTS picture (a 1920 x 1080 grey grain, two pictures) instead of
    /// its own, scaled 1.2 and shifted by a fresh random offset every frame (every third frame for `stns` 1 and 2), mirrored on alternate ticks.
    func noiseQuad(
        _ r: LayerRecord,
        _ m: Affine,
        _ layout: PictureLayout,
        _ rgba: UInt32,
        _ word: Int,
        _ window: PixelRect?,
        _ fx: QuadFx
    ) -> DrawCommand {
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for file in layout.files {
            for t in file.tiles {
                minX = min(minX, Double(t.x0 + file.offsetX))
                minY = min(minY, Double(t.y0 + file.offsetY))
                maxX = max(maxX, Double(t.x1 + file.offsetX))
                maxY = max(maxY, Double(t.y1 + file.offsetY))
            }
        }

        let (ax, ay) = m.apply(minX, minY)
        let (bx, by) = m.apply(maxX, minY)
        let (cx, cy) = m.apply(minX, maxY)
        let (dx, dy) = m.apply(maxX, maxY)
        let period: Int64 = r.stns > 2 ? 1 : 3
        let tick = noiseFrame / period
        let seed = UInt32(truncatingIfNeeded: noiseFrame)
        let fx0 = Self.noiseHash(seed, 1) * 160.0 / 2304.0
        let fy0 = Self.noiseHash(seed, 2) * 90.0 / 1296.0
        let span: Float = 1.0 / 1.2
        var u0 = fx0
        var u1 = fx0 + span
        if (tick & 1) == 1 {
            swap(&u0, &u1)
        }

        let sheet = TextureRef.uiTile(
            set: UiSet.noiseParts.rawValue,
            language: Int(Language.ja.rawValue),
            child: r.stns % 10 == 2 ? 1 : 0,
            tile: -1
        )
        return DrawCommand(
            kind: .texturedQuad,
            texture: sheet,
            v0: Vertex(x: Float(ax), y: Float(ay), u: u0, v: fy0, rgba: rgba),
            v1: Vertex(x: Float(bx), y: Float(by), u: u1, v: fy0, rgba: rgba),
            v2: Vertex(x: Float(cx), y: Float(cy), u: u0, v: fy0 + span, rgba: rgba),
            v3: Vertex(x: Float(dx), y: Float(dy), u: u1, v: fy0 + span, rgba: rgba),
            effectWord: Int16(truncatingIfNeeded: word),
            blendState: UInt8(truncatingIfNeeded: DrawEffectTables.blendStateOf(word)),
            clip: window,
            fx: fx
        )
    }

    static func noiseHash(_ seed: UInt32, _ k: UInt32) -> Float {
        var v = (seed &* 0x9E3779B1) &+ (k &* 0x85EBCA77)
        v ^= v >> 15
        v &*= 0x2C1B3C6D
        v ^= v >> 12
        v &*= 0x297A2D39
        v ^= v >> 15
        return Float(v & 0xFFFF) / 65535.0
    }
}
