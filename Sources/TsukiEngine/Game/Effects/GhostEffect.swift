import Foundation
import TsukiCore

/// The `_FADE(40, p, q)` screen effect (knife `game/ghost.rs`; the engine's sub_2E280 / sub_2F910 state and sub_2FC50 draw): each colour channel
/// of the frame is shifted along a slowly swinging direction and the three are overlaid back onto the frame, with the shift amplitude and angle animated
/// every 60 Hz frame. The parameters live in F words: F1100 = screen mode (4 while on), F1120 = p + 127 (brightness), F1121 = q (preset). `_FADE(41)`
/// sets mode 5, which fades the effect out. The PS4 has the same command and the same words (compositing.md 8); the animation is knife's.
public final class GhostEffect {
    /// Capture surface that holds the frame the channels are cut from.
    public static let sourceSurface = 8

    /// Capture surface that holds one shifted channel.
    public static let channelSurface = 9

    /// Capture surface that holds the sum of the three channels.
    public static let sumSurface = 10

    /// Render target of one shifted channel.
    public static let channelTarget: UInt8 = 2

    /// Render target of the channel sum.
    public static let sumTarget: UInt8 = 3

    private var _bright: Float = 0
    private var _latched: Float = 0
    private var _base: Float = 0
    private var _wobble: Float = 0
    private var _frame: Int = 0
    private var _sub: Int = 0
    private var _phase: Int = 0
    private var _curve: Float = 0
    private var _up: Bool = false
    private var _amp: Float = 0
    private var _angle: Float = 0

    /// The screen mode: 4 on (the alpha rises 1/60 a frame), 5 fading out, anything else off.
    public private(set) var mode: Int = 0

    /// The effect's alpha 0..1.
    public private(set) var alpha: Float = 0

    /// True once the phase wrapped (the wobble stops).
    public private(set) var wrapped: Bool = false

    /// True while the effect is on or fading out.
    public var active: Bool { mode == 4 || mode == 5 }

    /// The current shift amplitude in 960-wide pixels (tests).
    public var amplitude: Float { _amp }

    /// The current shift direction in degrees, swinging between -30 and 30 (tests).
    public var angle: Float { _angle }

    public init() {}

    /// Stops the effect at once (a scene start).
    public func reset() {
        mode = 0
        alpha = 0
        wrapped = false
        _up = false
        _frame = 0
        _sub = 0
        _phase = 0
    }

    // the q presets (sub_2E280): (amplitude, wobble, starting amplitude x 100)
    private static func preset(_ q: Int) -> (base: Float, wobble: Float, initVal: Float) {
        switch q {
        case 6, 7, 12:
            return (2.5, 200.0, 50.0)
        case 8:
            return (3.5, 200.0, 70.0)
        case 9:
            return (3.1, 105.0, 62.0)
        case 10:
            return (3.1, 150.0, 62.0)
        case 13:
            return (1.5, 105.0, 30.0)
        default:
            return (3.1, 200.0, 62.0)
        }
    }

    // q = 16: the brightness climbs from p to 0 by 90 / 8 per second
    private static func ramp(_ p: Float, _ frame: Int) -> Float {
        min(p + Float(Int(Float(frame) * 90.0 * 0.125 / 60.0)), 0.0)
    }

    private func resetPhase(_ initVal: Float) {
        _frame = 0
        _sub = 0
        _phase = 0
        _curve = 0
        wrapped = false
        _up = false
        _amp = initVal / 100.0
        _angle = 30.0
    }

    /// FADE(40) (sub_2E3E0(4, reset) -> sub_2E280): `reset` when the screen mode was 0 before, so a repeated FADE(40) only changes the
    /// brightness and preset of the running effect. A non-zero `p` shows it at once.
    public func start(_ p: Int, _ q: Int, _ reset: Bool) {
        mode = 4
        let pRes = Self.preset(q)
        _base = pRes.base
        _wobble = pRes.wobble
        _bright = q == 16 && !reset ? Self.ramp(Float(p), _frame) : Float(p)
        if reset {
            resetPhase(pRes.initVal)
        }
        if p != 0 {
            alpha = 1.0
        }
    }

    /// sub_2E430(mode): FADE(41) (mode 5) and the replay restoring F1100. Mode 4 always restarts the phase.
    public func setMode(_ mode: Int, _ p: Int, _ q: Int) {
        self.mode = mode
        if mode == 4 {
            let pRes = Self.preset(q)
            _base = pRes.base
            _wobble = pRes.wobble
            _bright = Float(p)
            resetPhase(pRes.initVal)
            if p != 0 {
                alpha = 1.0
            }
        }
    }

    /// Marks the phase as wrapped (the load of a running effect, knife game.rs).
    public func markWrapped() {
        wrapped = true
    }

    /// The effect as a restored record had it (knife game.rs restore_with: sub_2E430(F1100) with the restored words, the wobble marked as wrapped): mode 4
    /// with the preset's amplitude and the full alpha, since the effect was on when the record was pushed.
    public func restore(_ p: Int, _ q: Int) {
        setMode(4, p, q)
        alpha = 1.0
        wrapped = true
    }

    /// Runs `frames` 60 Hz steps of sub_2F910 with the brightness word `p` (F1120 - 127) and the preset `q` (F1121).
    public func step(_ frames: Int, _ p: Int, _ q: Int) {
        for _ in 0..<max(1, frames) where active {
            stepOne(p, q)
        }
    }

