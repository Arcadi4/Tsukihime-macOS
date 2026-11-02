import TsukiCore
import TsukiEngine
import Foundation

/// The addresses and counts of every table `Tsuki.Data` reads from an eboot.bin. `analysed` is the layout
/// of the verified build (CUSA47999 01.01, the constants the documents cite); `EbootLocator` builds one
/// for any other eboot from its content, and `EbootReader.layout` hands it to the readers. Virtual
/// addresses throughout; a count is the number of records a reader may read.
public struct EbootLayout {
    /// True when this is the layout of the verified build, taken from the constants rather than located.
    public var isAnalysed = false

    // MARK: - Catalog

    /// The image table (0x48-byte records).
    public var imageTable = 0

    /// Used records of the image table.
    public var imageRecords = 0

    /// Slots of the image table: the used records and the empty ones after them (the engine's bound).
    public var imageSlots = 0

    /// The picture-name list (32-byte records, one per image record plus one empty, then 0xFF).
    public var imageNames = 0

    /// The older, shorter name list; 0 when the eboot has none.
    public var oldImageNames = 0

    /// The movie table (0x30-byte records).
    public var movieTable = 0

    /// Records of the movie table before its terminator.
    public var movieRecords = 0

    /// The terminator record of the movie table (id -1).
    public var movieTerminator: Int { movieTable + EbootAddresses.movieRecordSize * movieRecords }

    /// The `char*` table of the language suffixes `ja en zc zt ko`.
    public var languageSuffixes = 0

    /// Entries of `languageSuffixes` (5).
    public var languageCount = 0

    /// The four prologue movie ids per language.
    public var prologueTable = 0

    /// `char *ui_text[languages][uiTextCount]`.
    public var uiText = 0

    /// Strings per language in `uiText` (1,499).
    public var uiTextCount = 0

    /// The string "Hunex Consumer Library".
    public var hunexString = 0

    /// The UI texture registration tables, in address order.
    public var uiTables: [Int] = []

    // MARK: - Fonts

    /// The 16 glyph lookup tables (fonts.md 5.1), in engine order.
    public var fontLookups: [FontLookupSpec] = []

    /// The 17 glyph record tables (fonts.md 5.3), in engine order.
    public var fontRecords: [FontRecordSpec] = []

    /// The wide-grid base slots, a u16 per language.
    public var fontWideBase = 0

    /// The 39 `[tag]` names, 11 bytes each.
    public var fontTags = 0

    // MARK: - Scripts and motions

    /// The scene-id table (an i16 per script, -1 terminated).
    public var sceneIds = 0

    /// Scripts in `sceneIds`.
    public var sceneCount = 0

    /// The STMA field-enable masks, `u64[motionCount + 1]`.
    public var motionMasks = 0

    /// The motion durations, `i64[motionCount]`.
    public var motionDurations = 0

    /// The exclusive keyframe end index of each motion, `i64[motionCount]`.
    public var motionEnds = 0

    /// The 72-byte keyframes.
    public var motionKeys = 0

    /// Motions (24,192).
    public var motionCount = 0

    /// Keyframes (71,905): the end index of the last motion.
    public var keyframeCount = 0

    // MARK: - Engine tables (docs/research/knife_tables.md)

    /// The STRA haze parameters (10 floats per entry, entry 0 the filler).
    public var haze = 0

    /// Entries of `haze` including entry 0 (558).
    public var hazeEntries = 0

    /// The flowchart node of each scene, `i32[sceneNodeCount]`.
    public var sceneNodes = 0

    /// Entries of `sceneNodes` (527).
    public var sceneNodeCount = 0

    /// The compiled STMA loop switch, `int loop_point(int id)`.
    public var motionLoopFunction = 0

    /// The compiled flowchart-jump clears, `void clear(int column)`.
    public var jumpClearFunction = 0

    /// The F word array the clears write into.
    public var fWordsBase = 0

    /// The flow-jump copy of the keep lists: words, bytes, bits.
    public var flowJumpKeepLists: [Int] = []

    /// The history-record copy of the keep lists: words, bytes, bits.
    public var historyKeepLists: [Int] = []

    /// The 30 x 4 focus-line keys.
    public var fclnLines = 0

    /// The three falling-note records.
    public var fclnNotes = 0

    /// The voice speaker records.
    public var voiceSpeakers = 0

    /// Records of `voiceSpeakers` (36).
    public var voiceSpeakerRecords = 0

    /// Speaker to config voice row bit, `i32[24]`.
    public var voiceRowBits = 0

    /// Config voice row to progress word, `i32[19]`.
    public var voiceRowWords = 0

