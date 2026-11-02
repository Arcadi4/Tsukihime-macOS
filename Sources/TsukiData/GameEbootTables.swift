import Foundation
import TsukiCore
import TsukiEngine

/// The eboot-only tables of the user's copy (``EbootTables``, RR 3.2, FORMATS 5.4), read from `eboot.bin` on first use:
/// the image catalog and picture names, the movie table, the UI registration tables and `ui_text` (all of them in
/// ``catalog``), the scene ids, the layer motions and the glyph lookups. It is the shipping counterpart of
/// `GoldenEbootTables`; more tables are hung on ``reader`` by the packages that decode them (TsukiData/Eboot/Tables).
///
/// Every table is immutable after it is built, so one instance is shared between decode workers. Tables that cost
/// milliseconds (the 71,905 motion keyframes, the 17,423 glyph lookups) are built on first use.
public final class GameEbootTables: EbootTables {
    /// The parsed eboot.bin: address mapping, strict reads at a virtual address (A2).
    public let reader: EbootReader

    /// The image table, picture names, NAM search, movie table, UI texture tables and UI text (A2).
    public let catalog: GameCatalog

    /// The engine tables read from the eboot.
    public let engineTables: EngineTables

    private let scenesLazy: LazyValue<Result<SceneTable, Error>>
    private let motionsLazy: LazyValue<Result<TsukiData.MotionTables, Error>>
    private let fontDataLazy: LazyValue<Result<EbootFontData, Error>>
    private let fontTablesLazy: LazyValue<Result<FontTables, Error>>

    private var stageMotions: TsukiEngine.MotionTables?
    private var stagePictures: PictureCatalog?
    private var stageHaze: TsukiEngine.HazeTable?
    private var gameFlowInstance: GameFlowTables?
    private var uiTablesInstance: UiTables?
    private var galleryTablesInstance: UiGalleryTables?
    private var effectTablesInstance: EffectTables?
    private let lock = NSLock()

    /// Creates the tables over a parsed eboot and the catalog built from it.
    public init(_ reader: EbootReader, _ catalog: GameCatalog) {
        self.reader = reader
        self.catalog = catalog
        self.engineTables = EngineTables(reader)
        self.scenesLazy = LazyValue(Result { try SceneTable.read(reader) })
        self.motionsLazy = LazyValue(Result { try TsukiData.MotionTables.read(reader) })
        self.fontDataLazy = LazyValue(Result { try EbootFontData.read(reader) })
        self.fontTablesLazy = LazyValue(Result {
            let data = try EbootFontData.read(reader)
            return data.toEngineTables()
        })
    }

    /// Script number k to scene id: 549 entries (docs/formats/script.md 2.5).
    public var sceneIds: SceneTable { get throws { try scenesLazy.value.get() } }

    /// The movie table, one record per movie file: 134 records (docs/formats/archives_ui_movies.md 9.2).
    public var movies: [MovieRecord] { catalog.movies }

    /// The layer motions of `_STMA` / `_SGMA`: 24,192 motions and 71,905 keyframes (docs/formats/layers.md).
    public var motionsData: TsukiData.MotionTables { get throws { try motionsLazy.value.get() } }

    /// The glyph lookup and rectangle tables as stored: 17,423 lookup entries (docs/formats/fonts.md 5).
    public var fontData: EbootFontData { get throws { try fontDataLazy.value.get() } }

    /// The same tables in the form the text layout reads (``TsukiEngine/Text``).
    public var fontTables: FontTables { get throws { try fontTablesLazy.value.get() } }

    /// The UI strings, 5 languages x 1,499 (RR 3.2).
    public var uiText: UiTextTable { get throws { try catalog.uiText } }

    // MARK: - EngineTables Accessors

    /// The STRA haze parameters (558 entries).
    public var hazeTable: HazeTable { get throws { try engineTables.haze } }

    /// Flowchart node per scene (527).
    public var sceneNodes: SceneNodeTable { get throws { try engineTables.sceneNodes } }

    /// STMA loop points (2,027 looping motions).
    public var motionLoops: MotionLoopTable { get throws { try engineTables.motionLoops } }

