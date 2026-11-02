import Darwin
import Foundation
import TsukiEngine

/// Options of a MoviePlayer.
public struct MoviePlayerOptions: Sendable {
    public var pipeline: MoviePipelineOptions?
    public var cadenceLockSeconds: Double
    public var audioLatencySeconds: Double
    public var audioClockTimeoutSeconds: Double
    public var prerollAudioFrames: Int

    public init(
        pipeline: MoviePipelineOptions? = nil,
        cadenceLockSeconds: Double = FrameSelector.defaultCadenceLockSeconds,
        audioLatencySeconds: Double = 0.010,
        audioClockTimeoutSeconds: Double = 2.0,
        prerollAudioFrames: Int = 4800
    ) {
        self.pipeline = pipeline
        self.cadenceLockSeconds = cadenceLockSeconds
        self.audioLatencySeconds = audioLatencySeconds
        self.audioClockTimeoutSeconds = audioClockTimeoutSeconds
        self.prerollAudioFrames = prerollAudioFrames
    }
}

/// One movie playing in a slot.
public final class MoviePlayer {
    private static let audioStreamDecoderRate = 48_000
    public static let timestampFrequency: Int64 = 1_000_000_000

    private let options: MoviePlayerOptions
    private let mixer: AudioMixer?
    private let voice: Int
    private let selector: FrameSelector
    private var stamps: [FrameStamp] = [FrameStamp](repeating: FrameStamp(index: 0, pts: 0), count: 16)
    private let frameDuration: Double
    private var audioClock: AudioClock?
    private var volume: Float
    private var prerolled: Bool = false
    private var frameClock: Bool = false
    private var basePts: Double = 0.0
    private var playStart: Int64 = 0
    private var voiceStarted: Int64 = 0
    private var lastAudioClock: Double = Double.nan
    private var lastAudioChange: Int64 = 0
    private var _ended: Bool = false
    private var _current: VideoFrame?

    public let slot: Int
    public let movieIndex: Int
    public let pipeline: MoviePipeline

    public init(
        slot: Int,
        movieIndex: Int,
        path: String,
        volume: Float,
        mixer: AudioMixer?,
        options: MoviePlayerOptions? = nil
    ) throws {
        self.slot = slot
        self.movieIndex = movieIndex
        let opts = options ?? MoviePlayerOptions()
        self.options = opts
        self.mixer = mixer
        self.voice = MixerVoices.movie(slot)
        self.volume = volume
        self.selector = FrameSelector(cadenceLockSeconds: opts.cadenceLockSeconds)
        self.pipeline = try MoviePipeline(path: path, options: opts.pipeline)
        self.frameDuration = 1.0 / pipeline.fps

        if mixer == nil {
            pipeline.discardAudio()
        }

        pipeline.start()
    }

    deinit {
        dispose()
    }

    public var current: VideoFrame? { _current }
    public var started: Bool { prerolled }
    public var usesFrameClock: Bool { frameClock || audioClock == nil }
    public var ended: Bool { _ended }
    public var error: Error? { pipeline.error }

    public func setVolume(_ volume: Float) {
        self.volume = volume
        if audioClock != nil {
            mixer?.post(MixerCommand.setGain(voice: voice, gain: volume))
        }
    }

    /// One 60 Hz tick: timestamp is the tick's nominal time in nanoseconds.
    public func tick(_ timestamp: Int64) -> MovieClock {
        if _ended {
            return report(clock(timestamp), playing: false)
        }

        if !prerolled && !tryPreroll(timestamp) {
            if pipeline.error != nil || (pipeline.frames.endOfStream && pipeline.frames.readyCount == 0) {
                _ended = true
            }
            return report(0, playing: !_ended)
        }

        var c = clock(timestamp)
        if c.isNaN {
            c = basePts - 1.0 // hold first frame
        }

        let ready = pipeline.frames.peekStamps(&stamps)
        let readySlice = Array(stamps[0..<ready])
        let consumed = selector.tick(clock: c, ready: readySlice)

        for i in 0..<consumed {
            let f = pipeline.frames.dequeue()
            if i == consumed - 1 {
                if let cur = _current {
                    pipeline.frames.returnFrame(cur)
                }
                _current = f
            } else {
                pipeline.frames.returnFrame(f)
            }
        }

        if !(options.pipeline?.loop ?? false) {
            let last = pipeline.frames.endOfStream && pipeline.frames.readyCount == 0
            if last && (_current == nil || (_current!.index == pipeline.lastVideoIndex && c >= _current!.pts + frameDuration - 1e-9)) {
                _ended = true
            }
        }

        return report(c, playing: !_ended)
    }

    public func dispose() {
        if audioClock != nil {
            mixer?.post(MixerCommand.stop(voice: voice))
        }
        pipeline.dispose()
    }

    private func tryPreroll(_ timestamp: Int64) -> Bool {
        guard let first = pipeline.frames.peek() else { return false }

        let audioReady = !pipeline.hasAudio || mixer == nil
            || (pipeline.firstAudioSample >= 0 && (pipeline.pcm.bufferedFrames >= options.prerollAudioFrames || pipeline.pcm.completed))
            || pipeline.demuxEnded

        guard audioReady else { return false }

        if pipeline.hasAudio, let m = mixer {
            basePts = pipeline.firstAudioSample >= 0 ? Double(pipeline.firstAudioSample) / Double(Self.audioStreamDecoderRate) : first.pts
            let aClock = AudioClock(timestampFrequency: Self.timestampFrequency, sampleRate: Self.audioStreamDecoderRate, latencySeconds: options.audioLatencySeconds, basePts: basePts)
            self.audioClock = aClock
            let source = MovieAudioSource(ring: pipeline.pcm, clock: aClock)
            m.post(MixerCommand.playStream(voice: voice, source: source, gain: volume))
            voiceStarted = timestamp
            lastAudioChange = timestamp
        } else {
            basePts = first.pts
        }

        playStart = timestamp
        prerolled = true
        return true
    }

    private func clock(_ timestamp: Int64) -> Double {
        guard prerolled else { return 0 }

        if let aClock = audioClock, !frameClock {
            let c = aClock.clockAt(timestamp)
            let sinceChange = Double(timestamp - lastAudioChange) / Double(Self.timestampFrequency)

            if !c.isNaN {
                if c != lastAudioClock {
                    lastAudioClock = c
                    lastAudioChange = timestamp
                    return c
                }

                if aClock.drained || sinceChange <= options.audioClockTimeoutSeconds {
                    return c
                }
            } else if Double(timestamp - voiceStarted) / Double(Self.timestampFrequency) <= options.audioClockTimeoutSeconds {
                return Double.nan
            }

            frameClock = true
            basePts = c.isNaN ? (_current?.pts ?? basePts) : c
            playStart = timestamp
            pipeline.discardAudio()
            mixer?.post(MixerCommand.stop(voice: voice))
        }

        return basePts + (Double(timestamp - playStart) / Double(Self.timestampFrequency))
    }

    private func report(_ clockSeconds: Double, playing: Bool) -> MovieClock {
        let micros: Int64 = clockSeconds.isNaN ? 0 : Int64(max(0, (clockSeconds * 1_000_000).rounded()))
        return MovieClock(slot: slot, movieIndex: movieIndex, playing: playing, ended: _ended, positionMicroseconds: micros)
    }
}
