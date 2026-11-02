import Foundation

/// A mutable block of bytes that several windows can share. It backs the game's fixed-size state
/// records (save slots, config, history entries) so a record can be viewed field by field and
/// copied to disk unchanged.
public final class ByteStorage {
    public var bytes: [UInt8]

    public init(count: Int) {
        bytes = [UInt8](repeating: 0, count: count)
    }

    public init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    public var count: Int { bytes.count }
}

/// A live, writable window into a `ByteStorage`.
public struct ByteWindow {
    public let storage: ByteStorage
    public let offset: Int
    public let length: Int

    public init(storage: ByteStorage, offset: Int, length: Int) {
        precondition(offset >= 0 && length >= 0 && offset + length <= storage.bytes.count)
        self.storage = storage
        self.offset = offset
        self.length = length
    }

    public init(count: Int) {
        self.init(storage: ByteStorage(count: count), offset: 0, length: count)
    }

    public var span: ByteSpan {
        ByteSpan(window: storage, offset: offset, count: length)
    }

    public var end: Int { offset + length }

    public subscript(index: Int) -> UInt8 {
        get {
            precondition(index >= 0 && index < length)
            return storage.bytes[offset + index]
        }
        nonmutating set {
            precondition(index >= 0 && index < length)
            storage.bytes[offset + index] = newValue
        }
    }

    public func slice(_ sliceOffset: Int, _ count: Int) -> ByteWindow {
        precondition(sliceOffset >= 0 && count >= 0 && sliceOffset + count <= length)
        return ByteWindow(storage: storage, offset: offset + sliceOffset, length: count)
    }

    public func copy(from source: ByteSpan) {
        precondition(source.count == length, "expected \(length) bytes, got \(source.count)")
        guard length > 0 else { return }
        storage.bytes.withUnsafeMutableBytes { dst in
            source.withUnsafeBytes { src in
                dst.baseAddress!.advanced(by: offset).copyMemory(from: src.baseAddress!, byteCount: length)
            }
        }
    }

    public func copy(from source: ByteWindow) {
        copy(from: source.span)
    }

    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try storage.bytes.withUnsafeBytes { raw in
            try body(UnsafeRawBufferPointer(start: raw.baseAddress!.advanced(by: offset), count: length))
        }
    }

    public func withUnsafeMutableBytes<R>(_ body: (UnsafeMutableRawBufferPointer) throws -> R) rethrows -> R {
        try storage.bytes.withUnsafeMutableBytes { raw in
            try body(UnsafeMutableRawBufferPointer(start: raw.baseAddress!.advanced(by: offset), count: length))
        }
    }

    /// Little-endian scalar access. Index checks are preconditions: parsers validate lengths first.
    public func u8(_ o: Int) -> UInt8 { self[o] }
    public func i8(_ o: Int) -> Int8 { Int8(bitPattern: self[o]) }
    public func u16(_ o: Int) -> UInt16 { UInt16(self[o]) | UInt16(self[o + 1]) << 8 }
    public func i16(_ o: Int) -> Int16 { Int16(bitPattern: u16(o)) }
    public func u32(_ o: Int) -> UInt32 {
        UInt32(self[o]) | UInt32(self[o + 1]) << 8 | UInt32(self[o + 2]) << 16 | UInt32(self[o + 3]) << 24
    }
    public func i32(_ o: Int) -> Int32 { Int32(bitPattern: u32(o)) }
    public func u64(_ o: Int) -> UInt64 {
        UInt64(u32(o)) | UInt64(u32(o + 4)) << 32
    }
    public func i64(_ o: Int) -> Int64 { Int64(bitPattern: u64(o)) }
    public func f32(_ o: Int) -> Float { Float(bitPattern: u32(o)) }

    public func setU8(_ o: Int, _ v: UInt8) { self[o] = v }
    public func setI8(_ o: Int, _ v: Int8) { self[o] = UInt8(bitPattern: v) }
    public func setU16(_ o: Int, _ v: UInt16) {
        self[o] = UInt8(truncatingIfNeeded: v)
        self[o + 1] = UInt8(truncatingIfNeeded: v >> 8)
    }
    public func setI16(_ o: Int, _ v: Int16) { setU16(o, UInt16(bitPattern: v)) }
    public func setU32(_ o: Int, _ v: UInt32) {
        self[o] = UInt8(truncatingIfNeeded: v)
        self[o + 1] = UInt8(truncatingIfNeeded: v >> 8)
        self[o + 2] = UInt8(truncatingIfNeeded: v >> 16)
        self[o + 3] = UInt8(truncatingIfNeeded: v >> 24)
    }
    public func setI32(_ o: Int, _ v: Int32) { setU32(o, UInt32(bitPattern: v)) }
    public func setU64(_ o: Int, _ v: UInt64) {
        setU32(o, UInt32(truncatingIfNeeded: v))
        setU32(o + 4, UInt32(truncatingIfNeeded: v >> 32))
    }
    public func setI64(_ o: Int, _ v: Int64) { setU64(o, UInt64(bitPattern: v)) }
    public func setF32(_ o: Int, _ v: Float) { setU32(o, v.bitPattern) }

    public func getBit(_ bit: Int) -> Bool {
        (storage.bytes[offset + (bit >> 3)] >> (bit & 7)) & 1 != 0
    }

    public func setBit(_ bit: Int, _ value: Bool) {
        let at = offset + (bit >> 3)
        let mask = UInt8(1 << (bit & 7))
        storage.bytes[at] = value ? (storage.bytes[at] | mask) : (storage.bytes[at] & ~mask)
    }

    public func clear() {
        for i in 0..<length { self[i] = 0 }
    }
}