    /// The F words the flowchart jump zeroes by column.
    public var jumpClears: JumpClearTable { get throws { try engineTables.jumpClears } }

    /// The F-word lists kept through a flowchart jump.
    public var flowKeep: FlowKeepLists { get throws { try engineTables.flowKeep } }

    /// The same lists as saved in a history record.
    public var historyKeep: FlowKeepLists { get throws { try engineTables.historyKeep } }

    /// The 30 focus-line effects.
    public var fclnLines: FclnLineTable { get throws { try engineTables.fclnLines } }

    /// The 3 falling-note kinds of FCLN effects 1..3.
    public var fclnNotes: [FclnNote] { get throws { try engineTables.fclnNotes } }

    /// Voice speakers, speaker row bits and voice row words.
    public var voices: VoiceSpeakerTable { get throws { try engineTables.voices } }

    /// The 14 config SE test names.
    public var testSes: [String] { get throws { try engineTables.testSes } }

    /// The confirm-dialog / help message ids.
    public var dialogs: DialogMessageTable { get throws { try engineTables.dialogs } }

    /// The message window types and offsets.
    public var windows: MessageWindowTable { get throws { try engineTables.windows } }

    /// The six soft-clip radii.
    public var clipRadiiTable: [Float] { get throws { try engineTables.clipRadii } }

    /// The five `@c1..@c5` fill colours.
    public var textColours: [TextColour] { get throws { try engineTables.textColours } }

    /// The two config pages with control positions.
    public var configPages: [ConfigPage] { get throws { try engineTables.configPages } }

    /// The STMA field masks.
    public var motionMasks: MotionFieldMasks { get throws { try engineTables.motionMasks } }

    /// The CG gallery, music room and ending list.
    public var galleryTable: GalleryTables { get throws { try engineTables.gallery } }

    /// The flowchart columns, nodes, edges and choice flags.
    public var flowchart: FlowchartTables { get throws { try engineTables.flowchart } }

    // MARK: - EbootTables Protocol

    public var gameFonts: FontTables {
        do {
            return try fontTablesLazy.value.get()
        } catch {
            fatalError("GameEbootTables.gameFonts failed: \(error)")
        }
    }

    public var gameFlow: GameFlowTables {
        lock.lock()
        defer { lock.unlock() }
        if let existing = gameFlowInstance { return existing }
        let scenes = (try? sceneIds) ?? (try! SceneTable.fromIds([]))
        let made = GameFlowTablesImpl(scenes: scenes, tables: engineTables, catalog: catalog)
        gameFlowInstance = made
        return made
    }

    public var motions: TsukiEngine.MotionTables {
        lock.lock()
        defer { lock.unlock() }
        if let existing = stageMotions { return existing }
        let made = buildStageMotions()
        stageMotions = made
        return made
    }

    public var pictures: PictureCatalog {
        lock.lock()
        defer { lock.unlock() }
        if let existing = stagePictures { return existing }
        let made = GamePictureCatalog(catalog: catalog)
        stagePictures = made
        return made
    }

    public var haze: TsukiEngine.HazeTable {
        lock.lock()
        defer { lock.unlock() }
        if let existing = stageHaze { return existing }
        let table = (try? engineTables.haze) ?? HazeTable(values: [])
        let made = GameHazeTable(table)
        stageHaze = made
        return made
    }

    public var clipRadii: [Float]? {
        try? engineTables.clipRadii
    }

    public var ui: UiTables {
        lock.lock()
        defer { lock.unlock() }
        if let existing = uiTablesInstance { return existing }
        let made = UiTablesView(self)
        uiTablesInstance = made
        return made
    }

    public var gallery: UiGalleryTables? {
        lock.lock()
        defer { lock.unlock() }
        if let existing = galleryTablesInstance { return existing }
        let made = UiGalleryView(self)
        galleryTablesInstance = made
        return made
    }

    public var effects: EffectTables? {
        lock.lock()
        defer { lock.unlock() }
        if let existing = effectTablesInstance { return existing }
        let made = try? GameEffectTables(engineTables)
        effectTablesInstance = made
        return made
    }

