import Foundation
import TsukiCore
import TsukiEngine

extension AppServices {
    func rebuildHost(language: Language) {
        let old = host
        let running = storyActive && old.phase == .running
        var carry: SlotImage?
        if running, let history = old.history, history.staging.used != 0 {
            carry = history.staging.clone()
        }

        let profile = old.profile
        let newHost = parts.hostFactory(language, profile)
        hostLanguage = language
        host = newHost
        attachHost(newHost)

        if let carry = carry {
            let temp = SaveStore()
            temp.saveManual(0, carry, date())
            try? newHost.loadSlot(temp, slot: 0)
            newHost.setSkipLatch(false)
        } else if running {
            if old.replayRequested {
                _ = newHost.beginReplay(Int(profile.vars.getG(8)))
            } else {
                newHost.beginStory(old.sceneId)
            }
            newHost.setSkipLatch(false)
        }

        hostReplaced?(newHost)
    }

    public func setInitialLanguage(_ language: Language) {
        hostLanguage = language
    }
}
