import Foundation
import TsukiCore
import TsukiData
import TsukiEngine

/// Applies the `_STEC` / `_SNX2` / `_SNX3` grade of a texture key to decoded RGBA pixels. Stateless and thread-safe.
public final class TileGrader: @unchecked Sendable {
    /// The tables.
    public let tables: StecTables

    public init(tables: StecTables) {
        self.tables = tables
    }

    /// Reads the tables from the eboot and wraps them.
    public static func fromEboot(_ eboot: EbootReader) throws -> TileGrader {
        TileGrader(tables: try StecTables.read(eboot))
    }

    /// True when the texture of `key` is a graded picture tile (`kind == .pictureTile`, `d != 0`).
    public static func isGraded(_ key: TextureRef) -> Bool {
        key.kind == .pictureTile && key.d != 0
    }

    /// Grades the pixels of a tile built for `key` in place; keys without a grade are left alone.
    public func apply(_ key: TextureRef, _ rgba: inout [UInt8]) {
        if Self.isGraded(key) {
            StecKernel.apply(&rgba, GradeKeys.resolve(Int(key.d)), tables)
        }
    }

    /// Grades the pixels of a tile built for `key` in place via buffer pointer.
    public func apply(_ key: TextureRef, _ rgba: UnsafeMutableBufferPointer<UInt8>) {
        if Self.isGraded(key) {
            StecKernel.apply(rgba, GradeKeys.resolve(Int(key.d)), tables)
        }
    }
}
