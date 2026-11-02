import Foundation
import TsukiEngine

/// A sheet of the UI: child `child` of set `set` in the current language (docs/formats/archives_ui_movies.md 5.2).
public struct UiSheet: Hashable, Sendable {
    public var set: UiSet
    public var child: Int

    public var `Set`: UiSet { get { set } }
    public var Child: Int { child }

    public init(set: UiSet, child: Int) {
        self.set = set
        self.child = child
    }

    public init(_ set: UiSet, _ child: Int) {
        self.set = set
        self.child = child
    }
}

/// The UI sheets the menus draw, by PS4 set and child (docs/formats/archives_ui_movies.md 5.2, 5.3 and the previews in samples/ui_misc/previews). The Switch
/// build of knife keeps the same pictures as separate textures (`menu_btn_ja`, `save_win`, ...); the names in the comments are knife's.
public enum UiSheets {
    // ---- TITLE_PARTS (registration table 0x873660: children 9+T, 0..8, 14 -> texture slots 125..136)

    /// 968 x 472: the five menu items in three columns (normal, cursor, pressed) at x 24 + 312 c, rows y 24 + 88 k (knife `titlemenu`).
    public static let titleMenu = UiSheet(.titleParts, 0)
    public static let TitleMenu = titleMenu

    /// The logo: 560 x 648 (ja) or 1850 x 440 (en) (`title_titlelog`).
    public static let titleLogo = UiSheet(.titleParts, 1)
    public static let TitleLogo = titleLogo

    /// 360 x 48: the cursor underline bar, cell (24, 24)-(360, 32) (system_flow.md 4.5 row 6).
    public static let titleUnderline = UiSheet(.titleParts, 2)
    public static let TitleUnderline = titleUnderline

    /// 184 x 64: (C)TYPE-MOON (`titlemenu_(c)type-moon`).
    public static let titleCopyright = UiSheet(.titleParts, 3)
    public static let TitleCopyright = titleCopyright

    /// 488 x 256: the moon glow (`titlemenu_lumi`).
    public static let titleGlow = UiSheet(.titleParts, 4)
    public static let TitleGlow = titleGlow

    /// The three logo shards (33 x 44, 32 x 55, 29 x 45); knife keeps them in one atlas (`logoparticle_all`).
    public static func titleShard(_ kind: Int) -> UiSheet {
        UiSheet(.titleParts, 5 + min(max(kind, 0), 2))
    }
    public static func TitleShard(_ kind: Int) -> UiSheet { titleShard(kind) }

    /// 2670 x 1266: the PRESS ANY BUTTON background layer (`title_bg0`).
    public static let titleBg0 = UiSheet(.titleParts, 9)
    public static let TitleBg0 = titleBg0

    /// The still behind the menu for title stage T (1..4): 1920 x 1080 children 10..13 (`title_bg1..4`).
    public static func titleStill(_ t: Int) -> UiSheet {
        UiSheet(.titleParts, 9 + min(max(t, 1), 4))
    }
    public static func TitleStill(_ t: Int) -> UiSheet { titleStill(t) }

    /// 472 x 88: PRESS ANY BUTTON (`press_start`).
    public static let pressAnyButton = UiSheet(.titleParts, 14)
    public static let PressAnyButton = pressAnyButton

    // ---- MENU_PARTS (tables 0x7A6B20 and 0x7A67F0: children 0..17 -> texture slots 320..337)

    /// 752 x 552: Save, Load, Config, FlowChart, Title in three columns (`menu_btn_ja`).
    public static let menuButtons = UiSheet(.menuParts, 0)
    public static let MenuButtons = menuButtons

    /// 312 x 1080: the window on the left (`menu_window`).
    public static let menuWindow = UiSheet(.menuParts, 1)
    public static let MenuWindow = menuWindow

    /// 3664 x 992 (English): the chapter titles (`system_phasetitle`).
    public static let phaseTitles = UiSheet(.menuParts, 2)
    public static let PhaseTitles = phaseTitles

    /// 1168 x 80: the scene title band (`system_scenebg`).
    public static let sceneBand = UiSheet(.menuParts, 3)
    public static let SceneBand = sceneBand

    /// 1920 x 392: the title band (`system_titlebg`).
    public static let titleBand = UiSheet(.menuParts, 4)
    public static let TitleBand = titleBand

    /// 528 x 240: the cursor light (`systemcursor_light`).
    public static let cursorLight = UiSheet(.menuParts, 5)
    public static let CursorLight = cursorLight

    /// 224 x 56: the cursor line (`systemcursor_line`).
    public static let cursorLine = UiSheet(.menuParts, 6)
    public static let CursorLine = cursorLine

    /// 1920 x 16: the underline (`underline`).
    public static let underline = UiSheet(.menuParts, 7)
    public static let Underline = underline

