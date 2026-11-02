import Foundation
import TsukiCore

/// Where a session is.
public enum GamePhase: UInt8, Sendable {
    /// No scene started.
    case notStarted = 0

    /// A script runs.
    case running = 1

    /// The script ended (`GameHost.endReason`); the caller goes back to the title.
    case ended = 2
}

/// Why the script ended (script.md 4.1: `END_`, `RTM_`, `RTMN`).
public enum EndReason: UInt8, Sendable {
    /// Still running.
    case none = 0

    /// `_END_`: script state 1.
    case end = 1

    /// `_RTM_`: return to the title, script state 2.
    case returnToTitle = 2

    /// `_RTMN`: return to the title with the BGM kept.
    case returnKeepBgm = 3

    /// The cursor ran off the end of the script.
    case endOfScript = 4

    /// A jump named a scene the data does not have.
    case missingScene = 5
}

/// An unknown command in a strict session (dev builds).
public struct UnknownCommandError: Error, CustomStringConvertible, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

struct ChoiceGlowKey: Hashable {
    let line: Int
    let colour: Int
}

/// The game interpreter of the PS4 build: the command handlers (`ScriptHost`), the 60 Hz frame (`step`) and the state that
/// belongs to a running story (messages, waits, choices, sound, movies, flowchart marks). The VM (`ScriptVm`) executes the variable
/// and flow commands itself and hands every other statement to `dispatch`. The layer commands go to `StageRuntime`
/// (GameHost+Stage.swift), the sound commands to `SoundModel` (GameHost+Sound.swift); everything the history ring or a save needs is
/// reported through `HistorySink` (GameHost+Save.swift).
public final class GameHost: ScriptHost {
    let services: GameServices
    let options: GameOptions
    let data: any GameData
    let flow: any GameFlowTables
    let fonts: FontTables
    let language: Language
    var unknown: [String: Int] = [:]
    var vm: ScriptVm!
    var frameCounter: Int64 = 0
    var lastSceneScript: Int = -1

    /// The persistent profile: system block (config, read tracking, unlocks) and the F / Z / G words.
    public let profile: GameProfile

    /// The persistent system block.
    public var systemData: SystemBlock { profile.system }

    /// The config block (system block + 4).
    public var config: ConfigBlock { profile.system.config }

    /// The F / Z / G variable words.
    public var vars: Vars { profile.vars }

    /// The variable state the VM commands run on (choice registers, argument buffer).
    public let varState: VarState

    /// The read tracking (`readmax`).
    public let markers: MarkerState

    /// The wait state (wait_model.md 2).
    public let wait: WaitState

    /// The layer stage.
    public internal(set) var stage: StageRuntime!

    /// The sound model.
    public internal(set) var sound: SoundModel!

    /// The script VM of the running story.
    public var machine: ScriptVm { vm }

    /// The running script number, or -1.
    public var script: Int { vm.image.index }

    /// The scene id of the running script.
    public var sceneId: Int { flow.sceneId(vm.image.index) }

    /// Where the session is.
    public internal(set) var phase: GamePhase = .notStarted

    /// Why the script ended.
    public internal(set) var endReason: EndReason = .none

    /// The 60 Hz frame counter of the last `step`.
    public var frame: Int64 { frameCounter }

    /// The history / save hooks (GameHost+Save.swift); defaults to a sink that records nothing.
    public var sink: any HistorySink

    /// Unknown command names seen so far and how often.
    public var unknownCommands: [String: Int] { unknown }

    /// Statements dispatched to the host so far.
    public internal(set) var dispatchCount: Int64 = 0

    /// The scripts reached since the host was created (script numbers).
    public var scriptsReached: Set<Int> = []

    /// Raised when a script is entered (a new game, a `_JUMP`): script number, scene id.
    public var sceneEntered: ((Int, Int) -> Void)?

    /// The parts of the player's text the options hide from the headless runner: set by the runner for traces.
    public var log: ((String) -> Void)?

    /// Raised by `_TRPY(n)` (trophy n; the platform layer decides what to do).
    public var trophyUnlocked: ((Int) -> Void)?

    /// When set, called for every statement whose dispatch took 5 ms or more: command name, script, offset, milliseconds.
    public var slowStatement: ((String, Int, Int, Double) -> Void)?

    var traceObserver: ((FlowStep) -> Void)?

