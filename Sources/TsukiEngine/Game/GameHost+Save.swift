import Foundation
import TsukiCore

/// The kinds of history record the interpreter pushes (adv_state.md 2.3).
public enum HistoryKind: UInt8, Sendable {
    /// The `_ZM` message marker (site VA 0x9291F).
    case message = 0

    /// The first layer change since the last commit (F991 was 0).
    case layerBatchStart = 1

    /// Music: `MPLY MFAD MVOL MSTP`.
    case music = 2

    /// Sound effects: `SEPL SEVL SEFD SESP` and friends.
    case soundEffect = 3

    /// Scene start: `_ATSV()` and `_ATSV(8)`.
    case sceneStart = 6

    /// Choice save point: `_ATSV(n)` with `n & 3 == 1`.
    case choicePoint = 7

    /// Commit point of a pending layer change (F991 != 0).
    case layerCommit = 9

    /// The start of a choice (`_SELD`).
    case choiceStart = 12

    /// A choice line (`_SELR`, the first of a group).
    case choiceLine = 13
}

/// One hook per push site of the history ring and of the save machinery (adv_state.md 2.4, 2.5, 5, 7).
public protocol HistorySink: AnyObject {
    func push(kind: HistoryKind, position: ScriptPosition, resume: ScriptPosition)
    func sceneStackPush()
    func autoSave()
    func setMessageText(_ text: [UInt8])
    func onSceneJump(fromScript: Int, toSceneId: Int)
    func onScriptEnd(reason: EndReason)
    func onChoiceTaken(choiceId: Int, option: Int)
    func onMessageShown()
    func onVoiceStarted(voiceId: Int, character: Int16, speakerRow: Int8)
    func updateStaging()
}

public typealias IHistorySink = HistorySink

/// A sink that records nothing.
public final class NullHistorySink: HistorySink {
    public static let instance = NullHistorySink()

    public init() {}

    public func push(kind: HistoryKind, position: ScriptPosition, resume: ScriptPosition) {}
    public func sceneStackPush() {}
    public func autoSave() {}
    public func setMessageText(_ text: [UInt8]) {}
    public func onSceneJump(fromScript: Int, toSceneId: Int) {}
    public func onScriptEnd(reason: EndReason) {}
    public func onChoiceTaken(choiceId: Int, option: Int) {}
    public func onMessageShown() {}
    public func onVoiceStarted(voiceId: Int, character: Int16, speakerRow: Int8) {}
    public func updateStaging() {}
}

/// Maps the interpreter's push-site hooks onto the history ring of package K4 (`AdvHistory`).
public final class AdvHistorySink: HistorySink {
    private unowned let host: GameHost
    private let clock: () -> SlotDate

    public let history: AdvHistory
    public let live: AdvLiveState
    public let store: SaveStore?
    public private(set) var pushes: Int64 = 0
    public var thumbnailProvider: (() -> SlotThumbnail?)?
    public var autoSaved: (() -> Void)?
    public var sceneStackPushed: (() -> Void)?

    public init(host: GameHost, history: AdvHistory, live: AdvLiveState, store: SaveStore? = nil, clock: (() -> SlotDate)? = nil) {
        self.host = host
        self.history = history
        self.live = live
        self.store = store
        self.clock = clock ?? {
            let cal = Calendar.current
            let d = Date()
            return SlotDate(
                year: cal.component(.year, from: d),
                month: cal.component(.month, from: d),
                day: cal.component(.day, from: d),
                hour: cal.component(.hour, from: d),
                minute: cal.component(.minute, from: d),
                second: cal.component(.second, from: d)
            )
        }
    }

    public func push(kind: HistoryKind, position: ScriptPosition, resume: ScriptPosition) {
        host.fillLive(live, script: position.script)
        let cmd = UInt64(max(0, position.offset - 1))
        if history.push(live: live, cmdOffset: cmd, resumeOffset: UInt64(resume.offset), kind: UInt16(kind.rawValue)) {
            pushes += 1
        }
    }

    public func sceneStackPush() {
        if history.pushSceneStack(effectBlockingBits: live.effectBlockingBits) {
            sceneStackPushed?()
        }
    }

