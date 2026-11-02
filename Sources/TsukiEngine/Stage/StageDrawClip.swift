// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Ported from knife (https://github.com/AuroraWright/knife) by AuroraWright: knife/src/stage.rs (ClipRect::inset_rect, ClipRect::soft, ClipRect::band; unrotated branches)
import Foundation
import TsukiCore

/// A clip window of a layer (STCH a12..a17) in 1920 x 1080 pixels, before it is cut to the screen: the crop rectangle moved by the shakes, the inset
/// (`a16`, in pixels) and the mode (`a17`).
public struct ClipWindow: Equatable, Sendable {
    /// Left.
    public var x: Float
    /// Top.
    public var y: Float
    /// Width.
    public var w: Float
    /// Height.
    public var h: Float
    /// STCH a16: the width of the soft edge (modes 0, 7, 8 and up) or of the ridge and the scissor shrink (modes 1..6).
    public var inset: Int
    /// STCH a17: 1..6 a ridge of a colour (black, white, red, three tints), 7 a twice as wide soft edge with the sharper textures, else a soft edge.
    public var mode: Int

    public init(x: Float, y: Float, w: Float, h: Float, inset: Int, mode: Int) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.inset = inset
        self.mode = mode
    }

    /// True for the ridge modes 1..6.
    public var isBand: Bool {
        mode >= 1 && mode <= 6
    }

    /// The scissor of the window (knife `inset_rect`, sub_36520): in the ridge modes it shrinks by the inset on each side whose extent is under the
    /// screen size, which cuts the solid outer half of the ridge away.
    public func scissor() -> ClipWindow {
        if !isBand {
            return self
        }

        var c = self
        let d = Float(inset)
        if c.w < 1920.0 {
            c.x += d
            c.w -= 2.0 * d
        }
        if c.h < 1080.0 {
            c.y += d
            c.h -= 2.0 * d
        }
        return c
    }
}

/// The soft mask of a window with a fade-out edge (knife `SoftClip`): the fade widths of the four sides in pixels and the texture that shapes it.
public struct SoftWindow: Equatable, Sendable {
    /// The window the mask covers.
    public var window: ClipWindow
    /// Fade width at the left edge (0: none).
    public var left: Float
    /// Fade width at the right edge.
    public var right: Float
    /// Fade width at the top edge.
    public var top: Float
    /// Fade width at the bottom edge.
    public var bottom: Float
    /// BORDER_PARTS child holding the gradation (0..5 the plain ones, 13..18 the sharper `_2` ones).
    public var texture: Int
    /// Texel size of one quadrant of the texture (the radius, 10..256).
    public var texels: Int

    public init(window: ClipWindow, left: Float, right: Float, top: Float, bottom: Float, texture: Int, texels: Int) {
        self.window = window
        self.left = left
        self.right = right
        self.top = top
        self.bottom = bottom
        self.texture = texture
        self.texels = texels
    }
}

extension StageRuntime {
    /// The render target that holds the soft mask of the window layer being drawn (rebuilt for every window with a soft edge).
    public static let softTarget: UInt8 = 8

    // texel sizes of the BORDER_PARTS gradation quadrants: f32[6] at text VA 0x200590 (K1b: SoftClipRadii). IEbootTables.ClipRadii gives the eboot's copy.
    private static let defaultRadii: [Float] = [10.0, 32.0, 40.0, 64.0, 128.0, 256.0]

    private var radii: [Float] {
        if let clipRadii, clipRadii.count == 6 {
            return clipRadii
        }
        return Self.defaultRadii
    }

    private static func border(_ child: Int) -> TextureRef {
        .uiTile(set: UiSet.borderParts.rawValue, language: Int(Language.ja.rawValue), child: child, tile: -1)
    }

    private func radiusClass(_ r: Float) -> Int {
        let rList = radii
        for i in 0..<rList.count {
            if r < rList[i] {
                return i
            }
        }
        return rList.count - 1
    }

