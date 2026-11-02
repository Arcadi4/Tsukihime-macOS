import Foundation
import TsukiCore

/// The mode of the focus-line / falling-note effect (`_FCLN`, `_FCSP`).
public enum FocusMode: UInt8, Sendable {
    /// Off.
    case off = 0

    /// Fading in.
    case fadingIn = 1

    /// On.
    case on = 2

    /// Fading out.
    case fadingOut = 3
}

/// The `_FCLN` screen effects (knife `game/focus.rs`; the engine's sub_86470 start / stop, sub_86850 step, sub_87A90 draw): effects 4..33 are
/// manga focus lines (up to 400 strips radiating from a centre, re-rolled every interval, keyed by up to four timed keyframes per effect), effects 1..3
/// are falling musical notes (50 sprites with their own drift). The keyframes come from the eboot (`EffectTables`, 118 of 120 equal knife's);
/// the random numbers are the engine's shared libc `rand()` (`Ps4Rand`), as on the console.
public final class FocusEffect {
    private static let lineSlots = 400
    private static let noteSlots = 50
    private static let randScale: Float = 1.0 / 1073741824.0

    // knife focus.rs SINGLE: effects (- 4) that stay on their first keyframe (a bit mask from the Switch exe; plain layout data)
    private static let singleKeyEffects: UInt32 = 0x2930_3FFB

    private let tables: (any EffectTables)?
    private let rng: Ps4Rand
    private var slots: [Slot] = [Slot](repeating: Slot(), count: lineSlots)
    private var rate: Float = 1.0
    private var chance: Float = 0.05
    private var clock: Int16 = 0
    private var since: Int16 = 0

    /// 0 off, 1 fading in, 2 on, 3 fading out.
    public private(set) var mode: FocusMode = .off

    /// The running effect id: 1..3 falling notes, 4..33 focus lines, 0 none.
    public private(set) var effect: Int = 0

    /// The fade level 0..1.
    public private(set) var level: Float = 0

    /// True while the effect runs in any mode.
    public var active: Bool { mode != .off }

    /// The live particles: lines (effects 4..33) or notes (1..3).
    public var particleCount: Int { slots.filter { $0.kind >= 0 }.count }

    /// The keyframe the last roll of the lines used (0..3).
    public var currentKey: Int { slots[0].key }

    /// Creates the effect over the eboot tables (nil: the lines have no keyframes and stay empty) and the shared random generator.
    public init(tables: (any EffectTables)?, rng: Ps4Rand) {
        self.tables = tables
        self.rng = rng
    }

    /// Stops everything (a scene start).
    public func reset() {
        mode = .off
        effect = 0
        level = 0
        rate = 1.0
        chance = 0.05
        clock = 0
        since = 0
        for i in 0..<slots.count {
            slots[i] = Slot()
        }
    }

    /// sub_86470(effect, frames): starts `effect` (frames 0) or stops it fading out over `frames`. The effect already on keeps running.
    public func start(_ effect: Int, _ frames: Int) {
        let r = frames > 0 ? 1.0 / Float(frames) : 1.0
        switch effect {
        case 0 where frames <= 0:
            level = 0
            mode = .off
            rate = 1.0
        case 0:
            mode = .fadingOut
            rate = r
        case 4...33:
            if mode == .on && self.effect == effect {
                return
            }
            mode = .fadingIn
            self.effect = effect
            level = 0
            rate = r
            for i in 0..<slots.count {
                slots[i] = Slot()
            }
            clock = 0
            since = 0
        case 1...3:
            mode = .fadingIn
            self.effect = effect
            level = 0
            rate = r
            for i in 0..<Self.noteSlots {
                slots[i].kind = -1
            }
            chance = effect == 3 ? 0.1 : 0.05
        default:
            break
        }
    }