    private func buildStageMotions() -> TsukiEngine.MotionTables {
        do {
            let t = try motionsData
            let n = TsukiData.MotionTables.motionCount
            var duration = [Int](repeating: 0, count: n)
            var end = [Int](repeating: 0, count: n)
            var masks = [UInt64](repeating: 0, count: n)
            var loops = [Int](repeating: 0, count: n)
            let motionMasks = try engineTables.motionMasks
            let motionLoops = try engineTables.motionLoops
            for id in 1...n {
                duration[id - 1] = Int(try t.duration(id))
                end[id - 1] = try t.keyRange(id).end
                masks[id - 1] = motionMasks.mask(of: id)
                loops[id - 1] = motionLoops.loopPoint(id)
            }

            let keys = t.keyframeCount
            var times = [Int](repeating: 0, count: keys)
            var fields = [Int](repeating: 0, count: keys * MotionTable.fieldCount)
            for i in 0..<keys {
                let k = try t.keyframe(i)
                times[i] = Int(k.time)
                for f in 0..<MotionTable.fieldCount {
                    fields[i * MotionTable.fieldCount + f] = Int(k.fields[f])
                }
            }

            return ArrayMotionTables(duration: duration, end: end, times: times, fields: fields, masks: masks, loops: loops)
        } catch {
            fatalError("GameEbootTables.buildStageMotions failed: \(error)")
        }
    }
}

// MARK: - GameFlowTables Implementation

private final class GameFlowTablesImpl: GameFlowTables {
    private let scenes: SceneTable
    private let tables: EngineTables
    private let catalog: GameCatalog
    private var scriptOfId: [Int: Int] = [:]
    private let edgesLazy: LazyValue<[FlowEdgeRow]>
    private let nodesLazy: LazyValue<[FlowNodeRow]>
    private let clearsLazy: LazyValue<[(lastColumn: Int, word: Int)]>
    private let seenLazy: LazyValue<(byName: [String: Int], map: [Int: Int])>

    init(scenes: SceneTable, tables: EngineTables, catalog: GameCatalog) {
        self.scenes = scenes
        self.tables = tables
        self.catalog = catalog
        for k in 0..<scenes.count {
            let sid = Int(scenes.ids[k])
            if scriptOfId[sid] == nil {
                scriptOfId[sid] = k
            }
        }
        self.seenLazy = LazyValue {
            var byName: [String: Int] = [:]
            for i in 0..<catalog.pictureNames.count {
                let key = catalog.pictureNames[i].lowercased()
                if byName[key] == nil {
                    byName[key] = i
                }
            }
            var map: [Int: Int] = [:]
            if let gallery = try? tables.gallery {
                for e in gallery.seenMap {
                    if let id = byName[e.name.lowercased()] {
                        map[id] = e.seenIndex
                    }
                }
            }
            return (byName, map)
        }
        self.edgesLazy = LazyValue {
            (try? tables.flowchart.edges.map { e in
                FlowEdgeRow(from: e.from, to: e.to, globalIds: e.globalIds, playthroughIds: e.playthroughIds)
            }) ?? []
        }
        self.nodesLazy = LazyValue {
            guard let flow = try? tables.flowchart else { return [] }
            return flow.nodes.map { n in
                let grp = n.column >= 0 && n.column < flow.columns.count ? flow.columns[n.column].group : 0
                return FlowNodeRow(column: n.column, scene: n.scene, scriptScene: n.scriptScene, link: n.link, group: grp)
            }
        }
        self.clearsLazy = LazyValue {
            (try? tables.jumpClears.pairs.map { (lastColumn: $0.lastRow, word: $0.word) }) ?? []
        }
    }

    var sceneCount: Int { scenes.count }

    func sceneId(_ script: Int) -> Int {
        guard script >= 0 && script < scenes.count else { return 0 }
        return Int(scenes.ids[script])
    }

    func scriptOfSceneId(_ sceneId: Int) -> Int {
        scriptOfId[sceneId] ?? -1
    }

