import Foundation
import TsukiCore

/// The sound engine's state and per-frame update: the BGM slots, the voice streams, the 20 script SE channels, the deferred-SE
/// queue, ducking and the voice gate, producing `AudioCommand`s (ARCHITECTURE 7.3; docs/formats/sound_runtime.md).
/// Port of `tsuki.misc_audio_runtime_semantics.SoundModel`, which was checked against the eboot's own code under emulation:
/// every float operation is float32 in the engine's order, so the channel records match the engine bit for bit.
public final class SoundModel {
    /// Number of BGM slots (streams 0, 1).
    public static let bgmSlots = 2

    /// Number of script SE channels (streams 6..25).
    public static let seChannels = AudioStreams.seChannelCount

    let _bgm: [SoundChannelRecord] = (0..<SoundModel.bgmSlots).map { _ in SoundChannelRecord() }
    let _voice: [SoundChannelRecord] = (0..<AudioStreams.voiceCount).map { _ in SoundChannelRecord() }
    let _se: [SoundChannelRecord] = (0..<SoundModel.seChannels).map { _ in SoundChannelRecord() }
    var _vol: [UInt8] = [UInt8](repeating: 0, count: 16) // the volume block 0x17DA268
    var _bgmLoop: [Int] = [1, 1] // 0x624380
    var _seLoop: [Int] = [Int](repeating: 0, count: SoundModel.seChannels) // 0xDD8FC0
    var _scrSeId: [Int] = [Int](repeating: 0, count: SoundModel.seChannels) // 0x1654210
    var _scrSeLoopId: [Int] = [Int](repeating: 0, count: SoundModel.seChannels) // 0x1654240
    var _scrSeVol: [Int] = [Int](repeating: 0, count: SoundModel.seChannels) // 0x1654270
    var _scrSeLoop: [Int] = [Int](repeating: 0, count: SoundModel.seChannels) // 0x16542A0
    var _scrSePan: [Int] = [Int](repeating: 0, count: SoundModel.seChannels) // 0x16542D0
    var _scrSeChar: [Int] = [Int](repeating: 0, count: SoundModel.seChannels) // 0x1654330
    var _defer: [DeferredSe] = (0..<SoundModel.seChannels).map { _ in
        DeferredSe(timer: 0, kind: 0, seId: 0, fade: 0, vol: 0, vol2: 0, pan: 0, pan2: 0, loop: 0, char: 0)
    }
    var _musicBits: [Int: Int] = [:] // bit array 0x164D5C0: byte index -> value
    var _out: [AudioCommand] = []
    var _isPlaying: (Int) -> Bool = { _ in true }
    var _slot: Int = 0 // 0xDD8F28
    var _track: Int = -1 // 0x62437C
    var _scrTrack: Int = 0 // 0x16545D0
    var _scrBgmVol: Int = 0 // 0x1654238
    var _duckLevel: Int = 256 // 0x7A6184
    var _duckApplied: Int = -1 // 0x7A608C
    var _vsyncs: Int = 1

    // Voice state fields (from Voice partial)
    var _voicePending: Int = -1 // 0x16541FC
    var _voiceChar: Int = 0 // 0x1654208
    var _voiceArg3: Int = 0 // 0x165420A
    var _voiceCounter: Int = 0 // 0xDD8F08: stream = 2 + (++n & 3)
    var _voiceState: Int = 0 // 0xDD8E50: 0 idle, 2 playing
    var _voiceStream: Int = -1
    var _voiceElapsed: Int = 0 // 0xDD8F04
    var _systemCounter: Int = 0 // the rotating system voice 0x2C + n

    /// The last voice a message started (0x86AA28), for the replay button; -1 = none.
    public internal(set) var lastVoice: Int = -1

    /// The entry the last `_VPLY` / `_VPL2` handed to the character marks (the second argument of 0x3D260, package K36): the pending
    /// voice after the statement's name rule, -1 when a name starting with an underscore found none pending.
    public internal(set) var vplyEntry: Int = -1
    /// The config the sound code reads.
    public let config: SoundConfig

    /// Resolves a script SE name and the search flags to a vse entry, or nil (VA 0xCC790).
    public var seLookup: (String, Int) -> Int?