    /// sub_86850 for `frames` frames (1, or more after a dropped frame): the fade, then the particles.
    public func step(_ frames: Int) {
        let n = Int16(truncatingIfNeeded: max(1, frames))
        let nf = Float(n)
        switch mode {
        case .fadingOut:
            level -= rate * nf
            if level < 0.0 {
                level = 0
                mode = .off
                return
            }
        case .fadingIn:
            level += rate * nf
            if level > 1.0 {
                level = 1.0
                mode = .on
            }
        case .off:
            return
        default:
            break
        }

        switch effect {
        case 4...33:
            stepLines(n)
        case 1...3:
            stepNotes(n)
        default:
            break
        }
    }

    private func stepLines(_ n: Int16) {
        guard let tables = tables else { return }

        let idx = effect - 4
        clock = Int16(truncatingIfNeeded: Int(clock) + Int(n))
        if clock < 0 {
            clock = 180
        }

        since = Int16(truncatingIfNeeded: Int(since) + Int(n))
        let t = Float(clock) * 1000.0 / 60.0
        let k0 = tables.focusKey(idx, 0)
        let k1 = tables.focusKey(idx, 1)
        let k2 = tables.focusKey(idx, 2)
        let k3 = tables.focusKey(idx, 3)
        let t1 = Float(k1.timeMs)
        let key: Int
        let next: Float
        if t < Float(k0.timeMs) || (((Self.singleKeyEffects >> idx) & 1) == 0 && t >= t1) {
            let t2 = Float(k2.timeMs)
            if t >= t1 && (idx != 2 || t < t2) {
                key = 1
                next = Float(k2.timeMs)
            } else if t >= t2 {
                key = 2
                next = Float(k3.timeMs)
            } else {
                key = 0
                next = Float(k1.timeMs)
            }
        } else {
            key = 0
            next = Float(k1.timeMs)
        }

        let kf = tables.focusKey(idx, key)
        var alpha = Float(kf.alpha)
        if next >= 0 {
            let following = tables.focusKey(idx, key + 1)
            alpha += (t - Float(kf.timeMs)) * Float(following.alpha - kf.alpha) / (next - Float(kf.timeMs))
        }

        if Float(since) * 1000.0 / 60.0 < Float(kf.rerollMs) {
            return
        }

        since = 0
        let span = max(1, abs(kf.countMax - kf.countMin))
        var count = min(Int(rng.next() % Int32(span)) + kf.countMin, Self.lineSlots)
        if effect <= 8 {
            count /= 2
        }

        count = max(0, count)
        for i in 0..<count {
            slots[i].key = key
            rollLine(i, idx)
            slots[i].alpha = alpha / 255.0
        }

        for i in count..<Self.lineSlots {
            slots[i] = Slot()
        }
    }

    private func rollLine(_ i: Int, _ idx: Int) {
        guard let tables = tables else { return }
        let kf = tables.focusKey(idx, slots[i].key)
        let angle = Int16(truncatingIfNeeded: Int((rng.next() % 65536)) - 32768)
        let lo = min(kf.radiusMin, kf.radiusMax)
        let span = max(1, abs(kf.radiusMax - kf.radiusMin))
        let r = Float(Int(rng.next() % Int32(span)) + lo) * 0.7
        let th = radians(angle)
        var s = slots[i]
        s.kind = Int16(idx + 4)
        s.angle = angle
        s.x = ((r * cos(th)) + Float(kf.centreX)) * 640.0 / 1280.0
        s.y = ((r * sin(th)) + Float(kf.centreY)) * 448.0 / 720.0
        slots[i] = s
    }

