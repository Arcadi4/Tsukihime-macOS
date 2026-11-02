import Foundation
import TsukiCore

/// The motion record helpers (24 bytes per layer: id, divisor, frame counter, pause; VA 0xBA800, 0xBA8E0, STMA 0xC0330) and one application
/// of a motion to a layer (VA 0xBE4C0; docs/formats/layers.md 8.2, 8.3). Port of `motion_record`, `motion_clear`, `motion_copy`
/// and `apply_motion` of `tsuki.misc_layer_state_and_motions`.
public enum MotionApply {
    // keyframe field -> enable mask in the per-motion flag word
    private static let mask3: UInt64 = 0x40880
    private static let mask4: UInt64 = 0x5100000
    private static let mask5: UInt64 = 0x4000
    private static let mask6: UInt64 = 0x10002
    private static let mask7: UInt64 = 0x20004
    private static let mask8: UInt64 = 0x88000
    private static let mask9: UInt64 = 0x80200000
    private static let mask10: UInt64 = 0x100400000
    private static let mask11And13: UInt64 = 0x10000080
    private static let mask12And14: UInt64 = 0x4000400
    private static let mask15: UInt64 = 0x10
    private static let mask16: UInt64 = 0x20
    private static let mask17: UInt64 = 0x2000000
    private static let mask18: UInt64 = 0x200
    private static let mask19: UInt64 = 0x200000000
    private static let mask22: UInt64 = 0x20000000
    private static let mask23: UInt64 = 0x40000000
    private static let mask24: UInt64 = 0x40
    private static let mask25: UInt64 = 0x100
    private static let mask26: UInt64 = 0x1000
    private static let mask27: UInt64 = 0x1
    private static let angleBit: UInt64 = 1 << 34

    @inline(__always) private static func f(_ x: Double) -> Double { Double(Float(x)) }
    @inline(__always) private static func f(_ x: Float) -> Double { Double(x) }

    /// Record change of `_STMA(l, id, w, n)` (VA 0xC0330), made to the scene record and to the drawn record. `id` (the
    /// 32-bit argument) above 0: id = i16(id), pause 0 (0xBA820), frames 0 (0xBA830), divisor n if i16(n) is above 0 else 0 (0xBA840).
    /// Otherwise (absent, 0, negative) only id = 0 and pause = 0: divisor and frame counter are kept.
    public static func motionRecord(recId: inout Int16, recDivisor: inout Int16, recFrames: inout Int64, recPause: inout UInt8, id: Int, n: Int) {
        recId = id > 0 ? StageMath.i16(Int64(id)) : 0
        recPause = 0
        if id > 0 {
            recFrames = 0
            recDivisor = max(StageMath.i16(Int64(n)), 0)
        }
    }

    /// Applies `motionRecord` to a drawn / committed record.
    public static func motionRecord(_ r: LayerRecord, _ id: Int, _ n: Int) {
        motionRecord(recId: &r.motionId, recDivisor: &r.motionDivisor, recFrames: &r.motionFrames, recPause: &r.motionPause, id: id, n: n)
    }

    /// VA 0xBA800: id = divisor = 0, frames = 0, pause = 0.
    public static func motionClear(_ r: LayerRecord) {
        r.motionId = 0
        r.motionDivisor = 0
        r.motionFrames = 0
        r.motionPause = 0
    }

    /// VA 0xBA8E0(dst, src): id, divisor and pause byte are copied; the frame counter only when the source id is above 0 and the destination
    /// counter is not larger.
    public static func motionCopy(dstId: inout Int16, dstDivisor: inout Int16, dstFrames: inout Int64, dstPause: inout UInt8, srcId: Int16, srcDivisor: Int16, srcFrames: Int64, srcPause: UInt8) {
        let dstF = dstFrames
        dstId = srcId
        if dstF <= srcFrames && srcId > 0 {
            dstFrames = srcFrames
        }
        dstDivisor = srcDivisor
        dstPause = srcPause
    }

