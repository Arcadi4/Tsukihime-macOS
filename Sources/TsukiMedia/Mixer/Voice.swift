import Foundation
import TsukiEngine

/// A linear ramp of a float32 value (gain or pan). Set at frame F with length N from the current value g0 to g1,
/// frame F + k - 1 (k = 1..N) gets `g0 + (g1 - g0) * (k / N)` and every later frame g1.
public struct Ramp: Sendable {
    private var _g0: Float
    private var _g1: Float
    private var _start: Int64
    private var _n: Int

    public init(_ value: Float) {
        _g0 = value
        _g1 = value
        _start = 0
        _n = 0
    }

    /// True when every frame from t on has the target value.
    public func constantFrom(_ t: Int64) -> Bool {
        _n == 0 || (t - _start + 1) >= Int64(_n)
    }

    /// The value of output frame t.
    public func at(_ t: Int64) -> Float {
        if _n == 0 {
            return _g1
        }
        let k = t - _start + 1
        if k >= Int64(_n) {
            return _g1
        }
        if k <= 0 {
            return _g0
        }
        return _g0 + ((_g1 - _g0) * (Float(k) / Float(_n)))
    }

    /// Starts a ramp to target at frame over frames.
    public mutating func set(target: Float, frame: Int64, frames: Int) {
        let current = at(frame - 1)
        _g1 = target
        if frames <= 0 {
            _g0 = target
            _n = 0
        } else {
            _g0 = current
            _start = frame
            _n = frames
        }
    }
}

/// One mixer voice: a clip with its loop, or a streaming source; gain and pan ramps; the engine pan law.
public final class Voice: @unchecked Sendable {
    public var active: Bool = false
    public var gain: Ramp = Ramp(1.0)
    public var pan: Ramp = Ramp(0.0)

    private var scratch: [Float] = [Float](repeating: 0, count: AudioMixer.maxPeriodFrames * 2)
    private var samples: [Float] = []
    private var source: (any MixerSource)?
    private var channels: Int = 0
    private var frames: Int = 0
    private var loop: Bool = false
    private var loopStart: Int = 0
    private var loopEnd: Int = 0
    private var repeats: Int = -1
    private var pos: Int = 0

    public init() {}

    public func start(clip: AudioClip, loop: Bool, repeats: Int, startFrame: Int, gain: Float, pan: Float) {
        self.source = nil
        self.samples = clip.samples
        self.channels = clip.channels
        self.frames = clip.frameCount
        self.loop = loop && clip.loop != nil
        self.loopStart = clip.loop?.start ?? 0
        self.loopEnd = clip.loop?.end ?? 0
        self.repeats = repeats
        self.pos = startFrame
        self.gain = Ramp(gain)
        self.pan = Ramp(pan)
        self.active = true
    }

    public func start(source: any MixerSource, gain: Float, pan: Float) {
        self.source = source
        self.samples = []
        self.channels = source.channels
        self.frames = 0
        self.loop = false
        self.gain = Ramp(gain)
        self.pan = Ramp(pan)
        self.active = true
    }

    public func stop() {
        self.source = nil
        self.samples = []
        self.active = false
    }

    /// Adds this voice into period (interleaved stereo); t0 is its first output frame.
    public func mix(period: UnsafeMutableBufferPointer<Float>, t0: Int64) {
        let need = period.count / 2
        var done = 0

        while done < need && active {
            let n: Int
            let periodSlice = UnsafeMutableBufferPointer(rebasing: period[(done * 2)..<period.count])

            if let src = source {
                let wantFrames = need - done
                let wantSamples = wantFrames * channels
                var readFrames = 0

                scratch.withUnsafeMutableBufferPointer { scratchBuf in
                    let readBuf = UnsafeMutableBufferPointer(rebasing: scratchBuf[0..<wantSamples])
                    readFrames = src.read(interleaved: readBuf)
                }

                if readFrames <= 0 {
                    if src.ended {
                        stop()
                    }
                    return // underflow: silence for the rest of period
                }

                n = readFrames
                scratch.withUnsafeBufferPointer { scratchBuf in
                    add(d: periodSlice, s: scratchBuf, count: n, t: t0 + Int64(done))
                }

                done += n
                if done < need {
                    if src.ended {
                        stop()
                    }
                    return // one read per period: short read is an underflow
                }
            } else {
                let segEnd = loop ? (loopEnd + 1) : frames
                n = min(need - done, segEnd - pos)

                samples.withUnsafeBufferPointer { sBuf in
                    let sSlice = UnsafeBufferPointer(rebasing: sBuf[(pos * channels)..<((pos + n) * channels)])
                    add(d: periodSlice, s: sSlice, count: n, t: t0 + Int64(done))
                }

                done += n
                pos += n

                if pos == segEnd {
                    if loop && repeats != 0 {
                        pos = loopStart
                        if repeats > 0 {
                            repeats -= 1
                        }
                    } else {
                        stop()
                    }
                }
            }
        }
    }

    private func add(
        d: UnsafeMutableBufferPointer<Float>,
        s: UnsafeBufferPointer<Float>,
        count n: Int,
        t: Int64
    ) {
        if gain.constantFrom(t) && pan.constantFrom(t) {
            var gl: Float = 0
            var gr: Float = 0
            Self.panLaw(g: gain.at(t), p: pan.at(t), gl: &gl, gr: &gr)

            if channels == 2 {
                for i in 0..<n {
                    d[2 * i] += gl * s[2 * i]
                    d[(2 * i) + 1] += gr * s[(2 * i) + 1]
                }
            } else {
                for i in 0..<n {
                    let sample = s[i]
                    d[2 * i] += gl * sample
                    d[(2 * i) + 1] += gr * sample
                }
            }
            return
        }

        for i in 0..<n {
            var gl: Float = 0
            var gr: Float = 0
            let frameTime = t + Int64(i)
            Self.panLaw(g: gain.at(frameTime), p: pan.at(frameTime), gl: &gl, gr: &gr)

            let sl = channels == 2 ? s[2 * i] : s[i]
            let sr = channels == 2 ? s[(2 * i) + 1] : s[i]
            d[2 * i] += gl * sl
            d[(2 * i) + 1] += gr * sr
        }
    }

    /// Engine stereo pan law (audio.md 7, VA 0x118658):
    /// q = (p + 1) / 2, gL = min(2 (1 - q), 1), gR = min(2 q, 1).
    public static func panLaw(g: Float, p: Float, gl: inout Float, gr: inout Float) {
        let q = (p + 1.0) * 0.5
        gl = g * min(2.0 * (1.0 - q), 1.0)
        gr = g * min(2.0 * q, 1.0)
    }
}