    func nodeOfScript(_ script: Int) -> Int {
        (try? tables.sceneNodes.nodeOfScriptIndex(script)) ?? -1
    }

    func pictureSeenIndex(_ pictureId: Int) -> Int {
        let entries = catalog.images.entries
        guard pictureId >= 0 && pictureId < entries.count else {
            return -1
        }

        let (byName, map) = seenLazy.value
        var pid = pictureId
        if entries[pid].isVariant {
            let name = catalog.pictureNames[pid]
            if name.count > 6, let b = byName[String(name.dropLast(6)).lowercased()] {
                pid = b
            } else {
                pid = -1
            }
        }

        if pid >= 0xA8D {
            pid = map[pid] ?? -1
        }

        return (pid >= 0 && pid <= 0xC7F) ? pid : -1
    }

    var edges: [FlowEdgeRow] { edgesLazy.value }

    var nodes: [FlowNodeRow] { nodesLazy.value }

    var jumpKeepWords: [Int] { (try? tables.flowKeep.words) ?? [] }

    var jumpKeepBytes: [Int] { (try? tables.flowKeep.bytes) ?? [] }

    var jumpKeepBits: [Int] { (try? tables.flowKeep.bits) ?? [] }

    var jumpClears: [(lastColumn: Int, word: Int)] { clearsLazy.value }
}

// MARK: - Stage Support

private final class GamePictureCatalog: PictureCatalog {
    private let infoArray: [PictureInfo]
    private let catalog: GameCatalog

    init(catalog: GameCatalog) {
        self.catalog = catalog
        self.infoArray = catalog.images.entries.map { e in
            PictureInfo(
                anchorX: e.anchorX,
                anchorY: e.anchorY,
                scaleClass: e.scaleClass,
                drawFlags: e.drawFlags,
                hasFace: e.name1 != nil
            )
        }
    }

    var count: Int { infoArray.count }

    func lookup(_ name: String) -> Int {
        (try? catalog.resolver.indexOf(name)) ?? -1
    }

    func name(_ pic: Int) -> String {
        pic >= 0 && pic < infoArray.count ? catalog.pictureNames[pic] : ""
    }

    func info(_ pic: Int) -> PictureInfo {
        guard pic >= 0 && pic < infoArray.count else {
            return PictureInfo(anchorX: 0, anchorY: 0, scaleClass: 0, drawFlags: 0, hasFace: false)
        }
        return infoArray[pic]
    }
}

private final class GameHazeTable: TsukiEngine.HazeTable {
    private let table: HazeTable

    init(_ table: HazeTable) {
        self.table = table
    }

    func tryGetEntry(_ straId: Int) -> [Float]? {
        table.entry(straId)
    }
}

// MARK: - UiTables Implementation

private final class UiTablesView: UiTables {
    private let owner: GameEbootTables
    private let engine: EngineTables
    private let saveTitles: [LazyValue<[SheetCell]>]
    private let phaseTitles: [LazyValue<[SheetCell]>]
    private let guideWords: [LazyValue<[SheetCell]>]
    private let voiceNames: [LazyValue<[SheetCell]>]
    private let guideIconsLazy: LazyValue<[SheetCell]>
    private let bannersLazy: LazyValue<[SheetCell]>
    private let bannerKeysLazy: LazyValue<[(x: Float, y: Float)]>
    private let facesLazy: LazyValue<[SheetCell]>
    private let configLazy: LazyValue<[UiConfigPage]>
    private let titleBackgroundLazy: LazyValue<[Int]>