    /// `motionCopy` between two records.
    public static func motionCopy(_ dst: LayerRecord, _ src: LayerRecord) {
        motionCopy(dstId: &dst.motionId, dstDivisor: &dst.motionDivisor, dstFrames: &dst.motionFrames, dstPause: &dst.motionPause,
                   srcId: src.motionId, srcDivisor: src.motionDivisor, srcFrames: src.motionFrames, srcPause: src.motionPause)
    }

    /// The scene copy of a layer's motion record (24 bytes at 0xD00 + 24 l) as record fields.
    public static func sceneMotion(_ s: SceneState, _ l: Int) -> (id: Int16, divisor: Int16, frames: Int64, pause: UInt8) {
        (s.getMotionId(l), s.getMotionDivisor(l), s.getMotionFrames(l), s.getMotionPause(l))
    }

    /// VA 0xF7A0 on a colour block (record +0x1F0, 17 bytes): +0 i16 = 0, +2 i16 = `par`, the old +5..+7 / +8..+0xA move to
    /// +0xB..+0xD / +0xE..+0x10, then +5..+7 = `rgb` and +8..+0xA = `rgb2` (bytes R, G, B).
    public static func colourBlock(_ block: inout [UInt8], _ rgb: Int, _ rgb2: Int = 0, _ par: Int = 0) {
        guard block.count >= 17 else { return }
        block[0] = 0
        block[1] = 0
        let p = StageMath.i16(Int64(par))
        block[2] = UInt8(truncatingIfNeeded: p & 0xFF)
        block[3] = UInt8(truncatingIfNeeded: (p >> 8) & 0xFF)
        block[0xB] = block[5]
        block[0xC] = block[6]
        block[0xD] = block[7]
        block[5] = UInt8(truncatingIfNeeded: (rgb >> 16) & 0xFF)
        block[6] = UInt8(truncatingIfNeeded: (rgb >> 8) & 0xFF)
        block[7] = UInt8(truncatingIfNeeded: rgb & 0xFF)
        block[0xE] = block[8]
        block[0xF] = block[9]
        block[0x10] = block[0xA]
        block[8] = UInt8(truncatingIfNeeded: (rgb2 >> 16) & 0xFF)
        block[9] = UInt8(truncatingIfNeeded: (rgb2 >> 8) & 0xFF)
        block[0xA] = UInt8(truncatingIfNeeded: rgb2 & 0xFF)
    }

    /// VA 0xF700: the colour block of a drawn record is reset to white with a white history (+5..+7 and +0xB..+0xD = FF, the rest 0).
    public static func colourReset(_ block: inout [UInt8]) {
        for i in 0..<block.count { block[i] = 0 }
        if block.count >= 17 {
            block[5] = 255
            block[6] = 255
            block[7] = 255
            block[0xB] = 255
            block[0xC] = 255
            block[0xD] = 255
        }
    }

    /// VA 0xFA90(ext + 6, rgb, 0): scene ext bytes +6..+8 = R, G, B and +9..+0xB = 0.
    private static func extColour(_ scene: SceneState, _ layer: Int, _ rgb: Int) {
        let e = scene.ext(layer)
        e[6] = UInt8(truncatingIfNeeded: (rgb >> 16) & 0xFF)
        e[7] = UInt8(truncatingIfNeeded: (rgb >> 8) & 0xFF)
        e[8] = UInt8(truncatingIfNeeded: rgb & 0xFF)
        e[9] = 0
        e[10] = 0
        e[11] = 0
    }

    private static func setExtI16(_ scene: SceneState, _ layer: Int, _ pos: Int, _ value: Int) {
        let e = scene.ext(layer)
        let v = StageMath.i16(Int64(value))
        e[pos] = UInt8(truncatingIfNeeded: v & 0xFF)
        e[pos + 1] = UInt8(truncatingIfNeeded: (v >> 8) & 0xFF)
    }

