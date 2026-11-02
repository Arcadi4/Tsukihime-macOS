import Foundation
import TsukiCore

extension StageRuntime {
    private static let oneOver255 = StageMath.f(1.0 / 255.0)

    /// Runs one layer statement: `STCH SCH2 STCC STCP STBR STEC SNX2 SNX3 STZ4 STRT STRR STRA STPV SOXY STGS STMA SPMA STNS STTR SACL SBAS STCL
    /// SQK2 SHK2 SSW2 SQS2 SHS2 SSS2 SGMA STCF FADS SHOK SHAF MSQK` (docs/formats/layers.md 4, quake.md 3, 6, 7). The arguments are read the way the
    /// PS4 handlers read them (the object parser; `STPV` and `SHOK` inline). Returns false for a statement that is not a stage command.
    public func execute(_ statement: Statement) -> Bool {
        let first = statement.name.first
        if first != UInt8(ascii: "S") && first != UInt8(ascii: "F") && first != UInt8(ascii: "M") {
            return false
        }

        let name = statement.name.description
        switch name {
        case "STPV":
            cmdStpv(statement)
            return true
        case "SHOK":
            cmdShok(statement)
            return true
        case "STCH", "SCH2", "STCC", "STCP", "STBR", "STEC", "SNX2", "SNX3", "STZ4", "STRT", "STRR", "STRA", "SOXY",
             "STGS", "STMA", "SPMA", "STNS", "STTR", "SACL", "SBAS", "STCL", "SQK2", "SHK2", "SSW2", "SQS2", "SHS2",
             "SSS2", "SGMA", "STCF", "FADS", "SHAF", "MSQK":
            break
        default:
            return false
        }

        let a = StageArgs(statement)
        switch name {
        case "STCH":
            cmdStch(a, reset: true)
        case "SCH2":
            cmdStch(a, reset: false)
        case "STCC":
            cmdStcc(a)
        case "STCP":
            let l = a.has(0) ? a.expr(0) : 0
            if (0...39).contains(l) {
                scene.setZ(l, StageMath.i16(Int64(a.expr(1))))
            }
        case "STBR":
            let l = a.has(0) ? a.expr(0) : 0
            if (0...39).contains(l) {
                scene.setBlend(l, StageMath.i16(Int64(a.expr(1))))
                if a.has(3) && a.expr(3) == 1 {
                    scene.setFlags(l, scene.getFlags(l) | 0x80)
                }
            }
        case "STEC":
            cmdStec(a)
        case "SNX2":
            let l = a.has(0) ? a.expr(0) : -1
            if (0...39).contains(l) {
                scene.setFxA(l, StageMath.i16(Int64(a.expr(1))))
            }
        case "SNX3":
            let l = a.has(0) ? a.expr(0) : -1
            if (0...39).contains(l) {
                scene.setFxB(l, StageMath.i8(Int64(a.expr(1))))
            }
        case "STZ4":
            cmdStz4(a)
        case "STRT":
            cmdStrt(a)
        case "STRR":
            let l = a.has(0) ? a.expr(0) : 0
            if (0...39).contains(l) {
                var v = 0
                if a.has(1) {
                    let r = a.expr(1)
                    v = r == -100001 ? -32768 : Int(StageMath.wrapAngle(Int32(truncatingIfNeeded: r)))
                }
                scene.setAngle(l, StageMath.i16(Int64(v)))
            }
        case "STRA":
            cmdStra(a)
        case "SOXY":
            let l = a.has(0) ? a.expr(0) : 0
            writeRawByte(0xAA8 + l, UInt8(truncatingIfNeeded: a.expr(1)))
            writeRawByte(0xAD0 + l, UInt8(truncatingIfNeeded: a.expr(2)))
        case "STGS":
            cmdStgs(a)
        case "STMA":
            cmdStma(a)
        case "SPMA":
            let v: UInt8 = a.has(0) && a.expr(0) == 1 ? 1 : 0
            for k in 0..<Self.layerCount {
                scene.setMotionPause(k, v)
                drawn[k].motionPause = v
            }
        case "STNS":
            cmdStns(a)
        case "STTR":
            cmdSttr(a)
        case "SACL":
            let l = a.has(0) ? a.expr(0) : 0
            if (0...39).contains(l) {
                let f = scene.getFlags(l)
                scene.setFlags(l, a.has(1) && a.expr(1) != 0 ? (f | 0x40) : (f & ~0x40))
            }
        case "SBAS":
            let l = a.has(0) ? a.expr(0) : 0
            if (0...39).contains(l) {
                scene.setParent(l, Int32(a.has(1) ? a.expr(1) : -1))
            }
        case "STCL":
            cmdStcl(a)
        case "SQK2":
            cmdSqk2(a)
        case "SHK2":
            cmdShk2(a)
        case "SSW2":
            cmdSsw2(a)
        case "SQS2":
            cmdStopShake(a, 1)
        case "SHS2":
            cmdStopShake(a, 2)
        case "SSS2":
            cmdStopShake(a, 3)
        case "SGMA":
            cmdSgma(a)
        case "STCF":
            break
        case "FADS":
            cmdFads(a)
        case "SHAF":
            shock.stop()
        case "MSQK":
            messageQuake.start(ms: a.has(0) ? a.expr(0) : 1000,
                               a1: a.has(1) ? a.expr(1) : 5,
                               a2: a.has(2) ? a.expr(2) : 5)
        default:
            return false
        }

        return true
    }

