import Foundation
import TsukiCore

// The sound side of a restore (package K6): after a load, a rewind, a previous-scene or a backlog jump the engine restarts the music and the looping
// effects from the script-side sound variables of the restored record (the resync 0x7E4E0 / 0x7E620 of docs/formats/adv_state.md 3.1, 5.1; K4.md
// "Where each AdvLiveState member comes from"). A fresh model is created for the restored scene; this fills its script-side state and starts the streams.
// A rewind onto a record with the BGM that already plays keeps that BGM (AdoptBgm; knife game.rs restore_with), and the end of a next-scene skip resyncs
// the live model's streams with the script-side state the skipped handlers left (ResyncScriptState, the 0x7E620 of every skip end site).
extension SoundModel {
    /// Restarts the script-side sound state of a restored record on this (fresh) model: the BGM `bgmTrack` at
    /// `bgmVolume` (negative track: none) and every loop-SE channel whose loop id is not negative and whose loop flag is above 0
    /// at its volume and pan. The play commands go to `takeCommands()` like the script's own. A BGM stream that already plays the track
    /// (`adoptBgm`) is left alone, as BgmStart's own early-out (VA 0x98C0) leaves it on the console.
    /// - Parameters:
    ///   - bgmTrack: The record's BGM track (RAM 0x16545D0).
    ///   - bgmVolume: The record's BGM volume word (0x1654238).
    ///   - loopSeIds: Loop SE entry per channel (0x1654240), -1 = none.
    ///   - volume: Volume per channel (0x1654270).
    ///   - looped: Loop flag per channel (0x16542A0).
    ///   - pan: Pan per channel (0x16542D0, thousandths).
    ///   - character: Voice character per channel (0x1654330).
    public func restoreScriptState(
        bgmTrack: Int,
        bgmVolume: Int,
        loopSeIds: [Int16],
        volume: [UInt16],
        looped: [UInt16],
        pan: [Int16],
        character: [UInt8]
    ) {
        // a fresh model reports track 0 at volume 0 for "no music yet"; that is silence, not track 0
        if bgmTrack > 0 || (bgmTrack == 0 && bgmVolume > 0) {
            if _track != bgmTrack {
                bgmSetLoop(1)
                bgmStart(bgmTrack, Float(bgmVolume))
            }

            _scrTrack = bgmTrack
            _scrBgmVol = SoundMath.i16(bgmVolume)
        } else {
            _scrTrack = -1
        }

        let count = min(SoundModel.seChannels, loopSeIds.count)
        for ch in 0..<count {
            let id = Int(loopSeIds[ch])
            if id < 0 || looped[ch] == 0 {
                continue
            }

            let vol = min(max(Int(Int16(bitPattern: volume[ch])), 0), 100)
            _scrSeId[ch] = id
            _scrSeLoopId[ch] = id
            _scrSeLoop[ch] = 1
            _scrSeVol[ch] = Int(volume[ch])
            _scrSePan[ch] = Int(pan[ch])
            _scrSeChar[ch] = Int(character[ch])
            _se[ch].character = character[ch]
            _seLoop[ch] = 1
            sePlayNow(ch, id, Float(vol))
            seSetPan(ch, Int(pan[ch]))
        }
    }

    /// Takes the BGM side of `previous` over into this fresh model: the two slot records, the loop flags, the current slot and track, the
    /// ducking level. A rewind onto a record whose track already plays uses it (knife game.rs restore_with: sub_5D710 keeps the BGM when it is the same
    /// track and stops only the effects and the voice); `restoreScriptState` then leaves the stream alone.
    public func adoptBgm(_ previous: SoundModel) {
        for s in 0..<SoundModel.bgmSlots {
            _bgm[s].copy(from: previous._bgm[s])
        }

        _bgmLoop[0] = previous._bgmLoop[0]
        _bgmLoop[1] = previous._bgmLoop[1]
        _slot = previous._slot
        _track = previous._track
        _duckLevel = previous._duckLevel
        _duckApplied = previous._duckApplied
    }

    /// The resync at the end of a next-scene skip (VA 0x7E620, "restart BGM 0x16545D0 and the loop SEs", adv_state.md 2.5, 5.2; every end site calls it).
    /// While the skip ran (word 0x120A6D2) the handlers only updated the script-side state. The eboot (tools/eboot/disasm.py func 0x7E620): a script track
    /// at or above 0 gives BgmSetLoop(1), BgmStart(track, volume) (the early-out 0x98C0 keeps a stream that plays the track) and the volume 0x9CE0, a negative
    /// one BgmStop; then every SE channel without a script-side loop (0x1654240 below 0 or 0x16542A0 at most 0) is stopped (0xAAB0) and every channel with
    /// one is started again (loop flag 1, its character, 0xA300 at the script volume, 0xA9E0 at the script pan; 0x1654210 = the loop entry).
    public func resyncScriptState() {
        if _scrTrack > 0 || (_scrTrack == 0 && _scrBgmVol > 0) { // a fresh model's track 0 at volume 0 is "no music yet" (RestoreScriptState)
            bgmSetLoop(1)
            bgmStart(_scrTrack, Float(_scrBgmVol))
            bgmSetLoop(1)
            bgmSetVolume(_scrBgmVol)
        } else if _track >= 0 {
            bgmStop()
        }

        for ch in 0..<SoundModel.seChannels {
            if _scrSeLoopId[ch] < 0 || _scrSeLoop[ch] <= 0 {
                seStop(ch)
                continue
            }

            _seLoop[ch] = 1
            _se[ch].character = UInt8(truncatingIfNeeded: _scrSeChar[ch] & 0xFF)
            sePlayNow(ch, _scrSeLoopId[ch], Float(SoundMath.i16(_scrSeVol[ch])))
            seSetPan(ch, _scrSePan[ch])
            _scrSeId[ch] = _scrSeLoopId[ch]
        }
    }

    /// VA 0x9CE0: the current slot's volume and target become `vol` at once (step 100), and the stream gets `vol * BGM byte / 100`.
    private func bgmSetVolume(_ vol: Int) {
        let r = _bgm[_slot]
        r.volume = Float(vol)
        r.volumeTarget = Float(vol)
        r.volumeStep = 100.0
        let g = min(max(SoundMath.trunc(Float(vol) * Float(SoundMath.i8(Int(_vol[0xC]))) * 0.01), 0), 100)
        setVolumeCall(_slot, Float(g) * 0.01)
    }

    /// Makes `entry` the pending voice of `character` (what `_VPLY` does): the next message display plays it
    /// through the usual gate. A load uses it to replay the voice of the restored line (VA 0x7EB19).
    public func setPendingVoice(_ entry: Int, _ character: Int) {
        _voicePending = entry
        _voiceChar = character
    }

    /// The commands that stop every decoder stream from `fromStream` on (0: BGM, voices and script effects, the way a script end does;
    /// `AudioStreams.firstVoice`: everything but the BGM, a rewind that keeps its music); for the host's restore.
    public static func stopEverything(fromStream: Int = 0) -> [AudioCommand] {
        var list: [AudioCommand] = []
        list.reserveCapacity(AudioStreams.count * 2)
        let start = max(0, fromStream)
        for s in start..<AudioStreams.count {
            list.append(AudioCommand.stop(s))
            list.append(AudioCommand.close(s))
        }
        return list
    }
}
