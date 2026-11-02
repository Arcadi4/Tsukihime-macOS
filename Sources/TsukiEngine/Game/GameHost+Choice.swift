import Foundation
import TsukiCore

/// One line of the choice menu (`_SELR`).
public final class ChoiceLine {
    /// The value the line stores in the result variable (argument 0 of `_SELR`).
    public var value: Int = 0

    /// Argument 2 of `_SELR` was 1: the line is greyed out and cannot be selected.
    public var locked: Bool = false

    /// The slot text: the number prefix line followed by the argument (script.md 5.1 of system_flow.md).
    public var text: [UInt8] = []

    /// The laid-out block of the line.
    public var block: TextBlock?

    public init() {}
}

/// What the choice machine shows (the Ui layer draws from it).
public enum ChoiceKind: UInt8, Sendable {
    case none = 0
    case list = 1
    case twoButtons = 2
    case savePrompt = 3
}

extension GameHost {
    private static let choiceFadeIn: Float = 0.04
    private static let choiceFadeOut: Float = 0.028
    private static let choiceFlashStep: Float = 0.02

    func initChoice() {
        glow = ChoiceGlow(sheetSize: { [weak self] child in
            self?.selectSheetSize(child) ?? (0, 0)
        })
    }

    func selectSheetSize(_ child: Int) -> (width: Int, height: Int) {
        if let size = selectSizesCache[child] {
            return size
        }
        let size: (width: Int, height: Int)
        size = data.uiSheetSize(.selectParts, language, child)
        selectSizesCache[child] = size
        return size
    }

    func choiceWidth() -> Int {
        language == .en ? 574 : 474
    }

    func resetChoice() {
        lines.removeAll()
        choicePhaseVal = 0
        cursorVal = -1
        previousCursorVal = -1
        choiceAlphaVal = 0
        choiceFlashVal = 0
        decidedVal = -1
        glow.reset()
        glowTextCache.removeAll()
    }

    /// True while a choice menu or prompt is open (wait bit 0x10).
    public var choiceOpen: Bool { (wait.bits & WaitBits.choice) != 0 }

    /// The kind of choice that is open (or none).
    public var choiceKind: ChoiceKind {
        choiceOpen ? (ChoiceKind(rawValue: UInt8(varState.choiceMode)) ?? .none) : .none
    }

    /// The lines of the open choice.
    public var choiceLines: [ChoiceLine] { lines }

    /// The highlighted line (-1: none yet); for a two-button prompt the selected button (0 No, 1 Yes).
    public var choiceCursor: Int { cursorVal }

    /// The choice machine's phase: 0 fade-in, 1 text reveal, 2 selecting, 3 decided.
    public var choicePhase: Int { choicePhaseVal }

    /// The line the cursor was on before its last move (u16 0x17506A4), -1 none.
    public var choicePreviousCursor: Int { previousCursorVal }

    /// The choice alpha (u32 0x17506A8): 0 to 1 while fading in, 1 while selecting, falling after the decision.
    public var choiceAlpha: Float { choiceAlphaVal }

    /// The highlight fade (0x17506B4): 0 after a cursor move, +0.1 per frame up to 1.
    public var choiceHighlight: Float { choiceHighlightVal }

    /// The decision flash (0x17506AC): 1 at the decision, -0.02 per frame; the decided phase ends at 0.
    public var choiceFlash: Float { choiceFlashVal }

    /// The flare pulse (0x17506B8) between 0.333 and 1.
    public var choicePulse: Float { glow.pulse }

    /// The choice point number (`_SELD` argument 1), -1 when absent.
    public var choicePoint: Int { Int(varState.choiceId) }

    /// True while the choice accepts a decision.
    public var choiceSelectable: Bool { choiceOpen && choicePhaseVal == 2 }

    /// Selects line `index` (list) or button `index` (the two-button prompts: 0 No, 1 Yes) and decides it.
    public func choose(_ index: Int) -> Bool {
        guard choiceOpen else { return false }

        if promptOpen {
            return choosePrompt(index)
        }

        if choicePhaseVal < 2 {
            choiceAlphaVal = 1.0
            choicePhaseVal = 2
        }

        let maxCount = max(varState.choiceCount, lines.count)
        guard choicePhaseVal == 2, index >= 0, index < maxCount else {
            return false
        }

        if index < lines.count && lines[index].locked {
            return false
        }

        setCursor(index)
        decide()
        return true
    }

