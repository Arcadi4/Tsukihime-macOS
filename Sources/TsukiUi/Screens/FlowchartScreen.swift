// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Ported from knife (https://github.com/AuroraWright/knife) by AuroraWright: knife/src/ui.rs (Screen::Flowchart)
import Foundation
import TsukiCore
import TsukiEngine

/// The flowchart: the node chart of the scenes the progress has opened, scrolling in a 1920 x 1022 view.
public final class FlowchartScreen: UiScreen {
    private static let scrollFrames: Float = ListScroll.frames
    private static let pageScroll: Float = 840.0
    private static let panThreshold: Float = 16.0

    private let _bar = UiScrollBar()
    private var _press: (x: Float, y: Float, scroll: Float, node: Int?)?
    private var _panning: Bool = false
    private let _gallery: Bool
    private let _openNode: Int
    private let _scroll = ListScroll()
    private var _chart: FlowchartChart!
    private var _cell: ChartCell = ChartCell(0, 0)
    private var _curY: Float = 0
    private var _ref: Float = 0
    private var _manual: Bool = false
    private var _shown: Int = -1
    private var _old: Int = -1
    private var _since: Float = Float.infinity
    private var _instant: Bool = false
    private var _replayed: Bool = false

    /// Creates the chart.
    public init(gallery: Bool, node: Int = -1) {
        self._gallery = gallery
        self._openNode = node
        super.init()
        startHidden()
    }

    public init(_ gallery: Bool, _ node: Int = -1) {
        self._gallery = gallery
        self._openNode = node
        super.init()
        startHidden()
    }

    /// Opened from the gallery.
    public var gallery: Bool { _gallery }
    public var Gallery: Bool { gallery }

    /// The chart.
    public var chart: FlowchartChart { _chart }
    public var Chart: FlowchartChart { chart }

    /// The cursor cell.
    public var cell: ChartCell { _cell }
    public var Cell: ChartCell { cell }

    /// The shown scroll.
    public var scroll: Float { _scroll.pos }
    public var Scroll: Float { scroll }

    func scrollNow(_ v: Float) {
        _ref = trunc(min(max(v, 0), _chart.scrollMax))
        _scroll.set(_ref)
    }

    /// The selectable node under the cursor (an index into `nodes`), or -1.
    public var selected: Int { _chart.nodeAt(_cell) }
    public var Selected: Int { selected }

    public override var opaque: Bool { true }
    public override var Opaque: Bool { true }

    public override var fadeInStep: Float { 1.0 / 30.0 }
    public override var FadeInStep: Float { fadeInStep }

    public override var fadeOutStep: Float { _instant ? 1.0 : (1.0 / 30.0) }
    public override var FadeOutStep: Float { fadeOutStep }

    /// Whether the flowchart can be opened.
    public static func available(_ ctx: UiContext, gallery: Bool) -> Bool {
        let s = ctx.services
        guard let tables = ctx.assets.gallery else {
            return false
        }
        if gallery {
            return s.sceneSeen(1)
        }
        return s.routeScene(1) && !GalleryModel.for(tables).isEndingNode(s.currentNode)
    }

    public static func Available(_ ctx: UiContext, _ gallery: Bool) -> Bool {
        available(ctx, gallery: gallery)
    }

    public override func onOpened() {
        guard let tables = ctx.assets.gallery else {
            fatalError("the data has no gallery tables")
        }
        _chart = FlowchartChart.build(tables, ctx.language, ctx.services, _gallery)
        _scroll.set(0)
        _ref = 0
        let id = _gallery ? _openNode : ctx.services.currentNode
        var placed: [ChartCell] = []
        _cell = _chart.openCursor(id, follow: { placed.append($0) })
        for c in placed {
            _cell = c
            place(animate: false)
        }
        _shown = selected
    }
    public override func OnOpened() {
        onOpened()
    }

