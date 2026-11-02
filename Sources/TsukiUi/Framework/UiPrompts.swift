import Foundation
import TsukiEngine

/// Which button prompts a screen draws.
public enum PromptStyle: Int, Sendable {
    /// Key caps (Enter, Esc, arrows, the mouse wheel).
    case keyboard = 0
    /// The game's own PlayStation icons (the PS4 pictures).
    case playStation = 1
    /// Drawn Xbox glyphs: coloured A, B, X, Y circles, bumpers, triggers, sticks.
    case xbox = 2

    public static let Keyboard = PromptStyle.keyboard
    public static let PlayStation = PromptStyle.playStation
    public static let Xbox = PromptStyle.xbox
}

/// The config screen's choice of button prompts.
public enum PromptSetting: Int, Sendable {
    /// Follow the device used last: the keyboard and the mouse show key caps, a PlayStation pad the PlayStation icons, any other pad the Xbox glyphs.
    case auto = 0
    /// Always key caps.
    case keyboard = 1
    /// Always the PlayStation icons.
    case playStation = 2
    /// Always the Xbox glyphs.
    case xbox = 3

    public static let Auto = PromptSetting.auto
    public static let Keyboard = PromptSetting.keyboard
    public static let PlayStation = PromptSetting.playStation
    public static let Xbox = PromptSetting.xbox
}

/// Helpers for `PromptSetting` and `PromptStyle`.
public enum PromptStyles {
    /// The style to draw: the setting itself, or for `PromptSetting.auto` the style of the device used last.
    public static func resolve(_ setting: PromptSetting, _ lastDevice: PromptStyle) -> PromptStyle {
        switch setting {
        case .keyboard: return .keyboard
        case .playStation: return .playStation
        case .xbox: return .xbox
        case .auto: return lastDevice
        }
    }
    public static func Resolve(_ setting: PromptSetting, _ lastDevice: PromptStyle) -> PromptStyle {
        resolve(setting, lastDevice)
    }

    /// The file and command-line name of a setting (lower case).
    public static func name(_ setting: PromptSetting) -> String {
        switch setting {
        case .keyboard: return "keyboard"
        case .playStation: return "playstation"
        case .xbox: return "xbox"
        case .auto: return "auto"
        }
    }
    public static func Name(_ setting: PromptSetting) -> String { name(setting) }

    /// Reads a setting name (case-insensitive; `ps`, `ps4`, `ps5` and `keys` are accepted); false when it is none.
    public static func tryParse(_ text: String?, setting: inout PromptSetting) -> Bool {
        let t = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch t {
        case "auto", "default":
            setting = .auto
            return true
        case "keyboard", "keys", "kb":
            setting = .keyboard
            return true
        case "playstation", "ps", "ps4", "ps5", "sony":
            setting = .playStation
            return true
        case "xbox", "xinput", "ms":
            setting = .xbox
            return true
        default:
            setting = .auto
            return false
        }
    }
    public static func TryParse(_ text: String?, _ setting: inout PromptSetting) -> Bool {
        tryParse(text, setting: &setting)
    }
}

/// What a button prompt asks the player to do, in the terms of the keyboard bindings (`PromptBindings`).
public enum PromptAction: Int, Sendable {
    case confirm
    case back
    case up
    case down
    case left
    case right
    case previousPage
    case nextPage
    case scroll
    case deleteData
    case systemMenu
    case backlog
    case skipToggle
    case autoToggle
    case fastForward
    case rewind
    case quickSave
}

public enum PromptItemKind: Sendable {
    case key
    case arrows
    case mouse
    case face
    case pill
    case dpad
}

public struct PromptItem: Sendable {
    public var kind: PromptItemKind
    public var text: String
    public var mask: Int

    public static let up = 1
    public static let down = 2
    public static let left = 4
    public static let right = 8

    public init(_ kind: PromptItemKind, _ text: String = "", _ mask: Int = 0) {
        self.kind = kind
        self.text = text
        self.mask = mask
    }

    public static func key(_ text: String) -> PromptItem {
        PromptItem(.key, text)
    }
    public static func Key(_ text: String) -> PromptItem { key(text) }