    private func writeRawByte(_ offset: Int, _ value: UInt8) {
        if offset >= 0 && offset < SceneState.size {
            scene.writeU8(offset, value)
        }
    }

    private func setExtOffsets(_ l: Int, _ ax: Int, _ ay: Int) {
        let e = scene.ext(l)
        let x = StageMath.i16(Int64(-ax))
        let y = StageMath.i16(Int64(-ay))
        e[2] = UInt8(truncatingIfNeeded: x & 0xFF)
        e[3] = UInt8(truncatingIfNeeded: (x >> 8) & 0xFF)
        e[4] = UInt8(truncatingIfNeeded: y & 0xFF)
        e[5] = UInt8(truncatingIfNeeded: (y >> 8) & 0xFF)
    }

    private func setExtWhite(_ l: Int) {
        let e = scene.ext(l)
        e[6] = 255
        e[7] = 255
        e[8] = 255
        e[9] = 0
        e[10] = 0
        e[11] = 0
        e[12] = 0
        e[13] = 0
    }

    private func resetDrawn(_ l: Int) {
        let r = drawn[l]
        r.alphaCur = 0
        r.moveDx = 0
        r.moveDy = 0
        r.alphaDelta = 0
        r.angle = 0
        MotionApply.motionClear(r)
        r.blend = 0
        r.fxMode = 0
        r.fxA = 0
        r.fxB = 0
        MotionApply.colourReset(&r.colour)
        shakes.resetLayer(l)
        r.stra = 0
        r.straPhase = 0
        r.stns = 0
        r.stnsB = 0
    }

    private func cmdStch(_ a: StageArgs, reset: Bool) {
        let s = scene
        let l = a.has(0) ? a.expr(0) : -1
        guard (0...39).contains(l) else { return }

        let src = a.has(18) ? a.expr(18) : -1
        var name = a.str(1)
        if name.count > 255 {
            name = String(name.prefix(255))
        }

        let hasSrc = (0...39).contains(src)
        var h = 0
        var v = 0
        if hasSrc {
            let p = Int(s.getPic(src))
            if p >= 0 && p < catalog.count {
                let d = PictureNames.variantDigitsStch(catalog.name(p))
                h = d.h
                v = d.v
            }
        }

        if a.has(9) {
            h = a.expr(9)
        }
        if a.has(10) {
            v = a.expr(10)
        }

        if (h | v) != 0 {
            let hStr = String(format: "%02d", h > 0 ? h % 100 : 0)
            let vStr = String(format: "%02d", v > 0 ? v % 100 : 0)
            name += "_\(hStr)_\(vStr)"
        }

        if reset {
            let ar = drawn[l]
            ar.rot = 0
            ar.rotDelta = 0
            ar.rotCur = 0
        }

        resetDrawn(l)

        s.setZoomY(l, 1000)
        s.setZoomX(l, 1000)
        s.setZoomPivot(l, 0)
        let pic = catalog.lookup(name)
        if hasSrc {
            copySourceLayer(src: src, l: l, pic: pic, name: name)
        } else {
            for sl in 0..<2 {
                s.setShakeKind(l, sl, 0)
                s.setShakeFade(l, sl, 0)
                s.setShakeTime(l, sl, 0)
            }
            for i in 0..<12 {
                s.setShakePar(l, i, 0)
            }
        }

        if name.isEmpty {
            s.setPic(l, -1)
            s.setScale(l, 1000)
            s.setAnchorX(l, 0)
            s.setAnchorY(l, 0)
            s.setRot(l, 0)
            s.setMask(l, -1)
            s.setParent(l, -1)
            s.setSoxyX(l, 0)
            s.setSoxyY(l, 0)
            s.setFlags(l, 0)
            for j in 0..<4 {
                s.setCrop(l, j, 0)
            }
            s.setA16(l, 0)
            s.setA17(l, 0)
            s.setAngle(l, 0)
            s.setSttr(l, -1)
            s.motion(l).clear()
            s.setBlend(l, 0)
            s.setFxMode(l, 0)
            s.setFxA(l, 0)
            s.setFxB(l, 0)
            for sl in 0..<2 {
                s.setShakeKind(l, sl, 0)
                s.setShakeFade(l, sl, 0)
                s.setShakeTime(l, sl, 0)
            }
            for i in 0..<12 {
                s.setShakePar(l, i, 0)
            }
            MotionApply.motionClear(committed[l])
            setExtWhite(l)
            return
        }

        if a.has(11) {
            s.setMask(l, StageMath.i16(Int64(a.expr(11))))
        }

        s.setSttr(l, -1)
        for k in 0..<4 {
            if a.has(12 + k) {
                s.setCrop(l, k, StageMath.i16(Int64(a.expr(12 + k))))
            }
        }

        if a.has(16) {
            s.setA16(l, UInt16(truncatingIfNeeded: a.expr(16) & 0xFFFF))
        }
        if a.has(17) {
            s.setA17(l, UInt8(truncatingIfNeeded: a.expr(17) & 0xFF))
        }
        if a.has(19) {
            s.setAngle(l, StageMath.i16(Int64(StageMath.wrapAngle(Int32(truncatingIfNeeded: a.expr(19))))))
        }

        if src < 0 {
            s.motion(l).clear()
            MotionApply.motionClear(drawn[l])
            MotionApply.motionClear(committed[l])
            MotionApply.colourBlock(&drawn[l].colour, 0xFFFFFF)
            s.setBlend(l, 0)
            s.setFxMode(l, 0)
            s.setFxA(l, 0)
            s.setFxB(l, 0)
            setExtWhite(l)
            if s.getPic(l) < 0 {
                s.setAlpha(l, 0)
                drawn[l].alpha = 0
            }
        }

        s.setPic(l, StageMath.i16(Int64(pic)))
        if a.has(2) {
            s.setX(l, StageMath.i16(Int64(StageMath.scriptX(Int32(truncatingIfNeeded: a.expr(2))))))
        }
        if a.has(3) {
            s.setY(l, StageMath.i16(Int64(StageMath.scriptY(Int32(truncatingIfNeeded: a.expr(3))))))
        }

        if reset {
            if pic >= 0 {
                let pi = catalog.info(pic)
                s.setAnchorX(l, StageMath.i16(Int64(pi.anchorX)))
                s.setAnchorY(l, StageMath.i16(Int64(pi.anchorY)))
            }
            s.setRot(l, 0)
        }

        if a.has(4) {
            s.setScale(l, StageMath.i16(Int64(a.expr(4))))
        }

        if reset || a.has(5) {
            let alphaVal = a.has(5) ? max(0, min(a.expr(5), 255)) : 255
            s.setAlpha(l, StageMath.i16(Int64(alphaVal)))
            s.setState(l, 0)
        }

        if reset || a.has(6) {
            s.setZ(l, StageMath.i16(Int64(a.has(6) ? a.expr(6) : 10 * l)))
        }

        if !hasSrc {
            let (ax, ay) = pic >= 0 ? (catalog.info(pic).anchorX, catalog.info(pic).anchorY) : (256, 255)
            setExtOffsets(l, ax, ay)
            if pic >= 0 {
                s.setAnchorX(l, StageMath.i16(Int64(ax)))
                s.setAnchorY(l, StageMath.i16(Int64(ay)))
            }
        }

        if defaultColourEffect > 0 && (pic < 0 || (catalog.info(pic).drawFlags & 1) == 0) {
            s.setFxMode(l, StageMath.i8(Int64(defaultColourEffect)))
        }
    }

