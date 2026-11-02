import Foundation
import TsukiCore

/// The wait bits of the u64 at VA 0x1653E00 (docs/formats/wait_model.md 3). The dead bits of section 3 are not modelled.
public enum WaitBits {
    /// The message text is being revealed (copy of `WaitState.flags` bit 0).
    public static let reveal: UInt64 = 0x1

    /// Wait for the voice (message flag bit 2, or `_VCWT`).
    public static let voice: UInt64 = 0x4

    /// `_FADS` transition running.
    public static let fads: UInt64 = 0x8

    /// Choice menu open.
    public static let choice: UInt64 = 0x10

    /// `_STCF` layer condition.
    public static let stcf: UInt64 = 0x20

    /// Message fully revealed, waiting to be dismissed.
    public static let shown: UInt64 = 0x40

    /// A message is displayed.
    public static let message: UInt64 = 0x100

    /// A system screen or fade state runs.
    public static let system: UInt64 = 0x200

    /// End mode 0: wait for a click (or auto / skip).
    public static let click: UInt64 = 0x400
}

/// The end mode of a message (wait_model.md 4.1).
public enum MessageEnd: UInt8, Sendable {
    /// `)`: wait for a click.
    case click = 0

    /// `@n`: no wait; the next `_MSAD` appends.
    case `continue` = 1

    /// `@e`, or `)` with the page option: no click.
    case noWait = 2
}

/// The ADV mode words of one frame (adv_state.md 6; `tsuki.wait_model.AdvMode`).
public struct AdvMode: Sendable {
    private static let stepTable: [Int] = [1, 1, 64, 64, 64]

    /// 0x17DB230: bit 0 auto mode, bit 1 latched skip.
    public var modeWord: Int = 0

    /// 0x17DB232: fast-forward active this frame.
    public var skipActive: Int = 0

    /// 0x17DB234: rewinding.
    public var rewind: Int = 0

    /// 0x17DB236: backlog shown.
    public var logShown: Int = 0

    /// 0x78AF80: the frame multiplier (1, or 64 while skipping).
    public var step: Int = 1

    /// 0xDC7BE0: vsyncs since the last update (1 at 60 Hz).
    public var vsync: Int = 1

    /// Frame count passed to both functions: `min(vsync, 3) * step` (0x61A81).
    public var frames: Int {
        max(0, min(vsync, 3)) * step
    }

    public init(modeWord: Int = 0, skipActive: Int = 0, rewind: Int = 0, logShown: Int = 0, step: Int = 1, vsync: Int = 1) {
        self.modeWord = modeWord
        self.skipActive = skipActive
        self.rewind = rewind
        self.logShown = logShown
        self.step = step
        self.vsync = vsync
    }

    /// The mode of a frame when no fast-forward or R2 is held (0x6120E..0x61261): a latched skip gives skip active and the step of table 0x2014F0.
    public static func fromModeWord(_ modeWord: Int, vsync: Int = 1) -> AdvMode {
        let mw = modeWord & 0xFFFF
        if mw < 2 {
            return AdvMode(modeWord: mw, skipActive: 0, rewind: 0, logShown: 0, step: 1, vsync: vsync)
        }
        let stepIdx = min(mw, stepTable.count - 1)
        return AdvMode(modeWord: mw, skipActive: 1, rewind: 0, logShown: 0, step: stepTable[stepIdx], vsync: vsync)
    }
}

/// The config fields the wait code reads (adv_state.md 9.2), copied from the `ConfigBlock` each frame.
public struct WaitConfig: Sendable {
    /// +0x20 ms per reveal counter (unseen text).
    public var textSpeedUnread: Int = 35

    /// +0x22 (seen text).
    public var textSpeedRead: Int = 15

    /// +0x2E auto-mode wait time (ms).
    public var autoWaitMs: Int = 2200

    /// +0x30 fast-forward: read text only.
    public var fastForwardReadOnly: Int = 1

    /// +0x4E interrupt voices on advancing text.
    public var interruptVoice: Int = 1