    public static func pill(_ text: String) -> PromptItem {
        PromptItem(.pill, text)
    }
    public static func Pill(_ text: String) -> PromptItem { pill(text) }
}

public enum PromptBindings {
    public static let cellEast = 7
    public static let cellWest = 8
    public static let cellNorth = 9
    public static let cellSouth = 10
    public static let cellLeftStick = 11
    public static let cellRightStick = 12

    public static let CellEast = cellEast
    public static let CellWest = cellWest
    public static let CellNorth = cellNorth
    public static let CellSouth = cellSouth
    public static let CellLeftStick = cellLeftStick
    public static let CellRightStick = cellRightStick

    public static let wordDeleteData = 18
    public static let wordNavigate = 25
    public static let wordScroll = 26
    public static let wordZoom = 24

    public static let WordDeleteData = wordDeleteData
    public static let WordNavigate = wordNavigate
    public static let WordScroll = wordScroll
    public static let WordZoom = wordZoom

    public static let keys: [(action: PromptAction, keys: [String])] = [
        (.confirm, ["Enter", "Space", "Z"]),
        (.back, ["Esc", "X"]),
        (.up, ["Up", "W"]),
        (.down, ["Down", "S"]),
        (.left, ["Left", "A"]),
        (.right, ["Right", "D"]),
        (.previousPage, ["Q"]),
        (.nextPage, ["E"]),
        (.scroll, ["PgUp", "PgDn"]),
        (.deleteData, ["Del"]),
        (.systemMenu, ["Esc", "M"]),
        (.backlog, ["PgUp", "I"]),
        (.skipToggle, ["Tab"]),
        (.autoToggle, ["A"]),
        (.fastForward, ["Ctrl"]),
        (.rewind, ["Backspace"]),
        (.quickSave, ["F5"]),
    ]
    public static var Keys: [(action: PromptAction, keys: [String])] { keys }

    public static func keysOf(_ action: PromptAction) -> [String] {
        for (a, k) in keys {
            if a == action {
                return k
            }
        }
        return []
    }
    public static func KeysOf(_ action: PromptAction) -> [String] { keysOf(action) }

    public static func keyboard(_ cell: Int, _ word: Int, menu: Bool = true) -> [PromptItem] {
        switch cell {
        case 0: return cursor(PromptItem.up | PromptItem.down | PromptItem.left | PromptItem.right, "WASD", menu)
        case 1: return cursor(PromptItem.left | PromptItem.right, "A D", menu)
        case 2: return cursor(PromptItem.up | PromptItem.down, "W S", menu)
        case 3: return cursor(PromptItem.up, "W", menu)
        case 4: return cursor(PromptItem.down, "S", menu)
        case 5: return cursor(PromptItem.right, "D", menu)
        case 6: return cursor(PromptItem.left, "A", menu)
        case cellEast: return [.key(keysOf(.confirm)[0])]
        case cellSouth: return [.key(keysOf(.back)[0])]
        case cellNorth where word == wordDeleteData: return [.key(keysOf(.deleteData)[0])]
        case cellLeftStick where word == wordNavigate: return [.key("Drag")]
        case cellLeftStick where word == wordScroll:
            return [PromptItem(.mouse), .key(keysOf(.scroll)[0]), .key(keysOf(.scroll)[1])]
        case cellLeftStick, cellRightStick:
            return [PromptItem(.mouse)]
        case 13, 16: return [.key(keysOf(.previousPage)[0])]
        case 14, 17: return [.key(keysOf(.nextPage)[0])]
        case 15: return [.key(keysOf(.previousPage)[0]), .key(keysOf(.nextPage)[0])]
        case 18, 22: return [.key(keysOf(.quickSave)[0])]
        case 19: return [.key(keysOf(.rewind)[0])]
        case 20: return [.key(keysOf(.fastForward)[0])]
        default: return []
        }
    }
    public static func Keyboard(_ cell: Int, _ word: Int, _ menu: Bool = true) -> [PromptItem] {
        keyboard(cell, word, menu: menu)
    }

