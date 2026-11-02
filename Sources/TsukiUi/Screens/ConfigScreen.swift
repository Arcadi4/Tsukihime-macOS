// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Ported from knife (https://github.com/AuroraWright/knife) by AuroraWright: knife/src/ui.rs (Ctl, conf_layout_at, conf_rect, conf_slider, conf_change, conf_nav, draw_config, en_radio_cell, en_toggle_cell, refresh_voice_rows)
import Foundation
import TsukiCore
import TsukiEngine

/// What a config control is.
public enum CtlKind: Int, Sendable {
    case tab
    case `default`
    case minus
    case plus
    case slider
    case toggle
    case radio
    case mute
    case test
    case lang
    case prompt
    case display
    case windowSize
    case screenshotNotice
    case copyText
    case textHooker
    case textWebSocket
    case opacity
    case backgroundMute
}

/// The port's rows at the bottom of the System tab.
public enum PortRow: Int, Sendable {
    case displayMode
    case windowSize
    case screenshotNotice
    case copyText
    case textHooker
    case textWebSocket
    case opacity
}

/// A control of the config screen: its kind, an index and (for radios) whether it is the first button of its pair.
public struct Ctl: Hashable, Sendable {
    public var kind: CtlKind
    public var index: Int
    public var first: Bool

    public var Kind: CtlKind { kind }
    public var Index: Int { index }
    public var First: Bool { first }

    public init(kind: CtlKind, index: Int = 0, first: Bool = false) {
        self.kind = kind
        self.index = index
        self.first = first
    }

    public init(_ kind: CtlKind, _ index: Int = 0, _ first: Bool = false) {
        self.kind = kind
        self.index = index
        self.first = first
    }
}

/// The config screen.
public final class ConfigScreen: UiScreen, ISubMenu {
    private static let scrollFrames: Float = 12.0
    private static let radioDy: Float = 6.637
    private static let pageTop: Float = 176.0
    private static let pillX: Float = 728.0
    private static let pillGap: Float = 12.0
    private static let viewRect = RectF(407.0, 165.0, 1402.0, 858.0)

    private static let pageY: Float = 68.03 * UiMetrics.unitY
    private static let displaySplitRow: Float = 1500.0
    private static let displayFillerTop: Float = 1400.0
    private static let displayRuleRow: Float = 1310.0
    private static let displayRuleDy: Float = 78.0
    private static let displayRowDy: Float = 96.0
    private static let displayRowPitch: Float = 56.0
    private static let bandBottom: Float = 8.0
    private static let displayLabelX: Float = 431.0
    private static let dimmedSizeRow: Float = 0.5

    private static let soundSplitRow: Float = 300.0
    private static let soundFillerTop: Float = 272.0
    private static let soundRowDy: Float = 15.0
    private static let twoLineHeadingScale: Double = 0.36
    public static let soundBandHeight: Float = 64.0
    public static let SoundBandHeight: Float = soundBandHeight

    private static let opacityTrack: Float = 400.0
    private static let opacityKnobWidth: Float = 22.0
    private static let opacityStep: Int = 5

    private var _target: [Float] = [0, 0, 0]
    private var _preview: [[Float]] = [[0, 0, 0], [0, 0, 0]]
    private var _voiceRows: [(row: Int, face: Int, name: Int)] = []
    private var _tab: Int = 0
    private var _nextTab: Int = -1
    private var _content: Float = 1.0
    private var _scroll: Float = 0
    private var _from: Float = 0
    private var _tween: Float = scrollFrames
    private var _cursor: Int = -1
    private var _bar: Int = 0
    private var _hold: Int = -1
    private let _scrollBar = UiScrollBar()
    private var _sampleLanguage: Language?
    private var _sampleScale: Float = 1.0
    private var _dragCtl: Ctl?
    private var _dragOffset: Float = 0
    private var _langCool: Int = 0
    private var _dirty: Bool = false
    private var _remember: [(row: Int, col: Int)?] = [(0, 0), (0, 0), nil]

    public override init() {
        super.init()
        self._side = SideFocus(self, 2)
        startHidden()
    }

    public var tab: Int { 2 }
    public var Tab: Int { tab }

    private var _side: SideFocus!
    public var side: SideFocus { _side }
    public var Side: SideFocus { side }

    public var currentTab: Int { _tab }
    public var CurrentTab: Int { currentTab }

    public var scroll: Float { _scroll }
    public var Scroll: Float { scroll }

    var bar: UiScrollBar { _scrollBar }

    public var cursor: Int { _cursor }
    public var Cursor: Int { cursor }

    public var voiceRows: [(row: Int, face: Int, name: Int)] { _voiceRows }
    public var VoiceRows: [(row: Int, face: Int, name: Int)] { voiceRows }

    public override var fadeInStep: Float { 0.024 }
    public override var FadeInStep: Float { fadeInStep }

    public override var fadeOutStep: Float { 0.048 }
    public override var FadeOutStep: Float { fadeOutStep }

    private var cfg: ConfigBlock { ctx.services.config }
    private var english: Bool { ctx.language == .en }

    // MARK: - Layout

    public func layoutAt(_ scrollPos: Float) -> [(ctl: Ctl, x: Float, y: Float)] {
        var v: [(ctl: Ctl, x: Float, y: Float)] = [
            (Ctl(.tab, 0), 408.0, 96.0),
            (Ctl(.tab, 1), 656.0, 96.0),
            (Ctl(.tab, 2), 888.0, 96.0),
            (Ctl(.default), 1536.0, 96.0)
        ]
        let pages = ctx.assets.tables.configPages
        func u(_ x: Float, _ y: Float) -> (x: Float, y: Float) {
            (x * 3.0, (y * UiMetrics.unitY) - scrollPos)
        }

        if _tab == 0 && !pages.isEmpty {
            let page = pages[0]
            var pair = 0
            var lang = 0
            for r in 0..<page.rows.count {
                let row = page.rows[r]
                for c in row.controls {
                    switch c.kind {
                    case 3:
                        let pos = u(c.x, c.y)
                        v.append((Ctl(.minus, r), pos.x, pos.y))
                    case 4:
                        let pos = u(c.x, c.y)
                        v.append((Ctl(.slider, r), pos.x, pos.y))
                    case 5:
                        let pos = u(c.x, c.y)
                        v.append((Ctl(.plus, r), pos.x, pos.y))
                    case 2:
                        let pos = u(c.x, c.y)
                        v.append((Ctl(.toggle, r < 2 ? r : 2), pos.x, pos.y))
                    case 6...9:
                        pair = c.kind - 6
                        let pos = u(c.x, c.y + Self.radioDy)
                        v.append((Ctl(.radio, pair, isFirstOfPair(page, r)), pos.x, pos.y))
                    case 10:
                        if languageAvailable(lang) {
                            let pos = u(c.x, c.y)
                            v.append((Ctl(.lang, lang), pos.x, pos.y))
                        }
                        lang += 1
                    default:
                        break
                    }
                }
            }

            let top = Self.pageY + Self.displaySplitRow - scrollPos
            let band = systemBandRows()
            for row in 0..<band.count {
                let y = top + Self.displayRowDy + (Self.displayRowPitch * Float(row))
                var x = Self.pillX
                switch band[row] {
                case .displayMode:
                    for i in 0..<2 {
                        v.append((Ctl(.display, i), x, y))
                        x += UiPrompts.displayPillWidth(i) + Self.pillGap
                    }
                case .windowSize:
                    if let d = display {
                        for i in 0..<d.sizeChoices.count {
                            v.append((Ctl(.windowSize, i), x, y))
                            x += UiPrompts.sizePillWidth + Self.pillGap
                        }
                    }
                case .screenshotNotice, .copyText, .textHooker, .textWebSocket:
                    for i in 0..<2 {
                        v.append((Ctl(Self.switchKind(band[row]), i), x, y))
                        x += UiPrompts.switchPillWidth + Self.pillGap
                    }
                default:
                    v.append((Ctl(.opacity), x, y))
                }
            }
        } else if _tab == 1 && pages.count > 1 {
            let page = pages[1]
            let band = soundBand
            for r in 0..<min(7, page.rows.count) {
                let dy: Float = r >= 3 ? band : 0.0
                for c in page.rows[r].controls {
                    let pos = u(c.x, c.y)
                    switch c.kind {
                    case 3:
                        v.append((Ctl(.minus, r), pos.x, pos.y + dy))
                    case 4:
                        v.append((Ctl(.slider, r), pos.x, pos.y + dy))
                    case 5:
                        v.append((Ctl(.plus, r), pos.x, pos.y + dy))
                    case 2:
                        v.append((Ctl(.mute, r), pos.x, pos.y + dy))
                    case 1:
                        v.append((Ctl(.test, 0), pos.x, pos.y + dy))
                    case 6, 7:
                        let posR = u(c.x, c.y + Self.radioDy)
                        v.append((Ctl(.radio, c.kind - 2, isFirstOfPair(page, r)), posR.x, posR.y + dy))
                    default:
                        break
                    }
                }
            }

            if port != nil {
                var x = Self.pillX
                let y = Self.pageY + Self.soundSplitRow - scrollPos + Self.soundRowDy
                for i in 0..<2 {
                    v.append((Ctl(.backgroundMute, i), x, y))
                    x += UiPrompts.switchPillWidth + Self.pillGap
                }
            }

            for n in 0..<_voiceRows.count {
                let k = _voiceRows[n].row
                let y = (Float(n) * 50.607) + 370.01
                let p1 = u(245.0, y)
                v.append((Ctl(.minus, 3 + k), p1.x, p1.y + band))
                let p2 = u(120.67, y - 44.8)
                v.append((Ctl(.slider, 3 + k), p2.x, p2.y + band))
                let p3 = u(452.0, y)
                v.append((Ctl(.plus, 3 + k), p3.x, p3.y + band))
                let p4 = u(476.33, y - 4.9778)
                v.append((Ctl(.mute, 3 + k), p4.x, p4.y + band))
                let p5 = u(560.33, y - 3.7333)
                v.append((Ctl(.test, 1 + k), p5.x, p5.y + band))
            }
        } else if _tab == 2 {
            var x = Self.pillX
            for i in 0..<4 {
                v.append((Ctl(.prompt, i), x, Self.pageTop + 6.0 - scrollPos))
                x += UiPrompts.pillWidth(i) + Self.pillGap
            }
        }

        return v
    }

