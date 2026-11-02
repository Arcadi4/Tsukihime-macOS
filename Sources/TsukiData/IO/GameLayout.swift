import Foundation
import TsukiCore
import TsukiEngine

/// How a player's dump of the game is laid out on disk (package K25): the extracted app folder itself,
/// a parent folder with the game inside, the base game and the update in two folders
/// (`CUSA47999` + `CUSA47999-patch`, `CUSA47999-app` + `CUSA47999-patch`, `CUSA47999` +
/// `CUSA47999-UPDATE`), or a `.pkg` that was never extracted. Resolving looks at directory listings
/// and small files only; the layout then reads through one view where the update's files override the
/// base's.
public enum GameLayoutKind: Sendable {
    /// Nothing was chosen.
    case notSet
    /// The path does not exist.
    case missing
    /// A `.pkg` file: the game must be extracted first.
    case pkgFile
    /// A folder (or a folder with subfolders) that holds no game: no `eboot.bin` with an `image/`
    /// folder anywhere one or two levels down.
    case noGame
    /// The update (patch) folder alone, without the base game beside it.
    case updateOnly
    /// Several different games or title ids were found inside; the player must choose one.
    case several
    /// One game folder: `eboot.bin` and `image/`.
    case game
    /// A base game folder with an update folder beside it; the update's files win.
    case gameWithUpdate
}

extension GameLayoutKind: CustomStringConvertible {
    /// The C# enum name, for messages that quote the resolver's verdict.
    public var description: String {
        switch self {
        case .notSet: return "NotSet"
        case .missing: return "Missing"
        case .pkgFile: return "PkgFile"
        case .noGame: return "NoGame"
        case .updateOnly: return "UpdateOnly"
        case .several: return "Several"
        case .game: return "Game"
        case .gameWithUpdate: return "GameWithUpdate"
        }
    }
}

/// A resolved game layout.
public struct GameLayout: Equatable, Sendable {
    /// The path as the player gave it (trimmed), or nil when nothing was chosen.
    public let chosen: String?
    /// What it is.
    public let kind: GameLayoutKind
    /// The folder that holds the full game (`image/` with the archives), when there is one.
    public let baseFolder: String?
    /// The update folder whose files override the base's, when there is one.
    public let patchFolder: String?
    /// For `.several`: the game folders that were found.
    public let candidates: [String]?
    /// An update folder beside the game that is not layered, because the game folder already holds an
    /// update as new as it (a known eboot).
    public let ignoredPatchFolder: String?

    public init(chosen: String?, kind: GameLayoutKind, baseFolder: String? = nil, patchFolder: String? = nil,
                candidates: [String]? = nil, ignoredPatchFolder: String? = nil) {
        self.chosen = chosen
        self.kind = kind
        self.baseFolder = baseFolder
        self.patchFolder = patchFolder
        self.candidates = candidates
        self.ignoredPatchFolder = ignoredPatchFolder
    }

    /// True when the game can be opened from this layout.
    public var isGame: Bool { kind == .game || kind == .gameWithUpdate }

    /// The folder the game is remembered and started by: the base folder.
    public var primaryFolder: String? { baseFolder }

    /// The game folders that were found (empty when none).
    public var candidateList: [String] { candidates ?? [] }

    /// The read-only view of the files: the update over the base, or the base alone.
    public func openFiles() throws -> GameFiles {
        guard let baseFolder else {
            throw TsukiError.state("the layout \(kind) holds no game folder")
        }

        let baseFiles = DirectoryGameFiles(root: baseFolder)
        guard let patchFolder else { return baseFiles }
        return LayeredGameFiles([DirectoryGameFiles(root: patchFolder), baseFiles])
    }

    /// One line for the log: `/games/CUSA47999 + update folder /games/CUSA47999-patch`.
    public func describe() -> String {
        let chosenText = chosen ?? ""
        switch kind {
        case .notSet:
            return "no game folder"
        case .missing:
            return "\(chosenText): does not exist"
        case .pkgFile:
            return "\(chosenText): a .pkg file, not extracted"
        case .noGame:
            return "\(chosenText): no game inside"
        case .updateOnly:
            return "\(chosenText): the update folder alone, no base game beside it"
        case .several:
            return "\(chosenText): \(candidateList.count) game folders inside"
        case .game:
            guard let ignored = ignoredPatchFolder else { return baseFolder ?? "" }
            return "\(baseFolder ?? "") (the update folder \(ignored) beside it is not needed: the game folder already holds an update as new)"
        case .gameWithUpdate:
            return "\(baseFolder ?? "") + update folder \(patchFolder ?? "")"
        }
    }
}