    /// The library's `is_playing` (sound_runtime.md 2.5): the model consults it to stop idle streams and to skip ramps of streams
    /// that ended. The default says every stream plays, which is what the reference traces assume. A running game passes the answer
    /// of the audio layer (`AudioCommandPlayer.isPlaying`); the explorer's virtual time passes `_ => false`, so that a
    /// voice ends at the next update instead of waiting for a mixer that never runs.
    public var isPlaying: (Int) -> Bool {
        get { _isPlaying }
        set { _isPlaying = newValue }
    }

    /// The SE notification hook (config +0x2C, VA 0xE7EE0 / 0xCD610): called with (channel, vse entry) after every started SE when `SoundConfig.seCaption` is 1.
    public var seStarted: ((Int, Int) -> Void)?

    /// "ff" (word 0x120A6D2): history fast-forward / replay; sound commands only update the script-side state.
    public var fastForward: Bool = false

    /// "scan" (byte 0x174DE48): history scan / restore; sound commands only update the script-side state.
    public var scan: Bool = false

    /// Skip mode (word 0x17DB232): one-shot SEs are dropped, voices follow `SoundConfig.skipVoice`.
    public var skip: Bool = false

    /// Vsyncs since the last frame (0xD47C0 returns min(n, 3)): the deferred-SE timers count down by it.
    public var vsyncs: Int {
        get { _vsyncs }
        set { _vsyncs = newValue }
    }

    /// The wait in 16 ms units that the last `_MFAD` returned (word 0x1653E08).
    public internal(set) var wait16: Int = 0
    /// Creates the sound state of a fresh game (all records idle, the BGM loop flags 1).
    /// - Parameters:
    ///   - config: The config the sound code reads; nil = the boot defaults.
    ///   - seLookup: Resolves a script SE name (`MOON_SE03028`) and the search flags to a vse entry (eboot VA 0xCC790); nil = no SE names.
    ///   - isPlaying: Asks whether a sound stream plays (the library's `is_playing`); nil = every stream plays.
    public init(config: SoundConfig? = nil,
                seLookup: ((String, Int) -> Int?)? = nil,
                isPlaying: ((Int) -> Bool)? = nil) {
        let cfg = config ?? SoundConfig()
        self.config = cfg
        self.seLookup = seLookup ?? { _, _ in nil }
        if let isPlaying = isPlaying {
            self._isPlaying = isPlaying
        }
        cfg.fillVolumeBlock(&self._vol)
    }

    /// The current BGM slot (0 or 1; u32 0xDD8F28).
    public var currentSlot: Int { _slot }

    /// The track started last, -1 = none (0x62437C).
    public var currentTrack: Int { _track }

    /// The track of the last `_MPLY`, -1 after `_MPLY(-n)` or `_MFAD` (0x16545D0).
    public var scriptTrack: Int { _scrTrack }

    /// The volume of the last `_MPLY` / `_MVOL` (0x1654238).
    public var scriptBgmVolume: Int { _scrBgmVol }

    /// The ducking level, 256 = full (0x7A6184).
    public var duckLevel: Int { _duckLevel }

    /// The volume block byte `index` (0xB movie, 0xC BGM, 0xD voice, 0xE SE, 0xF system SE; 0x17DA268).
    public func volumeByte(_ index: Int) -> Int {
        Int(_vol[index])
    }

    /// The "track heard" bit array (music room unlock, bit 3200 + track; 0x164D5C0): byte index to value.
    public var musicBits: [Int: Int] { _musicBits }

    /// The script's per-channel SE state (read-only views of 0x1654210.., for history records and the reconciler).
    public var scriptSe: ScriptSeState { ScriptSeState(self) }

    /// The channel record of sound stream `stream` (0..25; 0..1 BGM, 2..5 voice, 6..25 SE).
    public func record(_ stream: Int) -> SoundChannelRecord {
        precondition(stream >= 0 && stream < AudioStreams.count, "streams are 0..25, got \(stream)")
        if stream < AudioStreams.firstVoice {
            return _bgm[stream]
        } else if stream < AudioStreams.firstSE {
            return _voice[stream - AudioStreams.firstVoice]
        } else {
            return _se[stream - AudioStreams.firstSE]
        }
    }

