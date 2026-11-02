import Foundation

/// A decoded frame waiting to be shown: its index in the movie and its presentation time.
public struct FrameStamp: Sendable, Equatable {
    /// Frame number from 0.
    public let index: Int64
    /// Presentation time in seconds.
    public let pts: Double

    public init(index: Int64, pts: Double) {
        self.index = index
        self.pts = pts
    }
}

/// Chooses the frame each 60 Hz tick shows.
public final class FrameSelector {
    /// The lock of ARCHITECTURE 3.4: 4 ms.
    public static let defaultCadenceLockSeconds: Double = 0.004

    private static let epsilon: Double = 1e-9

    /// The cadence lock in seconds.
    public let cadenceLockSeconds: Double

    /// The frame shown, or nil before the first one.
    public private(set) var current: FrameStamp?

    /// Ticks the current frame has had, this one included.
    public private(set) var ticksShown: Int = 0

    /// Times the lock kept a frame for its second tick although the next one was due.
    public private(set) var holds: Int64 = 0

    /// Times the lock switched to the next frame early, after two ticks.
    public private(set) var earlySwitches: Int64 = 0

    /// Frames that were replaced before any tick showed them.
    public private(set) var dropped: Int64 = 0

    /// Called when a frame is replaced: the frame and the ticks it had.
    public var onRetired: ((FrameStamp, Int) -> Void)?

    /// Creates a selector with the given cadence lock (0 = off).
    public init(cadenceLockSeconds: Double = defaultCadenceLockSeconds) {
        self.cadenceLockSeconds = cadenceLockSeconds
    }

    /// One tick: clock is the movie clock sampled at tick's nominal time; ready holds decoded frames in order.
    /// Returns how many of them the caller removes from its queue.
    public func tick(clock: Double, ready: [FrameStamp]) -> Int {
        var consumed = 0

        while consumed < ready.count {
            let next = ready[consumed]
            if let cur = current {
                var due = next.pts <= clock + Self.epsilon
                if cadenceLockSeconds > 0 && cur.index + 1 == next.index {
                    if due && ticksShown == 1 && next.pts > clock - cadenceLockSeconds {
                        due = false // the boundary is within the lock window: give this frame its second tick
                        holds += 1
                    } else if !due && ticksShown >= 2 && next.pts <= clock + cadenceLockSeconds {
                        due = true // already had two ticks: switch up to the lock early
                        earlySwitches += 1
                    }
                }

                if !due {
                    break
                }

                if ticksShown == 0 {
                    dropped += 1
                }

                onRetired?(cur, ticksShown)
            }

            current = next
            ticksShown = 0
            consumed += 1
        }

        if current != nil {
            ticksShown += 1
        }

        return consumed
    }
}
