import Foundation
import TsukiCore
import TsukiEngine

/// How well a dump matches what the port knows.
public enum BuildMatch: Sendable {
    /// The eboot is one the port was verified on: every address of the documents applies.
    case verified
    /// The eboot is another one of a known release (same title id); its tables are located by
    /// content.
    case knownRelease
    /// A title id the port has never seen; its tables are located by content.
    case unknown
}

/// One eboot the port knows.
public struct KnownBuild: Equatable, Sendable {
    /// A short name: "CUSA47999 01.01 (official update)".
    public let name: String
    /// The title id of its release.
    public let titleID: String
    /// The version the update's param.sfo carries.
    public let appVersion: String
    /// The release's region word.
    public let region: String
    /// The data languages of the release.
    public let languages: String
    /// Size of eboot.bin.
    public let ebootSize: Int
    /// SHA-256 of eboot.bin, lower-case hex.
    public let ebootSha256: String
    /// How far it was checked: "played end to end" or "tables byte-identical to the verified eboot".
    public let status: String

    public init(name: String, titleID: String, appVersion: String, region: String, languages: String,
                ebootSize: Int, ebootSha256: String, status: String) {
        self.name = name
        self.titleID = titleID
        self.appVersion = appVersion
        self.region = region
        self.languages = languages
        self.ebootSize = ebootSize
        self.ebootSha256 = ebootSha256
        self.status = status
    }
}

/// The builds the port knows. Only the first is verified; the others are recorded because their
/// tables were checked against it.
public enum KnownBuilds {
    /// The verified build: the analysed eboot of docs/RUNTIME_REQUIREMENTS.md 3.3.
    public static let verified = KnownBuild(
        name: "CUSA47999 01.01 (official 1.01 update eboot)",
        titleID: "CUSA47999",
        appVersion: "01.01",
        region: "Asia",
        languages: "ja en zc zt",
        ebootSize: BuildInfo.analysedEbootSize,
        ebootSha256: BuildInfo.analysedEbootSHA256,
        status: "played end to end; every address of the documents applies"
    )

    /// Every known build, the verified one first.
    public static let all: [KnownBuild] = [
        verified,
        KnownBuild(
            name: "CUSA47999 01.01 (1.01 eboot of the 5.05 / 6.72 / 7.xx backport)",
            titleID: "CUSA47999",
            appVersion: "01.01",
            region: "Asia",
            languages: "ja en zc zt",
            ebootSize: 12_767_802,
            ebootSha256: "9e74a735fb794c7aa42e798768eb89c52a81cadf9f2585dd287aff87116a02e4",
            status: "418 bytes differ from the verified eboot (the SDK version words and six code patches); every table is byte-identical and found at the same address"
        ),
    ]

    /// The known build with this eboot, or nil.
    public static func find(ebootSize: Int, sha256: String) -> KnownBuild? {
        all.first { $0.ebootSize == ebootSize && $0.ebootSha256.caseInsensitiveCompare(sha256) == .orderedSame }
    }

    /// The title ids of the known releases.
    public static let titleIDs: [String] = {
        var seen: Set<String> = []
        var ids: [String] = []
        for build in all where seen.insert(build.titleID.uppercased()).inserted {
            ids.append(build.titleID)
        }
        return ids
    }()
}

/// The identity of a dump: what param.sfo, the eboot and the data say.
public final class BuildIdentity {
    /// The folder's (or the update's) param.sfo; nil when none could be read.
    public let sfo: ParamSfo?
    /// Size of eboot.bin.
    public let ebootSize: Int
    /// SHA-256 of eboot.bin, lower-case hex.
    public let ebootSha256: String
    /// The known build this eboot is, or nil.
    public let known: KnownBuild?
    /// Verified, another eboot of a known release, or unknown.
    public let match: BuildMatch
    /// The languages whose script text is real (not the U+3000 placeholder of the Korean slot).
    public let textLanguages: [Language]
    /// The languages that have glyph pages with glyphs (`ft_<lang>.mrg` with non-blank pages).
    public let fontLanguages: [Language]
    /// The languages that have localized UI sheets in allpac3 (`*_<lang>.mrg`).
    public let sheetLanguages: [Language]
    /// The languages that have their own movies (ja: the unsuffixed files; en, zc, zt:
    /// `*_<lang>.mp4`).
    public let movieLanguages: [Language]
    /// The selectable languages the data supports: text, glyph pages and UI sheets all present
    /// (movies fall back to Japanese).
    public let availableLanguages: [Language]

