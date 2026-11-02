import Foundation
import TsukiCore

/// How a table's address was established.
public enum LocateMethod: String, Sendable {
    /// Found by its own content (a signature and a validator).
    case content
    /// Derived from a neighbouring table (a fixed offset, an alignment rule) and validated.
    case anchored
    /// Read out of the code that uses it (a function found by its instruction pattern).
    case code
}

/// One located table.
public struct TableLocation: Sendable {
    /// The table's name in `EbootLayout.addresses()`.
    public let name: String
    /// Where it was found.
    public let va: Int
    /// Records found (0 when the table has no count of its own).
    public let count: Int
    /// How it was found.
    public let method: LocateMethod
    /// What the validator saw.
    public let detail: String

    public init(name: String, va: Int, count: Int, method: LocateMethod, detail: String) {
        self.name = name
        self.va = va
        self.count = count
        self.method = method
        self.detail = detail
    }
}

/// The outcome of `EbootLocator.locate`.
public final class LocateResult {
    /// The layout, when every table was found; nil otherwise.
    public let layout: EbootLayout?
    /// The tables that were found.
    public let found: [TableLocation]
    /// The tables that were not found or failed validation, with the reason.
    public let missing: [(name: String, problem: String)]
    /// How long the search took.
    public let elapsed: TimeInterval

    public init(layout: EbootLayout?, found: [TableLocation], missing: [(name: String, problem: String)], elapsed: TimeInterval) {
        self.layout = layout
        self.found = found
        self.missing = missing
        self.elapsed = elapsed
    }

    /// True when every table was found and validated.
    public var complete: Bool { layout != nil }

    /// One line per table for the log.
    public func report() -> String {
        var text = ""
        for table in found {
            text += "  " + pad(table.name, 22) + " 0x" + pad(String(table.va, radix: 16), 8)
                + " " + pad(table.method.rawValue, 9) + table.detail + "\n"
        }
        for entry in missing {
            text += "  " + pad(entry.name, 22) + " MISSING   " + entry.problem + "\n"
        }
        return text
    }

    /// "71 tables located in 0.4 s" or "3 of 71 tables missing: ...".
    public func summary() -> String {
        if missing.isEmpty {
            return "\(found.count) tables located by content in \(String(format: "%.1f", elapsed)) s"
        }
        return "\(missing.count) of \(found.count + missing.count) tables missing: "
            + missing.map(\.name).joined(separator: ", ")
    }

    private func pad(_ value: String, _ width: Int) -> String {
        value.count >= width ? value : value + String(repeating: " ", count: width - value.count)
    }
}

/// Locates every table of `EbootLayout` in an eboot by content. Each table has a structural signature
/// (record strides, pointer ranges, terminators, monotonic indices, strings the engine itself uses) and
/// a validator; a table that cannot be found or fails validation is reported by name, never guessed.
/// On the verified eboot the result equals `EbootLayout.analysed` field by field.
public enum EbootLocator {
    /// Runs every search on `reader`. Never throws for malformed content: a table that cannot be found
    /// is in `LocateResult.missing`.
    public static func locate(_ reader: EbootReader) -> LocateResult {
        let start = Date()
        do {
            let session = try Session(reader)
            session.run()
            return LocateResult(
                layout: session.build(), found: session.found, missing: session.missing,
                elapsed: Date().timeIntervalSince(start))
        } catch {
            return LocateResult(
                layout: nil, found: [], missing: [("segments", describe(error))],
                elapsed: Date().timeIntervalSince(start))
        }
    }

    /// Validates the tables of `layout` on `reader` by reading each one; the names of the tables that fail.
    public static func validate(_ reader: EbootReader, _ layout: EbootLayout) -> [String] {
        let r = reader.withLayout(layout)
        var failed: [String] = []

        func attempt(_ name: String, _ read: () throws -> Void) {
            do {
                try read()
            } catch {
                failed.append(name + ": " + describe(error))
            }
        }

        attempt("image table") { _ = try ImageCatalog.read(r) }
        attempt("picture names") { _ = try PictureNameLists.read(r) }
        attempt("movie table") { _ = try MovieTable.read(r) }
        attempt("language suffixes") { _ = try MovieTable.readLanguageSuffixes(r) }
        attempt("ui_text") { _ = try UiTextTable.read(r) }
        attempt("ui tables") { _ = try UiTextureTables.readAll(r) }
        attempt("fonts") {
            let issues = try EbootFontData.read(r).verify()
            if !issues.isEmpty {
                throw TsukiError.format(issues.prefix(3).joined(separator: "; "))
            }
        }
        attempt("scene ids") { _ = try SceneTable.read(r) }
        attempt("motions") { _ = try MotionTables.read(r) }
        let engine = EngineTables(r)
        attempt("haze") { _ = try engine.haze }
        attempt("scene nodes") { _ = try engine.sceneNodes }
        attempt("motion loops") { _ = try engine.motionLoops }
        attempt("jump clears") { _ = try engine.jumpClears }
        attempt("keep lists") { _ = try engine.flowKeep; _ = try engine.historyKeep }
        attempt("focus lines") { _ = try engine.fclnLines; _ = try engine.fclnNotes }
        attempt("voices") { _ = try engine.voices }
        attempt("test SE names") { _ = try engine.testSes }
        attempt("dialogs") { _ = try engine.dialogs }
        attempt("windows") { _ = try engine.windows; _ = try engine.clipRadii; _ = try engine.textColours }
        attempt("config pages") { _ = try engine.configPages }
        attempt("motion masks") { _ = try engine.motionMasks }
        attempt("gallery") { _ = try engine.gallery }
        attempt("flowchart") { _ = try engine.flowchart }
        attempt("cells") {
            _ = try UiCellTables.readSaveTitleCells(r, english: false)
            _ = try UiCellTables.readSaveTitleCells(r, english: true)
            _ = try UiCellTables.readPhaseTitleCells(r, set: .zh)
            _ = try UiCellTables.readFlowTitleCells(r, english: true)
            _ = try UiCellTables.readFlowLineCells(r)
            _ = try UiCellTables.readVoiceFaceCells(r)
            _ = try UiCellTables.readVoiceNameCells(r, english: true)
            _ = try UiCellTables.readGuideIconCells(r)
            _ = try UiCellTables.readGuideWordCells(r, language: 4)
            _ = try UiCellTables.readBannerCells(r)
            _ = try UiCellTables.readBannerKeys(r)
        }
        attempt("title background") { _ = try r.read(layout.titleBackground, 24) }
        return failed
    }

    private static func describe(_ error: Error) -> String {
        if let error = error as? TsukiError { return error.description }
        return String(describing: error)
    }

    private static func pad(_ value: String, _ width: Int) -> String {
        value.count >= width ? value : value + String(repeating: " ", count: width - value.count)
    }

    private static func hex(_ value: Int) -> String { String(value, radix: 16) }

    /// One loaded segment of the image.
    private struct Seg {
        let name: String
        let va: Int
        let bytes: ByteSpan

        var end: Int { va + bytes.count }

        func contains(_ address: Int) -> Bool { address >= va && address < end }

        func offset(_ address: Int) -> Int { address - va }
    }

    /// The image table record size, cached for the finders.
    private static let imageRecordSize = EbootAddresses.imageRecordSize

    private static let expectedLanguageSuffixes = "ja en zc zt ko"
    private static let lookupNames = [
        "narrow", "ja_s1", "en_s1", "zc_s1", "zt_s1", "ko_s1", "ja_s2", "en_s2",
        "zc_s2", "zt_s2", "ko_s2", "ja_wide", "en_wide", "zc_wide", "zt_wide", "ko_wide",
    ]
    private static let recordNames = [
        "ja_s0", "ja_s2", "ja_s1", "en_s0", "en_s2", "en_s3", "en_s4", "en_s5", "en_s1",
        "zc_s0", "zc_s2", "zc_s1", "zt_s0", "zt_s1", "ko_s0", "ko_s2", "ko_s1",
    ]

    private final class Session {
        private let r: EbootReader
        private let text: Seg
        private let relro: Seg
        private let data: Seg
        private let segs: [Seg]
        private var lea: Set<Int> = []
        private(set) var found: [TableLocation] = []
        private(set) var missing: [(name: String, problem: String)] = []

        // Results.
        private var imageTable = 0
        private var imageNames = 0
        private var oldImageNames = 0
        private var movieTable = 0
        private var suffixes = 0
        private var prologue = 0
        private var uiText = 0
        private var hunex = 0
        private var imageRecords = 0
        private var imageSlots = 0
        private var movieRecords = 0
        private var languageCount = 0
        private var uiTextCount = 0
        private var uiTables: [Int] = []
        private var lookups: [FontLookupSpec] = []
        private var records: [FontRecordSpec] = []
        private var fontWide = 0
        private var fontTags = 0
        private var sceneIds = 0
        private var masks = 0
        private var durations = 0
        private var ends = 0
        private var keys = 0
        private var sceneCount = 0
        private var motionCount = 0
        private var keyCount = 0
        private var haze = 0
        private var sceneNodes = 0
        private var loopFn = 0
        private var clearFn = 0
        private var fwords = 0
        private var fcln = 0
        private var notes = 0
        private var voice = 0
        private var rowBits = 0
        private var rowWords = 0
        private var testSe = 0
        private var dialogs = 0
        private var windows = 0
        private var dx = 0
        private var dy = 0
        private var radii = 0
        private var colours = 0
        private var config = 0
        private var hazeEntries = 0
        private var sceneNodeCount = 0
        private var voiceRecords = 0
        private var windowCount = 0
        private var flowKeep = [0, 0, 0]
        private var historyKeep = [0, 0, 0]
        private var groups = 0
        private var aliases = 0
        private var special = 0
        private var seen = 0
        private var music = 0
        private var extras = 0
        private var trophy = 0
        private var catJump = 0
        private var catJoin = 0
        private var columns = 0
        private var edges = 0
        private var choice = 0
        private var groupCount = 0
        private var aliasCount = 0
        private var specialCount = 0
        private var musicCount = 0
        private var extraCount = 0
        private var trophyCount = 0
        private var catCount = 0
        private var columnCount = 0
        private var edgeCount = 0
        private var choiceCount = 0
        private var saveTitle = [0, 0]
        private var phaseTitle = [0, 0, 0]
        private var flowTitle = [0, 0]
        private var voiceName = [0, 0]
        private var bannerRects = [0, 0]
        private var flowLine = 0
        private var voiceFace = 0
        private var guideIcon = 0
        private var guideWord = 0
        private var bannerKeys = 0
        private var titleBg = 0
        private var sceneIdList: [Int16] = []
        private var movieNames: [String] = []

