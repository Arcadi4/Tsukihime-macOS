import Foundation

/// A rented tile buffer. `length` bytes of `array` are the tile.
public final class StagingBuffer: @unchecked Sendable {
    public var array: [UInt8]
    public var length: Int

    public init(array: [UInt8]) {
        self.array = array
        self.length = array.count
    }

    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try array.withUnsafeBytes { ptr in
            let slice = UnsafeRawBufferPointer(rebasing: ptr[..<length])
            return try body(slice)
        }
    }

    public func withUnsafeMutableBytes<R>(_ body: (UnsafeMutableRawBufferPointer) throws -> R) rethrows -> R {
        try array.withUnsafeMutableBytes { ptr in
            let slice = UnsafeMutableRawBufferPointer(rebasing: ptr[..<length])
            return try body(slice)
        }
    }
}

/// A byte-bounded pool of pre-allocated buffers. Thread-safe.
public final class StagingPool: @unchecked Sendable {
    private static let page = 4096

    private let lock = NSCondition()
    private var freeBuffers: [Int: [ [UInt8] ]] = [:]
    private var freeBytes: Int64 = 0
    private var _outstandingBytes: Int64 = 0

    public let budgetBytes: Int64
    public private(set) var peakOutstandingBytes: Int64 = 0
    public private(set) var peakTotalBytes: Int64 = 0
    public private(set) var waits: Int64 = 0
    public private(set) var allocations: Int64 = 0

    public init(budgetBytes: Int64 = 64 << 20) {
        self.budgetBytes = budgetBytes
    }

    public var outstandingBytes: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return _outstandingBytes
    }

    /// Rents a buffer of `size` bytes, waiting while the pool is at its budget.
    public func rent(size: Int) -> StagingBuffer {
        precondition(size >= 1)
        let s = Int64(size)
        var array: [UInt8]?

        lock.lock()
        while true {
            if var stack = freeBuffers[size], !stack.isEmpty {
                array = stack.removeLast()
                freeBuffers[size] = stack
                freeBytes -= s
                break
            }

            if _outstandingBytes + freeBytes + s <= budgetBytes || _outstandingBytes == 0 {
                // Drop free buffers of other sizes if needed to stay within budget
                for (otherSize, var otherStack) in freeBuffers {
                    while !otherStack.isEmpty && _outstandingBytes + freeBytes + s > budgetBytes {
                        _ = otherStack.removeLast()
                        freeBytes -= Int64(otherSize)
                    }
                    freeBuffers[otherSize] = otherStack
                }

                if _outstandingBytes + freeBytes + s <= budgetBytes || _outstandingBytes == 0 {
                    break
                }
            }

            waits += 1
            lock.wait()
        }

        _outstandingBytes += s
        peakOutstandingBytes = max(peakOutstandingBytes, _outstandingBytes)
        peakTotalBytes = max(peakTotalBytes, _outstandingBytes + freeBytes)
        if array == nil {
            allocations += 1
        }
        lock.unlock()

        let result = array ?? Self.allocate(size)
        let buf = StagingBuffer(array: result)
        buf.length = size
        return buf
    }

    /// Returns a rented buffer.
    public func returnBuffer(_ buffer: StagingBuffer) {
        let size = buffer.array.count
        let s = Int64(size)
        lock.lock()
        _outstandingBytes -= s
        if _outstandingBytes + freeBytes + s <= budgetBytes {
            var stack = freeBuffers[size] ?? []
            stack.append(buffer.array)
            freeBuffers[size] = stack
            freeBytes += s
        }
        lock.broadcast()
        lock.unlock()
    }

    private static func allocate(_ size: Int) -> [UInt8] {
        var a = [UInt8](repeating: 0, count: size)
        var i = 0
        while i < size {
            a[i] = 0
            i += page
        }
        a[size - 1] = 0
        return a
    }
}
