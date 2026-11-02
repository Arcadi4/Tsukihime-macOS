import Foundation
import TsukiCore

/// Arguments of 0x84670(layer, params, dur_ms, fade_ms, kind).
public struct SlotStart: Sendable, Equatable {
    /// Target layer 0..39.
    public var layer: Int
    /// 1 quake, 2 shake, 3 swing.
    public var kind: Int
    /// The six parameters p0..p5.
    public var par: [Int]
    /// Duration in ms, -1 until stopped.
    public var durMs: Int
    /// Start delay in ms.
    public var fadeMs: Int

    public init(layer: Int, kind: Int, par: [Int], durMs: Int, fadeMs: Int) {
        self.layer = layer
        self.kind = kind
        self.par = par
        self.durMs = durMs
        self.fadeMs = fadeMs
    }
}

/// The layer shake slots of the drawn records and their per-frame update (VA 0x84670 start, 0x847F0 stop, 0x4A770 reset, 0x57F4D..0x5889A
/// update, 0x51A22..0x51B71 and 0x516DE..0x51746 draw terms; docs/formats/quake.md 3-5). Port of `ShakeLayers` of `tsuki.quake`,
/// working on the `LayerRecord.slots` of the drawn array. The quake fixes of the review are in: `resetLayer` runs for
/// `_STCH` and `_SCH2` alike, and `maskOffset` is the second draw path of masked layers through 0x49A60.
public final class ShakeEngine {
    private let a: [LayerRecord]
    private let noShock: (Int) -> Bool
    private let scene: SceneState?

    /// Creates the engine over the 40 drawn records.
    /// - Parameters:
    ///   - drawn: The drawn array A.
    ///   - rng: The shared `rand()`.
    ///   - rnd2: The flicker generator.
    ///   - noShock: True for a picture id whose catalog draw_flags has bit 1 (the seven colour fills): they ignore the screen shock.
    ///   - scene: The script-side scene state whose shake mirror (kind, delay, time, parameters) the update writes.
    public init(drawn: [LayerRecord], rng: Ps4Rand, rnd2: Rnd2, noShock: ((Int) -> Bool)? = nil, scene: SceneState? = nil) {
        self.a = drawn
        self.rng = rng
        self.rnd2 = rnd2
        self.noShock = noShock ?? { _ in false }
        self.scene = scene
    }

    /// The shared `rand()`.
    public let rng: Ps4Rand

    /// The flicker generator.
    public let rnd2: Rnd2

    /// Word 0x164B998: set by every start.
    public var sceneDirty: Bool = false

    private static func slotOfKind(_ kind: Int) -> Int {
        kind == 1 ? 0 : 1
    }

    /// 0x84670: stores a slot; ignored for a layer outside 0..39 and a kind outside 1..3.
    public func start(_ st: SlotStart) {
        guard (0...39).contains(st.layer), (1...3).contains(st.kind) else {
            return
        }

        let s = a[st.layer].slots[Self.slotOfKind(st.kind)]
        s.kind = st.kind
        s.delay = Int(StageMath.i16(Int64(StageMath.msToFrames(Int32(truncatingIfNeeded: st.fadeMs)))))
        s.time = st.durMs >= 0 ? Int(StageMath.i16(Int64(StageMath.msToFrames(Int32(truncatingIfNeeded: st.durMs))))) : -1
        for i in 0..<min(6, st.par.count) {
            s.par[i] = StageMath.i16(Int64(st.par[i]))
        }

        s.elapsed = 0
        s.phase = 0
        s.x = 0
        s.y = 0
        for i in 0..<s.w.count {
            s.w[i] = 0
        }
        sceneDirty = true
    }

    /// 0x847F0(layer, kind): clears the kind's slot; layer below 0 = all 40; above 39 nothing. `_SHS2` and `_SSS2` both clear slot 1.
    public func stop(layer: Int, kind: Int) {
        guard layer <= 39, (1...3).contains(kind) else {
            return
        }

        let slot = Self.slotOfKind(kind)
        if layer < 0 {
            for l in 0..<40 {
                a[l].slots[slot].clear()
            }
        } else {
            a[layer].slots[slot].clear()
        }
    }

