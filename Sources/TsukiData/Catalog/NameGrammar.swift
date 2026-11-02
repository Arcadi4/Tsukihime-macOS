import Foundation
import TsukiCore
import TsukiEngine

/// What an archive entry is for (docs/formats/archives_ui_movies.md 3); the wire names are those of `tsuki.catalog.Category`.
public enum NameCategory: String, CaseIterable, Sendable {
    /// BLACK / BLUE / ... 1920x1080 fills.
    case solidColor = "solid_color"
    /// IMGnnnn: a background or event CG.
    case scene = "scene"
    /// IMGnnnn_aa_bb: a variant of IMGnnnn picked by STCH a9 / a10.
    case sceneLayer = "scene_layer"
    /// IMG3000..IMG4193: gallery and flowchart only, never scripted.
    case galleryImage = "gallery_image"
    /// CCC_S_XX_YY_Pnn: a character sprite (a face of a body, or standalone).
    case sprite = "sprite"
    /// ..._B: the body a paired sprite's face is drawn over.
    case spriteBody = "sprite_body"
    /// ..._aa_bb: a sprite variant picked by STCH a9 / a10.
    case spriteLayer = "sprite_layer"
    /// allpac3 *_PARTS*.MRG: UI texture sheets.
    case uiParts = "ui_parts"
    /// One child image of a UI parts archive.
    case uiPart = "ui_part"
    /// GALLERY_PARTS_{CG,FC}_TH.MRG.
    case uiThumbnails = "ui_thumbnails"
    /// RULE_nn: 8-bit grey wipe masks.
    case transitionRule = "transition_rule"
    /// CAUTION*: boot notices.
    case cautionScreen = "caution_screen"
    /// DUMMY.MRG, CGMODE_TOP.MRG, *_TOP.MZP.
    case placeholder = "placeholder"
    /// parts.mrg entries.
    case systemScreen = "system_screen"
    /// Anything else.
    case unknown = "unknown"

    /// The wire name, as `tsuki.catalog.Category` writes it (`scene_layer`).
    public var wire: String { rawValue }
}

/// The result of `NameGrammar.classify`.
public struct NameInfo: Equatable, Sendable {
    /// The name as given.
    public let name: String
    /// What it is.
    public let category: NameCategory
    /// Language code when the name carries one.
    public let lang: String
    /// The name the entry belongs to (scene or sprite base, UI set).
    public let base: String
    /// The three-letter character code of a sprite.
    public let charCode: String
    /// The engine's character id (0 when unknown).
    public let charId: Int
    /// The character's name (inferred, [H] in the documents).
    public let charName: String
    /// The sprite size letter A / L / M / S.
    public let sizeClass: String
    /// The `aa_bb` of a variant.
    public let layer: String
    /// One sentence about the category.
    public let detail: String

    public init(name: String, category: NameCategory, lang: String = "", base: String = "", charCode: String = "",
                charId: Int = 0, charName: String = "", sizeClass: String = "", layer: String = "", detail: String = "") {
        self.name = name
        self.category = category
        self.lang = lang
        self.base = base
        self.charCode = charCode
        self.charId = charId
        self.charName = charName
        self.sizeClass = sizeClass
        self.layer = layer
        self.detail = detail
    }
}

/// The name grammar of the picture archives (docs/formats/archives_ui_movies.md 3): scenes, variants, sprites, bodies, UI
/// sets, rules, caution screens. A port of `tsuki.catalog.classify_name` and its tables.
public enum NameGrammar {
    private static let solidColors = ["BLACK", "BLUE", "GREEN", "ORANGE", "RED", "WHITE", "YELLOW"]

    /// Three-letter character code to (eboot char_id, name); the names are inferred from the code letters [H].
    public static let charCodes: [String: (charId: Int, name: String)] = [
        "SIK": (1, "Shiki Tohno"), "ARU": (2, "Arcueid Brunestud"), "SIE": (3, "Ciel"),
        "NOE": (4, "Noel"), "ROA": (5, "Roa"), "HIS": (6, "Hisui"), "KOH": (7, "Kohaku"),
        "AKI": (8, "Akiha Tohno"), "ARI": (9, "Arihiko Inui"), "MAR": (10, "Mario"),
        "VRV": (11, "Vlov"), "AOK": (12, "Aoko Aozaki"), "BOY": (13, "boy (minor)"),
        "ARA": (14, "Professor Arach"), "AND": (15, "Ando"), "KAR": (16, "Karius"),
        "GOT": (17, "Gouto Saiki"), "SAT": (18, "Satsuki Yumizuka"), "MIO": (21, "Mio"),
        "KUR": (23, "unknown (KUR)"), "KRO": (24, "unknown (KRO)"), "Z01": (25, "extra Z01"),
        "Z02": (26, "extra Z02"), "Z11": (27, "extra Z11"), "Z12": (28, "extra Z12"),
        "Z20": (29, "extra Z20"), "Y00": (30, "extra Y00"),
    ]