    public override func onClosed() {
        if _gallery && !_replayed && ctx.gallery.previous != GalleryMode.music.rawValue {
            ctx.services.playBgm(ctx.services.global(2) == 5 ? 72 : 2)
        }
    }
    public override func OnClosed() {
        onClosed()
    }

    private func place(animate: Bool) {
        let n = _chart.nodeAt(_cell)
        if n >= 0 {
            _curY = _chart.nodes[n].y
        }
        follow(animate: animate)
    }

    private func follow(animate: Bool) {
        if _manual || _chart.rowY.isEmpty || _cell.row < 0 {
            return
        }

        let y = _curY - _ref
        let target: Float
        if y < 2.0 {
            target = _chart.rowY[max(_cell.row, 1) - 1] - 4.0
        } else if y > 966.0 {
            target = _chart.rowY[min(_cell.row + 1, _chart.rowY.count - 1)] - 966.0
        } else {
            return
        }

        _ref = trunc(target)
        _scroll.to(_ref, _chart.scrollMax, animate)
    }

    private func setCell(_ cell: ChartCell) {
        _cell = cell
        place(animate: true)
        let n = _chart.nodeAt(cell)
        if n != _shown {
            _old = _shown
            _shown = n
            _since = 0
        }
    }

    public override func step(_ input: UiInput) {
        _scroll.step()
        _since += 1.0
        if closing || fade < 1.0 {
            return
        }

        if _manual {
            stepManual()
        }

        if input.cancel {
            ctx.sound(.buzzer)
            close()
            return
        }

        if input.wheel != 0 && _chart.scrollMax > 0 {
            _ref = trunc(min(max(_scroll.target - (Float(input.wheel) * 168.0), 0.0), _chart.scrollMax))
            _scroll.to(_ref, _chart.scrollMax, true)
            _manual = true
        }

        if stepPointer(input) {
            return
        }

        var next: ChartCell? = nil
        if input.left {
            next = _chart.moveLeft(_cell)
        } else if input.right {
            next = _chart.moveRight(_cell)
        } else if input.up {
            next = _chart.moveUp(_cell)
        } else if input.down {
            next = _chart.moveDown(_cell)
        }

        if let to = next {
            _manual = false
            ctx.sound(.cursor)
            setCell(to)
            return
        }

        if input.decide && !input.click {
            press()
        }
    }
    public override func Step(_ input: UiInput) {
        step(input)
    }

    private func stepPointer(_ input: UiInput) -> Bool {
        let maxScroll = _chart.scrollMax
        let use = _bar.step(
            input,
            fraction: maxScroll > 0 ? _scroll.pos / maxScroll : 0.0,
            height: 610.0,
            canScroll: maxScroll > 0
        )
        if let dragged = use.fraction {
            _ref = trunc(dragged * maxScroll)
            _scroll.over(_ref, maxScroll, 6.0)
            _manual = true
        } else if use.page != 0 {
            _ref = trunc(min(max(_scroll.target + (Float(use.page) * Self.pageScroll), 0.0), maxScroll))
            _scroll.to(_ref, maxScroll, true)
            _manual = true
        }

        if use.consumed {
            _press = nil
            _panning = false
            return false
        }

        if input.click && input.pointerActive && input.pointerY < FlowchartChart.viewHeight {
            _press = (input.pointerX, input.pointerY, _scroll.target, nodeAtPointer(input))
            _panning = false
        }

        if let pr = _press {
            if input.pointerHeld {
                if !_panning && maxScroll > 0 && abs(input.pointerX - pr.x) + abs(input.pointerY - pr.y) >= Self.panThreshold {
                    _panning = true
                }

                if _panning {
                    _ref = trunc(min(max(pr.scroll - (input.pointerY - pr.y), 0.0), maxScroll))
                    _scroll.over(_ref, maxScroll, 0.0)
                    _manual = true
                }

                return false
            }

            _press = nil
            let pan = _panning
            _panning = false
            if !pan, let node = pr.node, nodeAtPointer(input) == node, let cell = _chart.cellOf(node) {
                setCell(cell)
                press()
                return true
            }

            return false
        }

        if input.pointerMoved, let hit = nodeAtPointer(input), let c = _chart.cellOf(hit), c != _cell {
            ctx.sound(.cursor)
            setCell(c)
        }

        return false
    }