    private static func cursor(_ arrows: Int, _ letters: String, _ menu: Bool) -> [PromptItem] {
        menu ? [PromptItem(.arrows, "", arrows), .key(letters)] : [PromptItem(.arrows, "", arrows)]
    }

    public static func xbox(_ cell: Int) -> [PromptItem] {
        switch cell {
        case 0: return [PromptItem(.dpad, "", PromptItem.up | PromptItem.down | PromptItem.left | PromptItem.right)]
        case 1: return [PromptItem(.dpad, "", PromptItem.left | PromptItem.right)]
        case 2: return [PromptItem(.dpad, "", PromptItem.up | PromptItem.down)]
        case 3: return [PromptItem(.dpad, "", PromptItem.up)]
        case 4: return [PromptItem(.dpad, "", PromptItem.down)]
        case 5: return [PromptItem(.dpad, "", PromptItem.right)]
        case 6: return [PromptItem(.dpad, "", PromptItem.left)]
        case cellEast: return [PromptItem(.face, "A", 0)]
        case cellSouth: return [PromptItem(.face, "B", 1)]
        case cellWest: return [PromptItem(.face, "X", 2)]
        case cellNorth: return [PromptItem(.face, "Y", 3)]
        case cellLeftStick: return [.pill("LS")]
        case cellRightStick, 21: return [.pill("RS")]
        case 13, 16: return [.pill("LB")]
        case 14, 17: return [.pill("RB")]
        case 15: return [.pill("LB"), .pill("RB")]
        case 18, 22: return [.pill("Menu")]
        case 19: return [.pill("LT")]
        case 20: return [.pill("RT")]
        default: return []
        }
    }
    public static func Xbox(_ cell: Int) -> [PromptItem] { xbox(cell) }
}

public enum UiPrompts {
    public static let capHeight: Float = 30.0
    public static let CapHeight: Float = capHeight

    public static let gap: Float = 4.0
    public static let Gap: Float = gap

    private static let border: Float = 2.0
    private static let radius: Float = 6.0
    private static let padX: Float = 9.0
    private static let fudge: Float = 0.5

    private static let keyStyle = TextStyle(
        canvasW: 640, canvasH: 448, sx: 0.32, sy: 0.32 * (448.0 / 360.0),
        width: 600, height: 80, leading: 0, spacing: 0, colour: TextStyle.white,
        drawFlags: BlockDraw.always
    )

    private static let faceColours: [(r: Int, g: Int, b: Int)] = [
        (126, 206, 58),     // A green
        (238, 72, 64),      // B red
        (72, 148, 244),     // X blue
        (252, 196, 40),     // Y yellow
    ]

    public static func draw(_ p: UiPainter, _ items: [PromptItem], _ x: Float, _ bottom: Float, _ alpha: Float = 1.0) -> Float {
        let start = x
        var curX = x
        for i in 0..<items.count {
            if i > 0 {
                curX += gap
            }
            curX += drawItem(p, items[i], curX, bottom, alpha)
        }
        return curX - start
    }
    public static func Draw(_ p: UiPainter, _ items: [PromptItem], _ x: Float, _ bottom: Float, _ alpha: Float = 1.0) -> Float {
        draw(p, items, x, bottom, alpha)
    }

    public static func itemWidth(_ p: UiPainter, _ item: PromptItem) -> Float {
        switch item.kind {
        case .key, .pill:
            return capWidth(p, item.text)
        case .arrows:
            return Float(bitCount(item.mask) * 22) + 12.0
        case .mouse:
            return 24.0
        case .face, .dpad:
            return capHeight
        }
    }
    public static func ItemWidth(_ p: UiPainter, _ item: PromptItem) -> Float { itemWidth(p, item) }

    public static func drawItem(_ p: UiPainter, _ item: PromptItem, _ x: Float, _ bottom: Float, _ alpha: Float = 1.0) -> Float {
        let w = itemWidth(p, item)
        switch item.kind {
        case .key, .pill:
            drawCap(p, item.text, x, bottom, w, alpha)
        case .arrows:
            drawArrows(p, item.mask, x, bottom, w, alpha)
        case .mouse:
            drawMouse(p, x, bottom, alpha)
        case .face:
            drawFace(p, item, x, bottom, alpha)
        case .dpad:
            drawDpad(p, item.mask, x, bottom, alpha)
        }
        return w
    }
    public static func DrawItem(_ p: UiPainter, _ item: PromptItem, _ x: Float, _ bottom: Float, _ alpha: Float = 1.0) -> Float {
        drawItem(p, item, x, bottom, alpha)
    }