    /// Every `_STCH` and `_SCH2` with layer 0..39 resets the drawn record at the statement itself: the backend 0x81760 calls
    /// 0x4A770(layer) on both paths (VA 0x81A9C for STCH, 0x81ABB for SCH2), which zeroes both slots (+0x178..+0x1CF).
    public func resetLayer(_ layer: Int) {
        if (0...39).contains(layer) {
            a[layer].slots[0].clear()
            a[layer].slots[1].clear()
        }
    }

    /// Layer-array initialisation 0x57590 (ADV-mode entry, scan load): every slot of every layer is cleared.
    public func advStart() {
        for r in a {
            r.slots[0].clear()
            r.slots[1].clear()
        }
    }

    /// B to A transfer of the slots (VA 0x595B2..0x59779, first update after a commit): a committed slot replaces the drawn one only when its
    /// kind is non-zero and differs from the running kind.
    public func mergeCommitted(layer: Int, committed: LayerRecord) {
        for s in 0..<2 {
            let b = committed.slots[s]
            let aSlot = a[layer].slots[s]
            if b.kind != aSlot.kind && b.kind != 0 {
                aSlot.copyFrom(b)
                b.kind = 0
            }
        }
    }

    /// One call of the layer update with `dt` frames: layers 0..39 in index order, slot 0 then slot 1.
    public func update(dt: Int) {
        let dtf = Float(dt)
        for l in 0..<40 {
            for si in 0..<2 {
                updateSlot(l, si, dtf)
            }
        }
    }

    /// The slot update of one layer (both slots) with `dtf` frames, as the per-layer loop of 0x57980 runs it.
    public func updateLayer(_ l: Int, _ dtf: Float) {
        for si in 0..<2 {
            updateSlot(l, si, dtf)
        }
    }

    private func updateSlot(_ l: Int, _ si: Int, _ dtf: Float) {
        let s = a[l].slots[si]
        if s.delay > 0 {
            let v = StageMath.cvtt(StageMath.f(Float(s.delay) - dtf))
            s.delay = StageMath.i16(Int64(v)) > 0 ? Int(StageMath.i16(Int64(v))) : 0
            scene?.setShakeFade(l, si, Int16(truncatingIfNeeded: s.delay))
            return
        }

        if s.time == 0 {
            return
        }

        var el = StageMath.cvtt(StageMath.f(Float(s.elapsed) + dtf))
        if StageMath.i16(Int64(el)) >= 30000 {
            el = 30000
        }

        s.elapsed = Int(StageMath.i16(Int64(el)))
        if s.time > 0 && s.time < s.elapsed {
            s.clear()
            if let sc = scene {
                sc.setShakeKind(l, si, 0)
                sc.setShakeFade(l, si, 0)
                sc.setShakeTime(l, si, 0)
                for i in 0..<6 {
                    sc.setShakePar(l, (6 * si) + i, 0)
                }
            }
        }

        switch s.kind {
        case 1:
            quake(l, si, s, dtf)
        case 2:
            shake(s, dtf)
        case 3:
            swing(s, dtf)
        default:
            s.x = 0
            s.y = 0
        }
    }

