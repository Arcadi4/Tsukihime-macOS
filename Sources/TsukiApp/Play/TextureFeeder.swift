import Foundation
import TsukiCore
import TsukiData
import TsukiEngine
import TsukiMedia
import TsukiRender
import TsukiUi

public struct FeederStats: Sendable {
    public let requested: Int64
    public let waits: Int64
    public let waitMilliseconds: Double
    public let timedOut: Int64
    public let failures: Int64
    public let movieUploads: Int64
    public let prefetched: Int64

    public init(
        requested: Int64 = 0,
        waits: Int64 = 0,
        waitMilliseconds: Double = 0,
        timedOut: Int64 = 0,
        failures: Int64 = 0,
        movieUploads: Int64 = 0,
        prefetched: Int64 = 0
    ) {
        self.requested = requested
        self.waits = waits
        self.waitMilliseconds = waitMilliseconds
        self.timedOut = timedOut
        self.failures = failures
        self.movieUploads = movieUploads
        self.prefetched = prefetched
    }
}

public enum YuvConverter {
    public static func toRgba(frame: VideoFrame, rgba: inout [UInt8]) {
        let w = frame.width
        let h = frame.height
        let yp = frame.y
        let up = frame.u
        let vp = frame.v

        if rgba.count < w * h * 4 {
            rgba = [UInt8](repeating: 0, count: w * h * 4)
        }

        for row in 0..<(h / 2) {
            for dy in 0..<2 {
                let y = (row * 2) + dy
                let yo = y * w
                let co = row * (w / 2)
                var o = y * w * 4
                for x in 0..<w {
                    let c = Int(yp[yo + x]) - 16
                    let d = Int(up[co + (x >> 1)]) - 128
                    let e = Int(vp[co + (x >> 1)]) - 128
                    let c298 = 298 * c
                    rgba[o] = clamp((c298 + (459 * e) + 128) >> 8)
                    rgba[o + 1] = clamp((c298 - (55 * d) - (136 * e) + 128) >> 8)
                    rgba[o + 2] = clamp((c298 + (541 * d) + 128) >> 8)
                    rgba[o + 3] = 255
                    o += 4
                }
            }
        }
    }

    private static func clamp(_ v: Int) -> UInt8 {
        UInt8(truncatingIfNeeded: v < 0 ? 0 : v > 255 ? 255 : v)
    }
}

public final class TextureFeeder: @unchecked Sendable {
    private let data: GameFolderSource
    private let cache: TextureCache
    private let pool: StagingPool = StagingPool()
    private let scheduler: UploadScheduler
    private let workers: DecodeWorkers
    private var queued: Set<TextureRef> = []
    private var wanted: [TextureRef] = []
    private var _prefetched: Int64 = 0

    public var lastFresh: [TextureRef] = []
    private struct MovieKey: Hashable {
        let index: Int64
        let pts: Double
        let movie: Int
    }
    private var movieShown: [Int32: MovieKey] = [:]
    private var rgbaBuffer: [UInt8] = []
    private var _requested: Int64 = 0
    private var _waits: Int64 = 0
    private var _waitMs: Double = 0
    private var _timedOut: Int64 = 0
    private var _movieUploads: Int64 = 0
    private var partsPicture: Picture?
    private var partsIndex: Int32 = -1
    private let lock = NSLock()

    public init(data: GameFolderSource, cache: TextureCache, workers: Int = 0) {
        self.data = data
        self.cache = cache
        self.scheduler = UploadScheduler(cache: cache, pool: pool)
        self.workers = DecodeWorkers(scheduler: scheduler, workers: workers)
    }

    public var thumbnails: ((Int) -> UiThumbnail?)?
    public var movieFrames: ((Int) -> VideoFrame?)?
    public var composed: ((TextureRef) -> UiComposedPicture?)?

    public var poolRef: StagingPool { pool }

    public func describeQueues() -> String {
        "queued set \(queued.count), wanted \(wanted.count), movie slots \(movieShown.count)"
    }

    public var fault: Error? {
        workers.fault
    }