    init(_ owner: GameEbootTables) {
        self.owner = owner
        self.engine = owner.engineTables
        let r = owner.reader
        self.saveTitles = [
            LazyValue { Self.convert((try? UiCellTables.readSaveTitleCells(r, english: false)) ?? []) },
            LazyValue { Self.convert((try? UiCellTables.readSaveTitleCells(r, english: true)) ?? []) }
        ]
        self.phaseTitles = [
            LazyValue { Self.convert((try? UiCellTables.readPhaseTitleCells(r, set: .ja)) ?? []) },
            LazyValue { Self.convert((try? UiCellTables.readPhaseTitleCells(r, set: .en)) ?? []) },
            LazyValue { Self.convert((try? UiCellTables.readPhaseTitleCells(r, set: .zh)) ?? []) }
        ]
        self.guideWords = (0..<5).map { lang in
            LazyValue { Self.convert((try? UiCellTables.readGuideWordCells(r, language: lang)) ?? []) }
        }
        self.voiceNames = [
            LazyValue { Self.convert((try? UiCellTables.readVoiceNameCells(r, english: false)) ?? []) },
            LazyValue { Self.convert((try? UiCellTables.readVoiceNameCells(r, english: true)) ?? []) }
        ]
        self.guideIconsLazy = LazyValue {
            Self.convert((try? UiCellTables.readGuideIconCells(r)) ?? [])
        }
        self.bannersLazy = LazyValue {
            Self.convert((try? UiCellTables.readBannerCells(r)) ?? [])
        }
        self.bannerKeysLazy = LazyValue {
            let keys = (try? UiCellTables.readBannerKeys(r)) ?? []
            return keys.map { (x: $0.x, y: $0.y) }
        }
        self.facesLazy = LazyValue {
            Self.convert((try? UiCellTables.readVoiceFaceCells(r)) ?? [])
        }
        self.configLazy = LazyValue {
            let pages = (try? ConfigPageTable.read(r)) ?? []
            return pages.map { p in
                UiConfigPage(
                    firstItem: p.firstItem,
                    lastItem: p.lastItem,
                    rows: p.rows.map { row in
                        UiConfigRow(
                            controls: row.controls.map { c in
                                UiConfigControl(item: c.item, kind: c.kind, x: c.x, y: c.y)
                            },
                            current: row.current,
                            maximum: row.maximum
                        )
                    }
                )
            }
        }
        self.titleBackgroundLazy = LazyValue {
            guard let raw = try? r.read(r.layout.titleBackground, 24) else { return [] }
            return (0..<6).map { Int(raw.i32(4 * $0)) }
        }
    }

    var fonts: FontTables {
        owner.gameFonts
    }

    func text(_ language: Language, _ id: Int) -> String {
        guard let uiText = try? owner.catalog.uiText else { return "" }
        let rows = uiText.rows(min(Int(language.rawValue), 4))
        return id > 0 && id < rows.count ? rows[id].text : ""
    }

    func saveTitleCells(_ language: Language) -> [SheetCell] {
        saveTitles[language == .en ? 1 : 0].value
    }

    func phaseTitleCells(_ language: Language) -> [SheetCell] {
        let index: Int
        switch language {
        case .ja: index = 0
        case .en: index = 1
        default: index = 2
        }
        return phaseTitles[index].value
    }

    var guideIconCells: [SheetCell] {
        guideIconsLazy.value
    }

    func guideWordCells(_ language: Language) -> [SheetCell] {
        guideWords[min(Int(language.rawValue), 4)].value
    }

    var bannerCells: [SheetCell] {
        bannersLazy.value
    }

    var bannerKeys: [(x: Float, y: Float)] {
        bannerKeysLazy.value
    }

    var voiceFaceCells: [SheetCell] {
        facesLazy.value
    }

    func voiceNameCells(_ language: Language) -> [SheetCell] {
        voiceNames[language == .en ? 1 : 0].value
    }

    var configPages: [UiConfigPage] {
        configLazy.value
    }

    var dialogMessages: [Int] {
        (try? engine.dialogs.ids) ?? []
    }

    var voiceRowWords: [Int] {
        (try? engine.voices.rowWords) ?? []
    }

    var testSeNames: [String] {
        (try? engine.testSes) ?? []
    }

    var titleBackgroundTable: [Int] {
        titleBackgroundLazy.value
    }

    func findPicture(_ name: String) -> (archive: Int, entry: Int)? {
        guard let id = try? owner.catalog.nameIndex.find(name) else { return nil }
        return (archive: Int(id.archive.rawValue), entry: id.index)
    }

