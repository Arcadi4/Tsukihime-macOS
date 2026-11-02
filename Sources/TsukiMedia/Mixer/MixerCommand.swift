import Foundation
import TsukiEngine

/// What a MixerCommand does.
public enum MixerOp: UInt8, Sendable {
    /// Start a clip on a voice (replacing what it played), gain and pan set at once.
    case play
    /// Start a streaming source (the movie AAC ring) on a voice.
    case playStream
    /// Stop a voice at once (every engine caller passes fade 0; fades are gain ramps).
    case stop
    /// Ramp the voice gain to a new value.
    case setGain
    /// Ramp the voice pan (-1 left .. 1 right) to a new value.
    case setPan
    /// Stop every voice.
    case stopAll
}

/// A streaming PCM source for a mixer voice (the movie audio, ARCHITECTURE 7.5).
/// Read runs on the audio thread and must not block or allocate.
public protocol MixerSource: AnyObject, Sendable {
    /// 1 or 2.
    var channels: Int { get }
    /// True once the source has no more frames and never will.
    var ended: Bool { get }
    /// Reads up to interleaved.count / channels frames; returns the frames read (fewer on an underflow).
    func read(interleaved: UnsafeMutableBufferPointer<Float>) -> Int
}

/// One mixer command (ARCHITECTURE 7.1): posted from any thread, applied by the audio thread before output frame
/// `frame` is rendered (`now` = before the next frame).
public struct MixerCommand: Sendable {
    /// Apply before the next rendered frame.
    public static let now: Int64 = -1

    public var op: MixerOp
    public var voice: Int
    public var frame: Int64
    public var clip: AudioClip?
    public var source: (any MixerSource)?
    public var loop: Bool
    public var repeats: Int
    public var startFrame: Int
    public var gain: Float
    public var pan: Float
    public var rampFrames: Int

    public init(
        op: MixerOp,
        voice: Int,
        frame: Int64 = MixerCommand.now,
        clip: AudioClip? = nil,
        source: (any MixerSource)? = nil,
        loop: Bool = false,
        repeats: Int = -1,
        startFrame: Int = 0,
        gain: Float = 1.0,
        pan: Float = 0.0,
        rampFrames: Int = -1
    ) {
        self.op = op
        self.voice = voice
        self.frame = frame
        self.clip = clip
        self.source = source
        self.loop = loop
        self.repeats = repeats
        self.startFrame = startFrame
        self.gain = gain
        self.pan = pan
        self.rampFrames = rampFrames
    }

    /// Plays clip on voice.
    public static func play(
        voice: Int,
        clip: AudioClip,
        loop: Bool,
        gain: Float,
        pan: Float,
        repeats: Int = -1,
        startFrame: Int = 0,
        frame: Int64 = MixerCommand.now
    ) -> MixerCommand {
        MixerCommand(
            op: .play,
            voice: voice,
            frame: frame,
            clip: clip,
            loop: loop,
            repeats: repeats,
            startFrame: startFrame,
            gain: gain,
            pan: pan
        )
    }

    /// Plays a streaming source on voice.
    public static func playStream(
        voice: Int,
        source: any MixerSource,
        gain: Float,
        pan: Float = 0.0,
        frame: Int64 = MixerCommand.now
    ) -> MixerCommand {
        MixerCommand(
            op: .playStream,
            voice: voice,
            frame: frame,
            source: source,
            gain: gain,
            pan: pan
        )
    }

    /// Stops voice.
    public static func stop(voice: Int, frame: Int64 = MixerCommand.now) -> MixerCommand {
        MixerCommand(op: .stop, voice: voice, frame: frame)
    }

    /// Stops every voice.
    public static func stopAll(frame: Int64 = MixerCommand.now) -> MixerCommand {
        MixerCommand(op: .stopAll, voice: 0, frame: frame)
    }

    /// Ramps the gain of voice.
    public static func setGain(voice: Int, gain: Float, rampFrames: Int = -1, frame: Int64 = MixerCommand.now) -> MixerCommand {
        MixerCommand(op: .setGain, voice: voice, frame: frame, gain: gain, rampFrames: rampFrames)
    }

    /// Ramps the pan of voice.
    public static func setPan(voice: Int, pan: Float, rampFrames: Int = -1, frame: Int64 = MixerCommand.now) -> MixerCommand {
        MixerCommand(op: .setPan, voice: voice, frame: frame, pan: pan, rampFrames: rampFrames)
    }
}
