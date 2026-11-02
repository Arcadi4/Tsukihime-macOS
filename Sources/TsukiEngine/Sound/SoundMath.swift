import Foundation

/// The scalar helpers of the sound code, byte-exact ports of the helpers of `tsuki.misc_audio_runtime_semantics`: the engine's
/// integer wraps, the SSE `cvttss2si` / `minss` / `maxss` semantics and the ramps. Every float operation is IEEE
/// float32 in the engine's order (no fused multiply-add).
public enum SoundMath {
    /// Per-frame constants (data VAs 0x175024.., sound_runtime.md 6.2).
    public static let rampDefault: Float = 0.2        // 0x175028: the rate used when a record's rate is <= 0

    /// Fade rate of the BGM slot a new track replaces (0x175084 / 0x1750A4).
    public static let bgmReplaceFade: Float = 4.0

    /// 1000 (ms per second).
    public static let msPerSecond: Float = 1000.0

    /// 60 (frames per second).
    public static let fps: Float = 60.0

    /// 0x175024 = 1666.6666: a rate of 100 volume points in one frame jumps instead of ramping.
    public static let seJumpRate: Float = Float(bitPattern: 0x44D05555)

    /// The low 16 bits as a signed value.
    public static func i16(_ v: Int) -> Int {
        Int(Int16(truncatingIfNeeded: v))
    }

    /// The low 8 bits as a signed value.
    public static func i8(_ v: Int) -> Int {
        Int(Int8(truncatingIfNeeded: v))
    }

    /// Per-frame ramp rate for `delta` volume points over `ms` milliseconds at 60 fps.
    public static func rate(_ delta: Float, _ ms: Float) -> Float {
        let a = delta * msPerSecond
        let b = a / fps
        return b / ms
    }

    /// `vcvttss2si r32`: truncation, the integer indefinite for NaN and overflow.
    public static func trunc(_ x: Float) -> Int {
        if x.isNaN || x.isInfinite || !(x >= -2147483648.0 && x < 2147483648.0) {
            return Int(Int32.min)
        }

        return Int(x)
    }

    /// `minss`: `a < b ? a : b` (the second operand wins for NaN).
    public static func minSs(_ a: Float, _ b: Float) -> Float {
        a < b ? a : b
    }

    /// `maxss`: `a > b ? a : b`.
    public static func maxSs(_ a: Float, _ b: Float) -> Float {
        a > b ? a : b
    }

    /// Moves `cur` toward `tgt` by `step` (VA 0xAE53..0xAEA6 / 0xB1A1..0xB202).
    public static func ramp(_ cur: Float, _ tgt: Float, _ step: Float, always: Bool = false) -> Float {
        if !always && cur == tgt {
            return cur
        }

        let d = tgt - cur
        let ad = maxSs(-d, d)
        if step > ad {
            return tgt
        }

        if cur > tgt {
            return cur - step
        }

        return step + cur
    }

    /// The pan / third-parameter sweep (VA 0xB34D..0xB3B4): the new value and the new rate.
    public static func sweep(_ cur: Float, _ tgt: Float, _ rate: Float, _ dt: Float) -> (value: Float, rate: Float) {
        let p = (rate * dt) + cur
        if rate < 0 {
            if tgt >= p {
                return (tgt, 0)
            }

            return (p, rate)
        }

        if p >= tgt {
            return (tgt, 0)
        }

        return (p, rate)
    }

    /// The ``018` pan value (0 left .. 64 centre .. 128 right) as a pan -1000..1000 (VA 0x89970).
    public static func panFromTag(_ v: Int) -> Int {
        let x = (v * 1000) - 64000
        return x < 0 ? x / 64 : x >> 6
    }

    /// The bits of a float32.
    public static func bits(_ v: Float) -> Int32 {
        Int32(bitPattern: v.bitPattern)
    }
}
