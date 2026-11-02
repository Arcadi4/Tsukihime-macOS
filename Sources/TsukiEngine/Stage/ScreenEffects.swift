import Foundation

/// `_MSQK`: the message-window quake (globals 0xDF0894..0xDF08A8; docs/formats/quake.md 6). Port of `tsuki.quake.MessageQuake`.
/// The offsets (`x`, `y`) are added by the HUD (0x53CF0) to the message window and text positions, in 640 x 448 UI
/// canvas units.
public final class MessageQuake {
    private var dur: Float = 0
    private var t: Float = 0
    private var ampY: Float = 0
    private var ampX: Float = 0

    /// Offset x (0xDF08A4).
    public private(set) var x: Float = 0

    /// Offset y (0xDF08A8).
    public private(set) var y: Float = 0

    /// True while a quake runs (duration above 0).
    public var active: Bool { dur > 0 }

    public init() {}

    /// 0x962D3 -> 0x53BE0(ms, a2, a1): `_MSQK(ms = 1000, a1 = 5, a2 = 5)`.
    public func start(ms: Int, a1: Int, a2: Int) {
        dur = UInt32(bitPattern: Int32(truncatingIfNeeded: ms)) < 10001 ? Float(ms) : 1000
        t = 0
        ampY = Float(a2) * 448.0 / 720.0
        ampX = Float(a1) * 640.0 / 1280.0
        x = 0
        y = 0
    }

    /// Top of 0x57980 (before the layer loop; also runs while the layer update is frozen): two `rand()` calls per active frame, x first.
    /// `arg` is the update argument and `fpu` the frames per update (both 1 at 60 Hz).
    public func update(rng: Ps4Rand, arg: Int = 1, fpu: Int = 1) {
        guard dur > 0 else { return }

        t = ((Float(arg * fpu) * 1000.0) / 60.0) + t
        if t >= dur {
            dur = 0
            x = 0
            y = 0
            return
        }

        x = Ps4Math.rndRange(rng, -ampX, ampX)
        y = Ps4Math.rndRange(rng, -ampY, ampY)
    }

    /// 0x57590 zeroes all six globals: a running quake is cancelled (ADV-mode entry, scan load).
    public func reset() {
        dur = 0
        t = 0
        ampY = 0
        ampX = 0
        x = 0
        y = 0
    }
}

/// `_SHOK`: the screen shock, screen-effect kind 1 (globals 0xDF07B4.., 0xDF0818..; docs/formats/quake.md 7). A damped sine without
/// `rand()`. `x` and `y` (0xDF0720 / 0xDF0724, canvas units) are added to every scene layer except pictures
/// with catalog draw_flags bit 1, and not to the HUD. Port of `tsuki.quake.ScreenShock`.
public final class ScreenShock {
    private var kindVal: Int = 0
    private var remainingVal: Int = 0
    private var period: Float = 0
    private var count: Float = 0
    private var ax: Float = 0
    private var ay: Float = 0
    private var phase: Float = 0
    private var amp: Float = 0
    private var delayVal: Int = 0
    private var pending: (kind: Int, ax: Int, ay: Int, ms: Int, n: Int) = (0, 0, 0, 0, 0)

    /// Output x (0xDF0720).
    public private(set) var x: Float = 0

    /// Output y (0xDF0724).
    public private(set) var y: Float = 0

    /// Start delay remaining in ms (0xDF0818).
    public var delay: Int { delayVal }

    /// Frames remaining (0xDF07D4); negative = endless.
    public var remaining: Int { remainingVal }

    /// Screen-effect kind (0xDF07B4): 1 = shock, -1 after `_SHAF`, 0 idle.
    public var kind: Int { kindVal }

    public init() {}

    /// 0x438C0(1, ax, ay, ms, n, delay): `_SHOK(ax, ay, ms = 300, n = 3, delay = 0)` (values already as i16).
    public func start(ax: Int, ay: Int, ms: Int, n: Int, delay: Int = 0) {
        delayVal = delay
        if delay > 0 {
            pending = (1, ax, ay, ms, n)
            return
        }

        begin(kind: 1, ax: ax, ay: ay, ms: ms, n: n)
    }

    private func begin(kind: Int, ax: Int, ay: Int, ms: Int, n: Int) {
        kindVal = kind
        phase = 0
        amp = 1
        let t = (Float(ms) * 3.0) / 50.0
        remainingVal = Int(StageMath.cdiv(Int64(StageMath.i32(3 * Int64(StageMath.i32(Int64(ms) * Int64(n))))), 50))
        period = t == 0 ? 1 : t
        count = Float(n >= 2 ? n : 1)
        self.ax = Float(ax)
        self.ay = Float(ay)
    }

    /// `_SHAF()` (0x80AE0 -> 0x42DC0(0,0,0,0)): kind -1, remaining 0; offsets are 0 from the next update. A pending delayed shock is not cancelled.
    public func stop() {
        kindVal = -1
        remainingVal = 0
    }

    /// 0x57590 zeroes only the outputs (VA 0x578BB / 0x578C5); the effect state is not reset.
    public func advStart() {
        x = 0
        y = 0
    }

    /// The shock term of a scene layer's draw (VA 0x51808..0x51833): (x, y), or (0, 0) for a picture with catalog draw_flags bit 1.
    public func layerOffset(noShock: Bool = false) -> (x: Float, y: Float) {
        noShock ? (0, 0) : (x, y)
    }

    /// 0x439D0(dt), kind 1 only (other kinds belong to other commands).
    public func update(dt: Int) {
        if delayVal > 0 {
            let v = delayVal - Int(StageMath.cdiv(Int64(dt) * 1000, 60))
            delayVal = v > 0 ? v : 0
            if v <= 0 {
                begin(kind: pending.kind, ax: pending.ax, ay: pending.ay, ms: pending.ms, n: pending.n)
            }
        }

        if remainingVal == 0 {
            x = 0
            y = 0
            return
        }

        if kindVal != 1 {
            return
        }

        if remainingVal > 0 {
            let v = remainingVal - dt
            remainingVal = v > 0 ? v : 0
            if v <= 0 {
                kindVal = 0
                period = 0
                ax = 0
                ay = 0
                phase = 0
                amp = 0
                x = 0
                y = 0
                return
            }
        }

        let fr = Float(dt)
        let dph = (fr * Ps4Math.twoPi) / period
        let dam = (fr / period) / count
        phase = dph + phase
        let a = amp - dam
        amp = 0 > a ? 0 : a
        let s = Ps4Math.sinf(phase)
        x = (((s * ax) * amp) * 640.0) / 480.0
        y = (((amp * (s * ay)) * 480.0) / 360.0)
    }
}
