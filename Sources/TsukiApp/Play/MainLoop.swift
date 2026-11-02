import AppKit
import Foundation
import TsukiPlatform

/// Counters of one loop run.
public final class LoopStats: CustomStringConvertible, @unchecked Sendable {
    public var steps: Int64 = 0
    public var presents: Int64 = 0
    public var skippedSteps: Int64 = 0
    public var resyncs: Int64 = 0
    public var wallSeconds: Double = 0
    public var stopReason: String = ""

    /// Present-to-present intervals in 0.5 ms buckets; the last bucket holds 100 ms and more.
    public var intervalHistogram: [Int] = [Int](repeating: 0, count: 201)
    public private(set) var maxIntervalMs: Double = 0

    public init() {}

    public func addInterval(_ ms: Double) {
        if ms > maxIntervalMs {
            maxIntervalMs = ms
        }
        let b = max(0, min(intervalHistogram.count - 1, Int(ms * 2.0)))
        intervalHistogram[b] += 1
    }

    /// The bucket (upper edge, ms) holding the median interval.
    public func medianIntervalMs() -> Double {
        var total = 0
        for count in intervalHistogram {
            total += count
        }
        if total == 0 {
            return 0
        }

        let half = total / 2
        var sum = 0
        for i in 0..<intervalHistogram.count {
            sum += intervalHistogram[i]
            if sum >= half {
                return Double(i + 1) * 0.5
            }
        }
        return Double(intervalHistogram.count) * 0.5
    }

    public func intervalsOver(_ ms: Double) -> Int {
        let start = min(intervalHistogram.count, max(0, Int(ms * 2.0)))
        var sum = 0
        for i in start..<intervalHistogram.count {
            sum += intervalHistogram[i]
        }
        return sum
    }

    public var description: String {
        let rate = presents / Int64(max(wallSeconds, 1e-9))
        return "\(steps) steps, \(presents) presents in \(String(format: "%.3f", wallSeconds)) s (\(rate) presents/s); " +
            "present interval median <= \(String(format: "%.1f", medianIntervalMs())) ms, max \(String(format: "%.1f", maxIntervalMs)) ms, \(intervalsOver(17)) over 17 ms; " +
            "skipped steps \(skippedSteps), resyncs \(resyncs); stopped: \(stopReason)"
    }
}

/// Runs the main 60 Hz frame loop.
public final class MainLoop: @unchecked Sendable {
    private let window: GameWindow

    public init(window: GameWindow) {
        self.window = window
    }

    public func run(
        onStep: (LogicTick) -> Bool,
        onPresent: (Int64) -> Void,
        maxSeconds: Double = 0
    ) -> LoopStats {
        let stats = LoopStats()
        let frequency: Int64 = 1_000_000_000 // nanoseconds
        let startNs = Int64(Pacing.nowNanoseconds())
        let limitNs = maxSeconds > 0 ? startNs + Int64(maxSeconds * 1_000_000_000.0) : Int64.max

        let clock = FixedStepClock(frequency: frequency, startTimestamp: startNs, stepsPerSecond: 60)
        var newestFrame: Int64 = -1
        var lastPresentNs: Int64 = 0
        var running = true

        while running {
            // Process native AppKit events
            let app = NSApplication.shared
            while true {
                let event = app.nextEvent(matching: .any, until: nil, inMode: .default, dequeue: true)
                guard let ev = event else { break }
                app.sendEvent(ev)
            }

            let nowNs = Int64(Pacing.nowNanoseconds())
            while running, let tick = clock.nextTick(now: nowNs) {
                newestFrame = tick.frame
                stats.steps += 1
                if !onStep(tick) {
                    running = false
                    stats.stopReason = "step handler"
                }
            }

            onPresent(newestFrame)
            let presentedNs = Int64(Pacing.nowNanoseconds())
            if lastPresentNs != 0 {
                let diffMs = Double(presentedNs - lastPresentNs) / 1_000_000.0
                stats.addInterval(diffMs)
            }
            lastPresentNs = presentedNs
            stats.presents += 1

            if presentedNs >= limitNs {
                running = false
                stats.stopReason = "time limit"
            }

            if running {
                let nextDue = clock.nextDueTimestamp
                let cur = Int64(Pacing.nowNanoseconds())
                if nextDue > cur {
                    Pacing.waitUntil(timestamp: nextDue, frequency: frequency, currentTimestamp: cur)
                }
            }
        }

        stats.skippedSteps = clock.skippedSteps
        stats.resyncs = clock.resyncs
        stats.wallSeconds = Double(Int64(Pacing.nowNanoseconds()) - startNs) / 1_000_000_000.0
        return stats
    }
}
