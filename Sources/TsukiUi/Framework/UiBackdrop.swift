import Foundation

/// The shared submenu backdrop (knife `MenuBg`, sub_4B880).
public final class UiBackdrop {
    private static let strips: [(low: Bool, k: Int, alpha: Float, cx: Float, y0: Float, dy: Float)] = [
        (true, 0, 64.0, 960.0, 1080.0, -198.0), (true, 1, 96.0, 960.0, 1080.0, -160.5), (true, 2, 160.0, 960.0, 1080.0, -127.5), (true, 3, 224.0, 960.0, 1080.0, -82.5),
        (false, 0, 64.0, 960.0, 0.0, 155.25), (false, 1, 96.0, 849.75, 0.0, 117.75), (false, 2, 128.0, 960.0, 0.0, 84.75), (false, 3, 160.0, 829.5, 0.0, 39.75),
    ]

    private let _rng: UiRandom
    private var _sparks: [Spark] = []
    private var _acc: Float = 0

    public init(_ rng: UiRandom) {
        self._rng = rng
    }

    /// The backdrop alpha.
    public private(set) var a: Float = 0
    public var A: Float { a }

    /// The alpha step per frame (sub_49630).
    public private(set) var speed: Float = 0
    public var Speed: Float { speed }

    /// The strip animation 0..1.
    public private(set) var t: Float = 0
    public var T: Float { t }

    /// The strip animation step per frame.
    public private(set) var tSpeed: Float = 0
    public var TSpeed: Float { tSpeed }

    /// A fade in pauses the title movie, a fade out resumes it.
    public private(set) var moviePaused: Bool = false
    public var MoviePaused: Bool { moviePaused }

    /// True while any of it shows.
    public var visible: Bool { a > 0.0 }
    public var Visible: Bool { visible }

    /// Starts fading in (speed above 0) or out (below 0).
    public func fade(_ speed: Float) {
        if speed == 0.0 {
            a = self.speed < 0.0 ? 0.0 : self.speed > 0.0 ? 1.0 : a
        }
        self.speed = speed
        if speed > 0.0 {
            tSpeed = 1.0 / 60.0
            moviePaused = true
        } else if speed < 0.0 {
            tSpeed = speed
            moviePaused = false
        }
    }
    public func Fade(_ speed: Float) { fade(speed) }

    /// Hides the backdrop at once and stops its fade.
    public func reset() {
        a = 0.0
        speed = 0.0
        t = 0.0
        tSpeed = 0.0
        moviePaused = false
        _acc = 0.0
        _sparks.removeAll()
    }
    public func Reset() { reset() }

    /// Steps `frames` 60 Hz frames.
    public func update(_ frames: Float = 1.0) {
        a = min(max(a + (speed * frames), 0.0), 1.0)
        t = min(max(t + (tSpeed * frames), 0.0), 1.0)
        if a <= 0.0 {
            _sparks.removeAll()
            return
        }

        _acc += frames
        while _acc >= 1.0 {
            _acc -= 1.0
            if _sparks.count >= 100 {
                continue
            }

            let scale = (_rng.next() * 0.2) + 0.1
            let life = floor((_rng.next() * 150.0) + 120.0)
            let alpha = _rng.range(0.25, 0.5)
            let x = _rng.next() * 960.0
            let y = _rng.next() * 540.0
            let vy = (_rng.next() * 0.36667) + 0.13333
            _sparks.append(Spark(scale: scale, life: life, age: 0.0, vx: vy * (480.0 - x) / (y + 75.0), vy: vy, alpha: alpha, x: x, y: y))
        }

        for i in 0..<_sparks.count {
            _sparks[i].x += _sparks[i].vx * frames
            _sparks[i].y -= _sparks[i].vy * frames
            _sparks[i].age += frames
        }

        _sparks.removeAll(where: { $0.age > $0.life })
    }
    public func Update(_ frames: Float = 1.0) { update(frames) }

    /// The strip offset factor.
    public var slide: Float {
        tSpeed >= 0.0 ? 1.0 - ((1.0 - t) * (1.0 - t)) : 1.0
    }
    public var Slide: Float { slide }

    /// The strip alpha factor.
    public var stripAlpha: Float {
        1.0 - ((1.0 - t) * (1.0 - t))
    }
    public var StripAlpha: Float { stripAlpha }

    /// Draws the backdrop.
    public func draw(_ p: UiPainter) {
        if !visible {
            return
        }

        p.sprite(UiSheets.backdrop, UiMetrics.screen, alpha: a)
        let k = slide
        let sa = stripAlpha
        for (low, idx, alpha, cx, y0, dy) in Self.strips {
            let sheet = low ? UiSheets.stripLow(idx) : UiSheets.stripHigh(idx)
            let (w, h) = p.sizeOf(sheet)
            if w == 0 {
                continue
            }
            let cy = y0 + (dy * k)
            p.sprite(sheet, RectF(0, 0, Float(w), Float(h)), RectF(cx - (Float(w) / 2.0), cy - (Float(h) / 2.0), Float(w), Float(h)), alpha: sa * alpha / 255.0)
        }

        for s in _sparks {
            let (kk, dim) = Self.phase(s.age, s.life)
            let size = s.scale * kk * 80.0
            p.sprite(UiSheets.spark, RectF(0, 0, 80, 80), RectF(s.x * 2.0, s.y * 2.0, size, size), alpha: s.alpha * dim * a)
        }
    }
    public func Draw(_ p: UiPainter) { draw(p) }

    /// Fade-in / fade-out over 60 frames at both ends of a particle's life.
    public static func phase(_ age: Float, _ life: Float) -> (k: Float, dim: Float) {
        let ai = Int(age)
        if ai <= 59 {
            return (age / 60.0, 1.0)
        }
        let left = life - age
        if left > 59.0 {
            return (1.0, 1.0)
        }
        return (max(left, 0.0) / 60.0, (ai & 2) == 0 ? 0.7 : 1.0)
    }
    public static func Phase(_ age: Float, _ life: Float) -> (k: Float, dim: Float) {
        phase(age, life)
    }

    private struct Spark {
        var scale: Float
        var life: Float
        var age: Float
        var vx: Float
        var vy: Float
        var alpha: Float
        var x: Float
        var y: Float
    }
}
