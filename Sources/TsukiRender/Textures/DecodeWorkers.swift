import Foundation
import TsukiCore

/// Writes one tile's RGBA8 pixels into `rgba`.
public typealias TileDecode = @Sendable (UnsafeMutableRawBufferPointer) throws -> Void

/// One tile to decode.
public struct DecodeJob: @unchecked Sendable {
    public let key: TextureRef
    public let width: Int
    public let height: Int
    public let decode: TileDecode
    public let background: Bool

    public init(key: TextureRef, width: Int, height: Int, decode: @escaping TileDecode, background: Bool = false) {
        self.key = key
        self.width = width
        self.height = height
        self.decode = decode
        self.background = background
    }
}

/// A fixed set of decode threads feeding an `UploadScheduler`.
public final class DecodeWorkers: @unchecked Sendable {
    private let condition = NSCondition()
    private var jobs: [DecodeJob] = []
    private var backgroundJobs: [TextureRef: DecodeJob] = [:]
    private var backgroundOrder: [TextureRef] = []

    private var threads: [Thread] = []
    private let scheduler: UploadScheduler
    private var running = true
    private var inFlight = 0
    private var _decoded: Int64 = 0
    private var _fault: Error?

    public let workerCount: Int

    public init(scheduler: UploadScheduler, workers: Int = 0) {
        self.scheduler = scheduler
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let count = workers <= 0 ? min(8, max(1, cores)) : min(cores, max(1, workers))
        self.workerCount = count

        for i in 0..<count {
            let thread = Thread { [weak self] in
                self?.runLoop()
            }
            thread.name = "tsuki-tile-decode-\(i)"
            thread.qualityOfService = .utility
            threads.append(thread)
            thread.start()
        }
    }

    public var pending: Int {
        condition.lock()
        defer { condition.unlock() }
        return jobs.count + backgroundJobs.count + inFlight
    }

    public var decoded: Int64 {
        condition.lock()
        defer { condition.unlock() }
        return _decoded
    }

    public var fault: Error? {
        condition.lock()
        defer { condition.unlock() }
        return _fault
    }

    public func enqueue(_ job: DecodeJob) {
        condition.lock()
        jobs.append(job)
        condition.signal()
        condition.unlock()
    }

    public func enqueueBackground(_ job: DecodeJob) {
        condition.lock()
        if backgroundJobs[job.key] == nil {
            backgroundJobs[job.key] = job
            backgroundOrder.append(job.key)
            condition.signal()
        }
        condition.unlock()
    }

    public func promote(_ key: TextureRef) {
        condition.lock()
        if let job = backgroundJobs.removeValue(forKey: key) {
            jobs.append(DecodeJob(key: job.key, width: job.width, height: job.height, decode: job.decode, background: false))
            condition.signal()
        }
        condition.unlock()
        scheduler.promote(key)
    }

    public func stop() {
        condition.lock()
        running = false
        condition.broadcast()
        condition.unlock()

        for t in threads {
            while !t.isFinished {
                Thread.sleep(forTimeInterval: 0.005)
            }
        }
        threads.removeAll()
    }

    deinit {
        stop()
    }

    private func runLoop() {
        while true {
            var job: DecodeJob?
            condition.lock()
            while running && jobs.isEmpty && backgroundJobs.isEmpty {
                condition.wait()
            }
            if !running {
                condition.unlock()
                return
            }

            if !jobs.isEmpty {
                job = jobs.removeFirst()
            } else if !backgroundOrder.isEmpty {
                let nextKey = backgroundOrder.removeFirst()
                job = backgroundJobs.removeValue(forKey: nextKey)
            }

            guard let currentJob = job else {
                condition.unlock()
                continue
            }

            inFlight += 1
            condition.unlock()

            var buf: StagingBuffer?
            do {
                let buffer = scheduler.pool.rent(size: currentJob.width * currentJob.height * 4)
                buf = buffer

                try buffer.withUnsafeMutableBytes { ptr in
                    try currentJob.decode(ptr)
                }

                var graded = false
                if let grader = scheduler.cache.grader, TileGrader.isGraded(currentJob.key) {
                    buffer.withUnsafeMutableBytes { ptr in
                        let bytePtr = ptr.bindMemory(to: UInt8.self)
                        grader.apply(currentJob.key, bytePtr)
                    }
                    graded = true
                }

                let tile = DecodedTile(
                    key: currentJob.key,
                    width: currentJob.width,
                    height: currentJob.height,
                    pixels: buffer,
                    graded: graded
                )

                if currentJob.background {
                    scheduler.enqueueBackground(tile)
                } else {
                    scheduler.enqueue(tile)
                }

                // Buffer will be returned by scheduler once uploaded
                buf = nil

                condition.lock()
                _decoded += 1
                inFlight -= 1
                condition.unlock()
            } catch {
                if let b = buf {
                    scheduler.pool.returnBuffer(b)
                }
                condition.lock()
                if _fault == nil {
                    _fault = error
                }
                inFlight -= 1
                condition.unlock()
            }
        }
    }
}
