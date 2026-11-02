import Foundation
import AppKit
import SwiftUI
import TsukiCore
import TsukiEngine
import TsukiData
import TsukiPlatform

/// A question the confirm modal asks.
public struct ConfirmRequest: Identifiable {
    public var id: String { title }
    public let title: String
    public let body: String
    public let confirmLabel: String
    public let action: @MainActor () -> Void

    public init(title: String, body: String, confirmLabel: String, action: @escaping @MainActor () -> Void) {
        self.title = title
        self.body = body
        self.confirmLabel = confirmLabel
        self.action = action
    }
}

/// The launcher's view model.
@MainActor
public final class LauncherModel: ObservableObject {
    public static let languageOrder: [Language] = [.ja, .en, .zc, .zt]

    public let paths: LauncherPaths
    public let launcherDirectory: String

    @Published public var page: LauncherPage = .play
    @Published public var folder: GameFolderInfo = GameFolderCheck.notSet
    @Published public var folderText: String = ""
    @Published public var folderMessage: String = ""
    @Published public var readyRows: [ReadyRow] = []
    @Published public var canPlay: Bool = false
    @Published public var heroArt: NSImage?
    @Published public var heroLogo: NSImage?

    @Published public var appExe: String?
    @Published public var missingFfmpeg: [String] = []
    @Published public var graphics: [String] = []
    @Published public var controllers: [String] = []
    @Published public var monitors: [MonitorEntry] = []
    @Published public var selectedMonitor: MonitorEntry?

    @Published public var profile: LauncherProfile
    @Published public var languageIndex: Int = 0
    @Published public var fullscreen: Bool = false
    @Published public var vsync: Bool = true
    @Published public var promptsIndex: Int = 0
    @Published public var selectedWindowSize: WindowSizeChoice?

    @Published public var backups: [BackupInfo] = []
    @Published public var shadImage: String?

    @Published public var toast: String = ""
    @Published public var toastVisible: Bool = false
    @Published public var confirm: ConfirmRequest?
    @Published public var confirmVisible: Bool = false
    @Published public var gameRunning: Bool = false

    private var runningProcess: Process?

    public init(paths: LauncherPaths = .forUser(), launcherDirectory: String? = nil, gameFolder: String? = nil) {
        self.paths = paths
        let dir = launcherDirectory ?? Bundle.main.bundleURL.deletingLastPathComponent().path
        self.launcherDirectory = dir

        let prof = LauncherProfile.read(paths)
        self.profile = prof

        self.fullscreen = prof.fullscreen
        self.vsync = prof.vsync
        self.promptsIndex = prof.settings.prompts.rawValue
        self.languageIndex = LauncherModel.languageOrder.firstIndex(of: prof.language) ?? 0

        if let gameFolder = gameFolder {
            self.folderText = gameFolder
        } else if let remembered = paths.readGameDirectory() {
            self.folderText = remembered
        }

        refresh()
    }

    // -- Computed Properties ------------------------------------------------------------------------------------------

    public var readySummary: String {
        let count = readyRows.filter { $0.state == .warning }.count
        if count == 0 { return "All set" }
        if count == 1 { return "1 thing needs attention" }
        return "\(count) things need attention"
    }

    public var readyAllGood: Bool {
        readyRows.allSatisfy { $0.state == .ok }
    }

    public var statusText: String {
        if !folder.isReady {
            return folder.summary
        }
        if folder.isVerifiedBuild {
            return "Ready: this is the game the port was made for"
        }
        return "Ready, but not the verified build: \(folder.buildText)"
    }

    public var buildDetail: String {
        guard let name = folder.buildName else { return "unknown" }
        var result = name
        if let patch = folder.patchFolder {
            let filename = (patch as NSString).lastPathComponent
            result += "; update folder \(filename) beside the game, its files take precedence"
        }
        if let ignored = folder.ignoredPatchFolder {
            let filename = (ignored as NSString).lastPathComponent
            result += "; the update folder \(filename) beside the game is not needed"
        }
        if let note = folder.tablesNote {
            result += "; \(note)"
        }
        return result
    }

    public var languagesDetail: String {
        guard folder.state == .ready else { return "unknown" }
        return folder.languageList.map { LauncherProfile.languageName($0).native }.joined(separator: ", ")
    }

    public var titleText: String {
        guard let id = folder.titleId else { return "unknown" }
        let ver = folder.appVersion ?? "?"
        let sfoNote = (folder.isReady && folder.sfoVersion != nil && folder.sfoVersion != folder.appVersion)
            ? " (param.sfo says \(folder.sfoVersion!))" : ""
        return "\(id)  ·  version \(ver)\(sfoNote)"
    }

    public var checksText: String {
        folder.checksTotal == 0 ? "not run" : "\(folder.checksPassed) of \(folder.checksTotal) passed"
    }

    public var contentsText: String {
        folder.checksTotal == 0 ? "unknown" : "\(folder.archives) archives and data files, \(folder.movies) movies"
    }

    public var controllersText: String {
        controllers.isEmpty ? "No controller detected" : controllers.map { "• \($0)" }.joined(separator: "\n")
    }

