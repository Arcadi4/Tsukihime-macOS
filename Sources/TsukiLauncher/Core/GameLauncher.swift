import Foundation
import AppKit
import TsukiCore
import TsukiData

/// How to start the game once.
public struct LaunchPlan: Sendable, Equatable {
    public let exePath: String
    public let workingDirectory: String
    public let arguments: [String]

    public init(exePath: String, workingDirectory: String, arguments: [String]) {
        self.exePath = exePath
        self.workingDirectory = workingDirectory
        self.arguments = arguments
    }
}

/// Finds and starts Tsukihime.
public enum GameLauncher {
    /// The executable name of the game program on macOS.
    public static let appFileName = "Tsukihime"

    /// The executable name of the launcher on macOS.
    public static let launcherFileName = "TsukihimeLauncher"

    /// Required FFmpeg dynamic libraries on macOS.
    public static let ffmpegDylibs: [String] = [
        "libavutil.61.dylib",
        "libswresample.7.dylib",
        "libavcodec.63.dylib",
        "libavformat.63.dylib"
    ]

    public static let setupGuideFileName = "SETUP_GUIDE.txt"

    /// True while a Tsukihime process runs on this machine.
    public static func isGameRunning() -> Bool {
        let apps = NSWorkspace.shared.runningApplications
        for app in apps {
            if app.localizedName == appFileName || app.executableURL?.lastPathComponent == appFileName {
                return true
            }
        }
        return false
    }

    /// Looks for the game program.
    public static func findApp(_ launcherDirectory: String) -> String? {
        let manager = FileManager.default
        let own = (launcherDirectory as NSString).appendingPathComponent(appFileName)
        if manager.fileExists(atPath: own) {
            return own
        }

        // Check sibling directories and standard build locations
        let candidates = [
            (launcherDirectory as NSString).deletingLastPathComponent + "/\(appFileName)",
            (launcherDirectory as NSString).deletingLastPathComponent + "/Tsukihime/\(appFileName)",
            (launcherDirectory as NSString).appendingPathComponent("../Tsukihime"),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(appFileName).path,
            "./.build/debug/\(appFileName)",
            "./.build/release/\(appFileName)"
        ]

        for cand in candidates {
            let standard = (cand as NSString).standardizingPath
            if manager.fileExists(atPath: standard) {
                return standard
            }
        }
        return nil
    }

    /// Looks for the setup guide.
    public static func findSetupGuide(_ launcherDirectory: String) -> String? {
        let manager = FileManager.default
        let candidates = [
            (launcherDirectory as NSString).appendingPathComponent(setupGuideFileName),
            (launcherDirectory as NSString).appendingPathComponent("docs/SETUP_GUIDE.md"),
            (launcherDirectory as NSString).appendingPathComponent("../docs/SETUP_GUIDE.md"),
            "./docs/SETUP_GUIDE.md"
        ]
        for cand in candidates {
            let standard = (cand as NSString).standardizingPath
            if manager.fileExists(atPath: standard) {
                return standard
            }
        }
        return nil
    }

    /// The missing FFmpeg libraries next to the game program.
    public static func missingFfmpeg(_ appDirectory: String) -> [String] {
        let manager = FileManager.default
        var missing: [String] = []

        for dylib in ffmpegDylibs {
            let localPath = (appDirectory as NSString).appendingPathComponent(dylib)
            let frameworkPath = (appDirectory as NSString).appendingPathComponent("../Frameworks/\(dylib)")
            if !manager.fileExists(atPath: localPath) && !manager.fileExists(atPath: frameworkPath) {
                // If it can be loaded globally (e.g. Homebrew /usr/local or /opt/homebrew), it's not missing
                let handle = dlopen(dylib, RTLD_LAZY | RTLD_NOLOAD) ?? dlopen(dylib, RTLD_LAZY)
                if let h = handle {
                    dlclose(h)
                } else {
                    missing.append(dylib)
                }
            }
        }
        return missing
    }

    /// Looks for the launcher program.
    public static func findLauncher(_ launcherDirectory: String) -> String? {
        let own = (launcherDirectory as NSString).appendingPathComponent(launcherFileName)
        return FileManager.default.fileExists(atPath: own) ? own : nil
    }

    /// Builds the launch plan.
    public static func plan(
        appExe: String,
        gameFolder: String,
        paths: LauncherPaths,
        fullscreen: Bool,
        extra: [String]? = nil
    ) -> LaunchPlan {
        var args = [
            "--game", gameFolder,
            "--log", paths.lastRunLog,
            fullscreen ? "--fullscreen" : "--windowed"
        ]

        if !paths.isUserProfile {
            args.append("--save-dir")
            args.append(paths.dataDirectory)
        }

        if let extra = extra {
            args.append(contentsOf: extra)
        }

        let workDir = (appExe as NSString).deletingLastPathComponent
        return LaunchPlan(exePath: appExe, workingDirectory: workDir, arguments: args)
    }

    /// Starts the game process.
    @discardableResult
    public static func start(plan: LaunchPlan, paths: LauncherPaths) throws -> Process {
        try FileManager.default.createDirectory(atPath: paths.dataDirectory, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: plan.exePath)
        process.currentDirectoryURL = URL(fileURLWithPath: plan.workingDirectory)
        process.arguments = plan.arguments

        try process.run()
        return process
    }
}