    public static let controlRowCentres: [Float] = [85.5, 151.5, 214.5, 280.5, 344.5, 410.5, 476.0, 540.0, 605.5, 670.5, 736.5, 803.5]
    public static var ControlRowCentres: [Float] { controlRowCentres }

    public static let controlColumnX: Float = 976.0
    public static let ControlColumnX: Float = controlColumnX

    public static let controlRowsTop: Float = 46.0
    public static let ControlRowsTop: Float = controlRowsTop

    public static let controlRowsBottom: Float = 846.0
    public static let ControlRowsBottom: Float = controlRowsBottom

    public static func controlRow(_ row: Int, _ style: PromptStyle) -> [PromptItem] {
        if style == .xbox {
            let cells = [
                PromptBindings.cellEast, PromptBindings.cellSouth, PromptBindings.cellWest, PromptBindings.cellNorth,
                3, 4, 17, 16, 20, 19, PromptBindings.cellLeftStick, 22
            ]
            let clampedRow = min(max(row, 0), 11)
            return PromptBindings.xbox(cells[clampedRow])
        }

        func keysHelper(_ actions: PromptAction...) -> [PromptItem] {
            var items: [PromptItem] = []
            for a in actions {
                switch a {
                case .up:
                    items.append(PromptItem(.arrows, "", PromptItem.up))
                case .down:
                    items.append(PromptItem(.arrows, "", PromptItem.down))
                case .scroll:
                    items.append(PromptItem(.mouse))
                    for k in PromptBindings.keysOf(a) {
                        items.append(.key(k))
                    }
                default:
                    items.append(.key(PromptBindings.keysOf(a)[0]))
                }
            }
            return items
        }

        switch row {
        case 0: return PromptBindings.keysOf(.confirm).map { .key($0) }
        case 1: return [.key("X")]
        case 2: return PromptBindings.keysOf(.systemMenu).map { .key($0) }
        case 3: return PromptBindings.keysOf(.backlog).map { .key($0) }
        case 4: return keysHelper(.up)
        case 5: return keysHelper(.down)
        case 6: return keysHelper(.skipToggle, .nextPage)
        case 7: return keysHelper(.autoToggle, .previousPage)
        case 8: return keysHelper(.fastForward)
        case 9: return keysHelper(.rewind)
        case 10: return keysHelper(.scroll)
        default: return keysHelper(.quickSave)
        }
    }
    public static func ControlRow(_ row: Int, _ style: PromptStyle) -> [PromptItem] {
        controlRow(row, style)
    }

    public static func pillWidth(_ index: Int) -> Float {
        switch index {
        case 0: return 100.0
        case 1: return 156.0
        case 2: return 178.0
        default: return 100.0
        }
    }
    public static func PillWidth(_ index: Int) -> Float { pillWidth(index) }

    public static let pillHeight: Float = 34.0
    public static let PillHeight: Float = pillHeight

    public static func settingLabel(_ language: Language, _ index: Int) -> String {
        switch index {
        case 0:
            switch language {
            case .ja, .zt: return "自動"
            case .zc: return "自动"
            default: return "Auto"
            }
        case 1:
            switch language {
            case .ja: return "キーボード"
            case .zc: return "键盘"
            case .zt: return "鍵盤"
            default: return "Keyboard"
            }
        case 2: return "PlayStation"
        default: return "Xbox"
        }
    }
    public static func SettingLabel(_ language: Language, _ index: Int) -> String { settingLabel(language, index) }

    public static func settingHeading(_ language: Language) -> String {
        switch language {
        case .ja: return "ボタン表示"
        case .zc: return "按键提示"
        case .zt: return "按鍵提示"
        default: return "Button Prompts"
        }
    }
    public static func SettingHeading(_ language: Language) -> String { settingHeading(language) }

