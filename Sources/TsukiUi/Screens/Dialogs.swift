// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Ported from knife (https://github.com/AuroraWright/knife) by AuroraWright: knife/src/ui.rs (Confirm, Popup, DlgOut, draw_dialog_*)
import Foundation
import TsukiCore
import TsukiEngine

/// The confirm dialogs of the menus (knife `Confirm`; the number is knife's dialog id, whose message the eboot's dialog table gives).
public enum ConfirmKind: Int, Sendable {
    /// System menu Title during an archive scene (dialog 8, Yes first).
    case title
    /// Overwrite a save (dialog 2, No first).
    case overwrite
    /// Load a save (dialog 0, Yes first).
    case load
    /// Mode panel: previous scene (dialog 11, No first).
    case prevScene
    /// Mode panel: next scene (dialog 10, No first).
    case nextScene
    /// Mode panel: quick load (dialog 9, No first; shows the quick save's thumbnail).
    case quickLoad
    /// Config: Recommended Settings (ui_text 160, No first).
    case defaults
    /// Backlog quick jump (dialog 23, No first).
    case backlogJump
    /// Save list: delete the save (dialog 21, No first).
    case delete
    /// Save list: copy the save (dialog 22, No first).
    case copy
    /// System menu FlowChart during a replay picked in the gallery's flowchart: end the replay (dialog 12, Yes first; package K5b).
    case endReplay
}

/// A Yes / No confirm dialog.
public final class ConfirmDialog: UiScreen {
    private let _kind: ConfirmKind
    private let _customMessage: Int
    private let _customNo: Bool
    private let _answer: (Bool) -> Void
    private let _thumbSlot: Int
    private let _items = UiItemList()
    private var _t: Float = 0
    private var _hold: Int = -1
    private var _yes: Bool = false
    private var _acted: Bool = false

    /// Creates a dialog of `kind`; `answer` is called with the answer once the hold has run out.
    public init(_ kind: ConfirmKind, _ answer: @escaping (Bool) -> Void, thumbnailSlot: Int = -1) {
        _kind = kind
        _customMessage = -1
        _customNo = true
        _answer = answer
        _thumbSlot = thumbnailSlot
        super.init()
    }

    public init(kind: ConfirmKind, answer: @escaping (Bool) -> Void, thumbnailSlot: Int = -1) {
        _kind = kind
        _customMessage = -1
        _customNo = true
        _answer = answer
        _thumbSlot = thumbnailSlot
        super.init()
    }

    /// Creates a dialog with a message of the caller's choice (the `ui_text` id `messageId`).
    public init(_ messageId: Int, _ noFirst: Bool, _ answer: @escaping (Bool) -> Void) {
        _kind = .endReplay
        _customMessage = messageId
        _customNo = noFirst
        _answer = answer
        _thumbSlot = -1
        super.init()
    }

    public init(messageId: Int, noFirst: Bool, answer: @escaping (Bool) -> Void) {
        _kind = .endReplay
        _customMessage = messageId
        _customNo = noFirst
        _answer = answer
        _thumbSlot = -1
        super.init()
    }

    /// True while the dialog still waits for an answer.
    public var waiting: Bool { _hold < 0 && !closing }
    public var Waiting: Bool { waiting }

    /// The cursor is on Yes.
    public var cursorOnYes: Bool { _items.cursor == 0 }
    public var CursorOnYes: Bool { cursorOnYes }

    /// knife dialog id and whether the cursor starts on No.
    private var info: (dialog: Int, no: Bool) {
        if _customMessage >= 0 {
            return (-1, _customNo)
        }
        switch _kind {
        case .title: return (8, false)
        case .overwrite: return (2, true)
        case .load: return (0, false)
        case .prevScene: return (11, true)
        case .nextScene: return (10, true)
        case .quickLoad: return (9, true)
        case .backlogJump: return (23, true)
        case .delete: return (21, true)
        case .copy: return (22, true)
        case .endReplay: return (12, false)
        default: return (-1, true)
        }
    }

    /// The `ui_text` id of the message.
    public func messageId(_ assets: UiAssets) -> Int {
        if _kind == .defaults {
            return UiAssets.sysmes(160)
        }
        if _customMessage >= 0 {
            return _customMessage
        }
        let d = info.dialog
        let index = d >= 21 ? d + 2 : d
        let ids = assets.tables.dialogMessages
        return index < ids.count ? ids[index] : -1
    }

