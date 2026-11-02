import Foundation
import TsukiCore

/// The record of the movie system state (state 8, VA 0x5E530; wait_model.md 11.2).
public final class MovieRecord {
    /// +0x18: the language-neutral id passed to `_TOMP`.
    public var id: Int = 0

    /// +0x30: phase 0..7.
    public var phase: Int = 0

    /// +0x34: frames since playback started.
    public var frame: Int = 0

    /// +0x3C: picture alpha.
    public var alpha: Float = 0

    /// +0x40: fade-out step after a skip.
    public var fade: Float = 0

    /// +0x48: skip requested in phase 3.
    public var skip: Int = 0

    /// +0x4C: second fade.
    public var aux: Float = 0

    /// 0xDF293C: enter countdown; the update does nothing while it is above 1.
    public var countdown: Int = 20

    /// The movie table index after the language remap.
    public var tableIndex: Int = 0

    /// The ADV mode word 0x17DB230 the state's enter callback saved (0xDF2998); the exit restores its latched-skip bit (wait_model.md 9).
    public var savedModeWord: Int = 0

    /// The state ended; the exit callback ran.
    public var done: Bool = false

    public init() {}
}

extension GameHost {
    private static let thirdStep: Float = 0.0104166679084301

    func initMovie() {}

    func resetMovie() {
        movieRec = nil
        movieOut.removeAll()
        clocks.removeAll()
    }

    /// True while a script movie plays (from `_TOMP` to the exit of the movie state).
    public var movieActive: Bool { movieRec != nil && !movieRec!.done }

    /// The movie state, or nil.
    public var movieState: MovieRecord? { movieRec }

    /// The picture alpha of the movie (0 when none).
    public var movieAlpha: Float { movieActive ? movieRec!.alpha : 0 }

    /// Removes and returns the movie commands produced since the last call.
    public func takeMovieCommands() -> [MovieCommand] {
        let a = movieOut
        movieOut.removeAll()
        return a
    }

    /// The clocks the movie host reported for this frame (call before `step`).
    public func setMovieClocks(_ clocks: [MovieClock]) {
        self.clocks.removeAll()
        for c in clocks {
            self.clocks[c.slot] = c
        }
    }

    func cmdTomp(_ st: Statement) -> StepResult {
        let a = StageArgs(st)
        let id = ObjectParser.partialInt(ByteSpan([UInt8](a.str(0).utf8))) ?? 0
        if id != 7 || !skipScene {
            if id != 7 {
                endSceneSkip()
            }

            let saved = modeWord
            modeWord &= ~2
            setF(1103, 1)
            setF(36, 1)
            let index = MovieTable.remap(id, language)
            let rec = MovieRecord()
            rec.id = id
            rec.phase = 0
            rec.tableIndex = index
            rec.savedModeWord = saved
            movieRec = rec

            let volume = min(max(Float(config.musicVolumeCopy) / 100.0, 0.0), 1.0)
            movieOut.append(MovieCommand.open(MovieSlots.fullScreen, index, loop: false, volume: volume))
            movieStarted?(id)
        }

        return StepResult.yield
    }

    func cmdTomw(_ st: Statement) -> StepResult {
        f(36) != 0 ? StepResult.yieldAt(st.position) : StepResult.yield
    }

    private static let movieSeenBit: [Int: Int] = [4: 2, 5: 0, 6: 1, 35: 3, 36: 4, 37: 5]

    private static func movieParams(_ id: Int, _ lang: Language) -> (fadeIn: Float, fadeOutStart: Float, fadeOut: Float) {
        let slow: Float = 0.0208333358168602
        switch id {
        case 4:
            return (1.0, lang == .en ? 23340.0 : 23040.0, 1.0)
        case 5:
            return (1.0, 6420.0, 1.0)
        case 6:
            return (1.0, 6300.0, 1.0)
        case 7:
            return (slow, 312.0, slow)
        case 13:
            return (1.0, 540.0, 1.0)
        case 35:
            return (1.0, 18960.0, 1.0)
        case 36:
            return (1.0, 8880.0, 1.0)
        case 37:
            return (1.0, 15240.0, 1.0)
        case 39...45:
            return (1.0, 618.0, 1.0)
        default:
            return (slow, 420.0, 1.0)
        }
    }

