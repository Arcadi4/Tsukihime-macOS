import Foundation
import TsukiCore

/// The 40 script layers of the scenario renderer (docs/formats/layers.md, quake.md): the script-side `SceneState`, the committed
/// array B and the drawn array A, the layer commands, the `_FADS` commit, the per-frame update (tweens, motions, shakes, screen shock,
/// message quake) and the build of the layer part of the display list. The game interpreter calls `execute` for every layer
/// statement, `update` once per 60 Hz step and `draw` to append the scene to the frame's `DisplayList`.
public final class StageRuntime {
    /// Number of layers.
    public static let layerCount = 40

    private let pictureCatalog: any PictureCatalog
    private let motionTable: MotionTable
    private var isCommitPending: Bool = false
    var ruleSlotVal: Int = -1

    // Transition stored properties for StageDraw
    var requested: Bool = false
    var reqType: Int = 0
    var reqMs: Int = 0
    var reqRule: Int = 0
    var trActive: Bool = false
    var trBeginPending: Bool = false
    var trKind: Int = 0
    var trProgress: Float = 0
    var trStep: Float = 0
    var trRule: Int = -1
    var drawnLayersList: [Int] = []

    /// Called after the layers and before a running transition's capture quad (package K7).
    public var afterLayers: ((DisplayList) -> Void)? = nil

    /// The picture layout source used to draw (nil: layers produce no quads).
    public var layouts: (any PictureLayoutSource)? = nil

    /// The game language index for pictures with language bands (0 ja, 1 en, 2 zc, 3 zt).
    public var language: Int = 0

    /// When true a changed STEC / SNX parameter regrades a layer's picture at the next commit even when the picture is unchanged.
    public var regradeOnCommit: Bool = false

    /// The six soft-clip radii of the eboot (10, 32, 40, 64, 128, 256), or nil for the built-in copy.
    public var clipRadii: [Float]? = nil

    var quads: [DrawCommand] = []
    var maskBuilt: Bool = false
    var noiseFrame: Int64 = 0

    /// True when the group pass (offscreen masks, rule fades), the haze and the noise are drawn.
    public var effectPasses: Bool = true

    /// Word 0x120A6D2: a next-scene skip runs; `_SHOK` does nothing then.
    public var skipActive: Bool = false

    /// The script-side layer state (scene_state, VA 0x16500C0).
    public let scene: SceneState

    /// The drawn records A (VA 0xDDB5E8).
    public let drawn: [LayerRecord]

    /// The committed records B (VA 0xDE2650).
    public let committed: [LayerRecord]

    /// The picture catalog.
    public var catalog: any PictureCatalog { pictureCatalog }

    /// The session's motion table (edited by `_SGMA`).
    public var motions: MotionTable { motionTable }

    /// The shared `rand()`.
    public let rng: Ps4Rand

    /// The flicker generator of SHK2.
    public let rnd2: Rnd2

    /// The layer shake slots.
    public let shakes: ShakeEngine

    /// The message-window quake (`_MSQK`); its offsets go to the HUD.
    public let messageQuake: MessageQuake

    /// The screen shock (`_SHOK`).
    public let shock: ScreenShock

    /// The scan-mode byte (0x174DE48, the re-execution after a slot load): timed shakes and `_SHOK` do nothing while it is set.
    public var scanMode: Bool = false

    /// The global colour-effect word (0x164B97C): when above 0, `_STCH` stores it as the layer's colour-effect mode.
    public var defaultColourEffect: Int = 0

    /// The configuration byte 0x66C578+0xA5: whether `_STMA` without a wait argument waits (0 = wait).
    public var motionWaitConfig: Int = 0

    /// Set by `_STMA` when the script must wait for the motion (word 0x164BA6E); the interpreter clears it after reading.
    public var motionWaitRequested: Bool = false

    /// Word 0x164B998: set by `_SGMA` and every shake start.
    public var sceneDirty: Bool = false

    /// The system-menu fraction (float 0x1202F0C, VA 0x6F430): the whole layer update is skipped at 1.0 or more.
    public var menuFraction: Float = 0

    /// Frames per update (word 0xDC7BE0, 1 at 60 Hz, at most 3); `update`'s argument is multiplied by it.
    public var framesPerUpdate: Int = 1