    public static func displayHeading(_ language: Language) -> String {
        switch language {
        case .ja: return "画面モード"
        case .zc: return "显示模式"
        case .zt: return "顯示模式"
        default: return "Display Mode"
        }
    }
    public static func DisplayHeading(_ language: Language) -> String { displayHeading(language) }

    public static func displayLabel(_ language: Language, _ index: Int) -> String {
        if index == 0 {
            switch language {
            case .ja: return "ウィンドウ"
            case .zc: return "窗口"
            case .zt: return "視窗"
            default: return "Windowed"
            }
        } else {
            switch language {
            case .ja: return "フルスクリーン"
            case .zc: return "全屏"
            case .zt: return "全螢幕"
            default: return "Fullscreen"
            }
        }
    }
    public static func DisplayLabel(_ language: Language, _ index: Int) -> String { displayLabel(language, index) }

    public static func displayPillWidth(_ index: Int) -> Float { index == 0 ? 156.0 : 178.0 }
    public static func DisplayPillWidth(_ index: Int) -> Float { displayPillWidth(index) }

    public static func sizeHeading(_ language: Language) -> String {
        switch language {
        case .ja: return "ウィンドウサイズ"
        case .zc: return "窗口大小"
        case .zt: return "視窗大小"
        default: return "Window Size"
        }
    }
    public static func SizeHeading(_ language: Language) -> String { sizeHeading(language) }

    public static func sizeLabel(_ width: Int, _ height: Int) -> String { "\(width)x\(height)" }
    public static func SizeLabel(_ width: Int, _ height: Int) -> String { sizeLabel(width, height) }

    public static let sizePillWidth: Float = 150.0
    public static let SizePillWidth: Float = sizePillWidth

    public static func screenshotNoticeHeading(_ language: Language) -> String {
        switch language {
        case .ja: return "スクリーンショット^通知"
        case .zc: return "截图提示"
        case .zt: return "螢幕截圖通知"
        default: return "Screenshot Notice"
        }
    }
    public static func ScreenshotNoticeHeading(_ language: Language) -> String { screenshotNoticeHeading(language) }

    public static func copyTextHeading(_ language: Language) -> String {
        switch language {
        case .ja: return "テキストをコピー"
        case .zc: return "复制文本到剪贴板"
        case .zt: return "複製文字"
        default: return "Copy Text to^Clipboard"
        }
    }
    public static func CopyTextHeading(_ language: Language) -> String { copyTextHeading(language) }

    public static func textHookerHeading(_ language: Language) -> String {
        switch language {
        case .ja: return "テキストフッカー出力"
        case .zc: return "文本钩子输出"
        case .zt: return "文字鉤子輸出"
        default: return "Text Hooker^Output"
        }
    }
    public static func TextHookerHeading(_ language: Language) -> String { textHookerHeading(language) }

    public static func webSocketHeading(_ language: Language) -> String {
        switch language {
        case .ja: return "テキスト WebSocket"
        case .zc: return "文本 WebSocket"
        case .zt: return "文字 WebSocket"
        default: return "Text WebSocket"
        }
    }
    public static func WebSocketHeading(_ language: Language) -> String { webSocketHeading(language) }

    public static func opacityHeading(_ language: Language) -> String {
        switch language {
        case .ja: return "ウィンドウの不透明度"
        case .zc: return "文本框不透明度"
        case .zt: return "文字框不透明度"
        default: return "Text Window^Opacity"
        }
    }
    public static func OpacityHeading(_ language: Language) -> String { opacityHeading(language) }

    public static func muteHeading(_ language: Language) -> String {
        switch language {
        case .ja: return "バックグラウンドで消音"
        case .zc: return "后台静音"
        case .zt: return "背景靜音"
        default: return "Mute in Background"
        }
    }
    public static func MuteHeading(_ language: Language) -> String { muteHeading(language) }

