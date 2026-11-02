import Foundation
import TsukiCore
import TsukiEngine
import TsukiMedia
import TsukiUi

extension AppServices: UiStoryServices, UiGalleryServices {
    public var phase: Int {
        host.f(23)
    }

    public var sceneTitle: Int {
        host.f(22)
    }

    public var script: Int {
        Int(host.script)
    }

    public var autoMode: Bool {
        host.autoMode
    }

    public var skipMode: Bool {
        host.skipLatch
    }

    public var sceneJumpEnabled: Bool {
        host.config.sceneJumpButtons != 0
    }

    public var panelAllowed: Bool {
        storyActive && host.phase == .running && !host.movieActive && !host.choiceOpen && !host.archiveMode
    }

    public var storyPrompt: UiStoryPrompt? {
        if storyActive && host.phase == .running && host.promptOpen && host.choiceAlpha > 0 {
            return UiStoryPrompt(
                messageId: host.promptMessageId,
                cursor: host.choiceCursor,
                alpha: host.choiceAlpha,
                scale: host.promptScale
            )
        }
        return nil
    }

    public func toggleAuto() {
        host.setAutoMode(!host.autoMode)
    }

    public func toggleSkip() {
        host.setSkipLatch(!host.skipLatch)
    }

    public func fastForward(_ held: Bool) {
        fastForwardHeld = held
    }

    public func rewind(_ held: Bool) {
        rewindHeld = held
    }

    public func replayVoice() {
        let voice = host.sound.lastVoice
        if voice < 0 {
            return
        }
        host.sound.setPendingVoice(voice, host.sound.pendingVoiceCharacter)
        _ = host.sound.startVoiceAtMessage()
        flushMenuSound()
    }

    public func nextScene() {
        _ = host.requestNextScene()
    }

    public func previousScene() {
        if host.previousScene() {
            host.setSkipLatch(false)
        }
    }

    public func startScene(_ sceneId: Int) {
        stopMenuAudio()
        stopIntroMovie()
        stopTitleMovie()
        host.beginStory(sceneId)
        host.setSkipLatch(false)
        storyActive = true
        lastStartedScene = sceneId
    }

    public func resumeLoaded() {
        storyActive = (host.phase == .running)
    }

    public func returnToTitle() {
        storyActive = false
        _ = commit()
        pendingTitle = true
    }

    public func takePendingTitle() -> Bool {
        let p = pendingTitle
        pendingTitle = false
        return p
    }

    public func stopStoryOutputs() {
        parts.audio?.perform(SoundModel.stopEverything())
        parts.movies?.perform(MovieCommand.stop(MovieSlots.fullScreen))
        menuBgm = 0
    }

    public var backlog: [BacklogPage] {
        backlogRings.removeAll()
        backlogVoiceCharacter.removeAll()
        var pages = [BacklogPage]()
        guard storyActive, let history = host.history else {
            return pages
        }

        let ring = history.backlogEntries()
        var current = [Int]()
        for i in ring {
            let rec = history.record(i)
            current.append(i)
            let pageStart = AdvHistory.recordF8(rec, AdvLiveState.FIndex.pageMessage) <= 1
            if pageStart {
                addPage(history: history, pages: &pages, newestFirst: current)
                current.removeAll()
            }
        }

        if !current.isEmpty {
            addPage(history: history, pages: &pages, newestFirst: current)
        }

        return pages
    }

    private func addPage(history: AdvHistory, pages: inout [BacklogPage], newestFirst: [Int]) {
        var messages = [BacklogMessage]()
        messages.reserveCapacity(newestFirst.count)

        for k in (0..<newestFirst.count).reversed() {
            let rec = history.record(newestFirst[k])
            if rec.kind != AdvHistory.Kinds.message {
                continue
            }

            let raw = rec.messageText
            let nul = raw.firstIndex(of: 0) ?? raw.count
            let slice = raw[0..<nul]
            let text = Array(slice)
            let f823 = AdvHistory.recordF8(rec, AdvLiveState.FIndex.pageMessage)
            let blank = AdvHistory.recordF8(rec, 846 + max(0, min(11, f823)))
            let voice = rec.voiceId >= 0 ? Int(rec.voiceId) : -1
            if voice >= 0 {
                backlogVoiceCharacter[voice] = Int(rec.voiceCharacter)
            }

            messages.append(BacklogMessage(text: text, blankBefore: max(0, blank), voiceId: voice))
        }

        if messages.isEmpty {
            return
        }

        backlogRings.append([newestFirst[newestFirst.count - 1]])
        pages.append(BacklogPage(messages: messages))
    }

