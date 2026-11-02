/// The eboot-only tables (RR 3.2, FORMATS 5.4): picture names, image catalog, scene ids, movie table
/// and prologue remap, motion tables, font lookup and rectangles, layout and window-picture tables,
/// UI texture registration, rule-mask names, blend and effect tables, config defaults, history
/// F-index lists, `ui_text`, title backgrounds, music mode, BGM names and the gallery lists.
///
/// Everything is read once from the user's eboot and immutable. Implementations are safe to use from
/// the decode workers.
public protocol EbootTables: AnyObject {
    /// The glyph lookup and rectangle tables the text layout reads (docs/formats/fonts.md 5).
    var gameFonts: FontTables { get }

    /// The scene table and the flowchart data the interpreter needs for `_JUMP` and the flowchart
    /// marks.
    var gameFlow: GameFlowTables { get }

    /// The 24,192 layer motions with their field-enable words and loop points (`_STMA` / `_SGMA`).
    var motions: MotionTables { get }

    /// The image catalog and the picture-name map as the layer commands use them (14,744 records).
    var pictures: PictureCatalog { get }

    /// The STRA haze parameters (text VA 0x219910, ids 1..557, ten float32 each).
    var haze: HazeTable { get }

    /// The six soft-clip radii (texel sizes of the BORDER_PARTS gradation quadrants, text VA
    /// 0x200590: 10, 32, 40, 64, 128, 256); nil when the source has none (the stage then uses its
    /// built-in copy).
    var clipRadii: [Float]? { get }

    /// The UI cell, message and layout tables that the UI reads.
    var ui: UiTables { get }

    /// The gallery and flowchart tables, or nil when the source holds none (the golden slice).
    var gallery: UiGalleryTables? { get }

    /// The focus-line and falling-note tables of `_FCLN` / `_FLNT`, or nil when the source holds
    /// none (the golden slice); the effects then draw nothing.
    var effects: EffectTables? { get }
}

public extension EbootTables {
    /// A source without gradation quadrants uses the stage's built-in radii.
    var clipRadii: [Float]? { nil }

    /// A golden slice has no gallery tables.
    var gallery: UiGalleryTables? { nil }

    /// A golden slice has no effect tables.
    var effects: EffectTables? { nil }
}

// MARK: - Game flow

/// A scene-transition edge of the flowchart: the edge flags a story step from node `from` to node
/// `to` sets.
public struct FlowEdgeRow: Sendable {
    /// Source node.
    public let from: Int
    /// Target node.
    public let to: Int
    /// Edge ids set in the global progress words (G400+).
    public let globalIds: [Int]
    /// Edge ids set in the playthrough words (F600+).
    public let playthroughIds: [Int]

    public init(from: Int, to: Int, globalIds: [Int], playthroughIds: [Int]) {
        self.from = from
        self.to = to
        self.globalIds = globalIds
        self.playthroughIds = playthroughIds
    }
}

/// A node of the flowchart (a 64-byte record of text VA 0x18FC90).
public struct FlowNodeRow: Sendable {
    /// The flowchart column (0..276).
    public let column: Int
    /// The RTST bit of the node (positive), a link marker (negative) or 0.
    public let scene: Int
    /// The scene id the replay of the node starts (the `_JUMP` target).
    public let scriptScene: Int
    /// The choice edge flag id 564..1194 of the node, -1 none.
    public let link: Int
    /// The chapter band of the node's column (0 for the first chapter's columns).
    public let group: Int

    public init(column: Int, scene: Int, scriptScene: Int, link: Int = -1, group: Int = 0) {
        self.column = column
        self.scene = scene
        self.scriptScene = scriptScene
        self.link = link
        self.group = group
    }
}

/// The scene and flowchart tables of the game interpreter, read once from the user's eboot and
/// immutable (docs/research/knife_tables.md).
public protocol GameFlowTables: AnyObject {
    /// Number of scripts (549).
    var sceneCount: Int { get }

    /// The scene id of script `script` (`_JUMP` argument 0).
    func sceneId(_ script: Int) -> Int

    /// The script number of a scene id, or -1 when the table has none (script.md 6.1).
    func scriptOfSceneId(_ sceneId: Int) -> Int

    /// The flowchart node of script `script` (the RTST bit), -1 when it has none.
    func nodeOfScript(_ script: Int) -> Int

