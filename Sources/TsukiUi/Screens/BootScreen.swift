// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Ported from knife (https://github.com/AuroraWright/knife) by AuroraWright
import Foundation
import TsukiCore
import TsukiEngine

/// The boot screen of the PS4 flow (docs/formats/system_flow.md 3.3 and 3.4 step 5).
public final class BootScreen: UiScreen {
    private var _a: Float = 0
    private var _hold: Int = 0
    private var _step: Int = 0
    private var _angle: Float = 0
    private var _pulse: Float = 0.3
    private var _pulseStep: Float = 0.02

    public override init() {
        super.init()
    }

    /// The notice alpha (it runs to 1.1 while fading in and to -0.1 while fading out, as the engine's fade does).
    public var alpha: Float { _a }
    public var Alpha: Float { _a }

    /// True while the notice shows.
    public var showing: Bool { _step < 3 }
    public var Showing: Bool { _step < 3 }

    public override var opaque: Bool { true }
    public override var Opaque: Bool { true }

    public override func step(_ input: UiInput) {
        _angle += 500.0 / 65536.0 * 2.0 * Float.pi
        _pulse += _pulseStep
        if _pulse >= 1.0 || _pulse <= 0.3 {
            _pulseStep = -_pulseStep
            _pulse = min(max(_pulse, 0.3), 1.0)
        }

        switch _step {
        case 0:
            _a += 0.025
            if _a >= 1.1 {
                _step = 1
            }
        case 1:
            _hold += 1
            if _hold >= 240 || input.any {
                _step = 2
            }
        case 2:
            _a -= 0.025
            if _a <= -0.1 {
                _step = 3
                root?.push(TitleScreen())
                close()
            }
        default:
            break
        }
    }

    public override func Step(_ input: UiInput) {
        step(input)
    }

    public override func draw(_ p: UiPainter) {
        p.cover(1.0)
        let a = min(max(_a, 0.0), 1.0)
        let langVal = ctx.language.rawValue
        let index = 8 + min(langVal, 4)
        p.picture(UiPicture(UiPictureArchive.parts, index), UiMetrics.screen, a)
        p.spriteRotated(UiSheets.dispSpinner, RectF(0, 0, 160, 160), RectF(1750, 955, 80, 80), _angle, a)
        p.sprite(UiSheets.dispSaving, RectF(0, 0, 128, 56), RectF(1762, 983, 64, 28), a * _pulse)
        p.sprite(UiSheets.dispGlow, RectF(0, 0, 160, 160), RectF(1750, 955, 80, 80), a, .psAdd)
    }

    public override func Draw(_ p: UiPainter) {
        draw(p)
    }
}
