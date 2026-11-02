import Foundation
import TsukiData

public enum CensusAllowList {
    public static let pictureScriptBugs: [String: String] = [
        "IMG5007_02_02": "script bug: _STCH names a variant that is not in the picture list (archives_ui_movies.md 2.4)",
        "IMG5007_00_27": "script bug: _STCH names a variant that is not in the picture list (archives_ui_movies.md 2.4)",
        "IMG1637_28_28": "script bug: _STCH names a variant that is not in the picture list (archives_ui_movies.md 2.4)",
        "Z20_M_61_00_A00_10_00": "script bug: _STCH names a sprite variant that is not in the picture list (archives_ui_movies.md 2.4)",
        "SIK_A_32_00_N00_02_30": "script bug: _SCH2 takes the variant suffix of the layer it takes over and the result is not in the picture list (FORMATS 5.2)",
    ]

    public static let missingSpriteBodies: Set<String> = [
        "ARU_M_03_35_N00_B", "ARU_S_03_35_N00_B", "NOE_L_60_03_N00_B"
    ]

    public static func imageReason(_ image: ResolvedImage) -> String? {
        if !image.found {
            return pictureScriptBugs[image.key]
        }

        var any = false
        for (name, id) in [(image.file, image.fileId), (image.overlay, image.overlayId)] {
            guard let name = name, id == nil else { continue }
            any = true
            let stem = name.uppercased().hasSuffix(".MZP") ? String(name.dropLast(4)) : name
            if !missingSpriteBodies.contains(stem.uppercased()) {
                return nil
            }
        }
        return any ? "a sprite body that exists in no archive; the engine skips that layer (archives_ui_movies.md 3.3)" : nil
    }

    public static let glyphFallbacks: [String: Int] = [
        "zc_efbd82": 3,
        "zc_efbd81": 2,
        "zc_e9b2bd": 1,
        "zt_e9b088": 1,
    ]

    public static func glyphFallbackReason(language: String, key: String, uses: Int) -> String? {
        let lookupKey = "\(language)_\(key)"
        if let documented = glyphFallbacks[lookupKey], documented == uses {
            return "the font has no glyph for it; the engine draws the blank fallback (fonts.md 5.4, 9)"
        }
        return nil
    }

    public static func reason(_ reference: CensusReference) -> String? {
        guard reference.kind == .motion else { return nil }
        switch reference.result {
        case "zero":
            return "motion id 0 selects no motion (script.md doc_checks item 3: 92 statements)"
        case "out" where reference.key == "101960":
            return "script bug: the one motion id past the table (script.md doc_checks item 3)"
        default:
            return nil
        }
    }
}