        init(_ reader: EbootReader) throws {
            r = reader
            let image = reader.image

            func make(_ name: String, _ ph: ProgramHeader) throws -> Seg {
                guard let fileOffset = image.phdrFileOffset(ph) else {
                    throw TsukiError.format("segment \(name) has no file bytes")
                }
                guard let size = Int(exactly: ph.fileSize), let va = Int(exactly: ph.vAddr),
                      size >= 0, fileOffset >= 0, fileOffset <= image.data.count - size else {
                    throw TsukiError.format("segment \(name) is outside the file")
                }
                return Seg(name: name, va: va, bytes: image.data.slice(fileOffset, size))
            }

            let textSegment = try make("text", image.text)
            let dataSegment = try make("data", image.dataSegment)
            let relroHeader: ProgramHeader
            if let relro = image.relro {
                relroHeader = relro
            } else if let candidate = image.loadSegments.first(where: {
                $0.index != image.text.index && $0.index != image.dataSegment.index && ($0.flags & 3) == 0
            }) {
                relroHeader = candidate.header
            } else {
                throw TsukiError.format("no read-only data segment (SCE_RELRO)")
            }
            let relroSegment = try make("relro", relroHeader)
            text = textSegment
            data = dataSegment
            relro = relroSegment
            segs = [textSegment, relroSegment, dataSegment]
            scanLea()
        }

        func run() {
            step("HunexString") { try findHunex() }
            step("ImageTable") { try findImageTable() }
            step("ImageNames") { try findNameLists() }
            step("MovieTable") { try findMovies() }
            step("LanguageSuffixes") { try findSuffixes() }
            step("PrologueTable") { try findPrologue() }
            step("UiText") { try findUiText() }
            step("UiTables") { try findUiTables() }
            step("FontTags") { try findFontTagsAndWideBase() }
            step("FontRecords") { try findFontRecords() }
            step("FontLookups") { try findFontLookups() }
            step("TestSeNames") { try findTestSe() }
            step("VoiceRowWords") { try findRowWords() }
            step("VoiceSpeakers") { try findVoiceSpeakers() }
            step("HistoryKeepLists") { try findHistoryListsAndSceneIds() }
            step("FlowJumpKeepLists") { try findFlowJumpLists() }
            step("FlowTitleCells") { try findFlowCells() }
            step("Haze") { try findHaze() }
            step("WindowTypes") { try findWindowCluster() }
            step("FclnLines") { try findFclnLines() }
            step("FlowEdges") { try findEdgeCluster() }
            step("TitleBackground") { try findTitleBackground() }
            step("MotionEnds") { try findMotionTables() }
            step("MotionKeys") { try findMotionKeys() }
            step("ConfigPages") { try findConfigPages() }
            step("SeenMap") { try findSeenMapAndRowBits() }
            step("FclnNotes") { try findFclnNotes() }
            step("BannerKeys") { try findBannerAndDataCells() }
            step("Music") { try findMusic() }
            step("Extras") { try findExtras() }
            step("DialogMessages") { try findDialogs() }
            step("TextColours") { try findTextColours() }
            step("GalleryGroups") { try findGallery() }
            step("FlowColumns") { try findColumns() }
            step("CategoryJumpTable") { try findCategorySwitch() }
            step("MotionLoopFunction") { try findMotionLoopFunction() }
            step("JumpClearFunction") { try findJumpClearFunction() }
        }

        private func step(_ name: String, _ find: () throws -> Void) {
            do {
                try find()
            } catch {
                missing.append((name: name, problem: EbootLocator.describe(error)))
            }
        }

        private func ok(_ name: String, _ va: Int, _ count: Int, _ method: LocateMethod, _ detail: String) {
            found.append(TableLocation(name: name, va: va, count: count, method: method, detail: detail))
        }

        func build() -> EbootLayout? {
            guard missing.isEmpty else { return nil }
            var layout = EbootLayout()
            layout.isAnalysed = false
            layout.imageTable = imageTable
            layout.imageRecords = imageRecords
            layout.imageSlots = imageSlots
            layout.imageNames = imageNames
            layout.oldImageNames = oldImageNames
            layout.movieTable = movieTable
            layout.movieRecords = movieRecords
            layout.languageSuffixes = suffixes
            layout.languageCount = languageCount
            layout.prologueTable = prologue
            layout.uiText = uiText
            layout.uiTextCount = uiTextCount
            layout.hunexString = hunex
            layout.uiTables = uiTables
            layout.fontLookups = lookups
            layout.fontRecords = records
            layout.fontWideBase = fontWide
            layout.fontTags = fontTags
            layout.sceneIds = sceneIds
            layout.sceneCount = sceneCount
            layout.motionMasks = masks
            layout.motionDurations = durations
            layout.motionEnds = ends
            layout.motionKeys = keys
            layout.motionCount = motionCount
            layout.keyframeCount = keyCount
            layout.haze = haze
            layout.hazeEntries = hazeEntries
            layout.sceneNodes = sceneNodes
            layout.sceneNodeCount = sceneNodeCount
            layout.motionLoopFunction = loopFn
            layout.jumpClearFunction = clearFn
            layout.fWordsBase = fwords
            layout.flowJumpKeepLists = flowKeep
            layout.historyKeepLists = historyKeep
            layout.fclnLines = fcln
            layout.fclnNotes = notes
            layout.voiceSpeakers = voice
            layout.voiceSpeakerRecords = voiceRecords
            layout.voiceRowBits = rowBits
            layout.voiceRowWords = rowWords
            layout.testSeNames = testSe
            layout.dialogMessages = dialogs
            layout.windowTypes = windows
            layout.windowTypeCount = windowCount
            layout.windowDx = dx
            layout.windowDy = dy
            layout.clipRadii = radii
            layout.textColours = colours
            layout.configPages = config
            layout.galleryGroups = groups
            layout.galleryGroupCount = groupCount
            layout.galleryAliases = aliases
            layout.galleryAliasCount = aliasCount
            layout.gallerySpecial = special
            layout.gallerySpecialCount = specialCount
            layout.seenMap = seen
            layout.music = music
            layout.musicCount = musicCount
            layout.extras = extras
            layout.extraCount = extraCount
            layout.trophyScenes = trophy
            layout.trophySceneCount = trophyCount
            layout.categoryJumpTable = catJump
            layout.categoryJoin = catJoin
            layout.categoryCount = catCount
            layout.flowColumns = columns
            layout.flowColumnCount = columnCount
            layout.flowEdges = edges
            layout.flowEdgeCount = edgeCount
            layout.choiceFlags = choice
            layout.choiceFlagCount = choiceCount
            layout.saveTitleCells = saveTitle
            layout.phaseTitleCells = phaseTitle
            layout.flowTitleCells = flowTitle
            layout.flowLineCells = flowLine
            layout.voiceFaceCells = voiceFace
            layout.voiceNameCells = voiceName
            layout.guideIconCells = guideIcon
            layout.guideWordCells = guideWord
            layout.bannerRects = bannerRects
            layout.bannerKeys = bannerKeys
            layout.titleBackground = titleBg
            return layout
        }

        // MARK: - Helpers

        private func segOf(_ va: Int) -> Seg? {
            segs.first { $0.contains(va) }
        }

        private func isStringPointer(_ p: UInt64) -> Bool {
            p != 0 && p < UInt64(Int.max) && intVa(p).flatMap { segOf($0) } != nil
        }

        private func intVa(_ value: UInt64) -> Int? { Int(exactly: value) }

        private func inText(_ va: Int) -> Bool { text.contains(va) }

        private func u8(_ va: Int) throws -> UInt8 { try r.read(va, 1)[0] }

        private func i16(_ va: Int) throws -> Int16 { try r.i16(va) }

        private func u16(_ va: Int) throws -> UInt16 { try r.read(va, 2).u16(0) }

        private func i32(_ va: Int) throws -> Int32 { try r.i32(va) }

        private func u32(_ va: Int) throws -> UInt32 { try r.u32(va) }

        private func i64(_ va: Int) throws -> Int64 { try r.read(va, 8).i64(0) }

        private func u64(_ va: Int) throws -> UInt64 { try r.u64(va) }

        private func f32(_ va: Int) throws -> Float { try r.read(va, 4).f32(0) }

        private func readable(_ va: Int, _ n: Int) -> Bool {
            guard n >= 0, let seg = segOf(va) else { return false }
            return n <= seg.end - va
        }

        /// The NUL-terminated ASCII string at a VA, or nil when it is not readable, longer than `limit`
        /// or not printable ASCII.
        private func asciiString(_ va: Int, limit: Int = 96) -> String? {
            guard let seg = segOf(va) else { return nil }
            let start = seg.offset(va)
            let length = min(limit, seg.bytes.count - start)
            guard length > 0 else { return nil }
            let window = seg.bytes.slice(start, length)
            var end = window.count
            for i in 0..<window.count where window[i] == 0 {
                end = i
                break
            }
            guard end < window.count else { return nil }
            for i in 0..<end where window[i] < 0x20 || window[i] > 0x7E {
                return nil
            }
            return String(decoding: window.slice(0, end), as: UTF8.self)
        }

        private static func indexOfAll(_ hay: ByteSpan, _ needle: [UInt8]) -> [Int] {
            guard !needle.isEmpty, hay.count >= needle.count else { return [] }
            var list: [Int] = []
            var start = 0
            while start <= hay.count - needle.count {
                guard let hit = firstIndex(of: needle, in: hay, from: start) else { break }
                list.append(hit)
                start = hit + 1
            }
            return list
        }

        private static func firstIndex(of needle: [UInt8], in hay: ByteSpan, from start: Int) -> Int? {
            guard !needle.isEmpty, start >= 0, hay.count >= needle.count else { return nil }
            let last = hay.count - needle.count
            guard start <= last else { return nil }
            let lead = needle[0]
            var i = start
            while i <= last {
                if hay[i] == lead {
                    var k = 1
                    while k < needle.count, hay[i + k] == needle[k] { k += 1 }
                    if k == needle.count { return i }
                }
                i += 1
            }
            return nil
        }

        private static func align(_ value: Int, _ boundary: Int) -> Int {
            (value + boundary - 1) / boundary * boundary
        }

        private static func finite(_ value: Float) -> Bool {
            !value.isNaN && !value.isInfinite && abs(value) < 1e6
        }

        private static func leBytes(_ value: UInt64) -> [UInt8] {
            (0..<8).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
        }

        /// Every target of a 7-byte rip-relative `lea r64, [rip+disp32]` in the text segment: the
        /// addresses the code loads tables from.
        private func scanLea() {
            let code = text.bytes
            var i = 0
            while i + 7 <= code.count {
                let rex = code[i]
                if (rex == 0x48 || rex == 0x4C), code[i + 1] == 0x8D, (code[i + 2] & 0xC7) == 0x05 {
                    let displacement = Int(code.i32(i + 3))
                    lea.insert(text.va + i + 7 + displacement)
                }
                i += 1
            }
        }

        private func leaTargetsIn(_ seg: Seg) -> [Int] {
            lea.filter { seg.contains($0) }.sorted()
        }

        /// Searches `seg` for a masked byte pattern (nil = any byte); the VAs of every match.
        private func findPattern(_ seg: Seg, _ pattern: [UInt8?]) -> [Int] {
            var hits: [Int] = []
            guard let first = pattern.firstIndex(where: { $0 != nil }), let lead = pattern[first] else { return [] }
            let span = seg.bytes
            var i = 0
            while i + pattern.count <= span.count {
                guard span[i + first] == lead else { i += 1; continue }
                var matches = true
                for k in 0..<pattern.count {
                    if let byte = pattern[k], span[i + k] != byte {
                        matches = false
                        break
                    }
                }
                if matches { hits.append(seg.va + i) }
                i += 1
            }
            return hits
        }