    public func LayoutAt(_ scrollPos: Float) -> [(ctl: Ctl, x: Float, y: Float)] {
        layoutAt(scrollPos)
    }

    private var display: IUiDisplaySettings? { ctx.services.display }
    private var port: IUiPortSettings? { ctx.services.port }

    public var hasDisplayRows: Bool { display != nil }
    public var HasDisplayRows: Bool { hasDisplayRows }

    public var hasPortRows: Bool { port != nil }
    public var HasPortRows: Bool { hasPortRows }

    public func systemBandRows() -> [PortRow] {
        var rows: [PortRow] = []
        if let d = display {
            rows.append(.displayMode)
            if !d.sizeChoices.isEmpty {
                rows.append(.windowSize)
            }
        }
        if port != nil {
            rows.append(.screenshotNotice)
            rows.append(.copyText)
            rows.append(.textHooker)
            rows.append(.textWebSocket)
        }
        rows.append(.opacity)
        return rows
    }
    public func SystemBandRows() -> [PortRow] {
        systemBandRows()
    }

    public static func switchKind(_ row: PortRow) -> CtlKind {
        switch row {
        case .screenshotNotice: return .screenshotNotice
        case .copyText: return .copyText
        case .textHooker: return .textHooker
        case .textWebSocket: return .textWebSocket
        default: return .screenshotNotice
        }
    }
    public static func SwitchKind(_ row: PortRow) -> CtlKind {
        switchKind(row)
    }

    public static func isSwitch(_ kind: CtlKind) -> Bool {
        kind == .screenshotNotice || kind == .copyText || kind == .textHooker || kind == .textWebSocket || kind == .backgroundMute
    }
    public static func IsSwitch(_ kind: CtlKind) -> Bool {
        isSwitch(kind)
    }

    public static func bandFor(_ rows: Int) -> Float {
        displayRowDy - displayRowPitch + (displayRowPitch * Float(rows)) + bandBottom
    }
    public static func BandFor(_ rows: Int) -> Float {
        bandFor(rows)
    }

    private var systemBand: Float {
        Self.bandFor(systemBandRows().count)
    }

    private var soundBand: Float {
        port != nil ? Self.soundBandHeight : 0.0
    }

    public var windowOpacityPercent: Int {
        get { Int(round(Float(cfg.hud10) * 100.0 / 255.0)) }
        set {
            let clampedPct = min(max(newValue, 0), 100)
            cfg.hud10 = UInt16(clamping: Int(round(Float(clampedPct) * 255.0 / 100.0)))
        }
    }
    public var WindowOpacityPercent: Int {
        get { windowOpacityPercent }
        set { windowOpacityPercent = newValue }
    }

    private func isFirstOfPair(_ page: UiConfigPage, _ row: Int) -> Bool {
        guard let firstCtl = page.rows[row].controls.first(where: { $0.kind >= 6 && $0.kind <= 10 }) else {
            return true
        }
        let kind = firstCtl.kind
        return row == 0 || !page.rows[row - 1].controls.contains(where: { $0.kind == kind })
    }

    public var layout: [(ctl: Ctl, x: Float, y: Float)] {
        layoutAt(_scroll)
    }
    public var Layout: [(ctl: Ctl, x: Float, y: Float)] {
        layout
    }

    public func hitRect(_ c: Ctl, _ x: Float, _ y: Float) -> RectF {
        switch c.kind {
        case .tab:
            return RectF(x, y, 192, 80)
        case .default:
            return RectF(x, y, 288, 72)
        case .minus, .plus:
            return RectF(x, y, 80, 40)
        case .slider:
            return RectF(x + 432.0, y + (39.0 * UiMetrics.unitY), 69.0, 24.0 * UiMetrics.unitY)
        case .toggle:
            let cell = toggleCell(c.index, 0)
            return RectF(x, y, Float(cell.width), 72)
        case .radio:
            let cell = radioCell(c.index, c.first, 0)
            return RectF(x, y, Float(cell.width), 48)
        case .lang:
            return RectF(x, y + (7.0 * UiMetrics.unitY), 168, 19.0 * UiMetrics.unitY)
        case .prompt:
            return RectF(x, y, UiPrompts.pillWidth(c.index), UiPrompts.pillHeight)
        case .display:
            return RectF(x, y, UiPrompts.displayPillWidth(c.index), UiPrompts.pillHeight)
        case .windowSize:
            return RectF(x, y, UiPrompts.sizePillWidth, UiPrompts.pillHeight)
        case .screenshotNotice, .copyText, .textHooker, .textWebSocket, .backgroundMute:
            return RectF(x, y, UiPrompts.switchPillWidth, UiPrompts.pillHeight)
        case .opacity:
            return RectF(x - (Self.opacityKnobWidth / 2.0), y, Self.opacityTrack + Self.opacityKnobWidth, UiPrompts.pillHeight)
        case .mute:
            return RectF(x, y, 136, 64)
        case .test:
            return RectF(x, y, 104, 56)
        }
    }
    public func HitRect(_ c: Ctl, _ x: Float, _ y: Float) -> RectF {
        hitRect(c, x, y)
    }

