import AVFoundation
import Foundation

/// Renders the next frames as interleaved float32 stereo into interleaved
/// (length = frames * 2, frames <= AudioOutput.maxPeriodFrames). Must fill all of it.
public typealias AudioRenderCallback = @Sendable (UnsafeMutableBufferPointer<Float>) -> Void

/// One float32 stereo 48 kHz audio stream fed by a render callback.
public final class AudioOutput: @unchecked Sendable {
    /// Output rate (ARCHITECTURE 7.1).
    public static let sampleRate: Int = 48_000

    /// Output channels (stereo).
    public static let channels: Int = 2

    /// The largest period the callback is asked for (ARCHITECTURE 7.1).
    public static let maxPeriodFrames: Int = 1024

    private static let bytesPerFrame = channels * MemoryLayout<Float>.size

    private let render: AudioRenderCallback
    public let isDevice: Bool

    public private(set) var driver: String?
    public private(set) var deviceName: String?
    public private(set) var deviceRate: Int = sampleRate
    public private(set) var deviceChannels: Int = channels
    public private(set) var deviceBufferFrames: Int = 0

    private var _framesRendered: Int64 = 0
    private var _callbacks: Int64 = 0
    private var _callbackError: String?

    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private let lock = NSLock()

    /// Frames the callback has rendered so far.
    public var framesRendered: Int64 {
        OSAtomicAdd64(0, &_framesRendered)
    }

    /// Audio render callbacks so far.
    public var callbacks: Int64 {
        OSAtomicAdd64(0, &_callbacks)
    }

    /// The first error the render callback threw, or nil.
    public var callbackError: String? {
        lock.withLock { _callbackError }
    }

    private init(render: @escaping AudioRenderCallback, isDevice: Bool) {
        self.render = render
        self.isDevice = isDevice
    }

    deinit {
        dispose()
    }

    /// Opens the default playback device, paused. Call start() to play.
    public static func openDevice(render: @escaping AudioRenderCallback) throws -> AudioOutput {
        let output = AudioOutput(render: render, isDevice: true)
        let engine = AVAudioEngine()
        output.engine = engine

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate), channels: AVAudioChannelCount(channels), interleaved: false)!

        var scratch = [Float](repeating: 0, count: maxPeriodFrames * channels)

        let node = AVAudioSourceNode(format: format) { [weak output] isSilence, timestamp, frameCount, outputData -> OSStatus in
            guard let output = output else { return noErr }
            OSAtomicIncrement64(&output._callbacks)

            let bufferList = UnsafeMutableAudioBufferListPointer(outputData)
            guard bufferList.count >= 2,
                  let leftBuf = bufferList[0].mData?.assumingMemoryBound(to: Float.self),
                  let rightBuf = bufferList[1].mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }

            var framesRemaining = Int(frameCount)
            var frameOffset = 0

            while framesRemaining > 0 {
                let n = min(framesRemaining, AudioOutput.maxPeriodFrames)
                let sampleCount = n * AudioOutput.channels

                scratch.withUnsafeMutableBufferPointer { span in
                    let subspan = UnsafeMutableBufferPointer(rebasing: span[0..<sampleCount])
                    if output.callbackError == nil {
                        output.render(subspan)
                    } else {
                        subspan.initialize(repeating: 0)
                    }

                    // Deinterleave into non-interleaved CoreAudio buffers
                    for i in 0..<n {
                        leftBuf[frameOffset + i] = subspan[i * 2]
                        rightBuf[frameOffset + i] = subspan[i * 2 + 1]
                    }
                }

                OSAtomicAdd64(Int64(n), &output._framesRendered)
                frameOffset += n
                framesRemaining -= n
            }

            return noErr
        }

        output.sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)

        output.driver = "AVAudioEngine"
        output.deviceName = "Default Output"
        output.deviceRate = Int(engine.outputNode.outputFormat(forBus: 0).sampleRate)
        output.deviceChannels = Int(engine.outputNode.outputFormat(forBus: 0).channelCount)

        return output
    }

    /// Creates a 48 kHz float stereo stream with no device; read it with pull().
    public static func createPullOnly(render: @escaping AudioRenderCallback) -> AudioOutput {
        AudioOutput(render: render, isDevice: false)
    }

    /// Pull mode: reads interleaved frames through the render callback; returns frames read.
    @discardableResult
    public func pull(_ interleaved: UnsafeMutableBufferPointer<Float>) -> Int {
        precondition(!isDevice, "Pull is for pull-only streams")
        let frames = interleaved.count / Self.channels
        var framesRemaining = frames
        var frameOffset = 0

        while framesRemaining > 0 {
            let n = min(framesRemaining, Self.maxPeriodFrames)
            let sub = UnsafeMutableBufferPointer(rebasing: interleaved[(frameOffset * Self.channels)..<((frameOffset + n) * Self.channels)])
            render(sub)
            OSAtomicAdd64(Int64(n), &_framesRendered)
            OSAtomicIncrement64(&_callbacks)
            frameOffset += n
            framesRemaining -= n
        }

        return frames
    }

    /// Starts (resumes) audio playback.
    public func start() throws {
        guard isDevice, let engine = engine else { return }
        if !engine.isRunning {
            try engine.start()
        }
    }

    /// Pauses audio playback.
    public func pause() {
        guard isDevice, let engine = engine else { return }
        if engine.isRunning {
            engine.pause()
        }
    }

    /// Stops audio playback and releases resources.
    public func dispose() {
        if let engine = engine {
            if engine.isRunning {
                engine.stop()
            }
            if let node = sourceNode {
                engine.detach(node)
                sourceNode = nil
            }
            self.engine = nil
        }
    }
}

