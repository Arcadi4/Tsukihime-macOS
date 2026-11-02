import Foundation
import TsukiCore
import TsukiEngine

/// ``GameData`` over the user's CUSA47999 folder, read with native Swift decoders (ARCHITECTURE 3.3).
///
/// The folder is only ever opened for reading, and nothing large is read into memory: archives are memory-mapped
/// and an entry is a window onto the mapping; `allscr.mrg`, `script_text.mrg` and the font files are read by
/// section with positional reads.
///
/// Opening reads `eboot.bin` (12.7 MB), the five NAM tables of the image archives and nothing else.
/// Everything else is opened on first use. All members are safe to call from several threads (ARCHITECTURE 3.4).
public final class GameFolderSource: GameData {
    public static let imageArchiveNames: [String] = [
        "allpac0", "allpac1", "allpac1_2", "allpac2", "allpac3", "allpac4"
    ]

    /// Archives smaller than this stay in the working set (128 MiB).
    public static let trimmedArchiveBytes: Int = 128 << 20

    /// How long ``dispose()`` waits for decodes that are reading the mappings.
    private static let unmapWait: TimeInterval = 15.0

    private let files: GameFiles
    private let audioDecoder: AudioDecoder?
    private let decodeParallelism: Int

    private var archives: [String: Archive] = [:]
    private let archiveLock = NSLock()

    private var fonts: [Language: FontArchive] = [:]
    private let fontLock = NSLock()

    private let allscrLazy: LazyValue<Result<AllscrArchive, Error>>
    private let textLazy: LazyValue<Result<ScriptText, Error>>
    private let seNamesLazy: LazyValue<Result<SeNames, Error>>

    private let uses = UseGate()
    private var disposed = false

    // Thread-safe caches
    private let cacheLock = NSLock()
    private var cachedPictures: [PictureKey: Picture] = [:]
    private var cachedAudio: [AudioKey: AudioClip] = [:]
    private var cachedFontPages: [FontPageKey: FontPage] = [:]
    private var cachedUiSheets: [UiSheetKey: Picture] = [:]
    private var cachedUiSheetSizes: [UiSheetKey: (width: Int, height: Int)] = [:]
    private var cachedUiSheetLayouts: [UiSheetKey: Picture] = [:]
    private var cachedScripts: [Int: ScriptImage] = [:]

    private struct PictureKey: Hashable {
        let archive: Int
        let entry: Int
    }

    private struct AudioKey: Hashable {
        let bank: AudioBank
        let index: Int
    }

    private struct FontPageKey: Hashable {
        let language: Language
        let page: Int
    }

    private struct UiSheetKey: Hashable {
        let set: UiSet
        let language: Language
        let child: Int
    }

    private init(
        layout: GameLayout,
        files: GameFiles,
        build: BuildInfo,
        identity: BuildIdentity,
        located: LocateResult?,
        tables: GameEbootTables,
        audioDecoder: AudioDecoder?,
        decodeParallelism: Int
    ) {
        self.layout = layout
        self.files = files
        self.build = build
        self.identity = identity
        self.tableLocations = located
        self.tables = tables
        self.audioDecoder = audioDecoder
        self.decodeParallelism = max(1, decodeParallelism)
        self.allscrLazy = LazyValue(Result { try AllscrArchive.open(files) })
        self.textLazy = LazyValue(Result { try ScriptText.open(files) })
        self.seNamesLazy = LazyValue(Result { try SeNames.open(files) })
    }

    deinit {
        dispose()
    }

    /// The folder that was opened: the base game folder.
    public var rootDirectory: String { layout.baseFolder ?? "" }

    /// How the dump is laid out on disk (package K25).
    public let layout: GameLayout

    /// What the dump is: title id, version, the eboot's hash against the known builds, the languages the data carries.
    public let identity: BuildIdentity

    /// Where the eboot's tables were found when they had to be located by content; nil for the verified build.
    public let tableLocations: LocateResult?

    /// The languages the data supports (``BuildIdentity/availableLanguages``).
    public var availableLanguages: [Language] { identity.availableLanguages }