    private static func convert(_ cells: [UiCell]) -> [SheetCell] {
        cells.map { SheetCell(x0: $0.a, y0: $0.b, x1: $0.c, y1: $0.d) }
    }
}

// MARK: - UiGalleryTables Implementation

private final class UiGalleryView: UiGalleryTables {
    private let owner: GameEbootTables
    private let groupsLazy: LazyValue<[GalleryGroupRow]>
    private let aliasesLazy: LazyValue<[GalleryAliasRow]>
    private let tracksLazy: LazyValue<[GalleryTrackRow]>
    private let endingsLazy: LazyValue<[GalleryEndingRow]>
    private let columnsLazy: LazyValue<[ChartColumnRow]>
    private let edgesLazy: LazyValue<[ChartEdgeRow]>
    private let titleCells: [LazyValue<[SheetCell]>]
    private let lineCellsLazy: LazyValue<[SheetCell]>
    private let pictureIndexLazy: LazyValue<[String: Int]>

    init(_ owner: GameEbootTables) {
        self.owner = owner
        let r = owner.reader
        self.groupsLazy = LazyValue {
            guard let gallery = try? owner.engineTables.gallery else { return [] }
            return gallery.groups.map { g in
                GalleryGroupRow(
                    category: g.category,
                    entries: g.entries.map { e in
                        GalleryCgRow(
                            name: e.name,
                            thumbnail: e.thumbnail,
                            x: e.x,
                            y: e.y,
                            width: e.width,
                            height: e.height,
                            flag: e.flag
                        )
                    }
                )
            }
        }
        self.aliasesLazy = LazyValue {
            guard let gallery = try? owner.engineTables.gallery else { return [] }
            return gallery.aliases.map { GalleryAliasRow(key: $0.key, aliases: $0.aliases) }
        }
        self.tracksLazy = LazyValue {
            guard let gallery = try? owner.engineTables.gallery else { return [] }
            return gallery.music.map { m in
                GalleryTrackRow(
                    bgm: m.bgm,
                    titleUi: m.titleUi,
                    vocalUi: m.vocalUi,
                    lyricsUi: m.lyricsUi,
                    composerUi: m.composerUi,
                    arrangerUi: m.arrangerUi,
                    lengthMs: m.lengthMs,
                    loopStart: m.loopStart,
                    loopEnd: m.loopEnd,
                    variants: m.variants
                )
            }
        }
        self.endingsLazy = LazyValue {
            guard let gallery = try? owner.engineTables.gallery else { return [] }
            return gallery.extras.map { x in
                GalleryEndingRow(
                    scriptScene: x.scriptScene,
                    flowScene: x.flowScene,
                    unlockA: x.unlockA,
                    unlockB: x.unlockB,
                    messageUi: x.messageUi
                )
            }
        }
        self.columnsLazy = LazyValue {
            guard let flowchart = try? owner.engineTables.flowchart else { return [] }
            return Self.readColumns(r, flow: flowchart)
        }
        self.edgesLazy = LazyValue {
            guard let flowchart = try? owner.engineTables.flowchart else { return [] }
            return flowchart.edges.map { ChartEdgeRow(from: $0.from, to: $0.to, globalIds: $0.globalIds, playthroughIds: $0.playthroughIds) }
        }
        self.titleCells = [
            LazyValue { Self.fromRects((try? UiCellTables.readFlowTitleCells(r, english: false)) ?? []) },
            LazyValue { Self.fromRects((try? UiCellTables.readFlowTitleCells(r, english: true)) ?? []) }
        ]
        self.lineCellsLazy = LazyValue {
            Self.fromRects((try? UiCellTables.readFlowLineCells(r)) ?? [])
        }
        self.pictureIndexLazy = LazyValue {
            var map: [String: Int] = [:]
            let names = owner.catalog.pictureNames
            for i in 0..<names.count {
                let key = names[i].lowercased()
                if map[key] == nil {
                    map[key] = i
                }
            }
            return map
        }
    }

    private var gallery: GalleryTables? {
        try? owner.engineTables.gallery
    }

    var cgGroups: [GalleryGroupRow] { groupsLazy.value }

    var cgAliases: [GalleryAliasRow] { aliasesLazy.value }

