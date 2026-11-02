import Foundation
import TsukiEngine

/// Mixes clip and stream voices into float32 stereo at 48 kHz; nothing is clipped before the device.
public final class AudioMixer: @unchecked Sendable {
    /// Output rate (the PS4 rate).
    public static let sampleRate = 48_000

    /// Output channels.
    public static let channels = 2

    /// The largest period rendered in one piece (the engine's grain, audio.md 7).
    public static let maxPeriodFrames = 1024

    /// Voice slots: streams 0..25 (AudioStreams), system voices 0x2C..0x2F and more.
    public static let maxVoices = 64

    /// The default gain / pan ramp: one 60 Hz step (800 frames).
    public static let defaultRampFrames = sampleRate / 60

    /// Output frames a change of masterGainTarget takes to complete (half a second).
    public static let masterFadeFrames = sampleRate / 2

    private let lock = NSLock()
    private var _inbox: [MixerCommand] = []
    private var _pending: [MixerCommand] = []
    private let _voices: [Voice]
    private var _frame: Int64 = 0
    private var _posted: Int64 = 0
    private var _applied: Int64 = 0
    private var _masterTarget: Float = 1.0
    private var _master: Float = 1.0

    /// Creates a mixer with every voice idle.
    public init() {
        var voices: [Voice] = []
        voices.reserveCapacity(Self.maxVoices)
        for _ in 0..<Self.maxVoices {
            voices.append(Voice())
        }
        self._voices = voices
    }

    /// Output frames rendered so far.
    public var framesRendered: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return _frame
    }

    /// Commands posted so far (any thread).
    public var commandsPosted: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return _posted
    }

    /// Commands the audio thread has applied so far.
    public var commandsApplied: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return _applied
    }

    /// Posts a command (any thread). It applies before frame command.frame or the next frame.
    public func post(_ command: MixerCommand) {
        guard command.voice >= 0 && command.voice < Self.maxVoices else {
            fatalError("voice must be 0..\(Self.maxVoices - 1), got \(command.voice)")
        }

        if command.op == .play {
            guard let clip = command.clip else {
                fatalError("play needs a clip")
            }
            guard clip.channels == 1 || clip.channels == 2 else {
                fatalError("1 or 2 channels expected, got \(clip.channels)")
            }

            let end = command.loop && clip.loop != nil ? (clip.loop!.end + 1) : clip.frameCount
            guard command.startFrame >= 0 && command.startFrame < end && end <= clip.frameCount else {
                fatalError("start frame \(command.startFrame) outside [0, \(end))")
            }
        } else if command.op == .playStream {
            guard let src = command.source, (src.channels == 1 || src.channels == 2) else {
                fatalError("play stream needs a 1- or 2-channel source")
            }
        }

        lock.lock()
        _inbox.append(command)
        _posted += 1
        lock.unlock()
    }

    /// True while voice is playing (as of the last rendered period).
    public func isPlaying(_ voice: Int) -> Bool {
        guard voice >= 0 && voice < Self.maxVoices else { return false }
        return _voices[voice].active
    }

    /// The gain the whole mix is multiplied by after the voices (0 while in background with mute on, else 1).
    public var masterGainTarget: Float {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _masterTarget
        }
        set {
            lock.lock()
            _masterTarget = max(0.0, min(1.0, newValue))
            lock.unlock()
        }
    }

    /// The master gain at the end of the last rendered period.
    public var masterGain: Float {
        lock.lock()
        defer { lock.unlock() }
        return _master
    }

    /// Renders interleaved stereo frames (any length) in periods of at most maxPeriodFrames. Audio thread only.
    public func render(_ interleaved: inout [Float]) {
        interleaved.withUnsafeMutableBufferPointer { buf in
            render(interleaved: buf)
        }
    }

    /// Renders interleaved stereo frames (any length) in periods of at most maxPeriodFrames. Audio thread only.
    public func render(interleaved: UnsafeMutableBufferPointer<Float>) {
        guard interleaved.count % Self.channels == 0 else {
            fatalError("an interleaved stereo buffer has an even length, got \(interleaved.count)")
        }

        drain()
        interleaved.initialize(repeating: 0)

        let total = interleaved.count / Self.channels
        var done = 0
        var frame = _frame

        while done < total {
            while !_pending.isEmpty && _pending[0].frame <= frame {
                apply(_pending.removeFirst(), frame: frame)
            }

            var n = min(Self.maxPeriodFrames, total - done)
            if !_pending.isEmpty {
                let untilNext = Int(_pending[0].frame - frame)
                if untilNext < n {
                    n = max(0, untilNext)
                }
            }

            if n > 0 {
                let startSample = done * Self.channels
                let endSample = startSample + (n * Self.channels)
                let period = UnsafeMutableBufferPointer(rebasing: interleaved[startSample..<endSample])

                for v in _voices {
                    if v.active {
                        v.mix(period: period, t0: frame)
                    }
                }

                applyMasterGain(period: period)
                frame += Int64(n)
                done += n

                lock.lock()
                _frame = frame
                lock.unlock()
            }
        }
    }

    private func applyMasterGain(period: UnsafeMutableBufferPointer<Float>) {
        let target: Float
        lock.lock()
        target = _masterTarget
        lock.unlock()

        var g = _master
        if g == 1.0 && target == 1.0 {
            return
        }

        let step: Float = 1.0 / Float(Self.masterFadeFrames)
        for i in stride(from: 0, to: period.count, by: Self.channels) {
            if g != target {
                if abs(target - g) <= step {
                    g = target
                } else if g < target {
                    g += step
                } else {
                    g -= step
                }
            }
            period[i] *= g
            period[i + 1] *= g
        }

        _master = g
    }

    private func drain() {
        lock.lock()
        let incoming = _inbox
        _inbox.removeAll(keepingCapacity: true)
        lock.unlock()

        for var c in incoming {
            if c.frame < _frame {
                c.frame = _frame
            }

            // Stable insert: after every pending command of the same or earlier frame
            var at = _pending.count
            while at > 0 && _pending[at - 1].frame > c.frame {
                at -= 1
            }
            _pending.insert(c, at: at)
        }
    }

    private func apply(_ c: MixerCommand, frame: Int64) {
        let ramp = c.rampFrames < 0 ? Self.defaultRampFrames : c.rampFrames
        switch c.op {
        case .play:
            _voices[c.voice].start(
                clip: c.clip!,
                loop: c.loop,
                repeats: c.repeats,
                startFrame: c.startFrame,
                gain: c.gain,
                pan: c.pan
            )
        case .playStream:
            _voices[c.voice].start(
                source: c.source!,
                gain: c.gain,
                pan: c.pan
            )
        case .stop:
            _voices[c.voice].stop()
        case .stopAll:
            for v in _voices {
                v.stop()
            }
        case .setGain:
            if _voices[c.voice].active {
                _voices[c.voice].gain.set(target: c.gain, frame: frame, frames: ramp)
            }
        case .setPan:
            if _voices[c.voice].active {
                _voices[c.voice].pan.set(target: c.pan, frame: frame, frames: ramp)
            }
        }

        lock.lock()
        _applied += 1
        lock.unlock()
    }
}
