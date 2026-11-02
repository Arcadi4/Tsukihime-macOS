// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Ported from knife (https://github.com/AuroraWright/knife) by AuroraWright: knife/src/ui/touch.rs (Panel, panel_y, panel_button, panel_press, draw_touch_game)
import Foundation
import TsukiCore
import TsukiEngine

/// The mode panel: a bar that slides down from the top of the story with eight buttons.
public final class ModePanelScreen: UiScreen {
    /// The first button's x in units of 640 x 448 (widget 0xCB at x = 25.333 + 73.667 i).
    public static let x0: Float = 25.333
    public static let X0: Float = x0

    /// The distance between buttons in units.
    public static let dx: Float = 73.667
    public static let Dx: Float = dx

    /// The buttons' y below the bar's top in units.
    public static let buttonY: Float = 6.637
    public static let ButtonY: Float = buttonY

    private static let buttonW: Float = 224.0
    private static let buttonH: Float = 64.0

    private var _flash: [Float] = [Float](repeating: 0, count: 8)
    private var _t: Float = 0
    private var _closing: Bool = false
    private var _key: Int = 3
    private var _hover: Int = -1
    private var _held: Int = -1
    private var _opened: Bool = false

    public override init() {
        super.init()
    }

    /// The button the pad has (the last one picked; the panel starts on skip).
    public var key: Int { _key }
    public var Key: Int { _key }

    /// The button under the pointer, or -1.
    public var hover: Int { _hover }
    public var Hover: Int { _hover }

    /// The slide 0..1.
    public var slide: Float { _t }
    public var Slide: Float { _t }

    /// True once the bar has slid fully open.
    public var isOpen: Bool { _opened && !_closing }
    public var IsOpen: Bool { isOpen }

    /// The bar's top in units: -43.14 hidden, 0 open (quad-out over the slide).
    public var panelY: Float {
        -43.14 - (43.14 * _t * (_t - 2.0))
    }
    public var PanelY: Float { panelY }

    /// Hit rectangle of button `i` in canvas pixels.
    public func buttonRect(_ i: Int) -> RectF {
        RectF((Self.x0 + (Self.dx * Float(i))) * UiMetrics.unitX, (panelY + Self.buttonY) * UiMetrics.unitY, Self.buttonW, Self.buttonH)
    }
    public func ButtonRect(_ i: Int) -> RectF {
        buttonRect(i)
    }

    /// Whether button `i` is unavailable (drawn in the first row of its column).
    public func disabled(_ i: Int) -> Bool {
        let s = ctx.services
        switch i {
        case 0, 4:
            return !s.sceneJumpEnabled
        case 5:
            return s.savingDisabled
        case 6:
            return s.savingDisabled || !s.hasQuickSave
        default:
            return false
        }
    }
    public func Disabled(_ i: Int) -> Bool {
        disabled(i)
    }

    public override func onOpened() {
        ctx.sound(.cursor)
    }
    public override func OnOpened() {
        onOpened()
    }

    public override func close() {
        _closing = true
        releaseHeld()
    }
    public override func Close() {
        close()
    }

    private func releaseHeld() {
        if _held == 1 {
            ctx.services.rewind(false)
        } else if _held == 3 {
            ctx.services.fastForward(false)
        }
        _held = -1
    }

    public override func stepBackground() {
        animate()
    }
    public override func StepBackground() {
        stepBackground()
    }

    private func animate() {
        for i in 0..<_flash.count {
            _flash[i] = max(0.0, _flash[i] - 1.0)
        }

        if _closing {
            _t -= 0.05
            if _t <= 0 {
                _t = 0
                super.close()
            }
            return
        }

        if !_opened {
            _t += 0.05
            if _t >= 1.0 {
                _t = 1.0
                _opened = true
            }
        }
    }

