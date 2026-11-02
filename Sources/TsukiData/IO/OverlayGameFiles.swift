import Foundation
import TsukiCore
import TsukiEngine

/// A view over another `GameFiles` with some files replaced by in-memory bytes or hidden. It never
/// writes anything. The build-check tests use it to present "the real folder with one byte of eboot.bin
/// flipped" or "the real folder without bgm.hed" (ROADMAP M0 acceptance 2).
public final class OverlayGameFiles: GameFiles {
    private let inner: GameFiles
    private var replaced: [String: [UInt8]] = [:]
    private var hidden: Set<String> = []

    /// Creates an overlay with no changes.
    public init(_ inner: GameFiles) {
        self.inner = inner
    }

    public var description: String { inner.description + " (modified view)" }

    /// Makes `path` read as `bytes` (the array is not copied).
    @discardableResult
    public func replace(_ path: String, bytes: [UInt8]) -> OverlayGameFiles {
        let key = normalize(path)
        hidden.remove(key)
        replaced[key] = bytes
        return self
    }

    /// Copies `path` into memory with the byte at `position` XOR `mask`.
    @discardableResult
    public func flipByte(_ path: String, position: Int, mask: UInt8 = 0x01) throws -> OverlayGameFiles {
        var data = try inner.readAll(path).toArray()
        guard position >= 0, position < data.count else {
            throw TsukiError.bounds("byte \(position) is outside the \(data.count)-byte \(path)")
        }
        data[position] ^= mask
        return replace(path, bytes: data)
    }

    /// Makes `path` look missing.
    @discardableResult
    public func hide(_ path: String) -> OverlayGameFiles {
        let key = normalize(path)
        replaced.removeValue(forKey: key)
        hidden.insert(key)
        return self
    }

    public func exists(_ path: String) -> Bool {
        let key = normalize(path)
        return replaced[key] != nil || (!hidden.contains(key) && inner.exists(path))
    }

    public func length(of path: String) throws -> Int {
        let key = normalize(path)
        if let data = replaced[key] { return data.count }
        if hidden.contains(key) { throw missing(path) }
        return try inner.length(of: path)
    }

    public func read(_ path: String, offset: Int, count: Int) throws -> ByteSpan {
        let key = normalize(path)
        if let data = replaced[key] {
            guard offset >= 0, count >= 0 else {
                throw TsukiError.bounds("read [\(offset), \(offset + count)) outside the \(data.count)-byte \(path)")
            }
            guard offset < data.count else { return ByteSpan() }
            return ByteSpan(data, offset: offset, count: min(count, data.count - offset))
        }
        if hidden.contains(key) { throw missing(path) }
        return try inner.read(path, offset: offset, count: count)
    }

    public func listFiles(in directory: String) -> [String] {
        let dir = normalize(directory)
        var names: [String: String] = [:]
        for name in inner.listFiles(in: directory) where !hidden.contains(join(dir, name)) {
            if names[name.lowercased()] == nil { names[name.lowercased()] = name }
        }
        for key in replaced.keys {
            let slash = key.lastIndex(of: "/")
            let parent = slash.map { String(key[..<$0]) } ?? ""
            guard parent.lowercased() == dir.lowercased() else { continue }
            let name = slash.map { String(key[key.index(after: $0)...]) } ?? key
            if names[name.lowercased()] == nil { names[name.lowercased()] = name }
        }
        return names.values.sorted { $0.lowercased() < $1.lowercased() }
    }

    /// A replaced file lives in memory and has no path; a hidden one none either.
    public func resolveFile(_ path: String) -> String? {
        let key = normalize(path)
        return replaced[key] != nil || hidden.contains(key) ? nil : inner.resolveFile(path)
    }

    public func mapped(_ path: String) throws -> MappedFile {
        let key = normalize(path)
        if replaced[key] != nil || hidden.contains(key) {
            throw TsukiError.io("\(path) has no mapping in this view (in-memory or hidden)")
        }
        return try inner.mapped(path)
    }

    private func join(_ directory: String, _ name: String) -> String {
        directory.isEmpty ? name : directory + "/" + name
    }

    private func missing(_ path: String) -> TsukiError {
        TsukiError.io("\(path) is not part of this view")
    }

    /// `path` with `\` as `/` and no leading or trailing separator.
    private func normalize(_ path: String) -> String {
        var result = Substring(path.replacingOccurrences(of: "\\", with: "/"))
        while result.first == "/" { result.removeFirst() }
        while result.last == "/" { result.removeLast() }
        return String(result)
    }
}