/// The chosen path holds no game that can be opened: a `.pkg`, an update alone, a folder without the
/// game, or several games (package K25). Mirrors the C# `GameLayoutException` (an `IOException` there);
/// the layout travels with the error so the launcher can say what to do.
public struct GameLayoutException: Error, CustomStringConvertible, Equatable {
    /// What the path turned out to be.
    public let layout: GameLayout

    /// Creates the error for a layout that is not a game.
    public init(_ layout: GameLayout) {
        self.layout = layout
    }

    public var description: String {
        let chosen = layout.chosen ?? ""
        switch layout.kind {
        case .pkgFile:
            return "\(chosen) is a PS4 package (.pkg). It must be extracted first (shadPS4, a PKG extractor); then choose the extracted \(GameLayoutResolver.titleId) folder."
        case .updateOnly:
            return "\(chosen) holds only the game's update. The base game (the folder with image\\allpac0.mrg and the other archives) must be beside it."
        case .several:
            let names = layout.candidateList.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
            return "\(chosen) holds several game folders (\(names)); choose one of them."
        case .missing:
            return "\(chosen) does not exist."
        case .notSet:
            return "no game folder was chosen."
        default:
            return "\(chosen) holds no game: no folder with eboot.bin and image\\ inside it."
        }
    }
}

/// Turns the path a player chose into a `GameLayout`. Reads directory listings and `sce_sys/param.sfo`
/// only; writes nothing.
public enum GameLayoutResolver {
    /// The title id of TSUKIHIME -A piece of blue glass moon- (Asia); the folder name every extractor
    /// gives the game.
    public static let titleId = "CUSA47999"

    /// The folder name suffixes extractors give the update: `CUSA47999-patch` (some PKG extractors),
    /// `CUSA47999-UPDATE` (shadPS4), `_patch`, `-update`.
    public static let patchSuffixes = ["-patch", "_patch", "-update", "_update"]

    /// The folder name suffixes extractors give the base game beside a patch: `CUSA47999-app` (PS4 pkg
    /// tools).
    public static let baseSuffixes = ["-app", "_app"]

    /// The folders inside a game folder a player may pick by mistake; the game is their parent.
    private static let insideFolders = ["image", "data", "sce_sys", "sce_module"]

    private static let maxEbootSize = 64 * 1024 * 1024

