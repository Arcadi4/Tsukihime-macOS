import Foundation
import TsukiCore
import TsukiEngine

/// A picture of an image archive (the caution screens in allpac3, or an entry of the game's `parts` archive): `archive` is an image archive id
/// of docs/formats/archives_ui_movies.md 2.1 (0 allpac0 .. 5 allpac4), or `UiPictureArchive.parts`.
public struct UiPicture: Hashable, Sendable {
    public var archive: Int
    public var entry: Int

    public var Archive: Int { archive }
    public var Entry: Int { entry }

    public init(archive: Int, entry: Int) {
        self.archive = archive
        self.entry = entry
    }

    public init(_ archive: Int, _ entry: Int) {
        self.archive = archive
        self.entry = entry
    }
    public init(_ archive: Int, _ entry: UInt8) {
        self.archive = archive
        self.entry = Int(entry)
    }
}

/// Archive ids beyond the six image archives that the UI names in a `UiPicture` (package K5a; additive to the contract's 0..5).
public enum UiPictureArchive {
    /// The `parts` archive (parts.hed / parts.mrg: 24 pictures of the boot notices; docs/formats/archives_ui_movies.md 6).
    public static let parts = 6
    public static let Parts = parts
}

/// The pictures of the `parts` archive, which `GameData` does not serve (it knows the six image archives only). The host passes an
/// implementation to `UiRoot` when it has one; without it the boot notice draws its icons from DISP_PARTS and leaves the text out.
public protocol UiPictureSource: AnyObject {
    /// Picture `index` of parts.mrg (0..23), decoded; nil when there is none.
    func parts(_ index: Int) -> Picture?
}
public typealias IUiPictureSource = UiPictureSource

/// One tile of a sheet: where the displayed part lands in the sheet and where it sits in the stored (apron-bordered) texture.
public struct SheetTile: Equatable, Sendable {
    public var index: Int
    public var x: Int
    public var y: Int
    public var w: Int
    public var h: Int
    public var sourceX: Int
    public var sourceY: Int
    public var storedWidth: Int
    public var storedHeight: Int

    public var Index: Int { index }
    public var X: Int { x }
    public var Y: Int { y }
    public var W: Int { w }
    public var H: Int { h }
    public var SourceX: Int { sourceX }
    public var SourceY: Int { sourceY }
    public var StoredWidth: Int { storedWidth }
    public var StoredHeight: Int { storedHeight }

    public init(index: Int, x: Int, y: Int, w: Int, h: Int, sourceX: Int, sourceY: Int, storedWidth: Int, storedHeight: Int) {
        self.index = index
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.sourceX = sourceX
        self.sourceY = sourceY
        self.storedWidth = storedWidth
        self.storedHeight = storedHeight
    }
}

/// The size and tile layout of a sheet; no pixels (the executor fetches those through `GameData.uiSheet`).
public final class SheetGeometry: Sendable {
    public let width: Int
    public let height: Int
    public let tiles: [SheetTile]

    public var Width: Int { width }
    public var Height: Int { height }
    public var Tiles: [SheetTile] { tiles }

    public init(width: Int, height: Int, tiles: [SheetTile]) {
        self.width = width
        self.height = height
        self.tiles = tiles
    }

    /// The geometry of a decoded picture.
    public static func fromPicture(_ picture: Picture) -> SheetGeometry {
        var tiles: [SheetTile] = []
        tiles.reserveCapacity(picture.tiles.count)
        for t in picture.tiles {
            if t.flags == .empty || t.source.width <= 0 || t.source.height <= 0 {
                continue
            }
            tiles.append(SheetTile(
                index: t.index, x: t.x, y: t.y,
                w: t.source.width, h: t.source.height,
                sourceX: t.source.x, sourceY: t.source.y,
                storedWidth: t.storedWidth, storedHeight: t.storedHeight
            ))
        }
        return SheetGeometry(width: picture.width, height: picture.height, tiles: tiles)
    }
    public static func FromPicture(_ picture: Picture) -> SheetGeometry {
        fromPicture(picture)
    }
}

private struct SheetKey: Hashable {
    let set: UiSet
    let language: Language
    let child: Int
}

private struct ComposedKey: Hashable {
    let id: Int
    let language: Language
}

/// The sheets and tables the screens draw from, for one UI language: `GameData.uiSheet` geometry cached per sheet, the
/// `UiTables`, and the language. Changing the language drops the cache (knife `lang_frame`: the UI atlases reload).
public final class UiAssets {
    private let lock = NSLock()
    private var _geometry: [SheetKey: SheetGeometry] = [:]
    private var _pictures: [UiPicture: SheetGeometry] = [:]
    private var _composed: [ComposedKey: UiComposedPicture?] = [:]

    /// Creates the assets over a game data source.
    public init(data: GameData, language: Language, parts: UiPictureSource? = nil) {
        self.data = data
        self.parts = parts
        self.tables = data.eboot.ui
        self.gallery = data.eboot.gallery
        self.availableLanguages = data.availableLanguages.isEmpty ? [.ja, .en, .zc, .zt] : data.availableLanguages
        self.language = language
    }

