import Foundation
import TsukiCore
import TsukiEngine
import TsukiMedia
import TsukiPlatform
import TsukiUi

/// What `AppServices` is made of.
public struct AppServicesParts {
    public var data: GameData
    public var hostFactory: (Language, GameProfile) -> GameHost
    public var store: SaveStore
    public var audio: AudioCommandPlayer?
    public var movies: MovieHost?
    public var savePath: String?
    public var now: (() -> Date)?
    public var initialLanguage: Language
    public var settingsPath: String?
    public var promptOverride: PromptSetting?

    public init(
        data: GameData,
        hostFactory: @escaping (Language, GameProfile) -> GameHost,
        store: SaveStore,
        audio: AudioCommandPlayer? = nil,
        movies: MovieHost? = nil,
        savePath: String? = nil,
        now: (() -> Date)? = nil,
        initialLanguage: Language = .en,
        settingsPath: String? = nil,
        promptOverride: PromptSetting? = nil
    ) {
        self.data = data
        self.hostFactory = hostFactory
        self.store = store
        self.audio = audio
        self.movies = movies
        self.savePath = savePath
        self.now = now
        self.initialLanguage = initialLanguage
        self.settingsPath = settingsPath
        self.promptOverride = promptOverride
    }
}

/// The game side of the menus.
public final class AppServices: TsukiUi.GameServices {
    let parts: AppServicesParts
    let nowFunc: () -> Date
    var frameCounter: Int64 = 0

    public let store: SaveStore
    public internal(set) var host: GameHost
    public var ui: UiRoot?
    public var quitRequested: Bool = false
    public var display: UiDisplaySettings?
    public var port: UiPortSettings?
    public var frameCapture: (() -> (width: Int, height: Int, rgba: [UInt8])?)?

    public var hostReplaced: ((GameHost) -> Void)?
    public var saveScreenRequested: (() -> Void)?
    public var storyEnded: ((EndReason) -> Void)?
    public internal(set) var storyActive: Bool = false
    public var logged: ((String) -> Void)?
    public var saveFailed: ((String, String) -> Void)?

    public var voiceMarksRebuilt: (credited: Int, elapsed: TimeInterval)?
    public private(set) var voicePlaysPerformed: Int64 = 0
    public private(set) var voicePlaysDropped: Int64 = 0
    var voiceFailuresSeen: Int = 0
    var saveFailureReported: Bool = false

    // Host partial fields
    var hostLanguage: Language = .en

    // Save partial fields
    let quickSaveCooldownFrames: Int64 = 300
    var thumbnails: [Int: (thumbnail: UiThumbnail?, source: SlotThumbnail)] = [:]
    var slotsVersion: Int = 0
    var cachedVersion: Int = -1
    var slotList: [UiSlot] = []
    var lastQuickSave: Int64 = Int64.min / 2
    var thumbVersion: Int = 0
    var lastAutoSlot: SlotImage?
    var lastAutoDate: SlotDate = SlotDate(year: 0, month: 0, day: 0, hour: 0, minute: 0, second: 0)

    // Story partial fields
    var backlogRings: [[Int]] = []
    var backlogVoiceCharacter: [Int: Int] = [:]
    public internal(set) var rewindHeld: Bool = false
    public internal(set) var fastForwardHeld: Bool = false
    public internal(set) var lastStartedScene: Int = -1
    var pendingTitle: Bool = false

    // System partial fields
    static let menuBgmStream = AudioStreams.bgm0
    static let audioStreamsRate = 48_000
    var menuBgm: Int = 0
    var menuBgmGain: Float = 0
    var menuBgmTarget: Float = 0
    var menuBgmStep: Float = 0
    var musicPaused: Bool = false
    var musicStartedAt: Int64 = 0
    var musicOffsetSeconds: Double = 0
    var musicVolume: Float = 1.0
    var testRow: Int = -1
    var introStarted: Bool = false
    var introAge: Int = 0
    var introEnded: Bool = false

    // Prompts partial fields
    var promptStateObj: PromptState?