    /// True while a `_FADS` commit waits for the next update to move B to A and start the transition.
    public var commitPending: Bool { isCommitPending }

    /// The rule number last loaded into the shared rule slot (`_STTR`, `_FADS` type 2), or -1.
    public var ruleSlot: Int { ruleSlotVal }

    /// The STRA haze table (nil: `haze` returns nil).
    public var hazeTable: (any HazeTable)? = nil

    /// The layers the last `draw` produced quads for, in drawing order.
    public var drawnLayers: [Int] { drawnLayersList }

    /// True while a transition runs (progress above 0).
    public var transitionActive: Bool { trActive }

    /// The transition progress: 1 at the start, 0 at the end (float 0xE20CD0).
    public var transitionProgress: Float { trProgress }

    /// The type of the running transition (0xE23770).
    public var transitionKind: Int { trKind }

    /// Creates the stage over a catalog and the motion tables.
    /// - Parameters:
    ///   - catalog: The picture catalog and name map.
    ///   - motions: The motion tables.
    ///   - rng: The shared `rand()`; a fresh generator at state 1 when nil.
    public init(catalog: any PictureCatalog, motions: any MotionTables, rng: Ps4Rand? = nil) {
        self.pictureCatalog = catalog
        self.motionTable = MotionTable(motions)
        self.scene = SceneState.createDefault()
        let r = rng ?? Ps4Rand()
        self.rng = r
        self.rnd2 = Rnd2(r)

        var d = [LayerRecord]()
        d.reserveCapacity(Self.layerCount)
        var c = [LayerRecord]()
        c.reserveCapacity(Self.layerCount)
        for _ in 0..<Self.layerCount {
            d.append(LayerRecord())
            let rec = LayerRecord()
            for j in 0xB..<min(rec.colour.count, 0xB + 6) {
                rec.colour[j] = 0
            }
            c.append(rec)
        }
        self.drawn = d
        self.committed = c

        let cat = catalog
        self.shakes = ShakeEngine(drawn: d, rng: r, rnd2: rnd2, noShock: { pic in
            pic >= 0 && pic < cat.count && (cat.info(pic).drawFlags & 2) != 0
        }, scene: scene)
        self.messageQuake = MessageQuake()
        self.shock = ScreenShock()
    }

    /// The haze state of a layer while its STRA effect runs; nil when it does not or the id has no table entry.
    public func haze(_ layer: Int) -> HazeState? {
        let r = drawn[layer]
        guard r.stra > 0, let table = hazeTable, let entry = table.tryGetEntry(Int(r.stra)) else {
            return nil
        }
        return HazeState(id: Int(r.stra), entry: entry, phase: Int(r.straPhase), fadeIn: Int(r.straFadeIn), fadeTotal: Int(r.straFadeTotal), fadeLeft: Int(r.straFadeLeft))
    }

    func noShockPicture(_ pic: Int) -> Bool {
        pic >= 0 && pic < pictureCatalog.count && (pictureCatalog.info(pic).drawFlags & 2) != 0
    }

    /// `compose.fads_step`: the per-frame progress step of a transition of `ms` milliseconds (types 12 and 49 add 100 ms).
    public static func fadsStep(ms: Int, kind: Int = 0) -> Float {
        var ms = ms
        if (kind == 12 || kind == 49) && ms > 0 {
            ms += 100
        }
        return ms <= 0 ? -1.0 : -1.0 / (Float(ms) / 16.666)
    }

    func transitionRequest(type: Int, ms: Int, rule: Int) {
        requested = true
        reqType = type
        reqMs = ms
        reqRule = rule
    }

    func startTransition() {
        requested = false
        trKind = reqType
        trProgress = 1.0
        trStep = Self.fadsStep(ms: reqMs, kind: reqType)
        trActive = true
        trBeginPending = true
        trRule = reqRule > 0 ? reqRule : -1
    }

    func advanceTransition(_ dt: Int) {
        trProgress += Float(min(3, dt)) * trStep
        if trProgress <= 0.0 {
            trProgress = 0.0
            trStep = 0.0
            trActive = false
        } else if trProgress >= 1.0 {
            trProgress = 1.0
            trStep = -1.0
        }
    }

