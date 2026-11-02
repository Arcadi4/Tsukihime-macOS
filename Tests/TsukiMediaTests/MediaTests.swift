import Foundation
import TsukiCore
import TsukiEngine
@testable import TsukiMedia
import XCTest

final class MediaTests: XCTestCase {
    // MARK: - HeVag Tests

    func testHeVagHeaderParsing() throws {
        var bytes = [UInt8](repeating: 0, count: 0x30 + 32)
        // Magic "VAGp"
        bytes[0] = 0x56; bytes[1] = 0x41; bytes[2] = 0x47; bytes[3] = 0x70
        // Version 0x00020001
        bytes[4] = 0; bytes[5] = 2; bytes[6] = 0; bytes[7] = 1
        // DataSize 32 (2 frames)
        bytes[12] = 0; bytes[13] = 0; bytes[14] = 0; bytes[15] = 32
        // Rate 48000
        bytes[16] = 0; bytes[17] = 0; bytes[18] = 0xBB; bytes[19] = 0x80
        // Channels 1
        bytes[0x1E] = 1
        // Name "test_vag"
        let name = "test_vag"
        for (i, b) in name.utf8.enumerated() {
            bytes[0x20 + i] = b
        }

        let span = ByteSpan(bytes)
        let header = try HeVag.parseHeader(span)
        XCTAssertEqual(0x00020001, header.version)
        XCTAssertEqual(32, header.dataSize)
        XCTAssertEqual(48_000, header.sampleRate)
        XCTAssertEqual(1, header.channelsByte)
        XCTAssertEqual("test_vag", header.name)
        XCTAssertEqual(2, header.frames)
    }

    func testHeVagPredictorCoefficients() {
        XCTAssertEqual(128, HeVag.rows)
        XCTAssertEqual(512, HeVag.k.count)
        XCTAssertEqual(512, HeVag.c.count)
        XCTAssertEqual(7680, HeVag.coefficient8192(row: 1, tap: 0))
        XCTAssertEqual(-6656, HeVag.coefficient8192(row: 2, tap: 1))
    }

    // MARK: - RiffAtrac9 Tests