    private func stepManual() {
        if _chart.scrollMax <= 0 {
            _manual = false
            return
        }

        if !_scroll.moving {
            _manual = false
        }

        let at = _ref
        if let moved = _chart.keepInView(_cell, y: { [weak self] i in
            guard let self = self else { return 0 }
            return self._chart.nodes[i].y - at
        }) {
            _cell = moved
            let n = _chart.nodeAt(moved)
            if n >= 0 {
                _curY = _chart.nodes[n].y
            }
            ctx.sound(.cursor)
            if n != _shown {
                _old = _shown
                _shown = n
                _since = 0
            }
        }
    }

    private func nodeAtPointer(_ input: UiInput) -> Int? {
        if !input.pointerActive || input.pointerY >= FlowchartChart.viewHeight {
            return nil
        }

        for i in 0..<_chart.nodes.count {
            let n = _chart.nodes[i]
            if RectF(n.x, n.y - _scroll.pos, FlowchartChart.nodeW, FlowchartChart.nodeH).contains(input.pointerX, input.pointerY) {
                return i
            }
        }
        return nil
    }

    private func press() {
        guard let rec = _chart.recordAt(_cell) else { return }

        ctx.sound(.decide)
        if _gallery {
            _replayed = rec.scriptScene >= 0
            _instant = true
            root?.find(GalleryScreen.self)?.replayFromChart(rec.scriptScene, rec.node)
            close()
            return
        }

        root?.push(ConfirmDialog(1498, false, { [weak self] yes in
            guard let self = self else { return }
            if !yes {
                return
            }
            self.ctx.services.commitSystemData()
            if self.ctx.services.flowchartJump(rec.column, rec.node, rec.scriptScene) {
                self.root?.clear()
            } else {
                self.close()
            }
        }))
    }

    public override func draw(_ p: UiPainter) {
        if _gallery {
            p.cover(1.0)
        }

        ctx.backdrop.draw(p)
        let s = fade
        p.withAlpha(s * s) {
            drawChartFrame(p)
        }

        let guide = _chart.scrollMax > 0 ? 0 : 10
        UiWidgets.guide(p, guide, 0.0, s, decideIsCross: ctx.services.decideIsCross)
    }
    public override func Draw(_ p: UiPainter) {
        draw(p)
    }

    private func drawChartFrame(_ p: UiPainter) {
        p.sprite(GallerySheets.chartBackground, RectF(0, 0, 1920, FlowchartChart.viewHeight), RectF(0, 0, 1920, FlowchartChart.viewHeight))
        p.spriteAt(GallerySheets.chartCard, 1352.0, 96.0)
        let scrollPos = _scroll.pos

        p.withClip(RectF(0, 0, 1920, FlowchartChart.viewHeight)) {
            for sp in _chart.sprites {
                let d = sp.dst
                if d.y - scrollPos > FlowchartChart.viewHeight || d.y + d.h - scrollPos < 0 {
                    continue
                }
                p.sprite(GallerySheets.of(sp.sheet), sp.src, RectF(d.x, d.y - scrollPos, d.w, d.h))
            }

            if !closing {
                drawTitles(p, scrollPos)
            }

            drawCursor(p, scrollPos)
        }

        if _chart.scrollMax > 0 {
            UiWidgets.scrollBar(p, scrollPos / _chart.scrollMax, 610.0, 1.0, _bar)
        }

        drawCard(p)
    }