    /// The 14 config SE test names.
    public var testSeNames = 0

    /// The confirm-dialog and help message ids, `i32[55]`.
    public var dialogMessages = 0

    /// The message window types.
    public var windowTypes = 0

    /// Records of `windowTypes` (56).
    public var windowTypeCount = 0

    /// The 27 window x offsets.
    public var windowDx = 0

    /// The 37 window y offsets.
    public var windowDy = 0

    /// The six soft-clip radii.
    public var clipRadii = 0

    /// The `@c1..@c5` fill colours.
    public var textColours = 0

    /// The two config pages.
    public var configPages = 0

    /// The CG gallery groups.
    public var galleryGroups = 0

    /// Records of `galleryGroups` (458).
    public var galleryGroupCount = 0

    /// The CG alias records.
    public var galleryAliases = 0

    /// Records of `galleryAliases` (105).
    public var galleryAliasCount = 0

    /// The special (four-language-band) CG names.
    public var gallerySpecial = 0

    /// Entries of `gallerySpecial` (11).
    public var gallerySpecialCount = 0

    /// The picture seen-index map.
    public var seenMap = 0

    /// The music room records.
    public var music = 0

    /// Records of `music` (95).
    public var musicCount = 0

    /// The ending-list records.
    public var extras = 0

    /// Records of `extras` (25).
    public var extraCount = 0

    /// The trophy scene records.
    public var trophyScenes = 0

    /// Records of `trophyScenes` (27).
    public var trophySceneCount = 0

    /// The jump table of the CG category switch.
    public var categoryJumpTable = 0

    /// The common join of the category switch's cases.
    public var categoryJoin = 0

    /// Unlock categories with a rule (19).
    public var categoryCount = 0

    /// The flowchart column records.
    public var flowColumns = 0

    /// Records of `flowColumns` (277).
    public var flowColumnCount = 0

    /// The flowchart edge records.
    public var flowEdges = 0

    /// Records of `flowEdges` (630).
    public var flowEdgeCount = 0

    /// The choice edge flag triples.
    public var choiceFlags = 0

    /// Records of `choiceFlags` (83).
    public var choiceFlagCount = 0

    /// The savetitle cell tables: other languages, English.
    public var saveTitleCells: [Int] = []

    /// The system_phasetitle cell tables: ja, en, zh.
    public var phaseTitleCells: [Int] = []

    /// The flow_phasetitle cell tables: other languages, English.
    public var flowTitleCells: [Int] = []

    /// The flow_line_merge connector cells.
    public var flowLineCells = 0

    /// The conf_faceicon cells.
    public var voiceFaceCells = 0

    /// The conf_name cell tables: other languages, English.
    public var voiceNameCells: [Int] = []

    /// The help_key icon cells.
    public var guideIconCells = 0

    /// The help_txt word cells (five language blocks).
    public var guideWordCells = 0

    /// The two mode banner cells.
    public var bannerRects: [Int] = []

    /// The banner pop-in scale keys.
    public var bannerKeys = 0

    /// The six title background indices.
    public var titleBackground = 0

    public init() {}

