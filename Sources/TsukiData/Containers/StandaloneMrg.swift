import Foundation
import TsukiCore
import TsukiEngine

/// A standalone mrgd00 file: `allscr.mrg`, `script_text.mrg`, `ft_*.mrg`, `se_nam.mrg`
/// (docs/formats/containers.md 8), memory-mapped.
public final class StandaloneMrg {
    private let file: MappedFile

    /// The container over the whole file.
    public let container: MzpContainer

    private init(file: MappedFile, container: MzpContainer) {
        self.file = file
        self.container = container
    }

    /// File length in bytes.
    public var length: Int { file.length }

    /// Opens and parses a standalone file.
    ///
    /// Throws `TsukiError.format` when the file is not an mrgd00 container and `TsukiError.io` when it
    /// cannot be mapped.
    public static func open(_ path: String) throws -> StandaloneMrg {
        let file = try MappedFile(path: path)
        do {
            guard file.length <= Int(Int32.max) else {
                throw TsukiError.format("\(path) is \(file.length) bytes; standalone files are below 2 GiB")
            }
            return StandaloneMrg(file: file, container: try MzpContainer.parse(file.span()))
        } catch {
            file.dispose()
            throw error
        }
    }

    /// Frees the mapping. Views obtained earlier become invalid, as with any mapped buffer.
    public func dispose() {
        file.dispose()
    }
}
