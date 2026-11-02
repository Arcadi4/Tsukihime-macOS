import Foundation
import TsukiCore
import TsukiEngine

/// Every table K1b reads from the eboot (docs/research/knife_tables.md), each built on first use over one `EbootReader` and shared
/// afterwards. All tables are immutable once built, so one instance may serve several threads. The cell tables of the UI
/// (`UiCellTables`) are static readers and are not repeated here.
public final class EngineTables {
    /// The parsed eboot the tables are read from.
    public let reader: EbootReader

    private let hazeTable: LazyValue<Result<HazeTable, Error>>
    private let sceneNodeTable: LazyValue<Result<SceneNodeTable, Error>>
    private let motionLoopTable: LazyValue<Result<MotionLoopTable, Error>>
    private let jumpClearTable: LazyValue<Result<JumpClearTable, Error>>
    private let flowKeepTable: LazyValue<Result<FlowKeepLists, Error>>
    private let historyKeepTable: LazyValue<Result<FlowKeepLists, Error>>
    private let fclnLineTable: LazyValue<Result<FclnLineTable, Error>>
    private let fclnNoteTable: LazyValue<Result<[FclnNote], Error>>
    private let voiceTable: LazyValue<Result<VoiceSpeakerTable, Error>>
    private let testSeTable: LazyValue<Result<[String], Error>>
    private let dialogTable: LazyValue<Result<DialogMessageTable, Error>>
    private let windowTable: LazyValue<Result<MessageWindowTable, Error>>
    private let clipRadiiTable: LazyValue<Result<[Float], Error>>
    private let textColourTable: LazyValue<Result<[TextColour], Error>>
    private let configPageTable: LazyValue<Result<[ConfigPage], Error>>
    private let motionMaskTable: LazyValue<Result<MotionFieldMasks, Error>>
    private let galleryTable: LazyValue<Result<GalleryTables, Error>>
    private let flowchartTable: LazyValue<Result<FlowchartTables, Error>>

    /// Creates the set over a parsed eboot.
    public init(_ reader: EbootReader) {
        self.reader = reader
        hazeTable = LazyValue { Result { try HazeTable.read(reader) } }
        sceneNodeTable = LazyValue { Result { try SceneNodeTable.read(reader) } }
        motionLoopTable = LazyValue { Result { try MotionLoopTable.read(reader) } }
        jumpClearTable = LazyValue { Result { try JumpClearTable.read(reader) } }
        flowKeepTable = LazyValue { Result { try FlowKeepLists.read(reader) } }
        historyKeepTable = LazyValue { Result { try FlowKeepLists.read(reader, history: true) } }
        fclnLineTable = LazyValue { Result { try FclnLineTable.read(reader) } }
        fclnNoteTable = LazyValue { Result { try FclnNoteTable.read(reader) } }
        voiceTable = LazyValue { Result { try VoiceSpeakerTable.read(reader) } }
        testSeTable = LazyValue { Result { try TestSeNames.read(reader) } }
        dialogTable = LazyValue { Result { try DialogMessageTable.read(reader) } }
        windowTable = LazyValue { Result { try MessageWindowTable.read(reader) } }
        clipRadiiTable = LazyValue { Result { try SoftClipRadii.read(reader) } }
        textColourTable = LazyValue { Result { try TextColourTable.read(reader) } }
        configPageTable = LazyValue { Result { try ConfigPageTable.read(reader) } }
        motionMaskTable = LazyValue { Result { try MotionFieldMasks.read(reader) } }
        galleryTable = LazyValue { Result { try GalleryTables.read(reader) } }
        flowchartTable = LazyValue { Result { try FlowchartTables.read(reader) } }
    }

    /// The STRA haze parameters (558 entries).
    public var haze: HazeTable { get throws { try hazeTable.value.get() } }

    /// Flowchart node per scene (527).
    public var sceneNodes: SceneNodeTable { get throws { try sceneNodeTable.value.get() } }

    /// STMA loop points (2,027 looping motions; the first call interprets 24,192 calls of VA 0xC1C70, about 0.1 s).
    public var motionLoops: MotionLoopTable { get throws { try motionLoopTable.value.get() } }

    /// The F words the flowchart jump zeroes by column.
    public var jumpClears: JumpClearTable { get throws { try jumpClearTable.value.get() } }

    /// The F-word lists kept through a flowchart jump.
    public var flowKeep: FlowKeepLists { get throws { try flowKeepTable.value.get() } }

    /// The same lists as saved in a history record.
    public var historyKeep: FlowKeepLists { get throws { try historyKeepTable.value.get() } }

    /// The 30 focus-line effects.
    public var fclnLines: FclnLineTable { get throws { try fclnLineTable.value.get() } }

    /// The 3 falling-note kinds of FCLN effects 1..3.
    public var fclnNotes: [FclnNote] { get throws { try fclnNoteTable.value.get() } }

    /// Voice speakers, speaker row bits and voice row words.
    public var voices: VoiceSpeakerTable { get throws { try voiceTable.value.get() } }

    /// The 14 config SE test names.
    public var testSes: [String] { get throws { try testSeTable.value.get() } }

    /// The confirm-dialog / help message ids.
    public var dialogs: DialogMessageTable { get throws { try dialogTable.value.get() } }

    /// The message window types and offsets.
    public var windows: MessageWindowTable { get throws { try windowTable.value.get() } }

    /// The six soft-clip radii.
    public var clipRadii: [Float] { get throws { try clipRadiiTable.value.get() } }

    /// The five `@c1..@c5` fill colours.
    public var textColours: [TextColour] { get throws { try textColourTable.value.get() } }

    /// The two config pages with control positions.
    public var configPages: [ConfigPage] { get throws { try configPageTable.value.get() } }

    /// The STMA field masks.
    public var motionMasks: MotionFieldMasks { get throws { try motionMaskTable.value.get() } }

    /// The CG gallery, music room and ending list.
    public var gallery: GalleryTables { get throws { try galleryTable.value.get() } }

    /// The flowchart columns, nodes, edges and choice flags.
    public var flowchart: FlowchartTables { get throws { try flowchartTable.value.get() } }
}