    /// The picture-seen bit of picture `pictureId` (gallery.md 2.2: a `_HH_VV` variant counts as its
    /// base picture, ids from 0xA8D go through the seen map, bits 0..3199), or -1.
    func pictureSeenIndex(_ pictureId: Int) -> Int

    /// The 630 edges of the flowchart.
    var edges: [FlowEdgeRow] { get }

    /// The flowchart nodes (1,286).
    var nodes: [FlowNodeRow] { get }

    /// F words a flowchart jump keeps whole.
    var jumpKeepWords: [Int] { get }

    /// F words a flowchart jump keeps as a signed byte.
    var jumpKeepBytes: [Int] { get }

    /// F words a flowchart jump keeps as a flag.
    var jumpKeepBits: [Int] { get }

    /// (last column, F word) pairs: a jump to a column at or before the last column zeroes the word.
    var jumpClears: [(lastColumn: Int, word: Int)] { get }
}

// MARK: - Menus

/// A cell of a UI sheet in texels: the corners (x0, y0) and (x1, y1), x1 and y1 exclusive.
public struct SheetCell: Sendable {
    /// Left edge.
    public let x0: Int
    /// Top edge.
    public let y0: Int
    /// Right edge (exclusive).
    public let x1: Int
    /// Bottom edge (exclusive).
    public let y1: Int

    public init(x0: Int, y0: Int, x1: Int, y1: Int) {
        self.x0 = x0
        self.y0 = y0
        self.x1 = x1
        self.y1 = y1
    }

    /// Width in texels.
    public var width: Int { x1 - x0 }

    /// Height in texels.
    public var height: Int { y1 - y0 }
}

/// One control of a config row (docs/formats/adv_state.md 9.1): item id, type code and position in
/// 640 x 448 units.
public struct UiConfigControl: Sendable {
    /// Item id.
    public let item: Int
    /// Type code: 1 test button, 2 check box, 3 / 4 / 5 minus / slider / plus [H], 6..10 radio groups.
    public let kind: Int
    /// Position x in 640 x 448 units (-9999 where the screen places the control at run time).
    public let x: Float
    /// Position y in 640 x 448 units.
    public let y: Float

    public init(item: Int, kind: Int, x: Float, y: Float) {
        self.item = item
        self.kind = kind
        self.x = x
        self.y = y
    }
}

/// One row of a config page.
public struct UiConfigRow: Sendable {
    /// The controls, left to right.
    public let controls: [UiConfigControl]
    /// The page's stored current value.
    public let current: Int
    /// Slider maximum.
    public let maximum: Int

    public init(controls: [UiConfigControl], current: Int, maximum: Int) {
        self.controls = controls
        self.current = current
        self.maximum = maximum
    }
}

/// One data-driven config page (page 0 System, page 1 Sound).
public struct UiConfigPage: Sendable {
    /// First item id.
    public let firstItem: Int
    /// Last item id.
    public let lastItem: Int
    /// The rows.
    public let rows: [UiConfigRow]

    public init(firstItem: Int, lastItem: Int, rows: [UiConfigRow]) {
        self.firstItem = firstItem
        self.lastItem = lastItem
        self.rows = rows
    }
}

/// The eboot tables the menu screens need, read once from the user's eboot and immutable. Cell
/// tables are in texels of the named sheet; message ids are `ui_text` ids (the PS4 numbering, which
/// is knife's SYSMES number plus one from 217 on).
public protocol UiTables: AnyObject {
    /// The glyph lookup and rectangle tables of the text layout (docs/formats/fonts.md 5).
    var fonts: FontTables { get }

    /// The `ui_text` string `id` (1..1498) in `language`; `^` is the line break; empty when the id has
    /// no text.
    func text(_ language: Language, _ id: Int) -> String

    /// The savetitle cells by phase F023 (38) in SAVE_PARTS child 7 (the English table for English,
    /// the other one for the rest).
    func saveTitleCells(_ language: Language) -> [SheetCell]

    /// The system_phasetitle cells by phase (38) in MENU_PARTS child 2 (ja, en, and the third table
    /// for the others).
    func phaseTitleCells(_ language: Language) -> [SheetCell]

    /// The help_key icon cells (23) in DISP_PARTS child 16.
    var guideIconCells: [SheetCell] { get }