    // Effects
    var focus: FocusEffect!
    var ghost: GhostEffect!

    /// The focus-line / falling-note effect (state, particles and draw).
    public var focusEffect: FocusEffect { focus }

    /// The ghosting (channel split) effect of `_FADE(40)`.
    public var ghostEffect: GhostEffect { ghost }

    // Frame
    var modeWord: Int = 0
    public internal(set) var skipStoppedByReadRule: Bool = false
    var currentInput: InputFrame = InputFrame()
    var statementsAtFrameStart: Int64 = 0
    public internal(set) var mode: AdvMode = AdvMode.fromModeWord(0)
    public internal(set) var lastUpdate: WaitEffects = WaitEffects()
    public internal(set) var lastReveal: WaitEffects = WaitEffects()
    public internal(set) var skipScene: Bool = false
    public var sceneSkipEnded: (() -> Void)?

    // Flow
    public internal(set) var replayRequested: Bool = false
    var keepBgm: Bool = false

    // Sound
    let audio: VirtualAudio = VirtualAudio()
    var audioOut: [AudioCommand] = []
    var externalPlaying: ((Int) -> Bool)?
    var voiceRowWordsStorage: [Int]?
    var voiceRowWordsRead: Bool = false

    // Message
    var page: [PageMessage] = []
    var currentMsg: PageMessage?
    var currentRaw: [UInt8] = []
    var textFadeVal: Float = 1.0
    var windowQuick: Bool = false
    var zmStartedVoice: Bool = false
    public internal(set) var continueByte: Bool = false
    var windowHiddenVal: Bool = false
    public var messageStarted: ((Int, Int, Bool) -> Void)?
    public var waitStarted: ((String, Int) -> Void)?

    // NamePlate
    var namePlateBytes = [UInt8](repeating: 0, count: 0x1C)
    var namePlateBlock: TextBlock?

    // ClickIcon
    var iconAlphaVal: Float = 0
    var iconTickVal: Int = -1
    var iconAnchorVal: ClickAnchor = ClickAnchor(x: 0, y: 0, complete: false)
    var iconStoredXVal: Float = 0
    var iconStoredYVal: Float = 0
    public internal(set) var lastClickIcon: ClickIconDraw = ClickIconDraw(kind: .none, dispChild: 0, frame: 0, x: 0, y: 0, alpha: 0)

    // Choice
    var lines: [ChoiceLine] = []
    var choicePhaseVal: Int = 0
    var cursorVal: Int = -1
    var previousCursorVal: Int = -1
    var choiceAlphaVal: Float = 0
    var choiceFlashVal: Float = 0
    var choiceHighlightVal: Float = 0
    var choiceHeadVal: Float = 0
    var decidedVal: Int = -1
    var glow: ChoiceGlow!
    var glowTextCache: [ChoiceGlowKey: TextBlock] = [:]
    var selectSizesCache: [Int: (width: Int, height: Int)] = [:]
    public var choiceTrace: [ChoiceDraw]?
    public var savePromptAccepted: (() -> Void)?
    public var choiceDecided: ((ChoiceKind, Int, Int, Int) -> Void)?

    // Prompt
    var promptSaveDoneVal: Bool = false
    var promptPointerVal: (x: Int16, y: Int16)?

    // Movie
    var movieRec: MovieRecord?
    var movieOut: [MovieCommand] = []
    var clocks: [Int: MovieClock] = [:]
    public var movieStarted: ((Int) -> Void)?
    public var movieEnded: ((Int) -> Void)?

    // Marks
    var staffTask: Bool = false
    public var nodeCompleted: ((Int) -> Void)?
    public var autoSkipOffered: ((Int) -> Void)?

    // LookAhead
    var lookScript: Int = -1
    var lookOffset: Int = -1
    var lookDone: Set<StageRuntime.LookAheadKey> = []

    // History / Restore
    let committedScene: SceneState = SceneState.createDefault()
    var restoresCount: Int = 0
    public internal(set) var lastRestore: RestoreReport?
    public var restored: ((RestoreReport) -> Void)?

    // Draw
    public internal(set) var sceneCommandCount: Int = 0
    var sheetSizesCache: [Int: (width: Int, height: Int)] = [:]

