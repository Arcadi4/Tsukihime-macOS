import CoreVideo
import Foundation
import Metal

/// One decoded picture in buffers: planes of a yuv420p frame, or native BGRA / CVPixelBuffer / MTLTexture.
public final class VideoFrame: @unchecked Sendable {
    public let width: Int
    public let height: Int
    public var y: [UInt8]
    public var u: [UInt8]
    public var v: [UInt8]
    public var bgra: [UInt8]?
    public var pixelBuffer: CVPixelBuffer?
    public var texture: (any MTLTexture)?

    /// Frame number on the movie timeline, from 0.
    public var index: Int64 = 0
    /// Presentation time in seconds on the movie timeline.
    public var pts: Double = 0.0

    public init(width: Int, height: Int) {
        precondition(width > 0 && height > 0, "dimensions must be positive")
        precondition((width | height) % 2 == 0, "yuv420p needs even dimensions")

        self.width = width
        self.height = height
        let pixels = width * height
        self.y = [UInt8](repeating: 0, count: pixels)
        self.u = [UInt8](repeating: 0, count: pixels / 4)
        self.v = [UInt8](repeating: 0, count: pixels / 4)
    }

    /// Copies a CVPixelBuffer into this frame (native macOS path).
    public func copyFrom(cvPixelBuffer: CVPixelBuffer, index: Int64, pts: Double) {
        self.pixelBuffer = cvPixelBuffer
        self.index = index
        self.pts = pts

        CVPixelBufferLockBaseAddress(cvPixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(cvPixelBuffer, .readOnly) }

        let format = CVPixelBufferGetPixelFormatType(cvPixelBuffer)
        if format == kCVPixelFormatType_32BGRA || format == kCVPixelFormatType_32ARGB {
            guard let base = CVPixelBufferGetBaseAddress(cvPixelBuffer) else { return }
            let bytesPerRow = CVPixelBufferGetBytesPerRow(cvPixelBuffer)
            let total = width * height * 4
            if bgra == nil || bgra!.count != total {
                bgra = [UInt8](repeating: 0, count: total)
            }
            bgra!.withUnsafeMutableBytes { dstRaw in
                guard let dst = dstRaw.baseAddress else { return }
                if bytesPerRow == width * 4 {
                    memcpy(dst, base, total)
                } else {
                    for r in 0..<height {
                        memcpy(dst.advanced(by: r * width * 4), base.advanced(by: r * bytesPerRow), width * 4)
                    }
                }
            }
        }
    }

    /// Copies software planar YUV from raw pointers.
    public func copyPlanes(
        ySrc: UnsafePointer<UInt8>, yStride: Int,
        uSrc: UnsafePointer<UInt8>, uStride: Int,
        vSrc: UnsafePointer<UInt8>, vStride: Int
    ) {
        Self.copyPlane(src: ySrc, stride: yStride, dst: &y, rowBytes: width, rows: height)
        Self.copyPlane(src: uSrc, stride: uStride, dst: &u, rowBytes: width / 2, rows: height / 2)
        Self.copyPlane(src: vSrc, stride: vStride, dst: &v, rowBytes: width / 2, rows: height / 2)
    }

    private static func copyPlane(
        src: UnsafePointer<UInt8>,
        stride: Int,
        dst: inout [UInt8],
        rowBytes: Int,
        rows: Int
    ) {
        dst.withUnsafeMutableBufferPointer { dstPtr in
            guard let d = dstPtr.baseAddress else { return }
            if stride == rowBytes {
                memcpy(d, src, rowBytes * rows)
                return
            }
            for r in 0..<rows {
                memcpy(d + (r * rowBytes), src + (r * stride), rowBytes)
            }
        }
    }
}

/// A fixed pool of frame buffers plus ready queue main thread pulls from.
public final class FrameQueue: @unchecked Sendable {
    private let condition = NSCondition()
    private var ready: [VideoFrame] = []
    private var free: [VideoFrame] = []
    private var closed: Bool = false

    public let capacity: Int
    public var endOfStream: Bool = false

    public init(buffers: Int, width: Int, height: Int) {
        precondition(buffers >= 2, "pool requires at least 2 buffers")
        self.capacity = buffers
        for _ in 0..<buffers {
            free.append(VideoFrame(width: width, height: height))
        }
    }

    public var readyCount: Int {
        condition.lock()
        defer { condition.unlock() }
        return ready.count
    }

    /// Decoder: takes a free buffer, waiting while consumer holds them all. Nil when closed.
    public func rent() -> VideoFrame? {
        condition.lock()
        defer { condition.unlock() }

        while free.isEmpty && !closed {
            condition.wait(until: Date(timeIntervalSinceNow: 0.05))
        }

        return closed ? nil : free.popLast()
    }

    /// Decoder: queues a filled buffer.
    public func push(_ f: VideoFrame) {
        condition.lock()
        ready.append(f)
        condition.unlock()
    }

    /// Consumer: the next frame, or nil.
    public func peek() -> VideoFrame? {
        condition.lock()
        defer { condition.unlock() }
        return ready.first
    }

    /// Consumer: copies stamps of up to stamps.count ready frames, oldest first; returns count.
    public func peekStamps(_ stamps: inout [FrameStamp]) -> Int {
        condition.lock()
        defer { condition.unlock() }

        let n = min(stamps.count, ready.count)
        for i in 0..<n {
            stamps[i] = FrameStamp(index: ready[i].index, pts: ready[i].pts)
        }
        return n
    }

    /// Consumer: removes oldest ready frame.
    public func dequeue() -> VideoFrame {
        condition.lock()
        defer { condition.unlock() }
        return ready.removeFirst()
    }

    /// Consumer: gives a buffer back to pool.
    public func returnFrame(_ f: VideoFrame) {
        condition.lock()
        free.append(f)
        condition.broadcast()
        condition.unlock()
    }

    /// Wakes decoder and makes rent() return nil.
    public func close() {
        condition.lock()
        closed = true
        condition.broadcast()
        condition.unlock()
    }
}

public enum PacketKind: UInt8, Sendable {
    case packet
    case end
    case loop
}

/// Video packets from demuxer to decoder thread.
public final class PacketQueue: @unchecked Sendable {
    private let condition = NSCondition()
    private var queue: [(packet: UnsafeMutableRawPointer?, kind: PacketKind)] = []
    private var closed: Bool = false

    public init() {}

    public var count: Int {
        condition.lock()
        defer { condition.unlock() }
        return queue.count
    }

    public func enqueue(packet: UnsafeMutableRawPointer?, kind: PacketKind) {
        condition.lock()
        if !closed {
            queue.append((packet, kind))
            condition.signal()
        }
        condition.unlock()
    }

    public func dequeue() -> (packet: UnsafeMutableRawPointer?, kind: PacketKind)? {
        condition.lock()
        defer { condition.unlock() }

        while queue.isEmpty && !closed {
            condition.wait(until: Date(timeIntervalSinceNow: 0.05))
        }

        return queue.isEmpty ? nil : queue.removeFirst()
    }

    public func close() {
        condition.lock()
        closed = true
        condition.broadcast()
        condition.unlock()
    }
}