    /// Removes and returns the commands produced since the last call, in the order the engine makes the library calls.
    public func takeCommands() -> [AudioCommand] {
        if _out.isEmpty {
            return []
        }
        let a = _out
        _out.removeAll()
        return a
    }

    /// Appends the commands produced since the last call to `into` and clears them.
    public func takeCommands(into: inout [AudioCommand]) {
        into.append(contentsOf: _out)
        _out.removeAll()
    }

    /// The commands produced since the last `takeCommands()`, without removing them.
    public var pendingCommands: [AudioCommand] { _out }

    /// Number of commands waiting.
    public var pendingCommandCount: Int { _out.count }

    /// `Sound_ApplyConfig(full)` (VA 0x3E9B0 -> 0x674B0): refreshes the volume block from the config and forces the ducking to re-apply.
    public func applyConfig() {
        config.fillVolumeBlock(&_vol)
        _duckApplied = -1
    }

    // -- backend ---------------------------------------------------------------------------------
    func emit(_ c: AudioCommand) {
        _out.append(c)
    }

    func playCall(_ s: Int, _ bank: AudioBank, _ entry: Int, _ loop: Int, _ v: Float) {
        emit(AudioCommand.play(s, bank, entry, loop: loop != 0, volume: v))
    }

    func stopCall(_ s: Int) {
        emit(AudioCommand.stop(s))
        emit(AudioCommand.close(s))
    }

    func setVolumeCall(_ s: Int, _ v: Float) {
        emit(AudioCommand.setVolume(s, v, time: 0))
    }

    // -- BGM primitives --------------------------------------------------------------------------

    /// VA 0x9A90: stop + close the current slot now, track = -1 (the record keeps its state; the frame update will not touch a stream that does not play).
    func bgmStop() {
        emit(AudioCommand.stop(_slot))
        emit(AudioCommand.close(_slot))
        _track = -1
    }

    /// VA 0x9EE0 (`_MSTP`, `_MFAD`, the `_MPLY` cross-fade): the current slot -> state 2, target 0.
    func bgmFadeOut(_ rate: Float) {
        let r = _bgm[_slot]
        if r.state != 0 {
            r.state = 2
            r.volumeStep = rate
            r.volumeTarget = 0
        }

        _track = -1
    }

    func bgmEntry(_ track: Int) -> Int {
        config.altBgm == 1 && track - 1 >= 0 && track - 1 < 0x83 ? track + 0x83 : track
    }

    /// The previous slot fades out at 4.0 per frame when a new track starts on the other slot (VA 0x98C0 / 0x9B40).
    func bgmReplaceOld() {
        let old = _bgm[_slot]
        if old.state == 1 {
            old.state = 2
            old.volumeTarget = 0
            old.volumeStep = SoundMath.bgmReplaceFade
        }
    }

    /// VA 0x98C0: start `track` at volume `vol` on the other slot, no fade.
    func bgmStart(_ track: Int, _ vol: Float) {
        if track < 0 {
            bgmStop()
            return
        }

        if _track == track {
            return
        }

        bgmReplaceOld()
        _track = track
        _slot ^= 1
        let r = _bgm[_slot]
        let entry = bgmEntry(track)
        r.state = 1
        r.volumeClass = 0
        r.entry = UInt16(truncatingIfNeeded: entry)
        r.volume = vol
        r.volumeTarget = vol
        r.volumeStep = vol
        clearPans(r)
        let g = SoundMath.trunc(Float(SoundMath.i8(Int(_vol[0xC]))) * vol * 0.01)
        emit(AudioCommand.openFile(_slot, .bgm))
        playCall(_slot, .bgm, entry, _bgmLoop[_slot] != 0 ? 1 : 0, Float(SoundMath.i16(g)) * 0.01)
        emit(AudioCommand.setFlag6(_slot, on: false))
    }

    /// VA 0x9B40: start `track` from volume 0 ramping to `vol` at `rate` per frame.
    func bgmStartFade(_ track: Int, _ vol: Int, _ rate: Float) {
        if track < 0 {
            bgmStop()
            return
        }

        if _track == track {
            return
        }

        bgmReplaceOld()
        _track = track
        _slot ^= 1
        let r = _bgm[_slot]
        let entry = bgmEntry(track)
        r.state = 1
        r.volumeClass = 0
        r.entry = UInt16(truncatingIfNeeded: entry)
        r.volume = 0
        r.volumeStep = rate
        r.volumeTarget = Float(vol)
        emit(AudioCommand.openFile(_slot, .bgm))
        emit(AudioCommand.setVolume0(_slot, 0))
        playCall(_slot, .bgm, entry, _bgmLoop[_slot] != 0 ? 1 : 0, 0)
    }