    public init(parts: AppServicesParts) {
        self.parts = parts
        self.nowFunc = parts.now ?? { Date() }
        self.store = parts.store

        let vars = Vars()
        store.systemData.loadGlobalsInto(vars)

        if VoiceMarks.needsRebuild(vars, store.systemData.block) {
            let start = Date()
            let credited = VoiceMarks.rebuildFromReadText(data: parts.data, system: store.systemData, vars: vars, rowWords: parts.data.eboot.ui.voiceRowWords)
            let elapsed = Date().timeIntervalSince(start)
            self.voiceMarksRebuilt = (credited, elapsed)
        }

        let profile = GameProfile(system: store.systemData.block, vars: vars)
        let available = parts.data.availableLanguages
        let configLang = Int(profile.system.config.language)
        if configLang < 0 || configLang > 3 || (!available.isEmpty && !available.contains(Language(rawValue: UInt8(configLang)) ?? .en)) {
            let fallback: Language = (available.isEmpty || available.contains(parts.initialLanguage)) ? parts.initialLanguage : (available.first ?? .en)
            profile.system.config.language = Int16(fallback.rawValue)
        }

        let initialHostLang = Language(rawValue: UInt8(max(0, min(3, Int(profile.system.config.language))))) ?? parts.initialLanguage
        self.hostLanguage = initialHostLang
        let newHost = parts.hostFactory(initialHostLang, profile)
        self.host = newHost

        attachHost(newHost)
        store.updateLatestSlot()

        if let reb = voiceMarksRebuilt, reb.credited > 0 {
            store.systemData.captureGlobalsFrom(vars)
            _ = commit()
        }
    }

    public var frame: Int64 { frameCounter }

    public func requestQuit() {
        quitRequested = true
    }

    func log(_ message: String) {
        logged?(message)
    }

    func attachHost(_ host: GameHost) {
        host.useExternalAudio { [weak self, weak host] stream in
            guard let self = self, let host = host else { return false }
            return self.isStreamPlaying(host, stream: stream)
        }

        let sink = host.attachHistory(store: store)
        sink.thumbnailProvider = { [weak self] in
            self?.captureThumbnail()
        }
        sink.autoSaved = { [weak self] in
            _ = self?.commit()
        }
        sink.sceneStackPushed = { [weak self] in
            _ = self?.commit()
        }
        host.savePromptAccepted = { [weak self] in
            self?.saveScreenRequested?()
        }
    }

    private func isStreamPlaying(_ host: GameHost, stream: Int) -> Bool {
        guard let audio = parts.audio else {
            return false
        }
        performHostAudio(host, audio: audio)
        return audio.isPlaying(stream)
    }

    public func performHostAudio() {
        if let audio = parts.audio {
            performHostAudio(host, audio: audio)
        } else {
            _ = host.takeAudioCommands()
        }
    }

    private func performHostAudio(_ host: GameHost, audio: AudioCommandPlayer) {
        let commands = host.takeAudioCommands()
        if commands.isEmpty {
            return
        }
        audio.perform(commands)
        checkVoicePlays(commands, audio: audio)
    }

    private func checkVoicePlays(_ commands: [AudioCommand], audio: AudioCommandPlayer) {
        for i in 0..<commands.count {
            let c = commands[i]
            if c.op != .play || (c.bank != .voice && c.bank != .voice2) {
                continue
            }

            var cancelled = false
            for j in (i + 1)..<commands.count where !cancelled {
                cancelled = (commands[j].stream == c.stream && (commands[j].op == .stop || commands[j].op == .close))
            }

            if cancelled {
                continue
            }

            voicePlaysPerformed += 1
            if !audio.isPlaying(c.stream) && audio.failures.count == voiceFailuresSeen {
                voicePlaysDropped += 1
                if voicePlaysDropped == 1 {
                    log("verification: audio dead (the play of voice \(c.bank)#\(c.entry) on stream \(c.stream) did not reach the mixer)")
                }
            }

            voiceFailuresSeen = audio.failures.count
        }
    }

    public func tick() {
        frameCounter += 1
        tickAudio()
    }

    public func checkStoryEnd() {
        if storyActive && host.phase == .ended {
            storyActive = false
            let reason = host.endReason
            _ = commit()
            storyEnded?(reason)
        }
    }

    @discardableResult
    public func commit() -> Bool {
        guard let path = parts.savePath else {
            return true
        }

        do {
            try SaveFile.commit(path: path, store: store, vars: host.vars)
            return true
        } catch {
            log("save file not written: \(error.localizedDescription) (\(path))")
            if !saveFailureReported {
                saveFailureReported = true
                saveFailed?(path, error.localizedDescription)
            }
            return false
        }
    }

    func date() -> SlotDate {
        SlotDate.from(date: nowFunc())
    }

    func captureThumbnail() -> SlotThumbnail? {
        guard let f = frameCapture?() else {
            return nil
        }
        return ThumbnailCodec.encode(width: f.width, height: f.height, rgba: f.rgba)
    }
}