    /// True when the movie can be skipped (ids 4, 5, 6, 35, 36, 37 only after their movie_seen bit is set).
    public func movieSkippable(_ id: Int) -> Bool {
        guard let bit = Self.movieSeenBit[id] else { return true }
        return ((vars.getG(5) >> bit) & 1) != 0
    }

    func updateMovie(_ input: InputFrame, step: Int) {
        guard let r = movieRec, !r.done else { return }

        if r.countdown > 1 {
            r.countdown -= 1
            return
        }

        var ready = true
        var playing = false
        if options.virtualMovies {
            playing = r.frame < 100
        } else if let clock = clocks[MovieSlots.fullScreen] {
            ready = clock.playing || !clock.playing || r.phase != 1
            playing = clock.playing
        } else {
            ready = false
            playing = false
        }

        let skipPressed = input.pressed.contains(.cancel) || input.pressed.contains(.options)
        let skippable = (r.id >= 4 && r.id <= 37) ? movieSkippable(r.id) : true
        let (fin, fstart, fout) = Self.movieParams(r.id, language)
        let d = 1
        r.frame += options.virtualMovies ? (60 * d) : d
        let fd = Float(d)
        var action = ""

        if r.phase == 0 {
            r.phase = 1
        }

        if r.phase == 1 {
            if !ready { return }
            r.frame = 0
            r.alpha = 0
            r.aux = 0
            r.skip = 0
            r.phase = 2
        }

        if r.phase == 2 {
            var a = (fd * fin) + r.alpha
            a = 1.0 < a ? 1.0 : a
            r.alpha = a
            if a >= 0.5 {
                let x = (fd * Self.thirdStep) + r.aux
                r.aux = x > 1.0 ? 1.0 : x
            }

            if r.frame >= 60 {
                r.phase = 3
            }
            return
        }

        if r.phase == 7 {
            let x = (fd * Self.thirdStep) + r.aux
            r.aux = 1.0 < x ? 1.0 : x
            let a = r.alpha - (fd * r.fade)
            r.alpha = a
            if 0.0 >= a {
                r.alpha = 0
                r.phase = 6
                action = "stop"
            }

            if action.isEmpty { return }
            movieOut.append(MovieCommand.stop(MovieSlots.fullScreen))
            return
        }

        if r.phase == 3 {
            if r.id == 13 {
                if r.frame < 210 { return }
                r.phase = 4
            } else if r.id == 4 {
                let lim: Float = language == .en ? 21900.0 : 21600.0
                if !(Float(r.frame) >= lim) {
                    if !(skippable && skipPressed) { return }
                    r.skip = 1
                }
                r.phase = 4
            } else {
                r.phase = 4
            }
        }

        if r.phase == 4 {
            if r.id == 13 && r.frame < 330 { return }
            r.phase = 5
        }

        if r.phase == 5 {
            if playing {
                if skippable && (r.skip != 0 || skipPressed) {
                    r.frame = Int(fstart)
                    r.phase = 7
                    r.fade = 1.0 / 60.0
                    return
                }
            } else {
                r.phase = 6
            }
        }

        if r.phase == 5 || r.phase == 6 {
            let x = (fd * Self.thirdStep) + r.aux
            r.aux = 1.0 < x ? 1.0 : x
            if Float(r.frame) >= fstart {
                let a = r.alpha - (fd * fout)
                r.alpha = 0.0 > a ? 0.0 : a
            }

            if !playing {
                endMovie(r)
            }
        }
    }

    func endMovie(_ r: MovieRecord) {
        r.done = true
        setF(36, 0)
        modeWord = (modeWord & ~2) | (r.savedModeWord & 2)
        if let bit = Self.movieSeenBit[r.id] {
            vars.setG(5, vars.getG(5) | UInt16(1 << bit))
        }

        movieOut.append(MovieCommand.stop(MovieSlots.fullScreen))
        movieEnded?(r.id)
    }
}
