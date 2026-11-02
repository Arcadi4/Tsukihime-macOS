import Foundation
import TsukiCore
import TsukiEngine

/// One node of the flowchart (a 64-byte record; the first nine `i32` are static, the rest are run-time state and zero in the file).
public struct FlowNode: Equatable, Sendable {
    /// Static column index (0..276).
    public let column: Int
    /// Row inside the column.
    public let slot: Int
    /// +0x00: positive = the RTST bit (scene_done unlocks the node), negative = a link marker to -scene, 0 = empty.
    public let scene: Int
    /// +0x04: connector kind, -1 none (index into the flow_line cells).
    public let connector: Int
    /// +0x08: choice edge flag id 564..1194 (edge_seen), -1 none.
    public let link: Int
    /// +0x0C: the scene id the replay starts (the _JUMP target).
    public let scriptScene: Int
    /// +0x10: cell index into the flow_phasetitle tables.
    public let chapterLabel: Int
    /// +0x14: thumbnail/ordering index (no reader found in the PS4 code).
    public let order: Int
    /// +0x18: GALLERY_PARTS_FC_TH child (scene - 1 for real nodes).
    public let thumbnail: Int
    /// +0x1C: ui_text id of the scene title, -1 none.
    public let titleUi: Int
    /// +0x20: ui_text id of the synopsis, -1 none.
    public let synopsisUi: Int

    public init(
        column: Int, slot: Int, scene: Int, connector: Int, link: Int, scriptScene: Int, chapterLabel: Int, order: Int,
        thumbnail: Int, titleUi: Int, synopsisUi: Int
    ) {
        self.column = column
        self.slot = slot
        self.scene = scene
        self.connector = connector
        self.link = link
        self.scriptScene = scriptScene
        self.chapterLabel = chapterLabel
        self.order = order
        self.thumbnail = thumbnail
        self.titleUi = titleUi
        self.synopsisUi = synopsisUi
    }
}

/// A flowchart column.
public struct FlowColumn: Equatable, Sendable {
    /// Column index (0..276).
    public let index: Int
    /// +0x04: chapter band 0..15 (the look-ahead of the column filter stops at a higher group).
    public let group: Int
    /// The nodes (the record's count at +0x08).
    public let nodes: [FlowNode]

    public init(index: Int, group: Int, nodes: [FlowNode]) {
        self.index = index
        self.group = group
        self.nodes = nodes
    }
}

/// A scene-transition edge: the flags set when the story goes from node `from` to node `to`.
public struct FlowEdge: Equatable, Sendable {
    /// Source node.
    public let from: Int
    /// Target node.
    public let to: Int
    /// Edge ids (564..1194) set in the global progress words (positive entries of fields 2..6).
    public let globalIds: [Int]
    /// Edge ids set in the playthrough words F600+ (positive entries of fields 7..11).
    public let playthroughIds: [Int]

    public init(from: Int, to: Int, globalIds: [Int], playthroughIds: [Int]) {
        self.from = from
        self.to = to
        self.globalIds = globalIds
        self.playthroughIds = playthroughIds
    }
}

/// One choice edge flag triple, as read: the three `i32` of the record.
public struct ChoiceFlag: Equatable, Sendable {
    public let a: Int
    public let b: Int
    public let c: Int

    public init(a: Int, b: Int, c: Int) {
        self.a = a
        self.b = b
        self.c = c
    }
}

/// The flowchart tables (docs/formats/gallery.md 5; knife's `flow_table.rs` `ROWS`, `EDGES`): 277 columns (RELRO 0x418770, 32 bytes)
/// with 1,286 nodes (text 0x18FC90..0x1A3E10, 64 bytes), 630 edges (text 0x2218D0, 0x30 bytes) and 83 choice edge flag triples (text
/// 0x2214E0). The knife cross-check (docs/research/knife_tables.md) found all 1,286 nodes equal in seven fields and in the two SYSMES
/// fields after the +1 rule (`DialogMessageTable.ps4SysmesId`), and 628 of knife's 629 edges. Port of the flowchart half of
/// `tsuki.misc_gallery_extras_flowchart.load`.
public struct FlowchartTables: Sendable {
    /// RELRO VA of the 277 column records.
    public static let columnVa: Int = 0x418770

