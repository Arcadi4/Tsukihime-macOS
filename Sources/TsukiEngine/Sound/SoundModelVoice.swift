import Foundation
import TsukiCore

/// A voice the gate let through: the voice.hed entry, the config slot k and the voice gain 0..100 (sound_runtime.md 7).
/// - Parameter entry: The entry requested by `_VPLY` (<= 19,999: voice.hed; 20,000..59,999: voice2.hed entry - 20,000).
/// - Parameter slot: The config slot k of the character (bit k of config +0x3C, volume at config +0x76 + 2k).
/// - Parameter gain: The voice gain `char_vol[k] * voice / 100` (C division), also written to volume byte 0xD.
public struct VoiceStart: Equatable, Sendable {
    public let entry: Int
    public let slot: Int
    public let gain: Int

    public init(entry: Int, slot: Int, gain: Int) {
        self.entry = entry
        self.slot = slot
        self.gain = gain
    }
}

// The voice pipeline and the system sounds (docs/formats/sound_runtime.md 3.6, 7, 9, 10.1, 12): _VPLY makes the voice pending, the
// next message display runs the gate and starts it on one of streams 2..5, the next advance stops it, and the model reports whether
// a voice plays (for _VCWT, auto mode and the BGM ducking).
extension SoundModel {
    /// The voice state word (0xDD8E50): 0 idle, 2 playing. `_VCWT` waits while it is not 0; ducking follows it.
    public var voiceState: Int { _voiceState }

    /// The voice entry `_VPLY` requested and the next message display will play, -1 = none (0x16541FC).
    public var pendingVoice: Int { _voicePending }

    /// The character of the pending voice (0x1654208).
    public var pendingVoiceCharacter: Int { _voiceChar }

    /// The third `_VPLY` argument, 0 if absent; the history record keeps it (0x165420A).
    public var voiceArg3: Int { _voiceArg3 }

    /// The time auto mode waits on the voice (VA 0x96F0): elapsed frames * 17 ms while it plays, 10,000 ms when no voice state exists.
    public var autoModeVoiceMilliseconds: Int {
        _voiceState == 2 ? _voiceElapsed * 17 : 10_000
    }

    /// VA 0x968B2: `_VPLY(name, hex entry [, n])` remembers the voice (the next message display plays it); `_VPL2` plays it
    /// at once through the same gate and does not become the replay voice (knife game.rs "VPLY | VPL2": the PS4 docs 3.6 say "play
    /// immediately, same gate and gain as 7, and clear the pending voice"). A name starting with an underscore repeats the previous entry.
    func cmdVply(_ b: ByteSpan, _ sep: Int, immediate: Bool) -> Int {
        let name = SoundTags.argText(b, sep, 0)
        _voiceChar = VoiceGroups.characterOf(name)
        let nargs = SoundTags.countArgs(b, sep)
        _voiceArg3 = nargs >= 3 ? SoundTags.int(b, sep, 2) & 0xFFFF : 0
        if !name.hasPrefix("_") {
            let hex = SoundTags.argText(b, sep, 1).trimmingCharacters(in: .whitespacesAndNewlines)
            _voicePending = hex.isEmpty ? 0 : (Int(hex, radix: 16) ?? 0)
        }

        vplyEntry = _voicePending
        if immediate {
            if let v = voiceGate() {
                _ = startVoice(v.entry, remember: false)
            }
        }

        return 0
    }

    /// `_VCLR()` (VA 0x97277; no script uses it): the pending voice is dropped.
    func cmdVclr() -> Int {
        _voicePending = -1
        return 0
    }

    /// The gate of the voice start at the message display (VA 0x9281E..0x92902): takes the pending voice (always clearing it) and
    /// returns it when voices are on, the character's voice is enabled and neither fast-forward nor skip mode (without "voices in skip")
    /// forbids it; writes the voice gain into volume byte 0xD. Does not play anything.
    public func voiceGate() -> VoiceStart? {
        let idx = _voicePending
        _voicePending = -1
        if idx < 0 {
            return nil
        }

        if skip && config.skipVoice == 0 {
            return nil
        }

        if fastForward || !(config.voice != 0 && config.voiceOn2 != 0) {
            return nil
        }

        let k = VoiceGroups.slotOf(_voiceChar)
        if (config.charEnable & VoiceGroups.maskOf(_voiceChar)) == 0 {
            return nil
        }

        let gain = SoundMath.i16(config.charVol[k]) * SoundMath.i16(config.voice) / 100
        _vol[0xD] = UInt8(truncatingIfNeeded: gain)
        return VoiceStart(entry: idx, slot: k, gain: gain)
    }

    /// The voice part of the `_ZM` handler (VA 0x92380): runs the gate and, when it lets the pending voice through, starts it
    /// (`startVoice`) and remembers it for the replay button. Returns true when a voice started.
    @discardableResult
    public func startVoiceAtMessage() -> Bool {
        guard let v = voiceGate() else {
            return false
        }

        return startVoice(v.entry, remember: true)
    }

    /// `VoiceRequest(idx)` + the start of the stream (VA 0xC3A80, 0x8F60, 0x9220, 0x8BD0; sound_runtime.md 7 steps 3-4): stops
    /// streams 2..5, picks stream `2 + (++n & 3)`, sets its record {1, kind 0, vol = target = rate = 100} and plays the entry
    /// from memory at `volume byte 0xD * 0.01`. Returns false for an entry above 59,999 (rejected).
    @discardableResult
    public func startVoice(_ entry: Int, remember: Bool = false) -> Bool {
        let bank: AudioBank
        let bankEntry: Int
        if entry >= 0 && entry <= 19_999 {
            bank = .voice
            bankEntry = entry
        } else if entry >= 20_000 && entry <= 59_999 {
            bank = .voice2
            bankEntry = entry - 20_000
        } else {
            return false
        }

        stopVoice()
        _voiceCounter += 1
        let s = AudioStreams.firstVoice + (_voiceCounter & 3)
        let r = _voice[s - AudioStreams.firstVoice]
        r.state = 1
        r.volumeClass = 0
        r.volume = 100.0
        r.volumeTarget = 100.0
        r.volumeStep = 100.0
        emit(AudioCommand.openHandle(s, bank))
        playCall(s, bank, bankEntry, 0, Float(SoundMath.i8(Int(_vol[0xD]))) * 0.01)
        _voiceState = 2
        _voiceStream = s
        _voiceElapsed = 0
        if remember {
            lastVoice = entry
        }

        return true
    }

