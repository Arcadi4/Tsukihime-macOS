import Foundation

/// Runs `body` for every index, on at most `parallelism` threads. Results are written through a
/// lock; each call writes a distinct index, so the work is deterministic.
public func parallelForEach(_ count: Int, parallelism: Int = 0, _ body: @escaping (Int) -> Void) {
    guard count > 0 else { return }
    let requested = parallelism > 0 ? parallelism : ProcessInfo.processInfo.activeProcessorCount
    let workers = max(1, min(count, requested))
    guard workers > 1 else {
        for i in 0..<count { body(i) }
        return
    }

    let slice = (count + workers - 1) / workers
    DispatchQueue.concurrentPerform(iterations: workers) { worker in
        let start = worker * slice
        let end = min(count, start + slice)
        guard start < end else { return }
        for i in start..<end { body(i) }
    }
}

/// Maps a collection in parallel, preserving order.
public func parallelMap<T, R>(_ items: [T], parallelism: Int = 0, _ body: @escaping (T) -> R) -> [R] {
    guard !items.isEmpty else { return [] }
    var results = [R?](repeating: nil, count: items.count)
    let lock = NSLock()
    parallelForEach(items.count, parallelism: parallelism) { index in
        let value = body(items[index])
        lock.lock()
        results[index] = value
        lock.unlock()
    }
    return results.map { $0! }
}
