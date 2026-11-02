import Foundation
import TsukiCore
import TsukiEngine

/// One record of the movie table (data VA 0xDC8C70 + 0x30 * k, docs/formats/archives_ui_movies.md 9).
public struct MovieRecord: Sendable {
    /// The id (+0x00); equals the record number.
    public let movieId: Int
    /// VA of the record.
    public let va: Int
    /// The path string at +0x08, for example `/app0/image/movie/titlebg1.mp4`.
    public let path: String
    /// The eight u32 at +0x10..+0x2F: runtime defaults of the player object.
    public let rawFields: [UInt32]

    public init(movieId: Int, va: Int, path: String, rawFields: [UInt32]) {
        self.movieId = movieId
        self.va = va
        self.path = path
        self.rawFields = rawFields
    }

    /// The file name after the last '/'.
    public var fileName: String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: slash)...])
    }
}

/// The movie table and the small tables around it (port of the movie parts of `tsuki.catalog_eboot.Eboot`).
public enum MovieTable {
    /// Reads the records until the terminator (a negative id; at VA 0xDCA590 in v01.01). The first record must be
    /// `titlebg1.mp4`.
    /// - Throws: `TsukiError.format` when the table is not where the analysed build has it.
    public static func read(_ eb: EbootReader) throws -> [MovieRecord] {
        var list: [MovieRecord] = []
        var va = eb.layout.movieTable
        while true {
            let id = try eb.i32(va)
            if id < 0 {
                break
            }

            let path = eb.cString(Int(try eb.u64(va + 8)), limit: 96)
            let raw = try eb.read(va + 0x10, 0x20)
            var fields = [UInt32](repeating: 0, count: 8)
            for i in 0..<8 {
                fields[i] = raw.u32(4 * i)
            }

            list.append(MovieRecord(movieId: Int(id), va: va, path: path, rawFields: fields))
            va += EbootAddresses.movieRecordSize
        }

        guard let first = list.first, first.path.hasSuffix("titlebg1.mp4") else {
            throw TsukiError.format("movie table not found at 0x\(String(eb.layout.movieTable, radix: 16))")
        }
        return list
    }

    /// The five language suffixes `ja en zc zt ko` (RELRO VA 0x42C030).
    /// - Throws: `TsukiError.format` when the table holds anything else (a different eboot version).
    public static func readLanguageSuffixes(_ eb: EbootReader) throws -> [String] {
        var suffixes = [String](repeating: "", count: eb.layout.languageCount)
        for i in 0..<suffixes.count {
            suffixes[i] = eb.cString(Int(try eb.u64(eb.layout.languageSuffixes + 8 * i)), limit: 8)
        }

        guard suffixes == MovieRules.languages else {
            throw TsukiError.format("unexpected language suffix table [\(suffixes.joined(separator: ", "))] (different eboot version?)")
        }
        return suffixes
    }

    /// The prologue movie id per language (text VA 0x200F70): 4, 46, 47, 106 in v01.01.
    public static func readPrologueIds(_ eb: EbootReader) throws -> [Int] {
        var ids = [Int](repeating: 0, count: 4)
        for i in 0..<4 {
            ids[i] = Int(try eb.u32(eb.layout.prologueTable + 4 * i))
        }
        return ids
    }
}

/// The movie selection rules of the engine (VA 0x5E280): the movie names in table order and the language remap of the
/// script command `_TOMP(id)` (docs/formats/archives_ui_movies.md 9). A port of the movie parts of `tsuki.catalog`.
public enum MovieRules {
    /// The prologue movie ids per language (text VA 0x200F70).
    public static let prologueIds = [4, 46, 47, 106]

    /// The language codes of the asset suffixes in engine order.
    public static let languages = ["ja", "en", "zc", "zt", "ko"]

    private static let phases = [
        "01_00", "02_00", "03_00", "04_00", "05_00", "05_01", "06_00", "06_01", "07_00", "07_01",
        "08_00", "08_01", "09_00", "09_01", "10_00", "10_01", "10_02", "11_00", "11_01", "12_00",
        "12_01", "13_00", "13_01", "14_00", "14_01", "15_01a", "15_01b",
    ]

    /// The 134 movie names (without `.mp4`) in table order; index = movie id.
    public static let names: [String] = buildNames()

