import Foundation
import TsukiCore
import TsukiEngine

/// Options of an AudioCommandPlayer.
public struct AudioPlayerOptions: Sendable {
    public var asyncDecode: Bool
    public var cacheBudgetBytes: Int64

    public init(asyncDecode: Bool = false, cacheBudgetBytes: Int64 = 256 << 20) {
        self.asyncDecode = asyncDecode
        self.cacheBudgetBytes = cacheBudgetBytes
    }
}

/// A clip that could not be played (missing entry, decode error).
public struct AudioPlayFailure: Sendable {
    public let bank: AudioBank
    public let entry: Int
    public let error: String

    public init(bank: AudioBank, entry: Int, error: Error) {
        self.bank = bank
        self.entry = entry
        self.error = String(describing: error)
    }
}

/// Performs AudioCommands on an AudioMixer. Not thread-safe: call it from the engine thread.
public final class AudioCommandPlayer {
    private final class Pending {
        var bank: AudioBank
        var entry: Int
        var clip: AudioClip?
        var loop: Bool
        var repeats: Int = -1
        var startFrame: Int
        var gain: Float
        var pan: Float

        init(
            bank: AudioBank,
            entry: Int,
            clip: AudioClip? = nil,
            loop: Bool = false,
            repeats: Int = -1,
            startFrame: Int = 0,
            gain: Float = 1.0,
            pan: Float = 0.0
        ) {
            self.bank = bank
            self.entry = entry
            self.clip = clip
            self.loop = loop
            self.repeats = repeats
            self.startFrame = startFrame
            self.gain = gain
            self.pan = pan
        }
    }

    private final class StreamState {
        var playing: Bool = false
        var posted: Bool = false
        var serial: Int64 = 0
        var startSample: Int = 0
        var pending: Pending?
    }

    private let mixer: AudioMixer
    private let _cache: ClipCache
    private let asyncDecode: Bool
    private let streams: [StreamState]
    private var _failures: [AudioPlayFailure] = []

    public private(set) var playsPosted: Int64 = 0

    /// Creates a player that decodes through data.
    public convenience init(data: GameData, mixer: AudioMixer, options: AudioPlayerOptions? = nil) {
        self.init(clips: { bank, entry in data.audio(bank, entry) }, mixer: mixer, options: options)
    }

    /// Creates a player over a clip source.
    public init(clips: @escaping (AudioBank, Int) throws -> AudioClip, mixer: AudioMixer, options: AudioPlayerOptions? = nil) {
        self.mixer = mixer
        let opts = options ?? AudioPlayerOptions()
        self.asyncDecode = opts.asyncDecode
        self._cache = ClipCache(decode: clips, budgetBytes: opts.cacheBudgetBytes)
        var sts: [StreamState] = []
        sts.reserveCapacity(AudioStreams.count)
        for _ in 0..<AudioStreams.count {
            sts.append(StreamState())
        }
        self.streams = sts
    }

    deinit {
        dispose()
    }

    /// The decoded-clip cache.
    public var cache: ClipCache {
        _cache
    }

    /// Clips that could not be played, oldest first.
    public var failures: [AudioPlayFailure] {
        _failures
    }

    /// Stops decoding and waits for decodes that are running.
    public func shutdown(timeout: TimeInterval) -> Bool {
        _cache.shutdown(timeout: timeout)
    }

    public func dispose() {
        _cache.dispose()
    }

    /// Starts decoding an entry on a worker (a BGM about to play).
    public func prefetch(bank: AudioBank, entry: Int) {
        _cache.prefetch(bank: bank, entry: entry)
    }

    /// Performs one command.
    public func perform(_ command: AudioCommand) {
        apply(command)
        pump()
    }

    /// Performs commands of one step in order.
    public func perform(_ commands: [AudioCommand]) {
        for c in commands {
            apply(c)
        }
        pump()
    }

    /// Starts every pending play whose clip has arrived.
    public func pump() {
        for s in 0..<streams.count {
            let st = streams[s]
            guard let p = st.pending else { continue }

            if p.clip == nil && !asyncDecode {
                // Synchronous decode was already tried or clip ready
            }

            if p.clip != nil {
                postPlay(stream: s, st: st, p: p)
            }
        }
    }

    /// True while stream plays as sound library would answer is_playing.
    public func isPlaying(_ stream: Int) -> Bool {
        let st = streams[MixerVoices.stream(stream)]
        guard st.playing else { return false }
        if st.pending != nil { return true }
        return mixer.commandsApplied < st.serial || mixer.isPlaying(MixerVoices.stream(stream))
    }

    /// Stops every sound.
    public func stopAll() {
        for st in streams {
            st.pending = nil
            st.playing = false
            st.posted = false
            st.startSample = 0
        }
        mixer.post(MixerCommand.stopAll())
    }

