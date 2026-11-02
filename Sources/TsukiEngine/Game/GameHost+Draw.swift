import Foundation
import TsukiCore

extension GameHost {
    public static let textScale: Double = 3.0
    public static let pageScaleY: Double = 1.3 * 1080.0 / 448.0
    public static let choiceScaleY: Double = 1080.0 / 344.7
    private static let hudUnitY: Double = 1080.0 / 448.0
    static let wholeSheet: Int = -1

    func pack(_ r: Int, _ g: Int, _ b: Int, alpha: Double) -> UInt32 {
        let a = UInt8(clamping: Int(round(alpha * 255.0)))
        return UInt32(r & 0xFF) | (UInt32(g & 0xFF) << 8) | (UInt32(b & 0xFF) << 16) | (UInt32(a) << 24)
    }

    /// Draws the scene and overlay into `list`.
    public func draw(_ list: DisplayList) {
        _ = stage.draw(list)
        if movieActive && movieRec!.alpha > 0 {
            drawMovie(list, alpha: movieRec!.alpha)
        }

        sceneCommandCount = list.commands.count
        lastClickIcon = ClickIconDraw(kind: .none, dispChild: 0, frame: 0, x: 0, y: 0, alpha: 0)
        if phase == .running {
            if !windowHidden {
                drawWindow(list)
                drawPage(list)
            }

            if choiceOpen {
                drawChoice(list)
            }
        }
    }

    func addQuad(list: DisplayList, tex: TextureRef, x0: Double, y0: Double, x1: Double, y1: Double, u0: Float, v0: Float, u1: Float, v1: Float, rgba: UInt32, effectWord: Int = 0) {
        list.add(DrawCommand(
            kind: .texturedQuad,
            texture: tex,
            v0: Vertex(x: Float(x0), y: Float(y0), u: u0, v: v0, rgba: rgba),
            v1: Vertex(x: Float(x1), y: Float(y0), u: u1, v: v0, rgba: rgba),
            v2: Vertex(x: Float(x0), y: Float(y1), u: u0, v: v1, rgba: rgba),
            v3: Vertex(x: Float(x1), y: Float(y1), u: u1, v: v1, rgba: rgba),
            effectWord: Int16(truncatingIfNeeded: effectWord),
            blendState: UInt8(truncatingIfNeeded: DrawEffectTables.blendStateOf(effectWord))
        ))
    }

    func drawMovie(_ list: DisplayList, alpha: Float) {
        addQuad(
            list: list,
            tex: TextureRef.movieFrame(MovieSlots.fullScreen),
            x0: 0,
            y0: 0,
            x1: 1920,
            y1: 1080,
            u0: 0,
            v0: 0,
            u1: 1,
            v1: 1,
            rgba: pack(255, 255, 255, alpha: Double(alpha))
        )
    }

    func sheetSize(_ child: Int) -> (width: Int, height: Int) {
        if let size = sheetSizesCache[child] {
            return size
        }
        let size = data.uiSheetSize(.dispParts, language, child)
        sheetSizesCache[child] = size
        return size
    }

    func drawWindow(_ list: DisplayList) {
        if f(822) != 1 || f(1104) != 0 || wait.windowAlpha <= 0 {
            return
        }

        let w = windowIndex()
        guard let win = MessageWindow.windowFor(w, opacity: Int(config.hud10), fade: Double(wait.windowAlpha), xoffIdx: f(1106), yoffIdx: f(1107)) else {
            return
        }

        let (sw, sh) = sheetSize(win.dispChild)
        let x0 = win.xPx
        let y0 = win.yPx
        let x1 = x0 + (Double(sw) * win.scaleX)
        let y1 = y0 + (Double(sh) * win.scaleY)
        let tex = TextureRef.uiTile(set: UiSet.dispParts.rawValue, language: Int(language.rawValue), child: win.dispChild, tile: Self.wholeSheet)
        addQuad(list: list, tex: tex, x0: x0, y0: y0, x1: x1, y1: y1, u0: 0, v0: 0, u1: 1, v1: 1, rgba: pack(255, 255, 255, alpha: win.alpha))
    }