    private func quake(_ l: Int, _ si: Int, _ s: ShakeSlot, _ dtf: Float) {
        s.phase = Int(StageMath.i16(Int64(StageMath.cvtt(StageMath.f(Float(s.phase) + dtf)))))
        if Int(s.par[2]) > s.phase {
            return
        }

        s.phase = 0
        if l >= 2 && s.par[5] != 0 {
            var fx: Float = 0
            var fy: Float = 0
            for k in 0..<2 {
                let lk = a[k]
                if lk.used != 0 && lk.zOrder != 0 {
                    fx = lk.slots[si].x
                    fy = lk.slots[si].y
                }
            }

            s.x = fx
            s.y = fy
            return
        }

        var ax = Float(s.par[0])
        var ay = Float(s.par[1])
        let el = Float(s.elapsed)
        if Float(s.par[3]) > el {
            let r = el / Float(s.par[3])
            ax *= r
            ay *= r
        } else if s.time > 0 {
            let t0 = Float(s.time) - Float(s.par[4])
            if el > t0 {
                let r = 1.0 - ((el - t0) / Float(s.par[4]))
                ax *= r
                ay *= r
            }
        }

        let r1 = rng.next()
        let r2 = rng.next()
        let ux = Float(r1) * Ps4Math.twoPowMinus30
        let uy = Float(r2) * Ps4Math.twoPowMinus30
        let vx = ax * ux
        let vy = ay * uy
        s.x = ((vx + vx) - ax) * Ps4Math.third
        s.y = ((vy + vy) - ay) * Ps4Math.yCanvas
    }

    private func shake(_ s: ShakeSlot, _ dtf: Float) {
        let p = s.par
        let per = p[2] != 0 ? Int(p[2]) : 60
        let m = per != -32768 ? abs(per) & 0xFFFF : 32768
        var e = StageMath.cvtt(StageMath.f(Float(s.phase) + dtf))
        var d: Int16
        repeat {
            d = StageMath.i16(Int64(e))
            e = StageMath.i32(Int64(e) - Int64(m))
        } while m <= Int(d)

        s.phase = Int(StageMath.i16(Int64(m + Int(e))))
        var v = Ps4Math.sinf(Float(s.phase) * Ps4Math.twoPi / Float(per))
        if p[4] > 0 && s.elapsed < Int(p[4]) {
            v *= Float(s.elapsed) / Float(p[4])
        }

        if p[3] != 0 && s.time > 0 {
            let t = Float(s.time)
            let e2 = Float(s.elapsed)
            v *= (t - (t < e2 ? t : e2)) / t
        }

        if p[5] >= 2 {
            v = rnd2.next() % 5 == 0 ? v * (1.0 / Float(p[5])) : 0
        }

        s.x = v * Float(p[0]) * Ps4Math.third
        s.y = v * Float(p[1]) * Ps4Math.yCanvas
    }

    private func u() -> Float {
        Float(rng.next()) * Ps4Math.twoPowMinus30
    }

    private func swing(_ s: ShakeSlot, _ dtf: Float) {
        let p = s.par
        s.phase = Int(StageMath.i16(Int64(StageMath.cvtt(StageMath.f(Float(s.phase) + dtf)))))
        if !(Int(s.w[2]) >= s.phase) {
            s.phase = 0
            s.w[0] = StageMath.i16(Int64(StageMath.cvtt((u() * Float(p[1] - p[0])) + Float(p[0]))))
            s.w[2] = StageMath.i16(Int64(StageMath.cvtt((u() * Float(p[3] - p[2])) + Float(p[2]))))
            if s.w[4] == 0 {
                s.w[4] = u() < 0.5 ? 1 : -1
            }
        }

        let s1 = Ps4Math.sinf(Float(s.phase) * Ps4Math.twoPi / Float(s.w[2]))
        s.w[6] = StageMath.i16(Int64(StageMath.cvtt(StageMath.f(Float(s.w[6]) + dtf))))
        if !(Int(s.w[3]) >= Int(s.w[6])) {
            s.w[6] = 0
            s.w[1] = StageMath.i16(Int64(StageMath.cvtt((u() * Float(p[1] - p[0])) + Float(p[0]))))
            s.w[3] = StageMath.i16(Int64(StageMath.cvtt((u() * Float(p[3] - p[2])) + Float(p[2]))))
            if s.w[5] == 0 {
                s.w[5] = u() < 0.5 ? 1 : -1
            }
        }

        let p4 = Float(p[4])
        let aVal = Float(s.w[4]) * Float(s.w[0]) * p4 * s1
        let bVal = Float(s.w[5]) * Float(s.w[1]) * p4
        let s2 = Ps4Math.sinf(Float(s.w[6]) * Ps4Math.twoPi / Float(s.w[3]))
        s.x = aVal * Ps4Math.third
        s.y = s2 * bVal * Ps4Math.yCanvas
    }

