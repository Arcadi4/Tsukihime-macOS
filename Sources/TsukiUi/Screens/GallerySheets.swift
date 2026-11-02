// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Ported from knife (https://github.com/AuroraWright/knife) by AuroraWright: docs/formats/archives_ui_movies.md 7.3
import Foundation
import TsukiCore
import TsukiEngine

/// The UI sheets of the gallery sets by PS4 child.
public enum GallerySheets {
    // ---- GALLERY_PARTS_COMMON (identical in every language: the mode names are English everywhere)

    /// 304 x 56: the cursor line under the active mode button (`gallerycursor_line`).
    public static let menuLine = UiSheet(.galleryPartsCommon, 0)
    public static let MenuLine = menuLine

    /// 800 x 632: the six mode buttons in three columns (normal, hover, active) at x 8 + 264 c, rows y 8 + 104 k, cells 256 x 96 (`gallerymenu_btn`).
    public static let menuButtons = UiSheet(.galleryPartsCommon, 1)
    public static let MenuButtons = menuButtons

    /// 312 x 1080: the window on the left (`gallerymenu_window`).
    public static let menuWindow = UiSheet(.galleryPartsCommon, 2)
    public static let MenuWindow = menuWindow

    /// 528 x 240: the cursor light (`systemcursor_light`).
    public static let menuLight = UiSheet(.galleryPartsCommon, 3)
    public static let MenuLight = menuLight

    /// 1920 x 16: the underline.
    public static let underline = UiSheet(.galleryPartsCommon, 4)
    public static let Underline = underline

    /// 1560 x 1080: the panel background (`config_innerbg`).
    public static let panel = UiSheet(.galleryPartsCommon, 5)
    public static let Panel = panel

    // ---- GALLERY_PARTS_CG, CG_TH

    /// 520 x 160: the cursor frame (cell 8, 8, 248, 144) and its glow (264, 8, 248, 144) (`cg_cursor`).
    public static let cgCursor = UiSheet(.galleryPartsCg, 0)
    public static let CgCursor = cgCursor

    /// 720 x 100: the title banner (`cg_title`); the PS4 has it in English only.
    public static let cgTitle = UiSheet(.galleryPartsCg, 1)
    public static let CgTitle = cgTitle

    /// The thumbnail of a CG: child `child` of GALLERY_PARTS_CG_TH (231 x 130, or four such frames stacked).
    public static func cgThumb(_ child: Int) -> UiSheet {
        UiSheet(.galleryPartsCgTh, child)
    }
    public static func CgThumb(_ child: Int) -> UiSheet { cgThumb(child) }

    // ---- GALLERY_PARTS_MUSIC

    /// 926 x 16: the line under a list row (`music_bgline`).
    public static let musicLine = UiSheet(.galleryPartsMusic, 0)
    public static let MusicLine = musicLine

    /// 448 x 896: the player panel with TIME and VOLUME (`music_btnbg`).
    public static let musicPanel = UiSheet(.galleryPartsMusic, 1)
    public static let MusicPanel = musicPanel

    /// 584 x 272: the player buttons, cells 88 x 80 at x 8 + 96 k and y 8 (normal), 96 (hover), 184 (active) (`music_controlbtn`).
    public static let musicButtons = UiSheet(.galleryPartsMusic, 2)
    public static let MusicButtons = musicButtons

    /// 400 x 24: the time and volume slider tracks (`music_slider`).
    public static let musicSlider = UiSheet(.galleryPartsMusic, 3)
    public static let MusicSlider = musicSlider

    /// 960 x 1736: the list panel behind the rows (`music_soundbg`).
    public static let musicList = UiSheet(.galleryPartsMusic, 4)
    public static let MusicList = musicList

    /// 248 x 88: the slider knob, cells 72 x 72 at (8, 8) and its glow at (168, 8) (`music_soundbtn`).
    public static let musicKnob = UiSheet(.galleryPartsMusic, 5)
    public static let MusicKnob = musicKnob

    /// 720 x 100: the title banner (`music_title`); English only.
    public static let musicTitle = UiSheet(.galleryPartsMusic, 6)
    public static let MusicTitle = musicTitle

    // ---- GALLERY_PARTS_MOVIE

    /// 776 x 464: the three movie cards in three states (`movie_cur`).
    public static let movieCards = UiSheet(.galleryPartsMovie, 0)
    public static let MovieCards = movieCards

    /// The title banner (`movie_title`, 720 x 80, 720 x 100 in English).
    public static let movieTitle = UiSheet(.galleryPartsMovie, 1)
    public static let MovieTitle = movieTitle

    // ---- GALLERY_PARTS_ENDING

    /// 1472 x 584: the bad end plates, locked (rows y 8 + 96 r) and reached (y 296 + 96 r), 180 x 88 at x 8 + 180 c (`ending_badend`).
    public static let endingPlates = UiSheet(.galleryPartsEnding, 0)
    public static let EndingPlates = endingPlates

