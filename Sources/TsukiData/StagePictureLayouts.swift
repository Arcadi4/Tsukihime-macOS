import Foundation
import TsukiCore
import TsukiEngine

/// ``PictureLayoutSource`` over the game folder (package K2): the draw description of a catalog
/// picture, from its image-table record and the tile table of its image files, without decoding a
/// pixel. The files of a picture are the catalog's `name0` (the body) and `name1` (the face drawn
/// over it), found by the NAM search; the displayed part of a file is the record's source rectangle
/// for the language (the logical size, or the language band of a stacked picture). A tile
/// contributes the part of its inner rectangle that lies inside that rectangle, with texture
/// coordinates into the stored tile (the border pixels around the inner rectangle are the filter
/// apron, ARCHITECTURE 4.3).
///
/// Layouts are immutable and cached per picture and language; the class is safe to call from
/// several threads.
public final class GamePictureLayouts: PictureLayoutSource {
    private struct Key: Hashable {
        let pic: Int
        let language: Int
    }

    private let source: GameFolderSource
    private let lock = NSLock()
    private var cache: [Key: PictureLayout?] = [:]

    /// Creates the source over a game folder.
    public init(_ source: GameFolderSource) {
        self.source = source
    }

    /// The layout of picture `pic` for `language`, or nil when the catalog record is empty or a file
    /// of it is in no archive.
    public func get(_ pic: Int, _ language: Int) -> PictureLayout? {
        let key = Key(pic: pic, language: language)
        lock.lock()
        let cached = cache[key]
        lock.unlock()
        if let cached {
            return cached
        }

        let built = build(pic, language)
        lock.lock()
        if let stored = cache[key] {
            lock.unlock()
            return stored
        }
        cache.updateValue(built, forKey: key)
        lock.unlock()
        return built
    }

    private func build(_ pic: Int, _ language: Int) -> PictureLayout? {
        let catalog = source.catalog
        guard pic >= 0, pic < catalog.images.count else {
            return nil
        }

        let entry = catalog.images[pic]
        let name0 = entry.name0
        guard !name0.isEmpty, entry.width > 0, entry.height > 0,
              let band = try? entry.sourceRect(language: language) else {
            return nil
        }
        var files: [PictureFileLayout] = []
        files.reserveCapacity(2)
        let layers: [(String?, Int, Int)] = [
            (name0, 0, 0), (entry.name1, entry.layerX, entry.layerY),
        ]
        do {
            for (name, dx, dy) in layers {
                guard let name else {
                    continue
                }

                guard let id = try catalog.nameIndex.find(name) else {
                    // No archive holds the file: the picture cannot be drawn (the catalog names a few
                    // sprite variants that the data does not have).
                    return nil
                }

                files.append(try layout(id, band: band, offsetX: dx, offsetY: dy))
            }
        } catch {
            // The archive entry named by the catalog is missing or malformed.
            return nil
        }

        return PictureLayout(width: band.width, height: band.height, files: files)
    }

    private func layout(
        _ id: ImageId, band: PixelRect, offsetX: Int, offsetY: Int
    ) throws -> PictureFileLayout {
        let header = try source.openImage(id.archive.rawValue, id.index)
        var tiles: [TileQuad] = []
        tiles.reserveCapacity(header.tiles)
        for t in 0..<header.tiles {
            if !header.isLive(t) {
                continue
            }

            let (sx, sy, w, ht, x, y) = header.tileWindow(t)
            let x0 = max(x, band.x)
            let y0 = max(y, band.y)
            let x1 = min(x + w, band.x + band.width)
            let y1 = min(y + ht, band.y + band.height)
            if x1 <= x0 || y1 <= y0 {
                continue
            }

            tiles.append(
                TileQuad(
                    tile: t,
                    x0: Float(x0 - band.x), y0: Float(y0 - band.y),
                    x1: Float(x1 - band.x), y1: Float(y1 - band.y),
                    u0: Float(sx + (x0 - x)) / Float(header.tileWidth),
                    v0: Float(sy + (y0 - y)) / Float(header.tileHeight),
                    u1: Float(sx + (x1 - x)) / Float(header.tileWidth),
                    v1: Float(sy + (y1 - y)) / Float(header.tileHeight)))
        }

        return PictureFileLayout(
            archive: id.archive.rawValue, entry: id.index, offsetX: Float(offsetX),
            offsetY: Float(offsetY), tiles: tiles)
    }
}
