import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import TsukiCore

/// Options of a MoviePipeline.
public struct MoviePipelineOptions: Sendable {
    /// The loop point of title backgrounds, 8.0333 s (f32 at eboot VA 0x2186E4).
    public static let titleLoopPointSeconds: Double = 8.0333

    public var startSeconds: Double
    public var frameBuffers: Int
    public var videoThreads: Int
    public var loop: Bool
    public var loopPointSeconds: Double
    public var pcmRingFrames: Int

    public init(
        startSeconds: Double = 0,
        frameBuffers: Int = 8,
        videoThreads: Int = 0,
        loop: Bool = false,
        loopPointSeconds: Double = MoviePipelineOptions.titleLoopPointSeconds,
        pcmRingFrames: Int = 4 * 48_000
    ) {
        self.startSeconds = startSeconds
        self.frameBuffers = frameBuffers
        self.videoThreads = videoThreads
        self.loop = loop
        self.loopPointSeconds = loopPointSeconds
        self.pcmRingFrames = pcmRingFrames
    }
}

/// Demuxes and decodes one movie into a FrameQueue and a PcmRing.
/// Uses native macOS AVFoundation / VideoToolbox for hardware-accelerated H.264 and AAC decoding into BGRA/Metal.
public final class MoviePipeline: @unchecked Sendable {
    private let path: String
    private let options: MoviePipelineOptions
    private let lock = NSLock()
    private var stopped = false
    private var disposed = false
    private var videoThread: Thread?
    private var audioThread: Thread?
    private var _discardAudio = false

    public let width: Int
    public let height: Int
    public let fps: Double
    public let nbFrames: Int64
    public let durationSeconds: Double
    public let hasAudio: Bool

    public let frames: FrameQueue
    public let pcm: PcmRing

    public private(set) var framesDecoded: Int64 = 0
    public private(set) var framesBeforeStart: Int64 = 0
    public private(set) var lastVideoIndex: Int64 = -1
    public private(set) var firstAudioSample: Int64 = -1
    public private(set) var audioSamplesDecoded: Int64 = 0
    public private(set) var audioSamplesOut: Int64 = 0
    public private(set) var packetErrors: Int64 = 0
    public private(set) var loops: Int64 = 0
    public private(set) var demuxEnded: Bool = false
    public var videoThreadCount: Int { options.videoThreads > 0 ? options.videoThreads : 4 }
    public private(set) var error: Error?

    public init(path: String, options: MoviePipelineOptions? = nil) throws {
        self.path = path
        let opts = options ?? MoviePipelineOptions()
        self.options = opts

        let fileUrl = URL(fileURLWithPath: (path as NSString).standardizingPath)
        guard FileManager.default.fileExists(atPath: fileUrl.path) else {
            throw TsukiError.format("movie file not found: \(fileUrl.path)")
        }

        let asset = AVURLAsset(url: fileUrl)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            throw TsukiError.format("no video track in movie: \(path)")
        }

        let size = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
        let w = Int(abs(size.width))
        let h = Int(abs(size.height))
        self.width = (w % 2 == 0) ? w : w + 1
        self.height = (h % 2 == 0) ? h : h + 1

        let frameRate = Double(videoTrack.nominalFrameRate)
        self.fps = frameRate > 0 ? frameRate : 30.0

        let dur = CMTimeGetSeconds(asset.duration)
        self.durationSeconds = dur.isFinite ? dur : 0.0

        let audioTrack = asset.tracks(withMediaType: .audio).first
        self.hasAudio = audioTrack != nil

        let totalFrames = Int64((self.durationSeconds * self.fps).rounded())
        self.nbFrames = totalFrames > 0 ? totalFrames : 0

        self.frames = FrameQueue(buffers: opts.frameBuffers, width: self.width, height: self.height)
        self.pcm = PcmRing(capacityFrames: opts.pcmRingFrames)

