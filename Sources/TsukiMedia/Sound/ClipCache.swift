import Foundation
import TsukiCore
import TsukiData
import TsukiEngine

public struct AudioCacheKey: Hashable, Sendable {
    public let bank: AudioBank
    public let entry: Int

    public init(bank: AudioBank, entry: Int) {
        self.bank = bank
        self.entry = entry
    }
}

/// Decoded clips by (bank, entry), shared between the engine thread and prefetch workers, evicting the least recently used
/// clips above a byte budget.
public final class ClipCache: @unchecked Sendable {
    private final class LruNode {
        let key: AudioCacheKey
        var prev: LruNode?
        var next: LruNode?

        init(key: AudioCacheKey) {
            self.key = key
        }
    }

    private final class Entry {
        let clip: LazyValue<Result<AudioClip, Error>>
        var node: LruNode?
        var bytes: Int64 = 0

        init(clip: LazyValue<Result<AudioClip, Error>>) {
            self.clip = clip
        }
    }

    private let gate = NSLock()
    private let decoding = UseGate()
    private let _decode: (AudioBank, Int) throws -> AudioClip
    private let budgetBytes: Int64
    private let collectEveryBytes: Int64
    private let _collect: () -> Void
    private var decodedSinceCollect: Int64 = 0
    private var entries: [AudioCacheKey: Entry] = [:]
    private var lruHead: LruNode?
    private var lruTail: LruNode?
    private var _bytes: Int64 = 0

    public private(set) var collections: Int64 = 0
    public private(set) var decodes: Int64 = 0
    public private(set) var hits: Int64 = 0

    /// Creates a cache over decode function (for example IGameData.audio).
    public init(
        decode: @escaping (AudioBank, Int) throws -> AudioClip,
        budgetBytes: Int64 = 256 << 20,
        collectEveryBytes: Int64 = 128 << 20,
        collect: (() -> Void)? = nil
    ) {
        self._decode = decode
        self.budgetBytes = budgetBytes
        self.collectEveryBytes = collectEveryBytes
        self._collect = collect ?? {}
    }

    deinit {
        dispose()
    }

    public var bytes: Int64 {
        gate.lock()
        defer { gate.unlock() }
        return _bytes
    }

    /// Stops the cache: no decode starts any more and decodes that are running are waited for.
    public func shutdown(timeout: TimeInterval) -> Bool {
        decoding.close(timeout: timeout)
    }

    public func dispose() {
        _ = shutdown(timeout: 15.0)
    }

    /// The clip, decoding it on the calling thread if no one has yet.
    public func get(bank: AudioBank, entry: Int) throws -> AudioClip {
        let e = try acquire(bank: bank, entry: entry)
        let result = e.clip.value // outside the lock
        let clip: AudioClip
        switch result {
        case let .success(c):
            clip = c
        case let .failure(err):
            forget(bank: bank, entry: entry, only: e)
            throw err
        }

        var shouldCollect = false
        gate.lock()
        let key = AudioCacheKey(bank: bank, entry: entry)
        if e.bytes == 0, let current = entries[key], current === e {
            e.bytes = Int64(clip.samples.count * MemoryLayout<Float>.size)
            _bytes += e.bytes
            evict(keep: key)
            decodedSinceCollect += e.bytes
            if collectEveryBytes > 0 && decodedSinceCollect >= collectEveryBytes {
                decodedSinceCollect = 0
                collections += 1
                shouldCollect = true
            }
        }
        gate.unlock()

        if shouldCollect {
            _collect()
        }

        return clip
    }

    /// Starts decoding an entry on a worker; the next get finds it ready.
    public func prefetch(bank: AudioBank, entry: Int) {
        guard !decoding.isClosed else { return }

        do {
            _ = try acquire(bank: bank, entry: entry)
        } catch {
            return
        }

        DispatchQueue.global().async { [weak self] in
            _ = try? self?.get(bank: bank, entry: entry)
        }
    }

    private func forget(bank: AudioBank, entry: Int, only: Entry) {
        gate.lock()
        defer { gate.unlock() }
        let key = AudioCacheKey(bank: bank, entry: entry)
        if let e = entries[key], e === only {
            entries.removeValue(forKey: key)
            _bytes -= e.bytes
            if let node = e.node {
                removeNode(node)
            }
        }
    }

    private func decodeEntry(bank: AudioBank, entry: Int) -> Result<AudioClip, Error> {
        do {
            _ = try decoding.enter(self)
            let clip = try _decode(bank, entry)
            return .success(clip)
        } catch {
            return .failure(error)
        }
    }

    private func acquire(bank: AudioBank, entry: Int) throws -> Entry {
        guard !decoding.isClosed else {
            throw TsukiError.state("ClipCache is shut down")
        }

        gate.lock()
        defer { gate.unlock() }

        let key = AudioCacheKey(bank: bank, entry: entry)
        if let e = entries[key] {
            hits += 1
            if let node = e.node {
                removeNode(node)
                addFirstNode(node)
            }
            return e
        }

        decodes += 1
        let lazyClip = LazyValue<Result<AudioClip, Error>> { [weak self] in
            guard let self = self else {
                return .failure(TsukiError.state("ClipCache deallocated"))
            }
            return self.decodeEntry(bank: bank, entry: entry)
        }

        let e = Entry(clip: lazyClip)
        let node = LruNode(key: key)
        e.node = node
        addFirstNode(node)
        entries[key] = e
        return e
    }

    private func evict(keep: AudioCacheKey) {
        var current = lruTail
        while _bytes > budgetBytes, let node = current {
            let prev = node.prev
            if node.key != keep {
                removeNode(node)
                if let e = entries.removeValue(forKey: node.key) {
                    _bytes -= e.bytes
                }
            }
            current = prev
        }
    }

    private func addFirstNode(_ node: LruNode) {
        node.next = lruHead
        node.prev = nil
        if let head = lruHead {
            head.prev = node
        } else {
            lruTail = node
        }
        lruHead = node
    }

    private func removeNode(_ node: LruNode) {
        if let prev = node.prev {
            prev.next = node.next
        } else {
            lruHead = node.next
        }
        if let next = node.next {
            next.prev = node.prev
        } else {
            lruTail = node.prev
        }
        node.prev = nil
        node.next = nil
    }
}
