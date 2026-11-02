import Foundation
import TsukiCore
import TsukiEngine
import TsukiPlatform

/// What the game does with `settings.ini` when it starts.
public final class StartupSettings {
    public static let windowModeOffset = AppSettings.windowModeOffset

    public let path: String?
    public let data: AppSettingsData

    private init(path: String?, data: AppSettingsData) {
        self.path = path
        self.data = data
    }

    public static func dataDirectory(_ args: AppArgs) -> String {
        if let dir = args.saveDir {
            return dir
        }
        let profile = ProfileDirectory.forUser()
        try? FileManager.default.createDirectory(atPath: profile, withIntermediateDirectories: true)
        return profile
    }

    public static func load(_ args: AppArgs) -> StartupSettings {
        let path = args.noSave ? nil : (dataDirectory(args) as NSString).appendingPathComponent(AppSettings.fileName)
        return StartupSettings(path: path, data: AppSettings.load(path))
    }

    public static func from(_ data: AppSettingsData) -> StartupSettings {
        StartupSettings(path: nil, data: data)
    }

    public var requestedWindowSize: (width: Int, height: Int) {
        data.windowSize ?? (WindowFit.defaultWidth, WindowFit.defaultHeight)
    }

    public func windowOptions(title: String = "Tsukihime") -> WindowOptions {
        let (w, h) = requestedWindowSize
        return WindowOptions(
            title: title,
            width: w,
            height: h,
            hidden: true,
            resizable: true,
            swapInterval: data.vsync == false ? 0 : 1
        )
    }

    @discardableResult
    public func placeWindow(_ window: GameWindow) -> Placement {
        WindowPlacement.place(
            window: window,
            monitorX: data.monitor?.x,
            monitorY: data.monitor?.y,
            width: data.windowWidth,
            height: data.windowHeight
        )
    }

    @discardableResult
    public func applyToConfig(_ config: ConfigBlock, languageGivenOnCommandLine: Bool, windowMode: Bool? = nil) -> Bool {
        var language = false
        if let lang = data.gameLanguage, lang != .ko, !languageGivenOnCommandLine {
            config.language = Int16(lang.rawValue)
            language = true
        }

        var windowChanged = false
        if let mode = windowMode {
            let wanted: UInt8 = mode ? 1 : 0
            windowChanged = (config.readU8(Self.windowModeOffset) != wanted)
            config.writeU8(Self.windowModeOffset, wanted)
        }

        let consumed = language || windowMode != nil
        if consumed, let path = path, language || data.fullscreen != nil {
            _ = AppSettings.update(path) { saved in
                var s = saved
                if language { s.gameLanguage = nil }
                if windowMode != nil { s.fullscreen = nil }
                return s
            }
        }

        return language || windowChanged
    }
}