    func setCursor(_ c: Int) {
        if c != cursorVal {
            previousCursorVal = cursorVal
            cursorVal = c
            choiceHighlightVal = 0
            glow.onCursorChange()
        }
    }

    func cmdSelr(_ st: Statement) -> StepResult {
        let k = varState.choiceCount - 1
        if k == 0 {
            lines.removeAll()
            push(.choiceLine, st)
        }

        while lines.count < varState.choiceCount {
            lines.append(ChoiceLine())
        }

        if k >= 0 && k < lines.count {
            let line = lines[k]
            line.value = k < varState.choiceValues.count ? Int(Int16(bitPattern: varState.choiceValues[k])) : 0
            line.locked = k < varState.choiceLocked.count && varState.choiceLocked[k]
            let arg = argText(st, 1)
            let prefix = k < 9 ? 43960 + k : 43959
            let source = String(format: "$%06d%@", prefix, arg)
            line.text = expandMessage(Array(source.utf8))
        }

        return StepResult.continue
    }

    func openChoice(_ st: Statement) {
        endSceneSkip()
        wait.bits |= WaitBits.choice
        choicePhaseVal = 0
        cursorVal = -1
        previousCursorVal = -1
        choiceAlphaVal = 0
        choiceFlashVal = 0
        choiceHighlightVal = 0
        choiceHeadVal = 0
        decidedVal = -1
        glow.reset()
        glowTextCache.removeAll()

        if varState.choiceMode == ChoiceMode.list.rawValue {
            wait.windowTarget = 1
            let window = windowIndex()
            for k in 0..<lines.count {
                let p = LayoutParams(width: choiceWidth(), flags: window < 3 ? 0 : 1 << 20, block: 0x14 + k, window: window)
                lines[k].block = try? TextLayout.layout(lines[k].text, language, fonts, p)
            }

            let n = Int(varState.choiceId)
            let seen = n >= 0 && n < SystemBlock.choiceTakenCount && systemData.getChoiceTaken(n) != 0
            wait.readSel = seen ? 1 : 0
            if !seen && mode.skipActive != 0 && config.fastForwardReadOnly != 0 {
                modeWord &= ~2
                skipStoppedByReadRule = true
            }

            push(.choiceStart, st)
            sink.updateStaging()
        }
    }

    func cmdSeld(_ st: Statement) -> StepResult {
        if !varState.scanMode {
            openChoice(st)
        }
        return StepResult.yield
    }

    func cmdSels(_ st: Statement) -> StepResult {
        if varState.choiceMode == ChoiceMode.twoButtons.rawValue {
            openPrompt()
        }
        return StepResult.yield
    }

    func cmdSela(_ st: Statement) -> StepResult {
        if varState.choiceMode == ChoiceMode.savePrompt.rawValue {
            openPrompt()
        }
        return StepResult.yield
    }

    func decide() {
        let cursor = cursorVal
        let kind = ChoiceKind(rawValue: UInt8(varState.choiceMode)) ?? .none
        var value = 0
        if cursor >= 0 && cursor < varState.choiceValues.count {
            value = Int(Int16(bitPattern: varState.choiceValues[cursor]))
        }

        _ = try? VarCommands.choiceStore(varState, cursor)
        let n = Int(varState.choiceId)
        if n >= 0 && n < SystemBlock.choiceTakenCount {
            systemData.setChoiceTaken(n, systemData.getChoiceTaken(n) | UInt8(1 << (value & 7)))
            sink.onChoiceTaken(choiceId: n, option: value & 7)
        }

        sound.systemSePlay(3)
        decidedVal = cursor
        choicePhaseVal = 3
        choiceFlashVal = 1.0
        choiceDecided?(kind, n, value, cursor)
    }

