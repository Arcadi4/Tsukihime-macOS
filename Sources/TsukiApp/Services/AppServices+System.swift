import Foundation
import TsukiCore
import TsukiEngine
import TsukiMedia
import TsukiUi

extension AppServices: UiSystemServices {
    public var language: Language {
        let l = Int(host.config.language)
        if l >= 0 && l <= 3, let lang = Language(rawValue: UInt8(l)) {
            return lang
        }
        return hostLanguage
    }

    public var config: ConfigBlock {
        host.config
    }

    public var decideIsCross: Bool {
        true
    }

    public func configChanged(_ change: ConfigChange) {
        switch change {
        case .language:
            if language != hostLanguage {
                rebuildHost(language: language)
            }
        case .reset:
            if host.config.language < 0 || host.config.language > 3 {
                host.config.language = Int16(hostLanguage.rawValue)
            }
            applySoundConfig()
        default:
            applySoundConfig()
        }
        _ = commit()
    }

    func applySoundConfig() {
        host.sound.config.readFrom(host.config)
        host.sound.applyConfig()
        if testRow >= 0 {
            host.sound.applyTestRow(testRow)
            flushMenuSound()
        }

        parts.movies?.perform(MovieCommand.setVolume(MovieSlots.fullScreen, movieVolume()))
        if menuBgm > 0, let audio = parts.audio {
            audio.perform([AudioCommand.setVolume(Self.menuBgmStream, menuBgmGain * musicGain())])
        }
    }

    func musicGain() -> Float {
        host.config.musicMute != 0 ? 0.0 : max(0.0, min(1.0, Float(host.config.musicVolume) / 100.0))
    }

    func movieVolume() -> Float {
        host.config.musicMute != 0 ? 0.0 : max(0.0, min(1.0, Float(host.config.musicVolumeCopy) / 100.0))
    }

    public func commitSystemData() {
        _ = commit()
    }

    public func global(_ index: Int) -> Int {
        guard index >= 0 && index < Vars.gCount else { return 0 }
        return Int(host.vars.getG(index))
    }

    public func setGlobal(_ index: Int, _ value: Int) {
        guard index >= 0 && index < Vars.gCount else { return }
        host.vars.setG(index, UInt16(truncatingIfNeeded: value))
    }

    public func sceneBit(_ bit: Int) -> Bool {
        host.isSceneReached(bit)
    }

    public func playSystemSound(_ sound: UiSound) {
        host.sound.systemSePlay(sound.rawValue)
        flushMenuSound()
    }

    func flushMenuSound() {
        let commands = host.sound.takeCommands()
        if !commands.isEmpty {
            parts.audio?.perform(commands)
        }
    }

    public func playTestSe() {
        let names = parts.data.eboot.ui.testSeNames
        guard !names.isEmpty else { return }
        let name = names.randomElement() ?? names[0]
        _ = try? host.sound.run("_SEPL(19,0,\(name),,`017:100);")
        flushMenuSound()
    }

    public func playTestVoice(_ row: Int) -> Bool {
        testRow = -1
        guard row >= 0 && row < VoiceMarks.rowCount else { return false }

        let words = host.voiceRowWords
        if let words = words, row < words.count && global(words[row]) == 0 {
            return false
        }

        let entry = Int(Int16(truncatingIfNeeded: global(VoiceMarks.lastVoiceWord + row)))
        guard entry > 0 else { return false }

        testRow = row
        let started = host.sound.startTestVoice(entry, row)
        flushMenuSound()
        return started
    }

    public func stopTests() {
        testRow = -1
        _ = try? host.sound.run("_SEPL(19,0,,,);")
        host.sound.stopVoice()
        flushMenuSound()
    }

    // MARK: - Menu Music

    public func playBgm(_ track: Int) {
        startMenuBgm(track, gain: 1.0)
    }

    func startMenuBgm(_ track: Int, gain: Float) {
        menuBgm = track
        menuBgmGain = gain
        menuBgmTarget = gain
        menuBgmStep = 0
        musicPaused = false
        musicOffsetSeconds = 0
        musicStartedAt = frameCounter
        parts.audio?.perform([
            AudioCommand.stop(Self.menuBgmStream),
            AudioCommand.close(Self.menuBgmStream),
            AudioCommand.openFile(Self.menuBgmStream, .bgm),
            AudioCommand.play(Self.menuBgmStream, .bgm, track, loop: true, volume: gain * musicGain()),
        ])
    }

    public func fadeOutBgm(_ seconds: Float) {
        guard menuBgm > 0 else { return }
        menuBgmTarget = 0
        menuBgmStep = seconds <= 0 ? 1.0 : 1.0 / (seconds * 60.0)
    }

    func tickAudio() {
        if menuBgm > 0 && menuBgmStep > 0 && menuBgmGain != menuBgmTarget {
            let g = menuBgmGain + (menuBgmGain > menuBgmTarget ? -menuBgmStep : menuBgmStep)
            menuBgmGain = (menuBgmTarget == 0) ? max(0.0, g) : g
            if menuBgmGain <= 0.0001 && menuBgmTarget == 0 {
                parts.audio?.perform([
                    AudioCommand.stop(Self.menuBgmStream),
                    AudioCommand.close(Self.menuBgmStream),
                ])
                menuBgm = 0
                menuBgmStep = 0
            } else {
                parts.audio?.perform([AudioCommand.setVolume(Self.menuBgmStream, menuBgmGain * musicGain())])
            }
        }
    }

    public func stopMenuAudio() {
        if menuBgm > 0 {
            parts.audio?.perform([
                AudioCommand.stop(Self.menuBgmStream),
                AudioCommand.close(Self.menuBgmStream),
            ])
            menuBgm = 0
        }
    }

    // MARK: - Title & Intro Movies

    public var titleMovieSlot: Int {
        MovieSlots.titleBackground
    }

    public var introMovieSlot: Int {
        MovieSlots.fullScreen
    }

    public func startTitleMovie(_ movieIndex: Int) {
        parts.movies?.perform(MovieCommand.open(MovieSlots.titleBackground, movieIndex, loop: true, volume: 0.0))
    }

    public func stopTitleMovie() {
        parts.movies?.perform(MovieCommand.stop(MovieSlots.titleBackground))
    }

    public func seekTitleMovie(_ seconds: Double) {}

    public var titleMovieTime: Double {
        parts.movies?.currentFrame(slot: MovieSlots.titleBackground)?.pts ?? -1.0
    }

    public func startIntroMovie(_ movieIndex: Int) {
        let index = (movieIndex == 4 || movieIndex == 5 || movieIndex == 6) ? MovieTable.remap(movieIndex, language) : movieIndex
        parts.movies?.perform(MovieCommand.open(MovieSlots.fullScreen, index, loop: false, volume: movieVolume()))
        introStarted = true
        introEnded = false
        introAge = 0
    }

    public var introMoviePlaying: Bool {
        introStarted && (parts.movies?.openSlots ?? 0) > 0 && !introEnded
    }

    public func updateMovieClocks(_ clocks: [MovieClock]) {
        guard introStarted else { return }
        introAge += 1
        for c in clocks {
            if c.slot == MovieSlots.fullScreen {
                introEnded = c.ended
                return
            }
        }
        introEnded = (introAge > 3)
    }

    public func stopIntroMovie() {
        parts.movies?.perform(MovieCommand.stop(MovieSlots.fullScreen))
        introStarted = false
        introEnded = false
        introAge = 0
    }
}
