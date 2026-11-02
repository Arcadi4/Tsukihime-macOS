import Foundation
import TsukiCore

/// The `rand()` of the game's own `sce_module/libc.prx` (rand at libc VA 0x1C290, srand at 0x1C310;
/// docs/formats/quake.md 2.1): one global 64-bit LCG, state 1 at boot. Every random consumer of the
/// engine shares one instance; the title screen seeds it with `titleSeed`.
public final class Ps4Rand {
    private static let multiplier: UInt64 = 0x5851_F42D_4C95_7F2D

    /// The 64-bit state.
    public var state: UInt64
    /// Number of `next()` calls so far (for traces).
    public private(set) var calls: Int64 = 0

    public init(state: UInt64 = 1) {
        self.state = state
    }

    /// `srand(seed)`: the state becomes the zero-extended 32-bit seed.
    public func seed(_ seed: UInt32) {
        state = UInt64(seed)
    }

    /// Seed of the title-screen init (VA 0xAFE80): `minute * 256 + second` of the local clock.
    public static func titleSeed(minute: Int, second: Int) -> UInt32 {
        UInt32((minute & 0xFF) << 8 | (second & 0xFF))
    }

    /// `rand()`: 30 bits, `RAND_MAX = 2^30 - 1`.
    public func next() -> Int32 {
        state = state &* Self.multiplier &+ 1
        calls += 1
        return Int32(truncatingIfNeeded: (state >> 32) & 0x3FFF_FFFF)
    }
}

/// The engine's second generator (VA 0xE8200, state at data VA 0xDC7BF0, initial 0x6F37):
/// `s = (s * 0xF131 + 0x11E79431) mod 2^64 >> 1`; the result is `(i64)(int)rand() + s`. Drives the
/// SHK2 flicker.
public final class Rnd2 {
    /// The initial state in the eboot image.
    public static let initialState: UInt64 = 0x6F37

    private let rng: Ps4Rand
    public var state: UInt64

    public init(_ rng: Ps4Rand, state: UInt64 = initialState) {
        self.rng = rng
        self.state = state
    }

    /// One value (one `rand()` call).
    public func next() -> UInt64 {
        state = (state &* 0xF131 &+ 0x11E7_9431) >> 1
        return UInt64(Int64(rng.next())) &+ state
    }
}

/// Helpers built on `rand()` and the libc sine of the shake code.
public enum Ps4Math {
    /// 2 pi as float32 (VA 0x1A72AC).
    public static let twoPi = Float(bitPattern: 0x40C9_0FDB)
    /// 1920-pixel units to canvas x (VA 0x1A72B0).
    public static let third = Float(bitPattern: 0x3EAA_AAAB)
    /// 1080-pixel units to canvas y, 362 / 1080 (VA 0x1A72B4).
    public static let yCanvas = Float(bitPattern: 0x3EAB_9D65)
    /// 2^-30: rand() to [0, 1) (VA 0x1A72A4).
    public static let twoPowMinus30 = Float(bitPattern: 0x3080_0000)
    /// Canvas y to 1080-pixel units, 1080 / 362 (VA 0x1A6DB4).
    public static let yPixels = Float(bitPattern: 0x403E_F071)
    /// The screen shock's y factor in the mask term, 1080 / 448 (VA 0x1A6DBC).
    public static let shockYMask = Float(bitPattern: 0x401A_4925)

    /// 0xC2F90 `rnd_range(a, b)` (MSQK): `lo + (rand() % (trunc((hi - lo) * 2^20) + 1)) * 2^-20`,
    /// one rand call.
    public static func rndRange(_ rng: Ps4Rand, _ a: Float, _ b: Float) -> Float {
        let hi = a > b ? a : b
        let lo = b < a ? b : a
        let r = rng.next()
        let n = Int32(truncatingIfNeeded: StageMath.cvtt(StageMath.f(Double(hi - lo) * 1_048_576)) &+ 1)
        precondition(n != 0, "0xC2F90 range overflow (idiv by 0)")
        let rem = Int64(r) % Int64(n)
        return lo + Float(rem) * 9.536_743_164_062_5e-07
    }

