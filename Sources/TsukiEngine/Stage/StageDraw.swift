import Foundation
import TsukiCore

/// The draw-effect tables of docs/formats/compositing.md 5.1 that the stage needs to fill `DrawCommand.blendState` (copy of `compose.effect`).
public enum DrawEffectTables {
    // 0x2D55E0, index e (blend state): 26 x 1, 6, 1, 1, 6, 22 x 1, then effects 52..67
    private static let blendState: [Int] = build()

    // 0xA1A800286A0: effects whose 0x100 flag turns blending off (0xD9FB9)
    private static let flagSet: UInt64 = 0xA1A800286A0

    /// The fixed-function blend state 0..13 of a draw-mode word.
    public static func blendStateOf(_ word: Int) -> Int {
        let low = word & 0xFF
        let e = low < 0x44 ? low : 0
        let rest = word & ~0x100
        let flag = (word & 0x100) != 0 && rest >= 0 && rest <= 0x2B && ((flagSet >> rest) & 1) != 0
        return flag ? 0 : blendState[e]
    }

    private static func build() -> [Int] {
        var b = [Int]()
        b.append(contentsOf: repeatElement(1, count: 26))
        b.append(contentsOf: [6, 1, 1, 6])
        b.append(contentsOf: repeatElement(1, count: 22))
        b.append(contentsOf: [2, 7, 1, 10, 11, 5, 4, 9, 1, 1, 1, 2, 1, 13, 1, 1])
        return b
    }
}

/// What the host needs from one `StageRuntime.draw` call.
public struct StageDrawInfo: Equatable, Sendable {
    /// The rule picture a type-2 transition draws this frame, or null.
    public var ruleTexture: TextureRef?
    /// The remaining progress of the transition (the host sets the rule texture's transition parameters from it every frame).
    public var ruleProgress: Float
    /// Number of layers that produced quads.
    public var layersDrawn: Int

    public init(ruleTexture: TextureRef? = nil, ruleProgress: Float = 0, layersDrawn: Int = 0) {
        self.ruleTexture = ruleTexture
        self.ruleProgress = ruleProgress
        self.layersDrawn = layersDrawn
    }
}

extension StageRuntime {
    private static let capture15Types: Set<Int> = {
        var set: Set<Int> = [2, 29, 30, 31, 32, 46, 49, 52, 53, 70]
        for i in 12...24 {
            set.insert(i)
        }
        return set
    }()

    static func white(_ a: UInt8 = 255) -> UInt32 {
        0xFFFFFF | (UInt32(a) << 24)
    }

    static func fill(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, _ rgba: UInt32, word: Int) -> DrawCommand {
        DrawCommand(
            kind: .fillQuad,
            v0: Vertex(x: x0, y: y0, u: 0, v: 0, rgba: rgba),
            v1: Vertex(x: x1, y: y0, u: 0, v: 0, rgba: rgba),
            v2: Vertex(x: x0, y: y1, u: 0, v: 0, rgba: rgba),
            v3: Vertex(x: x1, y: y1, u: 0, v: 0, rgba: rgba),
            effectWord: Int16(truncatingIfNeeded: word),
            blendState: UInt8(truncatingIfNeeded: DrawEffectTables.blendStateOf(word))
        )
    }

    static func textured(
        tex: TextureRef,
        x0: Float,
        y0: Float,
        x1: Float,
        y1: Float,
        u0: Float,
        v0: Float,
        u1: Float,
        v1: Float,
        rgba: UInt32,
        word: Int
    ) -> DrawCommand {
        DrawCommand(
            kind: .texturedQuad,
            texture: tex,
            v0: Vertex(x: x0, y: y0, u: u0, v: v0, rgba: rgba),
            v1: Vertex(x: x1, y: y0, u: u1, v: v0, rgba: rgba),
            v2: Vertex(x: x0, y: y1, u: u0, v: v1, rgba: rgba),
            v3: Vertex(x: x1, y: y1, u: u1, v: v1, rgba: rgba),
            effectWord: Int16(truncatingIfNeeded: word),
            blendState: UInt8(truncatingIfNeeded: DrawEffectTables.blendStateOf(word))
        )
    }

