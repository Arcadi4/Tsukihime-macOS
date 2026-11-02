import Foundation

/// Allocation sampling diagnostics for soak runs.
public final class AllocationSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: [String: Int64] = [:]

    public init() {}

    public func record(type: String, amount: Int64) {
        lock.withLock {
            bytes[type, default: 0] += amount
        }
    }

    /// The biggest allocators since the last call (MiB), and clears counts.
    public func take(top: Int) -> String {
        let list: [(key: String, value: Int64)] = lock.withLock {
            let l = bytes.map { ($0.key, $0.value) }
            bytes.removeAll()
            return l
        }

        if list.isEmpty {
            return ""
        }

        let sorted = list.sorted { $0.value > $1.value }.prefix(top)
        var res = "  allocation ticks (MiB since the last line):"
        for item in sorted {
            res += " [\(item.key) \(item.value >> 20)]"
        }
        return res
    }
}
