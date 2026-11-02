import Foundation
import TsukiCore

/// The parsed header of an ATRAC9 RIFF/WAVE stream (audio.md 2.1-2.3).
public final class RiffAtrac9: Sendable {
    // {47E142D2-36BA-4D8D-88FC-61654F8C836C}, as stored (audio.md 2.1, fmt + 0x18)
    public static let atrac9Guid: [UInt8] = [
        0xD2, 0x42, 0xE1, 0x47, 0xBA, 0x36, 0x8D, 0x4D, 0x88, 0xFC, 0x61, 0x65, 0x4F, 0x8C, 0x83, 0x6C
    ]

    public static let sampleRates: [Int] = [
        11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000,
        44100, 48000, 64000, 88200, 96000, 128000, 176400, 192000
    ]

    public static let frameLog2: [Int] = [
        6, 6, 7, 7, 7, 8, 8, 8, 6, 6, 7, 7, 7, 8, 8, 8
    ]

    public static let configChannels: [Int] = [
        1, 2, 2, 6, 8, 4, 0, 0
    ]

    /// RIFF size field + 8: the whole stream in bytes.
    public let riffSize: Int
    /// Channel count (fmt).
    public let channels: Int
    /// Sample rate (fmt).
    public let sampleRate: Int
    /// Bytes per superframe (fmt block align).
    public let blockAlign: Int
    /// Samples per superframe (fmt wSamplesPerBlock, 1024).
    public let samplesPerBlock: Int
    /// The 12 bytes at fmt + 0x28 (dwVersionInfo, config word, reserved).
    public let extradata: [UInt8]
    /// The ATRAC9 config word, big-endian at fmt + 0x2C (audio.md 2.2).
    public let configWord: UInt32
    /// The fact chunk: (samples, 256, encoder delay 256).
    public let fact: [Int]
    /// The smpl loop records as stored (encoder delay included, end inclusive).
    public let smplLoops: [(start: Int, end: Int)]
    /// Offset of the data chunk's bytes in the stream.
    public let dataOffset: Int
    /// Size of the data chunk.
    public let dataSize: Int

    public init(
        riffSize: Int,
        channels: Int,
        sampleRate: Int,
        blockAlign: Int,
        samplesPerBlock: Int,
        extradata: [UInt8],
        configWord: UInt32,
        fact: [Int],
        smplLoops: [(start: Int, end: Int)],
        dataOffset: Int,
        dataSize: Int
    ) {
        self.riffSize = riffSize
        self.channels = channels
        self.sampleRate = sampleRate
        self.blockAlign = blockAlign
        self.samplesPerBlock = samplesPerBlock
        self.extradata = extradata
        self.configWord = configWord
        self.fact = fact
        self.smplLoops = smplLoops
        self.dataOffset = dataOffset
        self.dataSize = dataSize
    }

    /// Samples per ATRAC9 frame (config word).
    public var samplesPerFrame: Int {
        1 << Self.frameLog2[Int(configWord >> 20) & 0xF]
    }

    /// Frames per superframe (config word).
    public var framesPerSuperframe: Int {
        1 << Int((configWord >> 3) & 3)
    }

    /// Bytes per ATRAC9 frame (config word, stored minus 1).
    public var frameBytes: Int {
        Int((configWord >> 5) & 0x7FF) + 1
    }

    /// Playable sample frames: fact[0].
    public var playableFrames: Int {
        fact.isEmpty ? 0 : fact[0]
    }

    /// The encoder delay the engine subtracts: fact[2] (VA 0x113256).
    public var delay: Int {
        fact.count >= 3 ? fact[2] : 0
    }

    /// Superframes in the data chunk.
    public var superframes: Int {
        blockAlign > 0 ? dataSize / blockAlign : 0
    }

    /// Frames a decoder outputs from every superframe, delay included.
    public var decodedFrames: Int {
        superframes * samplesPerBlock
    }

    /// The loop in playable frames, end inclusive: [smpl.start - delay, smpl.end - delay]; nil without a smpl loop or start == end.
    public var playableLoop: (start: Int, end: Int)? {
        guard let first = smplLoops.first, first.start != first.end else {
            return nil
        }
        return (first.start - delay, first.end - delay)
    }

