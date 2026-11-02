import Foundation

/// Keyframe interpolation and time handling of the layer motions (VA 0xBDD70 with the spline helper 0xBD5E0, the time rules of 0xBE4C0
/// and the `_SGMA` edit 0xC23B0; docs/formats/layers.md 8.2, 8.4). Port of `motion_value`, `_spline_ab`, `motion_frames`,
/// `motion_keytime`, `motion_found`, `edit_motion` of `tsuki.misc_layer_state_and_motions`; all arithmetic is float32 as
/// in the oracle.
public enum MotionMath {
    private static let unset = MotionTable.unset
    private static let hold = MotionTable.hold

    @inline(__always) private static func f(_ x: Double) -> Double { Double(Float(x)) }
    @inline(__always) private static func f(_ x: Float) -> Double { Double(x) }

    /// Fields 3 / 4 (x / y in script units) snapped to whole engine units (`_q`).
    private static func quant(_ fld: Int, _ v: Double) -> Double {
        if fld == 3 {
            return f(f(Double(StageMath.i16(Int64(StageMath.cvtt(f(f(v * 640.0) / 480.0))))) * 480.0) / 640.0)
        }
        if fld == 4 {
            return f(f(Double(StageMath.i16(Int64(StageMath.cvtt(f(f(v * 480.0) / 360.0))))) * 360.0) / 480.0)
        }
        return v
    }

    private static func sentinels(_ fld: Int) -> (hold: Int, unset: Int) {
        (fld & ~8) == 0 ? (MotionTable.hold8, MotionTable.unset8) : (hold, unset)
    }

    /// VA 0xBD5E0: the second-derivative pair (a, b) of the segment [k-1, k] of the spline through the motion's keys, or null. The engine's
    /// forward elimination subtracts `diag * (1/diag)` (= 1) where the textbook Thomas step subtracts `rhs * (1/diag)`; the port keeps that.
    private static func splineAb(_ t: MotionTable, _ fld: Int, _ s: Int, _ e: Int, _ k: Int, _ cur: Double) -> (a: Double, b: Double)? {
        if s == k || e - s + 1 < 3 {
            return nil
        }

        let (sentinelHold, sentinelUnset) = sentinels(fld)

        func definedBack(_ i: Int) -> Double {
            var j = i
            var v = t.val(j, fld)
            while (v == sentinelHold || v == sentinelUnset) && j > s {
                j -= 1
                v = t.val(j, fld)
            }
            return (v == sentinelHold || v == sentinelUnset) ? cur : Double(v)
        }

        let v0 = t.val(s, fld)
        var y: [Double] = [(v0 == sentinelHold || v0 == sentinelUnset) ? cur : Double(v0)]
        var kmap: [Int: Int] = [0: 0]
        var prev = v0
        var i2 = s + 1
        while i2 < e {
            let raw = t.val(i2, fld)
            let nxt = t.val(i2 + 1, fld)
            if raw == sentinelHold || (prev == raw && raw == nxt) {
                kmap[i2 - s] = y.count - 1
            } else {
                kmap[i2 - s] = y.count
                y.append(definedBack(i2))
            }
            prev = raw
            i2 += 1
        }

        let rawE = t.val(e, fld)
        if prev != rawE && rawE != sentinelUnset {
            kmap[e - s] = y.count
            y.append(definedBack(e))
        }

        let n = y.count
        if n < 3 {
            return nil
        }

        var d = [Double](repeating: 0, count: n)
        for j in stride(from: n - 1, to: 0, by: -1) {
            d[j] = f(y[j] - y[j - 1])
        }

        var m = [Double](repeating: 0, count: n + 1)
        m[1] = f(d[2] - d[1])
        var diag = [Double](repeating: 0, count: n)
        diag[1] = 4.0
        var x3 = 4.0
        for j in 2..<(n - 1) {
            let w = f(1.0 / x3)
            m[j] = f(f(d[j + 1] - d[j]) - f(x3 * w))
            x3 = f(4.0 - w)
            diag[j] = x3
        }

        m[n - 2] = f(m[n - 2] - m[n - 1])
        for j in stride(from: n - 1, to: 1, by: -1) {
            m[j - 1] = f(f(m[j - 1] - m[j]) / diag[j - 1])
        }

        let idx = kmap[k - s - 1] ?? 0
        return (m[idx], m[idx + 1])
    }