    public static func switchLabel(_ language: Language, _ index: Int) -> String {
        if index == 0 {
            switch language {
            case .ja: return "オフ"
            case .zc: return "关"
            case .zt: return "關"
            default: return "Off"
            }
        } else {
            switch language {
            case .ja: return "オン"
            case .zc: return "开"
            case .zt: return "開"
            default: return "On"
            }
        }
    }
    public static func SwitchLabel(_ language: Language, _ index: Int) -> String { switchLabel(language, index) }

    public static let switchPillWidth: Float = 100.0
    public static let SwitchPillWidth: Float = switchPillWidth

    public static func percentLabel(_ percent: Int) -> String { "\(percent)%" }
    public static func PercentLabel(_ percent: Int) -> String { percentLabel(percent) }

    public static func textWidth(_ p: UiPainter, _ text: String, scale: Double = 0.4, translated: Bool = true) -> Float {
        let drawer = translated ? p.labelText : p.keyText
        var style = keyStyle
        style.sx = scale
        style.sy = scale * (448.0 / 360.0)
        style.colour = TextStyle.white
        return drawer.inkSpan(text, style).right
    }
    public static func TextWidth(_ p: UiPainter, _ text: String, _ scale: Double = 0.4, _ translated: Bool = true) -> Float {
        textWidth(p, text, scale: scale, translated: translated)
    }

    public static func drawPill(_ p: UiPainter, _ text: String, _ r: RectF, selected: Bool, hover: Bool, alpha: Float, translated: Bool = false) {
        let edge: Float = hover ? 1.0 : 0.72
        p.fillRounded(r, radius: 9.0, r: 0.62 * edge, g: 0.86 * edge, b: 1.0 * edge, a: (hover || selected ? 0.98 : 0.8) * alpha)
        let inner = RectF(r.x + border, r.y + border, r.w - (2.0 * border), r.h - (2.0 * border))
        if selected {
            p.fillRounded(inner, radius: 7.0, r: 0.12, g: 0.42, b: 0.86, a: 0.96 * alpha, smooth: false)
        } else {
            p.fillRounded(inner, radius: 7.0, r: 0.03, g: 0.07, b: 0.16, a: (hover ? 0.9 : 0.78) * alpha, smooth: false)
        }
        drawLabel(p, text, r.x + (r.w / 2.0), r.y + (r.h / 2.0), alpha, TextStyle.white, scale: 0.36, translated: translated)
    }
    public static func DrawPill(_ p: UiPainter, _ text: String, _ r: RectF, _ selected: Bool, _ hover: Bool, _ alpha: Float, _ translated: Bool = false) {
        drawPill(p, text, r, selected: selected, hover: hover, alpha: alpha, translated: translated)
    }

    public static func drawText(_ p: UiPainter, _ text: String, _ x: Float, _ cy: Float, _ alpha: Float, scale: Double = 0.4, translated: Bool = true) {
        if text.isEmpty {
            return
        }
        let drawer = translated ? p.labelText : p.keyText
        var style = keyStyle
        style.sx = scale
        style.sy = scale * (448.0 / 360.0)
        style.colour = TextStyle.white
        let th = drawer.height(text, style) * UiMetrics.unitY
        drawer.draw(p, text, style, x / UiMetrics.unitX, (cy - (th / 2.0) + fudge) / UiMetrics.unitY, alpha)
    }
    public static func DrawText(_ p: UiPainter, _ text: String, _ x: Float, _ cy: Float, _ alpha: Float, _ scale: Double = 0.4, _ translated: Bool = true) {
        drawText(p, text, x, cy, alpha, scale: scale, translated: translated)
    }

    public static func drawPressAnyKey(_ p: UiPainter, _ alpha: Float) {
        let text = "PRESS ANY KEY"
        let style = TextStyle(
            canvasW: 640, canvasH: 448, sx: 0.46, sy: 0.46 * (448.0 / 360.0),
            width: 600, height: 80, leading: 0, spacing: 4, colour: TextStyle.rgb565(184, 198, 222)
        )
        let w = p.keyText.width(text, style) * UiMetrics.unitX
        let h = p.keyText.height(text, style) * UiMetrics.unitY
        p.keyText.draw(p, text, style, (960.0 - (w / 2.0)) / UiMetrics.unitX, (858.0 - (h / 2.0) + fudge) / UiMetrics.unitY, alpha)
    }
    public static func DrawPressAnyKey(_ p: UiPainter, _ alpha: Float) {
        drawPressAnyKey(p, alpha)
    }

