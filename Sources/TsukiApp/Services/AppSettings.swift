import Foundation
import TsukiCore
import TsukiEngine
import TsukiUi

/// The left / top corner of a display in virtual-desktop pixels.
public struct MonitorOrigin: Equatable, Hashable, Sendable, CustomStringConvertible {
    public let x: Int
    public let y: Int

    public init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }

    public var description: String { "\(x),\(y)" }
}

/// The values of `settings.ini`. A nil value is a key that is not in the file: the game keeps what it did before.
public struct AppSettingsData: Equatable, Sendable {
    public static let defaultTextWebSocketPort = 6677
    public static let minWindowWidth = 640
    public static let minWindowHeight = 360
    public static let maxWindowSide = 16384

    public var prompts: PromptSetting
    public var fullscreen: Bool?
    public var windowWidth: Int?
    public var windowHeight: Int?
    public var monitor: MonitorOrigin?
    public var vsync: Bool?
    public var gameLanguage: Language?
    public var muteInBackground: Bool?
    public var copyText: Bool?
    public var textHooker: Bool?
    public var textWebSocket: Bool?
    public var textWebSocketPort: Int?
    public var screenshotNotice: Bool?
    public var textWebSocketOrigin: String?

    public init(
        prompts: PromptSetting = .auto,
        fullscreen: Bool? = nil,
        windowWidth: Int? = nil,
        windowHeight: Int? = nil,
        monitor: MonitorOrigin? = nil,
        vsync: Bool? = nil,
        gameLanguage: Language? = nil,
        muteInBackground: Bool? = nil,
        copyText: Bool? = nil,
        textHooker: Bool? = nil,
        textWebSocket: Bool? = nil,
        textWebSocketPort: Int? = nil,
        screenshotNotice: Bool? = nil,
        textWebSocketOrigin: String? = nil
    ) {
        self.prompts = prompts
        self.fullscreen = fullscreen
        self.windowWidth = windowWidth
        self.windowHeight = windowHeight
        self.monitor = monitor
        self.vsync = vsync
        self.gameLanguage = gameLanguage
        self.muteInBackground = muteInBackground
        self.copyText = copyText
        self.textHooker = textHooker
        self.textWebSocket = textWebSocket
        self.textWebSocketPort = textWebSocketPort
        self.screenshotNotice = screenshotNotice
        self.textWebSocketOrigin = textWebSocketOrigin
    }

    public var windowSize: (width: Int, height: Int)? {
        guard let w = windowWidth, let h = windowHeight else { return nil }
        return (w, h)
    }
}

/// Reads and writes `settings.ini`.
public enum AppSettings {
    /// The file name, next to `save.dat`.
    public static let fileName = "settings.ini"

    /// The byte of the config block of `save.dat` that remembers the window mode (0 = windowed, 1 = borderless fullscreen).
    public static let windowModeOffset = 0xA9

    /// The file and command-line name of a language: ja, en, zc or zt.
    public static func languageName(_ language: Language) -> String {
        switch language {
        case .ja: return "ja"
        case .zc: return "zc"
        case .zt: return "zt"
        default: return "en"
        }
    }

    /// Reads a language name (ja, en, zc, zt; a few aliases); nil when it is none.
    public static func tryParseLanguage(_ text: String?) -> Language? {
        let t = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch t {
        case "ja", "jp", "japanese", "0":
            return .ja
        case "en", "english", "1":
            return .en
        case "zc", "zh-cn", "zh-hans", "2":
            return .zc
        case "zt", "zh-tw", "zh-hant", "3":
            return .zt
        default:
            return nil
        }
    }

    /// Reads on / off (also true, false, yes, no, 1, 0); nil when it is neither.
    public static func tryParseSwitch(_ text: String?) -> Bool? {
        let t = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch t {
        case "on", "true", "yes", "1":
            return true
        case "off", "false", "no", "0":
            return false
        default:
            return nil
        }
    }