    /// The `sce_sys/param.sfo` of the dump; nil when missing or unreadable.
    public var paramSfo: ParamSfo? { identity.sfo }

    /// The game's title in `language`, from ``paramSfo`` with ``GameTitles`` fallback.
    public func title(_ language: Language) -> String {
        GameTitles.of(paramSfo, language)
    }

    /// Identity of the copy: the folder, and the size and SHA-256 of its eboot.bin (RR 3.3).
    public let build: BuildInfo

    /// The eboot tables with their typed readers.
    public let tables: GameEbootTables

    /// The eboot tables conforming to ``EbootTables``.
    public var eboot: EbootTables { tables }

    /// The catalog: image table, picture names, NAM search, movie table, UI tables (A2).
    public var catalog: GameCatalog { tables.catalog }

    /// `allscr.mrg`: the script names, label tables and script sections (opened on first use).
    public var scripts: AllscrArchive { get throws { try allscrLazy.value.get() } }

    /// `script_text.mrg`: the text tables of the five languages (opened on first use).
    public var text: ScriptText { get throws { try textLazy.value.get() } }

    /// `se_nam.mrg`: the sound-effect names (opened on first use).
    public var soundEffectNames: SeNames { get throws { try seNamesLazy.value.get() } }

    /// Lazily initialized picture layout source over this game folder.
    public private(set) lazy var layouts = GamePictureLayouts(self)

    /// Drops a range of a mapping from the process's working set (address, length).
    public var pageTrimmer: ((UnsafeMutableRawPointer, Int) -> Void)?

    // MARK: - Open

    /// Opens the game folder (any layout ``GameLayoutResolver/resolve(_:)`` understands).
    public static func open(
        _ folder: String,
        audioDecoder: AudioDecoder? = nil,
        decodeParallelism: Int = 1
    ) throws -> GameFolderSource {
        let trimmed = folder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TsukiError.bounds("game folder path cannot be empty")
        }
        let layout = GameLayoutResolver.resolve(trimmed)
        if layout.kind == .missing {
            throw TsukiError.io("game folder \(trimmed) does not exist")
        }