    /// Creates a host over the game data. The profile (system block, G words) is new; use `profile` to carry one over.
    public init(services: GameServices, options: GameOptions? = nil, profile: GameProfile? = nil) {
        self.services = services
        let opt = options ?? GameOptions()
        self.options = opt
        self.data = services.data
        self.flow = services.data.eboot.gameFlow
        self.fonts = services.data.eboot.gameFonts
        self.language = opt.language
        let prof = profile ?? GameProfile.createNew(opt.language)
        self.profile = prof
        self.varState = VarState(VarMemory(prof.vars, policy: .flat))
        self.markers = MarkerState(prof.system)
        self.wait = WaitState()
        self.sink = NullHistorySink.instance

        self.stage = createStage()
        self.sound = createSound()
        self.vm = ScriptVm(services.scripts, varState, markers, 0)

        initMessages()
        initMovie()
        initChoice()
    }

    private func createStage() -> StageRuntime {
        let t = data.eboot
        let stg = StageRuntime(
            catalog: t.pictures,
            motions: t.motions,
            rng: options.randomSeed == 0 ? nil : Ps4Rand(state: UInt64(options.randomSeed))
        )
        stg.hazeTable = t.haze
        stg.clipRadii = t.clipRadii
        stg.layouts = services.layouts
        stg.language = Int(language.rawValue)
        stg.motionWaitConfig = Int(config.constant50)
        self.focus = FocusEffect(tables: t.effects, rng: stg.rng)
        self.ghost = GhostEffect()
        stg.afterLayers = { [weak self] list in
            self?.drawScreenEffects(list)
        }
        return stg
    }

    private func createSound() -> SoundModel {
        let model = SoundModel(config: SoundConfig(), seLookup: services.seLookup)
        model.config.readFrom(config)
        if !options.sound {
            model.isPlaying = { _ in false }
        } else {
            model.isPlaying = externalPlaying ?? { [weak self] stream in
                self?.audio.isPlaying(stream) ?? false
            }
        }
        return model
    }

    // -- starting a story ---------------------------------------------------------------------------------------------------------

    /// Starts a new playthrough at scene `sceneId`: the F and Z words are cleared (the G words and the system block stay), the
    /// stage, sound, messages and waits start fresh, and the script runs from its top (or from `label`).
    public func newGame(_ sceneId: Int, label: String? = nil) {
        profile.clearPlaythrough()
        resetRuntime()
        if !enterScene(sceneId, label: label, jump: false) {
            phase = .ended
            endReason = .missingScene
        }
    }

    /// The scene a New Game starts: START_SCRIPT (110) once scene 260 (the prologue movie, bit 485) was read, else the prologue (script.md 7).
    public func newGameSceneId() -> Int {
        isSceneReached(485) ? 110 : 260
    }

    /// Resets runtime state for a new playthrough or restore.
    func resetRuntime(keepBgm: Bool = false) {
        wait.bits = 0
        wait.flags = 0
        wait.timer = 0
        wait.auto = 0
        wait.timerNoClick = 0
        wait.stcfLayers = 0
        for i in 0..<wait.stcfMask.count {
            wait.stcfMask[i] = 0
        }
        wait.advanceLatch = 0
        wait.head = 0
        wait.tail = 0
        wait.width = 0
        wait.advKey = 0
        wait.newPage = 0
        wait.windowTarget = 0
        wait.windowAlpha = 0
        wait.textFadeStep = 0
        wait.readSel = 0
        wait.voiceState = 0
        wait.fadeState = 0
        varState.choiceMode = ChoiceMode.none.rawValue
        varState.choiceCount = 0
        varState.choiceValues.removeAll()
        varState.choiceLocked.removeAll()
        varState.choiceId = -1
        varState.skipCounter = 0
        stage = createStage()
        let previous = sound
        sound = createSound()
        if keepBgm, let prev = previous {
            sound.adoptBgm(prev)
        }

        audio.reset(fromStream: keepBgm ? AudioStreams.firstVoice : 0)
        resetMessages()
        resetMovie()
        resetChoice()
        resetEffects()
        resetMarks()
        modeWord = 0
        replayRequested = false
        skipStoppedByReadRule = false
        phase = .notStarted
        endReason = .none
    }