    public func radioCell(_ k: Int, _ first: Bool, _ col: Int) -> SheetCell {
        let c = Float(col)
        let en = english
        func narrow(_ y: Float) -> SheetCell {
            Cell(256.0 * c, y, (256.0 * c) + 240.0, y + 48.0)
        }
        func wide(_ y: Float) -> SheetCell {
            switch col {
            case 0: return Cell(0, y, 441.0, y + 48.0)
            case 1: return Cell(448.0, y, 889.0, y + 48.0)
            default: return Cell(896.0, y, 1337.0, y + 48.0)
            }
        }

        switch (k, first) {
        case (0, true), (4, true), (5, true):
            return Cell(256.0 * c, 16.0, (256.0 * c) + 120.0, 64.0)
        case (0, false), (4, false), (5, false):
            if col == 2 {
                return Cell(512.0, 100.0, 632.0, 148.0)
            }
            return Cell(256.0 * c, 104.0, (256.0 * c) + 120.0, 152.0)
        case (1, true):
            return Cell(256.0 * c, 192.0, (256.0 * c) + 248.0, 240.0)
        case (1, false):
            return Cell(256.0 * c, 280.0, (256.0 * c) + 248.0, 328.0)
        case (2, true):
            if col == 0 {
                return Cell(0, 368.0, en ? 241.0 : 240.0, 416.0)
            }
            return Cell(256.0 * c, 368.0, (256.0 * c) + 248.0, 416.0)
        case (2, false):
            return en ? wide(456.0) : narrow(456.0)
        case (3, true):
            return narrow(544.0)
        default:
            return en ? wide(632.0) : narrow(632.0)
        }
    }
    public func RadioCell(_ k: Int, _ first: Bool, _ col: Int) -> SheetCell {
        radioCell(k, first, col)
    }

    public func toggleCell(_ t: Int, _ col: Int) -> SheetCell {
        let y: Float = t < 2 ? 0.0 : 80.0
        let c = Float(col)
        return english ? Cell(400.0 * c, y, (400.0 * c) + 392.0, y + 72.0) : Cell(8.0 + (304.0 * c), y, 296.0 + (304.0 * c), y + 72.0)
    }
    public func ToggleCell(_ t: Int, _ col: Int) -> SheetCell {
        toggleCell(t, col)
    }

    private func Cell(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float) -> SheetCell {
        SheetCell(x0: Int(x0), y0: Int(y0), x1: Int(x1), y1: Int(y1))
    }

    // MARK: - Values

    public func slider(_ i: Int) -> (value: Float, max: Float, step: Float) {
        let c = cfg
        switch (_tab, i) {
        case (0, 0): return (Float(c.unseenTextSpeed), 250.0, 1.0)
        case (0, 1): return (Float(c.seenTextSpeed), 250.0, 1.0)
        case (0, 2): return (Float(c.autoModePageSpeed), 10000.0, 50.0)
        case (0, _): return (Float(c.autoModeWait), 10000.0, 50.0)
        case (_, 0): return (Float(c.musicVolume), 100.0, 1.0)
        case (_, 1): return (Float(c.sfxVolume), 100.0, 1.0)
        case (_, 2): return (Float(c.systemSeVolume), 100.0, 1.0)
        case (_, let k): return (Float(c.getCharacterVoiceVolume(k - 3)), 100.0, 1.0)
        }
    }
    public func Slider(_ i: Int) -> (value: Float, max: Float, step: Float) {
        slider(i)
    }

    private func setSlider(_ i: Int, _ value: Float) {
        let (_, maxVal, _) = slider(i)
        let v = UInt16(clamping: Int(round(min(max(value, 0.0), maxVal))))
        let c = cfg
        var kind: ConfigChange = .setting
        switch (_tab, i) {
        case (0, 0):
            c.unseenTextSpeed = v
        case (0, 1):
            c.seenTextSpeed = v
        case (0, 2):
            c.autoModePageSpeed = v
        case (0, _):
            c.autoModeWait = v
        case (_, 0):
            c.musicVolume = v
            c.musicVolumeCopy = v
            kind = .volume
        case (_, 1):
            c.sfxVolume = v
            kind = .volume
        case (_, 2):
            c.systemSeVolume = v
            kind = .volume
        default:
            c.setCharacterVoiceVolume(i - 3, v)
            kind = .volume
        }
        ctx.services.configChanged(kind)
        _dirty = true
    }

    public func isOn(_ c: Ctl) -> Bool {
        let config = cfg
        switch c.kind {
        case .toggle:
            switch c.index {
            case 0: return config.pageEndInstantUnseen != 0
            case 1: return config.pageEndInstantSeen != 0
            default: return config.skipConfirm != 0
            }
        case .radio:
            let top: Bool
            switch c.index {
            case 0: top = config.autoSkipCleared != 0
            case 1: top = config.fastForwardReadOnly == 0
            case 2: top = config.textAnimations == 0
            case 3: top = config.seenTextAnimations == 0
            case 4: top = config.playAllVoices != 0
            default: top = config.interruptVoices != 0
            }
            return top == c.first
        case .mute:
            switch c.index {
            case 0: return config.musicMute != 0
            case 1: return config.sfxMute != 0
            case 2: return config.systemSeMute != 0
            default: return ((config.voiceEnableBits >> (c.index - 3)) & 1) == 0
            }
        case .tab:
            return _tab == c.index
        case .lang:
            let w = Int(config.language)
            let current = (w >= 1 && w <= 3) ? w : 0
            return c.index == current
        case .prompt:
            return ctx.services.promptSetting.rawValue == c.index
        case .display:
            return display.map { $0.fullscreen == (c.index == 1) } ?? false
        case .windowSize:
            guard let ds = display, c.index < ds.sizeChoices.count else { return false }
            let choice = ds.sizeChoices[c.index]
            return choice.width == ds.windowSize.width && choice.height == ds.windowSize.height
        case .screenshotNotice:
            return port.map { $0.screenshotNotice == (c.index == 1) } ?? false
        case .copyText:
            return port.map { $0.copyTextToClipboard == (c.index == 1) } ?? false
        case .textHooker:
            return port.map { $0.textHookerOutput == (c.index == 1) } ?? false
        case .textWebSocket:
            return port.map { $0.textWebSocket == (c.index == 1) } ?? false
        case .backgroundMute:
            return port.map { $0.muteInBackground == (c.index == 1) } ?? false
        default:
            return false
        }
    }
    public func IsOn(_ c: Ctl) -> Bool {
        isOn(c)
    }

    private func setRadio(_ k: Int, _ first: Bool) {
        let config = cfg
        var kind: ConfigChange = .setting
        switch k {
        case 0: config.autoSkipCleared = first ? 1 : 0
        case 1: config.fastForwardReadOnly = first ? 0 : 1
        case 2: config.textAnimations = first ? 0 : 1
        case 3: config.seenTextAnimations = first ? 0 : 1
        case 4:
            config.playAllVoices = first ? 100 : 0
            kind = .volume
        default:
            config.interruptVoices = first ? 1 : 0
        }
        ctx.services.configChanged(kind)
        _dirty = true
    }

    // MARK: - Actions

