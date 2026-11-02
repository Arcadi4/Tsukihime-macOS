import Foundation
import TsukiCore
import TsukiEngine

/// The `_STRA` heat-haze parameters: 558 entries of 10 floats, indexed by the STRA id (entry 0 is the all-zero filler) in the text
/// segment at VA 0x219910 (accessor 0xB3630: ids 1..0x22D). knife keeps the same table as `exe.rs` `ExeTables::haze`; 16 of the 558
/// entries were retuned for the PS4. Port of `tsuki.engine_tables.read_haze`.
///
/// Field use (knife `stage.rs` `Haze::params`): [0] / [3] x and y scale, [2] / [5] amplitude factors, [6] amplitude, [7] period term,
/// [9] fade-in time in ms. The meaning on the PS4 is [H]: the engine advances the haze phase, but its draw was not traced
/// (layers.md 4.3).
public struct HazeTable: Sendable {
    /// Text VA of entry 0.
    public static let va: Int = 0x219910

    /// The highest STRA id that has an entry.
    public static let maxId: Int = 557

    /// Floats per entry.
    public static let floatsPerEntry: Int = 10

    private let values: [Float]

    public init(values: [Float]) {
        self.values = values
    }

    /// Number of entries, including entry 0.
    public var count: Int { values.count / Self.floatsPerEntry }

    /// The highest STRA id that has an entry (`count` - 1).
    public var lastId: Int { count - 1 }

    /// Reads the table.
    public static func read(_ reader: EbootReader) throws -> HazeTable {
        let entries = reader.layout.hazeEntries
        let raw = try reader.read(reader.layout.haze, 4 * floatsPerEntry * entries)
        var values = [Float](repeating: 0, count: floatsPerEntry * entries)
        for k in 0..<values.count {
            values[k] = raw.f32(4 * k)
        }

        return HazeTable(values: values)
    }

    /// The raw entry `index` (0..557), whatever its content.
    public func raw(_ index: Int) throws -> [Float] {
        guard index >= 0, index <= lastId else {
            throw TsukiError.bounds("haze entry \(index) outside 0...\(lastId)")
        }

        let start = index * Self.floatsPerEntry
        return Array(values[start..<start + Self.floatsPerEntry])
    }

    /// The entry of a STRA id; ids outside 1..557 have none (the engine's accessor returns NULL).
    public func entry(_ straId: Int) -> [Float]? {
        guard straId >= 1, straId <= lastId else { return nil }
        let start = straId * Self.floatsPerEntry
        return Array(values[start..<start + Self.floatsPerEntry])
    }
}

/// The flowchart node (RTST bit) of each scene, `i32[527]` at text VA 0x228EF0, indexed by script index - 1 (knife
/// `save_tables.rs` `SCENE_NODE`; -1 = no node). The first script (scene 110) has none. Port of `tsuki.engine_tables.read_scene_node`.
public struct SceneNodeTable: Sendable {
    /// Text VA.
    public static let va: Int = 0x228EF0

    /// Number of entries.
    public static let count: Int = 527

    /// The nodes by script index - 1.
    public let nodes: [Int]

    public init(nodes: [Int]) {
        self.nodes = nodes
    }

    /// Reads the table.
    public static func read(_ reader: EbootReader) throws -> SceneNodeTable {
        let count = reader.layout.sceneNodeCount
        let raw = try reader.read(reader.layout.sceneNodes, 4 * count)
        var nodes = [Int](repeating: 0, count: count)
        for k in 0..<count {
            nodes[k] = Int(raw.i32(4 * k))
        }

        return SceneNodeTable(nodes: nodes)
    }

    /// The node of the script with allscr index `scriptIndex` (0-based), -1 when it has none (index 0 or out of range).
    public func nodeOfScriptIndex(_ scriptIndex: Int) -> Int {
        let k = scriptIndex - 1
        return k >= 0 && k < nodes.count ? nodes[k] : -1
    }
}