    /// The selectable languages the data carries (package K25): the config screen offers these only.
    public let availableLanguages: [Language]
    public var AvailableLanguages: [Language] { availableLanguages }

    /// The gallery and flowchart tables (package K5b), or nil when the data source holds none.
    public let gallery: UiGalleryTables?
    public var Gallery: UiGalleryTables? { gallery }

    /// The game data.
    public let data: GameData
    public var Data: GameData { data }

    /// The parts archive, or nil.
    public let parts: UiPictureSource?
    public var Parts: UiPictureSource? { parts }

    /// The eboot tables of the menus.
    public let tables: UiTables
    public var Tables: UiTables { tables }

    /// The UI language (0 ja, 1 en, 2 zc, 3 zt).
    public private(set) var language: Language
    public var Language: Language { language }

    /// Sheets that a draw asked for and the data did not have.
    public private(set) var missing: [UiSheet: Int] = [:]
    public var Missing: [UiSheet: Int] { missing }

    /// Pictures that a draw asked for and could not be found.
    public private(set) var missingPictures: [UiPicture: Int] = [:]
    public var MissingPictures: [UiPicture: Int] { missingPictures }

    /// Switches the language; the sheet cache is dropped.
    public func setLanguage(_ language: Language) {
        lock.lock()
        defer { lock.unlock() }
        if language != self.language {
            self.language = language
            _geometry.removeAll()
            _composed.removeAll()
        }
    }
    public func SetLanguage(_ language: Language) { setLanguage(language) }

    /// The picture the menus compose at run time from the player's own sheets (package K33; `UiComposedId`), in the current language.
    public func composed(_ id: Int) -> UiComposedPicture? {
        composed(id, language: language)
    }
    public func Composed(_ id: Int) -> UiComposedPicture? { composed(id) }

    /// The composed picture `id` of `language`.
    public func composed(_ id: Int, language: Language) -> UiComposedPicture? {
        lock.lock()
        let key = ComposedKey(id: id, language: language)
        if let cached = _composed[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        buildComposed(language)

        lock.lock()
        defer { lock.unlock() }
        return _composed[key] ?? nil
    }
    public func Composed(_ id: Int, _ language: Language) -> UiComposedPicture? {
        composed(id, language: language)
    }

    private func buildComposed(_ language: Language) {
        var exitNormal: UiComposedPicture? = nil
        var exitCursor: UiComposedPicture? = nil

        let pic = data.uiSheet(UiSheets.titleMenu.set, language, UiSheets.titleMenu.child)
        if let exit = TitleExitArt.compose(pic) {
            exitNormal = exit.normal
            exitCursor = exit.cursor
        }

        lock.lock()
        _composed[ComposedKey(id: UiComposedId.titleExit, language: language)] = exitNormal
        _composed[ComposedKey(id: UiComposedId.titleExitCursor, language: language)] = exitCursor
        lock.unlock()
    }

    /// The geometry of `sheet`, or nil when the set has no such child.
    public func geometry(_ sheet: UiSheet) -> SheetGeometry? {
        lock.lock()
        let key = SheetKey(set: sheet.set, language: language, child: sheet.child)
        if let g = _geometry[key] {
            lock.unlock()
            return g
        }
        lock.unlock()

        var geom: SheetGeometry? = nil
        let pic = data.uiSheetLayout(sheet.set, language, sheet.child)
        geom = SheetGeometry.fromPicture(pic)

        lock.lock()
        defer { lock.unlock() }
        if let g = geom {
            _geometry[key] = g
            return g
        } else {
            missing[sheet, default: 0] += 1
            return nil
        }
    }
    public func Geometry(_ sheet: UiSheet) -> SheetGeometry? { geometry(sheet) }

    /// The geometry of a picture of an image archive, or nil when it does not exist.
    public func geometry(_ picture: UiPicture) -> SheetGeometry? {
        lock.lock()
        if let g = _pictures[picture] {
            lock.unlock()
            return g
        }
        lock.unlock()

        var geom: SheetGeometry? = nil
        let pic: Picture?
        if picture.archive == UiPictureArchive.parts {
            pic = parts?.parts(picture.entry)
        } else {
            pic = data.picture(picture.archive, picture.entry)
        }
        if let p = pic {
            geom = SheetGeometry.fromPicture(p)
        }

        lock.lock()
        defer { lock.unlock() }
        if let g = geom {
            _pictures[picture] = g
            return g
        } else {
            missingPictures[picture, default: 0] += 1
            return nil
        }
    }
    public func Geometry(_ picture: UiPicture) -> SheetGeometry? { geometry(picture) }

    /// The `ui_text` string `id` in the current language.
    public func text(_ id: Int) -> String {
        tables.text(language, id)
    }
    public func Text(_ id: Int) -> String { text(id) }

    /// The `ui_text` id of knife's SYSMES message number `knifeId`.
    public static func sysmes(_ knifeId: Int) -> Int {
        knifeId >= 217 ? knifeId + 1 : knifeId
    }
    public static func Sysmes(_ knifeId: Int) -> Int { sysmes(knifeId) }
}
