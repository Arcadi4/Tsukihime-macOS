import Foundation
import TsukiCore
import TsukiEngine
import TsukiPlatform

/// Button prompt styles.
public enum PromptSetting: Int, Sendable, CaseIterable {
    case auto = 0
    case keyboard = 1
    case playstation = 2
    case xbox = 3

    public var title: String {
        switch self {
        case .auto: return "Auto"
        case .keyboard: return "Keyboard"
        case .playstation: return "PlayStation"
        case .xbox: return "Xbox"
        }
    }
}

/// The origin of a monitor.
public struct MonitorOrigin: Equatable, Hashable, Sendable {
    public let x: Int
    public let y: Int

    public init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }
}

/// Local app settings data stored in settings.ini.
public struct AppSettingsData: Equatable, Sendable {
    public var prompts: PromptSetting
    public var fullscreen: Bool?
    public var windowWidth: Int?
    public var windowHeight: Int?
    public var monitor: MonitorOrigin?
    public var vsync: Bool?
    public var gameLanguage: Language?

    public init(
        prompts: PromptSetting = .auto,
        fullscreen: Bool? = nil,
        windowWidth: Int? = nil,
        windowHeight: Int? = nil,
        monitor: MonitorOrigin? = nil,
        vsync: Bool? = nil,
        gameLanguage: Language? = nil
    ) {
        self.prompts = prompts
        self.fullscreen = fullscreen
        self.windowWidth = windowWidth
        self.windowHeight = windowHeight
        self.monitor = monitor
        self.vsync = vsync
        self.gameLanguage = gameLanguage
    }

    public var windowSize: (width: Int, height: Int)? {
        guard let w = windowWidth, let h = windowHeight else { return nil }
        return (w, h)
    }
}