    /// The help_txt word cells (27) in DISP_PARTS child 17 for `language`.
    func guideWordCells(_ language: Language) -> [SheetCell]

    /// The mode banner cells of the PS4 build (2) in DISP_PARTS child 10.
    var bannerCells: [SheetCell] { get }

    /// The banner pop-in scale keys (10 x {x scale, y scale}) sampled over t * 9.
    var bannerKeys: [(x: Float, y: Float)] { get }

    /// The conf_faceicon cells per config voice row (20) in CONF_PARTS child 12.
    var voiceFaceCells: [SheetCell] { get }

    /// The conf_name cells per config voice row (20) in CONF_PARTS child 13 (the English table for
    /// English).
    func voiceNameCells(_ language: Language) -> [SheetCell]

    /// The two data-driven config pages (System, Sound) with control positions.
    var configPages: [UiConfigPage] { get }

    /// The ui_text id of each confirm dialog and help message (55; -1 = none;
    /// docs/research/knife_tables.md 5.1).
    var dialogMessages: [Int] { get }

    /// The progress word (G) that says whether a config voice row's character has been heard, per
    /// row (19).
    var voiceRowWords: [Int] { get }

    /// The 14 config SE test names.
    var testSeNames: [String] { get }

    /// Finds a picture of the image archives by its file name (the engine's NAM search,
    /// docs/formats/archives_ui_movies.md 2.3; case-insensitive), for example the caution screens
    /// `caution_en.mzp`; (archive id, entry), or nil when there is none.
    func findPicture(_ name: String) -> (archive: Int, entry: Int)?

    /// The title background table by G002 (6 x i32 at text VA 0x218A40;
    /// docs/formats/system_flow.md 4.2).
    var titleBackgroundTable: [Int] { get }
}

// MARK: - Gallery, music room, ending list and flowchart

/// One CG of a gallery group (gallery.md 4.1).
public struct GalleryCgRow: Sendable {
    /// The picture name without the one-character prefix (`IMG1685.MZP`).
    public let name: String
    /// Child of the GALLERY_PARTS_CG_TH set.
    public let thumbnail: Int
    /// Source rectangle x in the picture (1920-wide units).
    public let x: Int
    /// Source rectangle y.
    public let y: Int
    /// Source rectangle width.
    public let width: Int
    /// Source rectangle height.
    public let height: Int
    /// The +0x1C byte (meaning [H]).
    public let flag: Int

    public init(name: String, thumbnail: Int, x: Int, y: Int, width: Int, height: Int, flag: Int) {
        self.name = name
        self.thumbnail = thumbnail
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.flag = flag
    }
}

/// A gallery group: the CGs shown as one tile of the main grid.
public struct GalleryGroupRow: Sendable {
    /// Unlock category 0..19 (gallery.md 4.4).
    public let category: Int
    /// The CGs of the group.
    public let entries: [GalleryCgRow]

    public init(category: Int, entries: [GalleryCgRow]) {
        self.category = category
        self.entries = entries
    }
}

/// A CG that is also unlocked by seeing one of its alias pictures (gallery.md 4.3).
public struct GalleryAliasRow: Sendable {
    /// The CG's picture name.
    public let key: String
    /// The alias picture names, in order.
    public let aliases: [String]

    public init(key: String, aliases: [String]) {
        self.key = key
        self.aliases = aliases
    }
}

/// A track of the music player (gallery.md 6.1).
public struct GalleryTrackRow: Sendable {
    /// The bgm.hed index; the heard bit is 0xC80 + this.
    public let bgm: Int
    /// `ui_text` id of the title.
    public let titleUi: Int
    /// Credit ids after the four labels (-1 none): vocals.
    public let vocalUi: Int
    /// Lyrics credit.
    public let lyricsUi: Int
    /// Composition credit.
    public let composerUi: Int
    /// Arrangement credit.
    public let arrangerUi: Int
    /// Shown length in ms (0 when the table has none).
    public let lengthMs: Int
    /// Loop start sample (48 kHz).
    public let loopStart: Int
    /// Loop end sample (48 kHz).
    public let loopEnd: Int
    /// Other BGM tracks that also unlock the entry.
    public let variants: [Int]