    /// Resolves `path` (a folder, a file, quotes allowed).
    public static func resolve(_ path: String?) -> GameLayout {
        guard let path else {
            return GameLayout(chosen: nil, kind: .notSet)
        }

        var chosen = trim(path.trimmingCharacters(in: .whitespacesAndNewlines), character: "\"")
        guard !chosen.isEmpty else {
            return GameLayout(chosen: nil, kind: .notSet)
        }

        let unixRoot = chosen == "/"
        if !unixRoot && chosen.allSatisfy({ $0 == "\\" || $0 == "/" }) {
            return GameLayout(chosen: nil, kind: .notSet)
        }

        if chosen.count == 2, chosen.hasSuffix(":"), let first = chosen.first, first.isASCII, first.isLetter {
            // A bare drive letter means its root, not the process's current directory on that drive.
            chosen += "/"
        }

        if !FileManager.default.fileExists(atPath: chosen) {
            chosen = trim(chosen, character: "\\")
        }

        guard let full = fullPath(chosen) else {
            return GameLayout(chosen: chosen, kind: .missing)
        }
        chosen = full

        if isFile(chosen) {
            if chosen.lowercased().hasSuffix(".pkg") {
                return GameLayout(chosen: chosen, kind: .pkgFile)
            }

            // eboot.bin or any other file inside the game: its folder.
            guard let directory = parentDirectory(of: chosen) else {
                return GameLayout(chosen: chosen, kind: .noGame)
            }
            return resolve(directory)
        }

        guard isDirectory(chosen) else {
            return GameLayout(chosen: chosen, kind: .missing)
        }

        // A folder inside the game (image/, data/, sce_sys/): its parent.
        let leaf = fileName(chosen)
        if let parent = parentDirectory(of: chosen),
           insideFolders.contains(where: { $0.lowercased() == leaf.lowercased() }),
           hasEboot(parent) {
            chosen = parent
        }

        if hasEboot(chosen) {
            return classify(chosen: chosen, folder: chosen)
        }

        // The folder above the game (one or two levels): every game folder below, patch folders paired
        // with their base.
        var inside = subdirectories(of: chosen).filter(hasEboot)
        if inside.isEmpty {
            for sub in subdirectories(of: chosen) {
                inside.append(contentsOf: subdirectories(of: sub).filter(hasEboot))
            }
        }

        let bases = inside.filter { !isPatchFolder($0) }
        let patches = inside.filter(isPatchFolder)
        if bases.isEmpty && patches.count == 1 {
            return classify(chosen: chosen, folder: patches[0])
        }

        if bases.count == 1 {
            return classify(chosen: chosen, folder: bases[0])
        }

        if bases.count > 1 {
            // Several: the one named by the title id wins when it is the only one.
            let titled = bases.filter { fileName($0).lowercased().hasPrefix(titleId.lowercased()) }
            if titled.count == 1 {
                return classify(chosen: chosen, folder: titled[0])
            }

            return GameLayout(chosen: chosen, kind: .several, candidates: bases)
        }

        if let patch = patches.first {
            return GameLayout(chosen: chosen, kind: .updateOnly, patchFolder: patch)
        }

        return GameLayout(chosen: chosen, kind: .noGame)
    }

    /// A folder with `eboot.bin` (the base game, a merged dump, or an update).
    private static func hasEboot(_ folder: String) -> Bool {
        resolveFile(folder, "eboot.bin") != nil
    }

    /// A folder that holds the full game: `eboot.bin` and the first picture archive.
    private static func isFullGame(_ folder: String) -> Bool {
        hasEboot(folder) && resolveFile(folder, "image/allpac0.hed") != nil
    }

    private static func resolveFile(_ folder: String, _ relativePath: String) -> String? {
        DirectoryGameFiles(root: folder).resolveFile(relativePath)
    }

    private static func readParamSfo(_ folder: String) -> ParamSfo? {
        guard let path = resolveFile(folder, "sce_sys/param.sfo") else { return nil }
        return ParamSfo.tryRead(path)
    }

    /// True for an update folder: its `param.sfo` says `CATEGORY gp` (a patch package; `gd` is the
    /// game), else its name ends in a patch suffix. A folder with an eboot but no archives and neither
    /// mark is an incomplete game, not an update (the build check then names the missing files).
    public static func isPatchFolder(_ folder: String) -> Bool {
        if let sfo = readParamSfo(folder), let category = sfo["CATEGORY"] {
            return category.lowercased() == "gp"
        }

        let name = fileName(folder).lowercased()
        return patchSuffixes.contains { name.hasSuffix($0) }
    }

    /// The folder with `eboot.bin`: a game (with a patch beside it when there is one), or an update
    /// alone (with its base beside it when there is one).
    private static func classify(chosen: String, folder: String) -> GameLayout {
        if isPatchFolder(folder) {
            guard let baseBeside = findBaseBeside(folder) else {
                return GameLayout(chosen: chosen, kind: .updateOnly, patchFolder: folder)
            }
            return pair(chosen: chosen, baseFolder: baseBeside, patchFolder: folder)
        }

        if !isFullGame(folder) {
            // An eboot without archives and not marked as a patch: the folder is incomplete; report it
            // as the game so the build check names the missing files.
            return GameLayout(chosen: chosen, kind: .game, baseFolder: folder)
        }

        guard let patch = findPatchBeside(folder) else {
            return GameLayout(chosen: chosen, kind: .game, baseFolder: folder)
        }
        return pair(chosen: chosen, baseFolder: folder, patchFolder: patch)
    }