    func updateChoice(_ input: InputFrame, dt: Int) {
        if promptOpen {
            updatePrompt(input, dt: dt)
            return
        }

        choiceHighlightVal = min(1.0, choiceHighlightVal + 0.1)
        glow.tick(dt)
        switch choicePhaseVal {
        case 0:
            choiceAlphaVal += Self.choiceFadeIn * Float(dt)
            if choiceAlphaVal >= 1.0 {
                choiceAlphaVal = 1.0
                choicePhaseVal = varState.choiceMode == ChoiceMode.list.rawValue ? 1 : 2
            }
        case 1:
            let cfg = WaitConfig.from(config)
            let speed = WaitModel.revealSpeed(cfg, wait.readSel)
            choiceHeadVal = speed >= WaitState.instant ? WaitState.instant : choiceHeadVal + (speed * Float(dt))
            var allDrawn = true
            for l in lines {
                let last = (l.block?.records.isEmpty == false) ? Int(l.block!.records.last!.ctr) : 0
                allDrawn = allDrawn && (choiceHeadVal >= Float(last) + 3.0)
            }

            if allDrawn || input.pressed.contains(.decide) || input.pointer.pressed.contains(.left) {
                choiceHeadVal = WaitState.instant
                choicePhaseVal = 2
            }
        case 2:
            selectInput(input)
        case 3:
            choiceAlphaVal = max(0, choiceAlphaVal - (Self.choiceFadeOut * Float(dt)))
            choiceFlashVal -= Self.choiceFlashStep * Float(dt)
            if choiceFlashVal <= 0 {
                closeChoice()
            }
        default:
            break
        }
    }

    func selectInput(_ input: InputFrame) {
        let count = max(varState.choiceCount, lines.count)
        let up = input.repeated.contains(.up) || input.pointer.wheel > 0
        let down = input.repeated.contains(.down) || input.pointer.wheel < 0
        if up || down {
            var c = cursorVal
            for _ in 0..<count {
                c = up ? (c <= 0 ? count - 1 : c - 1) : (c >= count - 1 ? 0 : c + 1)
                if varState.choiceMode != ChoiceMode.list.rawValue || !lines[c].locked {
                    setCursor(c)
                    break
                }
            }
        }

        if cursorVal >= 0 && (input.pressed.contains(.decide) || input.pointer.pressed.contains(.left)) {
            decide()
        }
    }

    func closeChoice() {
        choiceFlashVal = 0
        wait.bits &= ~WaitBits.choice
        varState.choiceMode = ChoiceMode.none.rawValue
        varState.choiceCount = 0
        varState.choiceValues.removeAll()
        varState.choiceLocked.removeAll()
        lines.removeAll()
    }

    // MARK: - Choice Pointer

    /// The choice line whose row contains canvas row `canvasY` (1080 rows), or -1.
    public func choiceLineAt(_ canvasY: Double) -> Int {
        if varState.choiceMode != ChoiceMode.list.rawValue || lines.isEmpty {
            return -1
        }

        let y0 = choiceFirstY()
        let rows = ((canvasY / Self.choiceScaleY) - y0) / ChoiceView.linePitch
        let k = Int(floor(rows))
        return rows >= 0 && k < lines.count ? k : -1
    }

    /// Moves the choice cursor to line `line` as a mouse hover does: only while the choice accepts a decision, never onto a locked line.
    public func hoverChoice(_ line: Int) -> Bool {
        if !choiceSelectable || varState.choiceMode != ChoiceMode.list.rawValue || line < 0 || line >= lines.count || lines[line].locked {
            return false
        }

        setCursor(line)
        return true
    }

    // MARK: - Two-Button Prompts

    /// True while a two-button prompt (`_SELS` or `_SELA`) is open.
    public var promptOpen: Bool {
        choiceOpen && (varState.choiceMode == ChoiceMode.twoButtons.rawValue || varState.choiceMode == ChoiceMode.savePrompt.rawValue)
    }

    /// The `ui_text` id of the open prompt's message: 216 for a `_SELA`, 1446 + F27 for a `_SELS`.
    public var promptMessageId: Int {
        varState.choiceMode == ChoiceMode.savePrompt.rawValue ? 216 : 1446 + f(27)
    }

    /// The window's size factor now: 1 + 0.05 (1 - alpha) while the prompt opens, 1 - 0.05 (1 - alpha) while it closes after an answer, else 1.
    public var promptScale: Float {
        let a = min(max(choiceAlphaVal, 0.0), 1.0)
        switch choicePhaseVal {
        case 0:
            return 1.0 + ((1.0 - a) * PromptLayout.pop)
        case 3:
            return 1.0 + ((1.0 - a) * -PromptLayout.pop)
        default:
            return 1.0
        }
    }

    /// Tells the host that the save screen it asked for (`savePromptAccepted`) has closed, saved or not.
    public func savePromptScreenClosed() {
        promptSaveDoneVal = true
    }

    func openPrompt() {
        endSceneSkip()
        wait.bits |= WaitBits.choice
        choicePhaseVal = 0
        cursorVal = -1
        previousCursorVal = -1
        choiceAlphaVal = 0
        choiceFlashVal = 0
        choiceHighlightVal = 0
        decidedVal = -1
        promptSaveDoneVal = false
        promptPointerVal = nil

        newPage()
        setF(823, 0)
        setF(1103, 1)
    }

