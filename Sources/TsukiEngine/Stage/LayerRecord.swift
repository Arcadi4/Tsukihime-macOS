import Foundation
import TsukiCore

/// One tween slot of a layer record (docs/formats/layers.md 4.3): the easing id, the counter in Q12 (starts at 0x1000 and counts down) and
/// the per-frame step. Five slots per record: move +0x84, scale +0x8A, rotation +0x90, alpha +0x96, zoom +0x9C.
public struct Tween: Sendable, Equatable {
    /// Easing id (+0).
    public var ease: Int16

    /// Counter in Q12 (+2); 0 = no tween.
    public var counter: Int16

    /// Step per frame (+4); negative while running.
    public var step: Int16

    /// Creates a tween slot.
    public init(ease: Int16 = 0, counter: Int16 = 0, step: Int16 = 0) {
        self.ease = ease
        self.counter = counter
        self.step = step
    }

    /// Starts a tween over `frames` 60 Hz frames (already wrapped to i16 as the engine stores them; setters VA 0x4A620, 0x49930, 0x4A4B0, 0x83350): counter 0x1000, step
    /// `-trunc(4096 / frames)`; no tween for 0 frames or fewer. The easing id is kept.
    public static func start(_ ease: Int16, _ frames: Int) -> Tween {
        if frames <= 0 {
            return Tween(ease: ease, counter: 0, step: 0)
        }
        return Tween(ease: ease, counter: 0x1000, step: StageMath.i16(Int64(-(0x1000 / frames))))
    }

    /// VA 0x49390 / 0x528DC: the fraction of the tween still to go, `1 - ease(id, p - 1, 0, 1, -1)` with `p = counter / 4096`; 0 once finished.
    public func remaining() -> Float {
        let p = StageMath.f(Double(Float(counter) * StageMath.f(1.0 / 4096.0)))
        if !(p > 0) {
            return 0
        }
        return StageMath.f(1.0 - Double(StageMath.f(Easing.ease(Int(ease), Double(StageMath.f(Double(p) - 1.0)), 0.0, 1.0, -1.0))))
    }

    /// One update of the counter (VA 0x57B2D..): a result at or below 0, or a step of 0 or more, ends the tween (counter and step 0).
    /// `dt` is the number of frames of this update.
    public mutating func tick(_ dt: Float) {
        if counter <= 0 {
            return
        }
        if step >= 0 {
            counter = 0
            step = 0
            return
        }
        let c = StageMath.cvtt(StageMath.f(Double(counter) + Double(StageMath.f(Float(step) * dt))))
        if c <= 0 {
            counter = 0
            step = 0
        } else {
            counter = StageMath.i16(Int64(c))
        }
    }
}

/// One shake slot of a drawn record (record + 0x178.., slot 0 = quake, slot 1 = shake or swing; docs/formats/quake.md 3.1). Port of
/// `ShakeSlot` of `tsuki.quake`.
public final class ShakeSlot {
    /// 0 none, 1 quake (SQK2), 2 shake (SHK2), 3 swing (SSW2).
    public var kind: Int = 0

    /// Start delay in frames (the field layers.md called "fade").
    public var delay: Int = 0

    /// Duration in frames; -1 until stopped; 0 never runs.
    public var time: Int = 0

    /// The six parameters p0..p5.
    public var par: [Int16] = [0, 0, 0, 0, 0, 0]

    /// Frames since the start (after the delay), saturating at 30000.
    public var elapsed: Int = 0

    /// Per-kind phase counter.
    public var phase: Int = 0

    /// Output offset x in canvas units.
    public var x: Float = 0

    /// Output offset y in canvas units.
    public var y: Float = 0

    /// Swing runtime w0..w6: amplitude x / y, period x / y, sign x / y, phase y.
    public var w: [Int16] = [0, 0, 0, 0, 0, 0, 0]

    public init() {}

    /// Clears every field (outputs included).
    public func clear() {
        kind = 0
        delay = 0
        time = 0
        elapsed = 0
        phase = 0
        par = [0, 0, 0, 0, 0, 0]
        w = [0, 0, 0, 0, 0, 0, 0]
        x = 0
        y = 0
    }

    /// A deep copy.
    public func copy() -> ShakeSlot {
        let c = ShakeSlot()
        c.copyFrom(self)
        return c
    }

    /// Copies every field from `o`.
    public func copyFrom(_ o: ShakeSlot) {
        kind = o.kind
        delay = o.delay
        time = o.time
        elapsed = o.elapsed
        phase = o.phase
        x = o.x
        y = o.y
        par = o.par
        w = o.w
    }
}

/// A layer record of the render arrays (40 x 0x2C8 bytes in the engine): **A** the drawn record (VA 0xDDB5E8), **B** the committed
/// record (0xDE2650). Only the fields the layer model reads or writes are kept (the oracle's `RENDER_FIELDS` plus the shake slots);
/// docs/formats/layers.md 5 lists the offsets.
public final class LayerRecord {
    /// +0x10: 1 while the layer is drawn (set when B is moved to A).
    public var used: Int = 0

