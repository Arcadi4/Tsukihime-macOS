import Foundation
import TsukiCore
import TsukiEngine

/// What one MZX0 decode did.
public struct MzxStats: Equatable {
    /// Bytes of the stream used, header included.
    public let consumed: Int
    public let commands: Int
    /// Bytes the last command wrote past the declared size (0...127).
    public let overshoot: Int
}

/// A decoded MZX0 stream: the declared bytes, plus the decoder's slack behind them.
public struct MzxDecoded {
    public let buffer: [UInt8]
    public let length: Int
    public let stats: MzxStats

    public var span: ByteSpan { ByteSpan(buffer, offset: 0, count: length) }
    public func toArray() -> [UInt8] { Array(buffer[0..<length]) }
}

/// MZX0: a 16-bit-word LZ codec with run, back-reference, ring-buffer and literal commands.
///
/// The decoder tests "output full?" only between commands, so the last command may write up to
/// `maxOvershoot` bytes past the declared size; output buffers therefore carry `outputSlack`
/// spare bytes. Inverted streams (script sections) decode plain and are then XORed with 0xFF.
public enum Mzx {
    public static let headerSize = 8
    public static let maxOvershoot = 127
    public static let outputSlack = 128
    private static let resetWords = 0x1000
    private static let magic: [UInt8] = Array("MZX0".utf8)

    public static func isMzx(_ data: ByteSpan) -> Bool {
        data.count >= headerSize && data.slice(0, 4).elementsEqual(magic)
    }

    public static func declaredSize(_ stream: ByteSpan) throws -> Int {
        guard isMzx(stream) else { throw TsukiError.format("not an MZX0 stream") }
        let size = stream.u32(4)
        return Int(size)
    }

    public static func bufferSize(_ declaredSize: Int) -> Int { declaredSize + outputSlack }

    /// Decodes a whole MZX0 stream into a new buffer.
    public static func decompress(_ stream: ByteSpan, invert: Bool = false) throws -> MzxDecoded {
        let size = try declaredSize(stream)
        let payloadBytes = max(0, stream.count - headerSize)
        guard size <= payloadBytes * 128 else {
            throw TsukiError.format("MZX0 declared size \(size) cannot come from a \(stream.count)-byte stream")
        }

        var buffer = [UInt8](repeating: 0, count: bufferSize(size))
        let stats = try decode(stream, into: &buffer, invert: invert)
        return MzxDecoded(buffer: buffer, length: size, stats: stats)
    }

    /// Decodes into `output`, which must hold `bufferSize(declaredSize)` bytes.
    public static func decode(_ stream: ByteSpan, into output: inout [UInt8], invert: Bool = false) throws -> MzxStats {
        let size = try declaredSize(stream)
        guard output.count >= size + outputSlack else {
            throw TsukiError.bounds("output buffer of \(output.count) bytes is smaller than the declared size \(size) plus \(outputSlack) bytes of slack")
        }

        let stats: MzxStats = try stream.withUnsafeBytes { source in
            try output.withUnsafeMutableBytes { destination in
                try decodeCore(source, destination, size: size)
            }
        }

        if invert {
            for i in 0..<size { output[i] = ~output[i] }
        }
        return stats
    }

    private static func decodeCore(
        _ source: UnsafeRawBufferPointer,
        _ destination: UnsafeMutableRawBufferPointer,
        size: Int
    ) throws -> MzxStats {
        var sp = headerSize
        var dp = 0
        var last: UInt16 = 0
        var counter = 0
        var ringPosition = 0
        var commands = 0
        var ring = [UInt16](repeating: 0, count: 64)

        func readWord(at offset: Int) -> UInt16 {
            UInt16(littleEndian: destination.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
        }

        func writeWord(_ value: UInt16, at offset: Int) {
            destination.storeBytes(of: value.littleEndian, toByteOffset: offset, as: UInt16.self)
        }

        while dp < size {
            if counter <= 0 {
                counter = resetWords
                last = 0
            }
            guard sp < source.count else {
                throw TsukiError.format("MZX0 input exhausted at output \(dp)/\(size)")
            }

            let command = source[sp]
            sp += 1
            let count = Int(command >> 2) + 1
            commands += 1

            switch command & 3 {
            case 0: // run: repeat the last word
                counter -= count
                if last == 0 {
                    for i in 0..<count { writeWord(0, at: dp + i * 2) }
                } else {
                    for i in 0..<count { writeWord(last, at: dp + i * 2) }
                }
                dp += count * 2

            case 1: // back-reference: count words from 2 * (distance + 1) bytes back
                counter -= count
                guard sp < source.count else {
                    throw TsukiError.format("MZX0: backref distance byte missing")
                }
                let distance = (Int(source[sp]) + 1) * 2
                sp += 1
                guard dp >= distance else {
                    throw TsukiError.format("MZX0 backref before start of output (op=\(dp), dist=\(distance))")
                }
                for i in 0..<count {
                    writeWord(readWord(at: dp - distance + i * 2), at: dp + i * 2)
                }
                dp += count * 2
                last = readWord(at: dp - 2)

            case 2: // ring-buffer: exactly one word
                counter -= 1
                last = ring[Int(command >> 2)]
                writeWord(last, at: dp)
                dp += 2

            default: // literal: count words from the stream, also entering the ring
                counter -= count
                let length = count * 2
                guard sp + length <= source.count else {
                    throw TsukiError.format("MZX0: literal runs past end of input")
                }
                destination.baseAddress!.advanced(by: dp)
                    .copyMemory(from: source.baseAddress!.advanced(by: sp), byteCount: length)
                for i in 0..<count {
                    ring[(ringPosition + i) & 63] = readWord(at: dp + i * 2)
                }
                ringPosition = (ringPosition + count) & 63
                sp += length
                dp += length
                last = readWord(at: dp - 2)
            }
        }

        return MzxStats(consumed: sp, commands: commands, overshoot: max(0, dp - size))
    }
}