    /// Sprite size letter to eboot size_class (image-table +0x42).
    public static let sizeClasses: [String: Int] = ["A": 0, "L": 1, "M": 2, "S": 3]

    /// allpac3 UI set to (eboot base name, purpose). Children are image MZPs.
    public static let uiPartsSets: [String: (ebootName: String, purpose: String)] = [
        "CONF_PARTS": ("conf_parts.mrg", "config screen: tabs, buttons (3 states per sheet), sliders, key help, language selector"),
        "DISP_PARTS": ("disp_parts.mrg", "in-game HUD: text windows, control panel, button glyphs, saving icon, quick menu"),
        "MENU_PARTS": ("menu_parts.mrg", "system menu: Save/Load/Config/FlowChart/Title buttons, backgrounds, route list"),
        "MODEPNL_PARTS": ("modepnl_parts.mrg", "mode panel bar (identical in all languages)"),
        "SAVE_PARTS": ("save_parts.mrg", "save/load screen: route cards, digits, chapter list, AUTO SAVE tag"),
        "TITLE_PARTS": ("title_parts.mrg", "title screen: logo, menu items, PRESS ANY BUTTON, (C)TYPE-MOON, backgrounds"),
        "SELECT_PARTS": ("select_parts.mrg", "choice screen frames/backgrounds (language-neutral)"),
        "SELECTTXT_PARTS": ("selecttxt_parts.mrg", "82 choice texts pre-rendered as 1416x416 images (Japanese; identical in all 5 sets) + digit column (child 82, loaded into slot 97 via the child clamp)"),
        "BORDER_PARTS": ("border_parts.mrg", "border / frame textures at 20..512 px (type 11)"),
        "EFFECT_PARTS": ("effect_parts.mrg", "effect textures (3 dummies + 1920x128 strip)"),
        "NOISE_PARTS": ("noise_parts.mrg", "two 1920x1080 noise textures"),
        "GALLERY_PARTS_COMMON": ("gallery_parts_common.mrg", "gallery shared frame/background"),
        "GALLERY_PARTS_CG": ("gallery_parts_cg.mrg", "CG gallery headers"),
        "GALLERY_PARTS_CG_TH": ("gallery_parts_cg_th.mrg", "CG gallery thumbnails (1979)"),
        "GALLERY_PARTS_MUSIC": ("gallery_parts_music.mrg", "music room"),
        "GALLERY_PARTS_FC": ("gallery_parts_fc.mrg", "flowchart screen"),
        "GALLERY_PARTS_FC_TH": ("gallery_parts_fc_th.mrg", "flowchart scene thumbnails (495)"),
        "GALLERY_PARTS_MOVIE": ("gallery_parts_movie.mrg", "movie gallery"),
        "GALLERY_PARTS_ENDING": ("gallery_parts_ending.mrg", "ending list"),
    ]

    /// The wire name of a category, as `tsuki.catalog.Category` writes it (`scene_layer`).
    public static func wire(_ c: NameCategory) -> String { c.rawValue }