    private func copySourceLayer(src: Int, l: Int, pic: Int, name: String) {
        let s = scene
        s.setBlend(l, s.getBlend(src))
        s.setFxMode(l, s.getFxMode(src))
        s.setFxA(l, s.getFxA(src))
        s.setFxB(l, s.getFxB(src))
        s.setX(l, s.getX(src))
        s.setY(l, s.getY(src))
        s.setAlpha(l, s.getAlpha(src))
        s.setState(l, s.getState(src))
        s.setU284(l, s.getU284(src))
        s.setU2AC(l, s.getU2AC(src))
        s.setU2D4(l, s.getU2D4(src))
        s.setZ(l, s.getZ(src))
        s.setRot(l, s.getRot(src))
        s.setScale(l, s.getScale(src))
        s.setAnchorX(l, s.getAnchorX(src))
        s.setAnchorY(l, s.getAnchorY(src))
        s.setU580(l, s.getU580(src))
        s.setU5D0(l, s.getU5D0(src))
        s.setU620(l, s.getU620(src))
        s.setU670(l, s.getU670(src))
        s.setU6C0(l, s.getU6C0(src))
        s.setU710(l, s.getU710(src))
        s.setU760(l, s.getU760(src))
        s.setU7B0(l, s.getU7B0(src))
        s.setU800(l, s.getU800(src))
        s.setU850(l, s.getU850(src))

        let sp = Int(s.getPic(src))
        if sp >= 0 && sp < catalog.count && catalog.info(sp).anchorX == Int(s.getAnchorX(src)) && catalog.info(sp).anchorY == Int(s.getAnchorY(src)) {
            let (dx, dy) = name.isEmpty ? (0, -1) : (256, 255)
            let known = pic >= 0 && pic < catalog.count
            s.setAnchorX(l, StageMath.i16(Int64(known ? catalog.info(pic).anchorX : dx)))
            s.setAnchorY(l, StageMath.i16(Int64(known ? catalog.info(pic).anchorY : dy)))
        }

        s.setZoomX(l, s.getZoomX(src))
        s.setZoomY(l, s.getZoomY(src))
        s.setZoomPivot(l, s.getZoomPivot(src))
        s.setMask(l, s.getMask(src))
        for k in 0..<Self.layerCount {
            if s.getMask(k) == src {
                s.setMask(k, StageMath.i16(Int64(l)))
            }
        }

        s.setParent(l, s.getParent(src))
        for k in 0..<Self.layerCount {
            if s.getParent(k) == src {
                s.setParent(k, Int32(l))
            }
        }

        s.setSoxyX(l, s.getSoxyX(src))
        s.setSoxyY(l, s.getSoxyY(src))
        s.setFlags(l, s.getFlags(src))
        for j in 0..<4 {
            s.setCrop(l, j, s.getCrop(src, j))
        }

        s.setA16(l, s.getA16(src))
        s.setA17(l, s.getA17(src))
        s.setAngle(l, s.getAngle(src))
        s.setU19AB(l, s.getU19AB(src))
        s.setU19D3(l, s.getU19D3(src))

        s.setMotionId(l, 0)
        s.setMotionDivisor(l, 0)
        s.setMotionFrames(l, 0)
        s.setMotionPause(l, 0)
        let sid = s.getMotionId(src)
        let sdiv = s.getMotionDivisor(src)
        let sfr = s.getMotionFrames(src)
        let sps = s.getMotionPause(src)
        let dfr = s.getMotionFrames(l)
        s.setMotionId(l, sid)
        if dfr <= sfr && sid > 0 {
            s.setMotionFrames(l, sfr)
        }
        s.setMotionDivisor(l, sdiv)
        s.setMotionPause(l, sps)

        for sl in 0..<2 {
            s.setShakeKind(l, sl, s.getShakeKind(src, sl))
            s.setShakeFade(l, sl, s.getShakeFade(src, sl))
            s.setShakeTime(l, sl, s.getShakeTime(src, sl))
        }
        for i in 0..<12 {
            s.setShakePar(l, i, s.getShakePar(src, i))
        }

        s.setStra(l, s.getStra(src))
        let ax = Int(s.getAnchorX(l))
        let ay = Int(s.getAnchorY(l))
        s.ext(l).copy(from: s.ext(src).span)
        setExtOffsets(l, ax, ay)

        let ex = s.ext(l)
        let rgb1 = (Int(ex[6]) << 16) | (Int(ex[7]) << 8) | Int(ex[8])
        let rgb2 = (Int(ex[9]) << 16) | (Int(ex[10]) << 8) | Int(ex[11])
        MotionApply.colourBlock(&drawn[l].colour, rgb1, rgb2)
    }