    /// Commit (`_FADS`, VA 0x7DD10): writes the committed records B from the scene state, puts the scene zoom and pivot flag into A, and
    /// requests the transition; the next `update` moves B to A. `type` and `ms` go to the transition.
    public func commit(type: Int, ms: Int, rule: Int) {
        for l in 0..<Self.layerCount {
            commitLayer(l)
        }
        isCommitPending = true
        transitionRequest(type: type, ms: ms, rule: rule)
    }

    private func commitLayer(_ l: Int) {
        let g = scene
        let b = committed[l]
        let a = drawn[l]
        let pic = g.getPic(l)
        b.pic = pic < 0x59D8 ? Int(pic) : -1
        b.blend = g.getBlend(l)
        b.fxMode = g.getFxMode(l)
        b.fxA = g.getFxA(l)
        b.fxB = g.getFxB(l)
        b.x = Float(g.getX(l))
        b.y = Float(g.getY(l))
        let ex = g.ext(l)
        let ox = Int16(bitPattern: UInt16(ex[2]) | (UInt16(ex[3]) << 8))
        let oy = Int16(bitPattern: UInt16(ex[4]) | (UInt16(ex[5]) << 8))
        b.offX = Float(ox)
        b.offY = Float(oy)
        b.alpha = Float(g.getAlpha(l)) * StageMath.f(1.0 / 255.0)
        b.state = Int(g.getState(l))
        b.scale = g.getScale(l)
        b.anchorX = g.getAnchorX(l)
        b.anchorY = g.getAnchorY(l)
        b.rot = g.getRot(l)
        b.mask = Int(g.getMask(l))
        b.parent = Int(g.getParent(l))
        b.sttr = Int(g.getSttr(l))
        b.soxyX = g.getSoxyX(l)
        b.soxyY = g.getSoxyY(l)
        b.flags = g.getFlags(l)
        for j in 0..<4 {
            b.crop[j] = g.getCrop(l, j)
        }

        b.a16 = g.getA16(l)
        b.a17 = g.getA17(l)
        b.angle = g.getAngle(l)
        b.stns = g.getStns(l)
        b.stnsB = g.getStnsB(l)
        b.zOrder = Int(g.getZ(l))
        b.stra = g.getStra(l)

        // colour block from the scene ext (0xF760): the previous colours shift to +0xB.., +5..+7 = ext +6..+8, +8..+0xA = ext +9..+0xB
        let rgb1 = (Int(ex[6]) << 16) | (Int(ex[7]) << 8) | Int(ex[8])
        let rgb2 = (Int(ex[9]) << 16) | (Int(ex[10]) << 8) | Int(ex[11])
        MotionApply.colourBlock(&b.colour, rgb1, rgb2)

        // motion record (0xBA8E0) and shake slots (kind, delay, time, parameters; the runtime fields stay 0)
        let mid = g.getMotionId(l)
        let mdiv = g.getMotionDivisor(l)
        let mfr = g.getMotionFrames(l)
        let mpause = g.getMotionPause(l)
        MotionApply.motionClear(b)
        MotionApply.motionCopy(dstId: &b.motionId, dstDivisor: &b.motionDivisor, dstFrames: &b.motionFrames, dstPause: &b.motionPause,
                              srcId: mid, srcDivisor: mdiv, srcFrames: mfr, srcPause: mpause)

        for s in 0..<2 {
            let slot = b.slots[s]
            slot.clear()
            slot.kind = Int(g.getShakeKind(l, s))
            slot.delay = Int(g.getShakeFade(l, s))
            slot.time = Int(g.getShakeTime(l, s))
            for p in 0..<6 {
                slot.par[p] = g.getShakePar(l, (6 * s) + p)
            }
        }

        // 0x49930(l, zoom, zoom, 0 frames): the scene zoom and the pivot flag go to A at once, ending a zoom tween
        a.zoomX = g.getZoomX(l)
        a.zoomY = g.getZoomY(l)
        a.zoomPivot = UInt8(truncatingIfNeeded: g.getZoomPivot(l))
        a.twZoom = Tween(ease: 0, counter: 0, step: 0)
        a.zoomDx = 0
        a.zoomDy = 0
    }

