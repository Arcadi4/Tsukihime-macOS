import Foundation

/// One logic step.
public struct LogicTick: Sendable, Equatable {
    /// The 60 Hz frame counter: steps run so far, 0 first (the only time logic sees).
    public let frame: Int64
    /// The step's grid time in clock units; media clocks are sampled here.
    public let nominalTimestamp: Int64

    public init(frame: Int64, nominalTimestamp: Int64) {
        self.frame = frame
        self.nominalTimestamp = nominalTimestamp
    }
}

/// Hands out fixed steps on a drift-free grid of frequency / stepsPerSecond clock units.
public final class FixedStepClock: @unchecked Sendable {
    private let _frequency: Int64
    private let _stepsPerSecond: Int
    private let _maxLagSteps: Int64
    private var _gridBase: Int64
    private var _gridBaseFrame: Int64

    /// The frame number the next step will carry (= steps run so far).
    public private(set) var frame: Int64 = 0

    /// Steps dropped after stalls.
    public private(set) var skippedSteps: Int64 = 0

    /// How many times the grid was restarted after a stall.
    public private(set) var resyncs: Int64 = 0

    /// Starts the grid: step 0 is due at startTimestamp.
    /// - Parameters:
    ///   - frequency: Clock units per second.
    ///   - startTimestamp: Due time of step 0.
    ///   - stepsPerSecond: Logic rate; the game runs at 60.
    ///   - maxLagSteps: Backlog beyond which pending steps are dropped (default: 4).
    public init(frequency: Int64, startTimestamp: Int64, stepsPerSecond: Int = 60, maxLagSteps: Int64 = 4) {
        precondition(frequency > 0, "frequency must be positive")
        precondition(stepsPerSecond > 0, "stepsPerSecond must be positive")
        precondition(maxLagSteps >= 0, "maxLagSteps must be non-negative")

        self._frequency = frequency
        self._stepsPerSecond = stepsPerSecond
        self._maxLagSteps = maxLagSteps
        self._gridBase = startTimestamp
        self._gridBaseFrame = 0
    }

    /// Clock units per second.
    public var frequency: Int64 { _frequency }

    /// Logic steps per second.
    public var stepsPerSecond: Int { _stepsPerSecond }

    /// When the next step is due, in clock units.
    public var nextDueTimestamp: Int64 {
        gridTime(frame)
    }

    /// Returns the next step if it is due at `now`. Call it in a loop until it returns nil, then render and present.
    public func nextTick(now: Int64) -> LogicTick? {
        let due = gridTime(frame)
        if now < due {
            return nil
        }

        let tick = LogicTick(frame: frame, nominalTimestamp: due)
        frame += 1
        let next = gridTime(frame)
        let lag = now - next
        if _maxLagSteps >= 0 && lag > stepsToUnits(_maxLagSteps) {
            let skipped = Int64(Double(lag) * Double(_stepsPerSecond) / Double(_frequency))
            skippedSteps += skipped
            resyncs += 1
            _gridBase = now
            _gridBaseFrame = frame - 1
        }

        return tick
    }

    /// Returns true and sets `tick` if the next step is due at `now`.
    public func tryNextTick(now: Int64, tick: inout LogicTick) -> Bool {
        if let t = nextTick(now: now) {
            tick = t
            return true
        }
        return false
    }

    /// Clock units in steps steps (rounded down).
    public func stepsToUnits(_ steps: Int64) -> Int64 {
        Int64(Double(steps) * Double(_frequency) / Double(_stepsPerSecond))
    }

    private func gridTime(_ targetFrame: Int64) -> Int64 {
        _gridBase + stepsToUnits(targetFrame - _gridBaseFrame)
    }
}