    private func cmdStcc(_ a: StageArgs) {
        let l = a.has(0) ? a.expr(0) : 0
        if l > 39 {
            return
        }

        let from = l < 0 ? 0 : l
        let to = l < 0 ? Self.layerCount : l + 1
        for k in from..<to {
            let s = scene
            s.setPic(k, -1)
            s.setScale(k, 1000)
            s.setAnchorY(k, 0)
            s.setAnchorX(k, 0)
            s.setRot(k, 0)
            s.setZ(k, 0)
            s.setX(k, 0)
            s.setY(k, 0)
            s.setAlpha(k, 255)
            s.setZoomY(k, 1000)
            s.setZoomX(k, 1000)
            s.setZoomPivot(k, 0)
            s.setMask(k, -1)
            s.setParent(k, -1)
            s.setSoxyX(k, 0)
            s.setSoxyY(k, 0)
            s.setFlags(k, 0)
            for j in 0..<4 {
                s.setCrop(k, j, 0)
            }
            s.setA16(k, 0)
            s.setA17(k, 0)
            s.setAngle(k, 0)
            s.setSttr(k, -1)
            s.motion(k).clear()
            s.setBlend(k, 0)
            s.setFxMode(k, 0)
            s.setFxA(k, 0)
            s.setFxB(k, 0)
            for sl in 0..<2 {
                s.setShakeKind(k, sl, 0)
                s.setShakeFade(k, sl, 0)
                s.setShakeTime(k, sl, 0)
            }
            for i in 0..<12 {
                s.setShakePar(k, i, 0)
            }
            s.setStra(k, 0)
            s.setStns(k, 0)
            s.setStnsB(k, 0)

            let r = drawn[k]
            r.angle = 0
            for ci in 0..<r.crop.count { r.crop[ci] = 0 }
            r.a16 = 0
            r.a17 = 0
            r.sttr = -1
            MotionApply.motionClear(r)
            MotionApply.motionClear(committed[k])
            MotionApply.colourReset(&r.colour)
        }
    }

    private func cmdStec(_ a: StageArgs) {
        let l = a.has(0) ? a.expr(0) : -1
        let mode = a.has(1) ? a.expr(1) : 0
        guard (0...39).contains(l), (0...81).contains(mode) else {
            return
        }

        let rgb = mode == 1 ? Self.strtol0(a.str(2)) & 0xFFFFFF : 0xFFFFFF
        scene.setFxMode(l, StageMath.i8(Int64(mode)))
        let e = scene.ext(l)
        e[6] = UInt8(truncatingIfNeeded: (rgb >> 16) & 0xFF)
        e[7] = UInt8(truncatingIfNeeded: (rgb >> 8) & 0xFF)
        e[8] = UInt8(truncatingIfNeeded: rgb & 0xFF)
        MotionApply.colourBlock(&drawn[l].colour, rgb)
    }

