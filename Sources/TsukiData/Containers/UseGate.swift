import Darwin
import Foundation
import TsukiCore
import TsukiEngine

/// Lets the owner of a resource that threads read through raw pointers (a memory mapping, the packet
/// bytes a native decoder copies) close it only after those threads have left. A reader brackets its
/// use with `enter(_:)`; `close(timeout:)` refuses new readers and waits for the ones inside. Without
/// it, disposing the owner unmaps the pages under a decode that is still running, and the access
/// violation that follows cannot be caught (package K10, docs/status/knife/K10.md).
///
/// Safe from any thread. A reader that holds the gate must not call `close(timeout:)` itself (it would
/// wait for its own exit).
public final class UseGate {
    private let lock = NSLock()
    private var userCount = 0
    private var closed = false

    public init() {}

    /// Readers inside the gate now.
    public var users: Int {
        lock.lock()
        defer { lock.unlock() }
        return userCount
    }

    /// True once `close(timeout:)` has been called.
    public var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    /// Enters the gate; dispose the result to leave it.
    ///
    /// `owner` is the object that owns the resource and names it in the error, thrown when the gate is
    /// closed.
    public func enter(_ owner: Any) throws -> Use {
        guard let use = tryEnter() else {
            throw TsukiError.state("\(String(describing: type(of: owner))) is disposed")
        }
        return use
    }

    /// Enters the gate unless it is closed.
    public func tryEnter() -> Use? {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return nil }
        userCount += 1
        return Use(self)
    }

    /// Refuses new readers and waits until the ones inside have left.
    ///
    /// Returns true when no reader is left; false when the wait ran out (the caller must then leave the
    /// resource mapped).
    public func close(timeout: TimeInterval) -> Bool {
        lock.lock()
        closed = true
        lock.unlock()

        let length = max(0, timeout)
        let start = DispatchTime.now().uptimeNanoseconds
        let limit = UInt64(length * 1_000_000_000)
        let deadline = start &+ limit
        var spins = 0
        while true {
            lock.lock()
            let inside = userCount
            lock.unlock()
            if inside == 0 { return true }
            if DispatchTime.now().uptimeNanoseconds >= deadline { return false }
            if spins < 20 {
                spins += 1
                _ = sched_yield()
            } else {
                Thread.sleep(forTimeInterval: 0.001)
            }
        }
    }

    /// One reader's stay in the gate: dispose it (or let it go) to leave.
    public final class Use {
        private var gate: UseGate?

        fileprivate init(_ gate: UseGate) {
            self.gate = gate
        }

        deinit {
            leave()
        }

        /// Leaves the gate. Calling it again does nothing.
        public func dispose() {
            leave()
        }

        private func leave() {
            guard let gate else { return }
            self.gate = nil
            gate.leave()
        }
    }

    fileprivate func leave() {
        lock.lock()
        if userCount > 0 { userCount -= 1 }
        lock.unlock()
    }
}