    private init(sfo: ParamSfo?, ebootSize: Int, ebootSha256: String, text: [Language], fonts: [Language],
                 sheets: [Language], movies: [Language]) {
        self.sfo = sfo
        self.ebootSize = ebootSize
        self.ebootSha256 = ebootSha256
        self.textLanguages = text
        self.fontLanguages = fonts
        self.sheetLanguages = sheets
        self.movieLanguages = movies
        let known = KnownBuilds.find(ebootSize: ebootSize, sha256: ebootSha256)
        self.known = known
        if known != nil {
            self.match = .verified
        } else if let titleID = sfo?["TITLE_ID"] ?? BuildIdentity.titleIdFromContent(sfo?["CONTENT_ID"]),
                  KnownBuilds.titleIDs.contains(where: { $0.caseInsensitiveCompare(titleID) == .orderedSame }) {
            self.match = .knownRelease
        } else {
            self.match = .unknown
        }
        self.availableLanguages = Language.selectable.filter { language in
            text.contains(language) && fonts.contains(language) && sheets.contains(language)
        }
    }

    /// TITLE_ID, or the title id inside CONTENT_ID (`HP3279-CUSA47999_00-...`), or nil.
    public var titleID: String? { sfo?["TITLE_ID"] ?? BuildIdentity.titleIdFromContent(sfo?["CONTENT_ID"]) }

    /// APP_VER (01.01), else VERSION, or nil.
    public var appVersion: String? { sfo?["APP_VER"] ?? sfo?["VERSION"] }

    /// CONTENT_ID, or nil.
    public var contentId: String? { sfo?["CONTENT_ID"] }

    /// CATEGORY: `gd` a game, `gp` a patch.
    public var category: String? { sfo?["CATEGORY"] }

    /// The plain TITLE of param.sfo.
    public var title: String? { sfo?["TITLE"] }

    /// "CUSA47999 01.01" (the title id and version, "unknown" for a missing field).
    public var shortName: String {
        "\(titleID ?? "unknown title") \(appVersion ?? "(version unknown)")"
    }

    /// One line: "known build: CUSA47999 01.01 (official 1.01 update eboot)" or "other version of a
    /// known release: CUSA47999 01.00, eboot 12,345,678 bytes, SHA-256 ab12...".
    public func describe() -> String {
        switch match {
        case .verified:
            return "known build: \(known?.name ?? KnownBuilds.verified.name)"
        case .knownRelease:
            return "other version of a known release: \(shortName), eboot \(buildNumber(ebootSize)) bytes, SHA-256 \(ebootSha256)"
        case .unknown:
            return "unknown build: \(shortName), eboot \(buildNumber(ebootSize)) bytes, SHA-256 \(ebootSha256)"
        }
    }

    /// "text ja en zc zt; fonts ja en zc zt; sheets ja en zc zt ko; movies ja en zc zt; selectable
    /// ja en zc zt".
    public func describeLanguages() -> String {
        let codes = { (languages: [Language]) in
            languages.isEmpty ? "none" : languages.map(\.code).joined(separator: " ")
        }
        return "text \(codes(textLanguages)); fonts \(codes(fontLanguages)); sheets \(codes(sheetLanguages)); "
            + "movies \(codes(movieLanguages)); selectable \(codes(availableLanguages))"
    }

    /// A multi-line summary for the build check output and the log.
    public func report() -> String {
        var text = describe() + "\n"
        if sfo != nil {
            text += "param.sfo: TITLE_ID \(titleID ?? "-"), APP_VER \(appVersion ?? "-"), CATEGORY \(category ?? "-"), "
                + "CONTENT_ID \(contentId ?? "-"), TITLE \(title ?? "-")\n"
        } else {
            text += "param.sfo: not read\n"
        }
        text += "languages: \(describeLanguages())\n"
        return text
    }

    /// The title id inside a content id (`HP3279-CUSA47999_00-GAME000TSUKIHIME`).
    public static func titleIdFromContent(_ contentId: String?) -> String? {
        guard let contentId,
              let dash = contentId.firstIndex(of: "-"),
              let underscore = contentId.firstIndex(of: "_"),
              dash < underscore else { return nil }
        return String(contentId[contentId.index(after: dash)..<underscore])
    }

    /// The message a copy the port cannot read is rejected with: it names the build and the tables
    /// and asks for the log file.
    public func unsupportedBuildMessage(_ result: LocateResult) -> String {
        let names = result.missing.map { $0.name }.joined(separator: ", ")
        return "This copy of the game (\(shortName), eboot.bin \(buildNumber(ebootSize)) bytes, SHA-256 \(ebootSha256)) "
            + "is a build the port does not know, and \(result.missing.count) of its "
            + "\(result.found.count + result.missing.count) tables could not be found: \(names). "
            + "Please report it with the log file."
    }