    /// Appends the scene to `list`: the transition start (the alpha-1 fill and the captures of the previous frame, once), the visible
    /// layers back to front by committed z (ties by layer number), and the transition frame (docs/formats/compositing.md 6, 7; layers.md 7, 9).
    public func draw(_ list: DisplayList) -> StageDrawInfo {
        if trBeginPending {
            trBeginPending = false
            list.add(Self.fill(0, 0, 1920, 1080, Self.white(), word: 56))
            list.add(DrawCommand(kind: .capture, texture: .capture(0)))
            if Self.capture15Types.contains(trKind) {
                list.add(DrawCommand(kind: .capture, texture: .capture(15)))
            }
        }

        drawnLayersList.removeAll(keepingCapacity: true)
        noiseFrame += 1
        let drawnCount = drawLayers(list)
        afterLayers?(list)
        let (rule, progress) = drawTransitionFrame(list)
        return StageDrawInfo(ruleTexture: rule, ruleProgress: progress, layersDrawn: drawnCount)
    }

    private func drawTransitionFrame(_ list: DisplayList) -> (rule: TextureRef?, progress: Float) {
        if !trActive || trKind == 1 || trProgress <= 0 {
            return (nil, 0)
        }

        if TransitionScreens.handles(trKind) {
            let screenRule: TextureRef? = (trKind == 69 && trRule > 0 && ruleSlot >= 0)
                ? TextureRef.pictureTile(archive: 4, entry: 85 + trRule, tile: 0)
                : nil
            TransitionScreens.frame(list, trKind, trProgress, screenRule) { [rng] in
                Int(rng.next())
            }
            return (nil, 0)
        }

        let surface: Int?
        if trKind == 49 {
            surface = nil
        } else if trKind == 2 {
            surface = 15
        } else if trKind < 0 || trKind > 70 {
            surface = nil
        } else {
            surface = 0
        }

        guard let surf = surface else {
            return (nil, 0)
        }

        let capture = TextureRef.capture(surf)
        if trKind == 2 && trRule > 0 && ruleSlot >= 0 {
            let rule = TextureRef.pictureTile(archive: 4, entry: 85 + trRule, tile: 0)
            list.add(Self.textured(tex: rule, x0: 0, y0: 0, x1: 1920, y1: 1080, u0: 0, v0: 0, u1: 1, v1: 1, rgba: Self.white(), word: 58))
            list.add(Self.textured(tex: capture, x0: 0, y0: 0, x1: 1920, y1: 1080, u0: 0, v0: 0, u1: 1, v1: 1, rgba: Self.white(), word: 26))
            return (rule, trProgress)
        }

        let alpha = UInt8(clamping: min(255, Int(max(0.0 as Float, trProgress) * 255.0)))
        list.add(Self.textured(tex: capture, x0: 0, y0: 0, x1: 1920, y1: 1080, u0: 0, v0: 0, u1: 1, v1: 1, rgba: Self.white(alpha), word: 0))
        return (nil, 0)
    }

    private func drawLayers(_ list: DisplayList) -> Int {
        var order = [Int](repeating: 0, count: Self.layerCount)
        var z = [Int](repeating: 0, count: Self.layerCount)
        for i in 0..<Self.layerCount {
            z[i] = Int(drawn[i].zOrder)
        }

        for i in 0..<Self.layerCount {
            var best = Int.max
            var idx = -1
            for j in 0..<Self.layerCount {
                if z[j] < best {
                    best = z[j]
                    idx = j
                }
            }
            order[i] = idx
            if idx >= 0 {
                z[idx] = Int.max
            }
        }

        var count = 0
        let shockOffset = shock.layerOffset()
        for i in 0..<Self.layerCount {
            let l = order[i]
            if l < 0 {
                continue
            }

            let r = drawn[l]
            if r.mask >= 0 {
                continue // drawn by its mask layer's pass (0x59EA0)
            }

            if !Self.visible(r) {
                continue
            }

            let clip = clipOf(l, shock: shockOffset)
            let window: PixelRect? = clip.map { Self.toScissor($0.scissor()) }
            let soft: SoftWindow? = effectPasses ? clip.flatMap { softOf($0) } : nil
            let windowed = Self.hasCrop(r)
            let kids = hasVisibleMaskedLayerAfter(order, i, l)
            let group = windowed || r.sttr >= 0 || kids
            maskBuilt = false
            let windowDrawn = drawLayer(list, l: l, window: window, noise: !windowed, group: group, windowOfKids: effectPasses && kids, maskedBy: 0, soft: soft)
            if windowDrawn {
                count += 1
                drawnLayersList.append(l)
            }

            let kidMask: UInt8 = maskBuilt ? Self.maskTarget : 0

            for k in (i + 1)..<Self.layerCount {
                let d = order[k]
                if d >= 0 && drawn[d].mask == l && Self.visible(drawn[d]) && drawLayer(list, l: d, window: window, noise: windowed, group: false, windowOfKids: false, maskedBy: kidMask, soft: nil) {
                    count += 1
                    drawnLayersList.append(d)
                }
            }

            if windowDrawn && effectPasses, let band = clip, band.isBand && band.inset > 0 {
                addBand(list, band, scissor: window)
            }
        }

        return count
    }

