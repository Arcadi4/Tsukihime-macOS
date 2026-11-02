import Foundation
import TsukiCore
import TsukiEngine

/// The constants and the small pure rules of `script_text.mrg` and its markup (docs/formats/text.md
/// 2-6). Nothing here reads a file.
public enum TextRules {
    /// Sections of `script_text.mrg`: an offset table and a string blob per language (text.md 2.1).
    public static let sectionCount = 10

    /// The end mark of an offset table.
    public static let endMark: UInt32 = 0xFFFF_FFFF

    /// Bytes of one line the engine copies: 0x301 minus the CR LF (VA 0x75F80).
    public static let engineLineMax = 0x2FF

    /// Output cap of the `$` expansion (VA 0x76040 stops once the output exceeds 0x2FB bytes).
    public static let engineExpandMax = 0x2FC

    /// Copy cap of a text command's argument (VA 0x92458) and the `src_len` passed to the expansion.
    public static let messageArgMax = 0x300

    /// Choice slot k < 9 gets the number line 43960 + k (`1．`..`9．`).
    public static let choiceNumberBase = 43960

    /// Choice slot k >= 9 gets line 43959 (`０．`).
    public static let choiceNumberOverflow = 43959

    /// Bytes per choice slot (VA 0x174FB70 + k * 0xFA).
    public static let choiceSlotSize = 0xFA

    /// The shipped value of the language option word (VA 0x66C59C).
    public static let languageOptionUnset = 0xFFFF

    /// Lines per language in the retail data.
    public static let retailLineCount = 43_969

    /// Language codes by engine index (the suffix table at VA 0x42C030).
    public static let languageCodes: [String] = ["ja", "en", "zc", "zt", "ko"]

    /// The four languages the options screen can select (text.md 3).
    public static let selectableLanguages: [Language] = [.ja, .en, .zc, .zt]

    /// The 39 inline icon names in engine order (table at VA 0x2D3580, 39 x 11 bytes; text.md 6.4).
    public static let iconNames: [String] = [
        "heart", "heart2", "star", "star2", "edia", "dummy", "onpu",
        "ber00", "ber01", "ber02", "ber03", "ber04", "ber05", "ber06", "ber07", "ber08", "ber09", "ber10",
        "ber11", "ber12", "ber13", "ber14", "ber15", "ber16", "ber17", "ber18", "ber19", "ber20",
        "ber21", "ber22", "ber23", "ber24", "ber25", "ber26", "ber27", "ber28", "ber29", "ber30",
        "zap00",
    ]

    /// `@c1`..`@c5` colour words (u16 table at VA 0x2D34C0; entry 0 is unused, `@c0` is the default).
    public static let colorRgb565: [Int] = [0, 0xF800, 0x345F, 0x1082, 0xAD55, 0x001F]

    /// `@hN` / `@wN` multiply the base glyph height / width by `scaleTable[N]` (floats at VA 0x2D3730,
    /// widened to double as the Python table holds them).
    public static let scaleTable: [Double] = [
        0.34375, 0.3723958432674408, 0.4010416567325592, 0.4296875, 0.4583333432674408,
        0.4869791567325592, 0.2291666716337204, 0.2578125, 0.2864583134651184, 0.3151041865348816,
    ]

    /// The language code (`ja`, `en`, `zc`, `zt`, `ko`).
    public static func code(_ language: Language) -> String {
        languageCodes[Int(language.rawValue)]
    }

    /// Parses a language code.
    public static func parse(_ code: String) throws -> Language {
        for (index, known) in languageCodes.enumerated() where known == code {
            return Language(rawValue: UInt8(index))!
        }
        throw TsukiError.format("unknown language \"\(code)\"; expected one of \(languageCodes.joined(separator: ", "))")
    }

    /// The engine parses `<base|ruby>` for every layout language except English (VA 0xC6D58, text.md 3).
    public static func rubyEnabled(_ language: Language) -> Bool {
        language != .en
    }

    /// `sceSystemServiceParamGetInt(LANG)` to a text language (VA 0x407F0 and the fallback of 0x3ED90):
    /// 0 is ja, 11 is zc, 10 is zt, any other value and a failed call (nil) are English.
    public static func systemLanguageToText(_ systemLanguage: Int?) -> Int {
        switch systemLanguage {
        case 0: return 0
        case 11: return 2
        case 10: return 3
        default: return 1
        }
    }

    /// (language used by the `$` expansion, language used by the layout) for a stored option word
    /// (u16 at VA 0x66C59C; text.md 3). A negative word (shipped default 0xFFFF) is replaced by the
    /// system-language mapping at load; the expansion then uses the signed word as it is, the layout
    /// only 0..3.
    public static func effectiveLanguages(optionWord: Int, systemLanguage: Int?) -> (expansion: Int, layout: Int) {
        let word = optionWord & 0xFFFF
        var signed = (word & 0x8000) != 0 ? word - 0x1_0000 : word
        if signed < 0 {
            signed = systemLanguageToText(systemLanguage)
        }

        let layout = (0..<4).contains(signed) ? signed : systemLanguageToText(systemLanguage)
        return (signed, layout)
    }

    /// Line id of the number the choice handler (VA 0x993E0) puts in front of choice slot `slot` (the
    /// count of `_SELR` commands executed for the current menu, not the `_SELR` argument; text.md 5.2).
    public static func choiceNumberId(_ slot: Int) -> Int {
        precondition(slot >= 0, "choice slot must not be negative")
        return slot < 9 ? choiceNumberBase + slot : choiceNumberOverflow
    }

    /// Contents of choice slot `slot` before expansion: `$0439NN` followed by the `_SELR` message
    /// (VA 0x99427..0x994E5), as UTF-8. It is expanded with a source length of `choiceSlotSize` when shown.
    public static func choiceSlotText(_ slot: Int, message: ByteSpan) -> [UInt8] {
        let id = String(choiceNumberId(slot))
        let digits = String(repeating: "0", count: max(0, 6 - id.count)) + id
        var result = Array(("$" + digits).utf8)
        result.append(contentsOf: message)
        return result
    }
}