    /// The soft mask of a window (knife `ClipRect::soft`, sub_32E30, unrotated): with an inset and a mode outside 1..6 the window is masked by a rounded
    /// rectangle whose edges fade out over (inset rounded up to even) pixels, twice that in mode 7, at most half the window's extent. A side that lies off the
    /// screen, or a window that spans the whole width or height, gets no fade there. Null when the window has no soft edge.
    func softOf(_ c: ClipWindow) -> SoftWindow? {
        if c.inset <= 0 || c.isBand {
            return nil
        }

        let half = Float((c.inset & 1) + c.inset) * 0.5
        let r0: Float = c.mode == 7 ? half * 2.0 : half
        let (l, t) = (c.x * 0.5, c.y * 0.5)
        let (rx, by) = ((c.x + c.w) * 0.5, (c.y + c.h) * 0.5)
        let r = min(r0, min((rx - l) * 0.5, (by - t) * 0.5))
        if r <= 0 {
            return nil
        }

        var rl: Float = (l + r <= 0) ? 0 : r
        var rr: Float = (rx - r >= 960.0) ? 0 : r
        var rt: Float = (t + r <= 0) ? 0 : r
        var rb: Float = (by - r >= 540.0) ? 0 : r
        if l == 0 && c.w * 0.5 == 960.0 {
            rl = 0
            rr = 0
        }
        if t == 0 && c.h * 0.5 == 540.0 {
            rt = 0
            rb = 0
        }

        if rl + rr + rt + rb <= 0 {
            return nil // no side fades: the mask would be the whole window at alpha 1
        }

        let k = radiusClass(r)
        return SoftWindow(
            window: c,
            left: rl * 2.0,
            right: rr * 2.0,
            top: rt * 2.0,
            bottom: rb * 2.0,
            texture: c.mode == 7 ? 13 + k : k,
            texels: Int(radii[k])
        )
    }

    // the pieces of an alphagradation texture of 2n x 2n texels (knife qword_572990): the four quadrants, the 1-texel strips beside the centre
    private static func piece(_ p: Int, _ n: Int) -> (u0: Float, v0: Float, u1: Float, v1: Float) {
        let m = Float(n)
        let d = 2.0 * Float(n)
        switch p {
        case 0: return (0, 0, m / d, m / d)
        case 1: return ((m - 1.0) / d, 0, m / d, m / d)
        case 2: return (m / d, 0, 1.0, m / d)
        case 3: return (0, (m - 1.0) / d, m / d, m / d)
        case 4: return (m / d, (m - 1.0) / d, 1.0, m / d)
        case 5: return (0, m / d, m / d, 1.0)
        case 6: return ((m - 1.0) / d, m / d, m / d, 1.0)
        default: return (m / d, m / d, 1.0, 1.0)
        }
    }

    /// Draws the soft mask into `target` (sub_32E30's nine-slice): the four corner quadrants and four edge strips of the gradation texture at the
    /// fade widths, the inner rectangle at alpha 1. With `multiply` the pieces narrow what the target holds (the window layer's silhouette)
    /// instead of replacing it.
    func addSoftMask(_ list: DisplayList, _ s: SoftWindow, _ target: UInt8, multiply: Bool) {
        let c = s.window
        let x0 = c.x, y0 = c.y, x1 = c.x + c.w, y1 = c.y + c.h
        let fl = s.left, fr = s.right, ft = s.top, fb = s.bottom
        let n = s.texels
        let whiteColor = Self.white()
        let word = multiply ? 0 : 58

        func add(_ q: DrawCommand) {
            var d = q
            d.target = target
            if multiply {
                d.effectWord = 0
                d.blendState = 0x80 // BlendStates.MaskMultiply: the target alpha times the quad alpha
            }
            list.add(d)
        }

        func slice(_ p: Int, _ ax: Float, _ ay: Float, _ bx: Float, _ by: Float) {
            if bx <= ax || by <= ay {
                return
            }
            let (u0, v0, u1, v1) = Self.piece(p, n)
            add(Self.textured(
                tex: Self.border(s.texture),
                x0: ax, y0: ay, x1: bx, y1: by,
                u0: u0, v0: v0, u1: u1, v1: v1,
                rgba: whiteColor,
                word: word
            ))
        }

        slice(0, x0, y0, x0 + fl, y0 + ft)
        slice(2, x1 - fr, y0, x1, y0 + ft)
        slice(5, x0, y1 - fb, x0 + fl, y1)
        slice(7, x1 - fr, y1 - fb, x1, y1)
        slice(1, x0 + fl, y0, x1 - fr, y0 + ft)
        slice(6, x0 + fl, y1 - fb, x1 - fr, y1)
        slice(3, x0, y0 + ft, x0 + fl, y1 - fb)
        slice(4, x1 - fr, y0 + ft, x1, y1 - fb)
        if x1 - fr > x0 + fl && y1 - fb > y0 + ft {
            add(Self.fill(x0 + fl, y0 + ft, x1 - fr, y1 - fb, whiteColor, word: word))
        }
    }