    public var gameChip: String {
        switch folder.state {
        case .notSet, .missing:
            return "CUSA47999  ·  game folder not set"
        case .notTheGame, .pkgFile, .updateOnly, .several:
            return "CUSA47999  ·  not the game folder"
        case .ready where !folder.isVerifiedBuild:
            return "\(folder.titleId ?? "CUSA47999")  ·  version \(folder.appVersion ?? "unknown")  ·  not verified"
        default:
            return "\(folder.titleId ?? "CUSA47999")  ·  version \(folder.appVersion ?? "unknown")"
        }
    }

    public var launcherVersion: String {
        "Launcher 1.0.0"
    }

    public var folderSize: String {
        folder.totalBytes > 0 ? GameFolderCheck.formatSize(folder.totalBytes) : "unknown"
    }

    public var graphicsName: String {
        graphics.isEmpty ? "Apple Silicon / Metal" : graphics.joined(separator: ", ")
    }

    public var windowSizes: [WindowSizeChoice] {
        if let m = selectedMonitor {
            return WindowSizeChoice.for(workArea: m.workArea)
        }
        return WindowSizeChoice.all
    }

    public var windowSizeNote: String {
        let m = selectedMonitor
        let (w, h) = profile.effectiveWindowSize(m?.workArea)
        let (rw, rh) = profile.windowSize
        let clamp = (w, h) != (rw, rh) ? " (settings.ini asks for \(rw) × \(rh), which does not fit)" : ""
        let displayStr = m.map { " on Display \($0.index)" } ?? ""
        return "The game opens as a \(w) × \(h) window\(displayStr)\(clamp). It fits inside the screen's work area."
    }

    public var statusLine: String {
        profile.statusLine(
            monitorSize: selectedMonitor.map { ($0.width, $0.height) },
            workArea: selectedMonitor?.workArea
        )
    }

    public var saves: SaveSummary {
        profile.saves
    }

    public var saveText: String {
        var str = profile.saves.describe()
        if let writeTime = profile.saves.lastWrite {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            str += "  ·  last changed \(formatter.string(from: writeTime))"
        }
        return str
    }

    public var dataDirectory: String {
        paths.dataDirectory
    }

    public var noBackups: Bool {
        backups.isEmpty
    }

    public var hasShadImage: Bool {
        shadImage != nil
    }

    public var playLabel: String {
        gameRunning ? "RUNNING" : "PLAY"
    }

    public var keys: [KeyRow] { KeyTable.rows }
    public var essentialKeys: [KeyRow] { KeyTable.essentials }

    // -- Actions ------------------------------------------------------------------------------------------------------

    public func refresh() {
        let currentFolder = paths.readGameDirectory() ?? folderText
        if !currentFolder.isEmpty {
            folder = GameFolderCheck.inspect(currentFolder)
            if folder.isReady, let path = folder.path {
                let hero = LauncherArt.loadHero(gameFolder: path)
                self.heroArt = hero.background
                self.heroLogo = hero.logo
            }
        } else {
            folder = GameFolderCheck.notSet
            heroArt = nil
            heroLogo = nil
        }

        appExe = GameLauncher.findApp(launcherDirectory)
        missingFfmpeg = appExe.map { GameLauncher.missingFfmpeg(($0 as NSString).deletingLastPathComponent) } ?? []
        graphics = SystemInfo.videoAdapters()
        controllers = Controllers.connected()
        monitors = SystemInfo.monitors()
        selectedMonitor = monitors.first(where: \.primary) ?? monitors.first

        profile = LauncherProfile.read(paths)
        fullscreen = profile.fullscreen
        vsync = profile.vsync
        promptsIndex = profile.settings.prompts.rawValue
        languageIndex = LauncherModel.languageOrder.firstIndex(of: profile.language) ?? 0

        let (curW, curH) = profile.windowSize
        selectedWindowSize = windowSizes.first(where: { $0.width == curW && $0.height == curH })

        readyRows = ReadyCheck.build(
            folder: folder,
            appExe: appExe,
            missingFfmpeg: missingFfmpeg,
            graphics: graphics,
            saves: profile.saves
        )
        canPlay = ReadyCheck.canPlay(folder: folder, appExe: appExe, missingFfmpeg: missingFfmpeg)
        gameRunning = GameLauncher.isGameRunning()

        backups = SaveTools.list(paths)
        shadImage = SaveTools.findShadPs4Image()
    }

    public func setLanguage(_ index: Int) {
        guard index >= 0 && index < LauncherModel.languageOrder.count else { return }
        languageIndex = index
        let lang = LauncherModel.languageOrder[index]
        updateSettings { s in
            var copy = s
            copy.gameLanguage = lang
            return copy
        }
    }

    public func setFullscreen(_ val: Bool) {
        fullscreen = val
        updateSettings { s in
            var copy = s
            copy.fullscreen = val
            return copy
        }
    }

    public func setVsync(_ val: Bool) {
        vsync = val
        updateSettings { s in
            var copy = s
            copy.vsync = val
            return copy
        }
    }