    private static func bitCount(_ mask: Int) -> Int {
        UInt32(mask).nonzeroBitCount
    }

    private static func capWidth(_ p: UiPainter, _ text: String) -> Float {
        let textW = p.keyText.width(text, keyStyle) * UiMetrics.unitX
        return max(capHeight, ceil(textW) + (2.0 * padX))
    }

    private static func drawCap(_ p: UiPainter, _ text: String, _ x: Float, _ bottom: Float, _ w: Float, _ alpha: Float) {
        let top = bottom - capHeight
        p.fillRounded(RectF(x, top, w, capHeight), radius: radius, r: 0.93, g: 0.95, b: 1.0, a: 0.95 * alpha)
        p.fillRounded(RectF(x + border, top + border, w - (2.0 * border), capHeight - (2.0 * border)), radius: radius - border, r: 0.03, g: 0.07, b: 0.16, a: 0.92 * alpha, smooth: false)
        drawLabel(p, text, x + (w / 2.0), top + (capHeight / 2.0), alpha, TextStyle.white)
    }

    private static func drawLabel(_ p: UiPainter, _ text: String, _ cx: Float, _ cy: Float, _ alpha: Float, _ colour: Int, scale: Double = 0.32, translated: Bool = false) {
        if text.isEmpty {
            return
        }
        let drawer = translated ? p.labelText : p.keyText
        var style = keyStyle
        style.colour = colour
        style.sx = scale
        style.sy = scale * (448.0 / 360.0)
        let tw = drawer.width(text, style) * UiMetrics.unitX
        let th = drawer.height(text, style) * UiMetrics.unitY
        drawer.draw(p, text, style, (cx - (tw / 2.0)) / UiMetrics.unitX, (cy - (th / 2.0) + fudge) / UiMetrics.unitY, alpha)
    }

    private static func drawArrows(_ p: UiPainter, _ mask: Int, _ x: Float, _ bottom: Float, _ w: Float, _ alpha: Float) {
        let top = bottom - capHeight
        p.fillRounded(RectF(x, top, w, capHeight), radius: radius, r: 0.93, g: 0.95, b: 1.0, a: 0.95 * alpha)
        p.fillRounded(RectF(x + border, top + border, w - (2.0 * border), capHeight - (2.0 * border)), radius: radius - border, r: 0.03, g: 0.07, b: 0.16, a: 0.92 * alpha, smooth: false)
        let order = [PromptItem.left, PromptItem.up, PromptItem.down, PromptItem.right]
        let n = bitCount(mask)
        let slot = (w - 12.0) / Float(max(1, n))
        var cx = x + 6.0 + (slot / 2.0)
        let cy = top + (capHeight / 2.0)
        for dir in order {
            if (mask & dir) == 0 {
                continue
            }
            arrow(p, dir, cx, cy, alpha)
            cx += slot
        }
    }

    private static func arrow(_ p: UiPainter, _ dir: Int, _ cx: Float, _ cy: Float, _ alpha: Float) {
        let rows = 7
        for i in 0..<rows {
            let run = 1.0 + (2.0 * Float(i))
            switch dir {
            case PromptItem.up:
                p.fill(RectF(cx - (run / 2.0), cy - 4.0 + Float(i), run, 1.0), r: 1.0, g: 1.0, b: 1.0, a: alpha)
            case PromptItem.down:
                p.fill(RectF(cx - (run / 2.0), cy + 3.0 - Float(i), run, 1.0), r: 1.0, g: 1.0, b: 1.0, a: alpha)
            case PromptItem.left:
                p.fill(RectF(cx - 4.0 + Float(i), cy - (run / 2.0), 1.0, run), r: 1.0, g: 1.0, b: 1.0, a: alpha)
            default:
                p.fill(RectF(cx + 3.0 - Float(i), cy - (run / 2.0), 1.0, run), r: 1.0, g: 1.0, b: 1.0, a: alpha)
            }
        }
    }

