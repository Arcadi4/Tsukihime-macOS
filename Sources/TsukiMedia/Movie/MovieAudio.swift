import Darwin
import Foundation

/// Single-producer single-consumer float32 stereo ring between the movie thread and the audio callback.
public final class PcmRing: @unchecked Sendable {
    private let lock = NSLock()
    private var buf: [Float]
    private var _written: Int64 = 0
    private var _read: Int64 = 0
    private var _completed: Bool = false

    /// Creates a ring of capacityFrames stereo frames (4 s = 192,000 by default).
    public init(capacityFrames: Int = 4 * 48_000) {
        self.capacityFrames = capacityFrames
        self.buf = [Float](repeating: 0, count: capacityFrames * 2)
    }

    /// Capacity in frames.
    public let capacityFrames: Int

    /// Frames written so far.
    public var written: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return _written
    }

    /// Frames read so far.
    public var readFrames: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return _read
    }

    /// Frames waiting to be read.
    public var bufferedFrames: Int {
        lock.lock()
        defer { lock.unlock() }
        return Int(_written - _read)
    }

    /// Frames that can be written now.
    public var freeFrames: Int {
        capacityFrames - bufferedFrames
    }

    /// Set by the producer after its last write.
    public var completed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _completed
    }

    /// Producer: no more frames will come.
    public func complete() {
        lock.lock()
        _completed = true
        lock.unlock()
    }

    /// Producer: writes as many frames as fit; returns count written.
    public func write(_ interleaved: [Float]) -> Int {
        interleaved.withUnsafeBufferPointer { bufPtr in
            write(bufPtr)
        }
    }

    /// Producer: writes as many frames as fit; returns count written.
    public func write(_ interleaved: UnsafeBufferPointer<Float>) -> Int {
        lock.lock()
        defer { lock.unlock() }

        let free = capacityFrames - Int(_written - _read)
        let frames = min(interleaved.count / 2, free)
        if frames <= 0 { return 0 }

        let capSamples = capacityFrames * 2
        let startSample = Int(_written % Int64(capacityFrames)) * 2
        let toCopy = frames * 2

        guard let src = interleaved.baseAddress else { return 0 }

        buf.withUnsafeMutableBufferPointer { dstPtr in
            guard let dst = dstPtr.baseAddress else { return }
            let firstPart = min(toCopy, capSamples - startSample)
            memcpy(dst + startSample, src, firstPart * MemoryLayout<Float>.size)
            if toCopy > firstPart {
                memcpy(dst, src + firstPart, (toCopy - firstPart) * MemoryLayout<Float>.size)
            }
        }

        _written += Int64(frames)
        return frames
    }

    /// Consumer: reads up to dst.count / 2 frames; returns count read.
    public func read(_ dst: UnsafeMutableBufferPointer<Float>) -> Int {
        lock.lock()
        defer { lock.unlock() }

        let avail = Int(_written - _read)
        let frames = min(dst.count / 2, avail)
        if frames <= 0 { return 0 }

        let capSamples = capacityFrames * 2
        let startSample = Int(_read % Int64(capacityFrames)) * 2
        let toCopy = frames * 2

        guard let out = dst.baseAddress else { return 0 }

        buf.withUnsafeBufferPointer { srcPtr in
            guard let src = srcPtr.baseAddress else { return }
            let firstPart = min(toCopy, capSamples - startSample)
            memcpy(out, src + startSample, firstPart * MemoryLayout<Float>.size)
            if toCopy > firstPart {
                memcpy(out + firstPart, src, (toCopy - firstPart) * MemoryLayout<Float>.size)
            }
        }

        _read += Int64(frames)
        return frames
    }
}

/// The mixer stream voice of a movie: reads PcmRing and reports every read to movie's AudioClock.
public final class MovieAudioSource: MixerSource, @unchecked Sendable {
    private let ring: PcmRing
    private let clock: AudioClock
    private let now: @Sendable () -> Int64

    public init(ring: PcmRing, clock: AudioClock, timestamp: (@Sendable () -> Int64)? = nil) {
        self.ring = ring
        self.clock = clock
        self.now = timestamp ?? {
            Int64(mach_absolute_time())
        }
    }

    public var channels: Int { 2 }

    public var ended: Bool {
        ring.completed && ring.bufferedFrames == 0
    }

    public private(set) var underrunFrames: Int64 = 0

    public func read(interleaved: UnsafeMutableBufferPointer<Float>) -> Int {
        let want = interleaved.count / 2
        let completed = ring.completed
        let got = ring.read(interleaved)

        if got < want && !completed {
            underrunFrames += Int64(want - got)
        }

        clock.onCallback(mediaFrames: got, requestedFrames: want, timestamp: now(), endOfStream: completed)
        return got
    }
}
