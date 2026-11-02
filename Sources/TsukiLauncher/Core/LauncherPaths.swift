import Foundation

/// Where the launcher and the game keep their files.
/// Everything is under ~/.config/Tsuki (or ~/Library/Application Support/Tsuki).
public final class LauncherPaths: Sendable {
    /// The folder for user profile data.
    public let dataDirectory: String

    public init(dataDirectory: String) {
        self.dataDirectory = dataDirectory
    }

    /// The paths of the current macOS user.
    public static func forUser() -> LauncherPaths {
        let home = NSHomeDirectory()
        let configDir = (home as NSString).appendingPathComponent(".config")
        let appSupport = (home as NSString).appendingPathComponent("Library/Application Support")

        let configTsuki = (configDir as NSString).appendingPathComponent("Tsuki")
        let appSupportTsuki = (appSupport as NSString).appendingPathComponent("Tsuki")

        let chosen: String
        if FileManager.default.fileExists(atPath: appSupportTsuki) && !FileManager.default.fileExists(atPath: configTsuki) {
            chosen = appSupportTsuki
        } else {
            chosen = configTsuki
        }
        return LauncherPaths(dataDirectory: chosen)
    }

    /// True when this is the profile of the current user, the one the game uses without `--save-dir`.
    public var isUserProfile: Bool {
        let userDir = LauncherPaths.forUser().dataDirectory
        let standardA = (dataDirectory as NSString).standardizingPath
        let standardB = (userDir as NSString).standardizingPath
        return standardA.caseInsensitiveCompare(standardB) == .orderedSame
    }

    /// The save file (140 slots, system data, config).
    public var saveFile: String {
        (dataDirectory as NSString).appendingPathComponent("save.dat")
    }

    /// The settings file.
    public var settingsFile: String {
        (dataDirectory as NSString).appendingPathComponent("settings.ini")
    }

    /// The game folder the game remembers (`--game` or this file).
    public var gameDirFile: String {
        (dataDirectory as NSString).appendingPathComponent("game_dir.txt")
    }

    /// The save backups, one folder per backup.
    public var backupsDirectory: String {
        (dataDirectory as NSString).appendingPathComponent("backups")
    }

    /// The log of the last run.
    public var lastRunLog: String {
        (dataDirectory as NSString).appendingPathComponent("last_run.log")
    }

    /// The crash log the game appends to.
    public var crashLog: String {
        (dataDirectory as NSString).appendingPathComponent("crash.log")
    }

    /// The log to show: the last run's, else the crash log, else nil.
    public func logToShow() -> String? {
        let manager = FileManager.default
        if manager.fileExists(atPath: lastRunLog) {
            return lastRunLog
        }
        if manager.fileExists(atPath: crashLog) {
            return crashLog
        }
        return nil
    }

    /// Reads the remembered game folder; nil when there is none.
    public func readGameDirectory() -> String? {
        guard FileManager.default.fileExists(atPath: gameDirFile) else {
            return nil
        }
        do {
            let text = try String(contentsOfFile: gameDirFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }

    /// Remembers the game folder for the game and the launcher.
    public func writeGameDirectory(_ folder: String) -> Bool {
        do {
            try FileManager.default.createDirectory(atPath: dataDirectory, withIntermediateDirectories: true)
            try folder.write(toFile: gameDirFile, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
}
