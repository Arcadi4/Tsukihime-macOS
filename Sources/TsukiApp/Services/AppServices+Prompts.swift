import Foundation
import TsukiPlatform
import TsukiUi

extension AppServices {
    private var prompts: PromptState {
        if let p = promptStateObj {
            return p
        }
        let p = PromptState(settingsPath: parts.settingsPath, overrideSetting: parts.promptOverride) { [weak self] msg in
            self?.log(msg)
        }
        promptStateObj = p
        return p
    }

    public var promptSetting: PromptSetting {
        get { prompts.setting }
        set { prompts.setting = newValue }
    }

    public var promptStyle: PromptStyle {
        prompts.style
    }

    public func observeDevice(_ device: InputDevice) {
        prompts.observe(device)
    }
}