    // libc.prx sinf (libc VA 0x4AF10; FreeBSD msun kernels with double kernels). Constants are the
    // IEEE doubles read from libc.prx data 0xD9290..0xD9360.
    private static let s1 = Double(bitPattern: 0xBFC5_5555_54CB_AC77)
    private static let s2 = Double(bitPattern: 0x3F81_1110_896E_FBB2)
    private static let s3 = Double(bitPattern: 0xBF2A_00F9_E2CA_E774)
    private static let s4 = Double(bitPattern: 0x3EC6_CD87_8C3B_46A7)
    private static let c0 = Double(bitPattern: 0xBFDF_FFFF_FD0C_5E81)
    private static let c1 = Double(bitPattern: 0x3FA5_5553_E105_3A42)
    private static let c2 = Double(bitPattern: 0xBF56_C087_E80F_1E27)
    private static let c3 = Double(bitPattern: 0x3EF9_9342_E0EE_5069)
    private static let pio2One = Double(bitPattern: 0x3FF9_21FB_5444_2D18)
    private static let pio2Two = Double(bitPattern: 0x4009_21FB_5444_2D18)
    private static let pio2Three = Double(bitPattern: 0x4012_D97C_7F33_21D2)
    private static let pio2Four = Double(bitPattern: 0x4019_21FB_5444_2D18)
    private static let invPio2 = Double(bitPattern: 0x3FE4_5F30_6DC9_C883)
    private static let toInt = Double(bitPattern: 0x4338_0000_0000_0000)
    private static let rPio2One = Double(bitPattern: 0x3FF9_21FB_5000_0000)
    private static let rPio2OneT = Double(bitPattern: 0x3E51_10B4_611A_6263)

    private static func kSin(_ x: Double) -> Double {
        let z = x * x
        let w = z * z
        let r = s3 + z * s4
        let s = z * x
        return (x + s * (s1 + z * s2)) + (s * w) * r
    }

    private static func kCos(_ x: Double) -> Double {
        let z = x * x
        let w = z * z
        let r = c2 + z * c3
        return ((1.0 + z * c0) + w * c1) + (z * w) * r
    }

    /// `sinf` of the game's libc.prx for a float32 argument, bit-exact. Arguments above 4.2e8 radians
    /// (not reachable from any shake) fall back to a correctly rounded sine.
    public static func sinf(_ x: Float) -> Float {
        let hx = x.bitPattern
        let ix = hx & 0x7FFF_FFFF
        if ix <= 0x3F49_0FDA {
            if ix < 0x3980_0000 && StageMath.cvtt(x) == 0 { return x }
            return Float(kSin(Double(x)))
        }
        if ix <= 0x407B_53D1 {
            if ix <= 0x4016_CBE3 {
                return hx > 0 ? Float(kCos(Double(x) - pio2One)) : -Float(kCos(Double(x) + pio2One))
            }
            return Float(kSin((hx > 0 ? pio2Two : -pio2Two) - Double(x)))
        }
        if ix <= 0x40E2_31D5 {
            if ix <= 0x40AF_EDDF {
                return hx > 0 ? -Float(kCos(Double(x) - pio2Three)) : Float(kCos(Double(x) + pio2Three))
            }
            return Float(kSin(Double(x) + (hx > 0 ? -pio2Four : pio2Four)))
        }
        if ix >= 0x7F80_0000 { return x - x }
        if ix > 0x4DC9_0FDA { return Float(sin(Double(x))) }

        let fn = (Double(x) * invPio2 + toInt) - toInt
        let n = Int32(truncatingIfNeeded: Int64(fn))
        let y = (Double(x) + fn * -rPio2One) + fn * -rPio2OneT
        switch n & 3 {
        case 0: return Float(kSin(y))
        case 1: return Float(kCos(y))
        case 2: return Float(kSin(-y))
        default: return -Float(kCos(y))
        }
    }
}

/// The easing functions of the layer tweens and motions (VA 0xBC460; docs/formats/layers.md 8.5).
public enum Easing {
    private static let families = ["quad", "cubic", "quart", "quint", "sine", "circ", "expo", "elastic", "back", "bounce"]

