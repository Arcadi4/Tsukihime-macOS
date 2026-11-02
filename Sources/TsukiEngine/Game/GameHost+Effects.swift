import Foundation
import TsukiCore

extension GameHost {
    func resetEffects() {
        focus.reset()
        ghost.reset()
    }

    /// The focus effect's mode.
    public var focusState: FocusMode { focus.mode }

    /// The running focus effect id (0 none): 1..3 falling notes, 4..33 focus lines.
    public var focusEffectId: Int { focus.effect }

    /// The focus effect's fade level 0..1.
    public var focusLevel: Float { focus.level }

    /// The ghosting effect: 4 on, 5 fading out, 0 off.
    public var ghostMode: Int { ghost.mode }

    /// The ghosting effect's alpha 0..1.
    public var ghostAlpha: Float { ghost.alpha }

    func startFocus(_ effect: Int, _ frames: Int) {
        focus.start(effect, frames)
    }

    func cmdFocus(_ st: Statement, _ cmd: Cmd) -> StepResult {
        let a = StageArgs(st)
        noteLayerChange(st)
        let effect: Int
        let frames: Int
        switch cmd {
        case .fcln:
            effect = a.has(5) ? a.expr(5) : 0
            frames = 0
        case .fcsp:
            effect = 0
            frames = 60 * (a.has(0) ? a.expr(0) : 0) / 1000
        case .flnt:
            effect = 1
            frames = 0
        case .flop:
            effect = (a.has(0) && a.expr(0) == 5) ? 2 : 3
            frames = 0
        case .flsp:
            effect = 0
            frames = 48
        default:
            effect = 0
            frames = 0
        }

        stage.scene.effect19A2 = UInt8(truncatingIfNeeded: effect)
        startFocus(effect, frames)
        return StepResult.continue
    }

    func restoreEffects() {
        if f(1100) == 4 {
            ghost.restore(f(1120) - 127, f(1121))
        }

        startFocus(Int(stage.scene.effect19A2), 0)
    }

    func cmdFade(_ st: Statement) -> StepResult {
        let a = StageArgs(st)
        noteLayerChange(st)
        let mode = a.has(0) ? a.expr(0) : 0
        if mode == 40 {
            let reset = f(1100) == 0
            let p = a.has(1) ? a.expr(1) : 0
            let q = a.has(2) ? a.expr(2) : 0
            setF(1100, 4)
            setF(1120, p + 127)
            setF(1121, q)
            ghost.start(p, q, reset)
        } else if mode == 41 {
            setF(1100, 0)
            ghost.setMode(5, 0, 0)
        }

        return StepResult.continue
    }

    func updateEffects(_ step: Int) {
        let frames = max(1, step)
        focus.step(frames)
        ghost.step(frames, f(1120) - 127, f(1121))
    }

    func drawScreenEffects(_ list: DisplayList) {
        if ghost.active {
            ghost.draw(list, stage.transitionActive ? 1.0 - stage.transitionProgress : nil)
        }

        if focus.active && f(963) != 1 {
            focus.draw(list)
        }
    }
}
