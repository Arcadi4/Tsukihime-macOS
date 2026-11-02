import Foundation
import TsukiCore
import TsukiData
import TsukiEngine
import TsukiUi

/// Name, title and start-up language of the game program.
public enum AppIdentity {
    public static let productName = GameTitles.productName
    public static let executableName = "Tsukihime"
    public static let iconSize = 64
    public static let version = "1.0.0"
    public static let isPersonalBuild = false

    public static func windowTitle(source: GameFolderSource?, language: Language) -> String {
        source == nil ? GameTitles.fallback(language) : source!.title(language)
    }

    public static func startupLanguage(args: AppArgs, settings: AppSettingsData, store: SaveStore?) -> Language {
        if let forced = args.language, let lang = Language(rawValue: UInt8(forced)), isSelectable(lang) {
            return lang
        }

        if let pending = settings.gameLanguage, isSelectable(pending) {
            return pending
        }

        if let store = store {
            let saved = Int(store.systemData.block.config.language)
            if saved >= 0 && saved <= 3, let lang = Language(rawValue: UInt8(saved)), isSelectable(lang) {
                return lang
            }
        }

        return PortText.fromCultureName(Locale.current.identifier)
    }

    private static func isSelectable(_ language: Language) -> Bool {
        language == .ja || language == .en || language == .zc || language == .zt
    }
}
