import Foundation

/// The movie table and its language remap (docs/formats/archives_ui_movies.md 9.2-9.3; ARCHITECTURE 7.5). A script's
/// `_TOMP(id)` passes the language-neutral id; the engine remaps it to the table index of the language's copy before it
/// emits `MovieCommand.open`.
public enum MovieTable {
    /// Records in the table (ids 0..133; the record after them has id -1).
    public static let count = 134

    /// The first title background loop (`titlebg1`); the four are ids 0..3.
    public static let firstTitleBackground = 0

    /// The prologue movie id passed by the script.
    public static let prologue = 4

    /// Opening 1 (`op1_arc`).
    public static let opening1 = 5

    /// Opening 2 (`op2_ciel`).
    public static let opening2 = 6

    /// The first chapter title card (`phasetitle_*`); ids 8..34.
    public static let firstPhaseTitle = 8

    /// The last chapter title card.
    public static let lastPhaseTitle = 34

    private static let prologueByLanguage = [4, 46, 47, 106]

    /// The table index of movie `id` in `language` (the routine at eboot VA 0x5E280, 9.3):
    /// the prologue has four copies, the 27 title cards and the two openings have `_en` / `_zc` (and title cards `_zt`)
    /// variants, every other movie is shared.
    public static func remap(_ id: Int, _ language: Language) -> Int {
        let lang = Int(language.rawValue)
        if id == prologue {
            return lang < prologueByLanguage.count ? prologueByLanguage[lang] : prologueByLanguage[1]
        }

        if id >= firstPhaseTitle && id <= lastPhaseTitle {
            switch lang {
            case 0: return id
            case 3: return id + 99
            case 2: return id + 67
            default: return id + 40
            }
        }

        if id == opening1 || id == opening2 {
            switch lang {
            case 2, 3: return id + 99
            case 0: return id
            default: return id + 97
            }
        }

        return id
    }
}

/// The movie slots the engine uses in `MovieCommand`s (slot numbers are ours; ARCHITECTURE 3.2).
public enum MovieSlots {
    /// The full-screen movie of `_TOMP`, the TYPE-MOON logo and the chapter cards.
    public static let fullScreen = 0

    /// The looping title background (`titlebg1..4`, texture slot 0x87 on the PS4, system_flow.md 4.2).
    public static let titleBackground = 1
}