        // MARK: - Strings

        private func findHunex() throws {
            let hits = Self.indexOfAll(text.bytes, Array("Hunex Consumer Library\0".utf8))
            guard let first = hits.first else {
                throw TsukiError.format("the string \"Hunex Consumer Library\" is not in the text segment: not the HuneX engine")
            }
            hunex = text.va + first
            ok("HunexString", hunex, 0, .content, hits.count == 1 ? "unique" : "\(hits.count) copies, first taken")
        }

        // MARK: - Catalog

        /// The image table: record 0 names BLACK.mzp (name0 pointer 0, file pointer at +8), record 1
        /// BLUE.mzp; used records contiguous, then empty slots.
        private func findImageTable() throws {
            let recordSize = EbootLocator.imageRecordSize
            let span = data.bytes
            for start in Self.indexOfAll(text.bytes, Array("BLACK.mzp\0".utf8)) {
                let pointer = Self.leBytes(UInt64(text.va + start))
                for p in Self.indexOfAll(span, pointer) {
                    let record = p - 8
                    guard record >= 0, record + 2 * recordSize <= span.count, span.u64(record) == 0 else { continue }
                    guard let secondAddress = Int(exactly: span.u64(record + recordSize + 8)),
                          let second = asciiString(secondAddress, limit: 48),
                          second.caseInsensitiveCompare("BLUE.mzp") == .orderedSame else { continue }

                    var used = 0
                    while record + (used + 1) * recordSize <= span.count,
                          span.u64(record + used * recordSize + 8) != 0 {
                        used += 1
                    }

                    var empty = 0
                    while true {
                        let offset = record + (used + empty) * recordSize
                        if offset + recordSize > span.count || span.u64(offset + 8) != 0
                            || span.u64(offset + 16) != 0 || span.i32(offset + 0x20) != -1 {
                            break
                        }
                        empty += 1
                    }

                    guard used >= 1000, empty > 0 else {
                        throw TsukiError.format(
                            "image table at 0x\(EbootLocator.hex(data.va + record)): \(used) records and \(empty) empty slots")
                    }

                    imageTable = data.va + record
                    imageRecords = used
                    imageSlots = used + empty
                    ok("ImageTable", imageTable, used, .content, "\(used) records, \(empty) empty slots, BLACK.mzp / BLUE.mzp first")
                    return
                }
            }

            throw TsukiError.format("no image table (no record pair naming BLACK.mzp and BLUE.mzp)")
        }

        /// The picture-name lists: 32-byte records, BLACK then BLUE, CR LF at bytes 30..31, 0xFF after
        /// the last record; the one with one record per image record is the live list.
        private func findNameLists() throws {
            let span = data.bytes
            var first = [UInt8](repeating: 0, count: 32)
            let black = Array("BLACK".utf8)
            for (i, byte) in black.enumerated() { first[i] = byte }
            first[30] = 0x0D
            first[31] = 0x0A
            let blue = Array("BLUE".utf8)

            var lists: [(va: Int, count: Int)] = []
            for p in Self.indexOfAll(span, first) {
                guard p + 36 <= span.count, Array(span.slice(p + 32, 4)) == blue else { continue }
                var count = 0
                while p + 32 * count < span.count, span[p + 32 * count] != 0xFF { count += 1 }
                lists.append((data.va + p, count))
            }

            guard let live = lists.first(where: { $0.count == imageRecords + 1 }) else {
                let found = lists.map { String($0.count) }.joined(separator: ", ")
                throw TsukiError.format("no picture-name list with \(imageRecords + 1) records (found \(found))")
            }

            imageNames = live.va
            let old = lists.first(where: { $0.va != live.va })
            oldImageNames = old?.va ?? 0
            ok("ImageNames", live.va, live.count, .content, "\(live.count) records ending in 0xFF")
            ok("OldImageNames", old?.va ?? 0, old?.count ?? 0, .content, old == nil ? "none (optional)" : "\(old!.count) records")
        }

        /// The movie table: 0x30-byte records {i32 id = k, pad, char* "/app0/image/movie/..."}; ends
        /// with a negative id.
        private func findMovies() throws {
            let span = data.bytes
            for start in Self.indexOfAll(text.bytes, Array("/app0/image/movie/".utf8)) {
                if start > 0 && text.bytes[start - 1] != 0 { continue }
                let pointer = Self.leBytes(UInt64(text.va + start))
                for p in Self.indexOfAll(span, pointer) {
                    guard p >= 8, span.i32(p - 8) == 0 else { continue }
                    let va = data.va + p - 8
                    var count = 0
                    var names: [String] = []
                    while readable(va + 0x30 * count, 0x30), try i32(va + 0x30 * count) == count {
                        guard let address = intVa(try u64(va + 0x30 * count + 8)),
                              let path = asciiString(address, limit: 96),
                              path.hasPrefix("/app0/image/movie/") else {
                            throw TsukiError.format("movie record \(count) at 0x\(EbootLocator.hex(va + 0x30 * count)) has no movie path")
                        }
                        names.append(path)
                        count += 1
                    }

                    guard count >= 10, try i32(va + 0x30 * count) < 0 else {
                        throw TsukiError.format("movie table at 0x\(EbootLocator.hex(va)): \(count) records and no terminator")
                    }

                    movieTable = va
                    movieRecords = count
                    movieNames = names
                    let first = String(names[0].dropFirst(18))
                    let terminator = try i32(va + 0x30 * count)
                    ok("MovieTable", va, count, .content,
                       "\(count) records, terminator id \(terminator), first \(first)")
                    return
                }
            }

            throw TsukiError.format("no movie table (no record pointing at a /app0/image/movie/ path)")
        }

        /// The prologue ids: the four u32 (ids of prologue, prologue_en, prologue_zc, prologue_zt)
        /// somewhere in the text segment, once.
        private func findPrologue() throws {
            func movieId(_ name: String) throws -> Int {
                guard let index = movieNames.firstIndex(of: "/app0/image/movie/" + name + ".mp4") else {
                    throw TsukiError.format("the movie table has no \(name).mp4")
                }
                return index
            }

            let ids = [try movieId("prologue"), try movieId("prologue_en"), try movieId("prologue_zc"), try movieId("prologue_zt")]
            var pattern = [UInt8](repeating: 0, count: 16)
            for (k, id) in ids.enumerated() {
                let value = UInt32(truncatingIfNeeded: id)
                for b in 0..<4 { pattern[4 * k + b] = UInt8(truncatingIfNeeded: value >> (8 * b)) }
            }

            let hits = Self.indexOfAll(text.bytes, pattern)
            guard hits.count == 1 else {
                throw TsukiError.format(
                    "the prologue id table (\(ids.map(String.init).joined(separator: ", "))) occurs \(hits.count) times in the text segment")
            }

            prologue = text.va + hits[0]
            ok("PrologueTable", prologue, 4, .content, "ids \(ids.map(String.init).joined(separator: ", ")), unique")
        }

        /// The language suffix table: consecutive pointers to "ja", "en", "zc", "zt", "ko" in RELRO.
        private func findSuffixes() throws {
            let want = EbootLocator.expectedLanguageSuffixes.split(separator: " ").map(String.init)
            let span = relro.bytes
            let bytesPerEntry = 8
            var i = 0
            while i + bytesPerEntry * want.count <= span.count {
                var matches = true
                for k in 0..<want.count {
                    let pointer = span.u64(i + bytesPerEntry * k)
                    guard isStringPointer(pointer), let address = intVa(pointer),
                          asciiString(address, limit: 8) == want[k] else {
                        matches = false
                        break
                    }
                }
                if matches {
                    suffixes = relro.va + i
                    languageCount = want.count
                    ok("LanguageSuffixes", suffixes, want.count, .content, EbootLocator.expectedLanguageSuffixes)
                    return
                }
                i += bytesPerEntry
            }

            throw TsukiError.format("no language suffix table (five pointers to ja en zc zt ko)")
        }

        /// `ui_text`: in RELRO, one block of N string pointers per language, entry 0 of every block
        /// pointing at "NULL" (the Chinese and Korean blocks say "NULL " with a space). The stride
        /// between the first two gives N; the language count is the suffix table's.
        private func findUiText() throws {
            let span = relro.bytes
            var nulls: [Int] = []
            var i = 0
            while i + 8 <= span.count {
                let pointer = span.u64(i)
                if isStringPointer(pointer), let address = intVa(pointer),
                   let value = asciiString(address, limit: 8),
                   value.trimmingCharacters(in: .whitespaces) == "NULL" {
                    nulls.append(i)
                }
                i += 8
            }

            let languages = languageCount
            for a in 0..<nulls.count {
                for b in (a + 1)..<nulls.count {
                    let stride = nulls[b] - nulls[a]
                    guard stride % 8 == 0, stride >= 8 * 100 else { continue }
                    var blocks = true
                    if languages > 2 {
                        for k in 2..<languages {
                            if !nulls.contains(nulls[a] + k * stride) {
                                blocks = false
                                break
                            }
                        }
                    }
                    if !blocks { continue }

                    let count = stride / 8
                    for k in 0..<(languages * count) {
                        if !isStringPointer(span.u64(nulls[a] + 8 * k)) {
                            throw TsukiError.format("ui_text entry \(k) is not a string pointer")
                        }
                    }

                    uiText = relro.va + nulls[a]
                    uiTextCount = count
                    ok("UiText", uiText, count, .content, "\(languages) languages x \(count) strings, entry 0 = NULL")
                    return
                }
            }

            throw TsukiError.format("no ui_text table (\(nulls.count) pointers to \"NULL\" in RELRO, none \(languages) blocks apart)")
        }

        /// The UI texture registration tables: runs of 0x18-byte records {i32 0, i32 slot 0..4095,
        /// char* "name.mrg", i32 child -1..512, i32 -1 or 1} in the data and RELRO segments, each ended by
        /// a record that breaks the shape, in address order.
        private func findUiTables() throws {
            var tables: [(va: Int, count: Int)] = []
            for seg in [data, relro] {
                let length = seg.bytes.count
                var i = 0
                while i + 24 <= length {
                    if uiRecordOk(seg, i) {
                        var j = i
                        while uiRecordOk(seg, j) { j += 24 }
                        tables.append((seg.va + i, (j - i) / 24))
                        i = j + 24
                    } else {
                        i += 8
                    }
                }
            }

            tables.sort { $0.va < $1.va }
            guard tables.count >= 10 else {
                throw TsukiError.format("only \(tables.count) UI texture registration tables found")
            }

            uiTables = tables.map(\.va)
            let records = tables.reduce(0) { $0 + $1.count }
            ok("UiTables", tables[0].va, tables.count, .content, "\(tables.count) tables, \(records) records")
        }