    /// +0x9C display end of page instantly (unseen).
    public var pageInstantUnread: Int = 0

    /// +0x9D (seen).
    public var pageInstantRead: Int = 0

    /// +0x9E auto-mode advance page speed (ms).
    public var autoPageMs: Int = 3000

    public init(
        textSpeedUnread: Int = 35,
        textSpeedRead: Int = 15,
        autoWaitMs: Int = 2200,
        fastForwardReadOnly: Int = 1,
        interruptVoice: Int = 1,
        pageInstantUnread: Int = 0,
        pageInstantRead: Int = 0,
        autoPageMs: Int = 3000
    ) {
        self.textSpeedUnread = textSpeedUnread
        self.textSpeedRead = textSpeedRead
        self.autoWaitMs = autoWaitMs
        self.fastForwardReadOnly = fastForwardReadOnly
        self.interruptVoice = interruptVoice
        self.pageInstantUnread = pageInstantUnread
        self.pageInstantRead = pageInstantRead
        self.autoPageMs = autoPageMs
    }

    /// Boot values (adv_state.md 9.2).
    public static var defaults: WaitConfig {
        WaitConfig()
    }

    /// Reads the fields from a config block.
    public static func from(_ c: ConfigBlock) -> WaitConfig {
        WaitConfig(
            textSpeedUnread: Int(c.unseenTextSpeed),
            textSpeedRead: Int(c.seenTextSpeed),
            autoWaitMs: Int(c.autoModeWait),
            fastForwardReadOnly: Int(c.fastForwardReadOnly),
            interruptVoice: Int(c.interruptVoices),
            pageInstantUnread: Int(c.pageEndInstantUnseen),
            pageInstantRead: Int(c.pageEndInstantSeen),
            autoPageMs: Int(c.autoModePageSpeed)
        )
    }
}

/// What the game input flow hands to the two wait functions for one frame (`tsuki.wait_model.FrameInput`).
public struct WaitInput: Sendable {
    /// The decide action mask of preset 0.
    public static let decide: UInt32 = 0x20

    /// R2.
    public static let r2: UInt32 = 0x2

    /// Game input word +0x10 (held).
    public var held: UInt32 = 0

    /// Game input word +0x20 (newly pressed).
    public var newly: UInt32 = 0

    /// Mouse flags: bit 0 left held, bit 1 left newly pressed.
    public var mouse: Int = 0

    /// Sum of the mouse wheel deltas read this frame.
    public var wheel: Int = 0

    /// 0xDF29E0: d-pad down newly pressed (and no HUD menu open).
    public var advKey: Int = 0

    public init(held: UInt32 = 0, newly: UInt32 = 0, mouse: Int = 0, wheel: Int = 0, advKey: Int = 0) {
        self.held = held
        self.newly = newly
        self.mouse = mouse
        self.wheel = wheel
        self.advKey = advKey
    }

    /// Builds the word from a frame input.
    public static func from(_ f: InputFrame) -> WaitInput {
        let mouse = (f.pointer.held.contains(.left) ? 1 : 0) | (f.pointer.pressed.contains(.left) ? 2 : 0)
        return WaitInput(
            held: f.held.rawValue,
            newly: f.pressed.rawValue,
            mouse: mouse,
            wheel: f.pointer.wheel,
            advKey: f.pressed.contains(.down) ? 1 : 0
        )
    }
}

/// What the two functions did in one frame (for the host and traces).
public struct WaitEffects: Sendable {
    /// Calls of the voice stop (0x8EA0).
    public var stopVoice: Int = 0

    /// Script_Step may run.
    public var scriptStep: Bool = false

    /// How a message advanced: "click", "auto", "skip", "nowait", "restored" or nil.
    public var advanced: String? = nil

    /// A click completed the reveal.
    public var revealClicked: Bool = false

    /// A click cancelled the `_WTTM` wait.
    public var timerClicked: Bool = false

