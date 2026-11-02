import Foundation
import TsukiCore
import TsukiEngine
import TsukiData

/// How far a folder is from being the game.
public enum FolderState: Sendable, Equatable {
    /// No folder has been chosen.
    case notSet
    /// The path does not exist.
    case missing
    /// The folder has no eboot.bin.
    case notTheGame
    /// It looks like the game, but a file is missing, or tables could not be found.
    case incomplete
    /// The game is complete and can be played.
    case ready
    /// A .pkg file: the game must be extracted first.
    case pkgFile
    /// The update folder alone, without the base game beside it.
    case updateOnly
    /// Several game folders inside the chosen one.
    case several
}

/// What the launcher knows about a game folder.
public struct GameFolderInfo: Sendable, Equatable {
    public let path: String?
    public let state: FolderState
    public let titleId: String?
    public let appVersion: String?
    public let title: String?
    public let ebootBytes: Int64
    public let totalBytes: Int64
    public let checksPassed: Int
    public let checksTotal: Int
    public let problems: [String]?
    public let archives: Int
    public let movies: Int
    public let sfoVersion: String?
    public let layout: GameLayout?
    public let build: BuildMatch
    public let buildName: String?
    public let tablesNote: String?
    public let languages: [Language]?

    public init(
        path: String?,
        state: FolderState,
        titleId: String? = nil,
        appVersion: String? = nil,
        title: String? = nil,
        ebootBytes: Int64 = 0,
        totalBytes: Int64 = 0,
        checksPassed: Int = 0,
        checksTotal: Int = 0,
        problems: [String]? = nil,
        archives: Int = 0,
        movies: Int = 0,
        sfoVersion: String? = nil,
        layout: GameLayout? = nil,
        build: BuildMatch = .verified,
        buildName: String? = nil,
        tablesNote: String? = nil,
        languages: [Language]? = nil
    ) {
        self.path = path
        self.state = state
        self.titleId = titleId
        self.appVersion = appVersion
        self.title = title
        self.ebootBytes = ebootBytes
        self.totalBytes = totalBytes
        self.checksPassed = checksPassed
        self.checksTotal = checksTotal
        self.problems = problems
        self.archives = archives
        self.movies = movies
        self.sfoVersion = sfoVersion
        self.layout = layout
        self.build = build
        self.buildName = buildName
        self.tablesNote = tablesNote
        self.languages = languages
    }

    /// True when the game can be started from this folder.
    public var isReady: Bool { state == .ready }

    /// True when the folder holds the verified build.
    public var isVerifiedBuild: Bool {
        isReady && build == .verified && (buildName == nil || buildName!.hasPrefix("known build: " + KnownBuilds.verified.name))
    }

    /// The failed checks' messages (never nil).
    public var problemList: [String] { problems ?? [] }

    /// The selectable languages (every one of the four when unknown).
    public var languageList: [Language] { languages ?? [.ja, .en, .zc, .zt] }

    /// The update folder beside the game whose files take precedence, or nil.
    public var patchFolder: String? { layout?.patchFolder }

    /// An update folder beside the game that is not needed, or nil.
    public var ignoredPatchFolder: String? { layout?.ignoredPatchFolder }

    /// Build description text.
    public var buildText: String {
        guard state == .ready else { return "" }
        if isVerifiedBuild { return "verified build" }
        switch build {
        case .verified:
            return buildName ?? "known build"
        case .knownRelease:
            return "other version of a known release (\(titleId ?? "CUSA47999") \(appVersion ?? "01.00")): tables found by content"
        default:
            return "unknown build (\(titleId ?? "no title id") \(appVersion ?? "?")): tables found by content"
        }
    }

    /// A one-line reason for a folder that is not ready.
    public var summary: String {
        switch state {
        case .notSet:
            return "No game folder chosen yet."
        case .missing:
            return "This folder does not exist."
        case .notTheGame:
            return "No eboot.bin in this folder. Choose the CUSA47999 folder (it holds eboot.bin and image/)."
        case .pkgFile:
            return "This is a PS4 package (.pkg). Extract it first (shadPS4, or a PKG extractor), then choose the extracted CUSA47999 folder."
        case .updateOnly:
            return "This folder holds only the game's update. The base game folder (with image/allpac0.mrg and the other archives) must be beside it."
        case .several:
            let list = layout?.candidateList ?? []
            let names = list.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
            let suffix = names.isEmpty ? "" : " (\(names))"
            return "Several game folders are inside this one\(suffix). Choose one of them."
        case .incomplete:
            return problemList.first ?? "The game files are incomplete."
        case .ready:
            return "Ready."
        }
    }
}