/// Helper for reading and writing `settings.ini`.
public enum AppSettings {
    public static func load(_ path: String?) -> AppSettingsData {
        guard let path = path, FileManager.default.fileExists(atPath: path),
              let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            return AppSettingsData()
        }
        return parse(text)
    }

    public static func parse(_ text: String) -> AppSettingsData {
        var data = AppSettingsData()
        let lines = text.components(separatedBy: "\n")
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
            let parts = line.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased()
            let val = parts[1].lowercased()

            switch key {
            case "prompts":
                switch val {
                case "keyboard", "keys", "kb", "1": data.prompts = .keyboard
                case "playstation", "ps", "ps4", "ps5", "dualshock", "dualsense", "2": data.prompts = .playstation
                case "xbox", "xinput", "pad", "gamepad", "controller", "3": data.prompts = .xbox
                default: data.prompts = .auto
                }
            case "fullscreen":
                data.fullscreen = (val == "on" || val == "true" || val == "yes" || val == "1")
            case "vsync":
                data.vsync = (val == "on" || val == "true" || val == "yes" || val == "1")
            case "window":
                let normalized = val.replacingOccurrences(of: "×", with: "x").replacingOccurrences(of: "X", with: "x")
                let dims = normalized.split(separator: "x").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                if dims.count == 2 && dims[0] >= 640 && dims[1] >= 360 {
                    data.windowWidth = dims[0]
                    data.windowHeight = dims[1]
                }
            case "monitor":
                let coords = val.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                if coords.count == 2 {
                    data.monitor = MonitorOrigin(coords[0], coords[1])
                }
            case "language":
                switch val {
                case "ja", "jp", "japanese", "0": data.gameLanguage = .ja
                case "en", "english", "1": data.gameLanguage = .en
                case "zc", "zh-cn", "zh-hans", "2": data.gameLanguage = .zc
                case "zt", "zh-tw", "zh-hant", "3": data.gameLanguage = .zt
                default: break
                }
            default:
                break
            }
        }
        return data
    }

    public static func format(_ data: AppSettingsData) -> String {
        var lines: [String] = [
            "# Tsuki launcher settings",
            "# prompts: auto, keyboard, playstation, xbox"
        ]
        switch data.prompts {
        case .keyboard: lines.append("prompts=keyboard")
        case .playstation: lines.append("prompts=playstation")
        case .xbox: lines.append("prompts=xbox")
        case .auto: lines.append("prompts=auto")
        }

        if let fullscreen = data.fullscreen {
            lines.append("fullscreen=\(fullscreen ? "on" : "off")")
        }
        if let w = data.windowWidth, let h = data.windowHeight {
            lines.append("window=\(w)x\(h)")
        }
        if let monitor = data.monitor {
            lines.append("monitor=\(monitor.x),\(monitor.y)")
        }
        if let vsync = data.vsync {
            lines.append("vsync=\(vsync ? "on" : "off")")
        }
        if let lang = data.gameLanguage {
            lines.append("language=\(lang.code)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func save(_ path: String?, _ data: AppSettingsData) -> Bool {
        guard let path = path else { return false }
        do {
            let dir = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try format(data).write(toFile: path, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    public static func update(_ path: String?, _ change: (AppSettingsData) -> AppSettingsData) -> Bool {
        guard let path = path else { return false }
        return save(path, change(load(path)))
    }
}

/// A window size preset the Display page offers.
public struct WindowSizeChoice: Sendable, Equatable, Hashable, Identifiable {
    public var id: String { label }
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var label: String {
        "\(width) × \(height)"
    }

    public static func `for`(workArea: (width: Int, height: Int)) -> [WindowSizeChoice] {
        WindowFit.presetsFor(workWidth: workArea.width, workHeight: workArea.height).map {
            WindowSizeChoice(width: $0.width, height: $0.height)
        }
    }

    public static var all: [WindowSizeChoice] {
        WindowFit.presets.map { WindowSizeChoice(width: $0.width, height: $0.height) }
    }
}

/// The values the settings pages show.
public struct LauncherProfile: Sendable, Equatable {
    public let settings: AppSettingsData
    public let saves: SaveSummary

    public init(settings: AppSettingsData, saves: SaveSummary) {
        self.settings = settings
        self.saves = saves
    }

    public var language: Language {
        if let l = settings.gameLanguage { return l }
        if let idx = saves.configLanguage, let lang = Language(rawValue: UInt8(idx)), Language.selectable.contains(lang) {
            return lang
        }
        return .en
    }

    public var fullscreen: Bool {
        settings.fullscreen ?? (saves.windowMode == 1)
    }

    public var vsync: Bool {
        settings.vsync ?? true
    }

    public var windowSize: (width: Int, height: Int) {
        settings.windowSize ?? (WindowFit.defaultWidth, WindowFit.defaultHeight)
    }

    public func effectiveWindowSize(_ workArea: (width: Int, height: Int)?) -> (width: Int, height: Int) {
        let (w, h) = windowSize
        guard let area = workArea else { return (w, h) }
        return WindowFit.clamp(width: w, height: h, workWidth: area.width, workHeight: area.height)
    }

    public static func read(_ paths: LauncherPaths) -> LauncherProfile {
        let settings = AppSettings.load(paths.settingsFile)
        var saves = SaveTools.summarize(paths.saveFile)
        saves.writeError = SaveTools.probeWritable(paths.dataDirectory)
        return LauncherProfile(settings: settings, saves: saves)
    }

    public static func languageName(_ language: Language) -> (native: String, english: String) {
        switch language {
        case .ja: return ("日本語", "Japanese")
        case .zc: return ("简体中文", "Simplified Chinese")
        case .zt: return ("繁體中文", "Traditional Chinese")
        default: return ("English", "English")
        }
    }

    public func statusLine(monitorSize: (width: Int, height: Int)? = nil, workArea: (width: Int, height: Int)? = nil) -> String {
        let (w, h) = effectiveWindowSize(workArea)
        let sizeText: String
        if fullscreen {
            if let m = monitorSize {
                sizeText = "\(m.width) × \(m.height)  ·  Fullscreen"
            } else {
                sizeText = "Fullscreen"
            }
        } else {
            sizeText = "\(w) × \(h)  ·  Windowed"
        }

        let promptsText: String
        switch settings.prompts {
        case .keyboard: promptsText = "Keyboard prompts"
        case .playstation: promptsText = "PlayStation prompts"
        case .xbox: promptsText = "Xbox prompts"
        case .auto: promptsText = "Auto prompts"
        }

        return "\(sizeText)  ·  \(LauncherProfile.languageName(language).native)  ·  \(promptsText)"
    }
}