    /// The choice code (0xA6180) runs this frame.
    public var choiceUpdate: Bool = false

    public init(
        stopVoice: Int = 0,
        scriptStep: Bool = false,
        advanced: String? = nil,
        revealClicked: Bool = false,
        timerClicked: Bool = false,
        choiceUpdate: Bool = false
    ) {
        self.stopVoice = stopVoice
        self.scriptStep = scriptStep
        self.advanced = advanced
        self.revealClicked = revealClicked
        self.timerClicked = timerClicked
        self.choiceUpdate = choiceUpdate
    }
}

/// The engine globals of the wait logic (docs/formats/wait_model.md 2; `tsuki.wait_model.WaitState`).
public final class WaitState {
    /// The reveal head value that means "all revealed".
    public static let instant: Float = 768.0

    /// 0x1653E00: wait bits.
    public var bits: UInt64 = 0

    /// 0x1653E08: `_WTTM` / `_WTSV` frames left.
    public var timer: Int = 0

    /// 0x1653E0E: auto countdown (frames).
    public var auto: Int = 0

    /// 0x1653E18: 1 = the timer ignores clicks.
    public var timerNoClick: Int = 0

    /// 0x1653E24: text fade step (positive while the text fades in).
    public var textFadeStep: Float = 0

    /// 0x1653E30: `_STCF` layer mask.
    public var stcfLayers: UInt64 = 0

    /// 0x1653E40: `_STCF` condition per layer.
    public var stcfMask: [UInt8] = [UInt8](repeating: 0, count: 40)

    /// 0x1653E70: message flags (bit 0 reveal, bit 2 voice wait).
    public var flags: UInt64 = 0

    /// 0x1653E7C: 1 after a click advance until decide and the left button are released.
    public var advanceLatch: Int = 0

    /// 0x1653E80: reveal head.
    public var head: Float = 0

    /// 0x1653E84: reveal tail.
    public var tail: Float = 0

    /// 0x1653E88: fade width.
    public var width: Float = 0

    /// 0x1653DF8: free-running counter.
    public var frameCounter: Int = 0

    /// 0xDF29E0: d-pad down newly pressed, consumed by a click.
    public var advKey: Int = 0

    /// 0x86AA24: the next `_ZM` starts a new message slot.
    public var newPage: Int = 0

    /// 0xDF0734: window target (1 = open).
    public var windowTarget: Int = 0

    /// 0xDF0730: window fade.
    public var windowAlpha: Float = 1.0

    /// 0x781AB0: 1 = the current message was read (speed +0x22).
    public var readSel: Int = 0

    /// 0xDD8E50: voice state (0 idle, 1 loading, 2 playing).
    public var voiceState: Int = 0

    /// 0xDF0774: screen fade state; 1 and 2 block the script.
    public var fadeState: Int = 0

    /// F988 != 0: fixed reveal step 0.675.
    public var f988: Int = 0

    /// F1103: the window was closed.
    public var f1103: Int = 0

    /// F1123: keep the voice when the text advances.
    public var f1123: Int = 0

    /// F799: 1 = last message of the page.
    public var f799: Int = 0

    /// F823: message counter of the page.
    public var f823: Int = 0

    /// 0x16541D8: block bits (1 / 2 extra blocks).
    public var blocks: Int = 1

    /// 0x16541F8: next-scene request.
    public var sceneJump: Int = 0

    /// F859..: dimming timers of previous messages (-1 = dimmed).
    public var dim: [Int] = [Int](repeating: 0, count: 12)

    /// The page "display end of page instantly" latch (VA 0xDF0EF0).
    public var pageLatch: Bool = false

    public init() {}
}

/// Ports of the two wait functions the ADV input flow calls every frame, Adv_Update (VA 0xA0B70) and tick_reveal (VA 0xA2630)
/// (docs/formats/wait_model.md 5; `tsuki.wait_model.adv_update`, `tick_reveal`; verified against the eboot's own code under
/// emulation). All float arithmetic is float32.
public enum WaitModel {
    private static let headAll: Float = 76800.0
    private static let f988Step: Float = 0.675
    private static let fastMult: Float = 60.0