    /// Enters scene `sceneId` (a new game or a `_JUMP`) and positions the VM at `label` or the script start.
    /// A scene id the table does not have falls back to START_SCRIPT (script.md 6.1). Returns false when no script can be found.
    func enterScene(_ sceneId: Int, label: String?, jump: Bool) -> Bool {
        var k = flow.scriptOfSceneId(sceneId)
        if k < 0 {
            k = flow.scriptOfSceneId(110)
            if k < 0 {
                return false
            }
        }

        var target = ScriptPosition(script: k, offset: 0)
        if let lbl = label, !lbl.isEmpty {
            let offset = services.scripts.labels(k).find(lbl)
            if offset < 0 {
                return false
            }
            target = ScriptPosition(script: k, offset: offset)
        }

        if !jump {
            vm = ScriptVm(services.scripts, varState, markers, k, target.offset)
            if let obs = traceObserver {
                vm.observer = obs
            }
        }

        lastSceneScript = k
        scriptsReached.insert(k)
        phase = .running
        sceneEntered?(k, flow.sceneId(k))
        return true
    }

    /// Sets the statement observer of the VM (traces and tests); nil removes it.
    public func setObserver(_ observer: ((FlowStep) -> Void)?) {
        traceObserver = observer
        vm.observer = observer
    }

    // -- the command dispatch -----------------------------------------------------------------------------------------------------

    public func dispatch(_ statement: Statement) -> StepResult {
        if let slow = slowStatement {
            let t0 = DispatchTime.now().uptimeNanoseconds
            let result = dispatchCore(statement)
            let dtNs = DispatchTime.now().uptimeNanoseconds - t0
            let ms = Double(dtNs) / 1_000_000.0
            if ms >= 5.0 {
                slow(statement.name.description, statement.script, statement.offset, ms)
            }
            return result
        }

        return dispatchCore(statement)
    }

    private func dispatchCore(_ statement: Statement) -> StepResult {
        dispatchCount += 1
        let cmd = GameCommands.classify(statement.name)
        switch cmd {
        case .stage:
            return dispatchStage(statement)
        case .sound:
            return dispatchSound(statement)
        case .zoneMessage:
            return cmdMessage(statement)
        case .zoneDisabled:
            return StepResult.continue
        case .msad:
            return cmdMsad(statement)
        case .wnty:
            return cmdWnty(statement)
        case .pgst:
            return cmdPgst(statement)
        case .clo2:
            return cmdClo2()
        case .clo3:
            return cmdClo3()
        case .clo4:
            return cmdClo4(statement)
        case .clo5:
            return cmdClo5(statement)
        case .wttm, .wttr:
            return cmdWttm(statement)
        case .wtsv:
            return cmdWtsv(statement)
        case .selr:
            return cmdSelr(statement)
        case .seld:
            return cmdSeld(statement)
        case .sels:
            return cmdSels(statement)
        case .sela:
            return cmdSela(statement)
        case .vcwt:
            return cmdVcwt()
        case .tomp:
            return cmdTomp(statement)
        case .tomw:
            return cmdTomw(statement)
        case .jump:
            return cmdJump(statement)
        case .end:
            return scriptEnd(reason: .end, keepBgm: false)
        case .rtm:
            return scriptEnd(reason: .returnToTitle, keepBgm: false)
        case .rtmn:
            keepBgm = true
            return scriptEnd(reason: .returnKeepBgm, keepBgm: true)
        case .rtm2:
            keepBgm = true
            return StepResult.continue
        case .ifsc:
            return jumpToLabelArg(statement, 1, condition: !replayRequested)
        case .ifur:
            return jumpToLabelArg(statement, 1, condition: allEndingsDone())
        case .ifla:
            return jumpToLabelArg(statement, 1, condition: inlineInt(statement, 0) != Int(language.rawValue))
        case .ifjp, .ifp4, .ifnx, .iff, .els, .eif, .nop, .ignored:
            return StepResult.continue
        case .atsv:
            return cmdAtsv(statement)
        case .rdst:
            return cmdRdst(statement)
        case .rtst:
            return cmdRtst(statement)
        case .rded:
            return cmdRded(statement)
        case .rdas:
            return cmdRdas(statement)
        case .trpy:
            trophyUnlocked?(inlineInt(statement, 0))
            return StepResult.continue
        case .xstp:
            return cmdXstp()
        case .xrsm:
            return cmdXrsm()
        case .fcln, .fcsp, .flnt, .flop, .flsp, .fccl:
            return cmdFocus(statement, cmd)
        case .fade:
            return cmdFade(statement)
        case .stcg:
            return cmdStcg(statement)
        case .spfc, .sprd, .sprc, .stpv:
            return dispatchStage(statement)
        default:
            return cmdUnknown(statement)
        }
    }

