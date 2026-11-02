import Foundation
import TsukiCore
import TsukiEngine

/// Resolves the `TextureRef`s of a display list to pixels and uploads them into a `TextureCache`.
public final class GameTextureProvider: @unchecked Sendable {
    /// The tile number that selects the whole sheet of a UI picture.
    public static let wholeSheet: Int32 = -1

    public let data: GameData
    public let cache: TextureCache

    private struct PictureKey: Hashable {
        let archive: Int
        let entry: Int
    }

    private struct SheetKey: Hashable {
        let set: UiSet
        let lang: Language
        let child: Int
    }

    private struct FontKey: Hashable {
        let lang: Language
        let page: Int
    }

    private var pictures: [PictureKey: Picture?] = [:]
    private var pictureOrder: [PictureKey] = []
    private var sheets: [SheetKey: Picture] = [:]
    private var fonts: [FontKey: FontPage] = [:]

    public private(set) var missing: Set<TextureRef> = []
    public var pictureWindow: Int = 6

    public init(data: GameData, cache: TextureCache) {
        self.data = data
        self.cache = cache
    }

    /// Uploads every textured quad's texture that is not resident yet; returns the number of uploads.
    @discardableResult
    public func upload(_ list: DisplayList) -> Int {
        var n = 0
        for cmd in list.commands {
            if cmd.kind == .texturedQuad {
                if ensure(cmd.texture) {
                    n += 1
                }
            }
        }
        return n
    }

    /// Makes `key` resident; true when it had to be uploaded.
    public func ensure(_ key: TextureRef) -> Bool {
        if key.kind == .none || key.kind == .capture || key.kind == .movieFrame || key.kind == .thumbnail || key.kind == .uiComposed {
            return false
        }
        if cache.contains(key) || missing.contains(key) {
            return false
        }

        switch key.kind {
        case .pictureTile:
            guard let pic = pictureOf(archive: Int(key.a), entry: Int(key.b)) else {
                missing.insert(key)
                return false
            }
            guard let tile = pic.tiles.first(where: { $0.index == Int(key.c) }),
                  tile.flags != .empty, !tile.rgba.isEmpty else {
                missing.insert(key)
                return false
            }
            cache.upload(key: key, width: tile.storedWidth, height: tile.storedHeight, rgba: tile.rgba)
            return true

        case .uiTile:
            guard let set = UiSet(rawValue: Int(key.a)),
                  let lang = Language(rawValue: UInt8(key.b)) else {
                missing.insert(key)
                return false
            }
            let sheetKey = SheetKey(set: set, lang: lang, child: Int(key.c))
            let sheet: Picture
            if let existing = sheets[sheetKey] {
                sheet = existing
            } else {
                let fetched = data.uiSheet(set, lang, Int(key.c))
                sheets[sheetKey] = fetched
                sheet = fetched
            }

            if key.d == Self.wholeSheet {
                let assembled = Self.assemble(picture: sheet)
                cache.upload(key: key, width: sheet.width, height: sheet.height, rgba: assembled)
                return true
            }

            guard let tile = sheet.tiles.first(where: { $0.index == Int(key.d) }),
                  tile.flags != .empty, !tile.rgba.isEmpty else {
                missing.insert(key)
                return false
            }
            cache.upload(key: key, width: tile.storedWidth, height: tile.storedHeight, rgba: tile.rgba)
            return true

        case .glyphPage:
            guard let lang = Language(rawValue: UInt8(key.a)) else {
                missing.insert(key)
                return false
            }
            let fontKey = FontKey(lang: lang, page: Int(key.b))
            let page: FontPage
            if let existing = fonts[fontKey] {
                page = existing
            } else {
                let fetched = data.fontPage(lang, Int(key.b))
                fonts[fontKey] = fetched
                page = fetched
            }
            cache.upload(key: key, width: page.width, height: page.height, rgba: page.rgba)
            return true

        default:
            missing.insert(key)
            return false
        }
    }

    /// The displayed picture as one RGBA image: each tile's source window is copied to its displayed position.
    public static func assemble(picture: Picture) -> [UInt8] {
        var rgba = [UInt8](repeating: 0, count: picture.width * picture.height * 4)
        for tile in picture.tiles {
            if tile.flags == .empty || tile.rgba.isEmpty {
                continue
            }
            for row in 0..<tile.source.height {
                let dy = tile.y + row
                if dy < 0 || dy >= picture.height {
                    continue
                }
                let w = min(tile.source.width, picture.width - tile.x)
                if w <= 0 {
                    continue
                }
                let srcOffset = (((tile.source.y + row) * tile.storedWidth) + tile.source.x) * 4
                let dstOffset = ((dy * picture.width) + tile.x) * 4
                let count = w * 4
                guard srcOffset + count <= tile.rgba.count, dstOffset + count <= rgba.count else {
                    continue
                }
                for i in 0..<count {
                    rgba[dstOffset + i] = tile.rgba[srcOffset + i]
                }
            }
        }
        return rgba
    }

    private func pictureOf(archive: Int, entry: Int) -> Picture? {
        let key = PictureKey(archive: archive, entry: entry)
        if let pic = pictures[key] {
            return pic
        }

        let pic: Picture? = {
            return data.picture(archive, entry)
        }()

        pictures[key] = pic
        pictureOrder.append(key)
        while pictureOrder.count > pictureWindow {
            let old = pictureOrder.removeFirst()
            pictures.removeValue(forKey: old)
        }
        return pic
    }
}
