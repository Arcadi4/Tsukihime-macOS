import Foundation
import TsukiCore
import TsukiEngine

/// Everything the runtime needs from the eboot to find a picture, a movie or a UI texture, loaded once from the user's
/// folder: the image catalog, the picture-name lists, the NAM search over the five searched archives, the script image
/// resolver, the movie table and the UI texture registration tables. The data is read-only after loading; the instance
/// can be shared between threads. Call it only after the build check accepted the folder (RR 3.3).
public final class GameCatalog {
    private let uiTextLazy: LazyValue<Result<UiTextTable, Error>>

    /// The parsed eboot.bin.
    public let eboot: EbootReader

    /// The image table: 14,744 records.
    public let images: ImageCatalog

    /// The picture-name list (14,745 records, the last empty): name k is the name of record k.
    public let pictureNames: [String]

    /// The old name list (9,959 records).
    public let oldPictureNames: [String]

    /// The NAM name tables of the archives that exist as image sources (allpac0, allpac1, allpac1_2, allpac3, allpac4).
    public let nams: [ImageArchive: NamTable]

    /// The engine's NAM file-name search.
    public let nameIndex: ImageNameIndex

    /// Script image id to image-table record to archive entries.
    public let resolver: ScriptImageResolver

    /// The movie table (134 records).
    public let movies: [MovieRecord]

    /// The language suffixes `ja en zc zt ko`.
    public let languageSuffixes: [String]

    /// The prologue movie ids per language (4, 46, 47, 106).
    public let prologueIds: [Int]

    /// The 21 UI texture registration tables.
    public let uiTables: [UiTexTable]

    /// The UI strings, 5 x 1,499; read on first use.
    public var uiText: UiTextTable {
        get throws { try uiTextLazy.value.get() }
    }

    private init(
        eboot: EbootReader, images: ImageCatalog, names: [String], oldNames: [String],
        nameIndex: ImageNameIndex, resolver: ScriptImageResolver, movies: [MovieRecord],
        languageSuffixes: [String], prologueIds: [Int], uiTables: [UiTexTable],
        nams: [ImageArchive: NamTable]
    ) {
        self.eboot = eboot
        self.images = images
        self.pictureNames = names
        self.oldPictureNames = oldNames
        self.nams = nams
        self.nameIndex = nameIndex
        self.resolver = resolver
        self.movies = movies
        self.languageSuffixes = languageSuffixes
        self.prologueIds = prologueIds
        self.uiTables = uiTables
        self.uiTextLazy = LazyValue(Result { try UiTextTable.read(eboot) })
    }

    /// The five archives whose name tables the NAM search uses, with the file that holds each.
    public static let searchedArchives: [(archive: ImageArchive, nam: String)] = [
        (archive: .allpac4, nam: "image/allpac4.nam"),
        (archive: .allpac3, nam: "image/allpac3.nam"),
        (archive: .allpac1_2, nam: "image/allpac1_2.nam"),
        (archive: .allpac1, nam: "image/allpac1.nam"),
        (archive: .allpac0, nam: "image/allpac0.nam"),
    ]

    /// Loads the catalog from a folder view: `eboot.bin` and the five `.nam` files.
    /// - Throws: `TsukiError.format` when the eboot does not hold the tables at the analysed addresses or a .nam file
    ///   breaks its layout.
    public static func load(_ files: GameFiles) throws -> GameCatalog {
        let data = try files.readAll("eboot.bin")
        let eb = try EbootReader.parse(data)
        var nams: [ImageArchive: NamTable] = [:]
        nams.reserveCapacity(searchedArchives.count)
        for entry in searchedArchives {
            nams[entry.archive] = try NamTable.parseNam32(files.readAll(entry.nam))
        }

        return try create(eb, nams)
    }

    /// Builds the catalog from a parsed eboot and the name tables of the searched archives.
    public static func create(_ eb: EbootReader, _ nams: [ImageArchive: NamTable]) throws -> GameCatalog {
        let images = try ImageCatalog.read(eb)
        let names = try PictureNameLists.read(eb)
        let nameIndex = ImageNameIndex(nams)
        return GameCatalog(
            eboot: eb, images: images, names: names, oldNames: try PictureNameLists.readOld(eb),
            nameIndex: nameIndex,
            resolver: ScriptImageResolver(names: names, table: images.entries, index: nameIndex),
            movies: try MovieTable.read(eb), languageSuffixes: try MovieTable.readLanguageSuffixes(eb),
            prologueIds: try MovieTable.readPrologueIds(eb), uiTables: try UiTextureTables.readAll(eb),
            nams: nams)
    }
}
