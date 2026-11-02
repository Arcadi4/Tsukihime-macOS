import Foundation
import TsukiCore

/// The 48-byte big-endian "VAGp" header (audio.md 6.1).
public struct VagHeader: Sendable, Equatable {
    /// Header size.
    public static let size = 0x30

    /// 0x00020001 in every entry.
    public let version: UInt32
    /// Bytes of ADPCM frames after the header (a multiple of 16).
    public let dataSize: Int
    /// 48,000.
    public let sampleRate: Int
    /// Byte 0x1E: 1, except 2 for entry 0 ("dummy").
    public let channelsByte: UInt8
    /// The NUL-padded ASCII name at 0x20, e.g. moon_se00001_L.
    public let name: String

    public init(version: UInt32, dataSize: Int, sampleRate: Int, channelsByte: UInt8, name: String) {
        self.version = version
        self.dataSize = dataSize
        self.sampleRate = sampleRate
        self.channelsByte = channelsByte
        self.name = name
    }

    /// Number of 16-byte frames.
    public var frames: Int {
        dataSize / HeVag.frameBytes
    }
}

/// The HE-VAG decoder (audio.md 6.2): 16-byte frames of 28 mono samples, a 4-tap predictor from 128 rows.
public enum HeVag {
    /// Bytes per frame.
    public static let frameBytes = 16

    /// Samples per frame.
    public static let frameSamples = 28

    // 128 x 4 predictor coefficients in units of 1/8192 (audio.md 6.2 table K; vgmstream hevag_coefs_f * 8192).
    public static let k: [Int16] = [
        0, 0, 0, 0, 7680, 0, 0, 0, 14720, -6656, 0, 0, 12544, -7040, 0, 0,
        15616, -7680, 0, 0, 14731, -7059, 0, 0, 14507, -7366, 0, 0, 13920, -7522, 0, 0,
        13133, -7680, 0, 0, 12028, -7680, 0, 0, 10764, -7680, 0, 0, 9359, -7680, 0, 0,
        7832, -7680, 0, 0, 6201, -7680, 0, 0, 4488, -7680, 0, 0, 2717, -7680, 0, 0,
        910, -7680, 0, 0, -910, -7680, 0, 0, -2717, -7680, 0, 0, -4488, -7680, 0, 0,
        -6201, -7680, 0, 0, -7832, -7680, 0, 0, -9359, -7680, 0, 0, -10764, -7680, 0, 0,
        -12028, -7680, 0, 0, -13133, -7680, 0, 0, -13920, -7522, 0, 0, -14507, -7366, 0, 0,
        -14731, -7059, 0, 0, 5376, -9216, 3328, -3072, -6400, -7168, -3328, -2304, -10496, -7424, -3584, -1024,
        -167, -2722, -494, -541, -7430, -2221, -2298, 424, -8001, -3166, -2814, 289, 6018, -4750, 2649, -1298,
        3798, -6946, 3875, -1216, -8237, -2596, -2071, 227, 9199, 1982, -1382, -2316, 13021, -3044, -3792, 1267,
        13112, -4487, -2250, 1665, -1668, -3744, -6456, 840, 7819, -4328, 2111, -506, 9571, -1336, -757, 487,
        10032, -2562, 300, 199, -4745, -4122, -5486, -1493, -5896, 2378, -4787, -6947, -1193, -9117, -1237, -3114,
        2783, -7108, -1575, -1447, -7334, -2062, -2212, 446, 6127, -2577, -315, -18, 9457, -1858, 102, 258,
        7876, -4483, 2126, -538, -7172, -1795, -2069, 482, -7358, -2102, -2233, 440, -9170, -3509, -2674, -391,
        -2638, -2647, -1929, -1637, 1873, 9183, 1860, -5746, 9214, 1859, -1124, -2427, 13204, -3012, -4139, 1370,
        12437, -4792, -256, 622, -2653, -1144, -3182, -6878, 9331, -1048, -828, 507, 1642, -620, -946, -4229,
        4246, -7585, -533, -2259, -8988, -3891, -2807, 44, -2562, -2735, -1730, -1899, 3182, -483, -714, -1421,
        7937, -3844, 2821, -1019, 10069, -2609, 314, 195, 8400, -3297, 1551, -155, -8529, -2775, -2432, -336,
        9477, -1882, 108, 256, 75, -2241, -298, -6937, -9143, -4160, -2963, 5, -7270, -1958, -2156, 460,
        -2740, 3745, 5936, -1089, 8993, 1948, -683, -2704, 13101, -2835, -3854, 1055, 9543, -1961, 130, 250,
        5272, -4270, 3124, -3157, -7696, -3383, -2907, -456, 7309, 2523, 434, -2461, 10275, -2867, 391, 172,
        10940, -3721, 665, 97, 24, -310, -1262, 320, -8122, -2411, -2311, -271, -8511, -3067, -2337, 163,
        326, -3846, 419, -933, 8895, 2194, -541, -2880, 12073, -1876, -2017, -601, 8729, -3423, 1674, -169,
        12950, -3847, -3007, 1946, 10038, -2570, 302, 198, 9385, -2757, 1008, 41, -4720, -5006, -2852, -1161,
        7869, -4326, 2135, -501, 2450, -8597, 1299, -2780, 10192, -2763, 360, 181, 11313, -4213, 833, 53,
        10154, -2716, 345, 185, 9638, -1417, -737, 482, 3854, -4554, 2843, -3397, 6699, -5659, 2249, -1074,
        11082, -3908, 728, 80, -1026, -9810, -805, -3462, 10396, -3746, 1367, -96, 10287, 988, -1915, -1437,
        7953, 3878, -764, -3263, 12689, -3375, -3354, 2079, 6641, 3166, 231, -2089, -2348, -7354, -1944, -4122,
        9290, -4039, 1885, -246, 4633, -6403, 1748, -1619, 11247, -4125, 802, 61, 9807, -2284, 219, 222,
        9736, -1536, -706, 473, 8440, -3436, 1562, -176, 9307, -1021, -835, 509, 1698, -9025, 688, -3037,
        10214, -2791, 368, 179, 8390, 3248, -758, -2989, 7201, 3316, 46, -2614, -88, -7809, -538, -4571,
        6193, -5189, 2760, -1245, 12325, -1290, -3284, 253, 13064, -4075, -2824, 1877, 5333, 2999, 775, -1132
    ]