    /// `strtol(s, NULL, 0)` of the STEC colour argument (hexadecimal with 0x, octal with a leading 0, else decimal).
    static func strtol0(_ s: String) -> Int {
        let chars = Array(s)
        var i = 0
        while i < chars.count && (chars[i] == " " || chars[i] == "\t" || chars[i] == "\n" || chars[i] == "\r" || chars[i] == "\u{000B}" || chars[i] == "\u{000C}") {
            i += 1
        }

        var neg = false
        if i < chars.count && (chars[i] == "+" || chars[i] == "-") {
            neg = chars[i] == "-"
            i += 1
        }

        var radix = 10
        if i + 1 < chars.count && chars[i] == "0" && (chars[i + 1] == "x" || chars[i + 1] == "X") && i + 2 < chars.count && chars[i + 2].isHexDigit {
            radix = 16
            i += 2
        } else if i < chars.count && chars[i] == "0" {
            radix = 8
        }

        var val: Int64 = 0
        var digits = 0
        while i < chars.count {
            let c = chars[i]
            let d: Int
            if c >= "0" && c <= "9" {
                d = Int(c.asciiValue! - UInt8(ascii: "0"))
            } else if c >= "a" && c <= "f" {
                d = Int(c.asciiValue! - UInt8(ascii: "a")) + 10
            } else if c >= "A" && c <= "F" {
                d = Int(c.asciiValue! - UInt8(ascii: "A")) + 10
            } else {
                break
            }

            if d >= radix {
                break
            }

            val = (val &* Int64(radix)) &+ Int64(d)
            digits += 1
            i += 1
        }

        if digits == 0 {
            return 0
        }

        let signedVal = neg ? (0 &- val) : val
        return Int(Int32(truncatingIfNeeded: signedVal))
    }

    private func cmdStz4(_ a: StageArgs) {
        let s = scene
        let l = a.has(0) ? a.expr(0) : 0
        guard (0...39).contains(l) else { return }

        let zx0 = a.has(1) ? a.expr(1) : Int(s.getZoomX(l))
        let zy0 = a.has(2) ? a.expr(2) : Int(s.getZoomY(l))
        if a.has(3) {
            s.setZoomX(l, StageMath.i16(Int64(a.expr(3))))
        }
        if a.has(4) {
            s.setZoomY(l, StageMath.i16(Int64(a.expr(4))))
        }

        let frames = a.has(5) ? Int(StageMath.msToFrames60(Int32(truncatingIfNeeded: a.expr(5)))) : 0
        let piv = a.has(7) ? a.expr(7) : Int(s.getZoomPivot(l))
        s.setZoomPivot(l, StageMath.i8(Int64(piv)))
        let ease = a.has(6) ? a.expr(6) : 0

        let r = drawn[l]
        let x0 = StageMath.i16(Int64(zx0))
        let y0 = StageMath.i16(Int64(zy0))
        let x1 = s.getZoomX(l)
        let y1 = s.getZoomY(l)
        let f16 = StageMath.i16(Int64(frames))
        r.zoomX = x1
        r.zoomY = y1
        r.zoomPivot = UInt8(truncatingIfNeeded: piv & 0xFF)
        r.twZoom = Tween.start(StageMath.i16(Int64(ease)), Int(f16))
        if f16 == 0 {
            r.zoomDx = 0
            r.zoomDy = 0
        } else {
            r.zoomDx = -((Float(x1) * 0.001) + (Float(x0) * -0.001))
            r.zoomDy = -((Float(y1) * 0.001) + (Float(y0) * -0.001))
        }
    }

    private func cmdStrt(_ a: StageArgs) {
        let s = scene
        let l = a.has(0) ? a.expr(0) : 0
        guard (0...39).contains(l) else { return }

        let r0 = a.has(1) ? a.expr(1) : Int(StageMath.i32(s.getRot(l)))
        let r1 = a.has(2) ? a.expr(2) : 0
        s.setRot(l, Int64(r1))
        let frames = a.has(3) ? Int(StageMath.msToFrames60(Int32(truncatingIfNeeded: a.expr(3)))) : 0
        let ease = a.has(4) ? a.expr(4) : 0

        let r = drawn[l]
        let f16 = StageMath.i16(Int64(frames))
        r.rot = Int64(r1)
        let delta = StageMath.i16(Int64(r0 - r1))
        r.rotDelta = delta
        r.rotCur = delta
        r.twRot = Tween.start(StageMath.i16(Int64(ease)), Int(f16))
        if f16 == 0 {
            r.rotDelta = 0
        }
    }

