import Foundation

/// A 2 x 3 affine map: `x' = a u + b v + c`, `y' = d u + e v + f` (the oracle's `Affine`).
public struct Affine: Sendable, Equatable {
    public var a: Double
    public var b: Double
    public var c: Double
    public var d: Double
    public var e: Double
    public var f: Double

    public init(a: Double, b: Double, c: Double, d: Double, e: Double, f: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.e = e
        self.f = f
    }

    /// The identity.
    public static let identity = Affine(a: 1, b: 0, c: 0, d: 0, e: 1, f: 0)

    /// Composition: `this . o` (apply `o` first).
    public static func * (l: Affine, o: Affine) -> Affine {
        Affine(
            a: (l.a * o.a) + (l.b * o.d),
            b: (l.a * o.b) + (l.b * o.e),
            c: (l.a * o.c) + (l.b * o.f) + l.c,
            d: (l.d * o.a) + (l.e * o.d),
            e: (l.d * o.b) + (l.e * o.e),
            f: (l.d * o.c) + (l.e * o.f) + l.f
        )
    }

    /// Maps a point.
    public func apply(_ u: Double, _ v: Double) -> (x: Double, y: Double) {
        ((a * u) + (b * v) + c, (d * u) + (e * v) + f)
    }

    /// A translation.
    public static func translate(_ x: Double, _ y: Double) -> Affine {
        Affine(a: 1, b: 0, c: x, d: 0, e: 1, f: y)
    }

    /// A scale.
    public static func scale(_ sx: Double, _ sy: Double) -> Affine {
        Affine(a: sx, b: 0, c: 0, d: 0, e: sy, f: 0)
    }

    /// A rotation by `rad` (clockwise on a y-down screen).
    public static func rotate(_ rad: Double) -> Affine {
        let c = cos(rad)
        let s = sin(rad)
        return Affine(a: c, b: -s, c: 0, d: s, e: c, f: 0)
    }
}

/// The 2D projection of a layer: picture texels to the 640 x 362.667 scene canvas to the 1920 x 1080 frame (docs/formats/layers.md 7; VA 0x51060
/// -> 0xEB780 -> 0xDD6D0). Port of `layer_world`, `layer_zoom`, `layer_rot`, `layer_matrix`, `sprite_matrix` and
/// `canvas_to_frame` of `tsuki.misc_layer_state_and_motions`, working on the drawn records.
public enum Projection {
    /// The scene canvas size (VA 0x1A7710).
    public static let canvasW: Double = 640.0

    /// The scene canvas height, 362.6666564941406.
    public static let canvasH: Double = 362.6666564941406

    /// Texel to canvas, x (global scale 1/3).
    public static let pxX: Double = 1.0 / 3.0

    /// Texel to canvas, y: the float32 of 362.667 / 1080 (0.3358025).
    public static let pxY: Double = Double(StageMath.f(362.6666564941406 / 1080.0))

    private static let maxDepth = 64

    /// The canvas command VA 0xDCBE0(w, h, 0, 0): frame pixel = canvas unit * (1920 / w, 1080 / h).
    public static func canvasToFrame() -> Affine {
        Affine.scale(1920.0 / canvasW, 1080.0 / canvasH)
    }

    private static func ok(_ recs: [LayerRecord], _ p: Int) -> Bool {
        p >= 0 && p < recs.count && recs[p].used != 0
    }

    private static func classFactorOf(_ c: PictureCatalog, _ pic: Int) -> Float {
        pic >= 0 && pic <= 0x39B6 && pic < c.count ? c.info(pic).classFactor : 1.0
    }

    /// The own zoom (per mille) of a record: end + delta * remaining (VA 0x528C0 / 0x529F0 without the parent factor).
    public static func zoomTween(_ r: LayerRecord) -> (x: Float, y: Float) {
        let rem = r.twZoom.remaining()
        let zx = (r.zoomDx / 0.001 * rem) + Float(r.zoomX)
        let zy = (r.zoomDy / 0.001 * rem) + Float(r.zoomY)
        return (zx, zy)
    }

    /// VA 0x528C0 / 0x529F0: zoom per mille including the parents: `z * zp / 1000 * class(parent)`.
    public static func layerZoom(_ recs: [LayerRecord], _ l: Int, _ cat: PictureCatalog, depth: Int = 0) -> (x: Float, y: Float) {
        var (zx, zy) = zoomTween(recs[l])
        let p = recs[l].parent
        if ok(recs, p) && depth < maxDepth {
            let (pzx, pzy) = layerZoom(recs, p, cat, depth: depth + 1)
            zx *= pzx * 0.001
            zy *= pzy * 0.001
            let fac = classFactorOf(cat, recs[p].pic)
            zx *= fac
            zy *= fac
        }
        return (zx, zy)
    }

    /// VA 0x4C3E0: rotation (1/100 degree) summed over the parent chain.
    public static func layerRot(_ recs: [LayerRecord], _ l: Int, depth: Int = 0) -> Float {
        let r = Float(recs[l].rot)
        let p = recs[l].parent
        return p >= 0 && p < 40 && ok(recs, p) && depth < maxDepth ? layerRot(recs, p, depth: depth + 1) + r : r
    }

