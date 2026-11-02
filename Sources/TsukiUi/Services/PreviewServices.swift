import Foundation
import TsukiCore
import TsukiEngine

/// The display settings of a preview game (package K19).
public final class PreviewDisplaySettings: UiDisplaySettings {
    private unowned let owner: PreviewServices
    private var _fullscreen: Bool = false
    private var _size: (width: Int, height: Int) = (1600, 900)

    public init(owner: PreviewServices) {
        self.owner = owner
    }

    public var fullscreen: Bool {
        get { _fullscreen }
        set {
            _fullscreen = newValue
            owner.calls.append(newValue ? "display fullscreen" : "display windowed")
        }
    }

    public var windowSize: (width: Int, height: Int) {
        get { _size }
        set {
            _size = newValue
            _fullscreen = false
            owner.calls.append("window size \(newValue.width)x\(newValue.height)")
        }
    }

    public var sizeChoices: [(width: Int, height: Int)] = [
        (1280, 720), (1600, 900), (1920, 1080), (2560, 1440)
    ]
}

/// The port's switches of a preview game.
public final class PreviewPortSettings: UiPortSettings {
    private unowned let owner: PreviewServices
    private var _mute: Bool = false
    private var _copy: Bool = false
    private var _hooker: Bool = true
    private var _socket: Bool = false
    private var _notice: Bool = true

    public init(owner: PreviewServices) {
        self.owner = owner
    }

    public var screenshotNotice: Bool {
        get { _notice }
        set {
            _notice = newValue
            owner.calls.append(newValue ? "screenshot notice on" : "screenshot notice off")
        }
    }

    public var textHookerOutput: Bool {
        get { _hooker }
        set {
            _hooker = newValue
            owner.calls.append(newValue ? "text hooker on" : "text hooker off")
        }
    }

    public var textWebSocket: Bool {
        get { _socket }
        set {
            _socket = newValue
            owner.calls.append(newValue ? "text websocket on" : "text websocket off")
        }
    }

    public var muteInBackground: Bool {
        get { _mute }
        set {
            _mute = newValue
            owner.calls.append(newValue ? "mute in background on" : "mute in background off")
        }
    }

    public var copyTextToClipboard: Bool {
        get { _copy }
        set {
            _copy = newValue
            owner.calls.append(newValue ? "copy text on" : "copy text off")
        }
    }
}

/// An in-memory `GameServices`.
public final class PreviewServices: GameServices {
    public var display: UiDisplaySettings? { _display }
    public var port: UiPortSettings? { _port }

    private var _display: PreviewDisplaySettings?
    private var _port: PreviewPortSettings?

    public var DisplaySettings: PreviewDisplaySettings? {
        get { _display }
        set { _display = newValue }
    }

    public var PortSettings: PreviewPortSettings? {
        get { _port }
        set { _port = newValue }
    }

    private var _slots: [UiSlot] = []
    private var _thumbnails: [Int: UiThumbnail] = [:]
    private var _globals: [Int: Int] = [:]
    private var _sceneBits: Set<Int> = []

    public var calls: [String] = []
    public var Calls: [String] { calls }

    public var language: Language
    public var config: ConfigBlock
    public var decideIsCross: Bool = false
    public var promptSetting: PromptSetting = .playStation
    public var lastDevice: PromptStyle = .keyboard
    public var promptStyle: PromptStyle {
        PromptStyles.resolve(promptSetting, lastDevice)
    }

    public var title: UiTitleInfo
    public var titleMovieTime: Double = -1
    public var titleMovieSlot: Int { 1 }
    public var introMovieSlot: Int { 0 }
    public var introMoviePlaying: Bool = false
    public var savingDisabled: Bool = false
    public var slots: [UiSlot] { _slots }
    public var hasQuickSave: Bool { _slots.indices.contains(139) && _slots[139].used }

    public var phase: Int = 12
    public var sceneTitle: Int = 6
    public var script: Int = 4
    public var autoMode: Bool = false
    public var skipMode: Bool = false
    public var sceneJumpEnabled: Bool = true
    public var panelAllowed: Bool = true
    public var storyPrompt: UiStoryPrompt?
    public var backlog: [BacklogPage] = []

    public let progress: PreviewProgress = PreviewProgress()
    public var Progress: PreviewProgress { progress }

    public var currentNode: Int = 0
    public private(set) var playingBgm: Int = 0
    public private(set) var musicVolume: Float = 1.0
    public private(set) var musicPaused: Bool = false
    public var replayActive: Bool = false