    public func autoSave() {
        if let store = store {
            let date = clock()
            let thumb = thumbnailProvider?()
            if store.autoSave(history.staging, date, thumb) {
                autoSaved?()
            }
        }
    }

    public func setMessageText(_ text: [UInt8]) {
        history.setNewestMessageText(text)
    }

    public func onSceneJump(fromScript: Int, toSceneId: Int) {}
    public func onScriptEnd(reason: EndReason) {}
    public func onChoiceTaken(choiceId: Int, option: Int) {}
    public func onMessageShown() { history.onMessageShown() }
    public func onVoiceStarted(voiceId: Int, character: Int16, speakerRow: Int8) {
        if live.restoredFromHistory == 0 {
            history.setNewestVoice(voiceId: Int32(voiceId), voiceCharacter: character, speaker: speakerRow)
        }
    }

    public func updateStaging() {
        host.fillLive(live, script: host.script)
        _ = history.updateStaging(history.newest, live)
    }
}

/// What kind of restore ran (`GameHost.restored`).
public enum RestoreKind: UInt8, Sendable {
    case load
    case rewind
    case previousScene
    case backlogJump
}

/// What a restore did (for the services, the tests and the log).
public struct RestoreReport: Sendable {
    public let kind: RestoreKind
    public let script: Int
    public let offset: Int
    public let recordKind: Int
    public let redisplayed: Bool
    public let bgmTrack: Int
    public let loopSeChannels: Int

    public init(kind: RestoreKind, script: Int, offset: Int, recordKind: Int, redisplayed: Bool, bgmTrack: Int, loopSeChannels: Int) {
        self.kind = kind
        self.script = script
        self.offset = offset
        self.recordKind = recordKind
        self.redisplayed = redisplayed
        self.bgmTrack = bgmTrack
        self.loopSeChannels = loopSeChannels
    }
}

extension GameHost {
    static let layerBatchFlagVar = 991
    static let historySuppressVar = 929
    static let historyModeVar = 1102

    /// Creates the history ring over this host and plugs it into the push sites (`sink`).
    public func attachHistory(store: SaveStore? = nil) -> AdvHistorySink {
        let live = AdvLiveState(vars: vars, config: config, scene: SceneState.createDefault(), committed: SceneState.createDefault())
        let sink = AdvHistorySink(host: self, history: AdvHistory(), live: live, store: store)
        self.sink = sink
        return sink
    }

    /// Fills the part of `live` that History_Push copies into a record from the interpreter, stage, sound model and message window.
    public func fillLive(_ live: AdvLiveState, script: Int) {
        live.scriptNumber = UInt16(truncatingIfNeeded: script)
        live.scene.copy(from: stage.scene)
        live.committed.copy(from: committedScene)
        live.textBlock = markers.block
        live.textLine = markers.sub
        live.textBlock2 = markers.block
        live.textLine2 = markers.sub
        for i in 0..<min(namePlateBytes.count, live.window164FD40.count) {
            live.window164FD40[i] = namePlateBytes[i]
        }
        live.var1654208 = UInt16(truncatingIfNeeded: sound.pendingVoiceCharacter)
        live.var165420A = UInt16(truncatingIfNeeded: sound.voiceArg3)
        for i in 0..<live.messageText.count {
            live.messageText[i] = 0
        }
        if let cur = currentMsg {
            let take = min(cur.text.count, AdvLiveState.messageTextSize - 2)
            for i in 0..<take {
                live.messageText[i] = cur.text[i]
            }
        }

        live.bgmTrack = Int16(truncatingIfNeeded: sound.scriptTrack)
        live.bgmVolume = Int16(truncatingIfNeeded: sound.scriptBgmVolume)
        for ch in 0..<AdvLiveState.soundChannels {
            let se = sound.scriptSe
            live.loopSeIds[ch] = Int16(truncatingIfNeeded: se.loopEntry(ch))
            live.seVolA[ch] = UInt16(truncatingIfNeeded: se.volume(ch))
            live.seVolB[ch] = UInt16(truncatingIfNeeded: se.looped(ch))
            live.seArrC[ch] = Int16(truncatingIfNeeded: se.pan(ch))
            live.seArrE[ch] = UInt8(truncatingIfNeeded: se.character(ch))
        }

        live.voiceId = Int32(sound.lastVoice)
        live.var16541F4 = UInt8(continueByte ? 1 : 0)
        live.var86AA24 = UInt32(wait.newPage)
        live.textFade = textFadeVal
        live.var1653E24 = wait.textFadeStep.bitPattern
        live.waitFlags = wait.bits
        live.waitFlags70 = wait.flags
        live.word1653E08 = UInt16(truncatingIfNeeded: wait.timer)
        live.effectActiveBits = UInt16(movieActive ? 1 : 0)
        live.effectBlockingBits = live.effectActiveBits
        live.lastMessageOfPage = f(799) == 1
        live.pageEndInstantLatch = wait.pageLatch
        live.scanMode = 0
    }