    /// VA 0xBDD70: value of keyframe field `f` at motion time `t` (ms) for the keys `[s, e]`
    /// (`e` inclusive), `k` the first key with time at least `t`, `cur` the
    /// layer's current value (returned where the field is not animated), `whole` motion 9999 (segment easing forced to linear).
    public static func motionValue(_ table: MotionTable, _ fld: Int, _ s: Int, _ e: Int, _ k: Int, _ t: Double, _ cur: Double, whole: Bool = false) -> Double {
        let (sentinelHold, sentinelUnset) = sentinels(fld)
        if Double(table.val(s, 0)) > t {
            return cur
        }

        var r = k
        var vn = 0
        var tn = 0.0
        while true {
            vn = table.val(r, fld)
            tn = Double(table.val(r, 0))
            if vn == sentinelHold && r < e {
                r += 1
                continue
            }
            break
        }

        var tp = 0.0
        var vp = 0
        if k != s && !(t >= tn) {
            var j = k
            while true {
                j -= 1
                vp = table.val(j, fld)
                if vp == sentinelHold && j > s {
                    continue
                }
                break
            }

            tp = Double(table.val(j, 0))
            if vn != sentinelUnset && vp == sentinelUnset && j > s {
                var i = j
                while true {
                    i -= 1
                    vp = table.val(i, fld)
                    if (vp != sentinelHold && vp != sentinelUnset) || i <= s {
                        break
                    }
                }
            }
        } else if r < s {
            vp = 0
        } else {
            var i = r
            while true {
                vp = table.val(i, fld)
                if (vp != sentinelHold && vp != sentinelUnset) || i <= s {
                    break
                }
                i -= 1
            }
        }

        if vn == sentinelUnset {
            var j = k
            var v = 0
            while true {
                v = table.val(j, fld)
                if (v != sentinelHold && v != sentinelUnset) || j <= s {
                    break
                }
                j -= 1
            }

            return (v == sentinelUnset || v == sentinelHold) ? cur : quant(fld, Double(v))
        }

        if vp == sentinelUnset {
            return cur
        }

        if vn == sentinelHold {
            for j in stride(from: e - 1, through: s, by: -1) {
                let v = table.val(j, fld)
                if v != sentinelHold {
                    return Double(v)
                }
            }
            return cur
        }

        if vp == sentinelHold {
            return cur
        }

        let p: Double
        if tn > tp {
            var eid: Int
            if whole {
                eid = 0
            } else if k == s {
                eid = table.val(s, 1)
            } else {
                eid = unset
                var j = k
                while j > s {
                    j -= 1
                    if table.val(j, fld) == sentinelHold {
                        continue
                    }

                    eid = table.val(j, 1)
                    if eid != unset && eid != hold {
                        break
                    }
                }
            }

            if eid == unset || eid == hold {
                eid = 0
            }

            p = f(Easing.ease(eid, f(t - tp), 0.0, 1.0, f(tn - tp)))
        } else {
            p = 1.0
        }

        if (fld >= 17 && fld <= 27) || fld == 15 {
            return Double(vp)
        }

        let vnF = quant(fld, Double(vn))
        let vpF = quant(fld, Double(vp))
        var it = 0
        if k == s {
            it = table.val(s, 2)
        } else if k > s {
            var j = k
            while true {
                j -= 1
                it = table.val(j, 2)
                if (it != unset && it != hold) || j <= s {
                    break
                }
            }
        } else {
            it = 0
        }

        if it == 2 {
            return vpF
        }

        if it == 1, let ab = splineAb(table, fld, s, e, k, cur) {
            var x = f(f(f(f(ab.b - ab.a) * p) + f(ab.a * 3.0)) * p)
            x = f(x + f(f(vnF - vpF) - f(f(ab.a + ab.a) + ab.b)))
            return f(f(x * p) + vpF)
        }

        return f(f(f(vnF - vpF) * p) + vpF)
    }