    public init(language: Language = .en, usedSlots: Int = 6) {
        self.language = language
        let cfg = ConfigBlock.createBootDefaults()
        cfg.language = Int16(language.rawValue)
        self.config = cfg

        let titleContinueSlot = usedSlots > 0 ? 100 : -1
        self.title = UiTitleInfo(prologueSeen: true, storyStarted: true, titleStage: 0, continueSlot: titleContinueSlot)

        self._display = nil
        self._port = nil

        let disp = PreviewDisplaySettings(owner: self)
        let prt = PreviewPortSettings(owner: self)
        self._display = disp
        self._port = prt

        _slots.reserveCapacity(140)
        for i in 0..<140 {
            _slots.append(UiSlot(index: i, used: false, date: Date(timeIntervalSince1970: 0), phase: 0, sceneTitle: 0, notes: ""))
        }

        let rng = UiRandom(seed: 7)
        for i in 0..<usedSlots {
            fill(i, phase: i, rng: rng)
        }
        fill(100, phase: 7, rng: rng)
        fill(101, phase: 5, rng: rng)
        fill(139, phase: 9, rng: rng)

        for row in 0..<19 {
            _globals[row] = 1
        }
    }

    public func setBacklog(_ pages: [BacklogPage]) {
        self.backlog = pages
    }
    public func SetBacklog(_ pages: [BacklogPage]) { setBacklog(pages) }

    public func configChanged(_ change: ConfigChange) {
        calls.append("config \(change)")
    }

    public func commitSystemData() {
        calls.append("commit")
    }

    public func global(_ index: Int) -> Int {
        _globals[index] ?? 0
    }

    public func setGlobal(_ index: Int, _ value: Int) {
        _globals[index] = value
    }

    public func sceneBit(_ bit: Int) -> Bool {
        _sceneBits.contains(bit)
    }

    public func setSceneBit(_ bit: Int, _ value: Bool) {
        if value {
            _sceneBits.insert(bit)
        } else {
            _sceneBits.remove(bit)
        }
    }
    public func SetSceneBit(_ bit: Int, _ value: Bool) { setSceneBit(bit, value) }

    public func playSystemSound(_ sound: UiSound) {
        calls.append("sound \(sound)")
    }

    public func playTestSe() {
        calls.append("test se")
    }

    public func playTestVoice(_ row: Int) -> Bool {
        calls.append("test voice \(row)")
        return true
    }

    public func stopTests() {
        calls.append("stop tests")
    }

    public func playBgm(_ track: Int) {
        calls.append("bgm \(track)")
    }

    public func fadeOutBgm(_ seconds: Float) {
        calls.append("bgm fade \(seconds)")
    }

    public func startTitleMovie(_ movieIndex: Int) {
        calls.append("title movie \(movieIndex)")
    }

    public func stopTitleMovie() {
        calls.append("title movie stop")
    }

    public func seekTitleMovie(_ seconds: Double) {
        calls.append("seek title movie \(seconds)")
    }

    public func startIntroMovie(_ movieIndex: Int) {
        calls.append("intro movie \(movieIndex)")
        introMoviePlaying = true
    }

    public func stopIntroMovie() {
        calls.append("intro movie stop")
        introMoviePlaying = false
    }

    public func thumbnail(_ slot: Int) -> UiThumbnail? {
        _thumbnails[slot]
    }

    public func save(_ slot: Int) -> Bool {
        calls.append("save \(slot)")
        fill(slot, phase: phase, rng: UiRandom(seed: UInt64(slot + 1)))
        return true
    }

    public func load(_ slot: Int) -> Bool {
        calls.append("load \(slot)")
        return _slots.indices.contains(slot) && _slots[slot].used
    }

    public func delete(_ slot: Int) -> Bool {
        calls.append("delete \(slot)")
        if _slots.indices.contains(slot) {
            _slots[slot] = UiSlot(index: slot, used: false, date: Date(timeIntervalSince1970: 0), phase: 0, sceneTitle: 0, notes: "")
        }
        _thumbnails.removeValue(forKey: slot)
        return true
    }

    public func copy(_ slot: Int) -> Bool {
        calls.append("copy \(slot)")
        guard let free = _slots.prefix(100).first(where: { !$0.used })?.index else {
            return false
        }
        if _slots[free].used || !_slots[slot].used {
            return false
        }
        var copySlot = _slots[slot]
        copySlot.index = free
        copySlot.date = Date()
        _slots[free] = copySlot
        _thumbnails[free] = _thumbnails[slot]
        return true
    }

    public func quickSave() -> Bool {
        calls.append("quick save")
        fill(139, phase: phase, rng: UiRandom(seed: 139))
        return true
    }

    public func quickLoad() -> Bool {
        calls.append("quick load")
        return hasQuickSave
    }

    public func toggleAuto() {
        autoMode = !autoMode
        calls.append("auto")
    }

