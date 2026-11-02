import Foundation

@inline(__always)
public func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
    value < lower ? lower : (value > upper ? upper : value)
}

@inline(__always)
public func clamp01(_ value: Float) -> Float {
    clamp(value, 0, 1)
}

@inline(__always)
public func mix(_ a: Float, _ b: Float, _ t: Float) -> Float {
    a + (b - a) * t
}

/// Rounds like the PS4's float-to-int conversion for the engine's pixel maths (round half away
/// from zero is the C# default for `(int)MathF.Round`; the engine itself mostly truncates).
@inline(__always)
public func truncInt(_ value: Float) -> Int {
    Int(value.rounded(.towardZero))
}

/// Little-endian 16-bit packing used by the engine's colour words.
@inline(__always)
public func packRGBA8(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8) -> UInt32 {
    UInt32(r) | UInt32(g) << 8 | UInt32(b) << 16 | UInt32(a) << 24
}

@inline(__always)
public func unpackRGBA8(_ rgba: UInt32) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
    (UInt8(truncatingIfNeeded: rgba),
     UInt8(truncatingIfNeeded: rgba >> 8),
     UInt8(truncatingIfNeeded: rgba >> 16),
     UInt8(truncatingIfNeeded: rgba >> 24))
}