    private static func pageOf(_ tex: Int) -> Int {
        tex - 0x21
    }

    func addBlock(
        _ list: DisplayList,
        block: TextBlock,
        x: Double,
        y: Double,
        alpha: Double,
        head: Double,
        tail: Double,
        scaleY: Double = pageScaleY,
        offsetXPx: Double = 0.0,
        offsetYPx: Double = 0.0,
        drawFlags: Int? = nil
    ) {
        let flags = drawFlags ?? (BlockDraw.always | (config.text28 != 0 ? BlockDraw.shadow : 0) | (config.textDraw26 != 0 ? BlockDraw.outline : 0))
        let quads = BlockDraw.blockQuads(
            block,
            Float(x),
            Float(y),
            drawFlags: flags,
            alpha: alpha,
            head: head,
            tail: tail,
            textFade: Double(textFadeVal),
            outlineOption: config.textDraw26 != 0,
            instantOption: config.textAnimations == 1,
            lang: language
        )

        for q in quads {
            let pageIdx = Self.pageOf(q.tex)
            let pw = pageIdx == 0 ? 256.0 : 1024.0
            let w = Double(q.u1 - q.u0 + 1) * q.sx * Self.textScale
            let h = Double(q.v1 - q.v0 + 1) * q.sy * scaleY
            let x0 = (q.x * Self.textScale) + offsetXPx
            let y0 = (q.y * scaleY) + offsetYPx
            addQuad(
                list: list,
                tex: TextureRef.glyphPage(language: Int(language.rawValue), page: pageIdx),
                x0: x0,
                y0: y0,
                x1: x0 + w,
                y1: y0 + h,
                u0: Float(Double(q.u0) / pw),
                v0: Float(Double(q.v0) / pw),
                u1: Float(Double(q.u1 + 1) / pw),
                v1: Float(Double(q.v1 + 1) / pw),
                rgba: pack(q.r, q.g, q.b, alpha: q.alpha)
            )
        }
    }

    func pageOrigins() -> [(x: Double, y: Double)] {
        var blocks: [TextBlock] = []
        var blank: [Int] = []
        var scale: [Double] = []
        for m in page {
            blocks.append(m.block)
            blank.append(m.blank)
            scale.append(m.scaleY)
        }

        let window = windowIndex()
        let origin: (x: Double, y: Double)? = (window >= 3 && window < MessageWindow.windowCount) ? MessageWindow.bubbleTextOrigin(window, xoffIdx: f(1106), yoffIdx: f(1107)) : nil
        var pos = MessageWindow.pagePositions(blocks, language, blankBefore: blank, scaleY: scale, origin: origin)
        if !pos.isEmpty {
            pos[pos.count - 1].y += namePlateShift()
        }
        return pos
    }

    func drawPage(_ list: DisplayList) {
        guard !page.isEmpty, wait.windowAlpha > 0 else { return }

        let pos = pageOrigins()
        let t: Double = windowIndex() < 3 ? 100.0 : 255.0
        let (qx, qy) = stage.messageQuake.active ? (stage.messageQuake.x, stage.messageQuake.y) : (0.0, 0.0)
        let offX = Double(Int(qx)) * Self.textScale
        let offY = Double(Int(qy)) * Self.hudUnitY

        if f(1103) == 0 {
            drawNamePlate(list, offX: offX, offY: offY)
            for j in 0..<page.count {
                let m = page[j]
                let current = (j == page.count - 1)
                var a = Double(wait.windowAlpha)
                if !current {
                    let dim = m.dimTimer < 0 ? (t / 255.0) : (1.0 - ((255.0 - t) / 255.0 * min(1.0, Double(m.dimTimer) / Double(max(1.0, m.dimLimit)))))
                    a *= dim
                }

                let head = current ? Double(wait.head) : BlockDraw.revealAll
                let tail = current ? Double(wait.tail) : BlockDraw.revealAll
                addBlock(list, block: m.block, x: pos[j].x, y: pos[j].y, alpha: a, head: head, tail: tail, scaleY: Self.pageScaleY, offsetXPx: offX, offsetYPx: offY)
            }
        }

        drawClickIcon(list, origin: pos[pos.count - 1], offX: offX, offY: offY)
    }