    /// One call of VA 0xBE4C0 for `layer` on its drawn record `rec`: advance the motion by `dt` frames,
    /// evaluate the enabled fields at the new time and write them to the record and, like the engine, to `scene` (scene writes
    /// need a scene picture, except the motion time and the colour key). Returns the key time used (ms) or null when nothing was applied.
    public static func apply(table: MotionTable, catalog: PictureCatalog, rec: LayerRecord, layer: Int, dt: Double, scene: SceneState?) -> Double? {
        if layer < 0 || layer > 39 {
            return nil
        }

        let mid = Int(rec.motionId)
        let div = Int(rec.motionDivisor)
        guard let mm = table.get(mid), mid > 0, mm.end > mm.start, mm.duration > 0 else {
            return nil
        }

        let m = mm
        let idt = StageMath.cvtt(dt)
        if idt != 0 && rec.motionPause == 0 {
            let frames = rec.motionFrames + Int64(idt)
            rec.motionFrames = frames >= 2 ? frames : 1
        }

        let qf = MotionMath.motionFrames(rec.motionFrames, div)
        let t0 = MotionMath.motionTimeMs(rec.motionFrames, div)
        guard let tk = MotionMath.keyTime(table, m, t0, table.loop(mid)) else {
            return nil
        }

        var t = tk
        if let scene = scene {
            scene.setMotionFrames(layer, qf)
        }

        let whole = mid == 9999
        if whole {
            let eid = table.val(m.start, 1)
            let last = Double(table.val(m.end - 1, 0))
            t = f(Easing.ease((eid == MotionTable.unset || eid == MotionTable.hold) ? 0 : eid, t, 0.0, last, last))
        }

        var k = -1
        for i in m.start..<m.end {
            if Double(table.val(i, 0)) >= t {
                k = i
                break
            }
        }

        if k < 0 {
            return nil
        }

        let s = m.start
        let e = m.end - 1
        var flags = table.flags(mid)
        let tt = t

        func val(_ fld: Int, _ cur: Double) -> Double {
            MotionMath.motionValue(table, fld, s, e, k, tt, cur, whole: whole)
        }
        func found(_ fld: Int) -> Bool {
            MotionMath.found(table, m, k, fld)
        }
        func sPic() -> Int {
            scene.map { Int($0.getPic(layer)) } ?? -1
        }
        func sceneOk() -> Bool {
            scene != nil && sPic() != -1
        }

        // 3, 4: position (0xBE7D2.., 0xBE912..)
        if !found(3) {
            flags &= ~mask3
        }
        if (flags & mask3) != 0 {
            let v = val(3, f(f(480.0 * Double(rec.x)) / 640.0))
            rec.x = Float(f(f(v * 640.0) / 480.0))
            if sceneOk() {
                scene?.setX(layer, StageMath.i16(Int64(StageMath.cvtt(rec.x))))
            }
        }

        if !found(4) {
            flags &= ~mask4
        }
        if (flags & mask4) != 0 {
            let v = val(4, f(f(360.0 * Double(rec.y)) / 480.0))
            rec.y = Float(f(f(v * 480.0) / 360.0))
            if sceneOk() {
                scene?.setY(layer, StageMath.i16(Int64(StageMath.cvtt(rec.y))))
            }
        }

        // 5: alpha (0xBEA47..); the running alpha-tween value is folded in only when dt == 0
        if !found(5) {
            flags &= ~mask5
        }
        if (flags & mask5) != 0 {
            var a = rec.alpha
            if dt == 0.0 {
                a += rec.alphaCur
                rec.alphaCur = 0
            }

            let v = val(5, f(Double(a) * 255.0))
            let c = 0.0 > v ? 0.0 : (v <= 255.0 ? v : 255.0)
            rec.alpha = Float(f(c / 255.0))
            if sceneOk() {
                scene?.setAlpha(layer, StageMath.i16(Int64(StageMath.cvtt(c))))
            }
        }

        // 22, 23: picture variant (0xBEB37..0xBF314): the name comes from the scene picture at t == 0 and from the drawn picture otherwise
        var srcPic = rec.pic
        if t == 0.0, scene != nil {
            srcPic = sPic()
        }

        var name = srcPic >= 0 ? PictureNames.engineName(catalog, srcPic) : ""
        var (hh, vv) = PictureNames.variantDigits(name)
        if !found(22) {
            flags &= ~mask22
        }
        if !found(23) {
            flags &= ~mask23
        }

        if (flags & (mask22 | mask23)) != 0 && rec.pic != -1 {
            let nh = (flags & mask22) != 0 ? max(Int(StageMath.cvtt(val(22, Double(hh)))), 0) : hh
            let nv = (flags & mask23) != 0 ? max(Int(StageMath.cvtt(val(23, Double(vv)))), 0) : vv
            if nh != hh || nv != vv {
                let n2 = PictureNames.variantName(name, hh, vv, nh, nv)
                let nid = catalog.lookup(n2)
                if nid >= 0 {
                    if let scene = scene {
                        let sp = sPic()
                        if t == 0.0 || rec.pic == sp {
                            let (cax, cay) = PictureNames.catalogAnchor(catalog, nid)
                            let ax: Int
                            let ay: Int
                            if sp == -1 {
                                ax = cax
                                ay = cay
                            } else {
                                let (csx, csy) = PictureNames.catalogAnchor(catalog, sp)
                                ax = Int(scene.getAnchorX(layer)) + cax - csx
                                ay = Int(scene.getAnchorY(layer)) + cay - csy
                            }

                            scene.setAnchorX(layer, StageMath.i16(Int64(ax)))
                            scene.setAnchorY(layer, StageMath.i16(Int64(ay)))
                            scene.setPic(layer, StageMath.i16(Int64(nid)))
                            setExtI16(scene, layer, 2, -ax)
                            setExtI16(scene, layer, 4, -ay)
                        }
                    }

                    if t > 0.0 {
                        let (ax, ay) = PictureNames.catalogAnchor(catalog, nid)
                        rec.pic = nid
                        rec.anchorX = StageMath.i16(Int64(ax))
                        rec.anchorY = StageMath.i16(Int64(ay))
                        rec.offX = -Float(StageMath.i16(Int64(ax)))
                        rec.offY = -Float(StageMath.i16(Int64(ay)))
                        rec.face = (nid >= 0 && nid < catalog.count && catalog.info(nid).hasFace) ? 1 : 0
                    }

                    name = n2
                    hh = nh
                    vv = nv
                }
            }
        }

        // anchor difference of a variant picture to its base (0xBF31B..0xBF389)
        var diffX: Int32 = 0
        var diffY: Int32 = 0
        if (hh | vv) != 0 {
            let baseName = name.count >= 6 ? String(name.dropLast(6)) : ""
            let bid = catalog.lookup(baseName)
            let (a1x, a1y) = PictureNames.catalogAnchor(catalog, rec.pic)
            let (b1x, b1y) = PictureNames.catalogAnchor(catalog, bid)
            diffX = StageMath.i32(Int64(StageMath.i16(Int64(a1x - b1x))))
            diffY = StageMath.i32(Int64(StageMath.i16(Int64(a1y - b1y))))
        }

        // 6, 7: anchor (0xBF391.., 0xBF4EA..); no found-scan
        if (flags & mask6) != 0 {
            let cur = Double(StageMath.cdiv(Int64(rec.anchorX) * 480, 640))
            let v = val(6, cur)
            var x = f(f(f(v * 640.0) / 480.0) + Double(diffX))
            let sp = scene != nil ? sPic() : rec.pic
            if sp != -1 {
                x = f(x * Double(classFactor(catalog, sp)))
            }

            rec.anchorX = StageMath.i16(Int64(StageMath.cvtt(x)))
            rec.offX = Float(-x)
            if let scene = scene, sPic() != -1 {
                scene.setAnchorX(layer, StageMath.i16(Int64(StageMath.cvtt(x))))
                setExtI16(scene, layer, 2, Int(StageMath.cvtt(-x)))
            }
        }

        if (flags & mask7) != 0 {
            let cur = Double(StageMath.cdiv(Int64(rec.anchorY) * 360, 480))
            let v = val(7, cur)
            var x = f(f(f(v * 480.0) / 360.0) + Double(diffY))
            let sp = scene != nil ? sPic() : rec.pic
            if sp != -1 {
                x = f(x * Double(classFactor(catalog, sp)))
            }

            rec.anchorY = StageMath.i16(Int64(StageMath.cvtt(x)))
            rec.offY = Float(-x)
            if let scene = scene, sPic() != -1 {
                scene.setAnchorY(layer, StageMath.i16(Int64(StageMath.cvtt(x))))
                setExtI16(scene, layer, 4, Int(StageMath.cvtt(-x)))
            }
        }

        // 8: rotation (0xBF648); the +0x15C angle only with flag bit 34 (0xBF6B8)
        if (flags & mask8) != 0 {
            let v = val(8, f(Double(rec.rot)))
            rec.rot = StageMath.cvtt64(v)
            if sceneOk() {
                scene?.setRot(layer, rec.rot)
            }
        }

        if (flags & angleBit) != 0 {
            let v = val(8, f(Double(rec.rot)))
            rec.angle = StageMath.i16(StageMath.cvtt64(v))
            if sceneOk() {
                scene?.setAngle(layer, rec.angle)
            }
        }

        // 9, 10: zoom. 0xBF724..0xBF754 first ends the zoom tween (delta 0, counter 0) on every call; a fractional value is stored rounded away
        // from zero with the fraction in that tween (delta = (v - zoom) * 0.001, counter 4096), so the drawn zoom is exactly v
        rec.zoomDx = 0
        rec.zoomDy = 0
        rec.twZoom.counter = 0
        if !found(9) {
            flags &= ~mask9
        }
        if !found(10) {
            flags &= ~mask10
        }

        for pass in 0..<2 {
            let fld = 9 + pass
            let mask = pass == 0 ? mask9 : mask10
            if (flags & mask) == 0 {
                continue
            }

            let v = val(fld, Double(pass == 0 ? rec.zoomX : rec.zoomY))
            var zi = StageMath.cvtt(v)
            if Double(StageMath.i16(Int64(zi))) != v {
                zi += v >= 0.0 ? 1 : -1
                let delta = Float(f(f(v - Double(StageMath.i16(Int64(zi)))) * f(0.001)))
                if pass == 0 {
                    rec.zoomDx = delta
                } else {
                    rec.zoomDy = delta
                }

                rec.twZoom.counter = 4096
            }

            if pass == 0 {
                rec.zoomX = StageMath.i16(Int64(zi))
                if sceneOk() {
                    scene?.setZoomX(layer, StageMath.i16(Int64(zi)))
                }
            } else {
                rec.zoomY = StageMath.i16(Int64(zi))
                if sceneOk() {
                    scene?.setZoomY(layer, StageMath.i16(Int64(zi)))
                }
            }
        }

        // 11..14: crop rectangle (0xBFA7A..); cur = the scene value when it differs from the drawn one
        for grp in 0..<2 {
            let cmask = grp == 0 ? mask11And13 : mask12And14
            if (flags & cmask) == 0 {
                continue
            }

            for sub in 0..<2 {
                let fld = grp == 0 ? (sub == 0 ? 11 : 13) : (sub == 0 ? 12 : 14)
                let j = fld - 11
                var cur = Double(rec.crop[j])
                if sceneOk() {
                    let sv = scene!.getCrop(layer, j)
                    cur = (sv == rec.crop[j]) ? Double(rec.crop[j]) : Double(sv)
                }

                rec.crop[j] = StageMath.i16(Int64(StageMath.cvtt(val(fld, cur))))
                if sceneOk() {
                    scene?.setCrop(layer, j, rec.crop[j])
                }
            }
        }

        // 15, 16: a17 / a16 (max 0)
        if (flags & mask15) != 0 {
            let v = max(0.0, val(15, Double(StageMath.i8(Int64(rec.a17)))))
            rec.a17 = UInt8(truncatingIfNeeded: StageMath.cvtt(v) & 0xFF)
            if sceneOk() {
                scene?.setA17(layer, rec.a17)
            }
        }

        if (flags & mask16) != 0 {
            let v = max(0.0, val(16, Double(StageMath.i16(Int64(rec.a16)))))
            rec.a16 = UInt16(truncatingIfNeeded: StageMath.cvtt(v) & 0xFFFF)
            if sceneOk() {
                scene?.setA16(layer, rec.a16)
            }
        }

        // 17: blend (written when it changes)
        if (flags & mask17) != 0 {
            let iv = StageMath.cvtt(val(17, Double(rec.blend)))
            if Int32(rec.blend) != iv {
                rec.blend = StageMath.i16(Int64(iv))
                if sceneOk() {
                    scene?.setBlend(layer, StageMath.i16(Int64(iv)))
                }
            }
        }

        func rgbFunc() -> Int {
            (Int(StageMath.cvtt(val(19, 0.0))) << 16) + (Int(StageMath.cvtt(val(20, 0.0))) << 8) + Int(StageMath.cvtt(val(21, 0.0)))
        }

        // 18: colour key (0xBFDF0..): value 1 sets the colour; the scene colour is set when the scene fx_mode byte is not 0xFF (no picture test)
        if (flags & mask18) != 0 && StageMath.cvtt(val(18, Double(rec.fxMode))) == 1 {
            let c = rgbFunc()
            colourBlock(&rec.colour, c)
            if let scene = scene, (Int(scene.getFxMode(layer)) & 0xFF) != 0xFF {
                extColour(scene, layer, c)
            }
        }

        // 19..21: colour (bit 33, 0xBFF57..)
        if (flags & mask19) != 0 {
            let c = rgbFunc()
            colourBlock(&rec.colour, c)
            if sceneOk() {
                extColour(scene!, layer, c)
            }
        }

        // 24, 25: colour-effect parameters; 26: noise
        if (flags & mask24) != 0 {
            let iv = StageMath.cvtt(val(24, Double(rec.fxA)))
            rec.fxA = StageMath.i16(Int64(iv))
            if sceneOk() {
                scene?.setFxA(layer, StageMath.i16(Int64(iv)))
            }
        }

        if (flags & mask25) != 0 {
            let iv = StageMath.cvtt(val(25, Double(rec.fxB)))
            if Int32(rec.fxB) != iv {
                rec.fxB = StageMath.i8(Int64(iv))
                if sceneOk() {
                    scene?.setFxB(layer, StageMath.i8(Int64(iv)))
                }
            }
        }

        if (flags & mask26) != 0 {
            let iv = StageMath.cvtt(val(26, Double(StageMath.i8(Int64(rec.stns)))))
            if Int32(StageMath.i8(Int64(rec.stns))) != iv {
                let nb: UInt8 = iv < 3 ? 20 : 12
                rec.stns = UInt8(truncatingIfNeeded: iv & 0xFF)
                rec.stnsB = nb
                if sceneOk() {
                    scene?.setStns(layer, rec.stns)
                    scene?.setStnsB(layer, nb)
                }
            }
        }

        // 27: z order (only when v != 0 and the scene z is not 0)
        if (flags & mask27) != 0, let scene = scene {
            let v = val(27, 0.0)
            if v != 0.0 && scene.getZ(layer) != 0 {
                rec.zOrder = Int(StageMath.cvtt(v))
                if sceneOk() {
                    scene.setZ(layer, StageMath.i16(Int64(StageMath.cvtt(v))))
                }
            }
        }

        return t
    }

    private static func classFactor(_ c: PictureCatalog, _ pic: Int) -> Float {
        let cls = PictureNames.scaleClass(c, pic)
        switch cls {
        case 1: return 0.5
        case 2: return 0.25
        case 3: return 0.125
        default: return 1.0
        }
    }
}
