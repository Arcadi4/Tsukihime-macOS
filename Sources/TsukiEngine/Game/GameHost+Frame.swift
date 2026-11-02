import Foundation
import TsukiCore

/// What one `GameHost.step` did (for traces and the headless runner).
public struct FrameReport: Sendable {
    public let frame: Int64
    public let scriptRan: Bool
    public let scriptEnd: StepEnd?
    public let advanced: String?
    public let statements: Int

    public init(frame: Int64, scriptRan: Bool, scriptEnd: StepEnd?, advanced: String?, statements: Int) {
        self.frame = frame
        self.scriptRan = scriptRan
        self.scriptEnd = scriptEnd
        self.advanced = advanced
        self.statements = statements
    }
}

extension GameHost {
    /// Auto mode is on (bit 0 of the mode word).
    public var autoMode: Bool { (modeWord & 1) != 0 }

    /// The skip latch is on (bit 1 of the mode word).
    public var skipLatch: Bool { (modeWord & 2) != 0 }

    /// The input of the frame being stepped.
    public var input: InputFrame { currentInput }

    /// Sets the auto mode (the mode panel and the shell use it).
    public func setAutoMode(_ on: Bool) {
        modeWord = on ? (modeWord | 1) : (modeWord & ~1)
    }

    /// Sets the skip latch.
    public func setSkipLatch(_ on: Bool) {
        modeWord = on ? (modeWord | 2) : (modeWord & ~2)
    }

    /// The "already read" state of the current line (VA 0x75C90).
    public var lineRead: Bool { markers.seen && markers.isRead }

    /// Updates the mode words from the frame's input (0x60710, adv_state.md 6 and 8): toggles, the fast-forward hold, the read-only rule
    /// before the frame. Returns the mode of the frame.
    func computeMode(_ input: InputFrame, cfg: WaitConfig) -> AdvMode {
        let pressed = input.pressed
        let shell = input.shellPressed
        if pressed.contains(.l1) || shell.contains(.autoToggle) {
            modeWord ^= 1
        }

        if pressed.contains(.r1) || shell.contains(.skipToggle) {
            modeWord ^= 2
        }

        if pressed.contains(.cancel) || input.pointer.pressed.contains(.right) {
            modeWord &= ~2
        }

        // action 25 (cancel, or the shell's H): hide / show the message window (VA 0x61CBF); a movie and a choice use the button themselves
        if !movieActive && !choiceOpen && (shell.contains(.hideWindow) || pressed.contains(.cancel)) {
            windowHiddenVal = !windowHiddenVal
        }

        let ffHold = input.held.contains(.r2) || input.shellHeld.contains(.fastForward)
        var m: AdvMode
        if ffHold && !choiceOpen && !movieActive {
            m = AdvMode(modeWord: modeWord & 0xFFFF, skipActive: 1, rewind: 0, logShown: 0, step: 64, vsync: 1)
        } else {
            m = AdvMode.fromModeWord(modeWord)
        }

        if movieActive {
            m.skipActive = 0
            m.step = 1
        }

        // the read-only rule before the frame (0x612D0)
        let r2 = ffHold && (input.held.contains(.r2) ? input.analogR2 != 0 : true)
        if m.skipActive != 0 && cfg.fastForwardReadOnly != 0 && !lineRead && !r2 {
            modeWord &= ~2
            m = AdvMode.fromModeWord(modeWord)
            skipStoppedByReadRule = true
        }

        return m
    }

    func syncSound(_ mode: AdvMode) {
        sound.skip = mode.skipActive != 0
        sound.fastForward = skipScene
    }