    func clickIconY() -> Double {
        let defaultY: Double = language == .en ? 35.0 : 49.0
        if page.isEmpty {
            return defaultY
        }

        let pos = pageOrigins()
        guard let last = page.last else { return defaultY }
        let lastLine = (wait.windowAlpha > 0 && !last.block.empty) ? Double(MessageWindow.clickIconAnchor(last.block, head: Double(wait.head), tail: Double(wait.tail), lang: language).y) : 0.0
        return pos[pos.count - 1].y + lastLine
    }

    public func choiceFirstY() -> Double {
        var y = Float(clickIconY())
        if !(y > 0) {
            y = language == .en ? 34.934246 : 49.151669
        }

        if f(823) > 0 {
            y += 52.04
        }

        return Double(y)
    }

    func drawChoice(_ list: DisplayList) {
        guard varState.choiceMode == ChoiceMode.list.rawValue, choiceAlphaVal > 0 else { return }

        let x0: Double = language == .en ? 30.0 : 87.0
        let y0 = choiceFirstY()
        let view = ChoiceView(
            phase: choicePhaseVal,
            cursor: cursorVal,
            previous: previousCursorVal,
            alpha: choiceAlphaVal,
            highlight: choiceHighlightVal,
            flash: choiceFlashVal,
            x0: x0,
            y0: y0,
            unitX: Self.textScale,
            unitY: Self.choiceScaleY
        )

        glow.trace = choiceTrace != nil ? { [weak self] d in self?.choiceTrace?.append(d) } : nil
        glow.drawVignette(list, view: view)
        let flags = 0x1020 | (config.text28 != 0 ? 0x10 : 0)
        for k in 0..<lines.count {
            let line = lines[k]
            guard let blk = line.block else { continue }

            let y = y0 + (ChoiceView.linePitch * Double(k))
            if choicePhaseVal != 3 || k == cursorVal {
                let head = choicePhaseVal >= 2 ? Double(WaitState.instant) : Double(choiceHeadVal)
                choiceTrace?.append(ChoiceDraw(kind: "text", slot: 0x14 + k, x: x0, y: y, alpha: 1.0, scaleX: 0, scaleY: 0, flags: flags, colour: 0xFFFF))
                addBlock(list, block: blk, x: x0, y: y, alpha: 1.0, head: head, tail: head, scaleY: Self.choiceScaleY)
            }

            glow.drawLine(list, view: view, k: k, glowText: { [weak self] l, c in
                self?.glowText(line: l, colour: c)
            }, drawText: { [weak self] block, bx, by, alpha in
                self?.addBlock(list, block: block, x: bx, y: by, alpha: alpha, head: BlockDraw.revealAll, tail: BlockDraw.revealAll, scaleY: Self.choiceScaleY, drawFlags: 0)
            })
        }

        glow.drawDecided(list, view: view)
    }

    func glowText(line: Int, colour: Int) -> TextBlock? {
        if line < 0 || line >= lines.count {
            return nil
        }

        let key = ChoiceGlowKey(line: line, colour: colour)
        if let cached = glowTextCache[key] {
            return cached
        }

        let window = windowIndex()
        let block = try? TextLayout.layout(lines[line].text, language, fonts, LayoutParams(width: choiceWidth(), color: colour, block: 100, window: window))
        if let b = block {
            glowTextCache[key] = b
        }
        return block
    }
}