    private func drawTitles(_ p: UiPainter, _ scrollPos: Float) {
        let off = -trunc(scrollPos)
        for phase in 0..<_chart.titles.count {
            let ts = _chart.titles[phase]
            if ts.isEmpty {
                continue
            }

            var o = off
            if ts[0].dst.y + o < 8.0 {
                o = 8.0 - ts[0].dst.y
            }

            let bottom = ts[ts.count - 1].dst.y + o + 32.0
            if phase < _chart.limits.count && _chart.limits[phase] + off < bottom {
                o -= bottom - (_chart.limits[phase] + off)
            }

            for t in ts {
                p.sprite(GallerySheets.of(t.sheet), t.src, RectF(t.dst.x, t.dst.y + o, t.dst.w, t.dst.h))
            }
        }
    }

    private func drawCursor(_ p: UiPainter, _ scrollPos: Float) {
        let n = selected
        if n < 0 {
            return
        }

        let node = _chart.nodes[n]
        let dst = RectF(node.x, node.y - scrollPos, FlowchartChart.nodeW, FlowchartChart.nodeH)
        p.sprite(GallerySheets.chartCursor, RectF(8, 8, 104, 64), dst)

        let a = 1.0 - (2.0 * _since / 30.0)
        if a > 0 {
            p.sprite(GallerySheets.chartCursor, RectF(120, 8, 104, 64), dst, a)
        }
    }

    private func drawCard(_ p: UiPainter) {
        let t = min(max(_since / 5.0, 0.0), 1.0)
        let e = t * (2.0 - t)
        if _old >= 0 && e < 1.0 {
            drawScene(p, _old, 1.0 - e, 1.0 - e)
        }

        if _shown >= 0 {
            drawScene(p, _shown, e, 1.0)
            p.spriteAt(GallerySheets.chartTag, 1672.0, 120.0)
        }
    }

    private func drawScene(_ p: UiPainter, _ node: Int, _ textAlpha: Float, _ previewAlpha: Float) {
        let n = _chart.nodes[node]
        let ctx = ctx

        let lang = ctx.language.rawValue
        let stacked = n.preview == 107 || n.preview == 114 || n.preview == 188 || n.preview == 481
        let y0: Float = stacked ? Float(lang) * 243.0 : 0.0
        p.sprite(GallerySheets.chartPreview(n.preview), RectF(0, y0, 430, 243), RectF(1380, 120, 430, 243), previewAlpha)

        let card = CardText.of(ctx.language)
        let title = ctx.message(n.titleUi).replacingOccurrences(of: "^", with: "")
        let synopsis = ctx.message(n.synopsisUi)
        ctx.text.draw(p, title, Self.titleStyle(ctx.text, card, title), card.x / UiMetrics.unitX, card.titleY / UiMetrics.unitY, textAlpha)
        ctx.text.draw(p, synopsis, card.synopsis, card.x / UiMetrics.unitX, card.synopsisY / UiMetrics.unitY, textAlpha)
    }

    struct CardText: Sendable {
        let x: Float
        let title: TextStyle
        let titleY: Float
        let titleLimit: Float
        let synopsis: TextStyle
        let synopsisY: Float

        static let cardTextBottom: Float = 567.0
        static let cardTextRight: Float = 1799.0

        static func of(_ language: Language) -> CardText {
            let english = language == .en
            let k: Double = english ? 0.75 : 1.0
            var title = TextStyle.slot(0.4 * k, 0.41481 * k)
            title.width = 200
            title.drawFlags = BlockDraw.always
            title.colour = TextStyle.rgb565(66, 65, 132)

            var synopsis = title
            synopsis.width = english ? 136 : 150
            synopsis.colour = TextStyle.black
            synopsis.leading = 0

            return CardText(
                x: english ? 1390.0 : 1392.0,
                title: title,
                titleY: 404.0,
                titleLimit: english ? cardTextRight : Float.infinity,
                synopsis: synopsis,
                synopsisY: english ? 436.0 : 452.0
            )
        }
    }

    static func titleStyle(_ text: UiText, _ card: CardText, _ title: String) -> TextStyle {
        let right = text.inkSpan(title, card.title).right
        if card.x + right <= card.titleLimit {
            return card.title
        }

        let k = Double((card.titleLimit - card.x) / right)
        var style = card.title
        style.sx *= k
        style.sy *= k
        return style
    }
}
