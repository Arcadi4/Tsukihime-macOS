import Foundation
import TsukiCore

/// A stand-in for the audio layer's `is_playing` when no mixer runs (headless runs, the explorer): it follows the sound model's
/// commands and lets a stream end after the frames of its clip. A looping stream and a BGM never end by themselves.
public final class VirtualAudio {
    private var left: [Int] = [Int](repeating: 0, count: AudioStreams.count)

    /// The commands seen since the last `reset` (for tests and traces).
    public private(set) var commands: Int64 = 0

    /// Plays started.
    public private(set) var plays: Int64 = 0

    public init() {}

    /// Forgets every stream from `fromStream` on (0: all; `AudioStreams.firstVoice`: all but the BGM slots).
    public func reset(fromStream: Int = 0) {
        for i in fromStream..<left.count {
            left[i] = 0
        }
    }

    /// True while the stream plays.
    public func isPlaying(_ stream: Int) -> Bool {
        stream >= 0 && stream < left.count && left[stream] != 0
    }

    /// Applies the commands of one frame.
    public func process(commands: [AudioCommand], clipFrames: ((AudioBank, Int) -> Int)?, defaultVoiceFrames: Int) {
        for c in commands {
            self.commands += 1
            if c.stream < 0 || c.stream >= left.count {
                continue
            }

            switch c.op {
            case .play:
                plays += 1
                let loop = c.arg0 != 0 || c.stream < AudioStreams.firstVoice
                let frames: Int
                if let cf = clipFrames {
                    frames = cf(c.bank, c.entry)
                } else if c.stream >= AudioStreams.firstVoice && c.stream < AudioStreams.firstSE {
                    frames = defaultVoiceFrames
                } else {
                    frames = 30
                }
                left[c.stream] = loop ? Int.max : max(1, frames)
            case .stop, .close:
                left[c.stream] = 0
            default:
                break
            }
        }
    }

    /// Advances every finite stream by one frame.
    public func tick() {
        for i in 0..<left.count {
            if left[i] > 0 && left[i] < Int.max {
                left[i] -= 1
            }
        }
    }
}

extension GameHost {
    /// The eboot's row word table (text VA 0x1A6850, i32[19]: config voice row to the G word whose bit 4 shows it); nil for a data source without
    /// the UI tables (a test rig), which then records the heard bit and the last voice but no row bit.
    public var voiceRowWords: [Int]? {
        if !voiceRowWordsRead {
            voiceRowWordsRead = true
            voiceRowWordsStorage = data.eboot.ui.voiceRowWords
        }
        return voiceRowWordsStorage
    }

    /// Uses the real audio layer's `is_playing` (`AudioCommandPlayer.isPlaying`) instead of the virtual clock; the caller then also performs
    /// the commands of `takeAudioCommands`.
    public func useExternalAudio(_ isPlaying: @escaping (Int) -> Bool) {
        externalPlaying = isPlaying
        sound.isPlaying = isPlaying
    }

    /// Removes and returns the sound commands produced since the last call (for the mixer).
    public func takeAudioCommands() -> [AudioCommand] {
        let a = audioOut
        audioOut.removeAll()
        return a
    }

    func dispatchSound(_ st: Statement) -> StepResult {
        let name = st.name.description
        let music = name == "MPLY" || name == "MFAD" || name == "MVOL" || name == "MSTP"
        let effect = name == "SEPL" || name == "SEFI" || name == "SEFD" || name == "SEVL" || name == "SESP"
        if name == "VPLY" || name == "VPL2" {
            commitLayerChange(st)
        }

        if music {
            push(.music, st)
        } else if effect {
            push(.soundEffect, st)
        }

        let waitVal: Int
        do {
            waitVal = try sound.execute(st)
        } catch {
            waitVal = 0
        }

        wait.voiceState = sound.voiceState
        if (name == "VPLY" || name == "VPL2") && varState.choiceMode != ChoiceMode.none.rawValue {
            // mark
        }
        if (name == "VPLY" || name == "VPL2") && varState.skipCounter == 0 {
            VoiceMarks.note(vars, voiceRowWords, sound.pendingVoiceCharacter, sound.vplyEntry)
        }

        if name == "MPLY" {
            let track = sound.scriptTrack
            if track >= 0 && track < SystemBlock.bgmHeardTracks {
                systemData.setBgmHeard(track, true)
            }
        }

        if name == "MFAD" && waitVal == 1 && sound.wait16 > 0 {
            wait.timer = Int(Int16(truncatingIfNeeded: sound.wait16))
            return StepResult.yield
        }

        return StepResult.continue
    }

    func cmdVcwt() -> StepResult {
        if sound.voiceState != 0 {
            wait.bits |= WaitBits.voice
            wait.voiceState = sound.voiceState
            return StepResult.yield
        }
        return StepResult.continue
    }
}
