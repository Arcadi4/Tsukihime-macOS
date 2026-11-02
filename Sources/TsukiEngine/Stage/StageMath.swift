import Foundation

/// Numeric helpers of the layer model. The PS4 engine computes in SSE float32 with one rounding per
/// operation and converts with `cvttss2si`; the port reproduces that.
enum StageMath {
    /// Rounds to float32.
    @inline(__always) static func f(_ x: Double) -> Float { Float(x) }
    @inline(__always) static func f(_ x: Float) -> Float { x }

    /// `cvttss2si` to a 32-bit register: truncate toward zero; NaN and out of range give INT_MIN.
    @inline(__always) static func cvtt(_ x: Float) -> Int32 {
        x.isNaN || !(x >= -2_147_483_648 && x < 2_147_483_648) ? Int32.min : Int32(x)
    }

    /// The same for a double.
    @inline(__always) static func cvtt(_ x: Double) -> Int32 {
        x.isNaN || !(x >= -2_147_483_648 && x < 2_147_483_648) ? Int32.min : Int32(x)
    }

    /// Truncation toward zero to 64 bits.
    static func cvtt64(_ x: Double) -> Int64 {
        x.isNaN || !(x >= -9_223_372_036_854_775_808 && x < 9_223_372_036_854_775_808) ? Int64.min : Int64(x)
    }

    @inline(__always) static func i16(_ v: Int64) -> Int16 { Int16(truncatingIfNeeded: v) }
    @inline(__always) static func i8(_ v: Int64) -> Int8 { Int8(truncatingIfNeeded: v) }
    @inline(__always) static func i32(_ v: Int64) -> Int32 { Int32(truncatingIfNeeded: v) }

    /// C integer division (truncates toward zero) on 64-bit operands, result wrapped to 32 bits.
    @inline(__always) static func cdiv(_ a: Int64, _ b: Int64) -> Int32 {
        Int32(truncatingIfNeeded: a / b)
    }

    /// `trunc(ms * 60 / 1000)` frames of STGS / STZ4 / STRT / STCL.
    static func msToFrames60(_ ms: Int32) -> Int32 { cdiv(Int64(ms) * 60, 1000) }

    /// `trunc(3 * ms / 50)` frames of SQK2 / SHK2 / SSW2 / STRA (32-bit multiply, VA 0x846B6).
    static func msToFrames(_ ms: Int32) -> Int32 { cdiv(Int64(ms &* 3), 50) }

    /// STCH x to engine units: `trunc(x * 640 / 480)` (VA 0x82941).
    static func scriptX(_ x: Int32) -> Int32 { cdiv(Int64(x) * 640, 480) }

    /// STCH y to engine units: `trunc(y * 480 / 360)` (VA 0x829A6).
    static func scriptY(_ y: Int32) -> Int32 { cdiv(Int64(y) * 480, 360) }

    /// STCH a19 / STRR: `v % 36000` (C remainder) moved into [-18000, 18000] (VA 0x821DF..0x82215).
    static func wrapAngle(_ v: Int32) -> Int32 {
        var r = v % 36000
        if r <= -18001 { r += 36000 } else if r >= 18001 { r -= 36000 }
        return r
    }

    /// The u8 of a colour channel.
    @inline(__always) static func b(_ v: Int32) -> UInt8 { UInt8(truncatingIfNeeded: v) }
}
