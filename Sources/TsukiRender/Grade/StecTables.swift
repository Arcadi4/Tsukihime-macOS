import Foundation
import TsukiCore
import TsukiData

/// The 81 colour-grade modes of `_STEC` as the eboot holds them.
public final class StecTables: @unchecked Sendable {
    /// Number of modes (ids 1..81).
    public static let count = 81

    /// Text VA of the flag words, `i32[81]`: 0x100 per-channel LUTs, 0x200 luma into the LUTs, 0x400 solid colour.
    public static let flagsVa = 0x2D5A78

    /// Relocated pointer arrays to the 256-byte LUT of byte 0 (blue), byte 1 (green), byte 2 (red), `u8*[81]` each.
    public static let lutPointerVa: [Int] = [0x42C590, 0x42C308, 0x42C080]

    /// Text VA of the luma weight of byte 0 (blue), `i32[81]`.
    public static let weightBlueVa = 0x2D5D00

    /// Text VA of the luma weight of byte 2 (red), `i32[81]` (the weight of byte 1 is 0x224).
    public static let weightRedVa = 0x2D5BBC

    /// Text VA of the two luma constants, `f32[2]` = (382.5, 765.0).
    public static let lumaConstantsVa = 0x2D4008

    public let lumaOffset: Float
    public let lumaDivisor: Float

    private let flagsArray: [Int32]
    private let weightBlueArray: [Int32]
    private let weightRedArray: [Int32]
    private let lutsData: [UInt8]

    /// Creates tables from raw arrays.
    public init(
        flags: [Int32],
        weightBlue: [Int32],
        weightRed: [Int32],
        luts: [UInt8],
        lumaOffset: Float = 382.5,
        lumaDivisor: Float = 765.0
    ) {
        precondition(flags.count == Self.count)
        precondition(weightBlue.count == Self.count)
        precondition(weightRed.count == Self.count)
        precondition(luts.count == Self.count * 3 * 256)
        self.flagsArray = flags
        self.weightBlueArray = weightBlue
        self.weightRedArray = weightRed
        self.lutsData = luts
        self.lumaOffset = lumaOffset
        self.lumaDivisor = lumaDivisor
    }

    /// The flag word of mode `id` (1..81).
    public func flags(_ id: Int) -> Int {
        Int(flagsArray[id - 1])
    }

    /// The luma weight of byte 0 (blue) of mode `id`.
    public func weightBlue(_ id: Int) -> Int {
        Int(weightBlueArray[id - 1])
    }

    /// The luma weight of byte 2 (red) of mode `id`.
    public func weightRed(_ id: Int) -> Int {
        Int(weightRedArray[id - 1])
    }

    /// The 256-byte LUT of mode `id` for byte `channel` (0 blue, 1 green, 2 red).
    public func lut(_ id: Int, _ channel: Int) -> [UInt8] {
        let start = (((id - 1) * 3) + channel) * 256
        return Array(lutsData[start..<(start + 256)])
    }

    /// Direct access to the 256-byte LUT without copying.
    public func withLut<R>(_ id: Int, _ channel: Int, _ body: (UnsafeBufferPointer<UInt8>) throws -> R) rethrows -> R {
        let start = (((id - 1) * 3) + channel) * 256
        return try lutsData.withUnsafeBufferPointer { buf in
            let slice = UnsafeBufferPointer(rebasing: buf[start..<(start + 256)])
            return try body(slice)
        }
    }

    /// Reads the tables from the eboot.
    public static func read(_ eboot: EbootReader) throws -> StecTables {
        var relocated: [UInt64: Int] = [:]
        for r in eboot.image.rela() {
            if r.type == SelfImage.rX86Relative {
                relocated[r.offset] = Int(r.addend)
            }
        }

        let flags = try readInts(eboot, flagsVa)
        let wb = try readInts(eboot, weightBlueVa)
        let wr = try readInts(eboot, weightRedVa)
        let k = try eboot.read(lumaConstantsVa, 8)
        let offset = k.f32(0)
        let divisor = k.f32(4)

        var luts = [UInt8](repeating: 0, count: count * 3 * 256)
        for channel in 0..<3 {
            for mode in 0..<count {
                let slot = lutPointerVa[channel] + (8 * mode)
                let ptr = try relocated[UInt64(slot)] ?? Int(eboot.u64(slot))
                if ptr != 0 {
                    let bytes = try eboot.read(ptr, 256)
                    let dstStart = (((mode * 3) + channel) * 256)
                    for i in 0..<256 {
                        luts[dstStart + i] = bytes[i]
                    }
                }
            }
        }

        return StecTables(flags: flags, weightBlue: wb, weightRed: wr, luts: luts, lumaOffset: offset, lumaDivisor: divisor)
    }

    private static func readInts(_ eboot: EbootReader, _ va: Int) throws -> [Int32] {
        let raw = try eboot.read(va, count * 4)
        var values = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            values[i] = raw.i32(i * 4)
        }
        return values
    }
}
