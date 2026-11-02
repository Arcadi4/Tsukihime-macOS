import Foundation
import TsukiCore
import TsukiEngine

/// Options of a MovieHost.
public struct MovieHostOptions: Sendable {
    public var virtualTime: Bool
    public var loopPointSeconds: Double
    public var videoThreads: Int
    public var audioLatencySeconds: Double
    public var audioClockTimeoutSeconds: Double

    public init(
        virtualTime: Bool = false,
        loopPointSeconds: Double = MoviePipelineOptions.titleLoopPointSeconds,
        videoThreads: Int = 0,
        audioLatencySeconds: Double = 0.010,
        audioClockTimeoutSeconds: Double = 2.0
    ) {
        self.virtualTime = virtualTime
        self.loopPointSeconds = loopPointSeconds
        self.videoThreads = videoThreads
        self.audioLatencySeconds = audioLatencySeconds
        self.audioClockTimeoutSeconds = audioClockTimeoutSeconds
    }
}

/// A movie that could not be opened or died while playing.
public struct MovieFailure: Sendable {
    public let slot: Int
    public let movieIndex: Int
    public let error: String

    public init(slot: Int, movieIndex: Int, error: Error) {
        self.slot = slot
        self.movieIndex = movieIndex
        self.error = String(describing: error)
    }
}

/// Performs MovieCommands and reports the MovieClock of every open slot.
public final class MovieHost {
    private final class Slot {
        var index: Int = 0
        var player: MoviePlayer?
        var openingThread: Thread?
        var openingResult: Result<MoviePlayer, Error>?
        var isOpening: Bool = false
        var volume: Float = 1.0
        var failed: Bool = false
        var virtualEnded: Bool = false
    }

    private let moviePath: (Int) -> String
    private let mixer: AudioMixer?
    private let options: MovieHostOptions
    private var slots: [Int: Slot] = [:]
    private var clocks: [MovieClock] = []
    private var _failures: [MovieFailure] = []

    public init(moviePath: @escaping (Int) -> String, mixer: AudioMixer? = nil, options: MovieHostOptions? = nil) {
        self.moviePath = moviePath
        self.mixer = mixer
        self.options = options ?? MovieHostOptions()
    }

    public convenience init(data: GameData, mixer: AudioMixer? = nil, options: MovieHostOptions? = nil) {
        self.init(moviePath: { data.movie($0) }, mixer: mixer, options: options)
    }

    deinit {
        dispose()
    }

    public var failures: [MovieFailure] { _failures }
    public var openSlots: Int { slots.count }

    public func player(slot: Int) -> MoviePlayer? {
        guard let s = slots[slot] else { return nil }
        return adopt(number: slot, s: s).player
    }

    public func isOpening(slot: Int) -> Bool {
        guard let s = slots[slot] else { return false }
        return s.isOpening
    }

    public func currentFrame(slot: Int) -> VideoFrame? {
        player(slot: slot)?.current
    }

    public func perform(_ commands: [MovieCommand]) {
        for c in commands {
            perform(c)
        }
    }

    public func perform(_ command: MovieCommand) {
        switch command.op {
        case .open:
            open(command)
        case .stop:
            close(command.slot)
        case .setVolume:
            if let s = slots[command.slot] {
                s.volume = command.volume
                s.player?.setVolume(command.volume)
            }
        }
    }

    /// One 60 Hz step: picks frame of every open movie at timestamp and returns one clock per open slot.
    public func step(timestamp: Int64) -> [MovieClock] {
        clocks.removeAll(keepingCapacity: true)

        let sortedKeys = slots.keys.sorted()
        for number in sortedKeys {
            guard let s = slots[number] else { continue }
            _ = adopt(number: number, s: s)

            if s.isOpening {
                clocks.append(MovieClock(slot: number, movieIndex: s.index, playing: false, ended: false, positionMicroseconds: 0))
            } else if let p = s.player {
                let clock = p.tick(timestamp)
                if let err = p.error, !_failures.contains(where: { $0.slot == number && $0.movieIndex == s.index }) {
                    _failures.append(MovieFailure(slot: number, movieIndex: s.index, error: err))
                }
                clocks.append(clock)
            } else {
                clocks.append(MovieClock(slot: number, movieIndex: s.index, playing: false, ended: true, positionMicroseconds: 0))
            }
        }

        return clocks
    }

    public func dispose() {
        for s in slots.values {
            release(s)
        }
        slots.removeAll()
    }

    private func open(_ c: MovieCommand) {
        close(c.slot)
        let slot = Slot()
        slot.index = c.movieIndex
        slot.volume = c.volume
        slots[c.slot] = slot

        if options.virtualTime {
            slot.virtualEnded = true
            return
        }

        do {
            let path = moviePath(c.movieIndex)
            guard FileManager.default.fileExists(atPath: path) else {
                throw TsukiError.format("movie file does not exist: \(path)")
            }

            let number = c.slot
            let movie = c.movieIndex
            let volume = c.volume
            let m = self.mixer
            let loop = c.loop
            let opts = self.options

            slot.isOpening = true
            let thread = Thread { [weak slot] in
                guard let slot = slot else { return }
                do {
                    let pipeline = MoviePipelineOptions(
                        videoThreads: opts.videoThreads,
                        loop: loop,
                        loopPointSeconds: opts.loopPointSeconds
                    )
                    let playerOpts = MoviePlayerOptions(
                        pipeline: pipeline,
                        audioLatencySeconds: opts.audioLatencySeconds,
                        audioClockTimeoutSeconds: opts.audioClockTimeoutSeconds
                    )
                    let player = try MoviePlayer(slot: number, movieIndex: movie, path: path, volume: volume, mixer: m, options: playerOpts)
                    slot.openingResult = .success(player)
                } catch {
                    slot.openingResult = .failure(error)
                }
                slot.isOpening = false
            }
            slot.openingThread = thread
            thread.name = "tsuki-movie-open-\(c.slot)"
            thread.start()
        } catch {
            slot.failed = true
            _failures.append(MovieFailure(slot: c.slot, movieIndex: c.movieIndex, error: error))
        }
    }

    private func close(_ slotNumber: Int) {
        if let s = slots.removeValue(forKey: slotNumber) {
            release(s)
        }
    }

    private func release(_ s: Slot) {
        s.player?.dispose()
        s.player = nil
        if let res = s.openingResult, case let .success(p) = res {
            p.dispose()
        }
    }

    private func adopt(number: Int, s: Slot) -> Slot {
        if !s.isOpening, let res = s.openingResult {
            s.openingResult = nil
            s.openingThread = nil
            switch res {
            case let .success(p):
                s.player = p
                p.setVolume(s.volume)
            case let .failure(err):
                s.failed = true
                _failures.append(MovieFailure(slot: number, movieIndex: s.index, error: err))
            }
        }
        return s
    }
}