    public func change(_ c: Ctl, _ d: Int, pointerX: Float = Float.nan) {
        let config = cfg
        switch c.kind {
        case .tab:
            switchTab(c.index)
        case .default:
            ctx.sound(.open)
            root?.push(ConfirmDialog(.defaults, { [weak self] yes in
                if yes {
                    self?.resetDefaults()
                }
            }))
        case .minus, .plus, .slider:
            let (v, maxVal, step) = slider(c.index)
            var nv: Float
            if c.kind == .minus {
                nv = v - step
            } else if c.kind == .plus {
                nv = v + step
            } else if d != 0 {
                nv = v + (step * Float(d))
            } else {
                let currentLayout = layout
                if let found = currentLayout.first(where: { $0.ctl == c }) {
                    nv = pointerX.isNaN ? v : trunc(max(0.0, (pointerX - (found.x + 468.0)) / 508.0 * maxVal))
                } else {
                    nv = v
                }
            }
            setSlider(c.index, nv)
        case .toggle:
            ctx.sound(.decide)
            switch c.index {
            case 0: config.pageEndInstantUnseen = config.pageEndInstantUnseen != 0 ? 0 : 1
            case 1: config.pageEndInstantSeen = config.pageEndInstantSeen != 0 ? 0 : 1
            default: config.skipConfirm = config.skipConfirm != 0 ? 0 : 1
            }
            ctx.services.configChanged(.setting)
            _dirty = true
        case .radio:
            ctx.sound(.decide)
            setRadio(c.index, c.first)
        case .mute:
            ctx.sound(.decide)
            switch c.index {
            case 0: config.musicMute = config.musicMute != 0 ? 0 : 1
            case 1: config.sfxMute = config.sfxMute != 0 ? 0 : 1
            case 2: config.systemSeMute = config.systemSeMute != 0 ? 0 : 1
            default: config.voiceEnableBits ^= 1 << (c.index - 3)
            }
            ctx.services.configChanged(.volume)
            _dirty = true
        case .test:
            if c.index == 0 {
                ctx.services.playTestSe()
            } else {
                ctx.services.playTestVoice(c.index - 1)
            }
        case .prompt:
            ctx.sound(.decide)
            if let ps = PromptSetting(rawValue: min(max(c.index, 0), 3)) {
                ctx.services.promptSetting = ps
            }
        case .display:
            if let disp = display {
                ctx.sound(.decide)
                disp.fullscreen = (c.index == 1)
            }
        case .windowSize:
            if let disp = display, c.index < disp.sizeChoices.count {
                ctx.sound(.decide)
                disp.windowSize = disp.sizeChoices[c.index]
            }
        case .screenshotNotice:
            if let p = port {
                ctx.sound(.decide)
                p.screenshotNotice = (c.index == 1)
            }
        case .copyText:
            if let p = port {
                ctx.sound(.decide)
                p.copyTextToClipboard = (c.index == 1)
            }
        case .textHooker:
            if let p = port {
                ctx.sound(.decide)
                p.textHookerOutput = (c.index == 1)
            }
        case .textWebSocket:
            if let p = port {
                ctx.sound(.decide)
                p.textWebSocket = (c.index == 1)
            }
        case .backgroundMute:
            if let p = port {
                ctx.sound(.decide)
                p.muteInBackground = (c.index == 1)
            }
        case .opacity:
            if d != 0 {
                setOpacity(windowOpacityPercent + (Self.opacityStep * d))
            } else if !pointerX.isNaN {
                if let found = layout.first(where: { $0.ctl == c }) {
                    opacityTo(found.x, pointerX)
                }
            }
        case .lang:
            ctx.sound(.decide)
            if Int(config.language) != c.index {
                config.language = Int16(c.index)
                _dirty = true
                ctx.services.configChanged(.language)
                _langCool = 5
                _voiceRows = buildVoiceRows()
            }
        }
    }
    public func Change(_ c: Ctl, _ d: Int, _ pointerX: Float = Float.nan) {
        change(c, d, pointerX: pointerX)
    }

    private func languageAvailable(_ index: Int) -> Bool {
        if let lang = Language(rawValue: UInt8(index)) {
            return ctx.assets.availableLanguages.contains(lang)
        }
        return false
    }

    private func setOpacity(_ percent: Int) {
        let clamped = min(max(percent, 0), 100)
        if clamped == windowOpacityPercent {
            return
        }
        windowOpacityPercent = clamped
        ctx.services.configChanged(.setting)
        _dirty = true
    }

    private func opacityTo(_ x: Float, _ centreX: Float) {
        let t = min(max((centreX - x) / Self.opacityTrack, 0.0), 1.0)
        setOpacity(Int(round(t * 100.0 / Float(Self.opacityStep))) * Self.opacityStep)
    }

    private func resetDefaults() {
        let currentLang = cfg.language
        cfg.copy(from: ConfigBlock.createBootDefaults())
        cfg.language = currentLang
        ctx.services.configChanged(.reset)
        _dirty = true
    }

    private func switchTab(_ newTab: Int) {
        if newTab != _tab || _nextTab >= 0 {
            _scrollBar.release()
            _dragCtl = nil
            _nextTab = newTab
            ctx.sound(.decide)
        }
    }

    private func buildVoiceRows() -> [(row: Int, face: Int, name: Int)] {
        var rows: [(Int, Int, Int)] = []
        let inGame = (root?.stack.isEmpty ?? true) || !(root?.stack[0] is TitleScreen)
        let words = ctx.assets.tables.voiceRowWords
        for r in 0..<min(19, words.count) {
            let w = ctx.services.global(words[r])
            if (w & 4) == 0 {
                continue
            }

            var face: Int
            var name: Int
            if r == 0 {
                if inGame {
                    if ctx.services.phase == 0 {
                        continue
                    }
                    switch ctx.services.script {
                    case 1:
                        face = 19
                        name = 0
                    case 2, 3:
                        face = 18
                        name = 19
                    default:
                        face = 0
                        name = 0
                    }
                } else if !ctx.services.sceneBit(485) {
                    face = 18
                    name = 19
                } else {
                    face = ctx.services.sceneBit(1) ? 0 : 19
                    name = 0
                }
            } else {
                face = (r >= 15 && r <= 16 && (w & 1) == 0) ? 18 : r
                name = (((0x3CF36 >> r) & 1) != 0 && (w & 2) == 0) ? 19 : r
            }

            rows.append((r, face, name))
        }

        return rows
    }

    private func maxScroll(_ tabIndex: Int) -> Float {
        switch tabIndex {
        case 0:
            return 750.0 + systemBand
        case 1:
            return max(122.0 * Float(_voiceRows.count), 113.0) - 113.0 + soundBand
        default:
            return max(0.0, (73.007 * UiMetrics.unitY) + 1528.0 - (Self.viewRect.y + Self.viewRect.h))
        }
    }

    func scrollNow(_ v: Float) {
        let clamped = trunc(min(max(v, 0.0), maxScroll(_tab)))
        _target[_tab] = clamped
        _scroll = clamped
        _tween = Self.scrollFrames
    }

    var scrollMaximum: Float { maxScroll(_tab) }

    func cursorTo(_ c: Ctl) {
        let currentLayout = layout
        if let at = currentLayout.firstIndex(where: { $0.ctl == c }) {
            _cursor = at
            followCursor()
        }
    }

    private func scrollTo(_ v: Float) {
        let clamped = trunc(min(max(v, 0.0), maxScroll(_tab)))
        if clamped != _target[_tab] {
            _target[_tab] = clamped
            _from = _scroll
            _tween = 0
        }
    }

    // MARK: - Navigation Grid

    private func rowsForLayout(_ layoutList: [(ctl: Ctl, x: Float, y: Float)]) -> [[Int]] {
        func at(_ c: Ctl) -> Int? {
            layoutList.firstIndex(where: { $0.ctl == c })
        }
        func row(_ cs: Ctl...) -> [Int] {
            cs.compactMap(at)
        }

        var result: [[Int]] = []
        if _tab == 0 {
            for i in 0..<4 {
                if i < 2 {
                    result.append(row(Ctl(.minus, i), Ctl(.slider, i), Ctl(.plus, i), Ctl(.toggle, i)))
                } else {
                    result.append(row(Ctl(.minus, i), Ctl(.slider, i), Ctl(.plus, i)))
                }
            }

            result.append(row(Ctl(.radio, 0, true), Ctl(.toggle, 2)))
            result.append(row(Ctl(.radio, 0, false)))
            for k in 1..<4 {
                result.append(row(Ctl(.radio, k, true)))
                result.append(row(Ctl(.radio, k, false)))
            }

            for k in 0..<4 {
                if languageAvailable(k) {
                    result.append(row(Ctl(.lang, k)))
                }
            }

            for band in systemBandRows() {
                switch band {
                case .displayMode:
                    result.append(row(Ctl(.display, 0), Ctl(.display, 1)))
                case .windowSize:
                    if let d = display {
                        let ctls = (0..<d.sizeChoices.count).map { Ctl(.windowSize, $0) }
                        result.append(ctls.compactMap(at))
                    }
                case .screenshotNotice, .copyText, .textHooker, .textWebSocket:
                    result.append(row(Ctl(Self.switchKind(band), 0), Ctl(Self.switchKind(band), 1)))
                default:
                    result.append(row(Ctl(.opacity)))
                }
            }
        } else if _tab == 1 {
            for i in 0..<3 {
                if i == 1 {
                    result.append(row(Ctl(.minus, i), Ctl(.slider, i), Ctl(.plus, i), Ctl(.mute, i), Ctl(.test, 0)))
                } else {
                    result.append(row(Ctl(.minus, i), Ctl(.slider, i), Ctl(.plus, i), Ctl(.mute, i)))
                }
            }

            if port != nil {
                result.append(row(Ctl(.backgroundMute, 0), Ctl(.backgroundMute, 1)))
            }

            for k in 4..<6 {
                result.append(row(Ctl(.radio, k, true)))
                result.append(row(Ctl(.radio, k, false)))
            }

            for voice in _voiceRows {
                let r = voice.row
                result.append(row(Ctl(.minus, 3 + r), Ctl(.slider, 3 + r), Ctl(.plus, 3 + r), Ctl(.mute, 3 + r), Ctl(.test, 1 + r)))
            }
        } else if _tab == 2 {
            result.append(row(Ctl(.prompt, 0), Ctl(.prompt, 1), Ctl(.prompt, 2), Ctl(.prompt, 3)))
        }

        return result
    }