    public init(bgm: Int, titleUi: Int, vocalUi: Int, lyricsUi: Int, composerUi: Int,
                arrangerUi: Int, lengthMs: Int, loopStart: Int, loopEnd: Int, variants: [Int]) {
        self.bgm = bgm
        self.titleUi = titleUi
        self.vocalUi = vocalUi
        self.lyricsUi = lyricsUi
        self.composerUi = composerUi
        self.arrangerUi = arrangerUi
        self.lengthMs = lengthMs
        self.loopStart = loopStart
        self.loopEnd = loopEnd
        self.variants = variants
    }
}

/// An entry of the ending list (gallery.md 8).
public struct GalleryEndingRow: Sendable {
    /// The QA scene passed to the replay (1000..1024).
    public let scriptScene: Int
    /// The scene's flowchart node (533..557).
    public let flowScene: Int
    /// scene_done(unlockA) or scene_done(unlockB) unlocks the entry.
    public let unlockA: Int
    /// Second unlock scene, or -1.
    public let unlockB: Int
    /// `ui_text` id of the play prompt, or -1.
    public let messageUi: Int

    public init(scriptScene: Int, flowScene: Int, unlockA: Int, unlockB: Int, messageUi: Int) {
        self.scriptScene = scriptScene
        self.flowScene = flowScene
        self.unlockA = unlockA
        self.unlockB = unlockB
        self.messageUi = messageUi
    }
}

/// A node record of the flowchart (gallery.md 5.2).
public struct ChartNodeRow: Sendable {
    /// Positive: the node (lit by scene_done); negative: a marker for -scene; 0: empty.
    public let scene: Int
    /// Connector code, -1 none.
    public let connector: Int
    /// Edge id 565..1194 (edge_seen) or -1.
    public let link: Int
    /// The scene id a replay or a jump starts.
    public let scriptScene: Int
    /// Cell index into the chapter label cells, or -1.
    public let chapterLabel: Int
    /// Cell of the scene-thumbnail mosaic (FC child 7).
    public let mosaic: Int
    /// Child of the GALLERY_PARTS_FC_TH set.
    public let preview: Int
    /// `ui_text` id of the title, -1 none.
    public let titleUi: Int
    /// `ui_text` id of the synopsis, -1 none.
    public let synopsisUi: Int

    public init(scene: Int, connector: Int, link: Int, scriptScene: Int, chapterLabel: Int,
                mosaic: Int, preview: Int, titleUi: Int, synopsisUi: Int) {
        self.scene = scene
        self.connector = connector
        self.link = link
        self.scriptScene = scriptScene
        self.chapterLabel = chapterLabel
        self.mosaic = mosaic
        self.preview = preview
        self.titleUi = titleUi
        self.synopsisUi = synopsisUi
    }
}

/// A flowchart column of the static table.
public struct ChartColumnRow: Sendable {
    /// Chapter band 0..15 (the phase).
    public let group: Int
    /// The nodes.
    public let nodes: [ChartNodeRow]
    /// The scene word of the record that follows the last node in memory: the engine's column
    /// filter reads it (gallery.md 5.4).
    public let overrunScene: Int
    /// The link word of that record.
    public let overrunLink: Int

    public init(group: Int, nodes: [ChartNodeRow], overrunScene: Int, overrunLink: Int) {
        self.group = group
        self.nodes = nodes
        self.overrunScene = overrunScene
        self.overrunLink = overrunLink
    }
}

/// An edge of the flowchart: the edge ids set when the story goes from node `from` to node `to`.
public struct ChartEdgeRow: Sendable {
    /// Source node.
    public let from: Int
    /// Target node.
    public let to: Int
    /// Edge ids for the persistent set.
    public let globalIds: [Int]
    /// Edge ids for this playthrough.
    public let playthroughIds: [Int]

    public init(from: Int, to: Int, globalIds: [Int], playthroughIds: [Int]) {
        self.from = from
        self.to = to
        self.globalIds = globalIds
        self.playthroughIds = playthroughIds
    }
}

/// The gallery, music room, ending list and flowchart tables read from the eboot
/// (docs/formats/gallery.md).
public protocol UiGalleryTables: AnyObject {
    /// The 458 CG groups.
    var cgGroups: [GalleryGroupRow] { get }

    /// The 105 CG aliases.
    var cgAliases: [GalleryAliasRow] { get }