    private func cmdStgs(_ a: StageArgs) {
        let s = scene
        let l = a.has(0) ? a.expr(0) : 0
        guard (0...39).contains(l) else { return }

        let start = a.has(1) ? min(a.expr(1), 255) : min(Int(s.getAlpha(l)), 255)
        let end = a.has(2) ? min(a.expr(2), 255) : 0
        s.setAlpha(l, StageMath.i16(Int64(end)))
        let frames = a.has(3) ? Int(StageMath.msToFrames60(Int32(truncatingIfNeeded: a.expr(3)))) : 0
        let ease = a.has(4) ? a.expr(4) : 0

        let r = drawn[l]
        let f16 = StageMath.i16(Int64(frames))
        let endF = Float(end) / 255.0
        let startF = Float(start) / 255.0
        r.alpha = endF
        r.twAlpha = Tween.start(StageMath.i16(Int64(ease)), Int(f16))
        if f16 == 0 {
            r.alphaDelta = 0
            r.alphaCur = 0
        } else {
            let d = startF - endF
            r.alphaDelta = d
            r.alphaCur = d
        }
    }

    private func cmdStcl(_ a: StageArgs) {
        let s = scene
        let l = a.has(1) ? a.expr(1) : 0
        guard (0...39).contains(l) else { return }

        let x0 = a.has(2) ? Int(StageMath.scriptX(Int32(truncatingIfNeeded: a.expr(2)))) : Int(s.getX(l))
        let y0 = a.has(3) ? Int(StageMath.scriptY(Int32(truncatingIfNeeded: a.expr(3)))) : Int(s.getY(l))
        let x1 = a.has(4) ? Int(StageMath.scriptX(Int32(truncatingIfNeeded: a.expr(4)))) : x0
        let y1 = a.has(5) ? Int(StageMath.scriptY(Int32(truncatingIfNeeded: a.expr(5)))) : y0
        s.setX(l, StageMath.i16(Int64(x1)))
        s.setY(l, StageMath.i16(Int64(y1)))
        let frames = a.has(6) ? Int(StageMath.msToFrames60(Int32(truncatingIfNeeded: a.expr(6)))) : 0
        let ease = a.expr(7)

        let r = drawn[l]
        let f16 = StageMath.i16(Int64(frames))
        r.x = Float(x1)
        r.y = Float(y1)
        r.twMove = Tween.start(StageMath.i16(Int64(ease)), Int(f16))
        if f16 == 0 {
            r.moveDx = 0
            r.moveDy = 0
        } else {
            r.moveDx = Float(x0 - x1)
            r.moveDy = Float(y0 - y1)
        }
    }

    private func cmdStma(_ a: StageArgs) {
        let l = a.has(0) ? a.expr(0) : 0
        guard (0...39).contains(l) else { return }

        let mid = a.has(1) ? a.expr(1) : 0
        let n = a.has(3) ? Int(StageMath.i16(Int64(a.expr(3)))) : 0

        var id = scene.getMotionId(l)
        var div = scene.getMotionDivisor(l)
        var fr = scene.getMotionFrames(l)
        var ps = scene.getMotionPause(l)
        MotionApply.motionRecord(recId: &id, recDivisor: &div, recFrames: &fr, recPause: &ps, id: mid, n: n)
        scene.setMotionId(l, id)
        scene.setMotionDivisor(l, div)
        scene.setMotionFrames(l, fr)
        scene.setMotionPause(l, ps)

        let r = drawn[l]
        MotionApply.motionRecord(r, mid, n)

        let w = a.has(2) ? a.expr(2) : -1
        if w == 1 || (!a.has(2) && motionWaitConfig == 0) || (w == 2 && motionWaitConfig == 1) {
            motionWaitRequested = true
        }

        _ = MotionApply.apply(table: motions, catalog: catalog, rec: r, layer: l, dt: 0.0, scene: scene)
    }

    private func cmdStns(_ a: StageArgs) {
        let l = a.has(0) ? a.expr(0) : 0
        guard (0...39).contains(l) else { return }

        var n = a.has(1) ? a.expr(1) & 0xFFFF : 0
        let b: UInt8
        if n >= 13 {
            n = 0
            b = 20
        } else {
            b = n < 3 ? 20 : 12
        }

        scene.setStns(l, UInt8(truncatingIfNeeded: n))
        scene.setStnsB(l, b)
        drawn[l].stns = UInt8(truncatingIfNeeded: n)
        drawn[l].stnsB = b
    }

    private func cmdSttr(_ a: StageArgs) {
        let l = a.has(0) ? a.expr(0) : 0
        let n = a.has(1) ? a.expr(1) : 0
        let m = a.has(2) ? a.expr(2) : 0
        guard (0...39).contains(l) else { return }

        let v = n > 0 ? ((n - 1) | (m << 12)) & 0xFFFF : 0xFFFF
        let v16 = StageMath.i16(Int64(v))
        scene.setSttr(l, v16)
        if drawn[l].used != 0 {
            drawn[l].sttr = Int(v16)
        }

        ruleSlotVal = n - 1
    }

