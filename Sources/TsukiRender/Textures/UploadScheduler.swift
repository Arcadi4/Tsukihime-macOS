import Foundation
import TsukiCore

/// A decoded tile waiting for upload.
public struct DecodedTile: @unchecked Sendable {
    public let key: TextureRef
    public let width: Int
    public let height: Int
    public let pixels: StagingBuffer
    public let graded: Bool

    public init(key: TextureRef, width: Int, height: Int, pixels: StagingBuffer, graded: Bool = false) {
        self.key = key
        self.width = width
        self.height = height
        self.pixels = pixels
        self.graded = graded
    }
}

/// What one `UploadScheduler.uploadSlice` did.
public struct UploadSliceStats: Equatable, Sendable {
    public var tiles: Int
    public var bytes: Int64
    public var allocations: Int
    public var recycles: Int
    public var cpuMilliseconds: Double
    public var pending: Int

    public init(
        tiles: Int = 0,
        bytes: Int64 = 0,
        allocations: Int = 0,
        recycles: Int = 0,
        cpuMilliseconds: Double = 0,
        pending: Int = 0
    ) {
        self.tiles = tiles
        self.bytes = bytes
        self.allocations = allocations
        self.recycles = recycles
        self.cpuMilliseconds = cpuMilliseconds
        self.pending = pending
    }
}

/// Queues decoded tiles and uploads them in byte-capped slices.
public final class UploadScheduler: @unchecked Sendable {
    public static let defaultMaxBytesPerFrame: Int64 = 16 << 20
    public static let backgroundBytesPerFrame: Int64 = 4 << 20

    public let cache: TextureCache
    public let pool: StagingPool
    public let maxBytesPerFrame: Int64

    private let lock = NSLock()
    private var queue: [DecodedTile] = []
    private var backgroundMap: [TextureRef: DecodedTile] = [:]
    private var backgroundOrder: [TextureRef] = []
    private var carry: DecodedTile?

    public private(set) var uploadedTiles: Int64 = 0
    public private(set) var uploadedBytes: Int64 = 0

    public init(cache: TextureCache, pool: StagingPool, maxBytesPerFrame: Int64 = defaultMaxBytesPerFrame) {
        self.cache = cache
        self.pool = pool
        self.maxBytesPerFrame = maxBytesPerFrame
    }

    public var pending: Int {
        lock.lock()
        defer { lock.unlock() }
        return queue.count + backgroundMap.count + (carry != nil ? 1 : 0)
    }

    public func enqueue(_ tile: DecodedTile) {
        lock.lock()
        queue.append(tile)
        lock.unlock()
    }

    public func enqueueBackground(_ tile: DecodedTile) {
        lock.lock()
        if backgroundMap[tile.key] == nil {
            backgroundMap[tile.key] = tile
            backgroundOrder.append(tile.key)
        }
        lock.unlock()
    }

    /// Moves a background tile into the urgent queue.
    @discardableResult
    public func promote(_ key: TextureRef) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let tile = backgroundMap.removeValue(forKey: key) {
            queue.insert(tile, at: 0)
            return true
        }
        return false
    }

    /// Uploads one slice of tiles to the GPU.
    public func uploadSlice() -> UploadSliceStats {
        let t0 = DispatchTime.now()
        var tiles = 0
        var allocations = 0
        var recycles = 0
        var bytes: Int64 = 0

        while true {
            var tile: DecodedTile?
            lock.lock()
            if let c = carry {
                tile = c
            } else if !queue.isEmpty {
                tile = queue.removeFirst()
            }
            lock.unlock()

            guard let currentTile = tile else {
                break
            }

            let size = Int64(currentTile.pixels.length)
            if tiles > 0 && bytes + size > maxBytesPerFrame {
                lock.lock()
                carry = currentTile
                lock.unlock()
                break
            }

            lock.lock()
            carry = nil
            lock.unlock()

            let allocated = currentTile.pixels.withUnsafeBytes { ptr in
                cache.upload(
                    key: currentTile.key,
                    width: currentTile.width,
                    height: currentTile.height,
                    rgba: ptr,
                    pregraded: currentTile.graded
                )
            }
            if allocated {
                allocations += 1
            } else {
                recycles += 1
            }

            pool.returnBuffer(currentTile.pixels)
            tiles += 1
            bytes += size
        }

        // Upload background look-ahead tiles with leftover budget
        var background: Int64 = 0
        while background < Self.backgroundBytesPerFrame {
            var bgTile: DecodedTile?
            lock.lock()
            while !backgroundOrder.isEmpty {
                let nextKey = backgroundOrder.removeFirst()
                if let t = backgroundMap.removeValue(forKey: nextKey) {
                    bgTile = t
                    break
                }
            }
            lock.unlock()

            guard let currentBgTile = bgTile else {
                break
            }

            let size = Int64(currentBgTile.pixels.length)
            let allocated = currentBgTile.pixels.withUnsafeBytes { ptr in
                cache.upload(
                    key: currentBgTile.key,
                    width: currentBgTile.width,
                    height: currentBgTile.height,
                    rgba: ptr,
                    pregraded: currentBgTile.graded
                )
            }
            if allocated {
                allocations += 1
            } else {
                recycles += 1
            }

            pool.returnBuffer(currentBgTile.pixels)
            tiles += 1
            bytes += size
            background += size
        }

        uploadedTiles += Int64(tiles)
        uploadedBytes += bytes

        let t1 = DispatchTime.now()
        let ms = Double(t1.uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000.0

        return UploadSliceStats(
            tiles: tiles,
            bytes: bytes,
            allocations: allocations,
            recycles: recycles,
            cpuMilliseconds: ms,
            pending: self.pending
        )
    }
}