    /// Parses the header (the bytes up to the data chunk header must be present, and the data chunk itself).
    public static func parse(_ b: ByteSpan) throws -> RiffAtrac9 {
        guard b.count >= 12 else {
            throw TsukiError.format("not a RIFF/WAVE stream: size \(b.count) < 12")
        }

        // Check "RIFF"
        guard b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 else {
            throw TsukiError.format("not a RIFF stream")
        }
        // Check "WAVE" at offset 8
        guard b[8] == 0x57 && b[9] == 0x41 && b[10] == 0x56 && b[11] == 0x45 else {
            throw TsukiError.format("not a WAVE stream")
        }

        let declaredSize = Int(b.u32(4)) + 8
        guard declaredSize >= 12 && declaredSize <= b.count else {
            throw TsukiError.format("RIFF size \(declaredSize) is outside the stream (\(b.count) bytes)")
        }

        let riffSize = declaredSize
        var o = 12
        var channels = 0
        var rate = 0
        var align = 0
        var spb = 0
        var config: UInt32 = 0
        var extradata: [UInt8]?
        var fact: [Int] = []
        var loops: [(start: Int, end: Int)] = []
        var dataOff = -1
        var dataSize = -1

        while o <= riffSize - 8 {
            let id0 = b[o]
            let id1 = b[o + 1]
            let id2 = b[o + 2]
            let id3 = b[o + 3]
            let chunkSize = Int(b.u32(o + 4))

            guard chunkSize <= riffSize - o - 8 else {
                throw TsukiError.format("RIFF chunk size \(chunkSize) is outside the stream")
            }

            let body = b.slice(o + 8, chunkSize)

            if id0 == 0x66 && id1 == 0x6D && id2 == 0x74 && id3 == 0x20 { // "fmt "
                guard body.count >= 0x34 else {
                    throw TsukiError.format("fmt chunk of \(chunkSize) bytes is too short for ATRAC9")
                }

                let tag = body.u16(0)
                guard tag == 0xFFFE else {
                    throw TsukiError.format("not ATRAC9 (format tag 0x\(String(tag, radix: 16, uppercase: true)))")
                }

                // Check GUID at offset 24 (16 bytes)
                for i in 0..<16 {
                    if body[24 + i] != atrac9Guid[i] {
                        throw TsukiError.format("not ATRAC9 GUID")
                    }
                }

                channels = Int(body.u16(2))
                rate = Int(body.u32(4))
                align = Int(body.u16(12))
                spb = Int(body.u16(18))
                extradata = body.slice(40, 12).toArray()
                config = body.u32be(44)
            } else if id0 == 0x66 && id1 == 0x61 && id2 == 0x63 && id3 == 0x74 { // "fact"
                guard chunkSize % 4 == 0 else {
                    throw TsukiError.format("fact chunk is not whole sample counts")
                }
                let count = chunkSize / 4
                fact = (0..<count).map { Int(body.u32($0 * 4)) }
            } else if id0 == 0x73 && id1 == 0x6D && id2 == 0x70 && id3 == 0x6C { // "smpl"
                guard chunkSize >= 36 else {
                    throw TsukiError.format("smpl chunk is shorter than its header")
                }
                let n = Int(body.u32(28))
                guard n <= (chunkSize - 36) / 24 else {
                    throw TsukiError.format("smpl loop count exceeds chunk size")
                }
                for k in 0..<n {
                    let r = body.suffix(from: 36 + (24 * k))
                    loops.append((start: Int(r.u32(8)), end: Int(r.u32(12))))
                }
            } else if id0 == 0x64 && id1 == 0x61 && id2 == 0x74 && id3 == 0x61 { // "data"
                dataOff = o + 8
                dataSize = chunkSize
                break
            }

            let next = o + 8 + chunkSize + (chunkSize & 1)
            guard next <= riffSize else {
                throw TsukiError.format("RIFF chunk padding is outside the stream")
            }
            o = next
        }

        guard let extra = extradata, dataOff >= 0, !fact.isEmpty else {
            throw TsukiError.format("fmt, fact or data chunk missing")
        }

        let h = RiffAtrac9(
            riffSize: riffSize,
            channels: channels,
            sampleRate: rate,
            blockAlign: align,
            samplesPerBlock: spb,
            extradata: extra,
            configWord: config,
            fact: fact,
            smplLoops: loops,
            dataOffset: dataOff,
            dataSize: dataSize
        )

        // Strict checks
        var problems: [String] = []
        if (config >> 24) != 0xFE {
            problems.append("config sync byte != 0xFE")
        }
        if ((config >> 16) & 1) != 0 {
            problems.append("config validation bit set")
        }
        let channelIndex = Int((config >> 17) & 7)
        if configChannels[channelIndex] != channels || (channels != 1 && channels != 2) {
            problems.append("config channel count != fmt channels (\(channels))")
        }
        let rateIndex = Int((config >> 20) & 0xF)
        if sampleRates[rateIndex] != rate {
            problems.append("config rate != fmt rate")
        }
        if align <= 0 || h.frameBytes * h.framesPerSuperframe != align {
            problems.append("superframe bytes != block align")
        }
        if h.samplesPerFrame * h.framesPerSuperframe != spb {
            problems.append("superframe samples != wSamplesPerBlock")
        }
        if align > 0 && (dataSize % align != 0 || dataOff + dataSize > b.count) {
            problems.append("data size is not whole superframes inside the stream")
        }

        let decoded = align > 0 ? (dataSize / align) * spb : 0
        if fact[0] < 0 || fact[0] > decoded || (fact.count >= 3 && (fact[2] < 0 || fact[2] + fact[0] > decoded)) {
            problems.append("fact range runs past the decoded samples")
        }

        if !problems.isEmpty {
            throw TsukiError.format(problems.joined(separator: "; "))
        }

        return h
    }
}
