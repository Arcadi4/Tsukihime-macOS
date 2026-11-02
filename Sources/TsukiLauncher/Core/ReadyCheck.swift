import Foundation
import TsukiData

/// The pages of the launcher, in sidebar order.
public enum LauncherPage: Int, CaseIterable, Sendable, Identifiable {
    /// Hero, ready check, quick settings.
    case play = 0
    /// The game folder.
    case gameFiles = 1
    /// Fullscreen, monitor, window size, vsync.
    case display = 2
    /// Game language and sound.
    case language = 3
    /// Button prompts, keys, controllers.
    case controls = 4
    /// Backups, restore, import.
    case saves = 5
    /// What this is, keys, licences.
    case help = 6

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .play: return "Play"
        case .gameFiles: return "Game files"
        case .display: return "Display"
        case .language: return "Language & sound"
        case .controls: return "Controls"
        case .saves: return "Saves"
        case .help: return "Help & about"
        }
    }

    public var systemImage: String {
        switch self {
        case .play: return "play.circle.fill"
        case .gameFiles: return "folder.fill"
        case .display: return "display"
        case .language: return "character.bubble.fill"
        case .controls: return "gamecontroller.fill"
        case .saves: return "externaldrive.fill"
        case .help: return "questionmark.circle.fill"
        }
    }
}

/// Whether a ready-check row is fine.
public enum CheckState: Sendable, Equatable {
    /// Fine (a check mark).
    case ok
    /// Needs attention (an exclamation mark and a fix link).
    case warning
}

/// One row of the ready check.
public struct ReadyRow: Sendable, Equatable, Identifiable {
    public var id: String { title }
    public let title: String
    public let detail: String
    public let state: CheckState
    public let fix: LauncherPage?

    public init(title: String, detail: String, state: CheckState, fix: LauncherPage? = nil) {
        self.title = title
        self.detail = detail
        self.state = state
        self.fix = fix
    }

    public var hasFix: Bool { fix != nil }
}

/// Builds the ready-check rows from what was found.
public enum ReadyCheck {
    public static func build(
        folder: GameFolderInfo,
        appExe: String?,
        missingFfmpeg: [String],
        graphics: [String],
        saves: SaveSummary
    ) -> [ReadyRow] {
        var rows: [ReadyRow] = []

        let version = folder.appVersion.map { "version \($0)" } ?? "version unknown"
        let update = folder.patchFolder.map { ", update folder \((($0 as NSString).lastPathComponent)) beside it" } ?? ""

        switch folder.state {
        case .notSet:
            rows.append(ReadyRow(title: "Game folder", detail: "Not chosen yet. Point the launcher at your CUSA47999 folder.", state: .warning, fix: .gameFiles))
        case .missing:
            rows.append(ReadyRow(title: "Game folder", detail: "The remembered folder is gone.", state: .warning, fix: .gameFiles))
        case .notTheGame:
            rows.append(ReadyRow(title: "Game folder", detail: "eboot.bin is not in this folder.", state: .warning, fix: .gameFiles))
        case .pkgFile:
            rows.append(ReadyRow(title: "Game folder", detail: "A .pkg file was chosen: extract it first, then choose the extracted CUSA47999 folder.", state: .warning, fix: .gameFiles))
        case .updateOnly:
            rows.append(ReadyRow(title: "Game folder", detail: "Only the update folder was found; the base game must be beside it.", state: .warning, fix: .gameFiles))
        case .several:
            rows.append(ReadyRow(title: "Game folder", detail: "Several game folders are inside the chosen one; choose one of them.", state: .warning, fix: .gameFiles))
        case .ready where folder.isVerifiedBuild || folder.build == .verified:
            rows.append(ReadyRow(title: "Game folder", detail: "\(folder.titleId ?? "Game") found, \(version)\(update): \(folder.buildText)", state: .ok))
        case .ready:
            rows.append(ReadyRow(title: "Game folder", detail: "\(folder.titleId ?? "Game") found, \(version)\(update): \(folder.buildText)", state: .warning, fix: .gameFiles))
        default:
            rows.append(ReadyRow(title: "Game folder", detail: "\(folder.titleId ?? "Game") found, \(version)\(update)", state: .ok))
        }

        switch folder.state {
        case .ready:
            let note = folder.tablesNote.map { "; \($0)" } ?? ""
            let verifiedText = folder.isVerifiedBuild ? "verified" : "checked"
            rows.append(ReadyRow(title: "Game files", detail: "\(folder.archives) archives and \(folder.movies) movies \(verifiedText)\(note)", state: .ok))
        case .incomplete:
            rows.append(ReadyRow(title: "Game files", detail: folder.summary, state: .warning, fix: .gameFiles))
        default:
            rows.append(ReadyRow(title: "Game files", detail: "Waiting for the game folder", state: .warning, fix: .gameFiles))
        }

        if appExe == nil {
            rows.append(ReadyRow(title: "Game program", detail: "\(GameLauncher.appFileName) is not found", state: .warning, fix: .help))
        } else if !missingFfmpeg.isEmpty {
            let more = missingFfmpeg.count > 1 ? " (and \(missingFfmpeg.count - 1) more)" : ""
            rows.append(ReadyRow(title: "Game program", detail: "\(missingFfmpeg[0]) is missing\(more)", state: .warning, fix: .help))
        } else {
            rows.append(ReadyRow(title: "Game program", detail: "\(GameLauncher.appFileName) and FFmpeg libraries ready", state: .ok))
        }

        let gpu = graphics.isEmpty ? "Metal graphics is checked when the game starts" : "\(graphics[0]); Metal graphics ready"
        rows.append(ReadyRow(title: "Graphics", detail: gpu, state: .ok))

        if saves.writeError != nil || saves.error != nil {
            rows.append(ReadyRow(title: "Saves", detail: saves.describe(), state: .warning, fix: .saves))
        } else {
            let detail = saves.exists ? saves.describe() + " in profile folder" : saves.describe()
            rows.append(ReadyRow(title: "Saves", detail: detail, state: .ok))
        }

        return rows
    }

    public static func canPlay(folder: GameFolderInfo, appExe: String?, missingFfmpeg: [String]) -> Bool {
        folder.isReady && appExe != nil && missingFfmpeg.isEmpty
    }
}
