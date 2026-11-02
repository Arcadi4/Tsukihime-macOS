import Darwin
import Foundation

/// A whole file mapped read-only into the process address space. Opening maps address space only;
/// the operating system pages in what is touched, so a 24 GB archive can be scanned without reading
/// it into memory. Views handed out by `span(offset:length:)` keep the mapping alive and are
/// zero-copy.
public final class MappedFile {
    public let path: String
    public let length: Int

    private var base: UnsafeMutableRawPointer?
    private var disposed = false
    private let lock = NSLock()

    public init(path: String) throws {
        let full = (path as NSString).standardizingPath
        let attributes = try FileManager.default.attributesOfItem(atPath: full)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        self.path = full
        self.length = size
        if size == 0 {
            base = nil
            return
        }

        let fd = open(full, O_RDONLY)
        guard fd >= 0 else {
            throw TsukiError.io("cannot open \(full): \(String(cString: strerror(errno)))")
        }
        defer { close(fd) }

        guard let mapping = mmap(nil, size, PROT_READ, MAP_PRIVATE, fd, 0), mapping != MAP_FAILED else {
            throw TsukiError.io("cannot map \(full): \(String(cString: strerror(errno)))")
        }
        base = mapping
    }

    deinit {
        unmap()
    }

    public var isDisposed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return disposed
    }

    /// Frees the mapping. Views obtained earlier become invalid, as with any mapped buffer.
    public func dispose() {
        lock.lock()
        defer { lock.unlock() }
        guard !disposed else { return }
        disposed = true
        if let base, length > 0 {
            munmap(base, length)
        }
        base = nil
    }

    /// A view of the whole file.
    public func span() -> ByteSpan {
        ByteSpan(mapped: self, offset: 0, count: length)
    }

    /// A zero-copy view of `[offset, offset + count)`.
    public func span(offset: Int, length count: Int) throws -> ByteSpan {
        guard offset >= 0, count >= 0, offset + count <= length else {
            throw TsukiError.bounds("range [\(offset), \(offset + count)) outside the \(length)-byte file \(path)")
        }
        checkLive()
        return ByteSpan(mapped: self, offset: offset, count: count)
    }

    public func read(offset: Int, length count: Int) -> [UInt8] {
        precondition(offset >= 0 && count >= 0 && offset + count <= length)
        guard count > 0 else { return [] }
        checkLive()
        let raw = rawBuffer(offset: offset, length: count)
        return [UInt8](raw)
    }

    /// Calls `body` with the whole mapping.
    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try body(rawBuffer(offset: 0, length: length))
    }

    /// Drops the resident pages this process touched from its working set; a later read is a soft
    /// fault. The mapping stays valid.
    public func trimResident(_ trim: (UnsafeMutableRawPointer, Int) -> Void) {
        checkLive()
        guard let base, length > 0 else { return }
        let piece = 1 << 30
        var offset = 0
        while offset < length {
            trim(base.advanced(by: offset), min(piece, length - offset))
            offset += piece
        }
    }

    func byte(at offset: Int) -> UInt8 {
        precondition(offset >= 0 && offset < length, "byte \(offset) outside the \(length)-byte file \(path)")
        checkLive()
        return base!.load(fromByteOffset: offset, as: UInt8.self)
    }

    func rawBuffer(offset: Int, length count: Int) -> UnsafeRawBufferPointer {
        precondition(offset >= 0 && count >= 0 && offset + count <= length)
        checkLive()
        guard let base, count > 0 else {
            return UnsafeRawBufferPointer(start: nil, count: 0)
        }
        return UnsafeRawBufferPointer(start: base.advanced(by: offset), count: count)
    }

    private func checkLive() {
        lock.lock()
        defer { lock.unlock() }
        precondition(!disposed, "the mapping of \(path) has been disposed")
    }

    private func unmap() {
        if let base, length > 0 {
            munmap(base, length)
        }
        base = nil
    }
}