    /// Runs one 60 Hz frame in the eboot's order (wait_model.md 13): the mode words, Adv_Update (and Script_Step when nothing waits), the
    /// read-only rule, tick_reveal, the layer and transition update, the choice, movie and sound updates, the window and text fades; then
    /// draws into `list` when it is not nil.
    public func step(_ input: InputFrame, list: DisplayList? = nil) -> FrameReport {
        frameCounter += 1
        currentInput = input
        statementsAtFrameStart = dispatchCount
        var scriptRan = false
        var scriptEnd: StepEnd? = nil
        var advanced: String? = nil

        if phase == .running {
            let cfg = WaitConfig.from(config)
            let wi = WaitInput.from(input)
            wait.advKey = wi.advKey
            syncWaitFromVars()
            wait.voiceState = sound.voiceState
            if skipScene {
                runSceneSkip()
            }

            let computedMode = computeMode(input, cfg: cfg)
            self.mode = computedMode
            syncSound(computedMode)

            // 1. Adv_Update, and Script_Step when nothing waits
            if computedMode.logShown == 0 {
                let eff = WaitModel.advUpdate(wait, wi, cfg, computedMode) { [weak self] layer, mask in
                    self?.stcfPending(layer: layer, mask: mask) ?? false
                }
                lastUpdate = eff
                advanced = eff.advanced
                if eff.stopVoice > 0 {
                    sound.stopVoiceOnAdvance(f1123: f(1123))
                    wait.voiceState = sound.voiceState
                }

                if eff.scriptStep {
                    scriptRan = true
                    scriptEnd = runScript()
                    wait.voiceState = sound.voiceState
                }
            }

            // 2. the read-only rule after the update, then tick_reveal
            var modeR = computedMode
            var n: Int? = nil
            let r2Held = input.held.contains(.r2) && input.analogR2 != 0
            if computedMode.skipActive != 0 && cfg.fastForwardReadOnly != 0 && !lineRead && !r2Held && !input.shellHeld.contains(.fastForward) {
                modeR.skipActive = 0
                n = max(0, min(computedMode.vsync, 3))
                modeWord &= ~2
                skipStoppedByReadRule = true
            }

            syncWaitFromVars()
            lastReveal = WaitModel.tickReveal(wait, wi, cfg, modeR, { [weak self] block in
                self?.revealDoneValue(block) ?? 1
            }, n)

            if lastReveal.revealClicked {
                let k = f(823)
                for j in 0..<min(k - 1, 12) {
                    setF(859 + j, -1)
                }

                for m in page {
                    m.dimTimer = -1
                }
            }

            // 3. layers and transitions (VA 0x57980), choice, movie, sound, fades
            let stepVal = computedMode.step
            stage.skipActive = skipScene
            stage.update(arg: stepVal)
            if (wait.bits & WaitBits.fads) != 0 && !stage.transitionActive && !stage.commitPending {
                wait.bits &= ~(WaitBits.fads | WaitBits.system)
            }

            if choiceOpen {
                updateChoice(input, dt: stepVal)
            }

            updateMovie(input, step: stepVal)
            updateSound()
            updateWindowFades(max(1, computedMode.step))
            updateEffects(stepVal)

            // 4. the HUD process (0x53CF0, priority 0x50) runs after the ADV update: the click-wait icon's alpha and anchor (package K34)
            updateClickIcon()
        }

        if let l = list {
            draw(l)
        }

        return FrameReport(
            frame: frameCounter,
            scriptRan: scriptRan,
            scriptEnd: scriptEnd,
            advanced: advanced,
            statements: Int(dispatchCount - statementsAtFrameStart)
        )
    }

    func runScript() -> StepEnd {
        let end: StepEnd
        do {
            end = try vm.step(self)
        } catch {
            end = .halted
        }

        if end == .endOfScript && phase == .running {
            phase = .ended
            endReason = .endOfScript
            sink.onScriptEnd(reason: .endOfScript)
        } else if end == .halted && phase == .running {
            phase = .ended
            if endReason == .none {
                endReason = .endOfScript
            }
        }

        return end
    }

    /// The "next scene" action (adv_state.md 5.2) after its dialog: the script runs at full speed inside the next `step` with every wait
    /// cleared, until a scene start (`_ATSV`), an unread message, a jump, the end of the story, a movie or a choice ends it. Not while a choice is open.
    public func requestNextScene() -> Bool {
        if phase != .running || choiceOpen {
            return false
        }

        skipScene = true
        return true
    }

    func endSceneSkip(resync: Bool = true) {
        if skipScene {
            skipScene = false
            sound.fastForward = false
            if resync {
                sound.resyncScriptState()
            }
            sceneSkipEnded?()
        }
    }

    func runSceneSkip() {
        sound.fastForward = true
        for _ in 0..<200_000 where skipScene && phase == .running {
            wait.bits = 0
            wait.flags = 0
            wait.timer = 0
            wait.auto = 0
            wait.stcfLayers = 0
            _ = runScript()
            stage.update(arg: 64)
            stage.update(arg: 64)
        }

        endSceneSkip()
    }

    func updateSound() {
        if !options.sound {
            _ = sound.takeCommands()
            return
        }

        drainSound()
        sound.vsyncs = 1
        sound.update(dt: 1)
        sound.duckUpdate()
        drainSound()
        audio.tick()
        wait.voiceState = sound.voiceState
    }

    func drainSound() {
        let cmds = sound.takeCommands()
        if !cmds.isEmpty {
            audioOut.append(contentsOf: cmds)
            audio.process(commands: cmds, clipFrames: services.clipFrames, defaultVoiceFrames: options.defaultVoiceFrames)
        }
    }
}