    private func cmdStra(_ a: StageArgs) {
        let l = a.has(0) ? a.expr(0) : 0
        guard l >= -1 && l <= 39 else { return }

        let n = a.has(1) ? a.expr(1) : 0
        let frames = a.has(2) ? Int(StageMath.msToFrames(Int32(truncatingIfNeeded: a.expr(2)))) : 0
        let n16 = StageMath.i16(Int64(n))
        let f16 = StageMath.i16(Int64(frames))
        if l == -1 {
            if n16 <= 0 {
                for k in 0..<Self.layerCount {
                    scene.setStra(k, 0)
                    drawn[k].stra = 0
                    drawn[k].straPhase = 0
                }
            }
            return
        }

        scene.setStra(l, n16)
        let r = drawn[l]
        if n16 != 0 || f16 == 0 {
            r.stra = n16
            r.straPhase = 0
            if n16 != 0 {
                r.straFadeIn = f16
            } else {
                r.straFadeLeft = f16
                r.straFadeTotal = f16
            }
        } else {
            r.straFadeLeft = f16
            r.straFadeTotal = f16
        }
    }

    private func cmdStpv(_ st: Statement) {
        let a = StageArgs(st)
        let l = Self.stpvLayer(st)
        guard (0...39).contains(l) else { return }

        let s = scene
        let pic = Int(s.getPic(l))
        let fac: Float = pic > 0 && pic < catalog.count ? catalog.info(pic).classFactor : 1.0
        let p1 = a.inlinePresent(1)
        let p2 = a.inlinePresent(2)
        if p1 {
            let v = Float(a.inline16(1)) * 640.0 / 480.0 * fac
            s.setAnchorX(l, StageMath.i16(Int64(StageMath.cvtt(v))))
        }
        if p2 {
            let v = Float(a.inline16(2)) * 480.0 / 360.0 * fac
            s.setAnchorY(l, StageMath.i16(Int64(StageMath.cvtt(v))))
        }

        if pic >= 0 && pic < catalog.count {
            let n = catalog.name(pic)
            let chars = Array(n)
            let len = chars.count
            let hasImg = n.prefix(3).caseInsensitiveCompare("IMG") == .orderedSame
            if len >= 7 && chars[len - 6] == "_" && chars[len - 3] == "_" && (hasImg || len >= 15)
                && !(chars[len - 5] == "0" && chars[len - 4] == "0" && chars[len - 2] == "0" && chars[len - 1] == "0") {
                let baseName = String(chars[0..<(len - 6)])
                let bp = catalog.lookup(baseName)
                if bp >= 0 {
                    let pi = catalog.info(pic)
                    let bi = catalog.info(bp)
                    if p1 {
                        s.setAnchorX(l, StageMath.i16(Int64(Int(s.getAnchorX(l)) + pi.anchorX - bi.anchorX)))
                    }
                    if p2 {
                        s.setAnchorY(l, StageMath.i16(Int64(Int(s.getAnchorY(l)) + pi.anchorY - bi.anchorY)))
                    }
                }
            }
        }

        setExtOffsets(l, Int(s.getAnchorX(l)), Int(s.getAnchorY(l)))
        if a.inlinePresent(3) {
            s.setRot(l, Int64(a.inline16(3)))
        }

        let r = drawn[l]
        r.anchorX = s.getAnchorX(l)
        r.anchorY = s.getAnchorY(l)
    }

    private static func stpvLayer(_ st: Statement) -> Int {
        let raw = st.args
        var i = min(1, raw.count)
        if i < raw.count && raw[i] == UInt8(ascii: "`") {
            i += 5
        }

        var v = 0
        var sign = 1
        let end = min(raw.count, i + 16)
        while i < end {
            let ch = raw[i]
            if ch == UInt8(ascii: ",") || ch == UInt8(ascii: ")") || ch == UInt8(ascii: ";") {
                break
            }
            if ch == UInt8(ascii: "-") {
                sign = -1
            } else if ch >= UInt8(ascii: "0") && ch <= UInt8(ascii: "9") {
                v = (v * 10) + Int(ch - UInt8(ascii: "0"))
            }
            i += 1
        }
        return Int(StageMath.i16(Int64(v * sign)))
    }
    private func cmdSqk2(_ a: StageArgs) {
        let l = a.has(0) ? a.expr(0) : 0
        if l > 39 {
            return
        }

        let dur = a.has(4) ? a.expr(4) : -1
        let fade = a.has(5) ? a.expr(5) : 0
        let p2: Int
        if !a.has(3) {
            p2 = 2
        } else {
            let a3 = a.expr(3)
            if a3 < 0 {
                p2 = 1
            } else {
                let term = UInt32(truncatingIfNeeded: Int64(3 * a3 + 0x31))
                p2 = term < 0x63 ? 2 : Int(StageMath.msToFrames(Int32(truncatingIfNeeded: a3))) + 1
            }
        }

        let a7 = a.has(7) ? a.expr(7) : 0
        let p4 = dur >= 0 && a7 <= 16 ? Int(StageMath.msToFrames(Int32(truncatingIfNeeded: dur))) : 0
        let par = [
            a.has(1) ? a.expr(1) : 15,
            a.has(2) ? a.expr(2) : 15,
            p2,
            Int(StageMath.msToFrames(Int32(truncatingIfNeeded: a7))),
            p4,
            a.has(6) ? a.expr(6) : 0
        ]
        startShake(l, 1, par, dur, fade, targets: sqk2Targets)
    }