    /// Classifies an asset by its NAM name (extension optional, case-insensitive). Only ASCII names are meaningful.
    /// A name that the Python reference would reject with a KeyError (a `_TH` suffix on a set without thumbnails) is
    /// `.unknown` here.
    public static func classify(_ name: String) -> NameInfo {
        let up = name.uppercased()
        let dot = up.lastIndex(of: ".")
        let head = dot.map { String(up[up.startIndex..<$0]) } ?? ""
        let stem = head.isEmpty ? up : head

        if solidColors.contains(stem) {
            return NameInfo(name: name, category: .solidColor, detail: "1920x1080 solid fill")
        }

        if stem == "DUMMY" || stem == "CGMODE_TOP" {
            return NameInfo(name: name, category: .placeholder, detail: "128-byte 16x16 transparent image MZP despite .MRG")
        }

        if stem.hasSuffix("_TOP") {
            return NameInfo(name: name, category: .placeholder, detail: "128x96 white image (1216 bytes, shared)")
        }

        if let scene = sceneName(stem) {
            if let layer = scene.layer {
                return NameInfo(name: name, category: .sceneLayer, base: "IMG" + scene.digits, layer: layer,
                                detail: "variant of the base shown instead of it by _STCH/_SCH2(..., base, ..., a9=aa, a10=bb)")
            }

            if scene.number >= 3000 && scene.number <= 4193 {
                return NameInfo(name: name, category: .galleryImage, base: stem,
                                detail: "allpac1_2 only, never referenced by scripts, listed by gallery tables")
            }

            return NameInfo(name: name, category: .scene, base: stem, detail: "background or event CG")
        }

        if let sprite = spriteName(stem) {
            let character = charCodes[sprite.code] ?? (0, "unknown")
            let category: NameCategory
            let detail: String
            var layer = ""
            if sprite.isBody {
                category = .spriteBody
                detail = "body; drawn under the face of every image-table record whose file it is"
            } else if let variant = sprite.layer {
                category = .spriteLayer
                layer = variant
                detail = "variant of the base sprite shown instead of it by _STCH/_SCH2(..., base, ..., a9=aa, a10=bb)"
            } else {
                category = .sprite
                detail = "script-visible sprite name; draw its image-table record: file, then overlay if set "
                    + "(3,529 records pair a _B body with this face, 1,221 are standalone)"
            }
            return NameInfo(name: name, category: category, base: sprite.base, charCode: sprite.code,
                            charId: character.charId, charName: character.name, sizeClass: sprite.size,
                            layer: layer, detail: detail)
        }

        if stem.hasPrefix("RULE_") {
            return NameInfo(name: name, category: .transitionRule, detail: "1920x1080 8-bit grey wipe mask")
        }

        if stem.hasPrefix("CAUTION") {
            let m = cautionName(stem)
            let lang = (m?.lang ?? "").lowercased()
            let kind: String
            switch m?.number ?? "" {
            case "": kind = "fiction/violence disclaimer"
            case "1": kind = "recording/streaming notice"
            case "2": kind = "disclaimer + recording notice"
            default: kind = "?"
            }
            return NameInfo(name: name, category: .cautionScreen, lang: lang, detail: kind)
        }

        let split = languageSplit(stem)
        let setName = split?.base ?? stem
        let langCode = split?.lang ?? ""
        if uiPartsSets[setName] != nil || uiPartsSets["\(setName)_\(langCode)"] != nil {
            if langCode == "TH" {
                guard let thumbnails = uiPartsSets["\(setName)_TH"] else {
                    return NameInfo(name: name, category: .unknown)
                }
                return NameInfo(name: name, category: .uiThumbnails, base: "\(setName)_TH", detail: thumbnails.purpose)
            }

            guard let set = uiPartsSets[setName] else {
                return NameInfo(name: name, category: .unknown)
            }
            return NameInfo(name: name, category: .uiParts, lang: langCode.lowercased(), base: setName, detail: set.purpose)
        }

        return NameInfo(name: name, category: .unknown)
    }

    // MARK: - The four regular expressions of `tsuki.catalog`

    private struct SceneName {
        let number: Int
        /// The four digits behind `IMG`.
        let digits: String
        /// `aa_bb` of a variant, nil for a plain scene.
        let layer: String?
    }

    private struct SpriteName {
        let code: String
        let size: String
        /// `CCC_S_XX_YY_Pnn`.
        let base: String
        /// `aa_bb` of a variant, nil when there is none.
        let layer: String?
        /// True for the `_B` body.
        let isBody: Bool
    }

    /// `^IMG(?<num>[0-9]{4})(?:_(?<la>[0-9]{2})_(?<lb>[0-9]{2}))?\z`
    private static func sceneName(_ stem: String) -> SceneName? {
        let b = Array(stem.utf8)
        guard b.count == 7 || b.count == 13 else { return nil }
        guard b[0] == 0x49, b[1] == 0x4D, b[2] == 0x47 else { return nil }
        guard isDigit(b[3]), isDigit(b[4]), isDigit(b[5]), isDigit(b[6]) else { return nil }
        let digits = String(decoding: b[3...6], as: UTF8.self)
        guard let number = Int(digits) else { return nil }
        if b.count == 7 {
            return SceneName(number: number, digits: digits, layer: nil)
        }

        guard b[7] == 0x5F, isDigit(b[8]), isDigit(b[9]), b[10] == 0x5F, isDigit(b[11]), isDigit(b[12]) else {
            return nil
        }
        let layer = String(decoding: b[8...9], as: UTF8.self) + "_" + String(decoding: b[11...12], as: UTF8.self)
        return SceneName(number: number, digits: digits, layer: layer)
    }