    /// Identifies the dump behind `files`: param.sfo, the eboot (hashed; `eboot` saves a second read
    /// when the caller has the bytes) and the languages present in the data. Reads small ranges only;
    /// never throws for a damaged file (what cannot be read counts as absent).
    public static func identify(_ files: GameFiles, eboot: ByteSpan? = nil) -> BuildIdentity {
        var sfo: ParamSfo? = nil
        do {
            if files.exists("sce_sys/param.sfo"), try files.length(of: "sce_sys/param.sfo") <= ParamSfo.maxFileSize {
                sfo = ParamSfo.tryParse(try files.readAll("sce_sys/param.sfo"))
            }
        } catch {
            sfo = nil
        }

        var size = 0
        var sha = ""
        do {
            if let eboot {
                size = eboot.count
                sha = sha256Hex(eboot)
            } else if files.exists("eboot.bin") {
                size = try files.length(of: "eboot.bin")
                if size <= 64 * 1024 * 1024 {
                    sha = sha256Hex(try files.readAll("eboot.bin"))
                }
            }
        } catch {
            sha = ""
        }

        return BuildIdentity(
            sfo: sfo,
            ebootSize: size,
            ebootSha256: sha,
            text: textLanguagesOf(files),
            fonts: fontLanguagesOf(files),
            sheets: sheetLanguagesOf(files),
            movies: movieLanguagesOf(files)
        )
    }

    /// The languages of `script_text.mrg` whose string blob is real text: the Korean slot of the
    /// retail data is 43,969 copies of U+3000, so a blob counts when it holds at least three
    /// distinct lines (read from its first 64 KB).
    private static func textLanguagesOf(_ files: GameFiles) -> [Language] {
        let path = "image/script_text.mrg"
        var list: [Language] = []
        do {
            if !files.exists(path) { return list }

            let length = try files.length(of: path)
            let head = try files.readRange(path, offset: 0, count: min(length, 8))
            let headSpan = ByteSpan(head)
            if headSpan.count < 8 || !Mzp.isContainer(headSpan) { return list }

            let count = Int(headSpan.u16(6))
            let sections = try MzpContainer.readTable(
                ByteSpan(try files.readRange(path, offset: 0, count: 8 + 8 * count)), totalLength: length)
            for k in 0..<AnalysedBuild.textLanguages.count where 2 * k + 1 < sections.count {
                let blob = sections[2 * k + 1]
                let n = min(blob.size, 64 * 1024)
                if n < 16 { continue }

                let sample = try files.readRange(path, offset: blob.offset, count: n)
                var distinct: Set<String> = []
                var start = 0
                var i = 0
                while i + 1 < sample.count && distinct.count < 3 {
                    if sample[i] == 0x0D && sample[i + 1] == 0x0A {
                        distinct.insert(hexLower(sample[start..<i]))
                        start = i + 2
                    }
                    i += 1
                }

                if distinct.count >= 3, let language = Language(rawValue: UInt8(k)) {
                    list.append(language)
                }
            }
        } catch {
            // a damaged text file supports no language
        }
        return list
    }

    /// The languages with a glyph file whose pages carry glyphs: `ft_<lang>.mrg` at least 1 MB (the
    /// all-blank Korean file is 583 KB, the smallest real one, English, 1.2 MB).
    private static func fontLanguagesOf(_ files: GameFiles) -> [Language] {
        var list: [Language] = []
        for language in Language.allCases {
            let path = "image/ft_\(language.code).mrg"
            do {
                if files.exists(path), try files.length(of: path) >= 1_000_000 {
                    list.append(language)
                }
            } catch {
                // absent
            }
        }
        return list
    }

    /// The languages with localized UI sheets: `allpac3.nam` names ending in `_<lang>.mrg`.
    private static func sheetLanguagesOf(_ files: GameFiles) -> [Language] {
        var list: [Language] = []
        do {
            if !files.exists("image/allpac3.nam") { return list }

            let nam = try NamTable.parseNam32(try files.readAll("image/allpac3.nam"))
            let names = nam.names.map { $0.uppercased() }
            for language in Language.allCases {
                let suffix = "_\(language.code.uppercased()).MRG"
                if names.filter({ $0.hasSuffix(suffix) }).count >= 3 {
                    list.append(language)
                }
            }
        } catch {
            // no sheets
        }
        return list
    }

    /// The languages with movies: Japanese when any unsuffixed mp4 exists, en / zc / zt when at
    /// least three `*_<lang>.mp4` exist.
    private static func movieLanguagesOf(_ files: GameFiles) -> [Language] {
        var list: [Language] = []
        let movies = files.listFiles(in: "image/movie")
        let mp4 = movies.filter { $0.lowercased().hasSuffix(".mp4") }
            .map { $0.dropLast(4).lowercased() }
        let suffixes = ["_en", "_zc", "_zt"]
        if mp4.contains(where: { name in !suffixes.contains(where: { name.hasSuffix($0) }) }) {
            list.append(.ja)
        }

        for language in [Language.en, .zc, .zt] {
            let suffix = "_" + language.code
            if mp4.filter({ $0.hasSuffix(suffix) }).count >= 3 {
                list.append(language)
            }
        }
        return list
    }
}

extension TsukiError {
    /// The error for a copy whose eboot is not one the port knows and whose tables could not be
    /// found by content: the same message as the C# `UnsupportedBuildException`.
    public static func unsupportedBuild(_ identity: BuildIdentity, _ result: LocateResult) -> TsukiError {
        .unsupported(identity.unsupportedBuildMessage(result))
    }
}