    /// B to A (the first update after a commit; VA 0x58B3D.. 0x59957): every field the commit wrote is moved to the drawn record, the layer
    /// becomes used, the motion record is merged (0xBA8E0) and committed shake slots replace the running ones when their kind differs.
    private func moveCommitted() {
        for l in 0..<Self.layerCount {
            let a = drawn[l]
            let b = committed[l]

            let texture = a.used != 0 || b.pic >= 0
            let regrade = regradeOnCommit || a.used == 0 || a.pic != b.pic
            a.used = b.pic >= 0 ? 1 : 0
            a.pic = b.pic
            a.flags = b.flags
            a.state = b.state
            a.alpha = b.alpha
            a.x = b.x
            a.y = b.y
            a.offX = b.offX
            a.offY = b.offY
            a.rot = b.rot
            a.scale = b.scale
            a.anchorX = b.anchorX
            a.anchorY = b.anchorY
            a.mask = b.mask
            a.parent = b.parent
            a.soxyX = b.soxyX
            a.soxyY = b.soxyY
            a.crop = b.crop
            a.a16 = b.a16
            a.a17 = b.a17
            a.angle = b.angle
            a.stns = b.stns
            a.stnsB = b.stnsB
            a.stra = b.stra
            if texture {
                a.blend = b.blend
                a.fxMode = b.fxMode
                a.fxA = b.fxA
                a.fxB = b.fxB
                a.colour = b.colour
                if regrade {
                    let rgb = (Int(b.colour[5]) << 16) | (Int(b.colour[6]) << 8) | Int(b.colour[7])
                    a.gradeKey = GradeKeys.intern(ColourGrade.from(Int(b.fxMode), brightness: Int(b.fxA), contrast: Int(b.fxB), rgb: rgb, globalColourMode: Int(scene.colourMode)))
                }
            }

            a.zOrder = b.zOrder
            a.face = a.pic >= 0 && a.pic < pictureCatalog.count && pictureCatalog.info(a.pic).hasFace ? 1 : 0
            MotionApply.motionCopy(a, b)
            shakes.mergeCommitted(layer: l, committed: b)

            // 0x59957: the motion is applied to the moved record at once (dt = 0)
            _ = MotionApply.apply(table: motionTable, catalog: pictureCatalog, rec: a, layer: l, dt: 0.0, scene: scene)
        }
    }

    /// One update of the layer stage with `arg` 60 Hz frames (VA 0x57980; `trunc(arg * FramesPerUpdate)` frames of
    /// time): the message quake, then per layer the tweens, the motion, the shake slots and the STRA phase, then the commit transfer and the screen
    /// shock. The whole layer part is skipped while the system menu covers the screen.
    public func update(arg: Int = 1) {
        messageQuake.update(rng: rng, arg: arg, fpu: framesPerUpdate)
        if menuFraction >= 1.0 {
            return
        }

        let dt = Int(StageMath.cvtt(Float(arg) * Float(framesPerUpdate)))
        let dtf = Float(dt)
        if trActive && !requested {
            advanceTransition(dt)
        }

        for l in 0..<Self.layerCount {
            let r = drawn[l]
            r.twMove.tick(dtf)
            r.twScale.tick(dtf)
            r.twRot.tick(dtf)
            r.twAlpha.tick(dtf)
            let rem = r.twAlpha.remaining()
            r.alphaCur = rem * r.alphaDelta
            r.twZoom.tick(dtf)
            _ = MotionApply.apply(table: motionTable, catalog: pictureCatalog, rec: r, layer: l, dt: Double(dtf), scene: scene)
            shakes.updateLayer(l, dtf)
            Self.updateStra(r, dt)
        }

        if isCommitPending {
            isCommitPending = false
            moveCommitted()
        }

        if requested {
            startTransition()
        }

        shock.update(dt: dt)
    }

    private static func updateStra(_ r: LayerRecord, _ dt: Int) {
        var phase = Int(r.straPhase) + dt
        phase -= (phase / 6000) * 6000
        r.straPhase = StageMath.i16(Int64(phase))
        if r.straFadeIn > 0 && phase >= Int(r.straFadeIn) {
            r.straFadeIn = 0
        }

        if r.straFadeTotal > 0 {
            let left = StageMath.i16(Int64(Int(r.straFadeLeft) - dt))
            r.straFadeLeft = left
            if left <= 0 {
                r.stra = 0
                r.straFadeTotal = 0
                r.straFadeLeft = 0
            }
        }
    }
}
