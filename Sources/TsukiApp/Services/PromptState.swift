import Foundation
import TsukiPlatform
import TsukiUi

/// The prompt setting and the last input device.
public final class PromptState {
    private let path: String?
    private let log: ((String) -> Void)?
    private var _setting: PromptSetting

    public init(settingsPath: String?, overrideSetting: PromptSetting? = nil, log: ((String) -> Void)? = nil) {
        self.path = settingsPath
        self.log = log
        self._setting = overrideSetting ?? AppSettings.load(settingsPath).prompts
    }

    public var setting: PromptSetting {
        get { _setting }
        set {
            guard _setting != newValue else { return }
            _setting = newValue
            if let path = path {
                let ok = AppSettings.update(path) { saved in
                    var s = saved
                    s.prompts = newValue
                    return s
                }
                if !ok {
                    log?("could not write \(path)")
                }
            }
        }
    }

    public private(set) var lastDevice: PromptStyle = .keyboard

    public var style: PromptStyle {
        PromptStyles.resolve(_setting, lastDevice)
    }

    public func observe(_ device: InputDevice) {
        lastDevice = Self.styleOf(device)
    }

    public static func styleOf(_ device: InputDevice) -> PromptStyle {
        switch device {
        case .playStationPad:
            return .playStation
        case .xboxPad:
            return .xbox
        default:
            return .keyboard
        }
    }
}