    /// VA 0x9EA0: both slots' loop flags; the current slot's stream gets loop (on, count -1) for flag 1, else (off, 1).
    func bgmSetLoop(_ flag: Int) {
        _bgmLoop[0] = flag
        _bgmLoop[1] = flag
        if flag == 1 {
            emit(AudioCommand.setLoop(_slot, on: true, count: -1))
        } else {
            emit(AudioCommand.setLoop(_slot, on: false, count: 1))
        }
    }

    func clearPans(_ r: SoundChannelRecord) {
        r.pan = 0
        r.panTarget = 0
        r.panStep = 0
        r.ramp3 = 0
        r.ramp3Target = 0
        r.ramp3Step = 0
    }

    // -- per frame -------------------------------------------------------------------------------

    /// BGM ducking in the ADV frame (VA 0x694B9..0x6955F): the level (256 = full) falls by 4 per frame to 128 while a voice plays and
    /// config +0x1C is set, else rises by 2 to 256; on a change the BGM volume byte becomes `level * BGM / 256`. Returns the new
    /// BGM volume byte, or nil when nothing changed.
    @discardableResult
    public func duckUpdate(voiceActive: Bool) -> Int? {
        var lv = _duckLevel
        if voiceActive && config.duck != 0 {
            if lv >= 0x81 {
                lv = max(lv, 0x84) - 4
            }
        } else if lv <= 0xFF {
            lv = min(lv, 0xFE) + 2
        }

        _duckLevel = lv
        if lv == _duckApplied {
            return nil
        }

        _duckApplied = lv
        var x = Float(lv) * Float(1 - SoundMath.i8(config.muteBgm))
        x *= Float(SoundMath.i16(config.bgm))
        x = x * 256.0 / 100.0 * 0.001953125
        x = x * 100.0 * 0.0078125
        x = SoundMath.minSs(100.0, SoundMath.maxSs(0, x))
        let v = SoundMath.trunc(x)
        _vol[0xC] = UInt8(truncatingIfNeeded: v)
        let r = _bgm[_slot]
        if r.state != 0 {
            var g = SoundMath.trunc(Float(SoundMath.i8(v)) * r.volume * 0.01)
            g = min(max(g, 0), 100)
            setVolumeCall(_slot, Float(g) * 0.01)
        }

        return v
    }

    /// The ducking step with the voice state of the model itself (`voiceState != 0` means a voice plays).
    @discardableResult
    public func duckUpdate() -> Int? {
        duckUpdate(voiceActive: voiceState != 0)
    }