    func cmdUnknown(_ st: Statement) -> StepResult {
        let name = st.name.description
        unknown[name, default: 0] += 1
        if options.strictCommands && !options.recordUnknownCommands {
            // Error
        }
        return StepResult.continue
    }

    // -- flow ---------------------------------------------------------------------------------------------------------------------

    /// True while a gallery replay runs (`F024`, set by the ARCHIVE scene itself; the replay scenes end at their `_RDED`).
    public var archiveMode: Bool { f(24) != 0 }

    /// Starts a gallery replay: the ARCHIVE scene (3000) runs with G008 = `sceneId` (the scene to replay); the scene sets F024 / F025
    /// itself and jumps to the replayed scene, which ends at its `_RDED` (script.md 7, gallery.md 2).
    public func startReplay(_ sceneId: Int) -> Bool {
        profile.clearPlaythrough()
        resetRuntime()
        vars.setG(8, UInt16(truncatingIfNeeded: sceneId))
        replayRequested = true
        return enterScene(3000, label: nil, jump: false)
    }

    func inlineInt(_ st: Statement, _ index: Int) -> Int {
        InlineReader.readInt16(st, index)
    }

    func jumpToLabelArg(_ st: Statement, _ argIndex: Int, condition: Bool) -> StepResult {
        guard condition else { return StepResult.continue }
        let label = argText(st, argIndex)
        guard !label.isEmpty else { return StepResult.continue }
        guard let pos = labelPosition(label) else { return StepResult.continue }
        return StepResult.continueAt(pos)
    }

    func labelPosition(_ label: String) -> ScriptPosition? {
        let offset = services.scripts.labels(vm.image.index).find(label)
        guard offset >= 0 else { return nil }
        return ScriptPosition(script: vm.image.index, offset: offset)
    }

    /// The text of textual argument `index` (Latin-1; the inline layout of an ordinary command).
    func argText(_ st: Statement, _ index: Int) -> String {
        let a = st.args
        var ranges: [ArgRange] = []
        _ = ArgumentList.split(a, ArgumentList.startIn(st), into: &ranges)
        guard index < ranges.count else { return "" }
        let slice = ranges[index].slice(a)
        return String(slice.map { Character(UnicodeScalar($0)) })
    }

    func cmdJump(_ st: Statement) -> StepResult {
        endSceneSkip()
        let idText = argText(st, 0)
        let id = ObjectParser.partialInt(ByteSpan([UInt8](idText.utf8))) ?? -1
        var label = argText(st, 1)
        var k = flow.scriptOfSceneId(id)
        markSceneJump(fromScript: vm.image.index, toSceneId: id)
        sink.onSceneJump(fromScript: vm.image.index, toSceneId: id)
        if k < 0 {
            // script.md 6.1: unknown ids fall back to START_SCRIPT
            k = flow.scriptOfSceneId(110)
            label = ""
            if k < 0 {
                phase = .ended
                endReason = .missingScene
                return StepResult.halt
            }
        }

        var offset = 0
        if !label.isEmpty {
            offset = services.scripts.labels(k).find(label)
            if offset < 0 {
                offset = 0
            }
        }

        lastSceneScript = k
        scriptsReached.insert(k)
        sceneEntered?(k, flow.sceneId(k))
        return StepResult.yieldAt(ScriptPosition(script: k, offset: offset))
    }

    /// The script-end cleanup (VA 0x7F1A0; END_, RTM_, RTMN): every SE channel stops, the voice stops, the BGM stops unless the keep flag
    /// (RTMN / RTM2) is set, the window closes. The host halts the VM; the caller returns to the title (`phase` = ended).
    func scriptEnd(reason: EndReason, keepBgm: Bool) -> StepResult {
        endSceneSkip()
        endReason = reason
        phase = .ended
        _ = try? sound.run("_SESP(-1);")
        sound.stopVoice()
        if !keepBgm && !self.keepBgm {
            _ = try? sound.run("_MPLY(-1);")
        }

        self.keepBgm = false
        wait.bits = 0
        sink.onScriptEnd(reason: reason)
        return StepResult.halt
    }
}