        if layout.kind == .noGame {
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDir)
            if exists && isDir.boolValue {
                let ebootPath = (trimmed as NSString).appendingPathComponent("eboot.bin")
                let subdirs = (try? FileManager.default.contentsOfDirectory(atPath: trimmed)) ?? []
                let hasSubdirs = subdirs.contains { sub in
                    var subIsDir: ObjCBool = false
                    _ = FileManager.default.fileExists(
                        atPath: (trimmed as NSString).appendingPathComponent(sub),
                        isDirectory: &subIsDir
                    )
                    return subIsDir.boolValue
                }
                if !FileManager.default.fileExists(atPath: ebootPath) && !hasSubdirs {
                    throw TsukiError.io("eboot.bin not found in \(trimmed)")
                }
            }
        }

        return try open(layout, audioDecoder: audioDecoder, decodeParallelism: decodeParallelism)
    }

    /// Opens a resolved layout.
    public static func open(
        _ layout: GameLayout,
        audioDecoder: AudioDecoder? = nil,
        decodeParallelism: Int = 1
    ) throws -> GameFolderSource {
        guard decodeParallelism >= 1 else {
            throw TsukiError.bounds("decodeParallelism must be >= 1")
        }
        guard layout.isGame else {
            throw TsukiError.state("the layout \(layout.describe()) is not a game")
        }

        let files = try layout.openFiles()
        let ebootBytes = try files.readAll("eboot.bin")
        let identity = BuildIdentity.identify(files, eboot: ebootBytes)
        var reader = try EbootReader.parse(ebootBytes)
        var located: LocateResult? = nil
        if identity.match != .verified || !reader.layout.isAnalysed || identity.known != KnownBuilds.verified {
            let loc = EbootLocator.locate(reader)
            guard loc.complete, let locLayout = loc.layout else {
                throw TsukiError.unsupportedBuild(identity, loc)
            }
            located = loc
            reader = reader.withLayout(locLayout)
        }

        var nams: [ImageArchive: NamTable] = [:]
        nams.reserveCapacity(GameCatalog.searchedArchives.count)
        for entry in GameCatalog.searchedArchives {
            nams[entry.archive] = try NamTable.parseNam32(files.readAll(entry.nam))
        }

        let catalog = try GameCatalog.create(reader, nams)
        let build = BuildInfo(
            source: layout.baseFolder ?? "",
            ebootSize: ebootBytes.count,
            ebootSHA256: identity.ebootSha256
        )
        let tables = GameEbootTables(reader, catalog)
        return GameFolderSource(
            layout: layout,
            files: files,
            build: build,
            identity: identity,
            located: located,
            tables: tables,
            audioDecoder: audioDecoder,
            decodeParallelism: decodeParallelism
        )
    }

    // MARK: - Scripts

    public var scriptCount: Int {
        (try? scripts.count) ?? 0
    }

    public func script(_ k: Int) -> ScriptImage {
        do {
            let use = try uses.enter(self)
            defer { use.dispose() }
            cacheLock.lock()
            if let cached = cachedScripts[k] {
                cacheLock.unlock()
                return cached
            }
            cacheLock.unlock()

            let loaded = try scripts.script(k)
            cacheLock.lock()
            cachedScripts[k] = loaded
            cacheLock.unlock()
            return loaded
        } catch {
            fatalError("GameFolderSource.script(\(k)) failed: \(error)")
        }
    }

    public func loadScript(_ k: Int) throws -> ScriptImage {
        let use = try uses.enter(self)
        defer { use.dispose() }
        cacheLock.lock()
        if let cached = cachedScripts[k] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let loaded = try scripts.script(k)
        cacheLock.lock()
        cachedScripts[k] = loaded
        cacheLock.unlock()
        return loaded
    }

    // MARK: - Text

    public var textLineCount: Int {
        (try? text.count) ?? 0
    }

    public func textLine(_ lang: Language, _ id: Int) -> ByteSpan {
        do {
            try throwIfDisposed()
            _ = TextRules.code(lang)
            let txt = try text
            guard id >= 0 && id < txt.count else {
                throw TsukiError.bounds("text line ids are 0..<\(txt.count)")
            }
            return try txt.engineLine(lang, id)
        } catch {
            fatalError("GameFolderSource.textLine(\(lang), \(id)) failed: \(error)")
        }
    }

    public func loadTextLine(_ lang: Language, _ id: Int) throws -> ByteSpan {
        try throwIfDisposed()
        _ = TextRules.code(lang)
        let txt = try text
        guard id >= 0 && id < txt.count else {
            throw TsukiError.bounds("text line ids are 0..<\(txt.count)")
        }
        return try txt.engineLine(lang, id)
    }

    // MARK: - Fonts

    public func fontPage(_ lang: Language, _ page: Int) -> FontPage {
        do {
            let use = try uses.enter(self)
            defer { use.dispose() }
            let key = FontPageKey(language: lang, page: page)
            cacheLock.lock()
            if let cached = cachedFontPages[key] {
                cacheLock.unlock()
                return cached
            }
            cacheLock.unlock()

            let p = try fontFile(lang).readPage(page)
            cacheLock.lock()
            cachedFontPages[key] = p
            cacheLock.unlock()
            return p
        } catch {
            fatalError("GameFolderSource.fontPage(\(lang), \(page)) failed: \(error)")
        }
    }

    public func fontFile(_ lang: Language) throws -> FontArchive {
        try throwIfDisposed()
        _ = TextRules.code(lang)
        fontLock.lock()
        defer { fontLock.unlock() }
        if let existing = fonts[lang] {
            return existing
        }
        let archive = try FontArchive.open(files, language: lang)
        fonts[lang] = archive
        return archive
    }

    // MARK: - Pictures

    public func picture(_ archive: Int, _ entry: Int) -> Picture {
        do {
            let use = try uses.enter(self)
            defer { use.dispose() }
            let key = PictureKey(archive: archive, entry: entry)
            cacheLock.lock()
            if let cached = cachedPictures[key] {
                cacheLock.unlock()
                return cached
            }
            cacheLock.unlock()

            let pic = try openImage(archive, entry).toPicture(maxDegreeOfParallelism: decodeParallelism)
            cacheLock.lock()
            cachedPictures[key] = pic
            cacheLock.unlock()
            return pic
        } catch {
            fatalError("GameFolderSource.picture(\(archive), \(entry)) failed: \(error)")
        }
    }

    public func picture(_ id: ImageId) -> Picture {
        picture(Int(id.archive.rawValue), id.index)
    }

    public func openImage(_ archive: Int, _ entry: Int) throws -> ImageMzp {
        try throwIfDisposed()
        guard archive >= 0 && archive < Self.imageArchiveNames.count else {
            throw TsukiError.bounds("image archive ids are 0..5 (allpac0 .. allpac4)")
        }
        let name = Self.imageArchiveNames[archive]
        let a = try self.archive(name)
        guard entry >= 0 && entry < a.count else {
            throw TsukiError.bounds("\(name) has entries 0..<\(a.count)")
        }
        return try ImageMzp.open(a.entry(entry))
    }

    public func openImage(_ archive: UInt8, _ entry: Int) throws -> ImageMzp {
        try openImage(Int(archive), entry)
    }

    // MARK: - Audio

    public func audio(_ bank: AudioBank, _ index: Int) -> AudioClip {
        do {
            let use = try uses.enter(self)
            defer { use.dispose() }
            let key = AudioKey(bank: bank, index: index)
            cacheLock.lock()
            if let cached = cachedAudio[key] {
                cacheLock.unlock()
                return cached
            }
            cacheLock.unlock()

            guard let decoder = audioDecoder else {
                throw TsukiError.state("GameFolderSource was opened without an AudioDecoder")
            }
            let payload = try audioPayload(bank, index)
            let clip = try decoder.decode(bank: bank, index: index, payload: payload)
            cacheLock.lock()
            cachedAudio[key] = clip
            cacheLock.unlock()
            return clip
        } catch {
            fatalError("GameFolderSource.audio(\(bank), \(index)) failed: \(error)")
        }
    }

    public func decodeAudio(_ bank: AudioBank, _ index: Int) throws -> AudioClip {
        let use = try uses.enter(self)
        defer { use.dispose() }
        let key = AudioKey(bank: bank, index: index)
        cacheLock.lock()
        if let cached = cachedAudio[key] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        guard let decoder = audioDecoder else {
            throw TsukiError.state("GameFolderSource was opened without an AudioDecoder")
        }
        let payload = try audioPayload(bank, index)
        let clip = try decoder.decode(bank: bank, index: index, payload: payload)
        cacheLock.lock()
        cachedAudio[key] = clip
        cacheLock.unlock()
        return clip
    }

    public func audioPayload(_ bank: AudioBank, _ index: Int) throws -> ByteSpan {
        try throwIfDisposed()
        let name = Self.bankFile(bank)
        let archive = try self.archive(name)
        guard index >= 0 && index < archive.count else {
            throw TsukiError.bounds("\(name) has entries 0..<\(archive.count)")
        }
        return (bank == .voice || bank == .voice2)
            ? try Lv.decompress(archive.sectorSpan(index)).data
            : archive.entry(index)
    }

    public func audioCount(_ bank: AudioBank) throws -> Int {
        try throwIfDisposed()
        return try archive(Self.bankFile(bank)).count
    }

    // MARK: - Movies

    public func movie(_ index: Int) -> String {
        do {
            try throwIfDisposed()
            let movies = tables.movies
            guard index >= 0 && index < movies.count else {
                throw TsukiError.bounds("movie table records are 0..<\(movies.count)")
            }
            let prefix = "/app0/"
            let path = movies[index].path
            guard path.hasPrefix(prefix) else {
                throw TsukiError.format("movie \(index): path \"\(path)\" does not start with \(prefix)")
            }
            let rel = String(path.dropFirst(prefix.count))
            guard let resolved = files.resolveFile(rel) else {
                throw TsukiError.io("movie \(index) (\(path)) is not in \(files.description)")
            }
            return resolved
        } catch {
            fatalError("GameFolderSource.movie(\(index)) failed: \(error)")
        }
    }

    public func moviePath(_ index: Int) throws -> String {
        try throwIfDisposed()
        let movies = tables.movies
        guard index >= 0 && index < movies.count else {
            throw TsukiError.bounds("movie table records are 0..<\(movies.count)")
        }
        let prefix = "/app0/"
        let path = movies[index].path
        guard path.hasPrefix(prefix) else {
            throw TsukiError.format("movie \(index): path \"\(path)\" does not start with \(prefix)")
        }
        let rel = String(path.dropFirst(prefix.count))
        guard let resolved = files.resolveFile(rel) else {
            throw TsukiError.io("movie \(index) (\(path)) is not in \(files.description)")
        }
        return resolved
    }

    // MARK: - UI Sheets

    public func uiSheet(_ set: UiSet, _ lang: Language, _ child: Int) -> Picture {
        do {
            let use = try uses.enter(self)
            defer { use.dispose() }
            let key = UiSheetKey(set: set, language: lang, child: child)
            cacheLock.lock()
            if let cached = cachedUiSheets[key] {
                cacheLock.unlock()
                return cached
            }
            cacheLock.unlock()

            let container = try uiSheetContainer(set, lang)
            let checked = try checkChild(set, lang, child, container: container)
            let pic = try ImageMzp.open(container.child(checked)).toPicture(maxDegreeOfParallelism: decodeParallelism)
            cacheLock.lock()
            cachedUiSheets[key] = pic
            cacheLock.unlock()
            return pic
        } catch {
            fatalError("GameFolderSource.uiSheet(\(set), \(lang), \(child)) failed: \(error)")
        }
    }

    public func parts(_ index: Int) throws -> Picture? {
        let use = try uses.enter(self)
        defer { use.dispose() }
        let archive = try self.archive("parts")
        guard index >= 0 && index < archive.count else {
            return nil
        }
        return try ImageMzp.open(archive.entry(index)).toPicture(maxDegreeOfParallelism: decodeParallelism)
    }

    public func uiSheetSize(_ set: UiSet, _ lang: Language, _ child: Int) -> (width: Int, height: Int) {
        do {
            let use = try uses.enter(self)
            defer { use.dispose() }
            let key = UiSheetKey(set: set, language: lang, child: child)
            cacheLock.lock()
            if let cached = cachedUiSheetSizes[key] {
                cacheLock.unlock()
                return cached
            }
            cacheLock.unlock()

            let img = try openUiSheetImage(set, lang, child)
            let size = (width: img.header.displayWidth, height: img.header.displayHeight)
            cacheLock.lock()
            cachedUiSheetSizes[key] = size
            cacheLock.unlock()
            return size
        } catch {
            fatalError("GameFolderSource.uiSheetSize(\(set), \(lang), \(child)) failed: \(error)")
        }
    }

    public func uiSheetLayout(_ set: UiSet, _ lang: Language, _ child: Int) -> Picture {
        do {
            let use = try uses.enter(self)
            defer { use.dispose() }
            let key = UiSheetKey(set: set, language: lang, child: child)
            cacheLock.lock()
            if let cached = cachedUiSheetLayouts[key] {
                cacheLock.unlock()
                return cached
            }
            cacheLock.unlock()

            let img = try openUiSheetImage(set, lang, child)
            let pic = img.toLayoutPicture()
            cacheLock.lock()
            cachedUiSheetLayouts[key] = pic
            cacheLock.unlock()
            return pic
        } catch {
            fatalError("GameFolderSource.uiSheetLayout(\(set), \(lang), \(child)) failed: \(error)")
        }
    }

    public func openUiSheetImage(_ set: UiSet, _ lang: Language, _ child: Int) throws -> ImageMzp {
        try throwIfDisposed()
        let container = try uiSheetContainer(set, lang)
        let checked = try checkChild(set, lang, child, container: container)
        return try ImageMzp.open(container.child(checked))
    }

    public func uiSheetChildCount(_ set: UiSet, _ lang: Language) throws -> Int {
        try throwIfDisposed()
        return try uiSheetContainer(set, lang).count
    }

    private func checkChild(_ set: UiSet, _ lang: Language, _ child: Int, container: MzpContainer? = nil) throws -> Int {
        let c = try container ?? uiSheetContainer(set, lang)
        guard child >= 0 && child < c.count else {
            throw TsukiError.bounds("\(UiSheetNames.fileName(set, lang)) has children 0..<\(c.count)")
        }
        return child
    }

    private func uiSheetContainer(_ set: UiSet, _ lang: Language) throws -> MzpContainer {
        _ = TextRules.code(lang)
        let file = UiSheetNames.fileName(set, lang)
        guard let id = try catalog.nameIndex.find(file) else {
            throw TsukiError.io("UI sheet \(file) is not in any image archive")
        }
        let a = try self.archive(Self.imageArchiveNames[Int(id.archive.rawValue)])
        return try MzpContainer.parse(a.entry(id.index))
    }

    // MARK: - Archives

    public func archive(_ name: String) throws -> Archive {
        try throwIfDisposed()
        archiveLock.lock()
        defer { archiveLock.unlock() }
        let lower = name.lowercased()
        if let existing = archives[lower] {
            return existing
        }
        let a = try openArchive(name)
        archives[lower] = a
        return a
    }

    private func openArchive(_ name: String) throws -> Archive {
        let hed = "image/\(name).hed"
        guard files.resolveFile(hed) != nil else {
            throw TsukiError.io("\(hed) is not in \(files.description); the game folder is incomplete")
        }
        guard let mrgPath = files.resolveFile("image/\(name).mrg") else {
            throw TsukiError.io("image/\(name).mrg is not in \(files.description); the game folder is incomplete")
        }
        let index = try ArchiveIndex.load(files, base: "image/\(name)")
        return Archive.open(index: index, file: try MappedFile(path: mrgPath))
    }

    private static func bankFile(_ bank: AudioBank) -> String {
        switch bank {
        case .bgm: return "bgm"
        case .se: return "vse"
        case .voice: return "voice"
        case .voice2: return "voice2"
        case .vag: return "vag"
        }
    }

    // MARK: - Trimming and Disposal

    public func trimMappedPages() -> Int {
        guard let trim = pageTrimmer, let use = uses.tryEnter() else {
            return 0
        }
        defer { use.dispose() }
        var trimmed = 0
        archiveLock.lock()
        let openArchives = Array(archives.values)
        archiveLock.unlock()
        for archive in openArchives {
            if archive.mappedLength >= Self.trimmedArchiveBytes {
                archive.trimResident(trim)
                trimmed += 1
            }
        }
        return trimmed
    }

    public func dispose() {
        guard !disposed else { return }
        disposed = true
        guard uses.close(timeout: Self.unmapWait) else { return }

        archiveLock.lock()
        let openArchives = Array(archives.values)
        archives.removeAll()
        archiveLock.unlock()

        for archive in openArchives {
            archive.dispose()
        }

        cacheLock.lock()
        cachedPictures.removeAll()
        cachedAudio.removeAll()
        cachedFontPages.removeAll()
        cachedUiSheets.removeAll()
        cachedUiSheetSizes.removeAll()
        cachedUiSheetLayouts.removeAll()
        cachedScripts.removeAll()
        cacheLock.unlock()
    }

    private func throwIfDisposed() throws {
        if disposed {
            throw TsukiError.state("GameFolderSource has been disposed")
        }
    }
}

// MARK: - Extensions for StagePictureLayouts & ImageMzp

extension PictureFileLayout {
    public init(archive: UInt8, entry: Int, offsetX: Float, offsetY: Float, tiles: [TileQuad]) {
        self.init(archive: Int(archive), entry: entry, offsetX: offsetX, offsetY: offsetY, tiles: tiles)
    }
}

extension ImageMzp {
    public var tiles: Int { header.tiles }
    public var tileWidth: Int { header.tileWidth }
    public var tileHeight: Int { header.tileHeight }
    public func isLive(_ t: Int) -> Bool { header.isLive(t) }
    public func tileWindow(_ t: Int) -> (sx: Int, sy: Int, width: Int, height: Int, x: Int, y: Int) {
        header.tileWindow(t)
    }
}