    /// The auto countdown conversion `trunc(ms / 1000.0f * 60.0f)` (VA 0xA2968).
    public static func msToFrames(_ ms: Int) -> Int {
        let x = (Float(Int16(truncatingIfNeeded: ms)) / 1000.0) * 60.0
        return x.isFinite && abs(Double(x)) < 2147483648.0 ? Int(x) : Int.min
    }

    /// `_WTTM` / `_WTSV` frames: `(3 * ms) / 50` with C truncation, at least 1 (VA 0x9ACF7).
    public static func waitFrames(_ ms: Int) -> Int {
        let t = Int32(truncatingIfNeeded: 3 &* ms)
        let q = Int(t / 50)
        return q >= 2 ? q : 1
    }

    /// VA 0x56160: counters per reveal step (768 when the speed is not positive).
    public static func revealSpeed(_ cfg: WaitConfig, _ readSel: Int, _ vsync: Int = 1) -> Float {
        let raw = readSel == 1 ? cfg.textSpeedRead : cfg.textSpeedUnread
        let v = Int16(truncatingIfNeeded: raw)
        if v <= 0 {
            return WaitState.instant
        }
        let d = Float(Int16(truncatingIfNeeded: min(vsync, 3)))
        return d / 60.0 * 1000.0 / Float(v)
    }

    /// VA 0x561D0: the fade width (0 when the speed is not positive or instant).
    public static func revealWidth(_ cfg: WaitConfig, _ readSel: Int, _ vsync: Int = 1) -> Float {
        let raw = readSel == 1 ? cfg.textSpeedRead : cfg.textSpeedUnread
        let v = Int16(truncatingIfNeeded: raw)
        if v <= 0 {
            return 0.0
        }
        let d = Float(Int16(truncatingIfNeeded: min(vsync, 3)))
        let sp = d / 60.0 * 1000.0 / Float(v)
        if sp == WaitState.instant {
            return 0.0
        }
        var x = Float(v) * 0.1 / 35.0
        x = 0.5 < x ? 0.5 : x
        return sp * x * 60.0
    }

    /// The 0xCA070 result for a block's glyph records: the alpha of the last record with non-zero flags equals 1.0; an empty block is done.
    public static func revealDone(_ records: [(flags: Int, ctr: Int)], head: Float, tail: Float) -> Bool {
        var alpha: Float? = nil
        for (flags, ctr) in records {
            if flags == 0 {
                continue
            }
            let c = Float(ctr)
            if c > head {
                alpha = 0.0
            } else if tail > c {
                alpha = 1.0
            } else {
                let d = head - tail
                alpha = 0.0 >= d ? 1.0 : (head - c) / d
            }
        }
        return alpha == nil || alpha == 1.0
    }

    private static func clickReveal(_ st: WaitState, _ inp: WaitInput) -> Bool {
        st.advKey != 0 || (inp.mouse & 2) != 0 || (inp.newly & WaitInput.decide) != 0 || inp.wheel < 0
    }

    private static func clickTimer(_ st: WaitState, _ inp: WaitInput) -> Bool {
        st.advKey != 0 || (inp.mouse & 2) != 0 || (inp.newly & WaitInput.decide) != 0
    }

    private static func stopVoiceCondition(_ st: WaitState, _ cfg: WaitConfig, _ mode: AdvMode) -> Bool {
        (st.f1123 == 0 && cfg.interruptVoice != 0) || mode.skipActive != 0
    }