    // C[i] = K[i] / 8192 as Float.
    public static let c: [Float] = k.map { Float($0) / 8192.0 }

    /// Number of predictor rows (128).
    public static var rows: Int { k.count / 4 }

    /// Coefficient tap of row in units of 1/8192.
    public static func coefficient8192(row: Int, tap: Int) -> Int {
        Int(k[(row * 4) + tap])
    }

    /// Parses the header; unless headerOnly the frames must follow it in data.
    public static func parseHeader(_ data: ByteSpan, headerOnly: Bool = false) throws -> VagHeader {
        guard data.count >= VagHeader.size else {
            throw TsukiError.format("not a VAGp stream: size \(data.count) < \(VagHeader.size)")
        }

        guard data[0] == 0x56 && data[1] == 0x41 && data[2] == 0x47 && data[3] == 0x70 else {
            throw TsukiError.format("not a VAGp stream: magic mismatch")
        }

        let version = data.u32be(4)
        let size = Int(data.u32be(12))
        let rate = Int(data.u32be(16))

        guard size % frameBytes == 0 else {
            throw TsukiError.format("VAG data size \(size) is not a multiple of \(frameBytes)")
        }

        if !headerOnly && VagHeader.size + size > data.count {
            throw TsukiError.format("VAG data size \(size) runs past the buffer (\(data.count) bytes)")
        }

        let nameSpan = data.slice(0x20, 16)
        var nameBytes: [UInt8] = []
        for i in 0..<16 {
            let b = nameSpan[i]
            if b == 0 { break }
            nameBytes.append(b)
        }
        let name = String(decoding: nameBytes, as: UTF8.self)

        return VagHeader(version: version, dataSize: size, sampleRate: rate, channelsByte: data[0x1E], name: name)
    }

    /// Playable frames of a whole VAGp file: the frames before the first one whose flag is 7 or more (audio.md 6.2).
    public static func playableFrames(_ vag: ByteSpan) throws -> Int {
        let h = try parseHeader(vag)
        let body = vag.slice(VagHeader.size, h.dataSize)
        for f in 0..<h.frames {
            if (body[(f * frameBytes) + 1] & 0x0F) >= 7 {
                return f
            }
        }
        return h.frames
    }

