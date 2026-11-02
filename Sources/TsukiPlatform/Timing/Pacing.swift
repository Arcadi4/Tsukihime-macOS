import Darwin
import Foundation

/// High-resolution pacing for fixed frame loops.
public enum Pacing {
    /// The current monotonic time in nanoseconds (CLOCK_UPTIME_RAW).
    @inline(__always)
    public static func nowNanoseconds() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    }

    /// Sleeps until nowNanoseconds reaches `targetNs`.
    public static func waitUntilNanoseconds(_ targetNs: UInt64) {
        var now = nowNanoseconds()
        if now >= targetNs {
            return
        }

        let remainingNs = targetNs - now
        // Sleep for the bulk of the duration (> 1 ms), reserving 1 ms for spinning.
        if remainingNs > 1_000_000 {
            let sleepNs = remainingNs - 1_000_000
            var req = timespec(tv_sec: Int(sleepNs / 1_000_000_000), tv_nsec: Int(sleepNs % 1_000_000_000))
            nanosleep(&req, nil)
            now = nowNanoseconds()
        }

        // Spin-wait the last stretch for microsecond accuracy.
        while now < targetNs {
            now = nowNanoseconds()
        }
    }

    /// Sleeps until a timestamp with a given frequency is reached.
    public static func waitUntil(timestamp: Int64, frequency: Int64, currentTimestamp: Int64) {
        let remaining = timestamp - currentTimestamp
        if remaining <= 0 {
            return
        }

        let clampedRemaining = min(remaining, frequency)
        let ns = UInt64(Double(clampedRemaining) * 1_000_000_000.0 / Double(frequency))
        let targetNs = nowNanoseconds() + ns
        waitUntilNanoseconds(targetNs)
    }
}