    /// `^(?<char>[A-Z]{3}|[ZY][0-9][0-9])_(?<size>[ALMS])_(?<group>[0-9][0-9])_(?<pose>[0-9][0-9])_(?<vletter>[NABC])(?<expr>[0-9][0-9])(?:_(?<body>B)|_(?<la>[0-9][0-9])_(?<lb>[0-9][0-9]))?\z`
    private static func spriteName(_ stem: String) -> SpriteName? {
        let b = Array(stem.utf8)
        guard b.count == 15 || b.count == 17 || b.count == 21 else { return nil }

        let codeIsLetters = isUpper(b[0]) && isUpper(b[1]) && isUpper(b[2])
        let codeIsZY = (b[0] == 0x5A || b[0] == 0x59) && isDigit(b[1]) && isDigit(b[2])
        guard codeIsLetters || codeIsZY else { return nil }
        guard b[3] == 0x5F, isSizeLetter(b[4]), b[5] == 0x5F, isDigit(b[6]), isDigit(b[7]),
              b[8] == 0x5F, isDigit(b[9]), isDigit(b[10]), b[11] == 0x5F, isVariantLetter(b[12]),
              isDigit(b[13]), isDigit(b[14]) else { return nil }

        let code = String(decoding: b[0...2], as: UTF8.self)
        let size = String(decoding: b[4...4], as: UTF8.self)
        let base = String(decoding: b[0...14], as: UTF8.self)
        if b.count == 15 {
            return SpriteName(code: code, size: size, base: base, layer: nil, isBody: false)
        }

        guard b[15] == 0x5F else { return nil }
        if b.count == 17 {
            guard b[16] == 0x42 else { return nil }
            return SpriteName(code: code, size: size, base: base, layer: nil, isBody: true)
        }

        guard isDigit(b[16]), isDigit(b[17]), b[18] == 0x5F, isDigit(b[19]), isDigit(b[20]) else { return nil }
        let layer = String(decoding: b[16...17], as: UTF8.self) + "_" + String(decoding: b[19...20], as: UTF8.self)
        return SpriteName(code: code, size: size, base: base, layer: layer, isBody: false)
    }

    /// `^(?<base>.+?)_(?<lang>JA|EN|ZC|ZT|KO|TH)\z`
    private static func languageSplit(_ stem: String) -> (base: String, lang: String)? {
        let b = Array(stem.utf8)
        guard b.count >= 4, b[b.count - 3] == 0x5F else { return nil }
        let lang = String(decoding: b[(b.count - 2)...], as: UTF8.self)
        guard lang == "JA" || lang == "EN" || lang == "ZC" || lang == "ZT" || lang == "KO" || lang == "TH" else {
            return nil
        }
        return (String(decoding: b[0..<(b.count - 3)], as: UTF8.self), lang)
    }

    /// `^CAUTION(?<n>[0-9]?)(?:_(?<lang>JA|EN|ZC|ZT))?\z`; nil when the pattern does not match.
    private static func cautionName(_ stem: String) -> (number: String, lang: String)? {
        let b = Array(stem.utf8)
        guard b.count >= 7 else { return nil }
        var i = 7
        var number = ""
        if i < b.count && isDigit(b[i]) {
            number = String(decoding: b[i...i], as: UTF8.self)
            i += 1
        }

        var lang = "JA"
        if i < b.count {
            guard b[i] == 0x5F, i + 2 < b.count else { return nil }
            let code = String(decoding: b[(i + 1)...(i + 2)], as: UTF8.self)
            guard code == "JA" || code == "EN" || code == "ZC" || code == "ZT" else { return nil }
            lang = code
            i += 3
        }

        guard i == b.count else { return nil }
        return (number, lang)
    }

    private static func isDigit(_ c: UInt8) -> Bool { c >= 0x30 && c <= 0x39 }
    private static func isUpper(_ c: UInt8) -> Bool { c >= 0x41 && c <= 0x5A }

    private static func isSizeLetter(_ c: UInt8) -> Bool {
        c == 0x41 || c == 0x4C || c == 0x4D || c == 0x53  // A L M S
    }

    private static func isVariantLetter(_ c: UInt8) -> Bool {
        c == 0x4E || c == 0x41 || c == 0x42 || c == 0x43  // N A B C
    }
}
