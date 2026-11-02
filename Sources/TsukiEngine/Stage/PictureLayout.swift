import Foundation

/// One tile quad of a picture layer: a rectangle in picture pixels and the texture rectangle that
/// fills it.
public struct TileQuad: Sendable {
    /// Tile number in the picture file (row-major).
    public var tile: Int
    /// Left edge in picture pixels (of the displayed band).
    public var x0: Float
    /// Top edge.
    public var y0: Float
    /// Right edge.
    public var x1: Float
    /// Bottom edge.
    public var y1: Float
    /// Texture coordinate of the left edge.
    public var u0: Float
    /// Texture coordinate of the top edge.
    public var v0: Float
    /// Texture coordinate of the right edge.
    public var u1: Float
    /// Texture coordinate of the bottom edge.
    public var v1: Float

    public init(
        tile: Int, x0: Float, y0: Float, x1: Float, y1: Float,
        u0: Float, v0: Float, u1: Float, v1: Float
    ) {
        self.tile = tile
        self.x0 = x0
        self.y0 = y0
        self.x1 = x1
        self.y1 = y1
        self.u0 = u0
        self.v0 = v0
        self.u1 = u1
        self.v1 = v1
    }
}

/// One picture file of a catalog picture: the body, or the face drawn over it (catalog `name1`).
public struct PictureFileLayout: Sendable {
    /// Image archive id (archives_ui_movies.md 2.1: 0 allpac0 .. 5 allpac4).
    public var archive: Int
    /// Entry in that archive.
    public var entry: Int
    /// Position of this file relative to the picture's top-left (the catalog layer position; 0 in
    /// every record).
    public var offsetX: Float
    /// See ``offsetX``.
    public var offsetY: Float
    /// The tiles that cover the displayed band of the file.
    public var tiles: [TileQuad]

    public init(
        archive: Int, entry: Int, offsetX: Float, offsetY: Float, tiles: [TileQuad]
    ) {
        self.archive = archive
        self.entry = entry
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.tiles = tiles
    }
}

/// The draw description of a catalog picture: the files to draw and their tile geometry. The
/// picture's texel space is that of the displayed band (for a picture with language bands, the band
/// of the current language), with the catalog anchor in the same space.
public struct PictureLayout: Sendable {
    /// Displayed width in picture pixels.
    public var width: Int
    /// Displayed height.
    public var height: Int
    /// Body first, then the face.
    public var files: [PictureFileLayout]

    public init(width: Int, height: Int, files: [PictureFileLayout]) {
        self.width = width
        self.height = height
        self.files = files
    }
}

/// Resolves catalog pictures to their files and tile geometry (the data layer implements it over
/// the image headers and the catalog).
public protocol PictureLayoutSource: AnyObject {
    /// The layout of picture `pic` for `language` (0 ja, 1 en, 2 zc, 3 zt), or nil when it has none.
    func get(_ pic: Int, _ language: Int) -> PictureLayout?
}