    // -- draw terms (0x51060) ----------------------------------------------------------------------------------------------------

    /// 0x49A60(A[m] + 0x10, axis), axis 0 = x, 1 = y: layer `m`'s crop origin plus its shake outputs in 1920 x 1080 units, plus
    /// the screen shock when m has a crop rectangle and is an offscreen target. The shake outputs are read from A[m.mask] when m itself has
    /// a mask, else from m (VA 0x49A8F). `shock` is (0xDF0720, 0xDF0724) when byte 0xDF07C8 is 0.
    public func maskAxis(_ m: Int, _ axis: Int, _ shock: (x: Float, y: Float), _ shakes: Bool = true) -> Float {
        let mr = a[m]
        let src = mr.mask >= 0 ? a[mr.mask] : mr
        var sh: Float = 0
        if shakes {
            for s in src.slots {
                if s.kind != 0 {
                    sh += axis == 0 ? s.x : s.y
                }
            }
        }

        sh *= axis == 0 ? 3.0 : Ps4Math.yPixels
        var v = 0.0 + (sh + Float(mr.crop[axis]))
        let anyCrop = mr.crop[0] != 0 || mr.crop[1] != 0 || mr.crop[2] != 0 || mr.crop[3] != 0
        if anyCrop && mr.offscreen {
            let (sx, sy) = noShock(mr.pic) ? (Float(0), Float(0)) : shock
            v = axis == 0 ? (sx * 3.0) + v : (sy * Ps4Math.shockYMask) + v
        }

        return v
    }

    /// The mask-layer term of layer `l`'s draw (VA 0x516DE..0x5174A): when l has a mask and not the `_SACL` flag,
    /// `(0x49A60(mask, 0) * 640 / 1920, 0x49A60(mask, 1) * 360 / 1080)` is added to the layer position (so it also moves the pivot-zoom point).
    public func maskOffset(_ l: Int, _ shock: (x: Float, y: Float), _ shakes: Bool = true) -> (x: Float, y: Float) {
        let r = a[l]
        if r.mask < 0 || (r.flags & 0x40) != 0 {
            return (0, 0)
        }

        let vx = maskAxis(r.mask, 0, shock, shakes)
        let vy = maskAxis(r.mask, 1, shock, shakes)
        return (vx * 640.0 / 1920.0, vy * 360.0 / 1080.0)
    }

    /// The canvas-unit translation the layer draw adds for the two slots (VA 0x51A22..0x51B71; added to the translation column, so the STZ4 pivot
    /// zoom scales it). Slot 0 of a quake follows the outermost quaking ancestor, or else the mask layer's quake.
    public func slotOffset(_ l: Int) -> (x: Float, y: Float) {
        let r = a[l]
        var dx: Float = 0
        var dy: Float = 0
        let k0 = r.slots[0].kind
        if k0 != 0 {
            var ox = r.slots[0].x
            var oy = r.slots[0].y
            if k0 == 1 {
                var p = r.parent
                if p >= 0 {
                    var guardCount = 0
                    while p >= 0 && p < 40 && guardCount < 64 {
                        guardCount += 1
                        if a[p].slots[0].kind != 0 {
                            ox = a[p].slots[0].x
                            oy = a[p].slots[0].y
                        }
                        p = a[p].parent
                    }
                } else if r.mask >= 0 && a[r.mask].slots[0].kind != 0 {
                    ox = a[r.mask].slots[0].x
                    oy = a[r.mask].slots[0].y
                }
            }

            dx += ox
            dy += oy
        }

        if r.slots[1].kind != 0 {
            dx += r.slots[1].x
            dy += r.slots[1].y
        }

        return (dx, dy)
    }
}