        /// One UI texture registration record at `i` in `seg`: {0, slot 0..4095, char* "name.mrg",
        /// child -1..512, -1 or 1}.
        private func uiRecordOk(_ seg: Seg, _ i: Int) -> Bool {
            let span = seg.bytes
            guard i + 24 <= span.count else { return false }
            let state = span.i32(i)
            let slot = span.i32(i + 4)
            let pointer = span.u64(i + 8)
            let child = span.i32(i + 16)
            let child2 = span.i32(i + 20)
            guard state == 0, slot >= 0, slot <= 4095, child >= -1, child <= 512,
                  child2 == -1 || child2 == 1, isStringPointer(pointer) else {
                return false
            }
            guard let address = intVa(pointer), let name = asciiString(address, limit: 64) else { return false }
            return ImageCatalog.isFileName(name) && name.lowercased().hasSuffix(".mrg")
        }

        /// The sheets a UI registration table registers (the record names, lower case without the
        /// extension) and its record count.
        private func uiTableSheets(_ va: Int) throws -> (sheets: Set<String>, records: Int) {
            var sheets: Set<String> = []
            var n = 0
            while true {
                if (try i32(va + 24 * n + 4)) < 0 { break }
                let pointer = try u64(va + 24 * n + 8)
                guard let address = intVa(pointer), let name = asciiString(address, limit: 64),
                      name.count > 4 else { break }
                sheets.insert(String(name.dropLast(4)).lowercased())
                n += 1
            }
            return (sheets, n)
        }

        /// The first UI registration table (after `after`) that registers `sheet` with at least
        /// `minRecords` records.
        private func uiTableFor(_ sheet: String, _ minRecords: Int, after: Int = 0) throws -> Int {
            for va in uiTables where va > after {
                let (sheets, records) = try uiTableSheets(va)
                if sheets.contains(sheet), records >= minRecords { return va }
            }
            throw TsukiError.format("no UI registration table for \(sheet).mrg with \(minRecords) records")
        }

        // MARK: - Fonts

        /// The tag names ([heart], [heart2], [star] ...) are 11-byte records; the wide-grid bases follow
        /// them at the next even address.
        private func findFontTagsAndWideBase() throws {
            var pattern = [UInt8](repeating: 0, count: 33)
            for (i, byte) in Array("[heart]".utf8).enumerated() { pattern[i] = byte }
            for (i, byte) in Array("[heart2]".utf8).enumerated() { pattern[11 + i] = byte }
            for (i, byte) in Array("[star]".utf8).enumerated() { pattern[22 + i] = byte }

            let hits = Self.indexOfAll(text.bytes, pattern).map { text.va + $0 }
            var fontBlocks: [Int] = []
            for t in hits {
                let wide = Self.align(t + EbootFontData.tagStride * EbootFontData.tagCount, 2)
                guard readable(wide, 10) else { continue }
                var slotsOk = true
                for k in 0..<5 {
                    let slot = Int(try u16(wide + 2 * k))
                    if slot < 0x21 || slot > 0x61 { slotsOk = false; break }
                }
                guard slotsOk, lea.contains(t) else { continue }
                var hasRecord = false
                for k in 1...2 where glyphRecordOk(t - 10 * k) || glyphRecordOk(t - 10 * k - 6) {
                    hasRecord = true
                }
                if hasRecord { fontBlocks.append(t) }
            }

            guard fontBlocks.count == 1 else {
                throw TsukiError.format(
                    "the [tag] name block occurs \(hits.count) times, \(fontBlocks.count) of them followed by texture slots after glyph records")
            }

            fontTags = fontBlocks[0]
            fontWide = Self.align(fontTags + EbootFontData.tagStride * EbootFontData.tagCount, 2)
            var wide: [String] = []
            for k in 0..<5 { wide.append(String(try u16(fontWide + 2 * k))) }
            ok("FontTags", fontTags, EbootFontData.tagCount, .content,
               "[heart] [heart2] [star] ... (\(hits.count) copies, the one before the wide bases)")
            ok("FontWideBase", fontWide, 5, .anchored, "slots \(wide.joined(separator: ", "))")
        }

        private func glyphRecordOk(_ va: Int) -> Bool {
            guard readable(va, 10), let seg = segOf(va) else { return false }
            let record = seg.bytes.slice(seg.offset(va), 10)
            let slot = Int(record.u16(0))
            let x = Int(record.u16(2))
            let y = Int(record.u16(4))
            let w = Int(record.i16(6))
            let h = Int(record.u16(8))
            return slot >= 0x21 && slot <= 0x61 && x < 1024 && y < 512 && w >= 1 && w <= 128 && h == 73
        }

        /// The 17 glyph record tables lie back to back before the tag block; each starts where the code
        /// loads it (a lea target) and its first record is a glyph rectangle (slot 0x21..0x61, h = 73).
        private func findFontRecords() throws {
            let low = fontTags - 0x14000
            let starts = lea.filter { $0 >= low && $0 < fontTags && glyphRecordOk($0) }.sorted()
            guard starts.count == EbootLocator.recordNames.count else {
                throw TsukiError.format(
                    "\(starts.count) glyph record tables before the tag block, expected \(EbootLocator.recordNames.count)")
            }
            records = starts.enumerated().map {
                FontRecordSpec(name: EbootLocator.recordNames[$0.offset], va: $0.element, count: 0, leaSite: 0)
            }
        }

        /// A glyph lookup record at data offset `i`: {u64 key != 0, s16 index >= 0, 6 zero bytes}.
        private func lookupRecordOk(_ i: Int) -> Bool {
            let span = data.bytes
            return i + 16 <= span.count
                && span.u16(i + 10) == 0 && span.u32(i + 12) == 0
                && span.i16(i + 8) >= 0 && span.u64(i) != 0
        }

        /// The 16 lookup tables: one contiguous run of 16-byte records {u64 key, s16 index, 6 zero
        /// bytes} in the data segment, split where the code loads a table (lea targets), each piece
        /// sorted by key with indices a permutation of 0..n-1.
        private func findFontLookups() throws {
            guard !records.isEmpty else {
                throw TsukiError.format("the glyph record tables were not found, so the lookups cannot be named")
            }

            let span = data.bytes
            let length = span.count
            var bestStart = 0
            var bestEnd = 0
            var i = 0
            while i + 16 <= length {
                if lookupRecordOk(i) {
                    var j = i
                    while lookupRecordOk(j) { j += 16 }
                    if (j - i) / 16 >= 1000 && j - i > bestEnd - bestStart {
                        bestStart = data.va + i
                        bestEnd = data.va + j
                    }
                    i = j + 16
                } else {
                    i += 8
                }
            }

            guard bestEnd != 0 else {
                throw TsukiError.format("no run of glyph lookup records in the data segment")
            }

            let starts = lea.filter { $0 >= bestStart && $0 < bestEnd }.sorted()
            var pieces: [(va: Int, count: Int)] = []
            for (k, a) in starts.enumerated() {
                let b = k + 1 < starts.count ? starts[k + 1] : bestEnd
                let n = (b - a) / 16
                var indices = [Int](repeating: 0, count: n)
                var previous: UInt64 = 0
                for e in 0..<n {
                    let key = try u64(a + 16 * e)
                    if e > 0 && key <= previous {
                        throw TsukiError.format(
                            "glyph lookup table at 0x\(EbootLocator.hex(a)): keys not strictly increasing at entry \(e)")
                    }
                    previous = key
                    indices[e] = Int(try i16(a + 16 * e + 8))
                }

                indices.sort()
                for (e, value) in indices.enumerated() where value != e {
                    throw TsukiError.format(
                        "glyph lookup table at 0x\(EbootLocator.hex(a)): indices are not a permutation of 0..\(n - 1)")
                }
                pieces.append((a, n))
            }

            guard pieces.count == EbootLocator.lookupNames.count else {
                throw TsukiError.format(
                    "\(pieces.count) glyph lookup tables in the run at 0x\(EbootLocator.hex(bestStart)), expected \(EbootLocator.lookupNames.count)")
            }

            lookups = pieces.enumerated().map {
                FontLookupSpec(name: EbootLocator.lookupNames[$0.offset], va: $0.element.va, count: $0.element.count, leaSite: 0)
            }
            let entries = pieces.reduce(0) { $0 + $1.count }
            ok("FontLookups", bestStart, pieces.count, .content,
               "\(pieces.count) sorted permutation tables, \(entries) entries")

            // Record counts: the feeding lookup, capped by the gap to the next table (fonts.md 5.3).
            func lookupCount(_ name: String) throws -> Int {
                guard let lookup = lookups.first(where: { $0.name == name }) else {
                    throw TsukiError.format("glyph lookup table \(name) was not found")
                }
                return lookup.count
            }

            var measured: [FontRecordSpec] = []
            for (k, record) in records.enumerated() {
                let next = k + 1 < records.count ? records[k + 1].va : fontTags
                let language = String(record.name.prefix(2))
                let suffix = String(record.name.dropFirst(3))
                let feedName = suffix == "s0" ? "narrow" : (suffix == "s2" ? language + "_s2" : language + "_s1")
                let feed = try lookupCount(feedName)
                let gap = (next - record.va) / 10
                let count = min(feed, gap)
                guard count >= 1 else {
                    throw TsukiError.format("glyph record table \(record.name) at 0x\(EbootLocator.hex(record.va)) has no room for a record")
                }
                measured.append(FontRecordSpec(name: record.name, va: record.va, count: count, leaSite: 0))
            }

            records = measured
            let total = records.reduce(0) { $0 + $1.count }
            ok("FontRecords", records[0].va, records.count, .content, "\(records.count) tables, \(total) records")
        }

        // MARK: - Engine tables (text)

        /// The 14 config SE test names: inline 13-byte strings "moon_se%05d".
        private func findTestSe() throws {
            let span = text.bytes
            for p in Self.indexOfAll(span, Array("moon_se".utf8)) {
                if p > 0 && span[p - 1] != 0 { continue }
                var n = 0
                while p + 13 * (n + 1) <= span.count,
                      let name = asciiString(text.va + p + 13 * n, limit: 13),
                      name.count == 12, name.hasPrefix("moon_se") {
                    n += 1
                }
                if n >= 10 {
                    testSe = text.va + p
                    ok("TestSeNames", testSe, n, .content, "\(n) names")
                    return
                }
            }

            throw TsukiError.format("no block of moon_se names")
        }

        /// The config voice row words follow the test SE names after a few C strings and zero padding:
        /// i32 F word numbers.
        private func findRowWords() throws {
            var va = testSe + 13 * TestSeNames.count
            while !(try u8(va) == 0 && u8(va + 1) == 0) { va += 1 }
            while (try u8(va)) == 0 { va += 1 }

            for k in 0..<VoiceSpeakerTable.rowCount {
                let word = Int(try i32(va + 4 * k))
                if word < 0 || word > 1199 {
                    throw TsukiError.format("voice row word \(k) = \(word) is not an F word number")
                }
            }

            rowWords = va
            ok("VoiceRowWords", va, VoiceSpeakerTable.rowCount, .anchored, "after the test SE names")
        }