    /// VA 0xBA8B0: the record's frame counter quantised by the STMA divisor (a3, signed i16): `frames - frames % n` (C remainder) for
    /// `n >= 2`, else `frames`. The motion keeps its speed and advances in steps of n frames.
    public static func motionFrames(_ frames: Int64, _ divisor: Int) -> Int64 {
        divisor >= 2 ? frames - (frames % Int64(divisor)) : frames
    }

    /// VA 0xBE5A8: motion time in ms, `frames * 50 / 3` in float32.
    public static func motionTimeMs(_ frames: Int64, _ divisor: Int) -> Double {
        f(f(Double(Float(motionFrames(frames, divisor))) * 50.0) / 3.0)
    }

    /// The time used for the keys (VA 0xBE5D3..0xBE63E): null before the first key (nothing applied); clamped to the duration, or wrapped for
    /// looping motions (`loops` = VA 0xC1C70(id), 0 = no loop).
    public static func keyTime(_ table: MotionTable, _ m: MotionRef, _ t: Double, _ loops: Int) -> Double? {
        if Double(table.val(m.start, 0)) > t {
            return nil
        }

        let dur = Double(m.duration)
        if t > dur {
            if loops == 0 {
                return dur
            }

            let span = Int64(m.duration >= 3 || m.duration > loops ? m.duration : 2)
            let lo = Int64(m.duration > loops ? loops : 1)
            if t >= Double(span) {
                let it = StageMath.cvtt64(t)
                let frac = f(t - Double(it))
                if lo == 1 {
                    return f(Double(it % span) + frac)
                }

                return f(Double(((it - lo) % (span - lo)) + lo) + frac)
            }
        }

        return t
    }

    /// The found-scan (VA 0xBE770..0xBE7D0): true if some key with a non-zero time defines field `f` (any value but
    /// -32767 / -100001; HOLD counts), or the current key `k` has time 0.
    public static func found(_ table: MotionTable, _ m: MotionRef, _ k: Int, _ fld: Int) -> Bool {
        var found = false
        for i in m.start..<m.end {
            if table.val(i, 0) == 0 {
                found = found || i == k
                continue
            }

            let v = table.val(i, fld)
            if v != MotionTable.unset && v != MotionTable.unset8 {
                return true
            }
        }

        return found
    }

    /// `_SGMA(l, id, key)` (VA 0xC23B0): writes the layer's drawn state into keyframe `key` of motion `id` in
    /// the session's table. Returns the keyframe index written, or null when the statement does nothing.
    public static func editMotion(_ table: MotionTable, _ rec: LayerRecord, _ id: Int, _ key: Int) -> Int? {
        if id <= 0 {
            return nil
        }

        let k = Int(StageMath.i16(Int64(id - 1)))
        let first = (k >= 1 && k <= table.motionCount) ? (table.get(k)?.end ?? 0) : 0
        let i = Int(StageMath.i32(Int64(first + key)))
        if i < 0 || i >= table.keyCount {
            return nil
        }

        func away(_ v: Int32, _ d: Int32) -> Int32 {
            let q = v / d
            return v - (q * d) == 0 ? q : q + (v >= 0 ? 1 : -1)
        }

        let xi = StageMath.cvtt(f(Double(rec.x * 480.0)))
        let yi = StageMath.cvtt(f(Double(rec.y * 360.0)))
        table.setVal(i, 3, Int(StageMath.i16(Int64(away(xi, 640)))))
        table.setVal(i, 4, Int(StageMath.i16(Int64(away(yi, 480)))))
        table.setVal(i, 5, Int(StageMath.i16(Int64(StageMath.cvtt(f(f(Double(rec.alpha + rec.alphaCur)) * 255.0))))))
        table.setVal(i, 8, Int(rec.rot))
        table.setVal(i, 9, Int(StageMath.i16(Int64(rec.zoomX))))
        table.setVal(i, 10, Int(StageMath.i16(Int64(rec.zoomY))))
        if rec.crop[0] != 0 {
            for j in 0..<4 {
                table.setVal(i, 11 + j, Int(StageMath.i16(Int64(rec.crop[j]))))
            }
        }

        return i
    }
}