    private static func visible(_ r: LayerRecord) -> Bool {
        r.used != 0 && r.zOrder > 0
    }

    private static func hasCrop(_ r: LayerRecord) -> Bool {
        r.crop[2] > 0 && r.crop[3] > 0
    }

    private func hasVisibleMaskedLayerAfter(_ order: [Int], _ i: Int, _ l: Int) -> Bool {
        for k in (i + 1)..<Self.layerCount {
            let d = order[k]
            if d < 0 {
                continue
            }
            let c = drawn[d]
            if c.used > 0 && min(1.0 as Float, c.alpha + c.alphaCur) != 0 && c.mask == l {
                return true
            }
        }
        return false
    }

    private func clipOf(_ l: Int, shock: (x: Float, y: Float)) -> ClipWindow? {
        let w = drawn[l].mask >= 0 ? drawn[l].mask : l
        let wr = drawn[w]
        if wr.crop[2] <= 0 || wr.crop[3] <= 0 {
            return nil
        }

        let src = wr.mask >= 0 ? drawn[wr.mask] : wr
        var sx: Float = 0
        var sy: Float = 0
        for s in src.slots {
            if s.kind != 0 {
                sx += s.x
                sy += s.y
            }
        }

        let (shx, shy) = noShockPicture(wr.pic) ? (Float(0), Float(0)) : shock
        let x = Float(wr.crop[0]) + (sx * 3.0) + (shx * 3.0)
        let y = Float(wr.crop[1]) + (sy * Ps4Math.yPixels) + (shy * Ps4Math.yPixels)
        let x0 = Int(round(x))
        let y0 = Int(round(y))
        return ClipWindow(x: Float(x0), y: Float(y0), w: Float(wr.crop[2]), h: Float(wr.crop[3]), inset: Int(wr.a16), mode: Int(wr.a17))
    }

    static func toScissor(_ c: ClipWindow) -> PixelRect {
        var x0 = Int(c.x)
        var y0 = Int(c.y)
        var x1 = x0 + Int(c.w)
        var y1 = y0 + Int(c.h)
        x0 = max(x0, 0)
        y0 = max(y0, 0)
        x1 = min(x1, 1920)
        y1 = min(y1, 1080)
        return PixelRect(x: x0, y: y0, width: max(x1 - x0, 0), height: max(y1 - y0, 0))
    }

    private func advanceNoise(_ r: LayerRecord) {
        if r.stns == 0 {
            return
        }

        let period = Int(r.stns < 3 ? 20 : 12)
        let clampedFpu = min(max(framesPerUpdate, 0), 3)
        let b = Int(StageMath.i8(Int64(Int(r.stnsB) + clampedFpu)))
        r.stnsB = UInt8(truncatingIfNeeded: b)
        if period < b {
            r.stnsB = UInt8(truncatingIfNeeded: b % period)
        }
    }

