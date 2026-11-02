import Foundation
import TsukiCore
import TsukiEngine

/// The scene-id table: the scene id of every allscr script, an i16 per script at text VA 0x216130
/// (docs/formats/script.md 2.5). `_JUMP(n)` and the title menu address scripts by scene id; the
/// engine maps an id to a script index by linear search (VA 0x792D0 / 0x79320).
public struct SceneTable {
    /// Scripts in the retail data.
    public static let retailCount = 549

    /// The scene id of every script, by script index.
    public let ids: [Int16]

    private init(ids: [Int16]) {
        self.ids = ids
    }

    /// Number of scripts.
    public var count: Int { ids.count }

    /// Reads `count` ids from the eboot (the layout's scene count by default).
    public static func read(_ eboot: EbootReader, count: Int? = nil) throws -> SceneTable {
        let n = count ?? eboot.layout.sceneCount
        guard n >= 0 else {
            throw TsukiError.bounds("scene count \(n) is negative")
        }
        let raw = try eboot.read(eboot.layout.sceneIds, 2 * n)
        var ids = [Int16](repeating: 0, count: n)
        for i in 0..<n {
            ids[i] = raw.i16(2 * i)
        }
        return SceneTable(ids: ids)
    }

    /// Builds a table from ids (tests).
    public static func fromIds(_ ids: [Int]) throws -> SceneTable {
        var values: [Int16] = []
        values.reserveCapacity(ids.count)
        for id in ids {
            guard let value = Int16(exactly: id) else {
                throw TsukiError.bounds("scene id \(id) does not fit an i16")
            }
            values.append(value)
        }
        return SceneTable(ids: values)
    }

    /// The scene id of script `index`.
    public func sceneId(_ index: Int) -> Int {
        Int(ids[index])
    }

    /// The script index of a scene id: the first table entry that holds it (the engine's linear
    /// search), or nil.
    public func indexOf(_ sceneId: Int) -> Int? {
        for (index, id) in ids.enumerated() where Int(id) == sceneId {
            return index
        }
        return nil
    }

    /// True when no scene id occurs twice (the retail table: all 549 are distinct).
    public func idsAreUnique() -> Bool {
        Set(ids).count == ids.count
    }
}