    /// VA 0xA2630 for one frame. `done` returns the 0xCA070 value of a block (slot + 4, 6, 8): 1 = the last record is fully
    /// visible, 0 = not yet, -1 = block not allocated. `n` overrides the frame count (the read-only rule after Adv_Update).
    public static func tickReveal(
        _ st: WaitState,
        _ inp: WaitInput,
        _ cfg: WaitConfig,
        _ mode: AdvMode,
        _ done: (Int) -> Int,
        _ n: Int? = nil
    ) -> WaitEffects {
        var eff = WaitEffects()
        let count = n ?? mode.frames
        let fast = mode.step >= 0x3D
        st.frameCounter = Int(Int16(truncatingIfNeeded: st.frameCounter + count))
        let mult: Float = fast ? fastMult : 1.0
        for _ in 0..<count {
            if (st.flags & WaitBits.reveal) == 0 && (st.bits & WaitBits.reveal) == 0 {
                continue
            }

            if st.windowTarget != 0 && mode.logShown == 0 && (st.textFadeStep > 0 || st.windowAlpha < 1.0) && st.f1103 == 0 {
                continue
            }

            st.windowTarget = 1
            var haveHead = true
            let sp: Float
            if st.f988 == 0 {
                sp = revealSpeed(cfg, st.readSel, mode.vsync)
                st.width = revealWidth(cfg, st.readSel, mode.vsync)
                if sp >= WaitState.instant {
                    st.head = WaitState.instant
                    st.tail = WaitState.instant
                    haveHead = false
                }
            } else {
                sp = f988Step
            }

            if haveHead {
                if WaitState.instant > st.head {
                    st.head = (sp * mult) + st.head
                }
                let x = st.head - st.width
                if x > st.tail {
                    st.tail = x
                }
            }

            if st.advanceLatch == 0 && clickReveal(st, inp) {
                st.head = headAll
                eff.revealClicked = true
                let k = st.f823
                if k >= 2 {
                    for j in 0..<min(k - 1, st.dim.count) {
                        st.dim[j] = -1
                    }
                }
            }
        }

        if st.timer > 0 {
            let left = Int(Int16(truncatingIfNeeded: st.timer - count))
            st.timer = max(0, left)
            if !(st.timerNoClick > 0) && st.advanceLatch == 0 && clickTimer(st, inp) {
                st.timer = 0
                eff.timerClicked = true
            }
        }

        if (mode.skipActive > 0 || (mode.modeWord & 2) != 0) && st.auto >= 0x3D {
            st.auto = 0x3C
        }

        if st.auto > 0 {
            let lim = msToFrames(st.f799 == 1 ? cfg.autoPageMs : cfg.autoWaitMs)
            var v = st.auto
            if lim < v {
                v = lim
            }
            v = Int(Int16(truncatingIfNeeded: v - count))
            st.auto = v > 0 ? v : 0
        }

        var r = done(4)
        if (st.blocks & 2) != 0 {
            r &= done(6)
        }
        if (st.blocks & 4) != 0 {
            r &= done(8)
        }

        if r != 0 {
            if (st.bits & WaitBits.reveal) != 0 {
                if (st.bits & WaitBits.click) != 0 {
                    st.auto = Int(Int16(truncatingIfNeeded: msToFrames(st.f799 == 1 ? cfg.autoPageMs : cfg.autoWaitMs)))
                }
                st.bits = (st.bits & ~(WaitBits.reveal | WaitBits.shown)) | WaitBits.shown
            }
            st.flags &= ~WaitBits.reveal
        }

        if fast && (mode.rewind != 0 || mode.skipActive > 0 || (mode.modeWord & 2) != 0) {
            st.auto = 0
        }

        if (st.bits & WaitBits.choice) != 0 {
            st.windowTarget = 1
            eff.choiceUpdate = true
        }

        return eff
    }