        if !hasAudio {
            pcm.complete()
        }
    }

    deinit {
        dispose()
    }

    public func discardAudio() {
        lock.lock()
        _discardAudio = true
        lock.unlock()
    }

    public func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !disposed, !stopped, videoThread == nil else { return }

        let vThread = Thread { [weak self] in
            self?.videoDecodeLoop()
        }
        vThread.name = "tsuki-movie-vdec"
        vThread.start()
        self.videoThread = vThread

        if hasAudio {
            let aThread = Thread { [weak self] in
                self?.audioDecodeLoop()
            }
            aThread.name = "tsuki-movie-adec"
            aThread.start()
            self.audioThread = aThread
        }
    }

    public func dispose() {
        lock.lock()
        if disposed {
            lock.unlock()
            return
        }
        disposed = true
        stopped = true
        lock.unlock()

        frames.close()
        pcm.complete()
    }

    private func videoDecodeLoop() {
        let fileUrl = URL(fileURLWithPath: (path as NSString).standardizingPath)
        var currentLoop = 0
        var frameIndex: Int64 = 0

        while !stopped {
            do {
                let asset = AVURLAsset(url: fileUrl)
                guard let videoTrack = asset.tracks(withMediaType: .video).first else { break }

                let reader = try AVAssetReader(asset: asset)
                let outputSettings: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: width,
                    kCVPixelBufferHeightKey as String: height
                ]
                let trackOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
                trackOutput.alwaysCopiesSampleData = false
                reader.add(trackOutput)

                if currentLoop > 0 && options.loop {
                    let loopSec = options.loopPointSeconds < durationSeconds ? max(0, options.loopPointSeconds) : 0
                    let startTime = CMTime(seconds: loopSec, preferredTimescale: 600)
                    reader.timeRange = CMTimeRange(start: startTime, duration: .positiveInfinity)
                } else if options.startSeconds > 0 {
                    let startTime = CMTime(seconds: options.startSeconds, preferredTimescale: 600)
                    reader.timeRange = CMTimeRange(start: startTime, duration: .positiveInfinity)
                }

                guard reader.startReading() else {
                    if let err = reader.error {
                        self.error = err
                    }
                    break
                }

                while !stopped {
                    guard let sampleBuffer = trackOutput.copyNextSampleBuffer() else {
                        break // End of track
                    }

                    let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                        continue
                    }

                    if currentLoop == 0 && pts < options.startSeconds {
                        framesBeforeStart += 1
                        continue
                    }

                    guard let frame = frames.rent() else {
                        break // Queue closed
                    }

                    frame.copyFrom(cvPixelBuffer: pixelBuffer, index: frameIndex, pts: pts)
                    frames.push(frame)
                    framesDecoded += 1
                    lastVideoIndex = frameIndex
                    frameIndex += 1
                }

                if stopped || !options.loop {
                    frames.endOfStream = true
                    demuxEnded = true
                    break
                }

                currentLoop += 1
                loops += 1
            } catch {
                self.error = error
                break
            }
        }
    }

    private func audioDecodeLoop() {
        let fileUrl = URL(fileURLWithPath: (path as NSString).standardizingPath)
        var currentLoop = 0

        while !stopped {
            do {
                let asset = AVURLAsset(url: fileUrl)
                guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
                    pcm.complete()
                    break
                }

                let reader = try AVAssetReader(asset: asset)
                let audioSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 48000,
                    AVNumberOfChannelsKey: 2,
                    AVLinearPCMBitDepthKey: 32,
                    AVLinearPCMIsFloatKey: true,
                    AVLinearPCMIsNonInterleaved: false
                ]
                let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: audioSettings)
                trackOutput.alwaysCopiesSampleData = false
                reader.add(trackOutput)

                if currentLoop > 0 && options.loop {
                    let loopSec = options.loopPointSeconds < durationSeconds ? max(0, options.loopPointSeconds) : 0
                    let startTime = CMTime(seconds: loopSec, preferredTimescale: 600)
                    reader.timeRange = CMTimeRange(start: startTime, duration: .positiveInfinity)
                } else if options.startSeconds > 0 {
                    let startTime = CMTime(seconds: options.startSeconds, preferredTimescale: 600)
                    reader.timeRange = CMTimeRange(start: startTime, duration: .positiveInfinity)
                }

                guard reader.startReading() else {
                    pcm.complete()
                    break
                }

                while !stopped {
                    if _discardAudio {
                        Thread.sleep(forTimeInterval: 0.05)
                        continue
                    }

                    guard let sampleBuffer = trackOutput.copyNextSampleBuffer() else {
                        break
                    }

                    var blockBuffer: CMBlockBuffer?
                    var bufferList = AudioBufferList()
                    CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
                        sampleBuffer,
                        bufferListSizeNeededOut: nil,
                        bufferListOut: &bufferList,
                        bufferListSize: MemoryLayout<AudioBufferList>.size,
                        blockBufferAllocator: nil,
                        blockBufferMemoryAllocator: nil,
                        flags: 0,
                        blockBufferOut: &blockBuffer
                    )

                    if let mData = bufferList.mBuffers.mData {
                        let sampleBytes = Int(bufferList.mBuffers.mDataByteSize)
                        let floatCount = sampleBytes / MemoryLayout<Float>.size
                        let floatPtr = mData.assumingMemoryBound(to: Float.self)
                        let slice = UnsafeBufferPointer(start: floatPtr, count: floatCount)

                        while pcm.freeFrames < floatCount / 2 && !stopped {
                            Thread.sleep(forTimeInterval: 0.01)
                        }

                        if !stopped {
                            let written = pcm.write(slice)
                            audioSamplesOut += Int64(written)
                            audioSamplesDecoded += Int64(floatCount / 2)
                            if firstAudioSample < 0 {
                                firstAudioSample = 0
                            }
                        }
                    }
                }

                if stopped || !options.loop {
                    pcm.complete()
                    break
                }

                currentLoop += 1
            } catch {
                pcm.complete()
                break
            }
        }
    }
}