    /// Port of `movie_index_for_language` (VA 0x5E280): the table index to play for a language-neutral id.
    public static func indexForLanguage(_ movieId: Int, _ lang: Int) -> Int {
        if movieId == 4 {
            return lang >= 0 && lang < 4 ? prologueIds[lang] : 46
        }

        if movieId >= 8 && movieId <= 34 {
            switch lang {
            case 0: return movieId
            case 3: return movieId + 99
            case 2: return movieId + 67
            default: return movieId + 40
            }
        }

        if movieId == 5 || movieId == 6 {
            if lang == 2 || lang == 3 { return movieId + 99 }
            return lang == 0 ? movieId : movieId + 97
        }

        return movieId
    }

    /// The file name (`prologue_en.mp4`) for a language-neutral id.
    public static func fileForLanguage(_ movieId: Int, _ lang: Int) -> String {
        names[indexForLanguage(movieId, lang)] + ".mp4"
    }

    /// Group, language and base of a movie-table index (port of `movie_info`).
    public static func info(_ index: Int) -> MovieInfo {
        let name = names[index]
        var lang = ""
        var baseName = name
        for candidate in ["en", "zc", "zt"] where name.hasSuffix("_" + candidate) {
            baseName = String(name.dropLast(candidate.count + 1))
            lang = candidate
            break
        }

        let group: String
        if baseName.hasPrefix("titlebg") {
            group = "title background loop"
        } else if baseName == "prologue" {
            group = "prologue"
        } else if baseName.hasPrefix("op") {
            group = "opening"
        } else if baseName.hasPrefix("phasetitle") {
            group = "chapter title card"
        } else if baseName == "phaseout" {
            group = "chapter end"
        } else if baseName.hasPrefix("ed") {
            group = "ending"
        } else if baseName.hasPrefix("credit") {
            group = "staff credits"
        } else if baseName == "TM_CI" {
            group = "TYPE-MOON logo"
        } else {
            group = "?"
        }

        let baseId = names.firstIndex(of: baseName) ?? -1
        var variants = [String](repeating: "", count: 4)
        for i in 0..<4 {
            variants[i] = fileForLanguage(baseId, i)
        }

        return MovieInfo(index: index, name: name, file: name + ".mp4", base: baseName, baseId: baseId,
                         lang: lang.isEmpty ? "neutral" : lang, group: group, variants: variants)
    }

    private static func buildNames() -> [String] {
        var names = ["titlebg1", "titlebg2", "titlebg3", "titlebg4", "prologue", "op1_arc", "op2_ciel", "phaseout"]
        names.append(contentsOf: phases.map { "phasetitle_" + $0 })
        names.append(contentsOf: ["ed01_arc", "ed02_ciel", "ed03_ciel", "TM_CI"])
        for i in 0..<7 {
            names.append("credit" + String(format: "%02d", i))
        }
        names.append(contentsOf: ["prologue_en", "prologue_zc"])
        names.append(contentsOf: phases.map { "phasetitle_\($0)_en" })
        names.append(contentsOf: phases.map { "phasetitle_\($0)_zc" })
        names.append(contentsOf: ["op1_arc_en", "op2_ciel_en", "op1_arc_zc", "op2_ciel_zc", "prologue_zt"])
        names.append(contentsOf: phases.map { "phasetitle_\($0)_zt" })
        precondition(names.count == 134, "\(names.count) movie names instead of 134")
        return names
    }
}

/// Group, language and base id of one movie-table index.
public struct MovieInfo: Sendable {
    /// The movie-table index.
    public let index: Int
    /// The name without extension.
    public let name: String
    /// The file name.
    public let file: String
    /// The name without the language suffix.
    public let base: String
    /// The index of `base` in the table.
    public let baseId: Int
    /// The suffix `en zc zt`, or `neutral`.
    public let lang: String
    /// What the movie is for.
    public let group: String
    /// The file played for languages ja, en, zc, zt of the base id.
    public let variants: [String]

    public init(index: Int, name: String, file: String, base: String, baseId: Int, lang: String, group: String,
                variants: [String]) {
        self.index = index
        self.name = name
        self.file = file
        self.base = base
        self.baseId = baseId
        self.lang = lang
        self.group = group
        self.variants = variants
    }
}
