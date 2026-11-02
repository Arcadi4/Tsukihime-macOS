import TsukiCore
import Foundation
import TsukiEngine

/// Which allpac3 archive holds a UI sheet set (docs/formats/archives_ui_movies.md 5.2, 7.3): the eboot's base name of the set
/// (`conf_parts.mrg`), and for the sets with language variants the loader's rule that turns it into `conf_parts_en.mrg`
/// (`UiTextureTables.localizePartsName`). The NAM search upper-cases the name, so it finds `CONF_PARTS_EN.MRG`.
public enum UiSheetNames {
    /// The eboot base name of a set, as in its registration tables.
    public static func baseName(_ set: UiSet) -> String {
        switch set {
        case .confParts: return "conf_parts.mrg"
        case .dispParts: return "disp_parts.mrg"
        case .menuParts: return "menu_parts.mrg"
        case .modePnlParts: return "modepnl_parts.mrg"
        case .saveParts: return "save_parts.mrg"
        case .titleParts: return "title_parts.mrg"
        case .selectParts: return "select_parts.mrg"
        case .selectTxtParts: return "selecttxt_parts.mrg"
        case .borderParts: return "border_parts.mrg"
        case .effectParts: return "effect_parts.mrg"
        case .noiseParts: return "noise_parts.mrg"
        case .galleryPartsCommon: return "gallery_parts_common.mrg"
        case .galleryPartsCg: return "gallery_parts_cg.mrg"
        case .galleryPartsCgTh: return "gallery_parts_cg_th.mrg"
        case .galleryPartsMusic: return "gallery_parts_music.mrg"
        case .galleryPartsFc: return "gallery_parts_fc.mrg"
        case .galleryPartsFcTh: return "gallery_parts_fc_th.mrg"
        case .galleryPartsMovie: return "gallery_parts_movie.mrg"
        case .galleryPartsEnding: return "gallery_parts_ending.mrg"
        }
    }

    /// True when the set exists once per language (`_JA` .. `_KO`); false for the six language-free sets.
    public static func hasLanguageVariants(_ set: UiSet) -> Bool {
        switch set {
        case .selectParts, .borderParts, .effectParts, .noiseParts, .galleryPartsCgTh, .galleryPartsFcTh:
            return false
        default:
            return true
        }
    }

    /// The archive name searched in allpac3 for a set in a language (`conf_parts_en.mrg`, or `border_parts.mrg` for a
    /// language-free set).
    public static func fileName(_ set: UiSet, _ lang: Language) -> String {
        hasLanguageVariants(set)
            ? UiTextureTables.localizePartsName(baseName(set), lang: Int(lang.rawValue))
            : baseName(set)
    }
}
