import Foundation
import TsukiCore
import TsukiEngine

/// The optional `LV` chunk in front of a voice entry's audio stream (docs/formats/containers.md 6).
public struct LvHeader: Equatable, Sendable {
    /// The engine clamps the copy of the payload to this many bytes (0x258).
    public static let engineCopyMax = 600

    /// Byte 0 is `L` (the only byte the engine tests).
    public let present: Bool
    /// The payload length n, the u16 at +2 (0 when absent).
    public let length: Int
    /// Where the audio stream starts: `4 + n`, or 0 when absent.
    public let bodyOffset: Int

    public init(present: Bool, length: Int, bodyOffset: Int) {
        self.present = present
        self.length = length
        self.bodyOffset = bodyOffset
    }

    /// Bytes the engine copies to its global LV buffer, header included (containers.md 6).
    public var engineCopyLength: Int {
        present ? 4 + min(length, Self.engineCopyMax) : 0
    }
}

/// A decoded voice entry (containers.md 6).
public struct LvDecoded {
    /// The LV chunk.
    public let header: LvHeader
    /// Backing array of the decoded audio (a raw body is copied exactly, and is exactly `length` long).
    public let buffer: [UInt8]
    /// Length of the decoded audio.
    public let length: Int
    /// True if the body started with `M` and was MZX0-decoded.
    public let compressed: Bool
    /// Entry bytes used: `bodyOffset + MZX bytes consumed` (the whole entry for a raw body). This
    /// defines the exact entry size that HED4 does not store (containers.md 3.1).
    public let consumed: Int
    /// The MZX0 statistics, nil for a raw body.
    public let mzx: MzxStats?

    public init(header: LvHeader, buffer: [UInt8], length: Int, compressed: Bool, consumed: Int, mzx: MzxStats?) {
        self.header = header
        self.buffer = buffer
        self.length = length
        self.compressed = compressed
        self.consumed = consumed
        self.mzx = mzx
    }

    /// The decoded audio: RIFF/WAVE ATRAC9 on retail data.
    public var data: ByteSpan {
        ByteSpan(buffer, offset: 0, count: length)
    }
}

/// The `LV` voice wrapper of voice.mrg / voice2.mrg entries (docs/formats/containers.md 6).
public enum Lv {
    /// Parses the LV chunk the way the engine does (VA 0x8BF8).
    ///
    /// Throws `TsukiError.format` when the chunk or its payload is cut off.
    public static func parse(_ entry: ByteSpan) throws -> LvHeader {
        guard entry.count >= 1, entry[0] == UInt8(ascii: "L") else {
            return LvHeader(present: false, length: 0, bodyOffset: 0)
        }

        guard entry.count >= 4 else {
            throw TsukiError.format("LV chunk shorter than its 4-byte header")
        }

        let n = Int(entry.u16(2))
        guard 4 + n <= entry.count else {
            throw TsukiError.format("LV payload length \(n) runs past the entry (\(entry.count) bytes)")
        }

        return LvHeader(present: true, length: n, bodyOffset: 4 + n)
    }

    /// Decodes one voice entry: the optional LV chunk, then an MZX0 stream if the next byte is `M`,
    /// otherwise the remaining bytes unchanged (engine behaviour). Pass the entry's whole sector span.
    public static func decompress(_ entry: ByteSpan) throws -> LvDecoded {
        let header = try parse(entry)
        let body = entry.suffix(from: header.bodyOffset)
        if body.count >= 1, body[0] == UInt8(ascii: "M") {
            let result = try Mzx.decompress(body)
            return LvDecoded(header: header, buffer: result.buffer, length: result.length, compressed: true,
                             consumed: header.bodyOffset + result.stats.consumed, mzx: result.stats)
        }

        let raw = body.toArray()
        return LvDecoded(header: header, buffer: raw, length: raw.count, compressed: false,
                         consumed: entry.count, mzx: nil)
    }
}