    public func toggleSkip() {
        skipMode = !skipMode
        calls.append("skip")
    }

    public func fastForward(_ held: Bool) {
        calls.append("fast forward \(held)")
    }

    public func replayVoice() {
        calls.append("replay voice")
    }

    public func nextScene() {
        calls.append("next scene")
    }

    public func previousScene() {
        calls.append("previous scene")
    }

    public func rewind(_ held: Bool) {
        calls.append("rewind \(held)")
    }

    public func startScene(_ sceneId: Int) {
        calls.append("start scene \(sceneId)")
    }

    public func requestQuit() {
        calls.append("quit")
    }

    public func resumeLoaded() {
        calls.append("resume loaded")
    }

    public func autoSaveForTitle() -> Bool {
        calls.append("auto save")
        fill(100, phase: phase, rng: UiRandom(seed: 100))
        return true
    }

    public func returnToTitle() {
        calls.append("return to title")
    }

    public func playBacklogVoice(_ voiceId: Int) {
        calls.append("backlog voice \(voiceId)")
    }

    public func backlogJump(_ page: Int) {
        calls.append("backlog jump \(page)")
    }

    public func openFlowchart() {
        calls.append("open flowchart")
    }

    public func openGallery() {
        calls.append("open gallery")
    }

    public func sceneDone(_ n: Int) -> Bool { progress.sceneDone(n) }
    public func edgeSeen(_ id: Int) -> Bool { progress.edgeSeen(id) }
    public func movieSeen(_ bit: Int) -> Bool { progress.movieSeen(bit) }
    public func pictureSeen(_ seenIndex: Int) -> Bool { progress.pictureSeen(seenIndex) }
    public func bgmHeard(_ track: Int) -> Bool { progress.bgmHeard(track) }
    public func routeScene(_ n: Int) -> Bool { progress.routeScene(n) }
    public func routeEdge(_ id: Int) -> Bool { progress.routeEdge(id) }

    public func markBgmHeard(_ track: Int) {
        progress.bgm.insert(track)
        calls.append("bgm heard \(track)")
    }

    public func playMusic(_ track: Int, volume: Float) {
        playingBgm = track
        musicVolume = volume
        musicPaused = false
        calls.append("music \(track)")
    }

    public func pauseMusic(_ paused: Bool) {
        musicPaused = paused
        calls.append("music pause \(paused)")
    }

    public func setMusicVolume(_ volume: Float) {
        musicVolume = volume
        calls.append(String(format: "music volume %.2f", volume))
    }

    public func stopMusic() {
        playingBgm = 0
        musicPaused = false
        calls.append("music stop")
    }

    public func replayScene(_ scriptScene: Int, node: Int) {
        calls.append("replay \(scriptScene) \(node)")
    }

    public func endReplay() {
        calls.append("end replay")
    }

    public func flowchartJump(column: Int, node: Int, scene: Int) -> Bool {
        calls.append("flow jump \(column) \(node) \(scene)")
        return scene >= 0
    }

    public func believe(_ data: GameData, profile: String = "mid") {
        guard let tables = data.eboot.gallery else {
            return
        }

        switch profile {
        case "none":
            progress.clear()
            currentNode = 0
        case "early":
            progress.readTo(tables, lastScene: 30)
            currentNode = 30
        case "full":
            progress.everything(tables)
            currentNode = 495
        default:
            progress.readTo(tables, lastScene: 190)
            currentNode = 190
        }

        for n in progress.seen {
            setSceneBit(n, true)
        }
    }
    public func Believe(_ data: GameData, _ profile: String = "mid") {
        believe(data, profile: profile)
    }

    private func fill(_ slot: Int, phase: Int, rng: UiRandom) {
        let calendar = Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 10
        comps.day = 1 + (slot % 25)
        comps.hour = 9 + (slot % 12)
        comps.minute = (slot * 7) % 60
        comps.second = 0
        let date = calendar.date(from: comps) ?? Date()

        _slots[slot] = UiSlot(
            index: slot,
            used: true,
            date: date,
            phase: min(max(phase + 2, 0), 37),
            sceneTitle: 4 + slot,
            notes: "I walked the long corridor.^The moon was bright."
        )

        let w = 100
        let h = 56
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let seed = rng.next()
        for y in 0..<h {
            for x in 0..<w {
                let o = ((y * w) + x) * 4
                px[o] = UInt8(40 + (x * 150 / w))
                px[o + 1] = UInt8(60 + (y * 120 / h))
                px[o + 2] = UInt8(120 + Int(seed * 100.0))
                px[o + 3] = 255
            }
        }

        _thumbnails[slot] = UiThumbnail(width: w, height: h, version: 1, rgba: px)
    }
}