    /// +0x14: 1 while the picture's face layer (catalog name1) is bound.
    public var face: Int = 0

    /// +0x18: picture id, -1 none.
    public var pic: Int = -1

    /// +0x1C: blend mode (STBR, motion field 17).
    public var blend: Int16 = 0

    /// +0x1E: 0x40 SACL (skip the mask offset), 0x80 STBR a3.
    public var flags: UInt8 = 0

    /// +0x1F: colour-effect mode (STEC).
    public var fxMode: Int8 = 0

    /// +0x20: colour-effect parameter A (SNX2, motion field 24).
    public var fxA: Int16 = 0

    /// +0x22: colour-effect parameter B (SNX3, motion field 25).
    public var fxB: Int8 = 0

    /// +0x24: scene state byte.
    public var state: Int = 0

    /// +0x2C: alpha 0..1.
    public var alpha: Float = 1.0

    /// +0x30: position x in engine units (640-wide canvas).
    public var x: Float = 0

    /// +0x34: position y.
    public var y: Float = 0

    /// +0x48: extra offset x.
    public var dx: Float = 0

    /// +0x4C: extra offset y.
    public var dy: Float = 0

    /// +0x50: picture offset x, minus the anchor (canvas units at scale 1).
    public var offX: Float = 0

    /// +0x54: picture offset y.
    public var offY: Float = 0

    /// +0x58: rotation in 1/100 degree.
    public var rot: Int64 = 0

    /// +0x70: scale per mille.
    public var scale: Int16 = 1000

    /// +0x76: anchor x (the pivot, integer canvas units).
    public var anchorX: Int16 = 0

    /// +0x78: anchor y.
    public var anchorY: Int16 = 0

    /// +0x7A: rotation tween start minus end.
    public var rotDelta: Int16 = 0

    /// +0x7C: current rotation tween offset (set by the draw: `trunc(remaining * rotDelta)`).
    public var rotCur: Int16 = 0

    /// +0x84: move tween (STCL).
    public var twMove: Tween = Tween()

    /// +0x8A: scale tween.
    public var twScale: Tween = Tween()

    /// +0x90: rotation tween (STRT).
    public var twRot: Tween = Tween()

    /// +0x96: alpha tween (STGS).
    public var twAlpha: Tween = Tween()

    /// +0x9C: zoom tween (STZ4).
    public var twZoom: Tween = Tween()

    /// +0xAA: zoom x per mille (negative = mirrored).
    public var zoomX: Int16 = 1000

    /// +0xAC: zoom y per mille.
    public var zoomY: Int16 = 1000

    /// +0xB0: STZ4 pivot flag: zoom in screen space about the layer position.
    public var zoomPivot: UInt8 = 0

    /// +0xCC: current alpha tween offset (`remaining * alphaDelta`).
    public var alphaCur: Float = 0

    /// +0xE0: scale tween start minus end.
    public var scaleDelta: Float = 0

    /// +0xE4: current scale tween offset.
    public var scaleCur: Float = 0

    /// +0xFC: zoom tween start minus end, x (zoom units / 1000).
    public var zoomDx: Float = 0

    /// +0x100: zoom tween start minus end, y.
    public var zoomDy: Float = 0

    /// +0x104: move tween start minus end, x.
    public var moveDx: Float = 0

    /// +0x108: move tween start minus end, y.
    public var moveDy: Float = 0

    /// +0x110: alpha tween start minus end.
    public var alphaDelta: Float = 0

    /// +0x120: mask layer (STCH a11), -1 none.
    public var mask: Int = -1

    /// +0x128: parent layer (SBAS), -1 none.
    public var parent: Int = -1

    /// +0x12C: STTR rule value, -1 none.
    public var sttr: Int = -1

    /// +0x130: SOXY x.
    public var soxyX: Int8 = 0

    /// +0x131: SOXY y.
    public var soxyY: Int8 = 0

    /// +0x132: crop rectangle x, y, w, h (STCH a12..a15, motion fields 11..14).
    public var crop: [Int16] = [0, 0, 0, 0]

    /// +0x13A: STCH a16.
    public var a16: UInt16 = 0

    /// +0x13C: STCH a17.
    public var a17: UInt8 = 0

    /// +0x15C: STCH a19 / STRR angle (no reader in the draw path).
    public var angle: Int16 = 0

    /// +0x160: motion id.
    public var motionId: Int16 = 0

    /// +0x162: motion divisor (STMA a3).
    public var motionDivisor: Int16 = 0

    /// +0x168: motion frame counter.
    public var motionFrames: Int64 = 0

    /// +0x170: motion pause byte (SPMA).
    public var motionPause: UInt8 = 0

    /// +0x1D0: STNS noise mode.
    public var stns: UInt8 = 0

    /// +0x1D1: STNS second byte.
    public var stnsB: UInt8 = 0