        /// The voice speaker records: {char[8] key, i32 speaker, i32 0}, the first key "ZZZ", keys
        /// reversed three-letter prefixes.
        private func findVoiceSpeakers() throws {
            let span = text.bytes
            var first = [UInt8](repeating: 0, count: 16)
            for (i, byte) in Array("ZZZ".utf8).enumerated() { first[i] = byte }
            for p in Self.indexOfAll(span, first) {
                var n = 0
                while p + 16 * (n + 1) <= span.count {
                    let record = span.slice(p + 16 * n, 16)
                    var key = record[3] == 0
                    for i in 4..<8 where record[i] != 0 { key = false }
                    for i in 0..<3 {
                        let byte = Int(record[i])
                        if !((0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte)) { key = false }
                    }
                    let speaker = record.i32(8)
                    if !key || record.i32(12) != 0 || speaker < 0 || speaker > 63 { break }
                    n += 1
                }

                if n >= 20 {
                    voice = text.va + p
                    voiceRecords = n
                    ok("VoiceSpeakers", voice, n, .content, "\(n) records, ZZZ first")
                    return
                }
            }

            throw TsukiError.format("no voice speaker table (records keyed ZZZ, 00A, ...)")
        }

        /// A -1-terminated i16 list of F word numbers (0..1199) at `va`, or nil.
        private func fWordList(_ va: Int) throws -> [Int]? {
            var list: [Int] = []
            while true {
                let value = Int(try i16(va + 2 * list.count))
                if value == -1 { return list.isEmpty ? nil : list }
                if value < 0 || value > 1199 || list.count > 2000 { return nil }
                list.append(value)
            }
        }

        /// The first 16-aligned address at or after `va` whose zero padding ends at or after it: the
        /// next table after a gap of zero bytes.
        private func afterZeroGap(_ va: Int) throws -> Int {
            var p = va
            while (try u8(p)) == 0 { p += 1 }
            return max(p / 16 * 16, va)
        }

        /// The history-record keep lists and the scene-id table follow the voice speakers: words (first
        /// entry F000), the -1-terminated scene ids, bits, bytes, each after a gap of zero bytes.
        private func findHistoryListsAndSceneIds() throws {
            let words = try afterZeroGap(voice + 16 * voiceRecords)
            guard let wordList = try fWordList(words) else {
                throw TsukiError.format("no F word list after the voice speakers at 0x\(EbootLocator.hex(words))")
            }
            let scenes = words + 2 * (wordList.count + 1)
            var ids: [Int16] = []
            while (try i16(scenes + 2 * ids.count)) != -1 {
                let id = try i16(scenes + 2 * ids.count)
                if id <= 0 || ids.count > 4000 {
                    throw TsukiError.format("scene id \(ids.count) = \(id) at 0x\(EbootLocator.hex(scenes)) is not positive")
                }
                ids.append(id)
            }

            let distinct = Set(ids).count
            guard ids.count >= 100, distinct == ids.count else {
                throw TsukiError.format("the scene-id table at 0x\(EbootLocator.hex(scenes)) has \(ids.count) ids, \(distinct) distinct")
            }

            let bits = try afterZeroGap(scenes + 2 * (ids.count + 1))
            guard let bitList = try fWordList(bits) else {
                throw TsukiError.format("no F bit list at 0x\(EbootLocator.hex(bits))")
            }
            let byteVa = try afterZeroGap(bits + 2 * (bitList.count + 1))
            guard let byteList = try fWordList(byteVa) else {
                throw TsukiError.format("no F byte list at 0x\(EbootLocator.hex(byteVa))")
            }

            historyKeep = [words, byteVa, bits]
            sceneIds = scenes
            sceneCount = ids.count
            sceneIdList = ids

            // The flowchart node table covers the story scripts: those whose scene id is below 3000
            // (the utility scripts START, ARCHIVE, QACALL, STAFFROLL, TEST and the JUMP scripts have
            // ids 3000 and up), minus script 0.
            var story = 0
            while story < ids.count && ids[story] < 3000 { story += 1 }
            sceneNodeCount = story - 1
            ok("HistoryKeepLists", words, wordList.count + bitList.count + byteList.count, .anchored,
               "words \(wordList.count), bits \(bitList.count), bytes \(byteList.count)")
            ok("SceneIds", scenes, ids.count, .content, "\(ids.count) distinct ids, -1 terminated; \(story) story scripts")
        }

        /// The flow-jump copy of the keep lists holds the same words as the history copy; the bytes and
        /// bits follow it after zero gaps.
        private func findFlowJumpLists() throws {
            guard let words = try fWordList(historyKeep[0]) else {
                throw TsukiError.format("no keep-word list at the history copy")
            }
            var pattern = [UInt8](repeating: 0, count: 2 * (words.count + 1))
            for (k, word) in words.enumerated() {
                pattern[2 * k] = UInt8(truncatingIfNeeded: word)
                pattern[2 * k + 1] = UInt8(truncatingIfNeeded: word >> 8)
            }
            pattern[2 * words.count] = 0xFF
            pattern[2 * words.count + 1] = 0xFF

            let hits = Self.indexOfAll(text.bytes, pattern).map { text.va + $0 }
                .filter { $0 != historyKeep[0] }
            guard hits.count == 1 else {
                throw TsukiError.format(
                    "the keep-word list occurs \(hits.count + 1) times in the text segment, expected twice")
            }

            let fw = hits[0]
            let byteVa = try afterZeroGap(fw + pattern.count)
            guard let byteList = try fWordList(byteVa) else {
                throw TsukiError.format("no flow-jump byte list at 0x\(EbootLocator.hex(byteVa))")
            }
            let bits = try afterZeroGap(byteVa + 2 * (byteList.count + 1))
            guard let bitList = try fWordList(bits) else {
                throw TsukiError.format("no flow-jump bit list at 0x\(EbootLocator.hex(bits))")
            }
            guard let historyBytes = try fWordList(historyKeep[1]),
                  let historyBits = try fWordList(historyKeep[2]) else {
                throw TsukiError.format("the history keep lists are unreadable")
            }
            guard byteList == historyBytes, bitList == historyBits else {
                throw TsukiError.format("the flow-jump keep lists differ from the history copy")
            }

            flowKeep = [fw, byteVa, bits]
            ok("FlowJumpKeepLists", fw, words.count + byteList.count + bitList.count, .content,
               "equal to the history copy")
        }

        private func cellsOk(_ va: Int, _ count: Int, _ sizes: Bool) throws -> Bool {
            for k in 0..<count {
                guard readable(va + 8 * k, 8) else { return false }
                let a = Int(try i16(va + 8 * k))
                let b = Int(try i16(va + 8 * k + 2))
                let c = Int(try i16(va + 8 * k + 4))
                let e = Int(try i16(va + 8 * k + 6))
                let ok: Bool
                if sizes {
                    ok = a >= 0 && a <= 4096 && b >= 0 && b <= 4096 && c >= 0 && c <= 4096 && e >= 0 && e <= 4096
                } else {
                    ok = a >= 0 && a <= c && c <= 4096 && b >= 0 && b <= e && e <= 4096
                }
                if !ok { return false }
            }
            return true
        }

        /// A cell table anchored at a fixed offset from a found table; the position is kept only when
        /// its cells validate.
        private func anchoredCells(_ name: String, _ anchor: Int, _ offset: Int, _ count: Int, _ sizes: Bool) throws -> Int {
            let va = anchor + offset
            guard try cellsOk(va, count, sizes) else {
                throw TsukiError.format(
                    "\(name): the \(count) cells at 0x\(EbootLocator.hex(va)) (anchor 0x\(EbootLocator.hex(anchor)) "
                        + "\(offset >= 0 ? "+" : "-") 0x\(EbootLocator.hex(abs(offset))) are not texel rectangles")
            }
            ok(name, va, count, .anchored,
               "anchor 0x\(EbootLocator.hex(anchor)) \(offset >= 0 ? "+" : "-") 0x\(EbootLocator.hex(abs(offset)))")
            return va
        }

        /// The flowchart title and connector cells sit just before the flow-jump keep lists.
        private func findFlowCells() throws {
            let fw = flowKeep[0]
            flowTitle = [
                try anchoredCells("FlowTitleCells[0]", fw, -0x370, 30, true),
                try anchoredCells("FlowTitleCells[1]", fw, -0x280, 30, true),
            ]
            flowLine = try anchoredCells("FlowLineCells", fw, -0x190, 12, true)
        }

        /// The haze table: entry 0 is 40 zero bytes, entry 1 the default parameters
        /// (1, 1, 1, 1, 1, 1, 2, 1, 1, 0); it runs while the entries are finite floats.
        private func findHaze() throws {
            var pattern = [UInt8](repeating: 0, count: 80)
            for (k, value) in [Float(1), 1, 1, 1, 1, 1, 2, 1, 1, 0].enumerated() {
                let bits = value.bitPattern
                for b in 0..<4 {
                    pattern[40 + 4 * k + b] = UInt8(truncatingIfNeeded: bits >> (8 * b))
                }
            }

            let hits = Self.indexOfAll(text.bytes, pattern)
            guard hits.count == 1 else {
                throw TsukiError.format("the haze table head (zero entry, default entry) occurs \(hits.count) times")
            }

            let va = text.va + hits[0]
            var n = 0
            while readable(va + 40 * n, 40) {
                var finite = true
                for k in 0..<10 {
                    if !Self.finite(try f32(va + 40 * n + 4 * k)) {
                        finite = false
                        break
                    }
                }
                if !finite { break }
                n += 1
            }

            guard n >= 100 else {
                throw TsukiError.format("the haze table at 0x\(EbootLocator.hex(va)) has only \(n) entries")
            }

            haze = va
            hazeEntries = n
            ok("Haze", va, n, .content, "\(n) entries of 10 floats")
        }

        private func windowRecordOk(_ va: Int) -> Bool {
            guard readable(va, 12), let seg = segOf(va) else { return false }
            let record = seg.bytes.slice(seg.offset(va), 12)
            let slot = record.u32(0)
            let x = record.f32(4)
            let y = record.f32(8)
            return slot < 4096 && Self.finite(x) && Self.finite(y)
                && abs(x) < 4096 && abs(y) < 4096 && (slot != 0 || x != 0 || y != 0)
        }

        /// The message window cluster: the six soft-clip radii (10, 32, 40, 64, 128, 256 as floats),
        /// then at the next 16-byte boundaries the 27 x offsets, the 37 y offsets and the window types
        /// {u32 slot, f32 x, f32 y} whose first slots count up by one.
        private func findWindowCluster() throws {
            var pattern = [UInt8](repeating: 0, count: 24)
            for (k, value) in [Float(10), 32, 40, 64, 128, 256].enumerated() {
                let bits = value.bitPattern
                for b in 0..<4 {
                    pattern[4 * k + b] = UInt8(truncatingIfNeeded: bits >> (8 * b))
                }
            }

            let hits = Self.indexOfAll(text.bytes, pattern)
            guard hits.count == 1 else {
                throw TsukiError.format("the soft-clip radii occur \(hits.count) times")
            }

            radii = text.va + hits[0]
            dx = Self.align(radii + 24, 16)
            dy = Self.align(dx + 4 * MessageWindowTable.dxCount, 16)
            let windowsVa = Self.align(dy + 4 * MessageWindowTable.dyCount, 16)
            let first = try u32(windowsVa)
            for k in 0..<20 {
                guard windowRecordOk(windowsVa + 12 * k), (try u32(windowsVa + 12 * k)) == first + UInt32(k) else {
                    throw TsukiError.format("no window type table at 0x\(EbootLocator.hex(windowsVa)) (record \(k) breaks the slot sequence)")
                }
            }

            var n = 0
            while windowRecordOk(windowsVa + 12 * n) { n += 1 }

            for k in 0..<(MessageWindowTable.dxCount + MessageWindowTable.dyCount) {
                if !Self.finite(try f32(dx + 4 * k)) {
                    throw TsukiError.format("window offset \(k) is not a finite float")
                }
            }

            windows = windowsVa
            windowCount = n
            ok("ClipRadii", radii, 6, .content, "10 32 40 64 128 256")
            ok("WindowDx", dx, MessageWindowTable.dxCount, .anchored, "after the radii")
            ok("WindowDy", dy, MessageWindowTable.dyCount, .anchored, "after the x offsets")
            ok("WindowTypes", windows, n, .content, "\(n) records, slots from \(first)")
        }