    /// The layout of the verified build: every constant the documents cite.
    public static let analysed: EbootLayout = {
        var layout = EbootLayout()
        layout.isAnalysed = true
        layout.imageTable = EbootAddresses.imageTable
        layout.imageRecords = EbootAddresses.imageTableRecords
        layout.imageSlots = EbootAddresses.imageTableSlots
        layout.imageNames = EbootAddresses.imageNames
        layout.oldImageNames = EbootAddresses.oldImageNames
        layout.movieTable = EbootAddresses.movieTable
        layout.movieRecords = (EbootAddresses.movieTerminator - EbootAddresses.movieTable) / EbootAddresses.movieRecordSize
        layout.languageSuffixes = EbootAddresses.languageSuffixes
        layout.languageCount = 5
        layout.prologueTable = EbootAddresses.prologueTable
        layout.uiText = EbootAddresses.uiText
        layout.uiTextCount = UiTextTable.count
        layout.hunexString = EbootAddresses.hunexString
        layout.uiTables = EbootAddresses.uiTables
        layout.fontLookups = EbootFontData.lookupSpecs
        layout.fontRecords = EbootFontData.recordSpecs
        layout.fontWideBase = EbootFontData.wideBaseVa
        layout.fontTags = EbootFontData.tagsVa
        layout.sceneIds = EbootAddresses.sceneIds
        layout.sceneCount = SceneTable.retailCount
        layout.motionMasks = MotionFieldMasks.va
        layout.motionDurations = MotionTables.durationVa
        layout.motionEnds = MotionTables.endVa
        layout.motionKeys = MotionTables.keysVa
        layout.motionCount = MotionTables.motionCount
        layout.keyframeCount = MotionTables.maxKey + 1
        layout.haze = HazeTable.va
        layout.hazeEntries = HazeTable.maxId + 1
        layout.sceneNodes = SceneNodeTable.va
        layout.sceneNodeCount = SceneNodeTable.count
        layout.motionLoopFunction = MotionLoopTable.functionVa
        layout.jumpClearFunction = JumpClearTable.functionVa
        layout.fWordsBase = JumpClearTable.fWordsBase
        layout.flowJumpKeepLists = FlowKeepLists.flowJumpVa
        layout.historyKeepLists = FlowKeepLists.historyVa
        layout.fclnLines = FclnLineTable.va
        layout.fclnNotes = FclnNoteTable.va
        layout.voiceSpeakers = VoiceSpeakerTable.va
        layout.voiceSpeakerRecords = VoiceSpeakerTable.recordCount
        layout.voiceRowBits = VoiceSpeakerTable.rowBitVa
        layout.voiceRowWords = VoiceSpeakerTable.rowWordVa
        layout.testSeNames = TestSeNames.va
        layout.dialogMessages = DialogMessageTable.va
        layout.windowTypes = MessageWindowTable.typesVa
        layout.windowTypeCount = MessageWindowTable.typeCount
        layout.windowDx = MessageWindowTable.dxVa
        layout.windowDy = MessageWindowTable.dyVa
        layout.clipRadii = SoftClipRadii.va
        layout.textColours = TextColourTable.va
        layout.configPages = ConfigPageTable.va
        layout.galleryGroups = GalleryTables.groupVa
        layout.galleryGroupCount = GalleryTables.groupCount
        layout.galleryAliases = GalleryTables.aliasVa
        layout.galleryAliasCount = GalleryTables.aliasCount
        layout.gallerySpecial = GalleryTables.specialVa
        layout.gallerySpecialCount = GalleryTables.specialCount
        layout.seenMap = GalleryTables.seenMapVa
        layout.music = GalleryTables.musicVa
        layout.musicCount = GalleryTables.musicCount
        layout.extras = GalleryTables.extraVa
        layout.extraCount = GalleryTables.extraCount
        layout.trophyScenes = GalleryTables.trophySceneVa
        layout.trophySceneCount = GalleryTables.trophySceneCount
        layout.categoryJumpTable = GalleryTables.categoryJumpTableVa
        layout.categoryJoin = GalleryTables.categoryJoin
        layout.categoryCount = GalleryTables.categoryCount
        layout.flowColumns = FlowchartTables.columnVa
        layout.flowColumnCount = FlowchartTables.columnCount
        layout.flowEdges = FlowchartTables.edgeVa
        layout.flowEdgeCount = FlowchartTables.edgeCount
        layout.choiceFlags = FlowchartTables.choiceFlagVa
        layout.choiceFlagCount = FlowchartTables.choiceFlagCount
        layout.saveTitleCells = UiCellTables.saveTitleVa
        layout.phaseTitleCells = UiCellTables.phaseTitleVa
        layout.flowTitleCells = UiCellTables.flowTitleVa
        layout.flowLineCells = UiCellTables.flowLineVa
        layout.voiceFaceCells = UiCellTables.voiceFaceVa
        layout.voiceNameCells = UiCellTables.voiceNameVa
        layout.guideIconCells = UiCellTables.guideIconVa
        layout.guideWordCells = UiCellTables.guideWordVa
        layout.bannerRects = UiCellTables.bannerRectVa
        layout.bannerKeys = UiCellTables.bannerKeyVa
        layout.titleBackground = titleBackgroundVa
        return layout
    }()

    /// Text VA of the six title background indices of the verified build (read by the title screen).
    public static let titleBackgroundVa = 0x218A40

