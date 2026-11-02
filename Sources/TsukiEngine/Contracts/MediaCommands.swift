import Foundation


/// Stream numbers of the sound library (docs/formats/sound_runtime.md 2.1).
public enum AudioStreams {
    public static let bgm0 = 0
    public static let bgm1 = 1
    public static let firstVoice = 2
    public static let voiceCount = 4
    public static let firstSE = 6
    public static let seChannelCount = 20
    public static let count = 26
    public static let firstSystemVoice = 0x2C
    public static let systemVoiceCount = 4

    public static func se(_ channel: Int) -> Int { firstSE + channel }
}

/// Sound library calls (nexl_Sound). `is_playing` is a query, not a command.
public enum AudioOp: UInt8, Sendable {
    case openFile
    case openHandle
    case close
    case play
    case stop
    case setVolume
    /// The volume before play.
    case setVolume0
    case setPan
    case setLoop
    case setStartSample
    case setFlag6
    /// HE-VAG system sound pair on a system voice.
    case playSystem
}

/// One sound command of a step. Volumes and pans are final values: the mixer applies them with
/// linear ramps and the pan law and never re-derives them.
public struct AudioCommand: Sendable {
    public var op: AudioOp
    public var stream: Int
    public var bank: AudioBank
    public var entry: Int
    public var arg0: Int
    public var arg1: Int
    public var value0: Float
    public var value1: Float

    public init(op: AudioOp, stream: Int, bank: AudioBank = .bgm, entry: Int = 0,
                arg0: Int = 0, arg1: Int = 0, value0: Float = 0, value1: Float = 0) {
        self.op = op
        self.stream = stream
        self.bank = bank
        self.entry = entry
        self.arg0 = arg0
        self.arg1 = arg1
        self.value0 = value0
        self.value1 = value1
    }

    public static func openFile(_ stream: Int, _ bank: AudioBank) -> AudioCommand {
        AudioCommand(op: .openFile, stream: stream, bank: bank)
    }

    public static func openHandle(_ stream: Int, _ bank: AudioBank) -> AudioCommand {
        AudioCommand(op: .openHandle, stream: stream, bank: bank)
    }

    public static func close(_ stream: Int) -> AudioCommand {
        AudioCommand(op: .close, stream: stream)
    }

    public static func play(_ stream: Int, _ bank: AudioBank, _ entry: Int, loop: Bool, volume: Float) -> AudioCommand {
        AudioCommand(op: .play, stream: stream, bank: bank, entry: entry, arg0: loop ? 1 : 0, value0: volume)
    }

    public static func stop(_ stream: Int, fadeFrames: Int = 0) -> AudioCommand {
        AudioCommand(op: .stop, stream: stream, arg0: fadeFrames)
    }

    public static func setVolume(_ stream: Int, _ volume: Float, time: Float = 0) -> AudioCommand {
        AudioCommand(op: .setVolume, stream: stream, value0: volume, value1: time)
    }

    public static func setVolume0(_ stream: Int, _ volume: Float) -> AudioCommand {
        AudioCommand(op: .setVolume0, stream: stream, value0: volume)
    }

    public static func setPan(_ stream: Int, _ pan: Float) -> AudioCommand {
        AudioCommand(op: .setPan, stream: stream, value0: pan)
    }

    public static func setLoop(_ stream: Int, on: Bool, count: Int) -> AudioCommand {
        AudioCommand(op: .setLoop, stream: stream, arg0: on ? 1 : 0, arg1: count)
    }

    public static func setStartSample(_ stream: Int, _ sample: Int) -> AudioCommand {
        AudioCommand(op: .setStartSample, stream: stream, arg0: sample)
    }

    public static func setFlag6(_ stream: Int, on: Bool) -> AudioCommand {
        AudioCommand(op: .setFlag6, stream: stream, arg0: on ? 1 : 0)
    }

    /// vag `left` hard left and `right` hard right on `voice`; `right` < 0 plays left centred.
    public static func playSystem(voice: Int, left: Int, right: Int, volume: Float) -> AudioCommand {
        AudioCommand(op: .playSystem, stream: voice, bank: .vag, entry: left, arg0: right, value0: volume)
    }
}

/// Movie calls (ARCHITECTURE 3.2, 7.5).
public enum MovieOp: UInt8, Sendable {
    case open
    case stop
    case setVolume
}

/// One movie command of a step. A slot is one open movie.
public struct MovieCommand: Sendable {
    public var op: MovieOp
    public var slot: Int
    public var movieIndex: Int
    public var loop: Bool
    public var volume: Float

    public init(op: MovieOp, slot: Int, movieIndex: Int = -1, loop: Bool = false, volume: Float = 0) {
        self.op = op
        self.slot = slot
        self.movieIndex = movieIndex
        self.loop = loop
        self.volume = volume
    }

    public static func open(_ slot: Int, _ movieIndex: Int, loop: Bool, volume: Float) -> MovieCommand {
        MovieCommand(op: .open, slot: slot, movieIndex: movieIndex, loop: loop, volume: volume)
    }

    public static func stop(_ slot: Int) -> MovieCommand {
        MovieCommand(op: .stop, slot: slot)
    }

    public static func setVolume(_ slot: Int, _ volume: Float) -> MovieCommand {
        MovieCommand(op: .setVolume, slot: slot, volume: volume)
    }
}

/// The movie clock reported back to the engine once per step. It is the movie's audio, or the frame
/// clock when the track is silent; in virtual time a movie ends as soon as it is opened and probed.
public struct MovieClock: Sendable {
    public var slot: Int
    public var movieIndex: Int
    public var playing: Bool
    public var ended: Bool
    public var positionMicroseconds: Int64

    public init(slot: Int, movieIndex: Int, playing: Bool, ended: Bool, positionMicroseconds: Int64) {
        self.slot = slot
        self.movieIndex = movieIndex
        self.playing = playing
        self.ended = ended
        self.positionMicroseconds = positionMicroseconds
    }
}