    /// The update takes precedence when its metadata is explicitly newer than the base's. Otherwise a
    /// known base eboot at least as new as the update keeps a merged dump's stale sibling update from
    /// being layered again.
    private static func pair(chosen: String, baseFolder: String, patchFolder: String) -> GameLayout {
        guard baseIsCurrent(baseFolder: baseFolder, patchFolder: patchFolder) == nil else {
            return GameLayout(chosen: chosen, kind: .game, baseFolder: baseFolder, ignoredPatchFolder: patchFolder)
        }
        return GameLayout(chosen: chosen, kind: .gameWithUpdate, baseFolder: baseFolder, patchFolder: patchFolder)
    }

    /// The known base eboot's version when the sibling update is unnecessary and metadata does not show
    /// a newer update; nil otherwise.
    private static func baseIsCurrent(baseFolder: String, patchFolder: String) -> String? {
        do {
            let files = DirectoryGameFiles(root: baseFolder)
            let size = try files.length(of: "eboot.bin")
            guard size <= maxEbootSize else { return nil }

            let sha = sha256Hex(try files.readAll("eboot.bin"))
            guard let known = KnownBuilds.find(ebootSize: size, sha256: sha) else { return nil }

            return currentBaseVersion(baseFolder: baseFolder, patchFolder: patchFolder, known: known)
        } catch {
            return nil
        }
    }

    private static func currentBaseVersion(baseFolder: String, patchFolder: String, known: KnownBuild) -> String? {
        let baseVersion = readParamSfo(baseFolder)?["APP_VER"]
        let patchVersion = readParamSfo(patchFolder)?["APP_VER"]
        if let baseVersion, let patchVersion, isAppVersion(baseVersion), isAppVersion(patchVersion),
           patchVersion > baseVersion {
            return nil
        }

        if let patchVersion, patchVersion > known.appVersion {
            return nil
        }
        return known.appVersion
    }

    /// Fixed-width `NN.NN` versions sort numerically (ASCII ordinal order); other metadata keeps the
    /// existing fallback.
    private static func isAppVersion(_ version: String) -> Bool {
        let digits = Array(version.utf8)
        guard digits.count == 5, digits[2] == UInt8(ascii: ".") else { return false }
        return digits[0].isASCIIDigit && digits[1].isASCIIDigit && digits[3].isASCIIDigit && digits[4].isASCIIDigit
    }

    /// The update folder beside a base folder: `<name>-patch`, `<name>-UPDATE`, ... or the same with
    /// the base's `-app` suffix removed.
    public static func findPatchBeside(_ baseFolder: String) -> String? {
        guard let parent = parentDirectory(of: baseFolder) else { return nil }

        let name = fileName(baseFolder)
        let lowered = name.lowercased()
        var stems = [name]
        for suffix in baseSuffixes where lowered.hasSuffix(suffix) {
            stems.append(String(name.dropLast(suffix.count)))
        }

        // The siblings as the disk spells them (the comparison ignores case): first the exact suffixes,
        // then any sibling named after the stem that is a patch.
        let siblings = subdirectories(of: parent).filter { $0.lowercased() != baseFolder.lowercased() }
        for stem in stems {
            for suffix in patchSuffixes {
                let wanted = (stem + suffix).lowercased()
                for candidate in siblings where fileName(candidate).lowercased() == wanted {
                    if hasEboot(candidate) && isPatchFolder(candidate) {
                        return candidate
                    }
                }
            }
        }

        for sibling in siblings {
            let siblingName = fileName(sibling)
            let loweredSibling = siblingName.lowercased()
            let namedAfterStem = stems.contains { loweredSibling.hasPrefix($0.lowercased()) && siblingName.count > $0.count }
            if namedAfterStem && hasEboot(sibling) && isPatchFolder(sibling) {
                return sibling
            }
        }

        return nil
    }