    public func gridRows() -> [[Ctl]] {
        let currentLayout = layout
        return rowsForLayout(currentLayout).map { rowIndices in
            rowIndices.map { currentLayout[$0].ctl }
        }
    }
    public func GridRows() -> [[Ctl]] {
        gridRows()
    }

    private func positionInRows(_ rowList: [[Int]], _ cursorIndex: Int) -> (row: Int, col: Int)? {
        for r in 0..<rowList.count {
            if let c = rowList[r].firstIndex(of: cursorIndex) {
                return (r, c)
            }
        }
        return nil
    }

    private func nav(_ dx: Int, _ dy: Int, _ decideHeld: Bool) {
        let currentLayout = layout
        let rowList = rowsForLayout(currentLayout)
        let pos = positionInRows(rowList, _cursor)
        let before = _cursor

        if pos == nil {
            let barVal = (_cursor >= 0 && _cursor < 4) ? _cursor : _bar
            if dx < 0 {
                if barVal > 0 {
                    _cursor = barVal - 1
                } else if side.menu != nil {
                    _bar = 0
                    _cursor = 0
                    side.enter()
                    return
                }
            } else if dx > 0 {
                _cursor = min(barVal + 1, 3)
            } else if dy > 0 && !rowList.isEmpty && !rowList[0].isEmpty {
                _cursor = rowList[0][0]
            } else {
                _cursor = barVal
            }

            if _cursor >= 0 && _cursor < 4 {
                _bar = _cursor
            }
        } else if let (r, c) = pos {
            if dx != 0 && decideHeld && currentLayout[rowList[r][c]].ctl.kind == .slider {
                change(currentLayout[rowList[r][c]].ctl, dx)
                return
            }

            if dx != 0 && currentLayout[rowList[r][c]].ctl.kind == .opacity {
                change(currentLayout[rowList[r][c]].ctl, dx)
                return
            }

            if dy < 0 {
                _cursor = (r == 0) ? _bar : rowList[r - 1][min(c, rowList[r - 1].count - 1)]
            } else if dy > 0 && r + 1 < rowList.count {
                _cursor = rowList[r + 1][min(c, rowList[r + 1].count - 1)]
            } else if dx < 0 {
                if c > 0 {
                    _cursor = rowList[r][c - 1]
                } else if side.menu != nil {
                    side.enter()
                    return
                }
            } else if dx > 0 && c + 1 < rowList[r].count {
                _cursor = rowList[r][c + 1]
            }
        }

        if _cursor != before {
            ctx.sound(.cursor)
        }
        followCursor()
    }

    private func followCursor() {
        let at0 = layoutAt(0)
        guard _cursor >= 0 && _cursor < at0.count else { return }

        let (c, _, y) = at0[_cursor]
        if c.kind == .tab || c.kind == .default {
            return
        }

        let knob = _tab == 1 && c.kind == .slider && c.index >= 3
        let top: Float = knob ? y - 260.0 + 108.0 : y - 260.0
        let bottom: Float = knob ? y - 870.0 + 98.0 : y - 870.0
        let cur = _target[_tab]
        if top < cur {
            scrollTo(top)
        } else if bottom > cur {
            scrollTo(bottom)
        }
    }

    public override func onOpened() {
        _voiceRows = buildVoiceRows()
        _scroll = _target[_tab]
        _tween = Self.scrollFrames
        _cursor = _remember[_tab].map { cursorOf($0) } ?? _tab
        _bar = _tab
        if fromTitle {
            ctx.backdrop.fade(0.02)
        }
    }
    public override func OnOpened() {
        onOpened()
    }

    private var fromTitle: Bool {
        guard let root = root, !root.stack.isEmpty else { return false }
        return root.stack[0] is TitleScreen
    }

    private func cursorOf(_ rc: (row: Int, col: Int)) -> Int {
        let rowList = rowsForLayout(layout)
        if rc.row >= rowList.count || rowList[rc.row].isEmpty {
            return _tab
        }
        return rowList[rc.row][min(rc.col, rowList[rc.row].count - 1)]
    }

    public override func onClosed() {
        ctx.services.stopTests()
        if _dirty {
            ctx.services.commitSystemData()
            _dirty = false
        }
    }
    public override func OnClosed() {
        onClosed()
    }

    public override func stepBackground() {
        stepTick()
    }
    public override func StepBackground() {
        stepBackground()
    }

    public override func step(_ input: UiInput) {
        stepTick()
        if closing || root?.top !== self {
            return
        }

        if side.step(input, ctx) {
            return
        }

        if _nextTab >= 0 || _content < 1.0 || _langCool > 0 {
            return
        }

        if input.cancel {
            ctx.sound(.buzzer)
            close()
            return
        }

        if side.clickOnTab(input, ctx) {
            return
        }

        let currentLayout = layout
        if input.l1 || input.r1 {
            switchTab((_tab + (input.r1 ? 1 : 2)) % 3)
            return
        }

        let maxVal = maxScroll(_tab)
        if stepScrollBar(input, maxVal) {
            return
        }

        if let dragged = _dragCtl {
            if input.pointerHeld {
                if let at = currentLayout.firstIndex(where: { $0.ctl == dragged }) {
                    if dragged.kind == .opacity {
                        opacityTo(currentLayout[at].x, input.pointerX - _dragOffset)
                    } else {
                        sliderTo(dragged, currentLayout[at].x, input.pointerX - _dragOffset, snap: false)
                    }
                }
                return
            }
            _dragCtl = nil
        }

        let dx = input.left ? -1 : (input.right ? 1 : 0)
        let dy = input.up ? -1 : (input.down ? 1 : 0)
        if dx != 0 || dy != 0 {
            nav(dx, dy, input.decideHeld)
        }

        if input.wheel != 0 && maxScroll(_tab) > 0 {
            scrollTo(_target[_tab] - (Float(input.wheel) * 60.0))
        }

        if input.pointerMoved {
            for i in stride(from: currentLayout.count - 1, through: 0, by: -1) {
                let r = contentRect(currentLayout, i)
                if r.contains(input.pointerX, input.pointerY) {
                    if _cursor != i {
                        _cursor = i
                        ctx.sound(.cursor)
                    }
                    break
                }
            }
        }

        var hit = -1
        for i in stride(from: currentLayout.count - 1, through: 0, by: -1) {
            if contentRect(currentLayout, i).contains(input.pointerX, input.pointerY) {
                hit = i
                break
            }
        }

        if input.click && hit >= 0 {
            _cursor = hit
            _hold = 20
            let clicked = currentLayout[hit].ctl
            if clicked.kind == .slider {
                beginSliderDrag(clicked, currentLayout[hit].x, input.pointerX)
            } else if clicked.kind == .opacity {
                _dragOffset = 0
                opacityTo(currentLayout[hit].x, input.pointerX)
                _dragCtl = clicked
            } else {
                change(clicked, 0, pointerX: input.pointerX)
            }
        } else if input.decide && !input.click && _cursor >= 0 && _cursor < currentLayout.count {
            let c = currentLayout[_cursor].ctl
            if c.kind != .slider {
                _hold = 20
                change(c, 0)
            }
        }

        var heldCtl: Ctl? = nil
        if input.pointerHeld && hit >= 0 {
            heldCtl = currentLayout[hit].ctl
        } else if input.decideHeld && _cursor >= 0 && _cursor < currentLayout.count {
            heldCtl = currentLayout[_cursor].ctl
        }

        if let hc = heldCtl, (hc.kind == .minus || hc.kind == .plus) && !input.decide && !input.click {
            if _hold > 0 {
                _hold -= 1
            } else if _hold == 0 {
                change(hc, 0)
            }
        }

        if !input.decide && !input.click && !input.decideHeld && !input.pointerHeld {
            _hold = -1
        }

        if _cursor >= 0 && _nextTab < 0 {
            _remember[_tab] = positionInRows(rowsForLayout(currentLayout), _cursor) ?? _remember[_tab]
        }
    }
    public override func Step(_ input: UiInput) {
        step(input)
    }