    /// 82 x 82: a sparkle (`kirakira`).
    public static let spark = UiSheet(.menuParts, 8)
    public static let Spark = spark

    /// 1920 x 1080: the backdrop (`menuBG01`).
    public static let backdrop = UiSheet(.menuParts, 9)
    public static let Backdrop = backdrop

    /// Strip k of the backdrop's lower group (`menuBG04_k`, children 10..13: 1920 x 396, 321, 255, 165).
    public static func stripLow(_ k: Int) -> UiSheet {
        UiSheet(.menuParts, 10 + k)
    }
    public static func StripLow(_ k: Int) -> UiSheet { stripLow(k) }

    /// Strip k of the backdrop's upper group (`menuBG05_k`, children 14..17: 1920 x 311, 1700 x 236, 1920 x 170, 1497 x 80).
    public static func stripHigh(_ k: Int) -> UiSheet {
        UiSheet(.menuParts, 14 + k)
    }
    public static func StripHigh(_ k: Int) -> UiSheet { stripHigh(k) }

    // ---- SAVE_PARTS (table 0x7A8300: children 8, 0..7, 9 -> texture slots 338..347)

    /// 192 x 32: the AUTO SAVE tag (`saveauto`).
    public static let saveAuto = UiSheet(.saveParts, 0)
    public static let SaveAuto = saveAuto

    /// 376 x 64: the date digits 0..9 and a separator, cells 24 x 32 at x 16 + 32 k, y 16 (`savedate_number`).
    public static let saveDateDigits = UiSheet(.saveParts, 1)
    public static let SaveDateDigits = saveDateDigits

    /// 472 x 712: the Arcueid route card (`saveinfobg_arc`).
    public static let saveInfoArc = UiSheet(.saveParts, 2)
    public static let SaveInfoArc = saveInfoArc

    /// 472 x 712: the Ciel route card (`saveinfobg_ciel`).
    public static let saveInfoCiel = UiSheet(.saveParts, 3)
    public static let SaveInfoCiel = saveInfoCiel

    /// 472 x 712: the neutral card (`saveinfobg_unknown`).
    public static let saveInfoUnknown = UiSheet(.saveParts, 4)
    public static let SaveInfoUnknown = saveInfoUnknown

    /// 64 x 24: the SCENE tag.
    public static let saveSceneTag = UiSheet(.saveParts, 5)
    public static let SaveSceneTag = saveSceneTag

    /// 376 x 64: the time digits and the colon (`savetime_number`).
    public static let saveTimeDigits = UiSheet(.saveParts, 6)
    public static let SaveTimeDigits = saveTimeDigits

    /// 2176 x 496 (English): the chapter titles of the list (`savetitle`).
    public static let saveTitles = UiSheet(.saveParts, 7)
    public static let SaveTitles = saveTitles

    /// 1024 x 640: the slot frame, white at (32, 32) and blue at (31, 336) (`save_win`).
    public static let saveFrame = UiSheet(.saveParts, 8)
    public static let SaveFrame = saveFrame

    /// 1560 x 1080: the panel background (`config_innerbg`).
    public static let savePanel = UiSheet(.saveParts, 9)
    public static let SavePanel = savePanel

    // ---- CONF_PARTS (table 0x66C9A0: children 0..19 -> texture slots 361..380)

    /// 608 x 272: the tab labels, 3 rows x 3 columns (`btn_base0`).
    public static let confTabs = UiSheet(.confParts, 0)
    public static let ConfTabs = confTabs

    /// 352 x 312: the Recommended Settings button (`btn_default`).
    public static let confDefault = UiSheet(.confParts, 1)
    public static let ConfDefault = confDefault

    /// 1560 x 1080: the panel background (`config_innerbg`).
    public static let confPanel = UiSheet(.confParts, 2)
    public static let ConfPanel = confPanel

    /// 1416 x 72: the header bar (`tab_bg`).
    public static let confHeader = UiSheet(.confParts, 3)
    public static let ConfHeader = confHeader

    /// The radio buttons: ON / OFF, All Text / Read Only, Fade-in, Fade-out (`btn_base1`).
    public static let confRadio = UiSheet(.confParts, 4)
    public static let ConfRadio = confRadio

    /// The two check boxes (`btn_base2`).
    public static let confToggle = UiSheet(.confParts, 5)
    public static let ConfToggle = confToggle

    /// 936 x 504: the slider knob and its glow (`conf_sbtn`).
    public static let confKnob = UiSheet(.confParts, 6)
    public static let ConfKnob = confKnob

    /// 168 x 137: the - and + buttons in three states (`conf_stxt01`).
    public static let confStep = UiSheet(.confParts, 7)
    public static let ConfStep = confStep