    /// The loop of a whole VAGp file from the PS-ADPCM flags (bit 2 = loop start frame, bits 0 + 1 = loop end), in
    /// samples with the end inclusive, or nil.
    public static func loop(_ vag: ByteSpan) throws -> (start: Int, end: Int)? {
        let h = try parseHeader(vag)
        let body = vag.slice(VagHeader.size, h.dataSize)
        var start = -1
        var end = -1
        for f in 0..<h.frames {
            let fl = body[(f * frameBytes) + 1] & 0x0F
            if fl >= 7 { continue }
            if start < 0 && (fl & 4) != 0 {
                start = f
            }
            if end < 0 && (fl & 3) == 3 {
                end = f
            }
        }

        guard start >= 0, end >= 0, end >= start else { return nil }
        return (start * frameSamples, ((end + 1) * frameSamples) - 1)
    }

    /// Decodes frames of body (mono) to Int16 PCM in output (28 per frame). history (h1..h4, newest first) carries state.
    public static func decodeFrames(body: ByteSpan, frames: Int, output: inout [Int16], history: inout [Int32]) throws {
        guard body.count >= frames * frameBytes else {
            throw TsukiError.format("frame count exceeds data size")
        }
        guard output.count >= frames * frameSamples else {
            throw TsukiError.format("output buffer too small")
        }
        guard history.count >= 4 else {
            throw TsukiError.format("history requires at least 4 elements")
        }

        var h1 = history[0]
        var h2 = history[1]
        var h3 = history[2]
        var h4 = history[3]
        let coeff = c
        var o = 0

        body.withUnsafeBytes { raw in
            guard let ptr = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }

            for f in 0..<frames {
                let p = f * frameBytes
                let b0 = Int(ptr[p])
                let b1 = Int(ptr[p + 1])
                var idx = (b1 & 0xF0) | (b0 >> 4)
                if idx > 127 { idx = 0 }

                let shift = b0 & 0x0F
                let flag = b1 & 0x0F
                let c0 = coeff[idx * 4]
                let c1 = coeff[(idx * 4) + 1]
                let c2 = coeff[(idx * 4) + 2]
                let c3 = coeff[(idx * 4) + 3]

                for i in 0..<frameSamples {
                    var s: Int32
                    if flag < 7 {
                        let b = Int(ptr[p + 2 + (i >> 1)])
                        var nib = (i & 1) != 0 ? b >> 4 : b & 0x0F
                        if nib >= 8 {
                            nib -= 16
                        }

                        let code = Int32((nib << 12) >> shift)
                        var acc = (Float(h1) * c0) + (Float(h2) * c1)
                        acc += Float(h3) * c2
                        acc += Float(h4) * c3
                        s = code + Int32(acc) // truncation toward zero
                    } else {
                        s = 0
                    }

                    let clamped: Int16
                    if s < Int32(Int16.min) {
                        clamped = Int16.min
                    } else if s > Int32(Int16.max) {
                        clamped = Int16.max
                    } else {
                        clamped = Int16(s)
                    }

                    output[o] = clamped
                    o += 1

                    h4 = h3
                    h3 = h2
                    h2 = h1
                    h1 = s // unclamped in history
                }
            }
        }

        history[0] = h1
        history[1] = h2
        history[2] = h3
        history[3] = h4
    }

    /// Decodes a whole mono VAGp file to Int16 PCM up to its end marker.
    public static func decode(_ vag: ByteSpan) throws -> [Int16] {
        let h = try parseHeader(vag)
        let n = try playableFrames(vag)
        var pcm = [Int16](repeating: 0, count: n * frameSamples)
        var hist: [Int32] = [0, 0, 0, 0]
        let body = vag.slice(VagHeader.size, h.dataSize)
        try decodeFrames(body: body, frames: n, output: &pcm, history: &hist)
        return pcm
    }

    /// The float PCM the mixer plays: decode / 32768.
    public static func decodeFloat(_ vag: ByteSpan) throws -> [Float] {
        let pcm = try decode(vag)
        var f = [Float](repeating: 0, count: pcm.count)
        for i in 0..<pcm.count {
            f[i] = Float(pcm[i]) / 32768.0
        }
        return f
    }
}