    /// +0x1F0: the 17-byte colour block (0xF7A0): +5..+7 RGB, +8..+0xA second RGB, +0xB.. the previous values.
    public var colour: [UInt8] = LayerRecord.newColour()

    /// The colour-effect key of the picture's texture (`TextureRef.D`): bound when the picture is (re)loaded by the commit.
    public var gradeKey: Int = 0

    /// +0x2C8: STRA value (the periodic effect id).
    public var stra: Int16 = 0

    /// +0x2CA: STRA phase in frames.
    public var straPhase: Int16 = 0

    /// +0x2CC: STRA fade-in length in frames.
    public var straFadeIn: Int16 = 0

    /// +0x2CE: STRA fade-out length.
    public var straFadeTotal: Int16 = 0

    /// +0x2D0: STRA fade-out frames left.
    public var straFadeLeft: Int16 = 0

    /// +0x6F50: the committed z (draw order), copied from B by the commit.
    public var zOrder: Int = 0

    /// +0x124: 1 while the layer is drawn offscreen as a mask / crop target (set by the offscreen pass).
    public var offscreen: Bool = false

    /// The two shake slots +0x178...
    public var slots: [ShakeSlot] = [ShakeSlot(), ShakeSlot()]

    public init() {}

    /// The colour block after a reset (VA 0xF700 on a white block): +5..+7 and +0xB..+0xD white.
    public static func newColour() -> [UInt8] {
        var c = [UInt8](repeating: 0, count: 17)
        c[5] = 255
        c[6] = 255
        c[7] = 255
        c[0xB] = 255
        c[0xC] = 255
        c[0xD] = 255
        return c
    }

    /// The motion record as 24 bytes (id, divisor, 4 unused, frames, pause, 7 unused).
    public func motionRecord(_ dst24: inout [UInt8]) {
        for i in 0..<min(24, dst24.count) { dst24[i] = 0 }
        let mid = UInt16(bitPattern: motionId)
        dst24[0] = UInt8(truncatingIfNeeded: mid)
        dst24[1] = UInt8(truncatingIfNeeded: mid >> 8)
        let mdiv = UInt16(bitPattern: motionDivisor)
        dst24[2] = UInt8(truncatingIfNeeded: mdiv)
        dst24[3] = UInt8(truncatingIfNeeded: mdiv >> 8)
        let mf = UInt64(bitPattern: motionFrames)
        for i in 0..<8 {
            dst24[8 + i] = UInt8(truncatingIfNeeded: mf >> (i * 8))
        }
        if dst24.count > 16 {
            dst24[16] = motionPause
        }
    }

    public func motionRecord() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 24)
        motionRecord(&bytes)
        return bytes
    }

    /// A deep copy of the record.
    public func clone() -> LayerRecord {
        let c = LayerRecord()
        c.copyFrom(self)
        return c
    }

    /// Copies every field of `o` into this record (the arrays by value).
    public func copyFrom(_ o: LayerRecord) {
        used = o.used
        face = o.face
        pic = o.pic
        blend = o.blend
        flags = o.flags
        fxMode = o.fxMode
        fxA = o.fxA
        fxB = o.fxB
        state = o.state
        alpha = o.alpha
        x = o.x
        y = o.y
        dx = o.dx
        dy = o.dy
        offX = o.offX
        offY = o.offY
        rot = o.rot
        scale = o.scale
        anchorX = o.anchorX
        anchorY = o.anchorY
        rotDelta = o.rotDelta
        rotCur = o.rotCur
        twMove = o.twMove
        twScale = o.twScale
        twRot = o.twRot
        twAlpha = o.twAlpha
        twZoom = o.twZoom
        zoomX = o.zoomX
        zoomY = o.zoomY
        zoomPivot = o.zoomPivot
        alphaCur = o.alphaCur
        scaleDelta = o.scaleDelta
        scaleCur = o.scaleCur
        zoomDx = o.zoomDx
        zoomDy = o.zoomDy
        moveDx = o.moveDx
        moveDy = o.moveDy
        alphaDelta = o.alphaDelta
        mask = o.mask
        parent = o.parent
        sttr = o.sttr
        soxyX = o.soxyX
        soxyY = o.soxyY
        crop = o.crop
        a16 = o.a16
        a17 = o.a17
        angle = o.angle
        motionId = o.motionId
        motionDivisor = o.motionDivisor
        motionFrames = o.motionFrames
        motionPause = o.motionPause
        stns = o.stns
        stnsB = o.stnsB
        colour = o.colour
        gradeKey = o.gradeKey
        stra = o.stra
        straPhase = o.straPhase
        straFadeIn = o.straFadeIn
        straFadeTotal = o.straFadeTotal
        straFadeLeft = o.straFadeLeft
        zOrder = o.zOrder
        offscreen = o.offscreen
        slots[0].copyFrom(o.slots[0])
        slots[1].copyFrom(o.slots[1])
    }
}