    public func setPrompts(_ index: Int) {
        guard let p = PromptSetting(rawValue: index) else { return }
        promptsIndex = index
        updateSettings { s in
            var copy = s
            copy.prompts = p
            return copy
        }
    }

    public func setWindowSize(_ choice: WindowSizeChoice) {
        selectedWindowSize = choice
        updateSettings { s in
            var copy = s
            copy.windowWidth = choice.width
            copy.windowHeight = choice.height
            return copy
        }
    }

    public func setMonitor(_ m: MonitorEntry) {
        selectedMonitor = m
        updateSettings { s in
            var copy = s
            copy.monitor = MonitorOrigin(m.x, m.y)
            return copy
        }
    }

    private func updateSettings(_ change: (AppSettingsData) -> AppSettingsData) {
        _ = AppSettings.update(paths.settingsFile, change)
        profile = LauncherProfile.read(paths)
    }

    public func applyFolderText() {
        let trimmed = folderText.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        guard !trimmed.isEmpty else {
            folderMessage = "Please select or type a folder."
            return
        }

        let resolved = GameFolderCheck.resolve(trimmed)
        let check = GameFolderCheck.inspect(resolved)
        folder = check
        folderText = resolved

        if check.isReady {
            _ = paths.writeGameDirectory(resolved)
            folderMessage = "Game folder verified and remembered."
            showToast("Game folder saved.")
            refresh()
        } else {
            folderMessage = check.summary
        }
    }

    public func browseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Game Folder"

        if panel.runModal() == .OK, let url = panel.url {
            folderText = url.path
            applyFolderText()
        }
    }

    public func openGameFolder() {
        if let path = folder.path {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
        }
    }

    public func openLog() {
        if let log = paths.logToShow() {
            NSWorkspace.shared.open(URL(fileURLWithPath: log))
        } else {
            showToast("No log file found yet.")
        }
    }

    public func openGuide() {
        if let guide = GameLauncher.findSetupGuide(launcherDirectory) {
            NSWorkspace.shared.open(URL(fileURLWithPath: guide))
        } else {
            showToast("Setup guide file not found.")
        }
    }

    public func openSavesFolder() {
        try? FileManager.default.createDirectory(atPath: paths.dataDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: paths.dataDirectory)
    }

    public func openBackupsFolder() {
        try? FileManager.default.createDirectory(atPath: paths.backupsDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: paths.backupsDirectory)
    }

    public func backupNow() {
        if let b = SaveTools.backup(paths) {
            backups = SaveTools.list(paths)
            showToast("Backup created: \(b.name)")
        } else {
            showToast("No save files found to back up.")
        }
    }

    public func askRestore(_ backup: BackupInfo) {
        askConfirm(
            title: "Restore Backup",
            body: "Restore backup '\(backup.name)'? Your current save.dat will be backed up before being replaced.",
            confirmLabel: "Restore"
        ) { [weak self] in
            guard let self = self else { return }
            do {
                _ = try SaveTools.restore(self.paths, backup: backup)
                self.refresh()
                self.showToast("Backup restored.")
            } catch {
                self.showToast("Restore failed: \(error.localizedDescription)")
            }
        }
    }

    public func importPs4File(url: URL) {
        askConfirm(
            title: "Import PS4 Save",
            body: "Import save data from '\(url.lastPathComponent)'? Your current save will be backed up first.",
            confirmLabel: "Import"
        ) { [weak self] in
            guard let self = self else { return }
            do {
                let (_, count) = try SaveTools.importPs4(paths: self.paths, imagePath: url.path)
                self.refresh()
                self.showToast("Imported \(count) slots from PS4 image.")
            } catch {
                self.showToast("Import failed: \(error.localizedDescription)")
            }
        }
    }

    public func importFoundShadImage() {
        guard let shad = shadImage else { return }
        importPs4File(url: URL(fileURLWithPath: shad))
    }

    public func play() {
        guard canPlay, let appExe = appExe, let folderPath = folder.path else {
            showToast("Cannot launch: game folder or executable not ready.")
            return
        }

        let plan = GameLauncher.plan(appExe: appExe, gameFolder: folderPath, paths: paths, fullscreen: fullscreen)
        do {
            let proc = try GameLauncher.start(plan: plan, paths: paths)
            self.runningProcess = proc
            self.gameRunning = true
            showToast("Tsukihime launched.")

            Task.detached {
                proc.waitUntilExit()
                await MainActor.run { [weak self] in
                    self?.gameRunning = false
                    self?.refresh()
                }
            }
        } catch {
            showToast("Failed to launch: \(error.localizedDescription)")
        }
    }

    public func askConfirm(title: String, body: String, confirmLabel: String, action: @escaping @MainActor () -> Void) {
        confirm = ConfirmRequest(title: title, body: body, confirmLabel: confirmLabel, action: action)
        confirmVisible = true
    }

    public func answerConfirm(_ yes: Bool) {
        if yes {
            confirm?.action()
        }
        confirm = nil
        confirmVisible = false
    }

    public func showToast(_ message: String) {
        toast = message
        toastVisible = true
        Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if self.toast == message {
                self.toastVisible = false
            }
        }
    }
}