    /// The sound frame update, VA 0xAD80(dt) (the ADV frame passes `dt = 1` when a vsync elapsed, else 0): the deferred
    /// timers, the BGM, voice and SE volume / pan ramps and the fade-to-stop, then the end of the script voice.
    public func update(dt: Int = 1) {
        let dec = min(_vsyncs, 3) * dt
        for ch in 0..<SoundModel.seChannels { // VA 0x880F0
            var t = _defer[ch].timer
            if SoundMath.i16(t) > 0 {
                t = SoundMath.i16(t - dec)
                _defer[ch].timer = t
                if t <= 0 {
                    runDeferred(ch)
                }
            }
        }

        let dtf = Float(dt)
        for s in 0..<SoundModel.bgmSlots {
            let r = _bgm[s]
            if r.state == 0 {
                if _isPlaying(s) {
                    stopCall(s)
                }
                continue
            }

            var rate = r.volumeStep
            if !(0 < rate || rate.isNaN) {
                rate = SoundMath.rampDefault
                r.volumeStep = SoundMath.rampDefault
            }

            if !_isPlaying(s) {
                continue
            }

            if !(r.volume == r.volumeTarget) {
                r.volume = SoundMath.ramp(r.volume, r.volumeTarget, rate * dtf)
                var g = SoundMath.trunc(r.volume * Float(SoundMath.i8(Int(_vol[0xC]))) * 0.01)
                g = min(max(g, 0), 100)
                setVolumeCall(s, Float(g) * 0.01)
            }

            if r.state == 2 && !(0 < r.volume || r.volume.isNaN) {
                r.state = 0
                stopCall(s)
            }
        }

        for s in AudioStreams.firstVoice..<AudioStreams.firstSE {
            let r = _voice[s - AudioStreams.firstVoice]
            if r.state == 0 {
                continue
            }

            var rate = r.volumeStep
            if !(0 < rate || rate.isNaN) {
                rate = SoundMath.rampDefault
                r.volumeStep = SoundMath.rampDefault
            }

            if _isPlaying(s) && !(r.volume == r.volumeTarget) {
                r.volume = SoundMath.ramp(r.volume, r.volumeTarget, rate * dtf)
                let vb = r.volumeClass == 1 ? 0xE : (r.volumeClass == 3 ? 0xF : 0xD)
                var g = SoundMath.trunc(r.volume * Float(SoundMath.i8(Int(_vol[vb]))) * 0.01)
                g = min(max(g, 0), 100)
                setVolumeCall(s, Float(g) * 0.01)
            }

            if r.state == 2 && !(0 < r.volume || r.volume.isNaN) {
                r.state = 0
                setVolumeCall(s, 0)
                stopCall(s)
            }
        }

        for s in AudioStreams.firstSE..<AudioStreams.count {
            let ch = s - AudioStreams.firstSE
            let r = _se[ch]
            if r.state == 0 {
                if _isPlaying(s) {
                    stopCall(s)
                }
                continue
            }

            if r.started == 0 {
                continue
            }

            let playing = _isPlaying(s)
            var rate = r.volumeStep
            if !(0 < rate || rate.isNaN) {
                rate = SoundMath.rampDefault
                r.volumeStep = SoundMath.rampDefault
            }

            if playing {
                r.volume = SoundMath.ramp(r.volume, r.volumeTarget, rate * dtf, always: true)
                let vb = r.volumeClass == 1 ? 0xE : (r.volumeClass == 3 ? 0xF : 0xD)
                let c = Int(r.character)
                let g = c - 1 >= 0 && c - 1 <= 0x12 ? config.charGain(c - 1) : SoundMath.i8(Int(_vol[vb]))
                let x = Float(g) * r.volume * 0.01
                let v = x < 0 ? 0 : SoundMath.minSs(100.0, x) * 0.01
                setVolumeCall(s, v)
                if g == 0 && r.volume > r.volumeTarget {
                    stopCall(s)
                    r.state = 0
                }

                if r.panStep != 0 || r.panStep.isNaN {
                    let (pan, panRate) = SoundMath.sweep(r.pan, r.panTarget, r.panStep, dtf)
                    r.pan = pan
                    r.panStep = panRate
                    emit(AudioCommand.setPan(s, r.pan * 0.001))
                }

                if r.ramp3Step != 0 || r.ramp3Step.isNaN {
                    let (p3, p3Rate) = SoundMath.sweep(r.ramp3, r.ramp3Target, r.ramp3Step, dtf)
                    r.ramp3 = p3
                    r.ramp3Step = p3Rate
                }
            }

            if r.state == 2 && !(0 < r.volume || r.volume.isNaN) {
                r.state = 0
                stopCall(s)
            }
        }

        endOfVoice(dt)
    }