    private static func drawMouse(_ p: UiPainter, _ x: Float, _ bottom: Float, _ alpha: Float) {
        let w: Float = 24.0
        let top = bottom - capHeight
        p.fillRounded(RectF(x, top, w, capHeight), radius: 10.0, r: 0.93, g: 0.95, b: 1.0, a: 0.95 * alpha)
        p.fillRounded(RectF(x + border, top + border, w - (2.0 * border), capHeight - (2.0 * border)), radius: 8.0, r: 0.03, g: 0.07, b: 0.16, a: 0.92 * alpha, smooth: false)
        p.fill(RectF(x + border, top + 13.0, w - (2.0 * border), 1.0), r: 0.93, g: 0.95, b: 1.0, a: 0.9 * alpha)
        p.fillRounded(RectF(x + (w / 2.0) - 2.0, top + 5.0, 4.0, 9.0), radius: 2.0, r: 0.49, g: 0.84, b: 1.0, a: alpha)
    }

    private static func drawFace(_ p: UiPainter, _ item: PromptItem, _ x: Float, _ bottom: Float, _ alpha: Float) {
        let top = bottom - capHeight
        let clampedMask = min(max(item.mask, 0), 3)
        let (r, g, b) = faceColours[clampedMask]
        p.fillRounded(RectF(x, top, capHeight, capHeight), radius: capHeight / 2.0, r: 0.93, g: 0.95, b: 1.0, a: 0.95 * alpha)
        p.fillRounded(RectF(x + border, top + border, capHeight - (2.0 * border), capHeight - (2.0 * border)), radius: (capHeight / 2.0) - border, r: 0.03, g: 0.07, b: 0.16, a: 0.92 * alpha, smooth: false)
        drawLabel(p, item.text, x + (capHeight / 2.0), top + (capHeight / 2.0), alpha, TextStyle.rgb565(r, g, b))
    }

    private static func drawDpad(_ p: UiPainter, _ mask: Int, _ x: Float, _ bottom: Float, _ alpha: Float) {
        let top = bottom - capHeight
        let cx = x + (capHeight / 2.0)
        let cy = top + (capHeight / 2.0)
        let arm: Float = 11.0
        let half: Float = 5.0

        p.fillRounded(RectF(cx - arm - 1.0, cy - half - 1.0, (2.0 * arm) + 2.0, (2.0 * half) + 2.0), radius: 3.0, r: 0.03, g: 0.07, b: 0.16, a: 0.9 * alpha)
        p.fillRounded(RectF(cx - half - 1.0, cy - arm - 1.0, (2.0 * half) + 2.0, (2.0 * arm) + 2.0), radius: 3.0, r: 0.03, g: 0.07, b: 0.16, a: 0.9 * alpha)
        p.fillRounded(RectF(cx - arm, cy - half, 2.0 * arm, 2.0 * half), radius: 2.0, r: 0.93, g: 0.95, b: 1.0, a: alpha)
        p.fillRounded(RectF(cx - half, cy - arm, 2.0 * half, 2.0 * arm), radius: 2.0, r: 0.93, g: 0.95, b: 1.0, a: alpha)

        func lit(_ dir: Int, _ r: RectF) {
            if (mask & dir) != 0 && mask != (PromptItem.up | PromptItem.down | PromptItem.left | PromptItem.right) {
                p.fillRounded(r, radius: 2.0, r: 0.38, g: 0.74, b: 1.0, a: alpha)
            }
        }

        lit(PromptItem.up, RectF(cx - half + 1.0, cy - arm + 1.0, (2.0 * half) - 2.0, arm - half))
        lit(PromptItem.down, RectF(cx - half + 1.0, cy + half, (2.0 * half) - 2.0, arm - half - 1.0))
        lit(PromptItem.left, RectF(cx - arm + 1.0, cy - half + 1.0, arm - half, (2.0 * half) - 2.0))
        lit(PromptItem.right, RectF(cx + half, cy - half + 1.0, arm - half - 1.0, (2.0 * half) - 2.0))
    }
}