    private func drawLayer(
        _ list: DisplayList,
        l: Int,
        window: PixelRect?,
        noise: Bool,
        group: Bool = false,
        windowOfKids: Bool = false,
        maskedBy: UInt8 = 0,
        soft: SoftWindow? = nil
    ) -> Bool {
        let r = drawn[l]
        if r.pic < 0 {
            return false
        }

        // 0x51060 start: the tween offsets of scale, rotation and alpha are evaluated for the draw
        r.scaleCur = r.twScale.remaining() * r.scaleDelta
        r.rotCur = StageMath.i16(Int64(StageMath.cvtt(r.twRot.remaining() * Float(r.rotDelta))))
        r.alphaCur = r.twAlpha.remaining() * r.alphaDelta
        let alpha = min(1.0 as Float, r.alpha + r.alphaCur)
        let visible = alpha > 0
        if !visible && !group {
            return false
        }

        if noise {
            advanceNoise(r)
        }

        if !visible {
            if windowOfKids {
                list.add(Self.clearTarget(Self.maskTarget))
                maskBuilt = true
            }
            return true
        }

        guard let layout = layouts?.get(r.pic, language) else {
            return false
        }

        if let win = window, win.width <= 0 || win.height <= 0 {
            return layout.files.contains { f in !f.tiles.isEmpty }
        }

        let (shx, shy) = noShockPicture(r.pic) ? (Float(0), Float(0)) : shock.layerOffset()
        let (slx, sly) = shakes.slotOffset(l)
        let (mx, my) = shakes.maskOffset(l, (0, 0))
        let m = Projection.frameMatrix(drawn, l, catalog, extra: (shx + slx, shy + sly), positionShift: (mx, my))
        let key = gradeKeyOf(l)
        let rgba = Self.white(UInt8(clamping: min(255, Int(max(0.0 as Float, alpha) * 255.0))))
        let word = ((r.flags & 0x80) != 0 ? 0x100 : 0) | (Int(r.blend) & 0xFF)
        let rule = (effectPasses && maskedBy == 0) ? Self.ruleOf(r) : nil
        let hazeState: HazeState? = (effectPasses && r.stns == 0) ? haze(l) : nil
        let noisy = effectPasses && r.stns >= 1 && r.stns <= 12
        var ownMask: UInt8 = rule != nil ? Self.maskTarget : maskedBy
        let ownSoft: SoftWindow? = (rule == nil && maskedBy == 0) ? soft : nil
        if ownSoft != nil {
            ownMask = Self.softTarget
        }

        quads.removeAll(keepingCapacity: true)
        for file in layout.files {
            for t in file.tiles {
                let ox = Double(file.offsetX)
                let oy = Double(file.offsetY)
                let (ax, ay) = m.apply(Double(t.x0) + ox, Double(t.y0) + oy)
                let (bx, by) = m.apply(Double(t.x1) + ox, Double(t.y1) + oy)
                let (cx, cy) = m.apply(Double(t.x0) + ox, Double(t.y1) + oy)
                let (dx, dy) = m.apply(Double(t.x1) + ox, Double(t.y1) + oy)
                let fx: QuadFx
                if let h = hazeState {
                    fx = Self.hazeFx(h, layout, file, t, ownMask)
                } else if ownMask != 0 {
                    fx = QuadFx.masked(ownMask)
                } else {
                    fx = QuadFx()
                }
                quads.append(DrawCommand(
                    kind: .texturedQuad,
                    texture: .pictureTile(archive: file.archive, entry: file.entry, tile: t.tile, colourEffect: key),
                    v0: Vertex(x: Float(ax), y: Float(ay), u: t.u0, v: t.v0, rgba: rgba),
                    v1: Vertex(x: Float(bx), y: Float(by), u: t.u1, v: t.v0, rgba: rgba),
                    v2: Vertex(x: Float(cx), y: Float(cy), u: t.u0, v: t.v1, rgba: rgba),
                    v3: Vertex(x: Float(dx), y: Float(dy), u: t.u1, v: t.v1, rgba: rgba),
                    effectWord: Int16(truncatingIfNeeded: word),
                    blendState: UInt8(truncatingIfNeeded: DrawEffectTables.blendStateOf(word)),
                    clip: window,
                    fx: fx
                ))
            }
        }

        if quads.isEmpty {
            return false
        }

        if noisy {
            let grainFx = ownMask != 0 ? QuadFx.masked(ownMask) : QuadFx()
            let grain = noiseQuad(r, m, layout, rgba, word, window, grainFx)
            quads.removeAll(keepingCapacity: true)
            quads.append(grain)
        }

        if let sw = ownSoft {
            list.add(Self.clearTarget(Self.softTarget))
            addSoftMask(list, sw, Self.softTarget, multiply: false)
        }

        if let rf = rule {
            list.add(Self.clearTarget(Self.maskTarget))
            addRuleMask(list, rf, alpha: alpha)
            maskBuilt = true
        } else if windowOfKids {
            list.add(Self.clearTarget(Self.maskTarget))
            addSilhouette(list, multiply: false)
            if let sk = ownSoft {
                addSoftMask(list, sk, Self.maskTarget, multiply: true)
            }
            maskBuilt = true
        }

        for q in quads {
            list.add(q)
        }

        if rule != nil && windowOfKids {
            addSilhouette(list, multiply: true)
        }

        return true
    }

    private func gradeKeyOf(_ l: Int) -> Int {
        drawn[l].gradeKey
    }
}