        private func fclnKeyOk(_ va: Int) -> Bool {
            guard readable(va, 36), let seg = segOf(va) else { return false }
            let record = seg.bytes.slice(seg.offset(va), 36)
            let time = Int(record.i32(0))
            if time == -1 {
                for k in 1...8 where record.i32(4 * k) != -1 { return false }
                return true
            }

            let cx = Int(record.i32(4))
            let cy = Int(record.i32(8))
            let r0 = Int(record.i32(12))
            let r1 = Int(record.i32(16))
            let c0 = Int(record.i32(20))
            let c1 = Int(record.i32(24))
            let alpha = Int(record.i32(28))
            let reroll = Int(record.i32(32))
            return time >= 0 && time <= 600_000 && cx >= -2000 && cx <= 2000 && cy >= -2000 && cy <= 2000
                && r0 >= 0 && r0 <= 4000 && r1 >= 0 && r1 <= 4000 && c0 >= 0 && c0 <= 4000 && c1 >= 0 && c1 <= 4000
                && alpha >= 0 && alpha <= 255 && reroll >= 0 && reroll <= 600_000
        }

        /// The focus-line keys: 30 x 4 records of 9 i32 loaded by the code (a lea target); the first key
        /// at time 0 with a centre on the screen, a visible alpha and an outer radius; at least 30 keys
        /// used and at least 10 unused (all -1).
        private func findFclnLines() throws {
            let n = FclnLineTable.effects * FclnLineTable.keysPerEffect
            for t in leaTargetsIn(text) {
                guard readable(t, 36 * n), try i32(t) == 0, try i32(t + 4) >= 100,
                      try i32(t + 16) > 0, try i32(t + 28) >= 100 else { continue }

                var used = 0
                for k in 0..<n {
                    if (try i32(t + 36 * k)) != -1 { used += 1 }
                }
                var valid = true
                for k in 0..<n {
                    if !fclnKeyOk(t + 36 * k) {
                        valid = false
                        break
                    }
                }
                if used >= 30 && n - used >= 10 && valid {
                    fcln = t
                    ok("FclnLines", t, n, .content, "\(n) keys, \(used) used")
                    return
                }
            }

            throw TsukiError.format("no focus-line key table (120 keys of 9 ints at a code reference)")
        }

        private func edgeFlag(_ value: Int) -> Bool { value == -1 || (value >= 500 && value <= 1300) }

        private func edgeOk(_ va: Int) -> Bool {
            guard readable(va, 48), let seg = segOf(va) else { return false }
            let record = seg.bytes.slice(seg.offset(va), 48)
            let from = Int(record.i32(0))
            let to = Int(record.i32(4))
            guard from >= 0, from < 2000, to >= 0, to < 2000 else { return false }
            for k in 2..<12 where !edgeFlag(Int(record.i32(4 * k))) { return false }
            return true
        }

        /// The flowchart edge cluster: the 48-byte edges {from, to, 10 flag ids} at a code reference, the
        /// scene-node table right after them, and before them (after zero padding) the 12-byte choice
        /// flag triples and the 8-byte trophy scene pairs {scene, -1}.
        private func findEdgeCluster() throws {
            for t in leaTargetsIn(text) {
                var first600 = true
                for k in 0..<600 where !edgeOk(t + 48 * k) {
                    first600 = false
                    break
                }
                if !first600 { continue }

                var n = 0
                while edgeOk(t + 48 * n) { n += 1 }
                edges = t
                edgeCount = n
                sceneNodes = t + 48 * n
                guard sceneNodeCount >= 100 else {
                    throw TsukiError.format(
                        "the scene-node table at 0x\(EbootLocator.hex(sceneNodes)) (\(sceneNodeCount) entries) holds values that are not node indices")
                }
                for k in 0..<sceneNodeCount {
                    let value = Int(try i32(sceneNodes + 4 * k))
                    if value < -1 || value > 4000 {
                        throw TsukiError.format(
                            "the scene-node table at 0x\(EbootLocator.hex(sceneNodes)) (\(sceneNodeCount) entries) holds values that are not node indices")
                    }
                }

                var end = t
                while (try u32(end - 4)) == 0 { end -= 4 }

                var triples = 0
                while true {
                    var triple = true
                    for k in 0..<3 {
                        if !edgeFlag(Int(try i32(end - 12 * (triples + 1) + 4 * k))) {
                            triple = false
                            break
                        }
                    }
                    if !triple { break }
                    triples += 1
                }

                guard triples >= 10 else {
                    throw TsukiError.format("only \(triples) choice flag triples before the edges at 0x\(EbootLocator.hex(t))")
                }

                choice = end - 12 * triples
                choiceCount = triples
                end = choice
                while (try u32(end - 4)) == 0 { end -= 4 }

                var pairs = 0
                while true {
                    let scene = Int(try i32(end - 8 * (pairs + 1)))
                    let minusOne = try i32(end - 8 * (pairs + 1) + 4)
                    if minusOne == -1 && scene >= 0 && scene < 2000 {
                        pairs += 1
                    } else {
                        break
                    }
                }

                guard pairs >= 5 else {
                    throw TsukiError.format("only \(pairs) trophy scene pairs before the choice flags at 0x\(EbootLocator.hex(choice))")
                }

                trophy = end - 8 * pairs
                trophyCount = pairs
                ok("FlowEdges", t, n, .content, "\(n) edges")
                ok("SceneNodes", sceneNodes, sceneNodeCount, .anchored, "after the edges, \(sceneNodeCount) story scripts")
                ok("ChoiceFlags", choice, triples, .anchored, "\(triples) triples before the edges")
                ok("TrophyScenes", trophy, pairs, .anchored, "\(pairs) pairs before the choice flags")
                return
            }

            throw TsukiError.format("no flowchart edge table (600 records of {from, to, flags} at a code reference)")
        }

        /// The six title background indices sit right before the string "caution_ja.mzp".
        private func findTitleBackground() throws {
            let hits = Self.indexOfAll(text.bytes, Array("caution_ja.mzp\0".utf8))
            guard hits.count == 1 else {
                throw TsukiError.format("the string caution_ja.mzp occurs \(hits.count) times")
            }

            let va = text.va + hits[0] - 24
            var values: [Int] = []
            for k in 0..<6 {
                values.append(Int(try i32(va + 4 * k)))
            }
            guard values.allSatisfy({ $0 >= 0 && $0 <= 15 }) else {
                throw TsukiError.format(
                    "the six words before caution_ja.mzp (\(values.map(String.init).joined(separator: ", "))) are not title background indices")
            }

            titleBg = va
            ok("TitleBackground", va, 6, .anchored, values.map(String.init).joined(separator: " "))
        }

        /// The motion tables: the keyframe end indices are the longest run of non-decreasing i64 (at a
        /// code reference) in the text segment; the durations are the same number of i64 right before
        /// them, the field masks (one more word) before those.
        private func findMotionTables() throws {
            var bestVa = 0
            var bestCount = 0
            for t in leaTargetsIn(text) {
                var n = 0
                var previous: Int64 = 0
                while readable(t + 8 * n, 8) {
                    let value = try i64(t + 8 * n)
                    if value < previous || value > 500_000 { break }
                    previous = value
                    n += 1
                }
                if n >= 20_000 && n > bestCount {
                    bestVa = t
                    bestCount = n
                }
            }

            guard bestCount > 0 else {
                throw TsukiError.format("no keyframe end-index table (a run of at least 20,000 non-decreasing words)")
            }

            ends = bestVa
            motionCount = bestCount
            let last = try i64(ends + 8 * (bestCount - 1))
            guard let count = Int(exactly: last) else {
                throw TsukiError.format("the last keyframe end index is not a count")
            }
            keyCount = count
            durations = ends - 8 * bestCount
            masks = durations - 8 * (bestCount + 1)
            guard lea.contains(durations), lea.contains(masks) else {
                throw TsukiError.format(
                    "the durations (0x\(EbootLocator.hex(durations))) or the masks (0x\(EbootLocator.hex(masks))) before the end indices are not referenced by code")
            }

            for k in 0..<bestCount {
                let duration = try i64(durations + 8 * k)
                if duration < 0 || duration > 36_000_000 {
                    throw TsukiError.format("motion \(k + 1): duration \(duration) ms")
                }
            }

            if (try u64(masks)) != 0 {
                throw TsukiError.format("field mask 0 is not zero")
            }

            ok("MotionEnds", ends, bestCount, .content, "\(bestCount) motions, \(keyCount) keyframes")
            ok("MotionDurations", durations, bestCount, .anchored, "before the end indices")
            ok("MotionMasks", masks, bestCount + 1, .anchored, "before the durations")
        }

        /// The keyframes: 72-byte records at a code reference in the data segment, record 0 at time 0,
        /// every time non-negative and bounded.
        private func findMotionKeys() throws {
            for t in leaTargetsIn(data) {
                guard readable(t, 72 * keyCount), try i64(t) == 0 else { continue }
                var valid = true
                for k in 0..<keyCount {
                    let time = try i64(t + 72 * k)
                    if time < 0 || time > 10_000_000 {
                        valid = false
                        break
                    }
                }
                if valid {
                    keys = t
                    ok("MotionKeys", t, keyCount, .content, "\(keyCount) keyframes of 72 bytes")
                    return
                }
            }

            throw TsukiError.format("no keyframe table (\(keyCount) records of 72 bytes at a code reference in the data segment)")
        }

        private func configPageOk(_ va: Int) -> Bool {
            guard readable(va, ConfigPageTable.stride), let seg = segOf(va) else { return false }
            let page = seg.bytes.slice(seg.offset(va), ConfigPageTable.stride)
            let first = Int(page.i32(0))
            let last = Int(page.i32(4))
            let minOne = Int(page.i32(8))
            let rows = Int(page.i32(12))
            guard first >= 0, last >= first, last < 500, minOne == -1, rows >= 0, rows <= 26 else { return false }
            for r in 0..<rows {
                let value = Int(page.i32(16 + 4 * r))
                if value < 0 || value > 5 { return false }
            }
            return true
        }