    private func stepNotes(_ n: Int16) {
        if (Float(rng.next()) * Self.randScale) < chance {
            for i in 0..<Self.noteSlots {
                if slots[i].kind < 0 {
                    dropNote(i, Int(rng.next() % 3))
                    break
                }
            }
        }

        let notes = tables?.focusNotes
        let nf = Float(n)
        for i in 0..<Self.noteSlots {
            if slots[i].kind < 0 {
                continue
            }

            var s = slots[i]
            if s.total >= 1 {
                var t = Int(s.tick) + Int(n)
                while t >= Int(s.total) {
                    t -= Int(s.total)
                }
                s.tick = Int16(t)
                s.frame = Int16(t / Int(s.step))
            }

            s.vy += s.ay * nf
            s.vx += s.ax * nf
            s.x += s.vx * nf
            s.y += s.vy * nf
            if let notes = notes, Int(s.kind) < notes.count && s.y > Float(notes[min(Int(s.kind), notes.count - 1)].floor) {
                s.kind = -1
            }

            slots[i] = s
        }
    }

    private func dropNote(_ i: Int, _ kind: Int) {
        guard let tables = tables, kind < tables.focusNotes.count else { return }
        let d = tables.focusNotes[kind]
        let total = d.frames * d.step
        let tick = Int16(rng.next() % Int32(max(1, total)))
        func jitter() -> Float { Float(Int(rng.next() % 16) - 8) }
        let jx = jitter(), jy = jitter(), jay = jitter()
        let px = Float(Int(rng.next() % 801) - 80)
        let py = Float(Int(rng.next() % 101) - 130)
        slots[i] = Slot(
            kind: Int16(kind),
            tick: tick,
            total: Int16(total),
            step: Int16(d.step),
            frame: Int16(Int(tick) / max(1, d.step)),
            key: 0,
            angle: 0,
            x: px,
            y: py,
            alpha: 1.0,
            vx: d.vx + (d.jitterX * jx),
            vy: d.vy + (d.jitterY * jy),
            ax: 0,
            ay: d.accel * jay
        )
    }

    private func radians(_ a: Int16) -> Float {
        Float(a) * Float.pi / 32768.0
    }

    private static func lineUv(_ idx: Int) -> (u: Float, v: Float) {
        switch idx {
        case 2: return (0, 10)
        case 3: return (0, 40)
        case 6: return (0, 30)
        case 14: return (850, 120)
        default: return (0, 0)
        }
    }

    private static func lineScale(_ kind: Int16, _ angle: Int16) -> (matched: Bool, sx: Float, sy: Float) {
        let native: Float = 448.0 / 1080.0
        let u = UInt16(bitPattern: angle)
        let near = UInt16(truncatingIfNeeded: Int(u) + 7999) <= 0x3E7E
        switch kind {
        case 7:
            return (true, 2.0 / 3.0, native / 2.0)
        case 8 where near:
            return (true, 1.0 / 6.0, native)
        case 8 where UInt16(truncatingIfNeeded: Int(u) + 27000) >= 0xD2F1:
            return (true, 0.4, native)
        case 9, 10:
            return (true, 0.5, native)
        case 13, 19:
            return (true, 0.4, native)
        case 15...17:
            return (true, 0.6, native)
        case 18 where UInt16(truncatingIfNeeded: Int(u) + 21000) >= 0xA411:
            return (true, 0.43333334, native)
        case 20 where near:
            return (true, 0.4, native)
        case 21...23 where u >= 0xE0C1:
            return (true, 0.4, native)
        case 26 where near, 27 where near:
            return (true, 0.6, native)
        case 28...31:
            return (true, 0.5333333, native)
        case 32 where UInt16(truncatingIfNeeded: Int(u) + 27000) >= 0xD2F1:
            return (true, 0.5333333, native)
        default:
            return (false, 0, 0)
        }
    }