    /// 296 x 104: the play button on a plate, cells 88 x 88 at x 8 and 104 (hover) (`ending_badendbtn`).
    public static let endingPlateButtons = UiSheet(.galleryPartsEnding, 1)
    public static let EndingPlateButtons = endingPlateButtons

    /// 368 x 128: the large play button, cells 112 x 112 at x 8 and 128 (hover) (`ending_btn`).
    public static let endingButtons = UiSheet(.galleryPartsEnding, 2)
    public static let EndingButtons = endingButtons

    /// 432 x 544: the card of ending `e` (0 Moon Princess, 1 Midnight Rainbow, 2 Cloudless Blue; `ending_icon_*`).
    public static func endingCard(_ e: Int) -> UiSheet {
        UiSheet(.galleryPartsEnding, 3 + min(max(e, 0), 2))
    }
    public static func EndingCard(_ e: Int) -> UiSheet { endingCard(e) }

    /// 432 x 544: the card of an ending not reached (`ending_icon_non`).
    public static let endingCardLocked = UiSheet(.galleryPartsEnding, 6)
    public static let EndingCardLocked = endingCardLocked

    /// The title banner (`ending_title`, 720 x 80 / 100).
    public static let endingTitle = UiSheet(.galleryPartsEnding, 7)
    public static let EndingTitle = endingTitle

    // ---- GALLERY_PARTS_FC, FC_TH

    /// 1920 x 1080: the chart's background (`flow_bg`).
    public static let chartBackground = UiSheet(.galleryPartsFc, 0)
    public static let ChartBackground = chartBackground

    /// 232 x 80: the node cursor (cell 8, 8, 104, 64) and its glow (120, 8) (`flow_cur`).
    public static let chartCursor = UiSheet(.galleryPartsFc, 1)
    public static let ChartCursor = chartCursor

    /// 144 x 32: the "Current Scene" tag (`flow_info`).
    public static let chartTag = UiSheet(.galleryPartsFc, 2)
    public static let ChartTag = chartTag

    /// 488 x 496: the card of the selected scene (`flow_infobase`).
    public static let chartCard = UiSheet(.galleryPartsFc, 3)
    public static let ChartCard = chartCard

    /// The preview picture of a scene: child `child` of GALLERY_PARTS_FC_TH (430 x 243, or four such bands stacked).
    public static func chartPreview(_ child: Int) -> UiSheet {
        UiSheet(.galleryPartsFcTh, child)
    }
    public static func ChartPreview(_ child: Int) -> UiSheet { chartPreview(child) }

    /// The sheet a `ChartSheet` piece is cut from.
    public static func of(_ sheet: ChartSheet) -> UiSheet {
        switch sheet {
        case .bandMiddle: return UiSheet(.galleryPartsFc, 8)
        case .bandUnder: return UiSheet(.galleryPartsFc, 9)
        case .bandUpper: return UiSheet(.galleryPartsFc, 10)
        case .lineGrey: return UiSheet(.galleryPartsFc, 4)
        case .lineLit: return UiSheet(.galleryPartsFc, 5)
        case .mosaic: return UiSheet(.galleryPartsFc, 7)
        case .nodeFrame: return UiSheet(.galleryPartsFc, 11)
        default: return UiSheet(.galleryPartsFc, 6)
        }
    }
    public static func Of(_ sheet: ChartSheet) -> UiSheet { of(sheet) }

    /// True when the title banner of `mode` exists in `language`.
    public static func hasTitle(_ mode: GalleryMode, _ language: Language) -> Bool {
        switch mode {
        case .cg, .music: return language == .en
        default: return true
        }
    }
    public static func HasTitle(_ mode: GalleryMode, _ language: Language) -> Bool {
        hasTitle(mode, language)
    }

    /// The banner sheet of `mode`.
    public static func titleOf(_ mode: GalleryMode) -> UiSheet {
        switch mode {
        case .cg: return cgTitle
        case .music: return musicTitle
        case .movies: return movieTitle
        default: return endingTitle
        }
    }
    public static func TitleOf(_ mode: GalleryMode) -> UiSheet { titleOf(mode) }
}

/// The modes of the gallery (the order of its six buttons; the Flowchart is a screen of its own).
public enum GalleryMode: Int, Sendable {
    case cg = 0
    case music = 1
    case flowchart = 2
    case movies = 3
    case endings = 4
}

/// What the gallery remembers between visits.
public final class GalleryMemory {
    public var mode: Int = -1
    public var Mode: Int { get { mode } set { mode = newValue } }

    public var node: Int = -1
    public var Node: Int { get { node } set { node = newValue } }

    public var previous: Int = -1
    public var Previous: Int { get { previous } set { previous = newValue } }

    public init() {}
}
