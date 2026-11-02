import Foundation
import TsukiCore
import TsukiEngine

/// One read-only view over several folders (package K25): the update folder over the base game, as the
/// PS4 mounts a patch over its app. A file is served by the first layer that has it; a directory
/// listing is the union. The layers are on disk, so `resolveFile` gives the path of the winning file
/// for the memory-mapped archives. Nothing is ever written.
public final class LayeredGameFiles: GameFiles {
    /// The layers, the update first.
    public let layers: [GameFiles]

    /// Creates the view; `layers` are tried in order (the update first, the base last).
    public init(_ layers: [GameFiles]) {
        precondition(!layers.isEmpty, "LayeredGameFiles needs at least one layer")
        self.layers = layers
    }

    public convenience init(_ layers: GameFiles...) {
        self.init(layers)
    }

    public var description: String {
        layers.reversed().map { $0.description }.joined(separator: " + ")
    }

    public func exists(_ path: String) -> Bool {
        layers.contains { $0.exists(path) }
    }

    public func length(of path: String) throws -> Int {
        try owner(path).length(of: path)
    }

    public func read(_ path: String, offset: Int, count: Int) throws -> ByteSpan {
        try owner(path).read(path, offset: offset, count: count)
    }

    public func listFiles(in directory: String) -> [String] {
        var names: [String: String] = [:]
        for layer in layers {
            for name in layer.listFiles(in: directory) where names[name.lowercased()] == nil {
                names[name.lowercased()] = name
            }
        }
        return names.values.sorted { $0.lowercased() < $1.lowercased() }
    }

    public func resolveFile(_ path: String) -> String? {
        for layer in layers where layer.exists(path) {
            return layer.resolveFile(path)
        }
        return nil
    }

    public func mapped(_ path: String) throws -> MappedFile {
        try owner(path).mapped(path)
    }

    /// The layer that serves `path`, or nil when none has it.
    public func layerOf(_ path: String) -> GameFiles? {
        layers.first { $0.exists(path) }
    }

    private func owner(_ path: String) throws -> GameFiles {
        guard let layer = layerOf(path) else {
            throw TsukiError.io("\(path) is in none of \(description)")
        }
        return layer
    }
}