    private func stepOne(_ p: Int, _ q: Int) {
        if mode == 4 {
            alpha = min(alpha + 0.016667, 1.0)
        } else {
            alpha -= 0.016667
            if alpha <= 0.0 {
                mode = 0
                alpha = 0
            }
        }

        _frame += 1
        let pRes = Self.preset(q)
        _base = pRes.base
        _wobble = pRes.wobble
        _bright = q == 16 ? Self.ramp(Float(p), _frame) : Float(p)
        let tick = _sub >= 5
        _sub += 1
        if !tick {
            return
        }

        _sub = 0
        _phase += 100
        if _phase >= 3334 {
            _phase -= 3333
            wrapped = true
        }

        let folded = _phase > 1666 ? 3333 - _phase : _phase
        _curve = 0.5 - (cos(Float(folded) * Float.pi / 1666.0) * 0.5)
        if !wrapped {
            _curve += _wobble / 100.0 * sin(Float(_phase) * Float.pi / 3333.0)
        }

        _amp = _base * (((_curve * 80.0) + 20.0) / 100.0)
        // the angle swings by 3 degrees a step and reflects off +-30
        if _up {
            _angle += 3.0
            if _angle > 30.0 {
                _angle = 30.0 - (_angle - 30.0)
                _up = false
            }
        } else {
            _angle -= 3.0
            if _angle < -30.0 {
                _angle = -30.0 - (_angle + 30.0)
                _up = true
            }
        }
    }

    /// sub_2FC50 as display-list commands over the composed frame (target 0): the frame is copied into capture surface `sourceSurface`,
    /// each of the three channels (red along the angle, green opposite, blue twice as far opposite) is drawn twice, unshifted then shifted, into target
    /// `channelTarget` through the channel colour, copied, and summed into target `sumTarget` (red replaces, green and blue add),
    /// and that is overlaid onto the frame (effect 22) at the effect's alpha. `transition` is the elapsed fraction of a running
    /// transition (0..1), which eases a brightness change in; nil when none runs.
    public func draw(_ list: DisplayList, _ transition: Float? = nil) {
        if alpha <= 0.0 || !active {
            return
        }

        var bright = _bright
        if let t = transition {
            bright = _latched + (t * (_bright - _latched))
        } else {
            _latched = _bright
        }

        let w: Float = 1920.0
        let h: Float = 1080.0
        let k = _amp * w / 960.0
        let th = _angle * Float.pi / 180.0
        let opp = th + Float.pi
        // red along the angle, green opposite, blue twice as far opposite (y down)
        let offsets: [(x: Float, y: Float)] = [
            (cos(th) * k, -(sin(th) * k)),
            (cos(opp) * k, -(sin(opp) * k)),
            (2.0 * k * cos(opp), -(2.0 * k * sin(opp)))
        ]

        // vertex colours 0xAARRGGBB: ((int)bright + 255) in one channel, built with the exe's wrapping maths
        let v = Int(bright) + 255
        let words: [UInt32] = [
            UInt32(truncatingIfNeeded: (v << 16) - 0x0100_0000),
            UInt32(truncatingIfNeeded: (v << 8) - 0x0100_0000),
            UInt32(truncatingIfNeeded: v - 0x0100_0000)
        ]

        list.add(Self.capture(0, Self.sourceSurface))
        for c in 0..<3 {
            let word = words[c]
            let rgba = ((word >> 16) & 0xFF) | (((word >> 8) & 0xFF) << 8) | ((word & 0xFF) << 16) | (word & 0xFF000000)
            let (ox, oy) = offsets[c]
            let src = TextureRef.capture(Self.sourceSurface)
            list.add(Self.quad(src, 0, 0, w, h, rgba, 0, 0, Self.channelTarget))
            list.add(Self.quad(src, ox, oy, ox + w, oy + h, rgba, 0, 0, Self.channelTarget))
            list.add(Self.capture(Self.channelTarget, Self.channelSurface))
            list.add(Self.quad(TextureRef.capture(Self.channelSurface), 0, 0, w, h, rgba, 0, c == 0 ? 0 : 2, Self.sumTarget))
        }

        list.add(Self.capture(Self.sumTarget, Self.sumSurface))
        let overlay = 0x00FFFFFF | (UInt32(UInt8(clamping: Int(round(alpha * 255.0)))) << 24)
        list.add(Self.quad(TextureRef.capture(Self.sumSurface), 0, 0, w, h, overlay, 22, 1, 0))
    }

    private static func capture(_ target: UInt8, _ surface: Int) -> DrawCommand {
        DrawCommand(kind: .capture, target: target, texture: TextureRef.capture(surface))
    }

    private static func quad(_ tex: TextureRef, _ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, _ rgba: UInt32, _ word: Int, _ blendState: Int, _ target: UInt8) -> DrawCommand {
        DrawCommand(
            kind: .texturedQuad,
            target: target,
            texture: tex,
            v0: Vertex(x: x0, y: y0, u: 0, v: 0, rgba: rgba),
            v1: Vertex(x: x1, y: y0, u: 1, v: 0, rgba: rgba),
            v2: Vertex(x: x0, y: y1, u: 0, v: 1, rgba: rgba),
            v3: Vertex(x: x1, y: y1, u: 1, v: 1, rgba: rgba),
            effectWord: Int16(truncatingIfNeeded: word),
            blendState: UInt8(truncatingIfNeeded: blendState)
        )
    }
}