    /// The state of the model as a list of 32-bit words in a fixed order (the integer globals, the script arrays and the deferred queue;
    /// the channel records are separate: `record`). Used by the trace tests to compare every step with the reference model.
    public func stateWords() -> [Int] {
        var w: [Int] = []
        w.reserveCapacity(512)
        w.append(_slot)
        w.append(_track)
        w.append(_bgmLoop[0])
        w.append(_bgmLoop[1])
        w.append(contentsOf: _seLoop)
        w.append(_scrTrack)
        w.append(_scrBgmVol)
        w.append(contentsOf: _scrSeId)
        w.append(contentsOf: _scrSeLoopId)
        w.append(contentsOf: _scrSeVol)
        w.append(contentsOf: _scrSeLoop)
        w.append(contentsOf: _scrSePan)
        w.append(contentsOf: _scrSeChar)
        w.append(_voicePending)
        w.append(_voiceChar)
        w.append(_voiceArg3)
        for i in 0xB...0xF {
            w.append(Int(_vol[i]))
        }

        w.append(_duckLevel)
        w.append(_duckApplied)
        for d in _defer {
            w.append(d.timer)
            w.append(d.kind)
            w.append(d.seId)
            w.append(Int(Int32(truncatingIfNeeded: d.fade)))
            w.append(Int(Int32(truncatingIfNeeded: d.fade >> 32)))
            w.append(d.vol)
            w.append(d.vol2)
            w.append(d.pan)
            w.append(d.pan2)
            w.append(d.loop)
            w.append(d.char)
        }

        w.append(_musicBits.count)
        for k in _musicBits.keys.sorted() {
            w.append(k)
            w.append(_musicBits[k]!)
        }

        return w
    }

    /// The channel records of streams 0..25 as one byte array (26 x 0x34 bytes), for traces and snapshots.
    public func recordBytes() -> [UInt8] {
        var all = [UInt8](repeating: 0, count: AudioStreams.count * SoundChannelRecord.size)
        for s in 0..<AudioStreams.count {
            let rec = record(s)
            let span = rec.bytes
            for i in 0..<SoundChannelRecord.size {
                all[s * SoundChannelRecord.size + i] = span[i]
            }
        }
        return all
    }
}

/// One deferred SE command (0x18 bytes at 0x16543F0 + 0x18 c; sound_runtime.md 5).
final class DeferredSe {
    /// Frames until the command runs (i16).
    var timer: Int

    /// 1 SEPL, 2 SEFD, 3 SEVL, 4 SEAC (engine-only).
    var kind: Int

    /// The vse entry (i16).
    var seId: Int

    /// The ``001` time in ms (-1 absent; i64).
    var fade: Int64

    /// The ``017` volume byte (0xFF absent).
    var vol: Int

    /// Second volume (SEAC).
    var vol2: Int

    /// The raw ``018` byte (0xFF absent).
    var pan: Int

    /// Second pan (SEAC).
    var pan2: Int

    /// The loop argument byte.
    var loop: Int

    /// The ``070` character.
    var char: Int

    init(timer: Int = 0, kind: Int = 0, seId: Int = 0, fade: Int64 = 0,
         vol: Int = 0, vol2: Int = 0, pan: Int = 0, pan2: Int = 0, loop: Int = 0, char: Int = 0) {
        self.timer = timer
        self.kind = kind
        self.seId = seId
        self.fade = fade
        self.vol = vol
        self.vol2 = vol2
        self.pan = pan
        self.pan2 = pan2
        self.loop = loop
        self.char = char
    }

    /// State after execution or cancel (VA 0x88098): timer 0, kind 0, id -1, bytes +8..+0x14 = 0xFF, +0x15 = 0.
    func clear() {
        timer = 0
        kind = 0
        seId = -1
        fade = -1
        vol = 0xFF
        vol2 = 0xFF
        pan = 0xFF
        pan2 = 0xFF
        loop = 0xFF
        char = 0
    }
}

/// Read-only views of the script-side SE arrays (the history record and the reconciler read them).
public struct ScriptSeState {
    private let model: SoundModel

    init(_ model: SoundModel) {
        self.model = model
    }

    /// The vse entry of the last `_SEPL` on channel `ch` (0x1654210).
    public func lastEntry(_ ch: Int) -> Int { model.scriptSeIdAt(ch) }

    /// The vse entry of the channel's looping SE, -1 = none (0x1654240).
    public func loopEntry(_ ch: Int) -> Int { model.scriptSeLoopIdAt(ch) }

    /// The script volume (0x1654270).
    public func volume(_ ch: Int) -> Int { model.scriptSeVolAt(ch) }

    /// 1 = the channel's last SE was looped (0x16542A0).
    public func looped(_ ch: Int) -> Int { model.scriptSeLoopAt(ch) }

    /// The pan -1000..1000 (0x16542D0).
    public func pan(_ ch: Int) -> Int { model.scriptSePanAt(ch) }

    /// The ``070` character (0x1654330).
    public func character(_ ch: Int) -> Int { model.scriptSeCharAt(ch) }
}
