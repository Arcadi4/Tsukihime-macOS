import Foundation
import TsukiCore

/// What a state field holds and which accessors the block exposes for it.
public enum StateFieldKind: UInt8, Sendable {
    case scalar = 0
    case array = 1
    case bits = 2
    case bytes = 3
    case block = 4
    case unused = 5
}

/// One entry of a state block's field map. The maps tile every byte of their block in offset order.
public struct StateField: Sendable {
    public let name: String
    public let oracleName: String
    public let offset: Int
    public let size: Int
    public let kind: StateFieldKind
    /// `u8 i8 u16 i16 u32 i32 u64 i64 f32`, `bytes`, or a block class name.
    public let type: String
    public let count: Int
    public let perEntry: Int

    public init(name: String, oracleName: String, offset: Int, size: Int, kind: StateFieldKind,
                type: String, count: Int = 1, perEntry: Int = 1) {
        self.name = name
        self.oracleName = oracleName
        self.offset = offset
        self.size = size
        self.kind = kind
        self.type = type
        self.count = count
        self.perEntry = perEntry
    }

    public var end: Int { offset + size }
    public var entrySize: Int { kind == .array ? size / count : size }
}

/// A fixed-size window of bytes with typed little-endian accessors. A block either owns a fresh
/// zeroed storage or is a view into a larger one, so bytes can be copied, saved and compared as the
/// PS4 engine does with memcpy.
open class StateBlock {
    public let storage: ByteStorage
    public let offset: Int
    public let length: Int

    public init(size: Int) {
        storage = ByteStorage(count: size)
        offset = 0
        length = size
    }

    public init(storage: ByteStorage, offset: Int, length: Int) {
        precondition(offset >= 0 && length >= 0 && offset + length <= storage.bytes.count,
                     "the block needs 0x\(String(length, radix: 16)) bytes at offset 0x\(String(offset, radix: 16))")
        self.storage = storage
        self.offset = offset
        self.length = length
    }

    public var window: ByteWindow {
        ByteWindow(storage: storage, offset: offset, length: length)
    }

    /// The block's bytes (zero-copy view).
    public var bytes: ByteSpan { window.span }

    public func copy(from source: ByteSpan) {
        precondition(source.count == length, "expected 0x\(String(length, radix: 16)) bytes, got 0x\(String(source.count, radix: 16))")
        window.copy(from: source)
    }

    public func copy(from source: StateBlock) {
        copy(from: source.bytes)
    }

    public func contentEquals(_ other: StateBlock) -> Bool {
        bytes.elementsEqual(other.bytes)
    }

    public func clear() {
        window.copy(from: ByteSpan([UInt8](repeating: 0, count: length)))
    }

    /// `index` when it is in `0..<count`, else a trap describing the bad index.
    @discardableResult
    public static func checkIndex(_ index: Int, _ count: Int) -> Int {
        precondition(index >= 0 && index < count, "index must be in 0..\(count - 1), got \(index)")
        return index
    }

    public func slice(_ sliceOffset: Int, _ count: Int) -> ByteWindow {
        window.slice(sliceOffset, count)
    }

    public func readU8(_ o: Int) -> UInt8 { storage.bytes[offset + o] }
    public func writeU8(_ o: Int, _ v: UInt8) { storage.bytes[offset + o] = v }
    public func readI8(_ o: Int) -> Int8 { Int8(bitPattern: storage.bytes[offset + o]) }
    public func writeI8(_ o: Int, _ v: Int8) { storage.bytes[offset + o] = UInt8(bitPattern: v) }

    public func readU16(_ o: Int) -> UInt16 { loadLE(o, UInt16.self) }
    public func writeU16(_ o: Int, _ v: UInt16) { storeLE(o, v) }
    public func readI16(_ o: Int) -> Int16 { loadLE(o, Int16.self) }
    public func writeI16(_ o: Int, _ v: Int16) { storeLE(o, v) }
    public func readU32(_ o: Int) -> UInt32 { loadLE(o, UInt32.self) }
    public func writeU32(_ o: Int, _ v: UInt32) { storeLE(o, v) }
    public func readI32(_ o: Int) -> Int32 { loadLE(o, Int32.self) }
    public func writeI32(_ o: Int, _ v: Int32) { storeLE(o, v) }
    public func readU64(_ o: Int) -> UInt64 { loadLE(o, UInt64.self) }
    public func writeU64(_ o: Int, _ v: UInt64) { storeLE(o, v) }
    public func readI64(_ o: Int) -> Int64 { loadLE(o, Int64.self) }
    public func writeI64(_ o: Int, _ v: Int64) { storeLE(o, v) }

    /// Bit-exact little-endian IEEE float32 (NaN payloads are kept).
    public func readF32(_ o: Int) -> Float { Float(bitPattern: loadLE(o, UInt32.self)) }
    public func writeF32(_ o: Int, _ v: Float) { storeLE(o, v.bitPattern) }

    /// Bit `bit` of the bit set at `offset` (byte bit / 8, bit bit % 8).
    public func getBit(_ o: Int, _ bit: Int) -> Bool {
        (storage.bytes[offset + o + (bit >> 3)] >> UInt8(bit & 7)) & 1 != 0
    }

    public func setBit(_ o: Int, _ bit: Int, _ value: Bool) {
        let i = offset + o + (bit >> 3)
        let mask: UInt8 = 1 << UInt8(bit & 7)
        storage.bytes[i] = value ? storage.bytes[i] | mask : storage.bytes[i] & ~mask
    }

    private func loadLE<T: FixedWidthInteger>(_ o: Int, _ type: T.Type) -> T {
        let i = offset + o
        var value: T = 0
        for k in 0..<MemoryLayout<T>.size {
            value |= T(storage.bytes[i + k]) << T(8 * k)
        }
        return value
    }

    private func storeLE<T: FixedWidthInteger>(_ o: Int, _ value: T) {
        let i = offset + o
        for k in 0..<MemoryLayout<T>.size {
            storage.bytes[i + k] = UInt8(truncatingIfNeeded: value >> T(8 * k))
        }
    }
}