/// Inspects a game folder, read-only.
public enum GameFolderCheck {
    public static let analysedVersion = "01.01"

    public static let notSet = GameFolderInfo(path: nil, state: .notSet)

    public static func resolve(_ path: String?) -> String {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return ""
        }
        let layout = GameLayoutResolver.resolve(path)
        if layout.isGame, let primary = layout.primaryFolder {
            return primary
        }
        return path.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    public static func inspect(_ folder: String?, measureSize: Bool = true) -> GameFolderInfo {
        guard let folder = folder?.trimmingCharacters(in: .whitespacesAndNewlines), !folder.isEmpty else {
            return notSet
        }

        let layout = GameLayoutResolver.resolve(folder)
        let path = layout.primaryFolder ?? layout.chosen ?? folder.trimmingCharacters(in: CharacterSet(charactersIn: "\""))

        switch layout.kind {
        case .notSet:
            return notSet
        case .missing:
            return GameFolderInfo(path: path, state: .missing, layout: layout)
        case .pkgFile:
            return GameFolderInfo(path: path, state: .pkgFile, layout: layout)
        case .updateOnly:
            return GameFolderInfo(path: path, state: .updateOnly, layout: layout)
        case .several:
            return GameFolderInfo(path: path, state: .several, layout: layout)
        case .noGame:
            return GameFolderInfo(path: path, state: .notTheGame, layout: layout)
        default:
            break
        }

        let ebootPath = (path as NSString).appendingPathComponent("eboot.bin")
        let ebootBytes = safeLength(ebootPath)
        let total = measureSize ? folderSize(path) + (layout.patchFolder.map { folderSize($0) } ?? 0) : 0

        do {
            let report = try BuildCheck.run(layout)
            let counts = report.counts
            let identity = report.identity
            let sfoVersion = identity?.appVersion
            let verified = report.accepted
            let problems = report.failures.map(\.message).filter { !$0.isEmpty }
            let problemsPrefix = Array(problems.prefix(8))

            return GameFolderInfo(
                path: path,
                state: report.usable ? .ready : .incomplete,
                titleId: identity?.titleID,
                appVersion: verified ? analysedVersion : sfoVersion,
                title: identity?.title,
                ebootBytes: ebootBytes,
                totalBytes: total,
                checksPassed: report.checks.filter(\.passed).count,
                checksTotal: report.checks.count,
                problems: problemsPrefix,
                archives: counts.tripletEntries.count + counts.standaloneSections.count,
                movies: counts.movieFiles,
                sfoVersion: sfoVersion,
                layout: layout,
                build: identity?.match ?? .unknown,
                buildName: identity?.describe(),
                tablesNote: report.locations?.summary(),
                languages: identity?.availableLanguages
            )
        } catch {
            let sfoPath = ((layout.patchFolder ?? path) as NSString).appendingPathComponent("sce_sys/param.sfo")
            let sfo = ParamSfo.tryRead(sfoPath)
            let titleId = sfo?["TITLE_ID"] ?? BuildIdentity.titleIdFromContent(sfo?["CONTENT_ID"])
            let appVer = sfo?["APP_VER"] ?? sfo?["VERSION"]
            let title = sfo?["TITLE"]

            return GameFolderInfo(
                path: path,
                state: .incomplete,
                titleId: titleId,
                appVersion: appVer,
                title: title,
                ebootBytes: ebootBytes,
                totalBytes: total,
                problems: ["The folder could not be read: \(error.localizedDescription)"],
                sfoVersion: sfo?["APP_VER"],
                layout: layout
            )
        }
    }

    public static func folderSize(_ path: String) -> Int64 {
        var total: Int64 = 0
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(atPath: path) else { return 0 }
        while let file = enumerator.nextObject() as? String {
            let full = (path as NSString).appendingPathComponent(file)
            total += safeLength(full)
        }
        return total
    }

    private static func safeLength(_ file: String) -> Int64 {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: file)
            return (attrs[.size] as? NSNumber)?.int64Value ?? 0
        } catch {
            return 0
        }
    }

    public static func formatSize(_ bytes: Int64) -> String {
        if bytes >= 1 << 30 {
            return String(format: "%.1f GB", Double(bytes) / Double(1 << 30))
        } else if bytes >= 1 << 20 {
            return String(format: "%.1f MB", Double(bytes) / Double(1 << 20))
        } else if bytes >= 1 << 10 {
            return String(format: "%.1f KB", Double(bytes) / Double(1 << 10))
        } else {
            return "\(bytes) B"
        }
    }
}