    /// The named addresses of this layout, in a fixed order, for reports and for the equality test of the
    /// locator: `(name, address)` pairs where a table family lists one line per member.
    public func addresses() -> [(name: String, va: Int)] {
        var list: [(name: String, va: Int)] = [
            ("ImageTable", imageTable),
            ("ImageNames", imageNames),
            ("OldImageNames", oldImageNames),
            ("MovieTable", movieTable),
            ("MovieTerminator", movieTerminator),
            ("LanguageSuffixes", languageSuffixes),
            ("PrologueTable", prologueTable),
            ("UiText", uiText),
            ("HunexString", hunexString),
        ]
        for (i, va) in uiTables.enumerated() { list.append(("UiTables[\(i)]", va)) }
        for spec in fontLookups { list.append(("FontLookup \(spec.name)", spec.va)) }
        for spec in fontRecords { list.append(("FontRecords \(spec.name)", spec.va)) }
        list.append(contentsOf: [
            ("FontWideBase", fontWideBase),
            ("FontTags", fontTags),
            ("SceneIds", sceneIds),
            ("MotionMasks", motionMasks),
            ("MotionDurations", motionDurations),
            ("MotionEnds", motionEnds),
            ("MotionKeys", motionKeys),
            ("Haze", haze),
            ("SceneNodes", sceneNodes),
            ("MotionLoopFunction", motionLoopFunction),
            ("JumpClearFunction", jumpClearFunction),
            ("FWordsBase", fWordsBase),
        ])
        for (i, va) in flowJumpKeepLists.enumerated() { list.append(("FlowJumpKeepLists[\(i)]", va)) }
        for (i, va) in historyKeepLists.enumerated() { list.append(("HistoryKeepLists[\(i)]", va)) }
        list.append(contentsOf: [
            ("FclnLines", fclnLines),
            ("FclnNotes", fclnNotes),
            ("VoiceSpeakers", voiceSpeakers),
            ("VoiceRowBits", voiceRowBits),
            ("VoiceRowWords", voiceRowWords),
            ("TestSeNames", testSeNames),
            ("DialogMessages", dialogMessages),
            ("WindowTypes", windowTypes),
            ("WindowDx", windowDx),
            ("WindowDy", windowDy),
            ("ClipRadii", clipRadii),
            ("TextColours", textColours),
            ("ConfigPages", configPages),
            ("GalleryGroups", galleryGroups),
            ("GalleryAliases", galleryAliases),
            ("GallerySpecial", gallerySpecial),
            ("SeenMap", seenMap),
            ("Music", music),
            ("Extras", extras),
            ("TrophyScenes", trophyScenes),
            ("CategoryJumpTable", categoryJumpTable),
            ("CategoryJoin", categoryJoin),
            ("FlowColumns", flowColumns),
            ("FlowEdges", flowEdges),
            ("ChoiceFlags", choiceFlags),
        ])
        for (i, va) in saveTitleCells.enumerated() { list.append(("SaveTitleCells[\(i)]", va)) }
        for (i, va) in phaseTitleCells.enumerated() { list.append(("PhaseTitleCells[\(i)]", va)) }
        for (i, va) in flowTitleCells.enumerated() { list.append(("FlowTitleCells[\(i)]", va)) }
        list.append(contentsOf: [
            ("FlowLineCells", flowLineCells),
            ("VoiceFaceCells", voiceFaceCells),
        ])
        for (i, va) in voiceNameCells.enumerated() { list.append(("VoiceNameCells[\(i)]", va)) }
        list.append(contentsOf: [
            ("GuideIconCells", guideIconCells),
            ("GuideWordCells", guideWordCells),
        ])
        for (i, va) in bannerRects.enumerated() { list.append(("BannerRects[\(i)]", va)) }
        list.append(contentsOf: [
            ("BannerKeys", bannerKeys),
            ("TitleBackground", titleBackground),
        ])
        return list
    }

    /// The counts of this layout as `(name, count)` pairs, in a fixed order.
    public func counts() -> [(name: String, count: Int)] {
        var list: [(name: String, count: Int)] = [
            ("ImageRecords", imageRecords),
            ("ImageSlots", imageSlots),
            ("MovieRecords", movieRecords),
            ("LanguageCount", languageCount),
            ("UiTextCount", uiTextCount),
            ("UiTables", uiTables.count),
        ]
        for spec in fontLookups { list.append(("FontLookup \(spec.name)", spec.count)) }
        for spec in fontRecords { list.append(("FontRecords \(spec.name)", spec.count)) }
        list.append(contentsOf: [
            ("SceneCount", sceneCount),
            ("MotionCount", motionCount),
            ("KeyframeCount", keyframeCount),
            ("HazeEntries", hazeEntries),
            ("SceneNodeCount", sceneNodeCount),
            ("VoiceSpeakerRecords", voiceSpeakerRecords),
            ("WindowTypeCount", windowTypeCount),
            ("GalleryGroupCount", galleryGroupCount),
            ("GalleryAliasCount", galleryAliasCount),
            ("GallerySpecialCount", gallerySpecialCount),
            ("MusicCount", musicCount),
            ("ExtraCount", extraCount),
            ("TrophySceneCount", trophySceneCount),
            ("CategoryCount", categoryCount),
            ("FlowColumnCount", flowColumnCount),
            ("FlowEdgeCount", flowEdgeCount),
            ("ChoiceFlagCount", choiceFlagCount),
        ])
        return list
    }
}