    /// sub_87A90(2): appends the lines (alpha-blended strips of the FocusLine texture) or the notes (sprites of the three FallNote sheets) to
    /// `list`. Nothing when the effect is off. Sheets are whole-sheet UI tiles of EFFECT_PARTS.
    public func draw(_ list: DisplayList) {
        guard active else { return }

        let kx: Float = 1920.0 / 640.0
        let ky: Float = 1080.0 / 448.0
        switch effect {
        case 4...33:
            let strip = TextureRef.uiTile(set: UiSet.effectParts.rawValue, language: Int(Language.ja.rawValue), child: 3, tile: -1)
            let native: Float = 448.0 / 1080.0
            var sx: Float = 640.0 / 1920.0
            var sy: Float = native
            for s in slots {
                if s.alpha <= 0 || s.kind < 0 {
                    continue
                }

                let scaled = Self.lineScale(s.kind, s.angle)
                if scaled.matched {
                    sx = scaled.sx
                    sy = scaled.sy
                }

                let th = radians(s.angle)
                let c = cos(th), sn = sin(th)
                let len = 960.0 * sx, wid = 2.0 * sy
                let (u0, v0) = Self.lineUv(Int(s.kind) - 4)
                let rgba = Self.pack(s.alpha * level)
                let (ax, ay) = px(s, c, sn, 0, 0, kx, ky)
                let (bx, by) = px(s, c, sn, len, 0, kx, ky)
                let (cx, cy) = px(s, c, sn, 0, wid, kx, ky)
                let (dx, dy) = px(s, c, sn, len, wid, kx, ky)
                list.add(DrawCommand(
                    kind: .texturedQuad,
                    texture: strip,
                    v0: Vertex(x: ax, y: ay, u: u0 / 1920.0, v: v0 / 128.0, rgba: rgba),
                    v1: Vertex(x: bx, y: by, u: (u0 + 960.0) / 1920.0, v: v0 / 128.0, rgba: rgba),
                    v2: Vertex(x: cx, y: cy, u: u0 / 1920.0, v: (v0 + 2.0) / 128.0, rgba: rgba),
                    v3: Vertex(x: dx, y: dy, u: (u0 + 960.0) / 1920.0, v: (v0 + 2.0) / 128.0, rgba: rgba),
                    blendState: 1
                ))
            }
        case 1...3:
            guard let tables = tables else { break }
            for i in 0..<Self.noteSlots {
                let s = slots[i]
                if s.alpha <= 0 || s.kind < 0 || Int(s.kind) >= tables.focusNotes.count {
                    continue
                }

                let d = tables.focusNotes[Int(s.kind)]
                let a = max(0.0, s.alpha * level)
                let x0 = s.x * kx, y0 = s.y * ky
                let w = Float(d.width), h = Float(d.height)
                let rgba = Self.pack(a)
                let sheet = TextureRef.uiTile(set: UiSet.effectParts.rawValue, language: Int(Language.ja.rawValue), child: Int(s.kind), tile: -1)
                list.add(DrawCommand(
                    kind: .texturedQuad,
                    texture: sheet,
                    v0: Vertex(x: x0, y: y0, u: 0, v: 0, rgba: rgba),
                    v1: Vertex(x: x0 + w, y: y0, u: 1, v: 0, rgba: rgba),
                    v2: Vertex(x: x0, y: y0 + h, u: 0, v: 1, rgba: rgba),
                    v3: Vertex(x: x0 + w, y: y0 + h, u: 1, v: 1, rgba: rgba),
                    blendState: 1
                ))
            }
        default:
            break
        }
    }

    private func px(_ s: Slot, _ c: Float, _ sn: Float, _ dl: Float, _ dw: Float, _ kx: Float, _ ky: Float) -> (x: Float, y: Float) {
        (((s.x + (c * dl) - (sn * dw)) * kx), ((s.y + (sn * dl) + (c * dw)) * ky))
    }

    private static func pack(_ alpha: Float) -> UInt32 {
        let a = UInt8(clamping: Int(round(alpha * 255.0)))
        return 0x00FFFFFF | (UInt32(a) << 24)
    }

    private struct Slot {
        var kind: Int16 = -1
        var tick: Int16 = 0
        var total: Int16 = 0
        var step: Int16 = 0
        var frame: Int16 = 0
        var key: Int = 0
        var angle: Int16 = 0
        var x: Float = 0
        var y: Float = 0
        var alpha: Float = 0
        var vx: Float = 0
        var vy: Float = 0
        var ax: Float = 0
        var ay: Float = 0
    }
}