    /// VA 0xA0B70 for one frame (live paths). `stcf` is 0x4AB80 (layer, mask). The result says whether Script_Step runs; the caller
    /// then executes statements up to the next yield.
    public static func advUpdate(
        _ st: WaitState,
        _ inp: WaitInput,
        _ cfg: WaitConfig,
        _ mode: AdvMode,
        _ stcf: (Int, Int) -> Bool
    ) -> WaitEffects {
        var eff = WaitEffects()
        if (inp.mouse & 1) == 0 && (inp.held & WaitInput.decide) == 0 {
            st.advanceLatch = 0
        }

        if (st.bits & WaitBits.voice) != 0 && st.voiceState == 0 {
            st.bits &= ~WaitBits.voice
            if st.auto < 0 {
                st.auto = 0
            }
        }

        if (st.bits & WaitBits.stcf) != 0 {
            var m = st.stcfLayers
            for l in 0..<40 {
                if ((m >> l) & 1) != 0 && !stcf(l, Int(st.stcfMask[l])) {
                    m &= ~(1 &<< l)
                }
            }
            st.stcfLayers = m
            if m == 0 {
                st.bits &= ~WaitBits.stcf
            }
        }

        if (st.bits & WaitBits.reveal) == 0 && (st.flags & WaitBits.reveal) == 0 && (st.bits & WaitBits.voice) != 0
            && (st.advKey != 0 || (inp.newly & WaitInput.decide) != 0 || (inp.mouse & 2) != 0 || mode.skipActive != 0 || inp.wheel < 0) {
            if stopVoiceCondition(st, cfg, mode) {
                eff.stopVoice += 1
            }
            st.flags &= ~WaitBits.voice
            st.bits &= ~WaitBits.voice
        }

        if (st.bits & WaitBits.shown) != 0 && st.timer == 0 {
            if clickReveal(st, inp) {
                st.advKey = 0
                st.auto = 0
                if (st.bits & WaitBits.message) != 0 {
                    st.bits &= ~WaitBits.message
                    st.flags = 0
                    st.newPage = 1
                }

                let cl = stopVoiceCondition(st, cfg, mode)
                if (st.bits & WaitBits.voice) != 0 {
                    if cl {
                        eff.stopVoice += 1
                    }
                    st.flags &= ~WaitBits.voice
                    st.bits &= ~WaitBits.voice
                } else if cl {
                    eff.stopVoice += 1
                }

                st.bits &= ~(WaitBits.reveal | WaitBits.shown | WaitBits.click)
                st.advanceLatch = 1
                eff.advanced = "click"
            } else {
                let go: Bool
                if (st.bits & WaitBits.click) != 0 && (mode.modeWord & 1) == 0 && !(mode.skipActive > 0) {
                    go = false
                } else if (st.bits & WaitBits.voice) == 0 && st.auto == 0 {
                    go = true
                } else {
                    go = mode.skipActive != 0 && st.auto == 0
                }

                if go {
                    let hadClick = (st.bits & WaitBits.click) != 0
                    if (st.bits & WaitBits.message) != 0 {
                        st.bits &= ~WaitBits.message
                        st.flags = 0
                        st.newPage = 1
                    }

                    st.bits &= ~(WaitBits.reveal | WaitBits.shown | WaitBits.click)
                    eff.advanced = !hadClick ? "nowait" : (mode.skipActive != 0 ? "skip" : "auto")
                }
            }
        }

        if st.bits == (WaitBits.click | WaitBits.message) {
            if st.advKey != 0 || (inp.mouse & 2) != 0 || (inp.newly & WaitInput.decide) != 0 || inp.wheel < 0 {
                st.advKey = 0
                st.bits &= ~(WaitBits.click | WaitBits.message)
                eff.advanced = "restored"
            } else if mode.skipActive > 0 || (mode.modeWord & 2) != 0 || ((mode.modeWord & 1) != 0 && st.auto <= 0) {
                st.bits &= ~(WaitBits.click | WaitBits.message)
                eff.advanced = "restored"
            }
        } else if st.bits == WaitBits.message {
            st.bits = 0
            st.newPage = 1
        }

        if (inp.held & WaitInput.r2) != 0 && st.f1123 == 0 && cfg.interruptVoice != 0 {
            eff.stopVoice += 1
        }

        if st.bits == 0 && st.timer == 0 && st.auto == 0 && st.fadeState != 1 && st.fadeState != 2 {
            eff.scriptStep = true
        }

        return eff
    }
}