    private static let exactIds: Set<Int> = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 14, 15, 18, 19, 20, 26, 27, 34, 35]

    /// The ids ported bit-exactly (and linear, which is every id outside 2..41).
    public static var exact: Set<Int> { exactIds }

    /// Easing function `id` (Penner form: time t, begin b, change c, duration d).
    public static func ease(_ id: Int, _ t: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
        if id >= 10 && id <= 41 && !exactIds.contains(id) {
            let fam = families[(id - 2) / 4]
            switch (id - 2) % 4 {
            case 0: return easeIn(fam, t, b, c, d)
            case 1: return easeOut(fam, t, b, c, d)
            case 2: return easeInOut(fam, t, b, c, d)
            default: return easeOutIn(fam, t, b, c, d)
            }
        }
        return easeExact(id, t, b, c, d)
    }

    private static func bounceOut(_ t0: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
        var t = t0 / d
        if t < 1 / 2.75 { return c * (7.5625 * t * t) + b }
        if t < 2 / 2.75 {
            t -= 1.5 / 2.75
            return c * ((7.5625 * t * t) + 0.75) + b
        }
        if t < 2.5 / 2.75 {
            t -= 2.25 / 2.75
            return c * ((7.5625 * t * t) + 0.9375) + b
        }
        t -= 2.625 / 2.75
        return c * ((7.5625 * t * t) + 0.984375) + b
    }

    private static func easeIn(_ fam: String, _ t0: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
        var t = t0
        switch fam {
        case "quad":
            t /= d
            return c * t * t + b
        case "cubic":
            t /= d
            return c * t * t * t + b
        case "quart":
            t /= d
            return c * pow(t, 4) + b
        case "quint":
            t /= d
            return c * pow(t, 5) + b
        case "sine":
            return -c * cos(t / d * (Double.pi / 2)) + c + b
        case "expo":
            return t == 0 ? b : c * pow(2, 10 * (t / d - 1)) + b - c * 0.001
        case "circ":
            t /= d
            return -c * (sqrt(max(0, 1 - t * t)) - 1) + b
        case "elastic":
            if t == 0 { return b }
            t /= d
            if t == 1 { return b + c }
            let p = d * 0.3
            let s = p / 4
            t -= 1
            return -(c * pow(2, 10 * t) * sin((t * d - s) * (2 * Double.pi) / p)) + b
        case "back":
            let s = 1.70158
            t /= d
            return c * t * t * ((s + 1) * t - s) + b
        case "bounce":
            return c - bounceOut(d - t, 0, c, d) + b
        default:
            preconditionFailure("unknown easing family \(fam)")
        }
    }

    private static func easeOut(_ fam: String, _ t0: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
        var t = t0
        switch fam {
        case "quad":
            t /= d
            return -c * t * (t - 2) + b
        case "cubic":
            t = t / d - 1
            return c * (t * t * t + 1) + b
        case "quart":
            t = t / d - 1
            return -c * (pow(t, 4) - 1) + b
        case "quint":
            t = t / d - 1
            return c * (pow(t, 5) + 1) + b
        case "sine":
            return c * sin(t / d * (Double.pi / 2)) + b
        case "expo":
            return t == d ? b + c : c * 1.001 * (-pow(2, -10 * t / d) + 1) + b
        case "circ":
            t = t / d - 1
            return c * sqrt(max(0, 1 - t * t)) + b
        case "elastic":
            if t == 0 { return b }
            t /= d
            if t == 1 { return b + c }
            let p = d * 0.3
            let s = p / 4
            return c * pow(2, -10 * t) * sin((t * d - s) * (2 * Double.pi) / p) + c + b
        case "back":
            let s = 1.70158
            t = t / d - 1
            return c * (t * t * ((s + 1) * t + s) + 1) + b
        case "bounce":
            return bounceOut(t, b, c, d)
        default:
            preconditionFailure("unknown easing family \(fam)")
        }
    }

    private static func easeInOut(_ fam: String, _ t0: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
        var t = t0
        switch fam {
        case "expo":
            if t == 0 { return b }
            if t == d { return b + c }
            t /= d / 2
            if t < 1 { return c / 2 * pow(2, 10 * (t - 1)) + b - c * 0.0005 }
            t -= 1
            return c / 2 * 1.0005 * (-pow(2, -10 * t) + 2) + b
        case "elastic":
            if t == 0 { return b }
            t /= d / 2
            if t == 2 { return b + c }
            let p = d * (0.3 * 1.5)
            let s = p / 4
            t -= 1
            if t < 0 {
                return -0.5 * (c * pow(2, 10 * t) * sin((t * d - s) * (2 * Double.pi) / p)) + b
            }
            return c * pow(2, -10 * t) * sin((t * d - s) * (2 * Double.pi) / p) * 0.5 + c + b
        case "back":
            let s = 1.70158 * 1.525
            t /= d / 2
            if t < 1 { return c / 2 * (t * t * ((s + 1) * t - s)) + b }
            t -= 2
            return c / 2 * (t * t * ((s + 1) * t + s) + 2) + b
        default:
            break
        }
        if t < d / 2 { return easeIn(fam, t * 2, b, c / 2, d) }
        return easeOut(fam, t * 2 - d, b + c / 2, c / 2, d)
    }

    private static func easeOutIn(_ fam: String, _ t0: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
        let t = t0
        if t < d / 2 { return easeOut(fam, t * 2, b, c / 2, d) }
        return easeIn(fam, t * 2 - d, b + c / 2, c / 2, d)
    }

    /// Bit-exact port of VA 0xBC460 for linear, quad / cubic / quart, quint in / out, sine
    /// in / out / in-out, expo in / out and back in / out, with the engine's float32 / float64 order.
    public static func easeExact(_ id: Int, _ t0: Double, _ b0: Double, _ c0: Double, _ d0: Double) -> Double {
        let t = Float(t0)
        let b = Float(b0)
        let c = Float(c0)
        let d = Float(d0)
        let td = Double(t), bd = Double(b), cd = Double(c), dd = Double(d)
        let k1 = Float(2.70158)
        let k2 = Float(1.70158)
        var x: Float
        switch id {
        case 10:
            x = t / d
            let y = pow(Double(x), 3) * Double(x * c)
            return Double(Float(y + bd))
        case 11:
            x = t / d - 1
            let y = (pow(Double(x), 3) * Double(x) - 1) * cd
            return Double(Float(bd - y))
        case 14:
            x = t / d
            let y = pow(Double(x), 4) * Double(x * c)
            return Double(Float(y + bd))
        case 15:
            x = t / d - 1
            let y = (pow(Double(x), 4) * Double(x) + 1) * cd
            return Double(Float(y + bd))
        case 18:
            x = t / d
            let y = cd - cd * cos(Double(x) * (Double.pi / 2))
            return Double(Float(y + bd))
        case 19:
            x = t / d
            let y = sin(Double(x) * (Double.pi / 2)) * cd
            return Double(Float(y + bd))
        case 20:
            let y = (cos(td * Double.pi / dd) - 1) * (cd * -0.5)
            return Double(Float(bd + y))
        case 26:
            if t == 0 { return Double(b) }
            x = (t / d - 1) * 10
            let y = cd * pow(2, Double(x)) + bd + cd * -0.001
            return Double(Float(y))
        case 27:
            if t == d { return Double(b + c) }
            x = t * -10 / d
            let y = (1 - pow(2, Double(x))) * (cd * 1.001) + bd
            return Double(Float(y))
        case 34:
            x = t / d
            let y = Double(x * (x * c)) * Double(x * k1 - k2)
            return Double(Float(y + bd))
        case 35:
            x = t / d - 1
            let inner = Double((x * x) * (x * k1 + k2) + 1)
            return Double(Float(cd * inner + bd))
        case 2:
            x = t / d
            let y = Double(x * c) * Double(x)
            return Double(Float(y + bd))
        case 3:
            x = t / d
            let y = Double(x * c) * Double(x - 2)
            return Double(Float(bd - y))
        case 4:
            x = t / (d * 0.5)
            if 1 > x {
                let y = Double(c * 0.5) * Double(x * x)
                return Double(Float(y + bd))
            }
            x -= 1
            let y = Double(c * -0.5) * Double((x * (x - 2)) - 1)
            return Double(Float(bd + y))
        case 5:
            x = t + t
            if d * 0.5 > t {
                x /= d
                let y = Double(c * -0.5) * Double(x) * Double(x - 2)
                return Double(Float(y + bd))
            }
            let b2 = c * 0.5 + b
            x = (x - d) / d
            let y = Double(c * 0.5) * Double(x) * Double(x)
            return Double(Float(y + Double(b2)))
        case 6:
            x = t / d
            let y = Double(x * c) * Double(x * x)
            return Double(Float(y + bd))
        case 7:
            x = t / d - 1
            let y = cd * (Double(x * (x * x)) + 1)
            return Double(Float(y + bd))
        case 8:
            x = t / (d * 0.5)
            if 1 > x {
                let y = pow(Double(x), 3) * Double(c * 0.5)
                return Double(Float(y + bd))
            }
            x -= 2
            let y = Double(c * 0.5) * (Double(x * (x * x)) + 2)
            return Double(Float(y + bd))
        case 9:
            x = t + t
            if d * 0.5 > t {
                x = x / d - 1
                let y = Double(c * 0.5) * (Double(x * (x * x)) + 1)
                return Double(Float(y + bd))
            }
            let b2 = c * 0.5 + b
            x = (x - d) / d
            let y = Double(c * 0.5) * Double(x) * Double(x * x)
            return Double(Float(y + Double(b2)))
        default:
            let y = (td * cd) / dd + bd
            return Double(Float(y))
        }
    }
}