    /// Reads `WxH` (also `W x H` and the multiplication sign); nil when it is not two sizes in range.
    public static func tryParseWindow(_ text: String?) -> (width: Int, height: Int)? {
        let s = (text ?? "").replacingOccurrences(of: "×", with: "x").replacingOccurrences(of: "X", with: "x")
        let parts = s.split(separator: "x").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 2,
              let w = Int(parts[0]),
              let h = Int(parts[1]),
              w >= AppSettingsData.minWindowWidth && w <= AppSettingsData.maxWindowSide,
              h >= AppSettingsData.minWindowHeight && h <= AppSettingsData.maxWindowSide else {
            return nil
        }
        return (w, h)
    }

    /// Reads `x,y`; nil when it is not two integers.
    public static func tryParseMonitor(_ text: String?) -> MonitorOrigin? {
        let parts = (text ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 2,
              let x = Int(parts[0]),
              let y = Int(parts[1]) else {
            return nil
        }
        return MonitorOrigin(x, y)
    }

    /// Reads one ASCII browser origin without credentials, a path, a query or a fragment.
    public static func tryParseWebSocketOrigin(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        for u in text.utf8 {
            if u > 127 || u <= 32 || u == UInt8(ascii: "\\") {
                return nil
            }
        }
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), (scheme == "http" || scheme == "https"),
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil,
              url.path == "" || url.path == "/",
              url.query == nil, url.fragment == nil else {
            return nil
        }
        if let port = url.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    /// Reads settings from text: lines of `key=value`, `#` comments, unknown keys and bad values left at defaults.
    public static func parse(_ text: String?) -> AppSettingsData {
        var data = AppSettingsData()
        let lines = (text ?? "").components(separatedBy: "\n")
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), let eq = line.firstIndex(of: "="), eq > line.startIndex else {
                continue
            }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)