    public func MessageId(_ assets: UiAssets) -> Int {
        messageId(assets)
    }

    private var thumbnail: Bool { _kind == .quickLoad }

    public override func onOpened() {
        let y: Float = thumbnail ? 261.46 : 249.01
        // Yes (object 0) at x 330 and No (object 1) at x 252; touch rect (0, -2)-(72, 24)
        _items.add(Self.objectRect(330, y), 0)
        _items.add(Self.objectRect(252, y), 1)
        _items.cursor = info.no ? 1 : 0
        ctx.sound(.open)
    }

    public override func OnOpened() {
        onOpened()
    }

    private static func objectRect(_ x: Float, _ y: Float) -> RectF {
        RectF(
            trunc(x) * UiMetrics.unitX,
            (trunc(y) - 2.0) * UiMetrics.unitY,
            73.0 * UiMetrics.unitX,
            27.0 * UiMetrics.unitY
        )
    }

    public override func step(_ input: UiInput) {
        if _hold >= 0 {
            if _hold > 0 {
                _hold -= 1
            } else {
                if !_acted {
                    _acted = true
                    _answer(_yes)
                }
                fadeOut()
            }
            return
        }

        _t = min(1.0, _t + 0.07)
        if _t < 1.0 {
            return
        }

        if input.cancel {
            ctx.sound(.buzzer)
            _yes = false
            _hold = 1
            return
        }

        if input.up || input.down || input.left || input.right {
            _items.cursor = _items.cursor == 1 ? 0 : 1
            ctx.sound(.cursor)
        }

        if _items.hover(input) {
            ctx.sound(.cursor)
        }

        let hit = _items.clicked(input)
        if hit >= 0 || (input.decide && !input.click) {
            if hit >= 0 {
                _items.cursor = hit
            }
            _yes = _items.cursor == 0
            ctx.sound(.decide)
            _hold = 15
        }
    }

    public override func Step(_ input: UiInput) {
        step(input)
    }

    public override func stepBackground() {
        if _acted {
            fadeOut()
        }
    }

    public override func StepBackground() {
        stepBackground()
    }

    private func fadeOut() {
        _t -= 0.07
        if _t <= 0 {
            close()
        }
    }

    public override func draw(_ p: UiPainter) {
        let t = _t
        p.sprite(UiSheets.dialogBackdrop, UiMetrics.screen, t * 0.75)
        let d = (1.0 - t) * 0.2
        let k = _acted && _yes ? 1.0 - d : 1.0 + d
        UiWidgets.dialogWindow(p, alpha: t, scale: k * k)
        if _t < 1.0 {
            return
        }

        let msg = ctx.message(messageId(ctx.assets))
        Self.dialogText(p, ctx, msg, thumbnail ? 160.0 : 184.0, 0)
        if thumbnail && _thumbSlot >= 0 {
            drawThumbnail(p, ctx.services.thumbnail(_thumbSlot), _thumbSlot)
        }

        let by: Float = thumbnail ? 261.46 : 249.01
        for i in 0..<2 {
            let yes = i == 0
            UiDialogButtons.draw(p, ctx, yes: yes, selected: _items.cursor == i, x: yes ? 990.0 : 756.0, y: by * UiMetrics.unitY)
        }
    }

    public override func Draw(_ p: UiPainter) {
        draw(p)
    }

    /// The width of the dark inner area of the 824 px `dialog_win` (x 566..1347 of the rendered window, package R1).
    public static let dialogInnerWidth: Float = 782.0
    public static let DialogInnerWidth: Float = dialogInnerWidth

    /// The widest ink a line of a dialog message may have: the inner area less 11 px on each side.
    public static let dialogTextWidth: Float = 760.0
    public static let DialogTextWidth: Float = dialogTextWidth

    /// A dialog message: scale 0.6 x 0.7 of the base glyph, lines centred from `top` (units of 448), `^` breaks lines.
    public static func dialogText(_ p: UiPainter, _ ctx: UiContext, _ message: String, _ top: Float, _ lineSpacing: Float) {
        ctx.text.draw(p, message, dialogStyle(ctx.text, message, lineSpacing), 0, top)
    }

    public static func DialogText(_ p: UiPainter, _ ctx: UiContext, _ message: String, _ top: Float, _ lineSpacing: Float) {
        dialogText(p, ctx, message, top, lineSpacing)
    }