    /// VA 0x525B0 / 0x52740: the position of a layer in canvas units. A child's (x, y) is a point in its parent's picture: relative to the parent's
    /// anchor, times the size-class factor of the parent's picture, times the parent's zoom, rotated by the parent's rotation, plus the parent's position.
    public static func layerWorld(_ recs: [LayerRecord], _ l: Int, _ cat: PictureCatalog, depth: Int = 0) -> (x: Float, y: Float) {
        let r = recs[l]
        let x = r.x
        let y = r.y
        let p = r.parent
        if !ok(recs, p) || depth >= maxDepth {
            return (x, y)
        }

        let (px, py) = layerWorld(recs, p, cat, depth: depth + 1)
        var (zx, zy) = layerZoom(recs, p, cat, depth: depth + 1)
        zx *= 0.001
        zy *= 0.001
        let th = Double(layerRot(recs, p) * Float.pi / 180.0 / -100.0)
        let fac = classFactorOf(cat, recs[p].pic)
        let dx = Double((x * fac - Float(recs[p].anchorX)) * zx)
        let dy = Double((Float(recs[p].anchorY) - (y * fac)) * zy)
        let c = cos(th)
        let s = sin(th)
        return (Float(Double(px) + (dx * c) - (dy * s)), Float(Double(py) - (dx * s) - (dy * c)))
    }

    /// The picture offset (+0x50 / +0x54) plus the integer anchor: the part of the offset the draw adds untransformed (VA 0x519FF..0x51A1C).
    public static func anchorResidual(_ r: LayerRecord) -> (x: Float, y: Float) {
        (r.offX + Float(r.anchorX), r.offY + Float(r.anchorY))
    }

    /// Map from picture texels of layer `l` to scene-canvas units, as the draw (VA 0x51060 -> 0xEB780 -> 0xDD6D0) computes it.
    /// `extra` (canvas units) is the screen-effect offset and the shake offsets of the slots, added to the translation column
    /// untransformed (and, with the STZ4 pivot flag, before the screen-space zoom); `positionShift` is the mask-layer term, added
    /// to the layer position (so it also moves the pivot-zoom point P).
    public static func layerMatrix(_ recs: [LayerRecord], _ l: Int, _ cat: PictureCatalog, extra: (x: Float, y: Float) = (0, 0), positionShift: (x: Float, y: Float) = (0, 0)) -> Affine {
        let r = recs[l]
        let (wx, wy) = layerWorld(recs, l, cat)
        let tw = r.twMove.remaining()
        // the oracle rounds the three-term sums once (float64 sum, one float32 rounding)
        var xx = Float(Double(wx) + Double(r.dx) + (Double(r.moveDx) * Double(tw)))
        var yy = Float(Double(wy) + Double(r.dy) + (Double(r.moveDy) * Double(tw)))
        xx += positionShift.x
        yy += positionShift.y
        let (zx, zy) = layerZoom(recs, l, cat)
        let s = Float((Double(r.scale) * Double(Float(0.001))) + Double(r.scaleCur))

        // 0x51574..0x515F6: the angle adds the DIRECT parent's rotation whenever its index is 0..39, without the in-use test of 0x4C3E0
        let p = r.parent
        let own = Float(r.rot) + Float(r.rotCur)
        let rot = (p >= 0 && p < recs.count) ? layerRot(recs, p) + own : own
        let ang = StageMath.cvtt((rot * 32768.0) / 18000.0)
        let th = Double(ang) * 2.0 * Double.pi / 65536.0
        let soxyX = Double(r.soxyX) * pxX
        let soxyY = Double(r.soxyY) * Double(StageMath.f(448.0 / 1080.0))

        let local: Affine
        let screenZoom: Affine
        if r.zoomPivot != 0 {
            local = Affine.scale(Double(s) * pxX, Double(s) * pxY)
            screenZoom = Affine.scale(Double(zx) * 0.001, Double(zy) * 0.001)
        } else {
            local = Affine.scale(Double(s) * Double(zx) * 0.001 * pxX, Double(s) * Double(zy) * 0.001 * pxY)
            screenZoom = Affine.identity
        }

        let ax = Double(r.anchorX)
        let ay = Double(r.anchorY)
        let (resX, resY) = anchorResidual(r)
        let off = Affine.translate(-ax / pxX, -ay / pxY)
        let m = Affine.translate(Double(xx), Double(yy)) * Affine.rotate(th) * local * off
        let tx = soxyX + Double(resX) + Double(extra.x)
        let ty = soxyY + Double(resY) + Double(extra.y)
        if r.zoomPivot != 0 {
            // 0x51FF5..0x52087: pivot = position + anchor - catalog anchor of the picture
            let (cax, cay): (Int, Int) = (r.pic >= 0 && r.pic < cat.count) ? (cat.info(r.pic).anchorX, cat.info(r.pic).anchorY) : (0, 0)
            let px = Double(StageMath.f(Double(xx) + ax - Double(cax)))
            let py = Double(StageMath.f(Double(yy) + ay - Double(cay)))
            return Affine.translate(px, py) * screenZoom * Affine.translate(-px + tx, -py + ty) * m
        }

        return Affine.translate(tx, ty) * m
    }

    /// Picture texels to 1920 x 1080 frame pixels.
    public static func frameMatrix(_ recs: [LayerRecord], _ l: Int, _ cat: PictureCatalog, extra: (x: Float, y: Float) = (0, 0), positionShift: (x: Float, y: Float) = (0, 0)) -> Affine {
        canvasToFrame() * layerMatrix(recs, l, cat, extra: extra, positionShift: positionShift)
    }
}