    public override func step(_ input: UiInput) {
        animate()
        if _closing || !_opened {
            return
        }

        if root?.top !== self {
            return
        }

        if input.down || input.cancel || input.square || input.triangle {
            close()
            return
        }

        var nextKey = _key
        if input.right {
            nextKey = nextKey < 7 ? nextKey + 1 : (input.rightPressed ? 0 : nextKey)
        } else if input.left {
            nextKey = nextKey > 0 ? nextKey - 1 : (input.leftPressed ? 7 : nextKey)
        }

        if nextKey != _key {
            _key = nextKey
            _hover = -1
            ctx.sound(.cursor)
        }

        if input.pointerMoved {
            let hit = buttonAt(input.pointerX, input.pointerY)
            if hit != _hover && hit >= 0 {
                ctx.sound(.cursor)
                _key = hit
            }
            _hover = hit
        }

        // buttons 1 (rewind) and 3 (skip) act while held
        var heldNow = -1
        if input.pointerHeld && (_hover == 1 || _hover == 3) {
            heldNow = _hover
        } else if input.decideHeld && _hover < 0 && (_key == 1 || _key == 3) {
            heldNow = _key
        }

        if heldNow != _held {
            releaseHeld()
            _held = heldNow
            if heldNow == 1 {
                ctx.services.rewind(true)
            } else if heldNow == 3 {
                ctx.services.fastForward(true)
            }
        }

        if input.click {
            let hit = buttonAt(input.pointerX, input.pointerY)
            if hit >= 0 {
                _key = hit
                press(hit)
            } else if input.pointerY > (panelY + 43.14) * UiMetrics.unitY {
                // a click below the bar closes it; the text does not advance
                close()
            }
        } else if input.decide && _key != 1 && _key != 3 {
            press(_key)
        }
    }

    public override func Step(_ input: UiInput) {
        step(input)
    }

    private func buttonAt(_ x: Float, _ y: Float) -> Int {
        for i in 0..<8 {
            if buttonRect(i).contains(x, y) {
                return i
            }
        }
        return -1
    }

    private func press(_ b: Int) {
        _flash[b] = 10.0
        let s = ctx.services
        if disabled(b) {
            ctx.sound(.buzzer)
            return
        }

        switch b {
        case 0:
            ctx.sound(.decide)
            root?.push(ConfirmDialog(.prevScene, { [weak self] yes in self?.jump(yes, previous: true) }))
        case 2:
            ctx.sound(.decide)
            s.toggleAuto()
            if s.autoMode {
                root?.showBanner(.auto)
            }
        case 4:
            ctx.sound(.decide)
            root?.push(ConfirmDialog(.nextScene, { [weak self] yes in self?.jump(yes, previous: false) }))
        case 5:
            ctx.sound(.decide)
            if s.quickSave() {
                root?.showBanner(.quickSave)
            }
        case 6:
            ctx.sound(.decide)
            root?.push(ConfirmDialog(.quickLoad, { [weak self] yes in
                if yes && s.quickLoad() {
                    self?.root?.clear()
                }
            }, thumbnailSlot: 139))
        case 7:
            s.replayVoice()
        default:
            break
        }
    }

    private func jump(_ yes: Bool, previous: Bool) {
        if !yes {
            return
        }
        if previous {
            ctx.services.previousScene()
        } else {
            ctx.services.nextScene()
        }
        close()
    }

    public override func draw(_ p: UiPainter) {
        if _t <= 0 {
            return
        }

        let y = panelY
        p.sprite(UiSheets.modeBar, RectF(0, 0, 1920, 96), RectF(0, y * UiMetrics.unitY, 1920, 96))
        let top = (y + Self.buttonY) * UiMetrics.unitY
        let dialog = root?.top !== self
        let focus = dialog ? -1 : (_hover >= 0 ? _hover : _key)
        for i in 0..<8 {
            let row: Int
            if i != 2 && disabled(i) {
                row = 0
            } else if _flash[i] > 0 || (i == 2 && ctx.services.autoMode) || _held == i {
                row = 3
            } else if focus == i {
                row = 2
            } else {
                row = 1
            }

            p.sprite(
                UiSheets.modeButtons,
                RectF(8.0 + (Float(i) * 232.0), 8.0 + (Float(row) * 72.0), Self.buttonW, Self.buttonH),
                RectF((Self.x0 + (Self.dx * Float(i))) * UiMetrics.unitX, top, Self.buttonW, Self.buttonH)
            )
        }
    }

    public override func Draw(_ p: UiPainter) {
        draw(p)
    }
}