    /// The ridge of a window in the modes 1..6 (knife `ClipRect::band`, sub_34A70, unrotated): a strip of the mode's colour along each edge, r = inset
    /// pixels wide inside the shrunk scissor, that fades out inward along the gradation texture; the solid outer half lies in the strip the scissor cuts away.
    /// Quads are clipped by the scissor.
    func addBand(_ list: DisplayList, _ c: ClipWindow, scissor: PixelRect?) {
        let half = Float(c.inset) * 0.5
        if half < 1.0 || !c.isBand {
            return
        }

        let (l, t) = (c.x * 0.5, c.y * 0.5)
        let (rx, by) = ((c.x + c.w) * 0.5, (c.y + c.h) * 0.5)
        let (w, h) = (rx - l, by - t)
        let r = min(half, min(w * 0.5, h * 0.5))
        if r <= 0 {
            return
        }

        let k = radiusClass(r)
        let n = Int(radii[k])
        let cr: UInt8
        let cg: UInt8
        let cb: UInt8
        switch c.mode {
        case 2: cr = 255; cg = 255; cb = 255
        case 3: cr = 255; cg = 0; cb = 0
        case 4: cr = 45; cg = 19; cb = 0
        case 5: cr = 246; cg = 244; cb = 232
        case 6: cr = 255; cg = 232; cb = 210
        default: cr = 0; cg = 0; cb = 0
        }
        let rgba = UInt32(cr) | (UInt32(cg) << 8) | (UInt32(cb) << 16) | 0xFF000000
        let over = 0

        func solid(_ x: Float, _ y: Float, _ qw: Float, _ qh: Float) {
            if qw > 0 && qh > 0 {
                var cmd = Self.fill(x * 2.0, y * 2.0, (x + qw) * 2.0, (y + qh) * 2.0, rgba, word: over)
                cmd.clip = scissor
                cmd.blendState = 1
                list.add(cmd)
            }
        }

        func slice(_ child: Int, _ pieceIndex: Int, _ x: Float, _ y: Float, _ qw: Float, _ qh: Float) {
            if qw > 0 && qh > 0 {
                let (u0, v0, u1, v1) = Self.piece(pieceIndex, n)
                var cmd = Self.textured(
                    tex: Self.border(child),
                    x0: x * 2.0, y0: y * 2.0, x1: (x + qw) * 2.0, y1: (y + qh) * 2.0,
                    u0: u0, v0: v0, u1: u1, v1: v1,
                    rgba: rgba,
                    word: over
                )
                cmd.clip = scissor
                cmd.blendState = 1
                list.add(cmd)
            }
        }

        let fullW = (l == 0 && w == 960.0)
        let fullH = (t == 0 && h == 540.0)
        let rl: Float = (l + r <= 0 || fullW) ? 0 : r
        let rr: Float = (rx - r >= 960.0 || fullW) ? 0 : r
        let rt: Float = (t + r <= 0 || fullH) ? 0 : r
        let rb: Float = (by - r >= 540.0 || fullH) ? 0 : r
        let gr = k, inv = k + 6

        let corners: [(on: Bool, x: Float, y: Float, piece: Int, ix: Float, iy: Float)] = [
            (rt > 0 && rl > 0, l, t, 0, l + r, t + r),
            (rb > 0 && rl > 0, l, by - r, 5, l + r, by - (2.0 * r)),
            (rr > 0 && rt > 0, rx - r, t, 2, rx - (2.0 * r), t + r),
            (rb > 0 && rr > 0, rx - r, by - r, 7, rx - (2.0 * r), by - (2.0 * r)),
        ]
        for cn in corners {
            if cn.on {
                solid(cn.x, cn.y, r, r)
                slice(inv, cn.piece, cn.ix, cn.iy, r, r)
            }
        }

        let along = w - (2.0 * rl) - (2.0 * rr)
        let down = h - (2.0 * rt) - (2.0 * rb)
        if rt > 0 {
            solid(l + rl, t, w - rl - rr, rt)
            slice(gr, 6, l + (2.0 * rl), t + rt, along, r)
        }
        if rb > 0 {
            solid(l + rl, by - rb, w - rl - rr, rb)
            slice(gr, 1, l + (2.0 * rl), by - (2.0 * rb), along, r)
        }
        if rl > 0 {
            solid(l, t + rt, rl, h - rt - rb)
            slice(gr, 4, l + rl, t + (2.0 * rt), r, down)
        }
        if rr > 0 {
            solid(rx - rr, t + rt, rr, h - rt - rb)
            slice(gr, 3, rx - (2.0 * rr), t + (2.0 * rt), r, down)
        }
    }
}