    func testRiffAtrac9HeaderParsing() throws {
        var w = ByteWriter(reserving: 256)
        // RIFF header
        w.raw([0x52, 0x49, 0x46, 0x46]) // "RIFF"
        w.u32(0) // placeholder for riff size
        w.raw([0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // "fmt " chunk (0x34 bytes = 52 bytes)
        w.raw([0x66, 0x6D, 0x74, 0x20])
        w.u32(52)
        w.u16(0xFFFE) // format tag
        w.u16(2)      // channels = 2
        w.u32(48000)  // sample rate = 48000
        w.u32(48000 * 4) // avg bytes per sec
        w.u16(512)    // block align = 512
        w.u16(16)     // bits per sample
        w.u16(34)     // cbSize = 34
        w.u16(1024)   // wSamplesPerBlock = 1024
        w.u32(3)      // dwChannelMask
        w.raw(RiffAtrac9.atrac9Guid) // 16 bytes GUID
        // 12 bytes extradata: version info (4), config word (4), reserved (4)
        w.u32(1)
        // config word: sync 0xFE, rate index 7 (48000), channel index 1 (2 ch), frameLog2 8 (256 samples), frameBytes 128, superframe 4 frames
        // (0xFE << 24) | (7 << 20) | (1 << 17) | (0 << 16) | ((128 - 1) << 5) | (2 << 3)
        let configWord: UInt32 = (0xFE << 24) | (7 << 20) | (1 << 17) | (127 << 5) | (2 << 3)
        w.u32be(configWord)
        w.u32(0)

        // "fact" chunk (12 bytes)
        w.raw([0x66, 0x61, 0x63, 0x74])
        w.u32(12)
        w.u32(2048) // fact[0] = playable frames
        w.u32(256)  // fact[1]
        w.u32(256)  // fact[2] = delay

        // "smpl" chunk (60 bytes)
        w.raw([0x73, 0x6D, 0x70, 0x6C])
        w.u32(36 + 24)
        for _ in 0..<7 { w.u32(0) }
        w.u32(1) // 1 loop
        w.u32(0) // sampler data
        // loop record
        w.u32(0); w.u32(0)
        w.u32(256); w.u32(2303) // loop start 256, loop end 2303
        w.u32(0); w.u32(0)

        // "data" chunk (3 superframes * 512 bytes = 1536 bytes)
        w.raw([0x64, 0x61, 0x74, 0x61])
        w.u32(1536)
        w.raw([UInt8](repeating: 0, count: 1536))

        var fileBytes = w.bytes
        let riffDataSize = UInt32(fileBytes.count - 8)
        fileBytes[4] = UInt8(riffDataSize & 0xFF)
        fileBytes[5] = UInt8((riffDataSize >> 8) & 0xFF)
        fileBytes[6] = UInt8((riffDataSize >> 16) & 0xFF)
        fileBytes[7] = UInt8((riffDataSize >> 24) & 0xFF)

        let span = ByteSpan(fileBytes)
        let riff = try RiffAtrac9.parse(span)

        XCTAssertEqual(2, riff.channels)
        XCTAssertEqual(48_000, riff.sampleRate)
        XCTAssertEqual(512, riff.blockAlign)
        XCTAssertEqual(1024, riff.samplesPerBlock)
        XCTAssertEqual(3, riff.superframes)
        XCTAssertEqual(3072, riff.decodedFrames)
        XCTAssertEqual(2048, riff.playableFrames)
        XCTAssertEqual(256, riff.delay)
        XCTAssertEqual(0, riff.playableLoop?.start)
        XCTAssertEqual(2047, riff.playableLoop?.end)
    }

    // MARK: - AudioMixer Tests

    func testAudioMixerPlaysClipAtGain() {
        let mixer = AudioMixer()
        var samples = [Float](repeating: 0, count: 200 * 2)
        for i in 0..<200 {
            samples[2 * i] = Float(i) / 1000.0
            samples[2 * i + 1] = -Float(i) / 1000.0
        }
        let clip = AudioClip(bank: .se, index: 1, channels: 2, sampleRate: 48000, samples: samples, loop: nil)

        mixer.post(MixerCommand.play(voice: 6, clip: clip, loop: false, gain: 0.5, pan: 0.0))
        XCTAssertEqual(1, mixer.commandsPosted)

        var rendered = [Float](repeating: 0, count: 100 * 2)
        mixer.render(&rendered)

        XCTAssertTrue(mixer.commandsApplied >= 1)
        XCTAssertEqual(100, mixer.framesRendered)
        XCTAssertTrue(mixer.isPlaying(6))

        for i in 0..<100 {
            let expectedL = 0.5 * (Float(i) / 1000.0)
            let expectedR = 0.5 * (-Float(i) / 1000.0)
            XCTAssertEqual(expectedL, rendered[2 * i], accuracy: 1e-5)
            XCTAssertEqual(expectedR, rendered[2 * i + 1], accuracy: 1e-5)
        }
    }

    func testAudioMixerPanLaw() {
        var gl: Float = 0
        var gr: Float = 0

        // Pan center (0.0): gl = 1.0, gr = 1.0
        Voice.panLaw(g: 1.0, p: 0.0, gl: &gl, gr: &gr)
        XCTAssertEqual(1.0, gl, accuracy: 1e-5)
        XCTAssertEqual(1.0, gr, accuracy: 1e-5)

        // Hard left (-1.0): gl = 1.0, gr = 0.0
        Voice.panLaw(g: 1.0, p: -1.0, gl: &gl, gr: &gr)
        XCTAssertEqual(1.0, gl, accuracy: 1e-5)
        XCTAssertEqual(0.0, gr, accuracy: 1e-5)

        // Hard right (1.0): gl = 0.0, gr = 1.0
        Voice.panLaw(g: 1.0, p: 1.0, gl: &gl, gr: &gr)
        XCTAssertEqual(0.0, gl, accuracy: 1e-5)
        XCTAssertEqual(1.0, gr, accuracy: 1e-5)
    }

    func testAudioMixerStopAndStopAll() {
        let mixer = AudioMixer()
        let clip = AudioClip(bank: .bgm, index: 1, channels: 2, sampleRate: 48000, samples: [Float](repeating: 1.0, count: 48000 * 2), loop: nil)

        mixer.post(MixerCommand.play(voice: 0, clip: clip, loop: true, gain: 1.0, pan: 0.0))
        var buf = [Float](repeating: 0, count: 64 * 2)
        mixer.render(&buf)
        XCTAssertTrue(mixer.isPlaying(0))

        mixer.post(MixerCommand.stopAll())
        mixer.render(&buf)
        XCTAssertFalse(mixer.isPlaying(0))
    }

    // MARK: - FrameSelector Tests

    func testFrameSelector30fpsCadenceLock() {
        let selector = FrameSelector(cadenceLockSeconds: 0.004)
        let frameRate: Double = 30.0
        let frameDuration = 1.0 / frameRate // 0.03333333333333333

        var stamps: [FrameStamp] = []
        for i in 0..<10 {
            stamps.append(FrameStamp(index: Int64(i), pts: Double(i) * frameDuration))
        }

        var ready = stamps
        var ticks = 0
        let tickDuration = 1.0 / 60.0

        for t in 0..<20 {
            let clock = Double(t) * tickDuration
            let consumed = selector.tick(clock: clock, ready: ready)
            if consumed > 0 {
                ready.removeFirst(consumed)
            }
            ticks += 1
        }

        XCTAssertEqual(20, ticks)
        XCTAssertNotNil(selector.current)
        // With cadence lock, 30fps frames on 60fps tick should have held or cleanly stepped
        XCTAssertTrue(selector.holds > 0 || selector.ticksShown == 2)
    }

    // MARK: - AudioClock Tests

    func testAudioClockExtrapolationAndClamping() {
        let clock = AudioClock(timestampFrequency: 1_000_000, sampleRate: 48_000, latencySeconds: 0.010, basePts: 0.0)

        // Before first callback, clockAt returns NaN
        XCTAssertTrue(clock.clockAt(100_000).isNaN)

        // First callback: 480 frames handed to device at t = 1_000_000
        clock.onCallback(mediaFrames: 480, requestedFrames: 480, timestamp: 1_000_000, endOfStream: false)

        // At t = 1_000_000, clock = 0 + (480 / 48000) - 0.010 + 0 = 0.0
        let c0 = clock.clockAt(1_000_000)
        XCTAssertEqual(0.0, c0, accuracy: 1e-5)

        // At t = 1_005_000 (5 ms later), elapsed = 0.005 s
        let c1 = clock.clockAt(1_005_000)
        XCTAssertEqual(0.005, c1, accuracy: 1e-5)

        // Clamping: max elapsed is 480 / 48000 = 0.010 s, even at t = 1_050_000
        let c2 = clock.clockAt(1_050_000)
        XCTAssertEqual(0.010, c2, accuracy: 1e-5)
    }

    // MARK: - PcmRing Tests

    func testPcmRingWriteAndRead() {
        let ring = PcmRing(capacityFrames: 1024)
        XCTAssertEqual(1024, ring.freeFrames)
        XCTAssertEqual(0, ring.bufferedFrames)

        var writeData = [Float](repeating: 0, count: 512 * 2)
        for i in 0..<writeData.count {
            writeData[i] = Float(i) * 0.1
        }

        let written = ring.write(writeData)
        XCTAssertEqual(512, written)
        XCTAssertEqual(512, ring.bufferedFrames)
        XCTAssertEqual(512, ring.freeFrames)

        var readData = [Float](repeating: 0, count: 512 * 2)
        readData.withUnsafeMutableBufferPointer { buf in
            let readCount = ring.read(buf)
            XCTAssertEqual(512, readCount)
        }

        XCTAssertEqual(0, ring.bufferedFrames)
        XCTAssertEqual(1024, ring.freeFrames)

        for i in 0..<writeData.count {
            XCTAssertEqual(writeData[i], readData[i], accuracy: 1e-5)
        }
    }

    // MARK: - ClipCache Tests

    func testClipCacheHitsAndMisses() throws {
        var decodes = 0
        let cache = ClipCache(decode: { bank, entry in
            decodes += 1
            return AudioClip(bank: bank, index: entry, channels: 2, sampleRate: 48000, samples: [Float](repeating: 0.1, count: 100), loop: nil)
        }, budgetBytes: 1024 * 1024)

        let clip1 = try cache.get(bank: .se, entry: 1)
        XCTAssertEqual(1, decodes)
        XCTAssertEqual(1, clip1.index)

        let clip2 = try cache.get(bank: .se, entry: 1)
        XCTAssertEqual(1, decodes) // Hit!
        XCTAssertEqual(1, cache.hits)
        XCTAssertEqual(1, clip2.index)

        _ = try cache.get(bank: .se, entry: 2)
        XCTAssertEqual(2, decodes)
    }

    // MARK: - AudioCommandPlayer Tests

    func testAudioCommandPlayerPerformsPlayAndSetVolume() {
        let mixer = AudioMixer()
        var samples = [Float](repeating: 0, count: 500 * 2)
        for i in 0..<500 {
            samples[2 * i] = Float(i) / 1000.0
            samples[2 * i + 1] = -Float(i) / 1000.0
        }
        let clip = AudioClip(bank: .se, index: 1, channels: 2, sampleRate: 48000, samples: samples, loop: nil)

        let player = AudioCommandPlayer(clips: { _, _ in clip }, mixer: mixer)
        player.perform([
            AudioCommand.openHandle(6, .se),
            AudioCommand.setVolume0(6, 0.5),
            AudioCommand.play(6, .se, 1, loop: false, volume: 0.5)
        ])

        XCTAssertTrue(player.isPlaying(6))
        XCTAssertTrue(mixer.commandsPosted >= 1)

        var rendered = [Float](repeating: 0, count: 200 * 2)
        mixer.render(&rendered)

        for i in 0..<200 {
            XCTAssertEqual(0.5 * (Float(i) / 1000.0), rendered[2 * i], accuracy: 1e-5)
            XCTAssertEqual(0.5 * (-Float(i) / 1000.0), rendered[2 * i + 1], accuracy: 1e-5)
        }
    }
}
