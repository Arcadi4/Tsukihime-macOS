import TsukiCore
import Foundation
import TsukiEngine

/// The localized titles of the game, read from the user's own `sce_sys/param.sfo`, whose `TITLE_xx`
/// keys carry the localized titles under the PS4's language numbers, with the names of the analysed
/// copy as the fallback when the file or the key is missing.
public enum GameTitles {
    /// The name of the port as the player sees it in the programs, dialogs and shortcuts: never the
    /// short project name.
    public static let productName = "Tsukihime"

    /// The param.sfo key of a language: `TITLE_00` Japanese, `TITLE_01` English (US), `TITLE_11`
    /// Simplified Chinese, `TITLE_10` Traditional Chinese (the PS4's language numbers; the retail file
    /// has 00, 10 and 11 and leaves English to the plain `TITLE`). Korean has no selectable UI; it maps
    /// to the English key.
    public static func key(_ language: Language) -> String {
        switch language {
        case .ja: return "TITLE_00"
        case .zc: return "TITLE_11"
        case .zt: return "TITLE_10"
        default: return "TITLE_01"
        }
    }

    /// The title of the analysed copy (CUSA47999 01.01) when param.sfo cannot be read: the same words
    /// the file holds.
    public static func fallback(_ language: Language) -> String {
        switch language {
        case .ja: return "月姫 -A piece of blue glass moon-"
        case .zc, .zt: return "月姬 -A piece of blue glass moon-"
        default: return "TSUKIHIME -A piece of blue glass moon-"
        }
    }

    /// The title for `language`: the file's `key` entry, else the file's plain `TITLE` (for English only:
    /// the other languages fall back to their own words rather than to the English line), else
    /// `fallback`. Blank values count as missing.
    public static func of(_ sfo: ParamSfo?, _ language: Language) -> String {
        if let exact = trimmed(sfo?[key(language)]) {
            return exact
        }

        if language != .ja && language != .zc && language != .zt {
            if let plain = trimmed(sfo?["TITLE"]) {
                return plain
            }
        }

        return fallback(language)
    }

    /// The title of a game folder: its `sce_sys/param.sfo` read now (nil folder: the fallback).
    public static func forFolder(_ gameFolder: String?, _ language: Language) -> String {
        guard let gameFolder else { return fallback(language) }
        let path = (gameFolder as NSString).appendingPathComponent("sce_sys/param.sfo")
        return of(ParamSfo.tryRead(path), language)
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
