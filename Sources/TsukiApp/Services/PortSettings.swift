import Foundation
import TsukiUi

/// The port's switches, applied at once and saved to `settings.ini`.
public final class PortSettings: UiPortSettings {
    private let settingsPath: String?
    private let log: ((String) -> Void)?
    private var _mute: Bool
    private var _copy: Bool
    private var _hooker: Bool
    private var _socket: Bool
    private var _notice: Bool

    /// Raised after a switch changed (and was saved).
    public var changed: (() -> Void)?

    public init(settingsPath: String?, data: AppSettingsData, log: ((String) -> Void)? = nil) {
        self.settingsPath = settingsPath
        self.log = log
        self._mute = data.muteInBackground ?? false
        self._copy = data.copyText ?? false
        self._hooker = data.textHooker ?? true
        self._socket = data.textWebSocket ?? false
        self._notice = data.screenshotNotice ?? true
        self.textWebSocketPort = data.textWebSocketPort ?? AppSettingsData.defaultTextWebSocketPort
        self.textWebSocketOrigin = data.textWebSocketOrigin
    }

    public var muteInBackground: Bool {
        get { _mute }
        set {
            guard _mute != newValue else { return }
            _mute = newValue
            save({ var s = $0; s.muteInBackground = newValue; return s }, "mute_in_background", newValue)
        }
    }

    public var copyTextToClipboard: Bool {
        get { _copy }
        set {
            guard _copy != newValue else { return }
            _copy = newValue
            save({ var s = $0; s.copyText = newValue; return s }, "copy_text", newValue)
        }
    }

    public var textHookerOutput: Bool {
        get { _hooker }
        set {
            guard _hooker != newValue else { return }
            _hooker = newValue
            save({ var s = $0; s.textHooker = newValue; return s }, "text_hooker", newValue)
        }
    }

    public var textWebSocket: Bool {
        get { _socket }
        set {
            guard _socket != newValue else { return }
            _socket = newValue
            save({ var s = $0; s.textWebSocket = newValue; return s }, "text_websocket", newValue)
        }
    }

    public var screenshotNotice: Bool {
        get { _notice }
        set {
            guard _notice != newValue else { return }
            _notice = newValue
            save({ var s = $0; s.screenshotNotice = newValue; return s }, "screenshot_notice", newValue)
        }
    }

    public let textWebSocketPort: Int
    public let textWebSocketOrigin: String?

    private func save(_ change: @escaping (AppSettingsData) -> AppSettingsData, _ key: String, _ value: Bool) {
        if let settingsPath = settingsPath {
            if AppSettings.update(settingsPath, change) {
                log?("\(key) \(value ? "on" : "off") saved to settings.ini")
            } else {
                log?("settings.ini not written (\(key))")
            }
        } else {
            log?("\(key) \(value ? "on" : "off") (not saved: no settings file)")
        }
        changed?()
    }
}
