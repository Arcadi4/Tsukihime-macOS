import Foundation
import TsukiCore
import TsukiEngine

/// Decodes bank entries to the engine's AudioClip (thread-safe: one decoder context per call).
public final class MediaAudioDecoder: AudioDecoder {
    public init() {}

    /// ATRAC9: the playable range decoded[delay * channels ..< (delay + playableFrames) * channels] and the loop
    /// [smpl.start - delay, smpl.end - delay], nil when start == end. HE-VAG: the samples before the end marker / 32768,
    /// mono, with the PS-ADPCM flag loop (none in retail data).
    public func decode(bank: AudioBank, index: Int, payload: ByteSpan) throws -> AudioClip {
        if bank == .vag {
            let h = try HeVag.parseHeader(payload)
            let vloop = try HeVag.loop(payload).map { AudioLoop(start: $0.start, end: $0.end) }
            let samples = try HeVag.decodeFloat(payload)
            return AudioClip(bank: bank, index: index, channels: 1, sampleRate: h.sampleRate, samples: samples, loop: vloop)
        }

        let riff = try RiffAtrac9.parse(payload)
        let decoded = try Atrac9Decoder.decodeAll(riff, stream: payload)
        return Self.toClip(bank: bank, index: index, riff: riff, decoded: decoded)
    }

    /// The playable clip of a full ATRAC9 decode.
    public static func toClip(bank: AudioBank, index: Int, riff: RiffAtrac9, decoded: [Float]) -> AudioClip {
        let start = riff.delay * riff.channels
        let count = riff.playableFrames * riff.channels
        let playable = Array(decoded[start..<(start + count)])
        let loop = riff.playableLoop.map { AudioLoop(start: $0.start, end: $0.end) }
        return AudioClip(bank: bank, index: index, channels: riff.channels, sampleRate: riff.sampleRate, samples: playable, loop: loop)
    }
}
