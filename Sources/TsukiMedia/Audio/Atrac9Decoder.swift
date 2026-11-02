import Darwin
import Foundation
import TsukiCore

/// One libavcodec ATRAC9 decoder context for one stream. Not thread-safe; one per worker.
public final class Atrac9Decoder {
    private let header: RiffAtrac9
    private var ctx: UnsafeMutableRawPointer?
    private var pkt: UnsafeMutableRawPointer?
    private var frame: UnsafeMutableRawPointer?

    // Known FFmpeg constants and offsets
    private static let avInputBufferPaddingSize = 64
    private static let sampleRateOffset = 344
    private static let blockAlignOffset = 380
    private static let chLayoutOffset = 352
    private static let extradataOffset = 72
    private static let extradataSizeOffset = 80
    private static let frameNbSamplesOffset = 112
    private static let frameFormatOffset = 116
    private static let frameExtendedDataOffset = 96
    private static let packetDataOffset = 24
    private static let packetSizeOffset = 32
    private static let sampleFmtFltp: Int32 = 8
    private static let eagain: Int32 = -35
    private static let averrorEof: Int32 = -541478725

    public init(header: RiffAtrac9) throws {
        self.header = header

        if !FfmpegLibrary.isLoaded {
            _ = try FfmpegLibrary.load()
        }

        let b = FfmpegBindings.shared
        guard let findFn = b.avcodec_find_decoder_by_name,
              let allocCtxFn = b.avcodec_alloc_context3,
              let openFn = b.avcodec_open2,
              let allocPktFn = b.av_packet_alloc,
              let allocFrameFn = b.av_frame_alloc,
              let malloczFn = b.av_mallocz,
              let chLayoutDefFn = b.av_channel_layout_default else {
            throw FfmpegError.notLoaded
        }

        guard let codec = "atrac9".withCString({ findFn($0) }) else {
            throw FfmpegError.codecNotFound("atrac9")
        }

        guard let c = allocCtxFn(codec) else {
            throw FfmpegError.loadFailed("avcodec_alloc_context3 returned null")
        }
        self.ctx = c

        // Set sample_rate, block_align
        c.advanced(by: Self.sampleRateOffset).storeBytes(of: Int32(header.sampleRate), as: Int32.self)
        c.advanced(by: Self.blockAlignOffset).storeBytes(of: Int32(header.blockAlign), as: Int32.self)

        // Set ch_layout
        let chLayoutPtr = c.advanced(by: Self.chLayoutOffset)
        _ = chLayoutDefFn(chLayoutPtr, Int32(header.channels))

        // Set extradata
        let extra = header.extradata
        let extraAlloc = extra.count + Self.avInputBufferPaddingSize
        guard let extraBuf = malloczFn(extraAlloc) else {
            dispose()
            throw FfmpegError.loadFailed("av_mallocz for extradata failed")
        }

        extra.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                memcpy(extraBuf, base, extra.count)
            }
        }
        c.advanced(by: Self.extradataOffset).storeBytes(of: extraBuf, as: UnsafeMutableRawPointer.self)
        c.advanced(by: Self.extradataSizeOffset).storeBytes(of: Int32(extra.count), as: Int32.self)

        let openRet = openFn(c, codec, nil)
        guard openRet >= 0 else {
            dispose()
            throw FfmpegError.nativeError(code: openRet, message: "avcodec_open2 failed")
        }

        guard let p = allocPktFn(), let f = allocFrameFn() else {
            dispose()
            throw FfmpegError.loadFailed("av_packet_alloc or av_frame_alloc failed")
        }
        self.pkt = p
        self.frame = f
    }

    deinit {
        dispose()
    }

    public func dispose() {
        let b = FfmpegBindings.shared
        if pkt != nil {
            var p: UnsafeMutableRawPointer? = pkt
            b.av_packet_free?(&p)
            pkt = nil
        }
        if frame != nil {
            var f: UnsafeMutableRawPointer? = frame
            b.av_frame_free?(&f)
            frame = nil
        }
        if ctx != nil {
            var c: UnsafeMutableRawPointer? = ctx
            b.avcodec_free_context?(&c)
            ctx = nil
        }
    }

    /// Decodes superframes [first, first + count) of stream into dst; returns frames written.
    public func decode(stream: ByteSpan, first: Int, count: Int, dst: inout [Float], dstOffset: Int = 0) throws -> Int {
        guard let c = ctx, let p = pkt else {
            throw FfmpegError.loadFailed("decoder is disposed")
        }

        guard first >= 0, count >= 0, first + count <= header.superframes else {
            throw TsukiError.format("superframes [\(first), \(first + count)) outside [0, \(header.superframes))")
        }

        let end = header.dataOffset + ((first + count) * header.blockAlign)
        guard header.dataOffset >= 0, header.blockAlign > 0, end <= stream.count else {
            throw TsukiError.format("superframes end at byte \(end), but stream has \(stream.count) bytes")
        }

        let b = FfmpegBindings.shared
        guard let sendPktFn = b.avcodec_send_packet else {
            throw FfmpegError.notLoaded
        }

        var written = 0
        try stream.withUnsafeBytes { raw in
            guard let rawBase = raw.baseAddress else { return }

            for s in first..<(first + count) {
                let packetPtr = rawBase.advanced(by: header.dataOffset + (s * header.blockAlign))
                p.advanced(by: Self.packetDataOffset).storeBytes(of: UnsafeMutableRawPointer(mutating: packetPtr), as: UnsafeMutableRawPointer?.self)
                p.advanced(by: Self.packetSizeOffset).storeBytes(of: Int32(header.blockAlign), as: Int32.self)

                let sendRet = sendPktFn(c, p)
                guard sendRet >= 0 else {
                    throw FfmpegError.nativeError(code: sendRet, message: "avcodec_send_packet failed")
                }

                written += try drain(dst: &dst, dstOffset: dstOffset + (written * header.channels))
            }
        }

        // Reset packet pointers
        p.advanced(by: Self.packetDataOffset).storeBytes(of: nil as UnsafeMutableRawPointer?, as: UnsafeMutableRawPointer?.self)
        p.advanced(by: Self.packetSizeOffset).storeBytes(of: Int32(0), as: Int32.self)

        return written
    }

    /// End of stream flush.
    public func finish(dst: inout [Float], dstOffset: Int = 0) throws -> Int {
        guard let c = ctx else {
            throw FfmpegError.loadFailed("decoder is disposed")
        }
        let b = FfmpegBindings.shared
        guard let sendPktFn = b.avcodec_send_packet,
              let flushFn = b.avcodec_flush_buffers else {
            throw FfmpegError.notLoaded
        }

        let ret = sendPktFn(c, nil)
        guard ret >= 0 else {
            throw FfmpegError.nativeError(code: ret, message: "avcodec_send_packet(flush) failed")
        }

        let written = try drain(dst: &dst, dstOffset: dstOffset)
        flushFn(c)
        return written
    }

    /// Resets decoder context.
    public func reset() throws {
        guard let c = ctx else { throw FfmpegError.loadFailed("decoder is disposed") }
        FfmpegBindings.shared.avcodec_flush_buffers?(c)
    }

    /// Decodes every superframe of stream.
    public static func decodeAll(_ header: RiffAtrac9, stream: ByteSpan) throws -> [Float] {
        var decoded = [Float](repeating: 0, count: header.decodedFrames * header.channels)
        let dec = try Atrac9Decoder(header: header)
        defer { dec.dispose() }

        var n = try dec.decode(stream: stream, first: 0, count: header.superframes, dst: &decoded, dstOffset: 0)
        n += try dec.finish(dst: &decoded, dstOffset: n * header.channels)

        guard n == header.decodedFrames else {
            throw TsukiError.format("atrac9 produced \(n) frames, expected \(header.decodedFrames)")
        }

        return decoded
    }

    private func drain(dst: inout [Float], dstOffset: Int) throws -> Int {
        guard let c = ctx, let f = frame else { return 0 }
        let b = FfmpegBindings.shared
        guard let recvFn = b.avcodec_receive_frame,
              let unrefFn = b.av_frame_unref else {
            throw FfmpegError.notLoaded
        }

        var frames = 0
        while true {
            let r = recvFn(c, f)
            if r == Self.eagain || r == Self.averrorEof {
                return frames
            }
            guard r >= 0 else {
                throw FfmpegError.nativeError(code: r, message: "avcodec_receive_frame failed")
            }

            defer {
                unrefFn(f)
            }

            let fmt = f.advanced(by: Self.frameFormatOffset).load(as: Int32.self)
            guard fmt == Self.sampleFmtFltp else {
                throw TsukiError.format("atrac9 produced format \(fmt), expected FLTP (\(Self.sampleFmtFltp))")
            }

            let n = Int(f.advanced(by: Self.frameNbSamplesOffset).load(as: Int32.self))
            let ch = header.channels

            let baseIndex = dstOffset + (frames * ch)
            guard baseIndex + (n * ch) <= dst.count else {
                throw TsukiError.format("output buffer too small")
            }

            let extData = f.advanced(by: Self.frameExtendedDataOffset).load(as: UnsafeMutablePointer<UnsafeMutablePointer<Float>>.self)
            for chIdx in 0..<ch {
                let src = extData[chIdx]
                for i in 0..<n {
                    dst[baseIndex + (i * ch) + chIdx] = src[i]
                }
            }

            frames += n
        }
    }
}