    public var stats: FeederStats {
        FeederStats(
            requested: _requested,
            waits: _waits,
            waitMilliseconds: _waitMs,
            timedOut: _timedOut,
            failures: workers.fault == nil ? 0 : 1,
            movieUploads: _movieUploads,
            prefetched: _prefetched
        )
    }

    public func prefetch(_ keys: [TextureRef]) {
        for key in keys {
            if key.kind == .pictureTile && key.a != UInt8(UiPictureArchive.parts) && !cache.contains(key) && queued.insert(key).inserted {
                _requested += 1
                _prefetched += 1
                workers.enqueueBackground(pictureJob(key))
            }
        }
    }

    public var pending: Int {
        workers.pending + scheduler.pending
    }

    @discardableResult
    public func ensureResident(list: DisplayList, budget: TimeInterval) -> Int {
        _ = scheduler.uploadSlice()
        wanted.removeAll(keepingCapacity: true)
        lastFresh.removeAll(keepingCapacity: true)
        var fresh = 0

        for c in list.commands {
            guard c.kind == .texturedQuad else { continue }
            let key = c.texture
            switch key.kind {
            case .capture, .none:
                break
            case .movieFrame:
                uploadMovieFrame(key)
            case .thumbnail:
                uploadThumbnail(key)
            case .uiComposed:
                uploadComposed(key)
            default:
                if cache.touch(key) {
                    break
                }
                if !cache.contains(key) {
                    wanted.append(key)
                    if queued.insert(key).inserted {
                        enqueue(key)
                        lastFresh.append(key)
                        fresh += 1
                    } else {
                        workers.promote(key)
                    }
                }
            }
        }

        if wanted.isEmpty {
            uploadSliceAndPrune()
            return 0
        }

        let start = Date()
        var missing = wanted.count
        while missing > 0 && Date().timeIntervalSince(start) < budget {
            _ = scheduler.uploadSlice()
            missing = countMissing()
            if missing > 0 {
                if workers.fault != nil && workers.pending == 0 && scheduler.pending == 0 {
                    break
                }
                Thread.sleep(forTimeInterval: 0.0001)
            }
        }

        uploadSliceAndPrune()
        missing = countMissing()
        let elapsed = Date().timeIntervalSince(start) * 1000.0
        if fresh > 0 || missing > 0 || elapsed >= 1.0 {
            _waits += 1
            _waitMs += elapsed
        }

        if missing > 0 && Date().timeIntervalSince(start) >= budget {
            _timedOut += 1
        }

        return missing
    }

    private func countMissing() -> Int {
        var missing = 0
        for k in wanted {
            if !cache.contains(k) {
                missing += 1
                workers.promote(k)
            }
        }
        return missing
    }

    private func uploadSliceAndPrune() {
        _ = scheduler.uploadSlice()
        queued = queued.filter { !cache.contains($0) }
    }

    private func enqueue(_ key: TextureRef) {
        _requested += 1
        switch key.kind {
        case .pictureTile where key.a == UInt8(UiPictureArchive.parts):
            workers.enqueue(partsJob(key))
        case .pictureTile:
            workers.enqueue(pictureJob(key))
        case .uiTile where key.d < 0:
            workers.enqueue(wholeSheetJob(key))
        case .uiTile:
            workers.enqueue(sheetTileJob(key))
        case .glyphPage:
            workers.enqueue(glyphJob(key))
        default:
            fatalError("no texture source for \(key)")
        }
    }

    private func pictureJob(_ key: TextureRef) -> DecodeJob {
        do {
            let image = try data.openImage(Int(key.a), Int(key.b))
            let h = image.header
            return DecodeJob(key: key, width: h.tileWidth, height: h.tileHeight, decode: { rgba in
                var tileRgba = [UInt8](repeating: 0, count: h.tileWidth * h.tileHeight * 4)
                let scratch = TileScratch()
                try image.decodeTile(Int(key.c), scratch: scratch, rgba: &tileRgba)
                tileRgba.withUnsafeBytes { ptr in
                    rgba.copyMemory(from: ptr)
                }
            })
        } catch {
            return DecodeJob(key: key, width: 256, height: 256, decode: { _ in throw error })
        }
    }