    func copyCommitted() {
        committedScene.copy(from: stage.scene)
    }

    func pushAllowed(_ kind: HistoryKind) -> Bool {
        if f(Self.historySuppressVar) != 0 || continueByte {
            return false
        }
        return f(Self.historyModeVar) == 0 || kind == .message || kind.rawValue == 11
    }

    func push(_ kind: HistoryKind, _ st: Statement) {
        if pushAllowed(kind) {
            sink.push(kind: kind, position: st.position, resume: st.next)
        }
    }

    func noteLayerChange(_ st: Statement) {
        if f(Self.layerBatchFlagVar) == 0 {
            push(.layerBatchStart, st)
            copyCommitted()
            setF(Self.layerBatchFlagVar, 1)
        }
    }

    func commitLayerChange(_ st: Statement) {
        if f(Self.layerBatchFlagVar) != 0 {
            copyCommitted()
            push(.layerCommit, st)
            setF(Self.layerBatchFlagVar, 0)
        }
    }

    func cmdAtsv(_ st: Statement) -> StepResult {
        let hasArg = InlineReader.isPresent(st, 0)
        let n = hasArg ? InlineReader.readInt16(st, 0) : 2
        let low = hasArg ? (n & 3) : 2
        if skipScene {
            endSceneSkip()
        }

        if n == 8 && hasArg {
            push(.sceneStart, st)
            sink.setMessageText([])
            sink.updateStaging()
            sink.sceneStackPush()
            sink.autoSave()
            return StepResult.continue
        }

        let kind: HistoryKind = (low == 1) ? .choicePoint : .sceneStart
        push(kind, st)
        sink.setMessageText((kind == .choicePoint && currentMsg != nil) ? currentMsg!.text : [])
        sink.updateStaging()

        if !hasArg || low == 2 || (n & 4) == 0 {
            sink.sceneStackPush()
        }

        return StepResult.continue
    }

    // MARK: - Restore

    /// The history sink (ring, live state, save store), or nil when `attachHistory` was not called.
    public var historySink: AdvHistorySink? { sink as? AdvHistorySink }

    /// The history ring, or nil.
    public var history: AdvHistory? { historySink?.history }

    /// Restores performed so far.
    public var restoreCount: Int { restoresCount }

    private var scriptBytes: ScriptBytesProvider {
        { [weak self] script in
            guard let self = self else { return [] }
            return self.services.scripts.script(Int(script)).bytes
        }
    }

    private var blockingEffectBits: UInt16 {
        UInt16(movieActive ? 1 : 0)
    }

    /// True when a rewind step has somewhere to go.
    public var canRewind: Bool {
        phase == .running && historySink != nil && history!.canRewind
    }

    /// True when the previous-scene action would restore something now.
    public var canGoToPreviousScene: Bool {
        phase == .running && historySink != nil && history!.canGoToPreviousScene(effectBlockingBits: blockingEffectBits, waitFlag10: choiceOpen)
    }

    public func beginStory(_ sceneId: Int, label: String? = nil) {
        if let h = historySink {
            h.history.clear(live: h.live)
            h.live.resetSound()
        }
        newGame(sceneId, label: label)
        stopEverythingOutside()
    }

    public func beginReplay(_ sceneId: Int) -> Bool {
        if let h = historySink {
            h.history.clear(live: h.live)
            h.live.resetSound()
        }
        let started = startReplay(sceneId)
        stopEverythingOutside()
        return started
    }