    /// Number of columns.
    public static let columnCount: Int = 277

    /// Text VA of the 630 edge records.
    public static let edgeVa: Int = 0x2218D0

    /// Number of edge records.
    public static let edgeCount: Int = 630

    /// Text VA of the choice edge flag triples.
    public static let choiceFlagVa: Int = 0x2214E0

    /// Number of triples; choice ids 1..82 are valid, entry 0 is unused.
    public static let choiceFlagCount: Int = 83

    /// The 277 columns.
    public let columns: [FlowColumn]

    /// The 630 edge records in table order (the engine uses the first match).
    public let edges: [FlowEdge]

    /// The 83 choice edge flag triples by choice id (the three i32 of each record, as read).
    public let choiceFlags: [ChoiceFlag]

    public init(columns: [FlowColumn], edges: [FlowEdge], choiceFlags: [ChoiceFlag]) {
        self.columns = columns
        self.edges = edges
        self.choiceFlags = choiceFlags
    }

    /// All 1,286 nodes in column order.
    public var nodes: [FlowNode] { columns.flatMap(\.nodes) }

    /// Reads the tables.
    public static func read(_ reader: EbootReader) throws -> FlowchartTables {
        let layout = reader.layout
        let columnCount = max(0, layout.flowColumnCount)
        let edgeCount = max(0, layout.flowEdgeCount)
        let choiceCount = max(0, layout.choiceFlagCount)
        var columns: [FlowColumn] = []
        columns.reserveCapacity(columnCount)
        for c in 0..<columnCount {
            let va = layout.flowColumns + 32 * c
            let group = Int(try reader.i32(va + 4))
            let count = Int(try reader.i32(va + 8))
            let nodesVa = try GalleryTables.pointer(reader, va + 16)
            var nodes: [FlowNode] = []
            nodes.reserveCapacity(max(0, count))
            for j in 0..<max(0, count) {
                let nva = nodesVa + 64 * j
                var f = [Int](repeating: 0, count: 16)
                for k in 0..<16 {
                    f[k] = Int(try reader.i32(nva + 4 * k))
                }

                if f[9..<16].contains(where: { $0 != 0 }) {
                    throw TsukiError.format("flow node \(c)/\(j): run-time fields are not zero")
                }

                nodes.append(FlowNode(
                    column: c, slot: j, scene: f[0], connector: f[1], link: f[2], scriptScene: f[3], chapterLabel: f[4],
                    order: f[5], thumbnail: f[6], titleUi: f[7], synopsisUi: f[8]))
            }

            columns.append(FlowColumn(index: c, group: group, nodes: nodes))
        }

        var edges: [FlowEdge] = []
        edges.reserveCapacity(edgeCount)
        for i in 0..<edgeCount {
            let va = layout.flowEdges + 0x30 * i
            var f = [Int](repeating: 0, count: 12)
            for k in 0..<12 {
                f[k] = Int(try reader.i32(va + 4 * k))
            }

            edges.append(FlowEdge(
                from: f[0], to: f[1], globalIds: f[2..<7].filter { $0 > 0 }, playthroughIds: f[7..<12].filter { $0 > 0 }))
        }

        var choice: [ChoiceFlag] = []
        choice.reserveCapacity(choiceCount)
        for i in 0..<choiceCount {
            let va = layout.choiceFlags + 12 * i
            choice.append(ChoiceFlag(a: Int(try reader.i32(va)), b: Int(try reader.i32(va + 4)), c: Int(try reader.i32(va + 8))))
        }

        return FlowchartTables(columns: columns, edges: edges, choiceFlags: choice)
    }
}