    /// 1432 x 224: the page frame.
    public static let confFrame = UiSheet(.confParts, 8)
    public static let ConfFrame = confFrame

    /// 1432 x 1602: the text settings page (`system_bg`).
    public static let confSystemPage = UiSheet(.confParts, 9)
    public static let ConfSystemPage = confSystemPage

    /// 504 x 128: the Mute button in three states (`btn_mute`).
    public static let confMute = UiSheet(.confParts, 10)
    public static let ConfMute = confMute

    /// 408 x 120: the Test button in three states (`btn_test`).
    public static let confTest = UiSheet(.confParts, 11)
    public static let ConfTest = confTest

    /// 688 x 1008: the character faces (`conf_faceicon`).
    public static let confFaces = UiSheet(.confParts, 12)
    public static let ConfFaces = confFaces

    /// 504 x 496 (ja) / 624 (en): the character names (`conf_name`).
    public static let confNames = UiSheet(.confParts, 13)
    public static let ConfNames = confNames

    /// 1432 x 328: the sound page header (`sound_bg`).
    public static let confSoundPage = UiSheet(.confParts, 14)
    public static let ConfSoundPage = confSoundPage

    /// 1432 x 2872: the voice page (`voice_bg`).
    public static let confVoicePage = UiSheet(.confParts, 15)
    public static let ConfVoicePage = confVoicePage

    /// 1416 x 1528: the controls page with CIRCLE as decide (`conf_manual0`).
    public static let confControlsPad = UiSheet(.confParts, 16)
    public static let ConfControlsPad = confControlsPad

    /// 1416 x 1528: the same page with CROSS as decide.
    public static let confControlsPadCross = UiSheet(.confParts, 17)
    public static let ConfControlsPadCross = confControlsPadCross

    /// 320 x 32: the digits 0..9 of the config values (`config_number`).
    public static let confDigits = UiSheet(.confParts, 18)
    public static let ConfDigits = confDigits

    /// 760 x 344: the four language buttons in three states.
    public static let confLanguage = UiSheet(.confParts, 19)
    public static let ConfLanguage = confLanguage

    // ---- DISP_PARTS (table 0x780C90)

    /// 160 x 160: the glow of the autosave icon.
    public static let dispGlow = UiSheet(.dispParts, 1)
    public static let DispGlow = dispGlow

    /// 160 x 160: the spinner of the autosave icon.
    public static let dispSpinner = UiSheet(.dispParts, 2)
    public static let DispSpinner = dispSpinner

    /// 128 x 56: the Saving... caption.
    public static let dispSaving = UiSheet(.dispParts, 3)
    public static let DispSaving = dispSaving

    /// 432 x 264: the mode banners (`popup_ja`).
    public static let banner = UiSheet(.dispParts, 10)
    public static let Banner = banner

    /// 16 x 888: the scroll bar track (`scroll_bar`).
    public static let scrollBar = UiSheet(.dispParts, 14)
    public static let ScrollBar = scrollBar

    /// 208 x 336: the scroll slider, cell (48, 24)-(80, 312) (`scroll_slider`).
    public static let scrollSlider = UiSheet(.dispParts, 15)
    public static let ScrollSlider = scrollSlider

    /// 384 x 256: the button icons of the guide line (`help_key`).
    public static let guideIcons = UiSheet(.dispParts, 16)
    public static let GuideIcons = guideIcons

    /// 512 x 256: the words of the guide line (`help_txt`).
    public static let guideWords = UiSheet(.dispParts, 17)
    public static let GuideWords = guideWords

    /// 64 x 64: the pointer arrow.
    public static let pointer = UiSheet(.dispParts, 18)
    public static let Pointer = pointer

    /// 448 x 264: the dialog buttons, Yes and No in a normal and a glow cell (`dialog_btn_ja`).
    public static let dialogButtons = UiSheet(.dispParts, 19)
    public static let DialogButtons = dialogButtons

    /// 824 x 416: the dialog window (`dialog_win`).
    public static let dialogWindow = UiSheet(.dispParts, 20)
    public static let DialogWindow = dialogWindow

    /// 1920 x 1080: the dialog backdrop (`dialog_BG`).
    public static let dialogBackdrop = UiSheet(.dispParts, 21)
    public static let DialogBackdrop = dialogBackdrop

    // ---- MODEPNL_PARTS (table 0x7A7680: children 0..1 -> texture slots 382, 383)

    /// 1920 x 96: the mode panel bar.
    public static let modeBar = UiSheet(.modePnlParts, 0)
    public static let ModeBar = modeBar

    /// 1864 x 296: the mode panel buttons (eight columns of five states).
    public static let modeButtons = UiSheet(.modePnlParts, 1)
    public static let ModeButtons = modeButtons
}
