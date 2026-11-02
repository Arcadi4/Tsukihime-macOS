import Foundation

/// A value built on first use and shared afterwards. Cheap concurrent reads: the factory runs
/// once, under a lock, and every later read is synchronised but non-allocating.
public final class LazyValue<T> {
    private let lock = NSLock()
    private var stored: T?
    private var factory: (() -> T)?

    public init(_ factory: @escaping () -> T) {
        self.factory = factory
    }

    public convenience init(_ value: T) {
        self.init { value }
        self.stored = value
        self.factory = nil
    }

    public var value: T {
        lock.lock()
        defer { lock.unlock() }
        if let stored { return stored }
        let made = factory!()
        stored = made
        factory = nil
        return made
    }
}

/// Name lookup that ignores ASCII case, for the game's upper-cased asset names. The index keeps
/// the first entry for a duplicate name, as the archives do.
public struct NameIndex {
    private var entries: [String: Int] = [:]

    public init() {}

    public init(_ pairs: [(String, Int)]) {
        for (name, index) in pairs {
            entries[asciiLower(name), default: index] = index
        }
    }

    public var count: Int { entries.count }

    public mutating func add(_ name: String, index: Int) {
        entries[asciiLower(name), default: index] = index
    }

    public func find(_ name: String) -> Int? {
        entries[asciiLower(name)]
    }

    public func find(_ name: String, default fallback: Int) -> Int {
        entries[asciiLower(name)] ?? fallback
    }
}

private func asciiLower(_ name: String) -> String {
    name.lowercased()
}