            switch key {
            case "prompts":
                var s = PromptSetting.auto
                if PromptStyles.tryParse(value, setting: &s) {
                    data.prompts = s
                }
            case "fullscreen":
                if let full = tryParseSwitch(value) {
                    data.fullscreen = full
                }
            case "vsync":
                if let vsync = tryParseSwitch(value) {
                    data.vsync = vsync
                }
            case "window":
                if let (w, h) = tryParseWindow(value) {
                    data.windowWidth = w
                    data.windowHeight = h
                }
            case "monitor":
                if let origin = tryParseMonitor(value) {
                    data.monitor = origin
                }
            case "language":
                if let lang = tryParseLanguage(value) {
                    data.gameLanguage = lang
                }
            case "mute_in_background":
                if let mute = tryParseSwitch(value) {
                    data.muteInBackground = mute
                }
            case "copy_text":
                if let copy = tryParseSwitch(value) {
                    data.copyText = copy
                }
            case "text_hooker":
                if let hooker = tryParseSwitch(value) {
                    data.textHooker = hooker
                }
            case "text_websocket":
                if let socket = tryParseSwitch(value) {
                    data.textWebSocket = socket
                }
            case "text_websocket_port":
                if let port = Int(value), port >= 1 && port <= Int(UInt16.max) {
                    data.textWebSocketPort = port
                }
            case "text_websocket_origin":
                if let origin = tryParseWebSocketOrigin(value) {
                    data.textWebSocketOrigin = origin
                }
            case "screenshot_notice":
                if let notice = tryParseSwitch(value) {
                    data.screenshotNotice = notice
                }
            default:
                break
            }
        }
        return data
    }

    /// The text of a settings file.
    public static func format(_ data: AppSettingsData) -> String {
        var text = ""
        text += "# Tsuki app settings (kept apart from the game's save data; the launcher writes this file, the game reads it at start)\n"
        text += "# prompts: auto, keyboard, playstation or xbox\n"
        text += "prompts=\(PromptStyles.name(data.prompts))\n"

        if let full = data.fullscreen {
            text += "# fullscreen: on or off, for the next start only (then Alt+Enter / F11 and the game's own memory take over)\n"
            text += "fullscreen=\(full ? "on" : "off")\n"
        }

        if let size = data.windowSize {
            text += "# window: the windowed size at start, width x height\n"
            text += "window=\(size.width)x\(size.height)\n"
        }

        if let monitor = data.monitor {
            text += "# monitor: left,top of the display to open on, in virtual-desktop pixels (the launcher lists them)\n"
            text += "monitor=\(monitor)\n"
        }

        if let vsync = data.vsync {
            text += "# vsync: on (presents wait for the monitor) or off (the game's own 60 Hz timer)\n"
            text += "vsync=\(vsync ? "on" : "off")\n"
        }

        if let language = data.gameLanguage {
            text += "# language: ja, en, zc or zt, for the next start only (the config screen changes it later)\n"
            text += "language=\(languageName(language))\n"
        }

        if let mute = data.muteInBackground {
            text += "# mute_in_background: on fades every sound out while the game window has no focus (Config > Sound > Mute in Background)\n"
            text += "mute_in_background=\(mute ? "on" : "off")\n"
        }

        if let copy = data.copyText {
            text += "# copy_text: on puts each new message's text on the clipboard for text hookers and dictionaries (Config > System > Copy Text to Clipboard)\n"
            text += "copy_text=\(copy ? "on" : "off")\n"
        }

        if let hooker = data.textHooker {
            text += "# text_hooker: on (the default) passes each new line through the GDI text calls LunaHook / Textractor attach to (Config > System > Text Hooker Output)\n"
            text += "text_hooker=\(hooker ? "on" : "off")\n"
        }

        if let socket = data.textWebSocket {
            text += "# text_websocket: on serves each new line as a text frame on ws://127.0.0.1:<text_websocket_port> for texthooker pages (Config > System > Text WebSocket)\n"
            text += "text_websocket=\(socket ? "on" : "off")\n"
        }

        if let port = data.textWebSocketPort {
            text += "# text_websocket_port: the WebSocket's port, 1..65535 (6677 when the line is missing)\n"
            text += "text_websocket_port=\(port)\n"
        }

        if let origin = tryParseWebSocketOrigin(data.textWebSocketOrigin) {
            text += "# text_websocket_origin: the trusted page's HTTP or HTTPS origin, with no path. Use an ASCII or punycode host. Restart the program after changing it\n"
            text += "text_websocket_origin=\(origin)\n"
        }

        if let notice = data.screenshotNotice {
            text += "# screenshot_notice: on (the default) shows the short \"Screenshot saved\" notice after F12; off saves the picture silently (Config > System > Screenshot Notice)\n"
            text += "screenshot_notice=\(notice ? "on" : "off")\n"
        }

        return text
    }

    /// Reads the file at `path`; default when missing or unreadable.
    public static func load(_ path: String?) -> AppSettingsData {
        guard let path = path, FileManager.default.fileExists(atPath: path) else {
            return AppSettingsData()
        }
        do {
            let text = try String(contentsOfFile: path, encoding: .utf8)
            return parse(text)
        } catch {
            return AppSettingsData()
        }
    }

    /// Writes the file atomically through a temporary file.
    public static func save(_ path: String?, _ data: AppSettingsData) -> Bool {
        guard let path = path else { return false }
        let temp = path + ".tmp"
        let text = format(data)
        do {
            let dir = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try text.write(toFile: temp, atomically: false, encoding: .utf8)
            _ = try? FileManager.default.removeItem(atPath: path)
            try FileManager.default.moveItem(atPath: temp, toPath: path)
            return true
        } catch {
            _ = try? FileManager.default.removeItem(atPath: temp)
            return false
        }
    }

    /// Reads the file, lets `change` alter the values and writes it back.
    public static func update(_ path: String?, _ change: (AppSettingsData) -> AppSettingsData) -> Bool {
        guard let path = path else { return false }
        return save(path, change(load(path)))
    }
}