    public func playBacklogVoice(_ voiceId: Int) {
        let ch = backlogVoiceCharacter[voiceId] ?? 0
        host.sound.setPendingVoice(voiceId, ch)
        _ = host.sound.startVoiceAtMessage()
        flushMenuSound()
    }

    public func backlogJump(_ page: Int) {
        guard page >= 0 && page < backlogRings.count else {
            return
        }
        if host.backlogJump(backlogRings[page][0]) {
            host.setSkipLatch(false)
        }
    }

    public func openFlowchart() {}

    public func openGallery() {
        stopTitleMovie()
    }

    public var title: UiTitleInfo {
        var latest = -1
        for i in 0...SaveStore.autoSaveLast {
            if store.hasSave(i) {
                latest = Int(store.systemData.latestSlot)
                if !store.hasSave(latest) {
                    latest = i
                }
                break
            }
        }

        return UiTitleInfo(
            prologueSeen: sceneBit(485),
            storyStarted: global(10) != 0,
            titleStage: max(0, min(5, global(2))),
            continueSlot: latest
        )
    }

    // MARK: - Gallery & Flowchart (UiGalleryServices)

    public func sceneDone(_ n: Int) -> Bool {
        SystemData.sceneDone(host.vars, n)
    }

    public func edgeSeen(_ id: Int) -> Bool {
        SystemData.edgeSeen(host.vars, id)
    }

    public func movieSeen(_ bit: Int) -> Bool {
        SystemData.movieSeen(host.vars, bit)
    }

    public func pictureSeen(_ seenIndex: Int) -> Bool {
        store.systemData.block.isPictureSeen(seenIndex)
    }

    public func bgmHeard(_ track: Int) -> Bool {
        store.systemData.block.isBgmHeard(track)
    }

    public func routeScene(_ n: Int) -> Bool {
        n >= 0 && n <= 0x23F && ((Int(host.vars.getF(201 + (n >> 3))) >> (n & 7)) & 1) != 0
    }

    public func routeEdge(_ id: Int) -> Bool {
        let e = id - 564
        return e >= 0 && e < 704 && ((Int(host.vars.getF(600 + (e >> 3))) >> (e & 7)) & 1) != 0
    }

    public var currentNode: Int {
        host.f(110)
    }

    public var playingBgm: Int {
        menuBgm > 0 ? menuBgm : max(0, host.sound.scriptTrack)
    }

    public func markBgmHeard(_ track: Int) {
        store.systemData.markBgmHeard(track)
    }

    public func playMusic(_ track: Int, volume: Float) {
        musicVolume = volume
        startMenuBgm(track, gain: volume)
    }

    public func pauseMusic(_ paused: Bool) {
        if menuBgm <= 0 || paused == musicPaused {
            return
        }

        if paused {
            musicOffsetSeconds += Double(frameCounter - musicStartedAt) / 60.0
            parts.audio?.perform([
                AudioCommand.stop(Self.menuBgmStream),
                AudioCommand.close(Self.menuBgmStream),
            ])
        } else {
            musicStartedAt = frameCounter
            parts.audio?.perform([
                AudioCommand.openFile(Self.menuBgmStream, .bgm),
                AudioCommand.setStartSample(Self.menuBgmStream, Int(musicOffsetSeconds * Double(Self.audioStreamsRate))),
                AudioCommand.play(Self.menuBgmStream, .bgm, menuBgm, loop: true, volume: musicVolume * musicGain()),
            ])
        }

        musicPaused = paused
    }

    public func setMusicVolume(_ volume: Float) {
        musicVolume = volume
        menuBgmGain = volume
        menuBgmTarget = volume
        if menuBgm > 0 && !musicPaused {
            parts.audio?.perform([AudioCommand.setVolume(Self.menuBgmStream, volume * musicGain())])
        }
    }

    public func stopMusic() {
        stopMenuAudio()
    }

    public var replayActive: Bool {
        storyActive && (host.archiveMode || host.replayRequested)
    }

    public func replayScene(_ scriptScene: Int, node: Int) {
        stopMenuAudio()
        stopIntroMovie()
        if host.beginReplay(scriptScene) {
            storyActive = true
        }
    }

    public func endReplay() {
        storyActive = false
        stopStoryOutputs()
        _ = ui?.returnToGallery()
    }

    public func flowchartJump(column: Int, node: Int, scene: Int) -> Bool {
        if !host.beginFlowchartJump(column: column, node: node, sceneId: scene) {
            return false
        }
        stopTitleMovie()
        host.setSkipLatch(false)
        storyActive = true
        return true
    }
}
