import Foundation
import TsukiCore
import TsukiEngine

/// Read-only access to one game folder, addressed by relative path with `/` separators. The build
/// check and the data decoders work through this view, so tests can present a synthetic folder
/// without touching the disk. Lookups ignore case.
public protocol GameFiles: AnyObject {
    /// A name for messages: the folder path, or a description of a synthetic view.
    var description: String { get }

    func exists(_ path: String) -> Bool

    /// Length in bytes.
    func length(of path: String) throws -> Int

    /// Up to `count` bytes at `offset`; fewer only at the end of the file.
    func read(_ path: String, offset: Int, count: Int) throws -> ByteSpan

    /// Whole file contents (never call this for a multi-gigabyte archive).
    func readAll(_ path: String) throws -> ByteSpan

    /// Names (not paths) of files directly inside `directory`, sorted.
    func listFiles(in directory: String) -> [String]

    /// Path on disk when the view is backed by real files.
    func resolveFile(_ path: String) -> String?

    /// A memory mapping of the file, for archives.
    func mapped(_ path: String) throws -> MappedFile
}

extension GameFiles {
    public func readAll(_ path: String) throws -> ByteSpan {
        let size = try length(of: path)
        let span = try read(path, offset: 0, count: size)
        guard span.count == size else {
            throw TsukiError.io("short read of \(path): \(span.count) of \(size) bytes")
        }
        return span
    }

    public func readRange(_ path: String, offset: Int, count: Int) throws -> [UInt8] {
        let span = try read(path, offset: offset, count: count)
        guard span.count == count else {
            throw TsukiError.io("short read of \(path) at \(offset): \(span.count) of \(count) bytes")
        }
        return span.toArray()
    }
}

/// Normalises a game-relative path: `/` separators, no leading slash.
public func normalizeGamePath(_ path: String) -> String {
    var result = path.replacingOccurrences(of: "\\", with: "/")
    while result.hasPrefix("/") { result.removeFirst() }
    return result
}

/// A real directory on disk.
public final class DirectoryGameFiles: GameFiles {
    public let root: String
    private var listings: [String: [String: String]] = [:]
    private var mappings: [String: MappedFile] = [:]
    private let lock = NSLock()

    public init(root: String) {
        self.root = (root as NSString).standardizingPath
    }

    public var description: String { root }

    private func diskPath(_ path: String) -> String {
        root + "/" + normalizeGamePath(path)
    }

    /// Finds the on-disk name of a file, ignoring case, by listing its directory once.
    private func actualPath(_ path: String) -> String? {
        let normalized = normalizeGamePath(path)
        let directory = (normalized as NSString).deletingLastPathComponent
        let name = (normalized as NSString).lastPathComponent

        lock.lock()
        let cached = listings[directory]
        lock.unlock()
        if let cached, let found = cached[name.lowercased()] {
            return directory.isEmpty ? found : directory + "/" + found
        }

        let directoryPath = directory.isEmpty ? root : root + "/" + directory
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directoryPath) else {
            return nil
        }
        var map: [String: String] = [:]
        map.reserveCapacity(entries.count)
        for entry in entries {
            map[entry.lowercased(), default: entry] = entry
        }
        lock.lock()
        listings[directory] = map
        lock.unlock()

        guard let actual = map[name.lowercased()] else { return nil }
        return directory.isEmpty ? actual : directory + "/" + actual
    }

    public func exists(_ path: String) -> Bool {
        guard let actual = actualPath(path) else { return false }
        return FileManager.default.fileExists(atPath: root + "/" + actual)
    }

    public func length(of path: String) throws -> Int {
        guard let actual = actualPath(path) else {
            throw TsukiError.io("\(path) is not in \(root)")
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: root + "/" + actual)
        return (attributes[.size] as? NSNumber)?.intValue ?? 0
    }

    public func read(_ path: String, offset: Int, count requested: Int) throws -> ByteSpan {
        guard let actual = actualPath(path) else {
            throw TsukiError.io("\(path) is not in \(root)")
        }
        let size = try length(of: path)
        guard offset >= 0, requested >= 0, offset <= size else {
            throw TsukiError.bounds("read [\(offset), \(offset + requested)) outside the \(size)-byte file \(path)")
        }
        let count = min(requested, size - offset)
        let full = root + "/" + actual
        if count <= 0 { return ByteSpan() }

        if count <= 1 << 16 {
            let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: full))
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(offset))
            let data = try handle.read(upToCount: count) ?? Data()
            return ByteSpan([UInt8](data))
        }

        let mapped = try self.mapped(path)
        return try mapped.span(offset: offset, length: count)
    }

    public func listFiles(in directory: String) -> [String] {
        let normalized = normalizeGamePath(directory)
        let directoryPath = normalized.isEmpty ? root : root + "/" + normalized
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directoryPath) else {
            return []
        }
        return entries
            .filter { !$0.hasPrefix(".") }
            .filter { entry in
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: directoryPath + "/" + entry, isDirectory: &isDirectory)
                return !isDirectory.boolValue
            }
            .sorted()
    }

    public func resolveFile(_ path: String) -> String? {
        guard let actual = actualPath(path) else { return nil }
        let full = root + "/" + actual
        return FileManager.default.fileExists(atPath: full) ? full : nil
    }

    public func mapped(_ path: String) throws -> MappedFile {
        guard let full = resolveFile(path) else {
            throw TsukiError.io("\(path) is not in \(root)")
        }
        let key = normalizeGamePath(path).lowercased()
        lock.lock()
        defer { lock.unlock() }
        if let existing = mappings[key] { return existing }
        let file = try MappedFile(path: full)
        mappings[key] = file
        return file
    }
}