    private static let sliderTrack: Float = 508.0
    private static let sliderCentre: Float = 468.0
    private static let dotPitch: Float = sliderTrack / 4.0
    private static let dotSnap: Float = 10.0
    private static let pageScroll: Float = 758.0

    private func stepScrollBar(_ input: UiInput, _ maxVal: Float) -> Bool {
        let use = _scrollBar.step(input, fraction: maxVal > 0 ? _scroll / maxVal : 0.0, height: 608.0, canScroll: maxVal > 0)
        if let f = use.fraction {
            scrollNow(f * maxVal)
        } else if use.page != 0 {
            scrollTo(_target[_tab] + (Float(use.page) * Self.pageScroll))
        }
        return use.consumed
    }

    private func beginSliderDrag(_ c: Ctl, _ x: Float, _ pointerX: Float) {
        let (v, maxVal, _) = slider(c.index)
        let centre = x + Self.sliderCentre + (maxVal > 0 ? v / maxVal * Self.sliderTrack : 0.0)
        if abs(pointerX - centre) <= 34.5 {
            _dragOffset = pointerX - centre
        } else {
            _dragOffset = 0
            sliderTo(c, x, pointerX, snap: true)
        }
        _dragCtl = c
    }

    private func sliderTo(_ c: Ctl, _ x: Float, _ centreX: Float, snap: Bool) {
        let (v, maxVal, step) = slider(c.index)
        var t = (centreX - (x + Self.sliderCentre)) / Self.sliderTrack
        if snap {
            for k in 0..<5 {
                if abs(centreX - (x + Self.sliderCentre + (Float(k) * Self.dotPitch))) <= Self.dotSnap {
                    t = Float(k) / 4.0
                    break
                }
            }
        }

        var nv = min(max(t, 0.0), 1.0) * maxVal
        nv = step > 1.0 ? round(nv / step) * step : round(nv)
        if nv != v {
            setSlider(c.index, nv)
        }
    }

    private func contentRect(_ layoutList: [(ctl: Ctl, x: Float, y: Float)], _ i: Int) -> RectF {
        let (c, x, y) = layoutList[i]
        var r = hitRect(c, x, y)
        if c.kind == .slider {
            r = RectF(r.x, r.y, Self.sliderTrack + r.w, r.h)
        }
        if c.kind != .tab && c.kind != .default {
            r = r.intersect(Self.viewRect)
        }
        return r
    }

    private func stepTick() {
        if _langCool > 0 {
            _langCool -= 1
        }

        if _tween < Self.scrollFrames {
            _tween = min(Self.scrollFrames, _tween + 1.0)
            let t = _tween / Self.scrollFrames
            _scroll = _from + ((_target[_tab] - _from) * -(t * (t - 2.0)))
        }

        if _nextTab >= 0 {
            _content -= 0.05
            if _content <= 0 {
                _content = 0
                _tab = _nextTab
                _nextTab = -1
                _scroll = _target[_tab]
                _tween = Self.scrollFrames
                _cursor = _remember[_tab].map { cursorOf($0) } ?? _bar
            }
        } else {
            _content = min(1.0, _content + 0.05)
        }

        if _tab == 0 {
            stepPreview()
        }
    }

    private func stepPreview() {
        let hold = Float(cfg.autoModeWait) * 60.0 / 1000.0
        for k in 0..<2 {
            let ms = Float(k == 0 ? cfg.unseenTextSpeed : cfg.seenTextSpeed)
            let speed = ms < 1.0 ? 768.0 : (16.667 / ms)
            let edge = speed >= 768.0 ? 0.0 : speed * min((ms * 0.1) / 35.0, 0.5) * 60.0
            let full: Bool
            if speed >= 768.0 {
                _preview[k][0] = 768.0
                _preview[k][1] = 768.0
                full = true
            } else {
                _preview[k][0] = min(_preview[k][0] + speed, 768.0)
                _preview[k][1] = max(_preview[k][1], _preview[k][0] - edge)
                full = _preview[k][1] >= 10.0
            }

            if full {
                _preview[k][2] += 1.0
                if _preview[k][2] > hold {
                    _preview[k][0] = 0
                    _preview[k][1] = 0
                    _preview[k][2] = 0
                }
            }
        }
    }

    // MARK: - Drawing

    public override func draw(_ p: UiPainter) {
        p.withAlpha(fade) {
            p.sprite(UiSheets.confPanel, RectF(0, 0, 1560, 1080), RectF(360, 0, 1560, 1080))
            p.sprite(UiSheets.confHeader, RectF(0, 0, 1416, 72), RectF(400, 96, 1416, 72))
            let currentLayout = layout
            p.withClip(Self.viewRect) {
                p.withAlpha(_content) {
                    drawPage(p)
                    drawNumbers(p)
                    if _tab == 0 {
                        drawPreview(p)
                    }
                    for i in 0..<currentLayout.count {
                        if currentLayout[i].ctl.kind == .tab || currentLayout[i].ctl.kind == .default {
                            continue
                        }
                        drawControl(p, currentLayout[i].ctl, currentLayout[i].x, currentLayout[i].y, i)
                    }
                }
            }

            for i in 0..<currentLayout.count {
                if currentLayout[i].ctl.kind == .tab || currentLayout[i].ctl.kind == .default {
                    drawControl(p, currentLayout[i].ctl, currentLayout[i].x, currentLayout[i].y, i)
                }
            }

            let maxVal = maxScroll(_tab)
            if maxVal > 0 {
                UiWidgets.scrollBar(p, _scroll / maxVal, 608.0, _content, _scrollBar)
            }

            UiWidgets.guide(p, UiWidgets.guideConfig, decideIsCross: ctx.services.decideIsCross)
        }
    }
    public override func Draw(_ p: UiPainter) {
        draw(p)
    }

    private func drawHeading(_ p: UiPainter, _ text: String, _ centre: Float) {
        let scale = text.contains("^") ? Self.twoLineHeadingScale : 0.4
        UiPrompts.drawText(p, text, Self.displayLabelX, centre, 1.0, scale: scale)
    }