    func newPage() {
        newMessageSlot()
        page.removeAll()
        currentMsg = nil
    }

    func choosePrompt(_ index: Int) -> Bool {
        if choicePhaseVal < 2 {
            choiceAlphaVal = 1.0
            choicePhaseVal = 2
        }

        if choicePhaseVal != 2 || index < 0 || index > 1 {
            return false
        }

        setPromptCursor(index, sound: false)
        decidePrompt()
        return true
    }

    func setPromptCursor(_ c: Int, sound: Bool) {
        if c != cursorVal {
            previousCursorVal = cursorVal
            cursorVal = c
            if sound {
                self.sound.systemSePlay(2)
            }
        }
    }

    func updatePrompt(_ input: InputFrame, dt: Int) {
        let dtf = Float(dt)
        switch choicePhaseVal {
        case 0:
            promptPointerVal = input.pointer.active ? (input.pointer.x, input.pointer.y) : nil
            choiceAlphaVal = (dtf * PromptLayout.fadeStep) + choiceAlphaVal
            if choiceAlphaVal >= 1.0 {
                choiceAlphaVal = 1.0
                choicePhaseVal = 2
            }
        case 2:
            promptInput(input)
        case 3:
            choiceAlphaVal = (dtf * -PromptLayout.fadeStep) + choiceAlphaVal
            if choiceAlphaVal <= 0.0 {
                choiceAlphaVal = 0
                closeChoice()
                newPage()
            }
        case 4:
            choiceAlphaVal = (dtf * -PromptLayout.fadeStep) + choiceAlphaVal
            if choiceAlphaVal <= 0.0 {
                choicePhaseVal = 5
            }
        case 5:
            choicePhaseVal = 6
            promptSaveDoneVal = savePromptAccepted == nil
            savePromptAccepted?()
        case 6:
            if promptSaveDoneVal {
                choicePhaseVal = 7
            }
        case 7:
            choicePhaseVal = 3
        default:
            break
        }
    }

    func promptInput(_ input: InputFrame) {
        let ptr = input.pointer
        if input.pressed.contains(.cancel) || ptr.pressed.contains(.right) {
            return
        }

        let click = ptr.pressed.contains(.left)
        var hovered = -1
        if ptr.active {
            let moved: Bool
            if let last = promptPointerVal {
                moved = last.x != ptr.x || last.y != ptr.y
            } else {
                moved = true
            }
            promptPointerVal = (ptr.x, ptr.y)
            if moved || !ptr.pressed.isEmpty {
                hovered = PromptLayout.buttonAt(Int(ptr.x), Int(ptr.y))
                if hovered >= 0 {
                    setPromptCursor(hovered, sound: true)
                }
            }
        } else {
            promptPointerVal = nil
        }

        if input.pressed.contains(.decide) || click {
            let beside = click && ptr.active && hovered < 0
            if !beside && (cursorVal == 0 || cursorVal == 1) {
                decidePrompt()
            }
            return
        }

        let left: PadButtons = [.left, .stickLeft]
        let right: PadButtons = [.right, .stickRight]
        let up: PadButtons = [.up, .stickUp]
        let down: PadButtons = [.down, .stickDown]
        let rep = input.repeated
        let fresh = input.pressed
        if !rep.isDisjoint(with: left) {
            setPromptCursor(cursorVal > 0 ? cursorVal - 1 : (!fresh.isDisjoint(with: left) ? 1 : 0), sound: true)
        } else if !rep.isDisjoint(with: right) {
            setPromptCursor(cursorVal <= 0 ? cursorVal + 1 : (!fresh.isDisjoint(with: right) ? 0 : 1), sound: true)
        } else if !rep.isDisjoint(with: up) {
            setPromptCursor(0, sound: true)
        } else if !rep.isDisjoint(with: down) {
            setPromptCursor(1, sound: true)
        }
    }

    func decidePrompt() {
        let cursor = cursorVal
        let kind = ChoiceKind(rawValue: UInt8(varState.choiceMode)) ?? .none
        if kind == .twoButtons {
            _ = try? VarCommands.choiceStore(varState, cursor)
        }

        sound.systemSePlay(0)
        decidedVal = cursor
        choicePhaseVal = (kind == .savePrompt && cursor == 1) ? 4 : 3
        choiceDecided?(kind, Int(varState.choiceId), cursor, cursor)
    }
}