        /// The two config pages: 0x9D0-byte pages {i32 first item, i32 last, -1, row count, per-row
        /// control counts ...}, the first page with more than five rows.
        private func findConfigPages() throws {
            var va = data.va
            while va + 2 * ConfigPageTable.stride <= data.end {
                if (try i32(va + 12)) > 5, configPageOk(va), configPageOk(va + ConfigPageTable.stride) {
                    config = va
                    voiceFace = try anchoredCells("VoiceFaceCells", va, -480, 20, false)
                    voiceName = [
                        try anchoredCells("VoiceNameCells[0]", va, -320, 20, false),
                        try anchoredCells("VoiceNameCells[1]", va, -160, 20, false),
                    ]
                    let firstItem = try i32(va)
                    let lastItem = try i32(va + 4)
                    let firstRows = try i32(va + 12)
                    let secondRows = try i32(va + ConfigPageTable.stride + 12)
                    ok("ConfigPages", va, 2, .content,
                       "items \(firstItem)..\(lastItem), \(firstRows) and \(secondRows) rows")
                    return
                }
                va += 16
            }

            throw TsukiError.format("no config page pair (0x9D0-byte pages with item ids and row counts)")
        }

        /// The seen-index map: {char* name, i32 -1, i32 seen} records whose seen indices count up from
        /// the 2700s; the speaker row bits sit 0x1E0 before it.
        private func findSeenMapAndRowBits() throws {
            var va = data.va
            while va + 32 <= data.end {
                let pointer = try u64(va)
                let seenIndex: Int
                if isStringPointer(pointer), try i32(va + 8) == -1 {
                    seenIndex = Int(try i32(va + 12))
                } else {
                    va += 8
                    continue
                }

                guard seenIndex >= 2000, seenIndex <= 6000, isStringPointer(try u64(va + 16)),
                      try i32(va + 24) == -1, try i32(va + 28) == seenIndex + 1 else {
                    va += 8
                    continue
                }

                var n = 0
                while (try u64(va + 16 * n)) != 0 {
                    if !isStringPointer(try u64(va + 16 * n)) {
                        throw TsukiError.format("seen-map record \(n) has no name")
                    }
                    n += 1
                }

                seen = va
                let bits = va - 0x1E0
                for k in 0..<VoiceSpeakerTable.speakerCount {
                    let bit = Int(try i32(bits + 4 * k))
                    if bit <= 0 || (bit & (bit - 1)) != 0 {
                        throw TsukiError.format(
                            "speaker row bit \(k) = 0x\(EbootLocator.hex(bit)) is not a power of two (0x\(EbootLocator.hex(bits)))")
                    }
                }

                rowBits = bits
                ok("SeenMap", va, n, .content, "\(n) records, seen indices from \(seenIndex)")
                ok("VoiceRowBits", bits, VoiceSpeakerTable.speakerCount, .anchored, "0x1E0 before the seen map, powers of two")
                return
            }

            throw TsukiError.format("no seen-index map ({name, -1, seen} records with ascending seen indices)")
        }

        /// The three falling-note records (0x58 bytes: u16 image, u16 frames 1..24, the frame order,
        /// i16 w h step, six floats, i32 floor).
        private func findFclnNotes() throws {
            let stride = FclnNoteTable.stride

            func noteOk(_ va: Int) -> Bool {
                guard readable(va, stride), let seg = segOf(va) else { return false }
                let record = seg.bytes.slice(seg.offset(va), stride)
                let image = Int(record.u16(0))
                let frames = Int(record.u16(2))
                let w = Int(record.i16(0x36))
                let h = Int(record.i16(0x38))
                let step = Int(record.i16(0x3A))
                let floor = Int(record.i32(0x54))
                guard image > 0, image < 1000, frames >= 1, frames <= 24,
                      w >= 1, w <= 1024, h >= 1, h <= 1024, step >= 1, step <= 60,
                      floor > 0, floor <= 1080 else {
                    return false
                }
                for f in 0..<frames {
                    let value = Int(record.i16(4 + 2 * f))
                    if value < 0 || value >= 24 { return false }
                }
                for k in 0..<6 where !Self.finite(record.f32(0x3C + 4 * k)) {
                    return false
                }
                return true
            }

            var va = data.va
            while va + 3 * stride <= data.end {
                if noteOk(va), noteOk(va + stride), noteOk(va + 2 * stride) {
                    notes = va
                    let firstFrames = try u16(va + 2)
                    let secondFrames = try u16(va + stride + 2)
                    let thirdFrames = try u16(va + 2 * stride + 2)
                    ok("FclnNotes", va, 3, .content,
                       "frames \(firstFrames), \(secondFrames), \(thirdFrames)")
                    return
                }
                va += 8
            }

            throw TsukiError.format("no falling-note records")
        }

        /// The banner keys and rectangles sit 0xB0 before the effect registration table; the other data
        /// cells at fixed offsets from their sheet's registration table.
        private func findBannerAndDataCells() throws {
            let effect = try uiTableFor("border_parts", 20)
            let keysVa = effect - 0xB0
            for k in 0..<20 {
                let value = try f32(keysVa + 4 * k)
                if !Self.finite(value) || value < -1 || value > 4 {
                    throw TsukiError.format("banner key \(k) = \(value) is not a scale (0x\(EbootLocator.hex(keysVa)))")
                }
            }

            bannerKeys = keysVa
            ok("BannerKeys", keysVa, 10, .anchored, "0xB0 before the effect registration table")
            bannerRects = [
                try anchoredCells("BannerRects[0]", keysVa, 80, 1, false),
                try anchoredCells("BannerRects[1]", keysVa, 96, 1, false),
            ]
            let menu = try uiTableFor("menu_parts", 10)
            guideIcon = try anchoredCells("GuideIconCells", menu, -0x660, 23, false)
            guideWord = try anchoredCells("GuideWordCells", menu, -0x5A0, 27 * 5, false)
            let menu2 = try uiTableFor("menu_parts", 5, after: menu)

            phaseTitle = [
                try anchoredCells("PhaseTitleCells[0]", menu2, 0x350, 38, false),
                try anchoredCells("PhaseTitleCells[1]", menu2, 0x480, 38, false),
                try anchoredCells("PhaseTitleCells[2]", menu2, 0x5B0, 38, false),
            ]
            let save = try uiTableFor("save_parts", 5)
            saveTitle = [
                try anchoredCells("SaveTitleCells[0]", save, 0x2C0, 38, false),
                try anchoredCells("SaveTitleCells[1]", save, 0x3F0, 38, false),
            ]
        }

        private func musicOk(_ va: Int) -> Bool {
            guard readable(va, 0x38), let seg = segOf(va) else { return false }
            let record = seg.bytes.slice(seg.offset(va), 0x38)
            let v = (0..<14).map { Int(record.i32(4 * $0)) }
            guard v[0] >= 0, v[0] < 300, v[1] >= 1, v[1] <= 2000 else { return false }
            for k in 2..<6 where !(v[k] == -1 || (v[k] >= 1 && v[k] <= 2000)) { return false }
            guard v[6] >= 0, v[6] <= 3_600_000, v[7] >= 0, v[7] <= v[8], v[8] <= 48000 * 1200 else { return false }
            for k in 9..<14 where !(v[k] == -1 || (v[k] >= 0 && v[k] < 300)) { return false }
            return true
        }

        /// The music room records: 0x38 bytes {bgm, title id, 4 credit ids, length, loop start, loop
        /// end, 5 variants} at a code reference, at least 50 in a row.
        private func findMusic() throws {
            for t in leaTargetsIn(text) {
                var first50 = true
                for k in 0..<50 where !musicOk(t + 0x38 * k) {
                    first50 = false
                    break
                }
                if !first50 { continue }

                var n = 0
                while musicOk(t + 0x38 * n) { n += 1 }
                music = t
                musicCount = n
                ok("Music", t, n, .content, "\(n) tracks")
                return
            }

            throw TsukiError.format("no music room table (50 records of {bgm, title, credits, length, loop, variants})")
        }

        private func extraOk(_ va: Int) -> Bool {
            guard readable(va, 20), let seg = segOf(va) else { return false }
            let record = seg.bytes.slice(seg.offset(va), 20)
            let scriptScene = Int(record.i32(0))
            let flowScene = Int(record.i32(4))
            let unlockA = Int(record.i32(8))
            let unlockB = Int(record.i32(12))
            let message = Int(record.i32(16))
            return scriptScene >= 900 && scriptScene <= 1200
                && flowScene >= 400 && flowScene <= 700
                && (unlockA == -1 || (unlockA >= 0 && unlockA < 2000))
                && (unlockB == -1 || (unlockB >= 0 && unlockB < 2000))
                && message >= 0 && message < 100
        }

        /// The ending-list records: 20 bytes {script scene 1000.., flow scene 533.., two unlock scenes,
        /// help message index} at a code reference, at least 20 in a row.
        private func findExtras() throws {
            for t in leaTargetsIn(text) {
                var first20 = true
                for k in 0..<20 where !extraOk(t + 20 * k) {
                    first20 = false
                    break
                }
                if !first20 { continue }

                var n = 0
                while extraOk(t + 20 * n) { n += 1 }
                extras = t
                extraCount = n
                ok("Extras", t, n, .content, "\(n) scenarios")
                return
            }

            throw TsukiError.format("no ending-list table (20 records of {scene, flow scene, unlocks, message})")
        }

        /// The dialog / help message ids: 55 i32 (ui_text ids or -1) at a code reference, followed by
        /// zero bytes, with at least three -1 entries and 30 distinct values, and holding a message for
        /// every ending-list prompt.
        private func findDialogs() throws {
            let count = DialogMessageTable.count
            var messages: [Int] = []
            messages.reserveCapacity(extraCount)
            for k in 0..<extraCount {
                messages.append(Int(try i32(extras + 20 * k + 16)))
            }

            var hits: [Int] = []
            for t in leaTargetsIn(text) {
                guard readable(t, 4 * count + 8) else { continue }
                var values: [Int] = []
                values.reserveCapacity(count)
                for k in 0..<count { values.append(Int(try i32(t + 4 * k))) }

                var valid = true
                for value in values where !(value == -1 || (value >= 1 && value <= 2000)) {
                    valid = false
                    break
                }
                if !valid { continue }
                guard values.filter({ $0 == -1 }).count >= 3, Set(values).count >= 30 else { continue }
                guard (try i64(t + 4 * count)) == 0 else { continue }
                guard messages.allSatisfy({ $0 < count && values[$0] > 0 }) else { continue }
                hits.append(t)
            }

            guard hits.count == 1 else {
                throw TsukiError.format("\(hits.count) candidate dialog message tables")
            }

            dialogs = hits[0]
            ok("DialogMessages", dialogs, count, .content,
               "\(count) ids, prompts of \(messages.count) scenarios resolve")
        }

        /// The fill colours: six RGB565 words (word 1 pure red) followed by eight copies of word 0.
        private func findTextColours() throws {
            let span = text.bytes
            var i = 0
            while i + 28 <= span.count {
                let word0 = span.u16(i)
                if word0 != 0 && span.u16(i + 2) == 0xF800 {
                    var repeated = true
                    for k in 6..<14 where span.u16(i + 2 * k) != word0 {
                        repeated = false
                        break
                    }

                    var distinct: Set<UInt16> = []
                    for k in 0..<6 { distinct.insert(span.u16(i + 2 * k)) }
                    if repeated && distinct.count >= 5 {
                        colours = text.va + i
                        ok("TextColours", colours, 6, .content, "RGB565, red second, default repeated after")
                        return
                    }
                }
                i += 2
            }

            throw TsukiError.format("no fill colour table (six RGB565 words then the default repeated)")
        }