    /// The config screen's voice test of slot `slot` (package K36): `VoiceRequest(entry, -1)` of VA 0x401E0, followed by
    /// the `Sound_ApplyConfig(0)` every config item ends with (VA 0x4008C..0x40093), which stops the voice when the slot is muted
    /// (0x3EA4A -> 0x8EA0) and otherwise sets volume byte 0xD to `char_vol[k] * voice / 100` (0x3EA4F..0x3EA89 -> 0xB6F0) before the stream
    /// starts, so the test plays at the row's volume. Returns true when a voice was commanded.
    @discardableResult
    public func startTestVoice(_ entry: Int, _ slot: Int) -> Bool {
        if slot < 0 || slot >= SoundConfig.characterSlots {
            return false
        }

        if (config.charEnable & (UInt32(1) << slot)) == 0 {
            stopVoice()
            return false
        }

        _vol[0xD] = UInt8(truncatingIfNeeded: testRowGain(slot))
        return startVoice(entry, remember: false)
    }

    /// `Sound_ApplyConfig(0)` with a test row (VA 0x3EA25..0x3EA89; package K36): the config screen's live change after a row was tested.
    /// A muted test row stops the voice; the row's gain `char_vol[k] * voice / 100` becomes the voice volume at once (`setVoiceVolume`).
    public func applyTestRow(_ slot: Int) {
        if slot < 0 || slot >= SoundConfig.characterSlots {
            return
        }

        if (config.charEnable & (UInt32(1) << slot)) == 0 {
            stopVoice()
        }

        setVoiceVolume(testRowGain(slot))
    }

    private func testRowGain(_ slot: Int) -> Int {
        SoundMath.i16(config.charVol[slot]) * SoundMath.i16(config.voice) / 100
    }

    /// VA 0xB6F0: volume byte 0xD becomes `gain` (0..100), and the voice stream that plays follows at once with
    /// `clamp(trunc(gain * record volume * 0.01), 0, 100) %` (the record volume is 100 for a voice, so the stream plays at gain %).
    public func setVoiceVolume(_ gain: Int) {
        _vol[0xD] = UInt8(truncatingIfNeeded: gain)
        if _voiceState == 0 || _voiceStream < 0 {
            return
        }

        let r = _voice[_voiceStream - AudioStreams.firstVoice]
        if r.state == 0 {
            return
        }

        let v = min(max(SoundMath.trunc(Float(SoundMath.i8(Int(_vol[0xD]))) * r.volume * 0.01), 0), 100)
        setVolumeCall(_voiceStream, Float(v) * 0.01)
    }

    /// The voice stop of the advance (VA 0xA1015..0xA1040, 0xA1149, 0xA124D): true when the message ending stops the voice, that is
    /// `(F1123 == 0 && config +0x4E) || skip`.
    public func shouldStopVoiceOnAdvance(f1123: Int = 0) -> Bool {
        (f1123 == 0 && config.stopOnAdvance != 0) || skip
    }

    /// Applies `shouldStopVoiceOnAdvance`: stops the voice when it says so. Returns what it said.
    @discardableResult
    public func stopVoiceOnAdvance(f1123: Int = 0) -> Bool {
        let stop = shouldStopVoiceOnAdvance(f1123: f1123)
        if stop {
            stopVoice()
        }
        return stop
    }

    /// VA 0x8EA0 / 0x8F60: stops streams 2..5 (every caller passes fade 0) and ends the voice state.
    public func stopVoice() {
        for s in AudioStreams.firstVoice..<AudioStreams.firstSE {
            if _isPlaying(s) {
                stopCall(s)
            }
        }

        _voiceState = 0
        _voiceStream = -1
    }

    /// The end of the script voice, at the end of the frame update: the stream stopped, so the voice state returns to 0 (VA 0x9220).
    func endOfVoice(_ dt: Int) {
        if _voiceState == 0 {
            return
        }

        if !_isPlaying(_voiceStream) {
            emit(AudioCommand.close(_voiceStream))
            _voiceState = 0
            _voiceStream = -1
            return
        }

        _voiceElapsed += dt
    }

    /// `SystemSE_Play(id)` (VA 0xCC670; sound_runtime.md 10.1): the HE-VAG pair of the id on the next of the four system voices
    /// 0x2C..0x2F, left hard left and right hard right, at `volume byte 0xF * 0.01`. A mono sound (right < 0) plays centred,
    /// and a pair with left <= 0 plays nothing (the voice is still consumed). Returns true when a sound was commanded.
    @discardableResult
    public func systemSePlay(_ id: Int) -> Bool {
        guard let (left, right) = try? SystemSounds.vags(id) else {
            return false
        }

        let vol = Float(SoundMath.i8(Int(_vol[0xF]))) * 0.01
        let voice = AudioStreams.firstSystemVoice + _systemCounter
        _systemCounter = (_systemCounter + 1) & 3
        if left <= 0 {
            return false
        }

        emit(AudioCommand.playSystem(voice: voice, left: left, right: right, volume: vol))
        return true
    }
}