    /// The style of a dialog message.
    public static func dialogStyle(_ text: UiText, _ message: String, _ lineSpacing: Float) -> TextStyle {
        var style = TextStyle.slot(0.6, 0.7)
        style.width = 640
        style.height = 200
        style.leading = Int(round(lineSpacing + 6.0))
        style.drawFlags = BlockDraw.always | BlockDraw.outline | BlockDraw.center
        var widest: Float = 0
        let lines = message.split(separator: "^", omittingEmptySubsequences: false)
        for line in lines {
            let span = text.inkSpan(String(line), style)
            widest = max(widest, span.right - span.left)
        }

        if widest <= dialogTextWidth {
            return style
        }

        let k = Double(dialogTextWidth / widest)
        style.sx *= k
        style.sy *= k
        return style
    }

    public static func DialogStyle(_ text: UiText, _ message: String, _ lineSpacing: Float) -> TextStyle {
        dialogStyle(text, message, lineSpacing)
    }

    /// The top of the quick save's thumbnail frame in units of 448: 212 in English, else 200.
    public static func thumbnailTop(_ language: Language) -> Float {
        language == .en ? 212.0 : 200.0
    }

    public static func ThumbnailTop(_ language: Language) -> Float {
        thumbnailTop(language)
    }

    private func drawThumbnail(_ p: UiPainter, _ thumb: UiThumbnail?, _ slot: Int) {
        guard let thumb = thumb else { return }
        let w: Float = 100.0 * 0.82667 * 0.825
        let h: Float = 53.0 * 1.0859 * 0.825
        let y = Self.thumbnailTop(ctx.language)
        p.fill(RectF((318.0 - (w / 2.0)) * UiMetrics.unitX, y * UiMetrics.unitY, (w + 4.0) * UiMetrics.unitX, (h + 4.0) * UiMetrics.unitY), r: 0, g: 0, b: 0, a: 1)
        p.thumbnail(slot, version: thumb.version, dst: RectF((320.0 - (w / 2.0)) * UiMetrics.unitX, (y + 2.0) * UiMetrics.unitY, w * UiMetrics.unitX, h * UiMetrics.unitY))
    }
}

/// A black message popup: `dialog_win` with the message centred, fading in and out at 0.07 per frame.
public final class MessagePopup: UiScreen {
    private let _message: String
    private let _held: Bool
    private let _minimum: Float
    private var _frames: Float
    private var _a: Float = 0
    private var _closing: Bool = false
    private var _released: Bool = false
    private var _age: Float = 0

    /// Creates a popup.
    public init(_ message: String, frames: Float = 480.0, held: Bool = false, minimumFrames: Float = 0.0) {
        _message = message
        _frames = frames
        _held = held
        _minimum = minimumFrames
        super.init()
    }

    public init(message: String, frames: Float = 480.0, held: Bool = false, minimumFrames: Float = 0.0) {
        _message = message
        _frames = frames
        _held = held
        _minimum = minimumFrames
        super.init()
    }

    /// The text (`^` breaks lines).
    public var message: String { _message }
    public var Message: String { _message }

    /// The window alpha 0..1.
    public var alpha: Float { _a }
    public var Alpha: Float { _a }

    /// True while the popup is fully shown.
    public var fullyShown: Bool { _a >= 1.0 }
    public var FullyShown: Bool { fullyShown }

    /// Lets a held popup go (it still stays for its minimum time).
    public func release() {
        _released = true
    }
    public func Release() {
        release()
    }

    public override func step(_ input: UiInput) {
        _age += 1
        if _held {
            if _released && _age >= _minimum {
                _closing = true
            }
        } else if input.any || input.decide || input.cancel {
            _closing = true
        }

        if _closing {
            _a -= 0.07
            if _a <= 0 {
                close()
            }
        } else if _a < 1.0 {
            _a = min(1.0, _a + 0.07)
        } else if !_held {
            _frames -= 1
            _closing = _frames < 1.0
        }
    }

    public override func Step(_ input: UiInput) {
        step(input)
    }

    public override func draw(_ p: UiPainter) {
        let scale = Float(pow(Double(1.0 - ((1.0 - _a) * 0.2)), 2.0))
        UiWidgets.dialogWindow(p, alpha: _a, scale: scale)
        if _a >= 1.0 {
            ConfirmDialog.dialogText(p, ctx, _message, 214.0, 4.0)
        }
    }

    public override func Draw(_ p: UiPainter) {
        draw(p)
    }
}
