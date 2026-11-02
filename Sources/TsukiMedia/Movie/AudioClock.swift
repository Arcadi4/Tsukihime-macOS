import Foundation

/// An audio-master clock fed by the audio thread and read by the 60 Hz tick (thread-safe).
public final class AudioClock: @unchecked Sendable {
    private let gate = NSLock()
    private let rate: Int
    private let latency: Double
    private let frequency: Double
    private let basePts: Double
    private var _mediaFrames: Int64 = 0
    private var _lastCallback: Int64 = 0
    private var _haveCallback: Bool = false
    private var _lastChunk: Int = 0
    private var _drained: Bool = false
    private var _last: Double = -Double.infinity

    /// Creates a clock.
    public init(timestampFrequency: Int64, sampleRate: Int = 48_000, latencySeconds: Double = 0.010, basePts: Double = 0) {
        self.rate = sampleRate
        self.latency = latencySeconds
        self.frequency = Double(timestampFrequency)
        self.basePts = basePts
    }

    /// Media frames handed to the device so far.
    public var mediaFrames: Int64 {
        gate.lock()
        defer { gate.unlock() }
        return _mediaFrames
    }

    /// True once the stream has ended and the source ran dry.
    public var drained: Bool {
        gate.lock()
        defer { gate.unlock() }
        return _drained
    }

    /// Audio thread: mediaFrames (of requestedFrames asked for) were handed to the device at timestamp;
    /// endOfStream once the source has no more.
    public func onCallback(mediaFrames: Int, requestedFrames: Int, timestamp: Int64, endOfStream: Bool) {
        gate.lock()
        defer { gate.unlock() }
        _mediaFrames += Int64(mediaFrames)
        _lastCallback = timestamp
        _haveCallback = true
        _lastChunk = requestedFrames
        if endOfStream && mediaFrames < requestedFrames {
            _drained = true
        }
    }

    /// The media clock in seconds at timestamp, or Double.nan before the first callback.
    public func clockAt(_ timestamp: Int64) -> Double {
        gate.lock()
        defer { gate.unlock() }

        if !_haveCallback {
            return Double.nan
        }

        var elapsed = Double(timestamp - _lastCallback) / frequency
        let maxElapsed = Double(_lastChunk) / Double(rate)

        if !_drained {
            elapsed = min(elapsed, maxElapsed)
        }

        var clock = basePts + (Double(_mediaFrames) / Double(rate)) - latency + elapsed
        if clock < _last {
            clock = _last
        } else {
            _last = clock
        }

        return clock
    }
}