    private func cmdShk2(_ a: StageArgs) {
        let l = a.has(0) ? a.expr(0) : 0
        guard l >= -1 && l <= 39 else { return }

        let par = [
            a.has(1) ? a.expr(1) : 0,
            a.has(2) ? a.expr(2) : 15,
            a.has(3) ? Int(StageMath.msToFrames(Int32(truncatingIfNeeded: a.expr(3)))) : 18,
            a.has(6) ? a.expr(6) : 0,
            a.has(7) ? Int(StageMath.msToFrames(Int32(truncatingIfNeeded: a.expr(7)))) : 0,
            a.has(8) ? a.expr(8) : 1
        ]
        startShake(l, 2, par, a.has(4) ? a.expr(4) : -1, a.has(5) ? a.expr(5) : 0, targets: shk2Targets)
    }

    private func cmdSsw2(_ a: StageArgs) {
        let l = a.has(0) ? a.expr(0) : 0
        guard (0...39).contains(l) else { return }

        let par = [
            a.has(1) ? a.expr(1) : 7,
            a.has(2) ? a.expr(2) : 15,
            a.has(3) ? Int(StageMath.msToFrames(Int32(truncatingIfNeeded: a.expr(3)))) : 60,
            a.has(4) ? Int(StageMath.msToFrames(Int32(truncatingIfNeeded: a.expr(4)))) : 120,
            a.has(5) ? a.expr(5) : 1,
            0
        ]
        startShake(l, 3, par, a.has(6) ? a.expr(6) : -1, a.has(7) ? a.expr(7) : 0, targets: sqk2Targets)
    }

    private func startShake(_ l: Int, _ kind: Int, _ par: [Int], _ dur: Int, _ fade: Int, targets: () -> [Int]) {
        if dur >= 0 && scanMode {
            return
        }

        let list = l >= 0 ? [l] : targets()
        let slot = kind == 1 ? 0 : 1
        for k in list {
            let s = scene
            s.setShakeKind(k, slot, UInt8(truncatingIfNeeded: kind))
            s.setShakeFade(k, slot, StageMath.i16(Int64(StageMath.msToFrames(Int32(truncatingIfNeeded: fade)))))
            s.setShakeTime(k, slot, dur >= 0 ? StageMath.i16(Int64(StageMath.msToFrames(Int32(truncatingIfNeeded: dur)))) : -1)
            for i in 0..<6 {
                s.setShakePar(k, (6 * slot) + i, StageMath.i16(Int64(par[i])))
            }

            shakes.start(SlotStart(layer: k, kind: kind, par: par, durMs: dur, fadeMs: fade))
        }

        sceneDirty = true
    }

    private func sqk2Targets() -> [Int] {
        var t = [Int]()
        for k in 0..<2 {
            if drawn[k].used != 0 {
                t.append(k)
            }
        }
        for k in 2..<Self.layerCount {
            if (drawn[k].used != 0 && drawn[k].zOrder > 0) || scene.getPic(k) != -1 {
                t.append(k)
            }
        }
        return t
    }

    private func shk2Targets() -> [Int] {
        var t = [Int]()
        for k in 0..<2 {
            if drawn[k].used != 0 && drawn[k].zOrder > 0 {
                t.append(k)
            }
        }
        for k in 2..<Self.layerCount {
            if (drawn[k].used != 0 && drawn[k].zOrder > 0) || scene.getPic(k) != -1 {
                t.append(k)
            }
        }
        return t
    }

    private func cmdStopShake(_ a: StageArgs, _ kind: Int) {
        let l = a.has(0) ? a.expr(0) : 0
        if l > 39 {
            return
        }

        let slot = kind == 1 ? 0 : 1
        let from = l < 0 ? 0 : l
        let to = l < 0 ? Self.layerCount : l + 1
        for k in from..<to {
            scene.setShakeKind(k, slot, 0)
            scene.setShakeFade(k, slot, 0)
            scene.setShakeTime(k, slot, 0)
            for i in 0..<6 {
                scene.setShakePar(k, (6 * slot) + i, 0)
            }
        }

        shakes.stop(layer: l, kind: kind)
    }

    private func cmdShok(_ st: Statement) {
        if scanMode || skipActive {
            return
        }

        let a = StageArgs(st)
        var v = [0, 0, 300, 3, 0]
        for i in 0..<5 {
            if a.inlinePresent(i) {
                v[i] = a.inline16(i)
            }
        }

        shock.start(ax: v[0], ay: v[1], ms: v[2], n: v[3], delay: v[4])
    }

    private func cmdSgma(_ a: StageArgs) {
        let l = a.has(0) ? a.expr(0) : 0
        guard (0...39).contains(l), a.has(1), a.expr(1) > 0 else {
            return
        }

        sceneDirty = true
        _ = MotionMath.editMotion(motions, drawn[l], a.expr(1), a.has(2) ? a.expr(2) : 0)
    }

    private func cmdFads(_ a: StageArgs) {
        let type = a.expr(0)
        let ms = a.expr(1)
        let rule = a.expr(2)
        if rule > 0 && !skipActive {
            ruleSlotVal = rule - 1
        }
        commit(type: type, ms: ms, rule: rule)
    }
}