    /// The 11 CG names that stack one picture per language (their source rectangle moves down by its
    /// height times the language).
    var cgLanguageStrips: [String] { get }

    /// Per CG category 1..19, the scene_seen ids of which any one opens it.
    var cgCategoryScenes: [Int: [Int]] { get }

    /// The 95 music player tracks.
    var tracks: [GalleryTrackRow] { get }

    /// The 25 ending list entries.
    var endings: [GalleryEndingRow] { get }

    /// The 277 flowchart columns.
    var chartColumns: [ChartColumnRow] { get }

    /// The 630 flowchart edges (table order, first match wins).
    var chartEdges: [ChartEdgeRow] { get }

    /// The chapter label cells (30) in FC child 6 (the English table for English).
    func chartTitleCells(_ language: Language) -> [SheetCell]

    /// The connector cells (12) of the route line sheets (FC children 4 and 5).
    var chartLineCells: [SheetCell] { get }

    /// The index of a picture name (extension ignored, case-insensitive) in the picture name table,
    /// or -1.
    func pictureIndex(_ name: String) -> Int

    /// The picture-seen bit of picture `pictureId` (gallery.md 2.2), or -1.
    func pictureSeenIndex(_ pictureId: Int) -> Int
}

// MARK: - Screen effects

/// One timed key of a focus-line effect; `timeMs` -1 marks an unused key. Positions are in
/// 1280 x 720 units.
public struct FocusKey: Sendable {
    /// Key time in ms, -1 = unused.
    public let timeMs: Int
    /// Centre x.
    public let centreX: Int
    /// Centre y.
    public let centreY: Int
    /// Inner radius of the lines.
    public let radiusMin: Int
    /// Outer radius of the lines.
    public let radiusMax: Int
    /// Fewest lines.
    public let countMin: Int
    /// Most lines.
    public let countMax: Int
    /// 0..255.
    public let alpha: Int
    /// Interval at which the lines are rolled again.
    public let rerollMs: Int

    public init(timeMs: Int, centreX: Int, centreY: Int, radiusMin: Int, radiusMax: Int,
                countMin: Int, countMax: Int, alpha: Int, rerollMs: Int) {
        self.timeMs = timeMs
        self.centreX = centreX
        self.centreY = centreY
        self.radiusMin = radiusMin
        self.radiusMax = radiusMax
        self.countMin = countMin
        self.countMax = countMax
        self.alpha = alpha
        self.rerollMs = rerollMs
    }
}

/// One falling-note kind of the effects 1..3 (docs/research/knife_tables.md row 2.5).
public struct FocusNote: Sendable {
    /// Animation frames.
    public let frames: Int
    /// The frame shown at each animation step (`frames` entries).
    public let sequence: [Int]
    /// Frame width in texels.
    public let width: Int
    /// Frame height in texels.
    public let height: Int
    /// Ticks per animation frame.
    public let step: Int
    /// Initial x velocity.
    public let vx: Float
    /// Initial y velocity.
    public let vy: Float
    /// Velocity jitter scale in x.
    public let jitterX: Float
    /// Velocity jitter scale in y.
    public let jitterY: Float
    /// Acceleration in y per frame.
    public let accel: Float
    /// The y at which a note ends.
    public let floor: Int

    public init(frames: Int, sequence: [Int], width: Int, height: Int, step: Int, vx: Float,
                vy: Float, jitterX: Float, jitterY: Float, accel: Float, floor: Int) {
        self.frames = frames
        self.sequence = sequence
        self.width = width
        self.height = height
        self.step = step
        self.vx = vx
        self.vy = vy
        self.jitterX = jitterX
        self.jitterY = jitterY
        self.accel = accel
        self.floor = floor
    }
}

/// The focus-line and falling-note tables read from the user's eboot.
public protocol EffectTables: AnyObject {
    /// Number of focus-line effects (30: `_FCLN` effects 4..33).
    var focusEffects: Int { get }

    /// Key `key` (0..3) of focus-line effect `effect` (0..29; 0 is `_FCLN` effect 4).
    func focusKey(_ effect: Int, _ key: Int) -> FocusKey

    /// The three falling-note kinds (`_FCLN` effects 1..3).
    var focusNotes: [FocusNote] { get }
}
