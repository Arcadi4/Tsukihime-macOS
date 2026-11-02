import Foundation
import TsukiCore

/// The one protocol through which the engine, the UI and the media layer read game data
/// (ARCHITECTURE 3.2, 3.3).
///
/// Implementations only ever read the user's folder (ARCHITECTURE 1.2, 4.4), are safe to call from
/// the decode workers (ARCHITECTURE 3.4), and are keyed by the game's own ids (ARCHITECTURE 1.10).
public protocol GameData: AnyObject {
    /// Identity of the copy, as established by the build check (RR 3.3, ARCHITECTURE 4.1).
    var build: BuildInfo { get }

    /// The selectable languages this copy's data carries (package K25): script text, glyph pages and
    /// UI sheets all present. The config screen and the launcher hide the others.
    var availableLanguages: [Language] { get }

    /// The tables that exist only in eboot.bin (RR 3.2, FORMATS 5.4).
    var eboot: EbootTables { get }

    /// Number of scripts: the sections of allscr.mrg after the name and label tables
    /// (docs/formats/script.md 2.1-2.4; 549 in the retail data).
    var scriptCount: Int { get }

    /// Script `k`: section k + 3 of allscr.mrg after MZX0 and XOR 0xFF, with its segment offsets
    /// (docs/formats/script.md 2.1-2.2, 3.1; ARCHITECTURE 5.2).
    func script(_ k: Int) -> ScriptImage

    /// Number of lines per language in script_text.mrg (docs/formats/text.md 2; 43,969).
    var textLineCount: Int { get }

    /// Raw text line `id` in `lang`: the bytes of the string blob with their markup, without the
    /// terminating NUL, and with `$` references not expanded (docs/formats/text.md 2, 4, 5.3, 6).
    func textLine(_ lang: Language, _ id: Int) -> ByteSpan

    /// Glyph page `page` of `ft_<lang>.mrg` (docs/formats/fonts.md 3; ARCHITECTURE 4.2, 6.4).
    func fontPage(_ lang: Language, _ page: Int) -> FontPage

    /// Picture `entry` of image archive `archive` (archive ids of
    /// docs/formats/archives_ui_movies.md 2.1: 0 allpac0 .. 5 allpac4), decoded to straight-alpha
    /// RGBA tiles (docs/formats/images.md 2-6). Colour effects (STEC/SNX, compositing 9) are not
    /// applied here.
    func picture(_ archive: Int, _ entry: Int) -> Picture

    /// Audio entry `index` of `bank`, decoded to float PCM with its loop
    /// (docs/formats/audio.md 2-6; ARCHITECTURE 7.2, 7.6).
    func audio(_ bank: AudioBank, _ index: Int) -> AudioClip

    /// Full path of movie table record `index` (docs/formats/archives_ui_movies.md 9.2), after the
    /// caller's language remap (9.3, ARCHITECTURE 7.5). Movies are streamed from the user's folder,
    /// never copied.
    func movie(_ index: Int) -> String

    /// Child `child` of the UI sheet `set` in the language variant `lang`
    /// (docs/formats/archives_ui_movies.md 5.2, 7.3; ARCHITECTURE 9.1).
    func uiSheet(_ set: UiSet, _ lang: Language, _ child: Int) -> Picture

    /// The displayed size of a UI sheet child without decoding its pixels (package K8: the choice
    /// decoration and the message window need sizes only; decoding a sheet for them cost
    /// 20..100 ms on the main thread). The default decodes the sheet.
    func uiSheetSize(_ set: UiSet, _ lang: Language, _ child: Int) -> (width: Int, height: Int)

    /// The size and tile windows of a UI sheet child with empty pixel arrays (package K8): what the
    /// menus need to place a sheet. The default decodes the sheet; ``uiSheet(_:_:_:)`` stays the way
    /// to get pixels.
    func uiSheetLayout(_ set: UiSet, _ lang: Language, _ child: Int) -> Picture

    /// Entry `index` of `image/parts.mrg` decoded to a picture, or nil when the archive has no such
    /// entry (package K6: the boot notices, `parts.mrg` #8 + language). An implementation without
    /// the archive throws `TsukiError.unsupported` (the golden slice); the default does so for
    /// implementations that predate the member.
    func parts(_ index: Int) throws -> Picture?
}

public extension GameData {
    /// The four languages of the verified build (an implementation that predates the member, the
    /// golden slice).
    var availableLanguages: [Language] { [.ja, .en, .zc, .zt] }

    /// Decodes the sheet for its size (package K8).
    func uiSheetSize(_ set: UiSet, _ lang: Language, _ child: Int) -> (width: Int, height: Int) {
        let picture = uiSheet(set, lang, child)
        return (picture.width, picture.height)
    }

    /// Decodes the sheet for its layout (package K8).
    func uiSheetLayout(_ set: UiSet, _ lang: Language, _ child: Int) -> Picture {
        uiSheet(set, lang, child)
    }

    /// An implementation without `parts.mrg` does not serve parts (the golden slice).
    func parts(_ index: Int) throws -> Picture? {
        throw TsukiError.unsupported("this GameData does not serve parts.mrg")
    }
}