    /// The base game beside an update folder: the name without its patch suffix, or that plus `-app`.
    public static func findBaseBeside(_ patchFolder: String) -> String? {
        guard let parent = parentDirectory(of: patchFolder) else { return nil }

        let name = fileName(patchFolder)
        let lowered = name.lowercased()
        var stems: [String] = []
        for suffix in patchSuffixes where lowered.hasSuffix(suffix) {
            stems.append(String(name.dropLast(suffix.count)))
        }

        let siblings = subdirectories(of: parent).filter { $0.lowercased() != patchFolder.lowercased() }
        for stem in stems {
            for candidate in [stem] + baseSuffixes.map({ stem + $0 }) {
                let wanted = candidate.lowercased()
                for directory in siblings where fileName(directory).lowercased() == wanted {
                    if isFullGame(directory) {
                        return directory
                    }
                }
            }
        }

        // Any full game beside it that shares the title id.
        let titleID = readParamSfo(patchFolder)?["TITLE_ID"]
        for sibling in siblings where isFullGame(sibling) && !isPatchFolder(sibling) {
            let siblingID = readParamSfo(sibling)?["TITLE_ID"]
            if let titleID, let siblingID, siblingID.lowercased() != titleID.lowercased() {
                continue
            }
            return sibling
        }

        return nil
    }

    /// A short note for a layout that is a game: "update folder CUSA47999-patch beside it; its files
    /// take precedence", or why a sibling update was left alone, or nil.
    public static func note(_ layout: GameLayout) -> String? {
        if layout.kind == .gameWithUpdate, let patch = layout.patchFolder {
            return "update folder \(fileName(patch)) beside it; its files take precedence"
        }
        if let ignored = layout.ignoredPatchFolder {
            return "update folder \(fileName(ignored)) beside it is not needed: the game folder already holds an update as new"
        }
        return nil
    }

    // MARK: - File system helpers

    private static func isFile(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return false }
        return !isDirectory.boolValue
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return false }
        return isDirectory.boolValue
    }

    /// Absolute, collapsed path with no trailing separator except the root: the platform equivalent of
    /// `Path.GetFullPath` followed by `Path.TrimEndingDirectorySeparator`. `..` never climbs above the
    /// root, and a bare drive letter stays a name of this file system.
    private static func fullPath(_ path: String) -> String? {
        guard !path.utf8.contains(0) else { return nil }
        let absolute = path.hasPrefix("/")
        var components: [String] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." {
                if let last = components.last, last != ".." {
                    components.removeLast()
                } else if !absolute {
                    components.append("..")
                }
                continue
            }
            components.append(String(part))
        }

        let joined = components.joined(separator: "/")
        if absolute { return "/" + joined }
        let root = FileManager.default.currentDirectoryPath
        return joined.isEmpty ? root : root + "/" + joined
    }

    /// The directory a path sits in, as `Path.GetDirectoryName` reports it; nil for the root or a name
    /// without a directory.
    private static func parentDirectory(of path: String) -> String? {
        let trimmed = trimTrailingSeparators(path)
        guard trimmed != "/" else { return nil }
        let parent = (trimmed as NSString).deletingLastPathComponent
        return parent.isEmpty ? nil : parent
    }

    /// The last path component, as `Path.GetFileName` reports it.
    private static func fileName(_ path: String) -> String {
        let trimmed = trimTrailingSeparators(path)
        guard trimmed != "/" else { return "" }
        return (trimmed as NSString).lastPathComponent
    }

    /// The real subdirectories of a folder, sorted; an unreadable folder holds nothing.
    private static func subdirectories(of folder: String) -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return [] }
        var result: [String] = []
        result.reserveCapacity(entries.count)
        for entry in entries {
            let full = folder.hasSuffix("/") ? folder + entry : folder + "/" + entry
            if isDirectory(full) {
                result.append(full)
            }
        }
        return result.sorted()
    }

    /// Removes trailing path separators but keeps the root.
    private static func trimTrailingSeparators(_ path: String) -> String {
        var result = path
        while result.count > 1, result.hasSuffix("/") || result.hasSuffix("\\") {
            result.removeLast()
        }
        return result
    }

    /// Removes every leading and trailing occurrence of `character` (as `string.Trim(char)` does).
    private static func trim(_ path: String, character: Character) -> String {
        var result = Substring(path)
        while result.first == character { result.removeFirst() }
        while result.last == character { result.removeLast() }
        return String(result)
    }
}

private extension UInt8 {
    var isASCIIDigit: Bool { self >= UInt8(ascii: "0") && self <= UInt8(ascii: "9") }
}