/// A read-only view of bytes: an owned buffer, a window into shared mutable storage, or a window
/// into a memory-mapped file. Slicing is O(1) and never copies.
public struct ByteSpan: RandomAccessCollection {
    public typealias Element = UInt8
    public typealias Index = Int

    enum Storage {
        case array([UInt8], Int)
        case window(ByteStorage, Int)
        case mapped(MappedFile, Int)
    }

    var storage: Storage
    var _count: Int

    public init() {
        storage = .array([], 0)
        _count = 0
    }

    public init(_ bytes: [UInt8]) {
        storage = .array(bytes, 0)
        _count = bytes.count
    }

    public init(_ slice: ArraySlice<UInt8>) {
        let buffer = Array(slice)
        storage = .array(buffer, 0)
        _count = buffer.count
    }

    public init(_ bytes: [UInt8], offset: Int, count: Int) {
        precondition(offset >= 0 && count >= 0 && offset + count <= bytes.count)
        storage = .array(bytes, offset)
        _count = count
    }

    init(window: ByteStorage, offset: Int, count: Int) {
        storage = .window(window, offset)
        _count = count
    }

    init(mapped: MappedFile, offset: Int, count: Int) {
        storage = .mapped(mapped, offset)
        _count = count
    }

    public var count: Int { _count }
    public var isEmpty: Bool { _count == 0 }
    public var startIndex: Int { 0 }
    public var endIndex: Int { _count }

    public func index(after i: Int) -> Int { i + 1 }
    public func index(before i: Int) -> Int { i - 1 }
    public func index(_ i: Int, offsetBy distance: Int) -> Int { i + distance }
    public func distance(from start: Int, to end: Int) -> Int { end - start }

    public subscript(index: Int) -> UInt8 {
        switch storage {
        case let .array(buffer, base):
            return buffer[base + index]
        case let .window(storage, base):
            return storage.bytes[base + index]
        case let .mapped(file, base):
            return file.byte(at: base + index)
        }
    }

    public static func == (left: ByteSpan, right: ByteSpan) -> Bool {
        left.elementsEqual(right)
    }

    /// A subrange; O(1). The caller must keep indexes inside `0..<count`.
    public func slice(_ offset: Int, _ count: Int) -> ByteSpan {
        precondition(offset >= 0 && count >= 0 && offset + count <= _count,
                     "slice [\(offset), \(offset + count)) outside \(_count) bytes")
        var result = self
        switch storage {
        case let .array(buffer, base):
            result.storage = .array(buffer, base + offset)
        case let .window(storage, base):
            result.storage = .window(storage, base + offset)
        case let .mapped(file, base):
            result.storage = .mapped(file, base + offset)
        }
        result._count = count
        return result
    }

    public func suffix(from offset: Int) -> ByteSpan {
        slice(offset, _count - offset)
    }

    public func toArray() -> [UInt8] {
        switch storage {
        case let .array(buffer, base):
            return Array(buffer[base..<base + _count])
        case let .window(storage, base):
            return Array(storage.bytes[base..<base + _count])
        case let .mapped(file, base):
            return file.read(offset: base, length: _count)
        }
    }

    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        switch storage {
        case let .array(buffer, base):
            return try buffer.withUnsafeBytes { raw in
                try body(UnsafeRawBufferPointer(start: raw.baseAddress?.advanced(by: base), count: _count))
            }
        case let .window(storage, base):
            return try storage.bytes.withUnsafeBytes { raw in
                try body(UnsafeRawBufferPointer(start: raw.baseAddress?.advanced(by: base), count: _count))
            }
        case let .mapped(file, base):
            return try body(file.rawBuffer(offset: base, length: _count))
        }
    }

    /// Little-endian scalar reads. Parsers check lengths before reading.
    public func u8(_ o: Int) -> UInt8 { self[o] }
    public func i8(_ o: Int) -> Int8 { Int8(bitPattern: self[o]) }
    public func u16(_ o: Int) -> UInt16 { UInt16(self[o]) | UInt16(self[o + 1]) << 8 }
    public func i16(_ o: Int) -> Int16 { Int16(bitPattern: u16(o)) }
    public func u32(_ o: Int) -> UInt32 {
        UInt32(self[o]) | UInt32(self[o + 1]) << 8 | UInt32(self[o + 2]) << 16 | UInt32(self[o + 3]) << 24
    }
    public func i32(_ o: Int) -> Int32 { Int32(bitPattern: u32(o)) }
    public func u64(_ o: Int) -> UInt64 { UInt64(u32(o)) | UInt64(u32(o + 4)) << 32 }
    public func i64(_ o: Int) -> Int64 { Int64(bitPattern: u64(o)) }
    public func f32(_ o: Int) -> Float { Float(bitPattern: u32(o)) }
    public func f64(_ o: Int) -> Double { Double(bitPattern: u64(o)) }

    public func u16be(_ o: Int) -> UInt16 { UInt16(self[o]) << 8 | UInt16(self[o + 1]) }
    public func u32be(_ o: Int) -> UInt32 {
        UInt32(self[o]) << 24 | UInt32(self[o + 1]) << 16 | UInt32(self[o + 2]) << 8 | UInt32(self[o + 3])
    }
}