    private func apply(_ c: AudioCommand) {
        switch c.op {
        case .openFile, .openHandle:
            _ = MixerVoices.stream(c.stream)
        case .close, .stop:
            stopStream(c.stream)
        case .play:
            beginPlay(c)
        case .setVolume:
            let st = streams[MixerVoices.stream(c.stream)]
            if let p = st.pending {
                p.gain = c.value0
            } else if st.posted {
                mixer.post(MixerCommand.setGain(voice: c.stream, gain: c.value0, rampFrames: Self.rampFrames(c.value1)))
            }
        case .setVolume0:
            let st = streams[MixerVoices.stream(c.stream)]
            if let p = st.pending {
                p.gain = c.value0
            }
        case .setPan:
            let st = streams[MixerVoices.stream(c.stream)]
            let pan = max(-1.0, min(1.0, c.value0))
            if let p = st.pending {
                p.pan = pan
            } else if st.posted {
                mixer.post(MixerCommand.setPan(voice: c.stream, pan: pan))
            }
        case .setLoop:
            let st = streams[MixerVoices.stream(c.stream)]
            if let p = st.pending {
                p.loop = c.arg0 != 0
                p.repeats = c.arg1 < 0 ? -1 : max(0, c.arg1 - 1)
            }
        case .setStartSample:
            streams[MixerVoices.stream(c.stream)].startSample = c.arg0
        case .setFlag6:
            break
        case .playSystem:
            playSystem(c)
        }
    }

    private static func rampFrames(_ time: Float) -> Int {
        time > 0.0 ? Int((time * Float(AudioMixer.defaultRampFrames)).rounded()) : -1
    }

    private func beginPlay(_ c: AudioCommand) {
        let st = streams[MixerVoices.stream(c.stream)]
        let p = Pending(
            bank: c.bank,
            entry: c.entry,
            loop: c.arg0 != 0,
            startFrame: st.startSample,
            gain: c.value0
        )
        st.startSample = 0
        st.pending = nil

        do {
            if asyncDecode {
                let bank = c.bank
                let entry = c.entry
                DispatchQueue.global().async { [weak self, weak st, weak p] in
                    guard let self = self, let st = st, let p = p else { return }
                    do {
                        let clip = try self._cache.get(bank: bank, entry: entry)
                        p.clip = clip
                    } catch {
                        self.fail(p: p, error: error)
                        st.pending = nil
                        st.playing = false
                    }
                }
            } else {
                p.clip = try _cache.get(bank: c.bank, entry: c.entry)
            }
        } catch {
            fail(p: p, error: error)
            st.playing = false
            return
        }

        st.pending = p
        st.playing = true
    }

    private func postPlay(stream: Int, st: StreamState, p: Pending) {
        guard let clip = p.clip else { return }
        st.pending = nil

        guard clip.frameCount > 0, clip.channels == 1 || clip.channels == 2 else {
            fail(p: p, error: TsukiError.format("clip \(p.bank)#\(p.entry) has \(clip.frameCount) frames and \(clip.channels) channels"))
            st.playing = false
            return
        }

        var loop = p.loop && clip.loop != nil
        var end = loop ? (clip.loop!.end + 1) : clip.frameCount
        if end > clip.frameCount {
            end = clip.frameCount
            loop = false
        }

        let start = (p.startFrame >= 0 && p.startFrame < end) ? p.startFrame : 0
        mixer.post(MixerCommand.play(
            voice: MixerVoices.stream(stream),
            clip: clip,
            loop: loop,
            gain: p.gain,
            pan: p.pan,
            repeats: p.repeats,
            startFrame: start
        ))

        st.serial = mixer.commandsPosted
        st.posted = true
        playsPosted += 1
    }

    private func stopStream(_ stream: Int) {
        let st = streams[MixerVoices.stream(stream)]
        st.pending = nil
        st.playing = false
        if st.posted {
            st.posted = false
            mixer.post(MixerCommand.stop(voice: stream))
        }
    }

    private func playSystem(_ c: AudioCommand) {
        let left = c.entry
        let right = c.arg0
        guard left > 0 else { return }

        let voice = MixerVoices.system(c.stream)
        do {
            let l = try _cache.get(bank: .vag, entry: left)
            if right >= 0 {
                let r = try _cache.get(bank: .vag, entry: right)
                mixer.post(MixerCommand.play(voice: voice, clip: l, loop: false, gain: c.value0, pan: -1.0))
                mixer.post(MixerCommand.play(voice: MixerVoices.systemRight(c.stream), clip: r, loop: false, gain: c.value0, pan: 1.0))
            } else {
                mixer.post(MixerCommand.play(voice: voice, clip: l, loop: false, gain: c.value0, pan: 0.0))
            }
            playsPosted += 1
        } catch {
            _failures.append(AudioPlayFailure(bank: .vag, entry: left, error: error))
        }
    }

    private func fail(p: Pending, error: Error) {
        _failures.append(AudioPlayFailure(bank: p.bank, entry: p.entry, error: error))
    }
}