    private func sheetTileJob(_ key: TextureRef) -> DecodeJob {
        guard let set = UiSet(rawValue: Int(key.a)), let lang = Language(rawValue: UInt8(truncatingIfNeeded: key.b)) else {
            return DecodeJob(key: key, width: 256, height: 256, decode: { _ in })
        }
        do {
            let image = try data.openUiSheetImage(set, lang, Int(key.c))
            let h = image.header
            return DecodeJob(key: key, width: h.tileWidth, height: h.tileHeight, decode: { rgba in
                var tileRgba = [UInt8](repeating: 0, count: h.tileWidth * h.tileHeight * 4)
                let scratch = TileScratch()
                try image.decodeTile(Int(key.d), scratch: scratch, rgba: &tileRgba)
                tileRgba.withUnsafeBytes { ptr in
                    rgba.copyMemory(from: ptr)
                }
            })
        } catch {
            return DecodeJob(key: key, width: 256, height: 256, decode: { _ in throw error })
        }
    }
    private func wholeSheetJob(_ key: TextureRef) -> DecodeJob {
        guard let set = UiSet(rawValue: Int(key.a)), let lang = Language(rawValue: UInt8(truncatingIfNeeded: key.b)) else {
            return DecodeJob(key: key, width: 256, height: 256, decode: { _ in })
        }
        do {
            let image = try data.openUiSheetImage(set, lang, Int(key.c))
            let h = image.header
            return DecodeJob(key: key, width: h.displayWidth, height: h.displayHeight, decode: { rgba in
                let decoded = try image.decodeDisplayed()
                decoded.withUnsafeBytes { ptr in
                    rgba.copyMemory(from: ptr)
                }
            })
        } catch {
            return DecodeJob(key: key, width: 256, height: 256, decode: { _ in throw error })
        }
    }

    private func glyphJob(_ key: TextureRef) -> DecodeJob {
        guard let lang = Language(rawValue: UInt8(truncatingIfNeeded: key.a)) else {
            return DecodeJob(key: key, width: 256, height: 256, decode: { _ in })
        }
        let page = data.fontPage(lang, Int(key.b))
        return DecodeJob(key: key, width: page.width, height: page.height, decode: { rgba in
            page.rgba.withUnsafeBytes { ptr in
                rgba.copyMemory(from: ptr)
            }
        })
    }
    private func partsJob(_ key: TextureRef) -> DecodeJob {
        lock.lock()
        if partsIndex != key.b || partsPicture == nil {
            partsPicture = try? data.parts(Int(key.b))
            partsIndex = key.b
        }
        let pic = partsPicture
        lock.unlock()

        guard let pic = pic, let tile = pic.tiles.first(where: { $0.index == Int(key.c) }) else {
            return DecodeJob(key: key, width: 256, height: 256, decode: { _ in })
        }

        return DecodeJob(key: key, width: tile.storedWidth, height: tile.storedHeight, decode: { rgba in
            tile.rgba.withUnsafeBytes { ptr in
                rgba.copyMemory(from: ptr)
            }
        })
    }

    private func uploadThumbnail(_ key: TextureRef) {
        if cache.contains(key) { return }
        guard let thumb = thumbnails?(Int(key.a)) else { return }
        cache.upload(key: key, width: thumb.width, height: thumb.height, rgba: thumb.rgba)
    }

    private func uploadComposed(_ key: TextureRef) {
        if cache.contains(key) { return }
        guard let pic = composed?(key) else { return }
        cache.upload(key: key, width: pic.width, height: pic.height, rgba: pic.rgba)
    }

    private func uploadMovieFrame(_ key: TextureRef) {
        guard let frame = movieFrames?(Int(key.a)) else { return }
        let shown = MovieKey(index: frame.index, pts: frame.pts, movie: 0)
        if let last = movieShown[key.a], last == shown && cache.contains(key) {
            return
        }

        let w = frame.width
        let h = frame.height
        YuvConverter.toRgba(frame: frame, rgba: &rgbaBuffer)
        cache.upload(key: key, width: w, height: h, rgba: rgbaBuffer)
        movieShown[key.a] = shown
        _movieUploads += 1
    }

    public func dispose() {}
}