    private func drawPage(_ p: UiPainter) {
        func u(_ x: Float, _ y: Float) -> (x: Float, y: Float) {
            (x * 3.0, (y * UiMetrics.unitY) - _scroll)
        }

        if _tab == 0 {
            let (x, y) = u(128.667, 68.03)
            let (w, h) = p.sizeOf(UiSheets.confSystemPage)
            if Float(h) > Self.displaySplitRow {
                let rows = systemBandRows()
                let band = Self.bandFor(rows.count)
                p.sprite(UiSheets.confSystemPage, RectF(0, 0, Float(w), Self.displaySplitRow), RectF(x, y, Float(w), Self.displaySplitRow))
                p.sprite(UiSheets.confSystemPage, RectF(0, Self.displayFillerTop, Float(w), Self.displaySplitRow - Self.displayFillerTop), RectF(x, y + Self.displaySplitRow, Float(w), band))
                p.sprite(UiSheets.confSystemPage, RectF(0, Self.displaySplitRow, Float(w), Float(h) - Self.displaySplitRow), RectF(x, y + Self.displaySplitRow + band, Float(w), Float(h) - Self.displaySplitRow))
                let top = y + Self.displaySplitRow
                p.sprite(UiSheets.confSystemPage, RectF(0, Self.displayRuleRow, Float(w), 1), RectF(x, top + Self.displayRuleDy, Float(w), 1))
                for i in 0..<rows.count {
                    let centre = top + Self.displayRowDy + (Self.displayRowPitch * Float(i)) + (UiPrompts.pillHeight / 2.0) + 2.0
                    switch rows[i] {
                    case .displayMode:
                        UiPrompts.drawText(p, UiPrompts.displayHeading(ctx.language), Self.displayLabelX, centre, 1.0)
                    case .windowSize:
                        UiPrompts.drawText(p, UiPrompts.sizeHeading(ctx.language), Self.displayLabelX, centre, (display?.fullscreen ?? false) ? Self.dimmedSizeRow : 1.0)
                    case .screenshotNotice:
                        drawHeading(p, UiPrompts.screenshotNoticeHeading(ctx.language), centre)
                    case .copyText:
                        drawHeading(p, UiPrompts.copyTextHeading(ctx.language), centre)
                    case .textHooker:
                        drawHeading(p, UiPrompts.textHookerHeading(ctx.language), centre)
                    case .textWebSocket:
                        drawHeading(p, UiPrompts.webSocketHeading(ctx.language), centre)
                    default:
                        drawHeading(p, UiPrompts.opacityHeading(ctx.language), centre)
                    }
                }
            } else {
                p.sprite(UiSheets.confSystemPage, RectF(0, 0, Float(w), Float(h)), RectF(x, y, Float(w), Float(h)))
            }
        } else if _tab == 1 {
            var (x, y) = u(128.667, 68.03)
            let band = soundBand
            if band > 0 {
                p.sprite(UiSheets.confSoundPage, RectF(0, 0, 1432, Self.soundSplitRow), RectF(x, y, 1432, Self.soundSplitRow))
                p.sprite(UiSheets.confSoundPage, RectF(0, Self.soundFillerTop, 1432, Self.soundSplitRow - Self.soundFillerTop), RectF(x, y + Self.soundSplitRow, 1432, band))
                p.sprite(UiSheets.confSoundPage, RectF(0, Self.soundSplitRow, 1432, 328 - Self.soundSplitRow), RectF(x, y + Self.soundSplitRow + band, 1432, 328 - Self.soundSplitRow))
                UiPrompts.drawText(p, UiPrompts.muteHeading(ctx.language), Self.displayLabelX, y + Self.soundSplitRow + Self.soundRowDy + (UiPrompts.pillHeight / 2.0) + 2.0, 1.0)
            } else {
                p.sprite(UiSheets.confSoundPage, RectF(0, 0, 1432, 328), RectF(x, y, 1432, 328))
            }

            (x, y) = u(128.667, 199.94)
            p.sprite(UiSheets.confVoicePage, RectF(0, 0, 1432, 386), RectF(x, y + band, 1432, 386))
            let faces = ctx.assets.tables.voiceFaceCells
            let names = ctx.assets.tables.voiceNameCells(ctx.language)
            for i in 0..<_voiceRows.count {
                let n = Float(i) * 50.607
                (x, y) = u(128.667, 360.06 + n)
                p.sprite(UiSheets.confVoicePage, RectF(0, 386, 1432, 122), RectF(x, y + band, 1432, 122))
                let (_, face, name) = _voiceRows[i]
                if face < faces.count {
                    let f = faces[face]
                    let (fx, fy) = u(144.0, 365.04 + n)
                    p.sprite(UiSheets.confFaces, RectF.fromCorners(Float(f.x0), Float(f.y0), Float(f.x1), Float(f.y1)), RectF(fx, fy + band, Float(f.width), Float(f.height)))
                }
                if name < names.count {
                    let nm = names[name]
                    let (nx, ny) = u(144.0, 394.9 + n)
                    p.sprite(UiSheets.confNames, RectF.fromCorners(Float(nm.x0), Float(nm.y0), Float(nm.x1), Float(nm.y1)), RectF(nx, ny + band, Float(nm.width), Float(nm.height)))
                }
            }

            (x, y) = u(128.667, 360.06 + (Float(_voiceRows.count) * 50.607))
            p.sprite(UiSheets.confVoicePage, RectF(0, 508, 1432, 19), RectF(x, y + band, 1432, 19))
        } else {
            drawControlsPage(p)
        }
    }

    private func drawControlsPage(_ p: UiPainter) {
        let sheet = ctx.services.decideIsCross ? UiSheets.confControlsPadCross : UiSheets.confControlsPad
        func u(_ x: Float, _ y: Float) -> (x: Float, y: Float) {
            (x * 3.0, (y * UiMetrics.unitY) - _scroll)
        }
        let (x, y) = u(133.333, 73.007)
        let (w, h) = p.sizeOf(sheet)
        let style = p.promptStyle
        if style == .playStation || w < 1200 {
            p.sprite(sheet, RectF(0, 0, Float(w), Float(h)), RectF(x, y, Float(w), Float(h)))
        } else {
            let colX: Float = UiPrompts.controlColumnX - 16.0
            let colW: Float = 140.0
            let half: Float = 24.0
            let slice: Float = 6.0
            var cursorY: Float = 0

            func strip(_ y0: Float, _ y1: Float) {
                if y1 > y0 {
                    p.sprite(sheet, RectF(0, y0, Float(w), y1 - y0), RectF(x, y + y0, Float(w), y1 - y0))
                }
            }

            var rowIndex = 0
            for centre in UiPrompts.controlRowCentres {
                let top = floor(centre) - half
                let sliceY = rowIndex == 0 ? top + half + 21.0 : top + half - 27.0
                rowIndex += 1
                strip(cursorY, top)
                p.sprite(sheet, RectF(0, top, colX, 2.0 * half), RectF(x, y + top, colX, 2.0 * half))
                p.sprite(sheet, RectF(colX + colW, top, Float(w) - colX - colW, 2.0 * half), RectF(x + colX + colW, y + top, Float(w) - colX - colW, 2.0 * half))
                let sliceCount = Int(2.0 * half / slice)
                for k in 0..<sliceCount {
                    p.sprite(sheet, RectF(colX, sliceY, colW, slice), RectF(x + colX, y + top + (Float(k) * slice), colW, slice))
                }
                cursorY = top + (2.0 * half)
            }

            strip(cursorY, Float(h))
            for row in 0..<UiPrompts.controlRowCentres.count {
                let items = UiPrompts.controlRow(row, style)
                UiPrompts.draw(p, items, x + UiPrompts.controlColumnX, y + UiPrompts.controlRowCentres[row] + (UiPrompts.capHeight / 2.0), 1.0)
            }
        }

        UiPrompts.drawText(p, UiPrompts.settingHeading(ctx.language), x + 28.0, y + 26.0, 1.0)
    }

    private func drawNumbers(_ p: UiPainter) {
        func u(_ x: Float, _ y: Float) -> (x: Float, y: Float) {
            (x * 3.0, (y * UiMetrics.unitY) - _scroll)
        }

        if _tab == 0 {
            let ys: [Float] = [131.5, 205.75, 271.29, 330.61]
            for i in 0..<4 {
                let (x, y) = u(450.0, ys[i])
                UiWidgets.number(p, UiSheets.confDigits, Int(round(slider(i).value)), x, y)
            }
        } else if _tab == 1 {
            let ys: [Float] = [107.44, 134.81, 163.02]
            for i in 0..<3 {
                let (x, y) = u(538.67, ys[i])
                UiWidgets.number(p, UiSheets.confDigits, Int(round(slider(i).value)), x, y)
            }

            let band = soundBand
            for n in 0..<_voiceRows.count {
                let (x, y) = u(538.33, 372.5 + (50.607 * Float(n)))
                UiWidgets.number(p, UiSheets.confDigits, Int(round(slider(3 + _voiceRows[n].row).value)), x, y + band)
            }
        }
    }

    public static let sampleLeft: Float = 252.333 * 3.0
    public static let SampleLeft: Float = sampleLeft
    public static let sampleBoxRight: Float = 1264.0
    public static let SampleBoxRight: Float = sampleBoxRight