    var cgLanguageStrips: [String] { gallery?.special ?? [] }

    var cgCategoryScenes: [Int: [Int]] { gallery?.categoryFlags ?? [:] }

    var tracks: [GalleryTrackRow] { tracksLazy.value }

    var endings: [GalleryEndingRow] { endingsLazy.value }

    var chartColumns: [ChartColumnRow] { columnsLazy.value }

    var chartEdges: [ChartEdgeRow] { edgesLazy.value }

    func chartTitleCells(_ language: Language) -> [SheetCell] {
        titleCells[language == .en ? 1 : 0].value
    }

    var chartLineCells: [SheetCell] { lineCellsLazy.value }

    func pictureIndex(_ name: String) -> Int {
        var key = name.count > 32 ? String(name.prefix(32)) : name
        if let dot = key.firstIndex(of: ".") {
            key = String(key[..<dot])
        }
        return pictureIndexLazy.value[key.lowercased()] ?? -1
    }

    func pictureSeenIndex(_ pictureId: Int) -> Int {
        owner.gameFlow.pictureSeenIndex(pictureId)
    }

    private static func fromRects(_ cells: [UiCell]) -> [SheetCell] {
        cells.map { SheetCell(x0: $0.a, y0: $0.b, x1: $0.a + $0.c, y1: $0.b + $0.d) }
    }

    private static func readColumns(_ r: EbootReader, flow: FlowchartTables) -> [ChartColumnRow] {
        var columns: [ChartColumnRow] = []
        columns.reserveCapacity(flow.columns.count)
        for c in 0..<flow.columns.count {
            let col = flow.columns[c]
            guard let nodesVa = try? GalleryTables.pointer(r, FlowchartTables.columnVa + 32 * c + 16) else {
                continue
            }
            let after = nodesVa + 64 * col.nodes.count
            let overrunScene = (try? r.i32(after)).map { Int($0) } ?? 0
            let overrunLink = (try? r.i32(after + 8)).map { Int($0) } ?? 0
            columns.append(ChartColumnRow(
                group: col.group,
                nodes: col.nodes.map { n in
                    ChartNodeRow(
                        scene: n.scene,
                        connector: n.connector,
                        link: n.link,
                        scriptScene: n.scriptScene,
                        chapterLabel: n.chapterLabel,
                        mosaic: n.order,
                        preview: n.thumbnail,
                        titleUi: n.titleUi,
                        synopsisUi: n.synopsisUi
                    )
                },
                overrunScene: overrunScene,
                overrunLink: overrunLink
            ))
        }
        return columns
    }
}

// MARK: - EffectTables Implementation

private final class GameEffectTables: EffectTables {
    private let notes: [FocusNote]
    private let fclnLines: FclnLineTable

    init(_ tables: EngineTables) throws {
        self.fclnLines = try tables.fclnLines
        self.notes = try tables.fclnNotes.map { n in
            FocusNote(
                frames: n.frames,
                sequence: n.sequence,
                width: n.width,
                height: n.height,
                step: n.step,
                vx: n.vx,
                vy: n.vy,
                jitterX: n.jitterX,
                jitterY: n.jitterY,
                accel: n.accel,
                floor: n.floor
            )
        }
    }

    var focusEffects: Int {
        FclnLineTable.effects
    }

    func focusKey(_ effect: Int, _ key: Int) -> FocusKey {
        guard let k = try? fclnLines.get(effect: effect, key: key) else {
            return FocusKey(timeMs: -1, centreX: 0, centreY: 0, radiusMin: 0, radiusMax: 0, countMin: 0, countMax: 0, alpha: 0, rerollMs: 0)
        }
        return FocusKey(
            timeMs: k.timeMs,
            centreX: k.centreX,
            centreY: k.centreY,
            radiusMin: k.radiusMin,
            radiusMax: k.radiusMax,
            countMin: k.countMin,
            countMax: k.countMax,
            alpha: k.alpha,
            rerollMs: k.rerollMs
        )
    }

    var focusNotes: [FocusNote] {
        notes
    }
}