        private func mzpName(_ pointer: UInt64) -> Bool {
            guard isStringPointer(pointer), let address = intVa(pointer),
                  let name = asciiString(address, limit: 64), ImageCatalog.isFileName(name) else {
                return false
            }
            return name.hasSuffix(".MZP")
        }

        /// The gallery: group records {relro* entries, i32 category 0..19, 20 zero bytes} in RELRO (at
        /// least 400 in a row), each entry list NULL-terminated 32-byte records naming a picture; the
        /// special names are the pointers right before the first group's list (back to a NULL); the
        /// aliases are 0x28-byte records of picture-name pointers (at least 50 in a row).
        private func findGallery() throws {
            func groupOk(_ va: Int) -> Bool {
                guard readable(va, 32), let seg = segOf(va) else { return false }
                let record = seg.bytes.slice(seg.offset(va), 32)
                guard let entries = intVa(record.u64(0)), relro.contains(entries) else { return false }
                let category = Int(record.i32(8))
                guard category >= 0, category <= 19 else { return false }
                for k in 12..<32 where record.u8(k) != 0 { return false }
                return true
            }

            var groupsVa = 0
            var va = relro.va
            while va + 32 * 400 <= relro.end {
                var all = true
                for k in 0..<400 where !groupOk(va + 32 * k) {
                    all = false
                    break
                }
                if all {
                    groupsVa = va
                    break
                }
                va += 8
            }

            guard groupsVa != 0 else {
                throw TsukiError.format("no CG group table (400 records of {entry list, category, zeros} in RELRO)")
            }

            var n = 0
            var entries = 0
            while groupOk(groupsVa + 32 * n) {
                var list = Int(try u64(groupsVa + 32 * n))
                while (try u64(list)) != 0 {
                    let pointer = try u64(list)
                    if !isStringPointer(pointer) {
                        throw TsukiError.format("CG group \(n): entry name pointer 0x\(EbootLocator.hex(Int(truncatingIfNeeded: pointer))) is not a string")
                    }
                    entries += 1
                    list += 32
                }
                n += 1
            }

            groups = groupsVa
            groupCount = n
            ok("GalleryGroups", groupsVa, n, .content, "\(n) groups, \(entries) entries")

            let firstList = Int(try u64(groupsVa))
            let nul = firstList - 8
            guard (try u64(nul)) == 0 else {
                throw TsukiError.format("the first CG entry list is not preceded by a NULL-terminated name list")
            }

            var specialNames = 0
            while isStringPointer(try u64(nul - 8 * (specialNames + 1))) { specialNames += 1 }
            guard specialNames > 0 else {
                throw TsukiError.format("no special CG names before the first entry list")
            }

            special = nul - 8 * specialNames
            specialCount = specialNames
            ok("GallerySpecial", special, specialNames, .anchored, "\(specialNames) names before the first entry list")

            func aliasOk(_ va: Int) -> Bool {
                guard readable(va, 40), let seg = segOf(va), mzpName(seg.bytes.u64(seg.offset(va))) else { return false }
                var any = false
                for k in 1..<5 {
                    let pointer = seg.bytes.u64(seg.offset(va) + 8 * k)
                    if pointer == 0 { continue }
                    guard mzpName(pointer) else { return false }
                    any = true
                }
                return any
            }

            var aliasVa = relro.va
            while aliasVa + 40 * 50 <= relro.end {
                var all = true
                for k in 0..<50 where !aliasOk(aliasVa + 40 * k) {
                    all = false
                    break
                }
                if !all {
                    aliasVa += 8
                    continue
                }

                var m = 0
                while aliasOk(aliasVa + 40 * m) { m += 1 }
                aliases = aliasVa
                aliasCount = m
                ok("GalleryAliases", aliasVa, m, .content, "\(m) alias records")
                return
            }

            throw TsukiError.format("no CG alias table (50 records of picture-name pointers in RELRO)")
        }

        /// The flowchart columns: 32-byte RELRO records {i32 index = k, i32 group, i32 count 1..64, 0,
        /// text* nodes, 0}, at least 200 in a row.
        private func findColumns() throws {
            func columnOk(_ va: Int, _ k: Int) -> Bool {
                guard readable(va, 32), let seg = segOf(va) else { return false }
                let record = seg.bytes.slice(seg.offset(va), 32)
                let index = Int(record.i32(0))
                let group = Int(record.i32(4))
                let count = Int(record.i32(8))
                let zero = Int(record.i32(12))
                guard let nodes = intVa(record.u64(16)) else { return false }
                return index == k && group >= 0 && group <= 31 && count >= 1 && count <= 64 && zero == 0
                    && inText(nodes) && record.u64(24) == 0
            }

            var va = relro.va
            while va + 32 * 200 <= relro.end {
                var all = true
                for k in 0..<200 where !columnOk(va + 32 * k, k) {
                    all = false
                    break
                }
                if !all {
                    va += 8
                    continue
                }

                var n = 0
                var nodes = 0
                while columnOk(va + 32 * n, n) {
                    nodes += Int(try i32(va + 32 * n + 8))
                    n += 1
                }
                columns = va
                columnCount = n
                ok("FlowColumns", va, n, .content, "\(n) columns, \(nodes) nodes")
                return
            }

            throw TsukiError.format("no flowchart column table (200 indexed records pointing at node records)")
        }

        // MARK: - Code

        private func rel32Target(_ instruction: Int, _ opcodeLength: Int) throws -> Int {
            instruction + opcodeLength + 4 + Int(try i32(instruction + opcodeLength))
        }

        /// The CG category switch: `push rbp; mov rbp,rsp; push rbx; push rax; dec edi; mov bl,1;
        /// cmp edi,N; ja; lea rax,[rip+table]; movsxd rcx,[rax+rdi*4]; add rcx,rax; jmp rcx`. The jump
        /// table, the category count (N + 1) and the join (the `jmp rel32` of the first case) come out of
        /// the instructions.
        private func findCategorySwitch() throws {
            let pattern: [UInt8?] = [
                0x55, 0x48, 0x89, 0xE5, 0x53, 0x50, 0xFF, 0xCF, 0xB3, 0x01, 0x83, 0xFF, nil,
                0x0F, 0x87, nil, nil, nil, nil, 0x48, 0x8D, 0x05, nil, nil, nil, nil,
                0x48, 0x63, 0x0C, 0xB8, 0x48, 0x01, 0xC1, 0xFF, 0xE1,
            ]
            let hits = findPattern(text, pattern)
            guard hits.count == 1 else {
                throw TsukiError.format("the CG category switch pattern occurs \(hits.count) times")
            }

            let function = hits[0]
            let categories = Int(try u8(function + 12)) + 1
            let table = try rel32Target(function + 19, 3)
            let firstCase = table + Int(try i32(table))
            var at = firstCase
            while (try u8(at)) != 0xE9 {
                at += 1
                if at > firstCase + 64 {
                    throw TsukiError.format("the first category case has no jmp rel32")
                }
            }

            let join = try rel32Target(at, 1)
            for category in 0..<categories {
                let target = table + Int(try i32(table + 4 * category))
                if target <= function || target >= join {
                    throw TsukiError.format("category \(category + 1): case at 0x\(EbootLocator.hex(target)) is outside the switch")
                }
            }

            catJump = table
            catJoin = join
            catCount = categories
            ok("CategoryJumpTable", table, categories, .code,
               "switch at 0x\(EbootLocator.hex(function)), join 0x\(EbootLocator.hex(join)), \(categories) categories")
        }

        /// The STMA loop switch: `xor eax,eax; cmp edi,imm; jle; lea ecx,[rdi-N]; cmp ecx,K; ja; lea
        /// rdx,[rip+table]; movsxd rcx,[rdx+rcx*4]; add rcx,rdx; jmp rcx`; validated by running it.
        private func findMotionLoopFunction() throws {
            let pattern: [UInt8?] = [
                0x31, 0xC0, 0x81, 0xFF, nil, nil, nil, nil, 0x7E, nil, 0x8D, 0x8F, nil, nil, nil, nil,
                0x81, 0xF9, nil, nil, nil, nil, 0x0F, 0x87, nil, nil, nil, nil,
                0x48, 0x8D, 0x15, nil, nil, nil, nil, 0x48, 0x63, 0x0C, 0x8A, 0x48, 0x01, 0xD1, 0xFF, 0xE1,
            ]
            let hits = findPattern(text, pattern)
            guard hits.count == 1 else {
                throw TsukiError.format("the loop-point switch pattern occurs \(hits.count) times")
            }

            let function = hits[0]
            let cpu = TinyX86(r.read)
            var loops = 0
            if motionCount > 0 {
                for id in 1...motionCount {
                    let value = try cpu.run(function, UInt64(id)).eax
                    if value > 36_000_000 {
                        throw TsukiError.format("loop point of motion \(id) is \(value)")
                    }
                    if value != 0 { loops += 1 }
                }
            }

            guard loops >= 100 else {
                throw TsukiError.format("the loop-point switch at 0x\(EbootLocator.hex(function)) yields only \(loops) looping motions")
            }

            loopFn = function
            ok("MotionLoopFunction", function, loops, .code, "\(loops) looping motions of \(motionCount)")
        }

        /// The flowchart-jump clears: `cmp edi,imm; jg; lea rax,[rip+F words]; cmp edi,imm; mov word
        /// [rax+off],0; jg ...`; the F array is the lea target; validated by running it.
        private func findJumpClearFunction() throws {
            let pattern: [UInt8?] = [
                0x81, 0xFF, nil, nil, nil, nil, 0x0F, 0x8F, nil, nil, nil, nil,
                0x48, 0x8D, 0x05, nil, nil, nil, nil, 0x81, 0xFF, nil, nil, nil, nil,
                0x66, 0xC7, 0x80, nil, nil, nil, nil, 0x00, 0x00, 0x0F, 0x8F,
            ]
            let hits = findPattern(text, pattern)
            guard hits.count == 1 else {
                throw TsukiError.format("the jump-clear pattern occurs \(hits.count) times")
            }

            let function = hits[0]
            let fWords = try rel32Target(function + 12, 3)
            guard let segment = r.image.segmentOf(fWords), (segment.flags & 2) != 0 else {
                throw TsukiError.format("the F word array at 0x\(EbootLocator.hex(fWords)) is not in the writable segment")
            }

            let cpu = TinyX86(r.read)
            var words = 0
            for row in 0...300 {
                let result = try cpu.run(function, UInt64(row))
                for store in result.stores {
                    let offset = store.address - fWords
                    if store.value != 0 || offset < 0 || offset > 2400 || (offset & 1) != 0 {
                        throw TsukiError.format(
                            "the clear function at 0x\(EbootLocator.hex(function)) stores 0x\(String(store.value, radix: 16)) at 0x\(EbootLocator.hex(store.address))")
                    }
                    words += 1
                }
            }

            clearFn = function
            fwords = fWords
            ok("JumpClearFunction", function, words, .code, "\(words) zero stores over 301 columns")
            ok("FWordsBase", fWords, 0, .code, "the lea of the clear function")
        }
    }
}