    public func beginFlowchartJump(column: Int, node: Int, sceneId: Int) -> Bool {
        if !jumpToRecord(column: column, node: node, sceneId: sceneId) {
            return false
        }
        if let h = historySink {
            h.history.clear(live: h.live)
            h.live.resetSound()
        }
        stopEverythingOutside()
        return true
    }

    func stopEverythingOutside(fromStream: Int = 0) {
        audioOut.append(contentsOf: SoundModel.stopEverything(fromStream: fromStream))
        movieOut.append(MovieCommand.stop(MovieSlots.fullScreen))
    }

    public func rewindStep() -> Bool {
        guard canRewind, let h = historySink else { return false }
        let r = h.history.rewindStep(live: h.live, scripts: scriptBytes)
        guard r.stepped, !r.restores.isEmpty else { return false }

        let last = r.restores[r.restores.count - 1]
        applyRestore(kind: .rewind, last: last, live: h.live, redisplay: last.redisplay, stopEffects: r.stopEffectSlots)
        return true
    }

    public func previousScene() -> Bool {
        guard phase == .running, let h = historySink else { return false }
        var flushPending = false
        guard let r = h.history.previousScene(live: h.live, effectBlockingBits: blockingEffectBits, waitFlag10: choiceOpen, flushPending: &flushPending) else {
            return false
        }

        applyRestore(kind: .previousScene, last: r.restore, live: h.live, redisplay: nil, stopEffects: 0)
        replayVoiceOf(r)
        return true
    }

    public func backlogJump(_ ringIndex: Int) -> Bool {
        guard phase == .running, let h = historySink else { return false }
        guard let o = h.history.backlogJump(ringIndex, h.live) else { return false }

        applyRestore(kind: .backlogJump, last: o, live: h.live, redisplay: nil, stopEffects: 0)
        return true
    }

    public func loadSlot(_ store: SaveStore, slot: Int) throws {
        guard let h = historySink else {
            throw TsukiError.state("no history is attached")
        }
        let r = try store.load(slot, h.history, h.live)
        applyRestore(kind: .load, last: r.restore, live: h.live, redisplay: nil, stopEffects: 0)
        replayVoiceOf(r)
    }

    private func replayVoiceOf(_ r: SceneRestoreResult) {
        if r.replayVoiceId >= 0 {
            sound.setPendingVoice(r.replayVoiceId, Int(r.replayVoiceCharacter))
        }
    }

    func applyRestore(kind: RestoreKind, last: RestoreOutcome, live: AdvLiveState, redisplay: RedisplayInfo?, stopEffects: UInt16) {
        endSceneSkip(resync: false)
        let autoBit = modeWord & 1
        let replay = replayRequested
        let keepBgm = (kind == .rewind) && (sound.currentTrack == Int(live.bgmTrack))
        resetRuntime(keepBgm: keepBgm)
        replayRequested = replay
        modeWord = autoBit
        phase = .running
        endReason = .none
        stopEverythingOutside(fromStream: keepBgm ? AudioStreams.firstVoice : 0)

        if last.rebuildFromCommitted {
            stage.scene.copy(from: live.committed)
            stage.commit(type: 0, ms: 0, rule: 0)
            stage.update(arg: 1)
            stage.update(arg: 1)
            stage.scene.copy(from: live.scene)
        } else {
            stage.scene.copy(from: live.scene)
            stage.commit(type: 0, ms: 0, rule: 0)
            stage.update(arg: 1)
            stage.update(arg: 1)
        }

        committedScene.copy(from: live.committed)

        var loops = 0
        for ch in 0..<AdvLiveState.soundChannels {
            if live.loopSeIds[ch] >= 0 && live.seVolB[ch] != 0 {
                loops += 1
            }
        }

        sound.restoreScriptState(
            bgmTrack: Int(live.bgmTrack),
            bgmVolume: Int(live.bgmVolume),
            loopSeIds: live.loopSeIds,
            volume: live.seVolA,
            looped: live.seVolB,
            pan: live.seArrC,
            character: live.seArrE
        )
        drainSound()

        restoreEffects()

        markers.restore(live.textBlock, live.textLine)
        vm.seek(ScriptPosition(script: Int(live.scriptNumber), offset: Int(live.scriptOffset)))
        lastSceneScript = Int(live.scriptNumber)
        scriptsReached.insert(Int(live.scriptNumber))

        if last.kind == AdvHistory.Kinds.message || last.kind == AdvHistory.Kinds.choiceStart || last.kind == AdvHistory.Kinds.choiceLine {
            wait.windowTarget = 1
            wait.windowAlpha = 1.0
        }

        textFadeVal = 1.0
        setNamePlate(live.window164FD40)
        var shown = false
        if let redisp = redisplay {
            showRestoredMessage(redisp, live: live)
            shown = true
        } else if let recText = last.showRecordText, !recText.isEmpty {
            showRestoredMessage(RedisplayInfo(text: recText, endCode: 0, namePlate: [UInt8](repeating: 0, count: 0x1C)), live: live)
            shown = true
        }

        let report = RestoreReport(
            kind: kind,
            script: Int(live.scriptNumber),
            offset: Int(live.scriptOffset),
            recordKind: Int(last.kind),
            redisplayed: shown,
            bgmTrack: Int(live.bgmTrack),
            loopSeChannels: loops
        )
        lastRestore = report
        restoresCount += 1
        restored?(report)
    }