    public static func sampleStyle(_ scale: Float = 1.0) -> TextStyle {
        TextStyle(
            canvasW: 640,
            canvasH: 448,
            sx: 0.74 * Double(scale),
            sy: 0.9176 * Double(scale),
            width: 200,
            height: 20,
            leading: 0,
            spacing: 0,
            colour: TextStyle.white,
            drawFlags: BlockDraw.always | BlockDraw.outline
        )
    }
    public static func SampleStyle(_ scale: Float = 1.0) -> TextStyle {
        sampleStyle(scale)
    }

    var sampleScale: Float {
        if _sampleLanguage != ctx.language {
            var ink: Float = 0
            for k in 0..<2 {
                let text = ctx.message(138 + k)
                if !text.isEmpty {
                    ink = max(ink, ctx.text.inkSpan(text, Self.sampleStyle()).right)
                }
            }
            let fit = ink > 0 ? (Self.sampleBoxRight - Self.sampleLeft) / ink : 1.0
            _sampleScale = min(english ? 0.9 : 1.0, fit)
            _sampleLanguage = ctx.language
        }
        return _sampleScale
    }

    private func drawPreview(_ p: UiPainter) {
        func u(_ x: Float, _ y: Float) -> (x: Float, y: Float) {
            (x * 3.0, (y * UiMetrics.unitY) - _scroll)
        }

        let scale = sampleScale
        let style = Self.sampleStyle(scale)
        for k in 0..<2 {
            let text = ctx.message(138 + k)
            if text.isEmpty {
                continue
            }
            let s = _preview[k]
            let rowY: Float = k == 0 ? 126.93 : 201.19
            let (x, y) = u(252.333, rowY)
            ctx.text.draw(p, text, style, x / UiMetrics.unitX, (y + ((1.0 - scale) * 26.0)) / UiMetrics.unitY, 1.0, count: s[0], edge: s[1])
        }
    }

    private func drawControl(_ p: UiPainter, _ c: Ctl, _ x: Float, _ y: Float, _ index: Int) {
        let hover = (index == _cursor) && !side.active
        if c.kind == .prompt {
            UiPrompts.drawPill(p, UiPrompts.settingLabel(ctx.language, c.index), hitRect(c, x, y), selected: isOn(c), hover: hover, alpha: 1.0, translated: c.index < 2 && ctx.language != .en)
            return
        }

        if c.kind == .display {
            UiPrompts.drawPill(p, UiPrompts.displayLabel(ctx.language, c.index), hitRect(c, x, y), selected: isOn(c), hover: hover, alpha: 1.0, translated: ctx.language != .en)
            return
        }

        if c.kind == .windowSize {
            if let disp = display, c.index < disp.sizeChoices.count {
                let choice = disp.sizeChoices[c.index]
                let dimAlpha: Float = (disp.fullscreen && !hover) ? Self.dimmedSizeRow : 1.0
                UiPrompts.drawPill(p, UiPrompts.sizeLabel(choice.width, choice.height), hitRect(c, x, y), selected: isOn(c), hover: hover, alpha: dimAlpha)
            }
            return
        }

        if Self.isSwitch(c.kind) {
            UiPrompts.drawPill(p, UiPrompts.switchLabel(ctx.language, c.index), hitRect(c, x, y), selected: isOn(c), hover: hover, alpha: 1.0, translated: ctx.language != .en)
            return
        }

        if c.kind == .opacity {
            drawOpacity(p, x, y, hover)
            return
        }

        let col = isOn(c) ? 2 : (hover ? 1 : 0)
        drawControlSprite(p, c, x, y, col, hover, 1.0, .alpha)

        let focused = hover || (_cursor < 0 && !side.active && c.kind == .tab && c.index == _tab)
        if focused {
            let pulse = UiEase.triangle((Float(ctx.frame) / 60.0) * 1.2)
            drawControlSprite(p, c, x, y, col, hover, pulse, .psAdd)
        }
    }

    private func drawOpacity(_ p: UiPainter, _ x: Float, _ y: Float, _ hover: Bool) {
        let cy = y + (UiPrompts.pillHeight / 2.0)
        let pct = windowOpacityPercent
        let kx = x + (Self.opacityTrack * Float(pct) / 100.0)
        let edge: Float = hover ? 1.0 : 0.72

        p.fillRounded(RectF(x, cy - 3.0, Self.opacityTrack, 6.0), radius: 3.0, r: 0.62 * edge, g: 0.86 * edge, b: 1.0 * edge, a: 0.45, smooth: false)
        if kx > x {
            p.fillRounded(RectF(x, cy - 3.0, kx - x, 6.0), radius: 3.0, r: 0.12, g: 0.42, b: 0.86, a: 0.96, smooth: false)
        }

        for k in 0...4 {
            let dx = x + (Self.opacityTrack * Float(k) / 4.0)
            p.fillRounded(RectF(dx - 4.0, cy - 4.0, 8.0, 8.0), radius: 4.0, r: 0.62 * edge, g: 0.86 * edge, b: 1.0 * edge, a: 0.9, smooth: false)
        }

        let knob = RectF(kx - (Self.opacityKnobWidth / 2.0), y, Self.opacityKnobWidth, UiPrompts.pillHeight)
        p.fillRounded(knob, radius: 9.0, r: 0.62 * edge, g: 0.86 * edge, b: 1.0 * edge, a: hover ? 0.98 : 0.8)
        p.fillRounded(RectF(knob.x + 2.0, knob.y + 2.0, knob.w - 4.0, knob.h - 4.0), radius: 7.0, r: 0.12, g: 0.42, b: 0.86, a: 0.96, smooth: false)
        UiPrompts.drawText(p, UiPrompts.percentLabel(pct), x + Self.opacityTrack + 28.0, cy + 2.0, 1.0, translated: false)
    }

    private func drawControlSprite(_ p: UiPainter, _ c: Ctl, _ x: Float, _ y: Float, _ col: Int, _ hover: Bool, _ alpha: Float, _ blend: UiBlend) {
        switch c.kind {
        case .tab:
            p.sprite(UiSheets.confTabs, RectF(8.0 + (Float(col) * 200.0), 8.0 + (Float(c.index) * 88.0), 192, 80), RectF(x, y, 192, 80), alpha, blend)
        case .default:
            p.sprite(UiSheets.confDefault, RectF(32, 24.0 + (Float(hover ? 1 : 0) * 96.0), 288, 72), RectF(x, y, 288, 72), alpha, blend)
        case .minus, .plus:
            let sx: Float = c.kind == .plus ? 88.0 : 0.0
            let sy: Float = hover ? 49.0 : 0.0
            p.sprite(UiSheets.confStep, RectF(sx, sy, 80, 40), RectF(x, y, 80, 40), alpha, blend)
        case .slider:
            let (v, maxVal, _) = slider(c.index)
            let kx = x + (maxVal > 0 ? v / maxVal * 508.0 : 0.0)
            let src = hover ? RectF(0, 0, 936, 248) : RectF(0, 256, 936, 248)
            p.sprite(UiSheets.confKnob, src, RectF(kx, y, 936, 248), alpha, blend)
        case .toggle:
            let cell = toggleCell(c.index, col)
            p.sprite(UiSheets.confToggle, RectF.fromCorners(Float(cell.x0), Float(cell.y0), Float(cell.x1), Float(cell.y1)), RectF(x, y, Float(cell.width), Float(cell.height)), alpha, blend)
        case .radio:
            let cell = radioCell(c.index, c.first, col)
            p.sprite(UiSheets.confRadio, RectF.fromCorners(Float(cell.x0), Float(cell.y0), Float(cell.x1), Float(cell.y1)), RectF(x, y, Float(cell.width), Float(cell.height)), alpha, blend)
        case .lang:
            p.sprite(UiSheets.confLanguage, RectF(Float(col) * 256.0, 88.0 * Float(c.index), 248, 80), RectF(x, y, 248, 80), alpha, blend)
        case .mute:
            p.sprite(UiSheets.confMute, RectF(32.0 + (Float(col) * 152.0), 32, 136, 64), RectF(x, y, 136, 64), alpha, blend)
        case .test:
            p.sprite(UiSheets.confTest, RectF(32.0 + (Float(hover ? 1 : 0) * 120.0), 32, 104, 56), RectF(x, y, 104, 56), alpha, blend)
        default:
            break
        }
    }
}
