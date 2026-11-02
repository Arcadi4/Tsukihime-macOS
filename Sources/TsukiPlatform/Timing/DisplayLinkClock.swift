import CoreVideo
import Foundation

/// A 60 Hz pacing clock backed by CVDisplayLink with fallback to a high-resolution dispatch timer.
public final class DisplayLinkClock: @unchecked Sendable {
    public typealias TickHandler = @Sendable (Int64, UInt64) -> Void

    private var displayLink: CVDisplayLink?
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "org.tsukihime.displaylink", qos: .userInteractive)
    private var isRunning = false
    private var frameCounter: Int64 = 0
    private let handler: TickHandler

    public init(handler: @escaping TickHandler) {
        self.handler = handler
        setupDisplayLink()
    }

    deinit {
        stop()
    }

    private func setupDisplayLink() {
        var link: CVDisplayLink?
        let status = CVDisplayLinkCreateWithActiveCGDisplays(&link)
        if status == kCVReturnSuccess, let link = link {
            self.displayLink = link
            let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, displayLinkContext -> CVReturn in
                guard let context = displayLinkContext else { return kCVReturnSuccess }
                let clock = Unmanaged<DisplayLinkClock>.fromOpaque(context).takeUnretainedValue()
                clock.onTick()
                return kCVReturnSuccess
            }
            CVDisplayLinkSetOutputCallback(link, callback, Unmanaged.passUnretained(self).toOpaque())
        }
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        if let link = displayLink {
            CVDisplayLinkStart(link)
        } else {
            startTimerFallback()
        }
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        if let link = displayLink {
            CVDisplayLinkStop(link)
        }
        timer?.cancel()
        timer = nil
    }

    private func startTimerFallback() {
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        t.schedule(deadline: .now(), repeating: .nanoseconds(16_666_667), leeway: .nanoseconds(500_000))
        t.setEventHandler { [weak self] in
            self?.onTick()
        }
        timer = t
        t.resume()
    }

    private func onTick() {
        let frame = OSAtomicIncrement64(&frameCounter) - 1
        let now = Pacing.nowNanoseconds()
        handler(frame, now)
    }
}