/// Sequential writer with little-endian scalars.
public struct ByteWriter {
    public private(set) var bytes: [UInt8] = []

    public init(reserving capacity: Int = 0) {
        bytes.reserveCapacity(capacity)
    }

    public var count: Int { bytes.count }

    public mutating func u8(_ value: UInt8) { bytes.append(value) }
    public mutating func i8(_ value: Int8) { bytes.append(UInt8(bitPattern: value)) }
    public mutating func raw(_ values: [UInt8]) { bytes.append(contentsOf: values) }
    public mutating func raw(_ span: ByteSpan) { bytes.append(contentsOf: span) }

    public mutating func u16(_ value: UInt16) {
        bytes.append(UInt8(truncatingIfNeeded: value))
        bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    public mutating func i16(_ value: Int16) { u16(UInt16(bitPattern: value)) }

    public mutating func u32(_ value: UInt32) {
        bytes.append(UInt8(truncatingIfNeeded: value))
        bytes.append(UInt8(truncatingIfNeeded: value >> 8))
        bytes.append(UInt8(truncatingIfNeeded: value >> 16))
        bytes.append(UInt8(truncatingIfNeeded: value >> 24))
    }

    public mutating func i32(_ value: Int32) { u32(UInt32(bitPattern: value)) }

    public mutating func u64(_ value: UInt64) {
        u32(UInt32(truncatingIfNeeded: value))
        u32(UInt32(truncatingIfNeeded: value >> 32))
    }

    public mutating func i64(_ value: Int64) { u64(UInt64(bitPattern: value)) }
    public mutating func f32(_ value: Float) { u32(value.bitPattern) }
    public mutating func u32be(_ value: UInt32) {
        bytes.append(UInt8(truncatingIfNeeded: value >> 24))
        bytes.append(UInt8(truncatingIfNeeded: value >> 16))
        bytes.append(UInt8(truncatingIfNeeded: value >> 8))
        bytes.append(UInt8(truncatingIfNeeded: value))
    }

    public mutating func align(to boundary: Int, with filler: UInt8 = 0) {
        precondition(boundary > 0)
        while bytes.count % boundary != 0 { bytes.append(filler) }
    }

    public mutating func patchU32(at offset: Int, _ value: UInt32) {
        precondition(offset >= 0 && offset + 4 <= bytes.count)
        bytes[offset] = UInt8(truncatingIfNeeded: value)
        bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
        bytes[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
        bytes[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
    }
}

/// Bounds-checked sequential reader. Parsers use it for file headers and tables; hot loops read a
/// `ByteSpan` directly after checking its length once.
public struct ByteCursor {
    public let span: ByteSpan
    public private(set) var offset: Int

    public init(_ span: ByteSpan, offset: Int = 0) {
        self.span = span
        self.offset = offset
    }

    public var remaining: Int { span.count - offset }
    public var isAtEnd: Bool { offset >= span.count }

    public mutating func u8() throws -> UInt8 {
        try require(1)
        defer { offset += 1 }
        return span[offset]
    }

    public mutating func i8() throws -> Int8 { Int8(bitPattern: try u8()) }

    public mutating func u16() throws -> UInt16 {
        try require(2)
        defer { offset += 2 }
        return span.u16(offset)
    }

    public mutating func i16() throws -> Int16 { Int16(bitPattern: try u16()) }

    public mutating func u32() throws -> UInt32 {
        try require(4)
        defer { offset += 4 }
        return span.u32(offset)
    }

    public mutating func i32() throws -> Int32 { Int32(bitPattern: try u32()) }

    public mutating func u64() throws -> UInt64 {
        try require(8)
        defer { offset += 8 }
        return span.u64(offset)
    }

    public mutating func f32() throws -> Float { Float(bitPattern: try u32()) }

    public mutating func bytes(_ count: Int) throws -> ByteSpan {
        try require(count)
        defer { offset += count }
        return span.slice(offset, count)
    }

    public mutating func skip(_ count: Int) throws {
        try require(count)
        offset += count
    }

    public mutating func require(_ count: Int) throws {
        if count < 0 || remaining < count {
            throw TsukiError.format("read of \(count) bytes at \(offset) past the end of \(span.count) bytes")
        }
    }
}