    func showRestoredMessage(_ info: RedisplayInfo, live: AdvLiveState) {
        let raw = info.text
        let text = expandMessage(raw)
        let block = live.textBlock
        let sub = live.textLine
        let max = (block >= 0 && block <= MarkerState.maxRecordedBlock) ? Int(profile.system.getReadmax(block)) : 0
        let read = max != 0 && sub <= max
        let mode: MessageEnd
        switch info.endCode {
        case 1: mode = .continue
        case 2: mode = .noWait
        default: mode = .click
        }

        let f823 = f(823)
        page.removeAll()
        let (layout, colour) = layoutText(text, read: read)
        setNamePlate(info.namePlate)
        let f32 = f(32)
        let msg = PageMessage()
        msg.raw = raw
        msg.text = text
        msg.block = layout
        msg.records = Self.recordsOf(layout)
        msg.end = mode
        msg.colour = colour
        msg.read = read
        msg.blank = f(846 + f823)
        msg.scaleY = f32 > 0 ? Double(f32) / 24.0 : 1.0
        msg.index = f823
        msg.window = windowIndex()
        let clampedIdx = Swift.min(Swift.max(f823, 0), 11)
        msg.dimLimit = Float(f(870 + clampedIdx) + 128) * 1.2

        page.append(msg)
        currentMsg = msg
        currentRaw = raw
        windowHiddenVal = false
        wait.readSel = read ? 1 : 0
        wait.head = 0
        wait.tail = 0
        continueByte = mode == .continue
        wait.flags |= WaitBits.reveal
        wait.bits |= (mode == .click ? WaitBits.click : 0) | WaitBits.message
        if wait.flags != 0 {
            wait.bits |= wait.flags
        }
    }

    // MARK: - LookAhead

    /// Appends to `into` the picture tiles that the next statements will need.
    public func lookAhead(_ into: inout [TextureRef]) {
        guard phase == .running else { return }

        let at = vm.position
        if at.script == lookScript && at.offset == lookOffset {
            return
        }

        if at.script != lookScript || lookDone.count > 400 {
            lookDone.removeAll()
        }

        lookScript = at.script
        lookOffset = at.offset
        let bytes = vm.image.bytes
        let span = ByteSpan(bytes)
        var pos = at.offset
        var messages = 0
        let scan = stage.beginLookAhead()

        for _ in 0..<400 where pos < bytes.count && messages < 10 {
            guard let seg = try? ScriptSegmenter.read(span, pos) else { break }
            pos = seg.end
            guard let st = ScriptSegmenter.statement(at.script, span, seg) else { continue }

            if GameCommands.classify(st.name) == .zoneMessage {
                messages += 1
            } else if scan.feed(st) {
                scan.flush(&into, &lookDone)
            }
        }

        scan.flush(&into, &lookDone)
    }
}
