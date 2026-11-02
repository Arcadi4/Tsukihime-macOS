// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Ported from knife (https://github.com/AuroraWright/knife) by AuroraWright: knife/src/ui.rs (cGalleryCGMain, cGalleryCGSub, cGalleryCGPhoto)
import Foundation
import TsukiCore
import TsukiEngine

/// The CG gallery's content: a grid of 6 columns of the groups with at least one unlocked picture.
final class GalleryCgPanel: GalleryPanel {
    public static let cols: Int = 6
    public static let Cols: Int = cols

    private static let clipTop: Float = 109.0
    private static let clipBottom: Float = 1014.0
    private static let fadeFrames: Float = 30.0

    private let _scroll = ListScroll()
    private let _bar = UiScrollBar()
    private var _unlocked: [[Int]] = []
    private var _list: [Int] = []
    private var _sub: Int? = nil
    private var _cur: Int = -1
    private var _mem: Int = -1
    private var _pickMain: Int = -1
    private var _pickMainScroll: Float = 0
    private var _pickSubScroll: Float = 0
    private var _flash: Float = 0
    private var _in: Float = fadeFrames
    private var _track: Bool = false
    private var _old: OldGrid? = nil

    private final class OldGrid {
        let list: [Int]
        let sub: Int?
        let scroll: Float
        init(list: [Int], sub: Int?, scroll: Float) {
            self.list = list
            self.sub = sub
            self.scroll = scroll
        }
    }

    override var mode: GalleryMode { .cg }
    override var selectable: Bool { !_list.isEmpty }
    override var guideIndex: Int { scrollMax > 0 ? 0 : 10 }

    var unlocked: [[Int]] { _unlocked }
    var sub: Int? { _sub }
    var cursor: Int { _cur }
    var count: Int { _list.count }
    var scroll: Float { _scroll.pos }

    var scrollMax: Float {
        let rows = Int(ceil(Float(_list.count) / Float(Self.cols)))
        return (Float(rows - 6) * 139.0) - 69.5
    }

    func entry(_ group: Int, _ pos: Int) -> GalleryCg {
        host.model.groups[group][_unlocked[group][pos]]
    }

    func flat() -> [(group: Int, pos: Int)] {
        var result: [(Int, Int)] = []
        for g in 0..<_unlocked.count {
            for k in 0..<_unlocked[g].count {
                result.append((g, k))
            }
        }
        return result
    }

    private func rebuild() {
        if let g = _sub {
            _list = Array(0..<_unlocked[g].count)
        } else {
            _list = (0..<_unlocked.count).filter { !_unlocked[$0].isEmpty }
        }
    }

    static func cell(_ k: Int, _ scroll: Float) -> RectF {
        RectF(
            392.0 + (Float(k % cols) * 240.0),
            109.0 + (Float(k / cols) * 139.0) - trunc(scroll),
            231.0,
            130.5
        )
    }

    override func show() {
        _unlocked = host.model.unlocked(host.services)
        _sub = nil
        _old = nil
        rebuild()
        _scroll.set(0)
        _cur = -1
        _mem = -1
        _in = Self.fadeFrames
        _track = false
    }

    override func takeFocus() -> Bool {
        if _list.isEmpty {
            return false
        }
        let a = (_mem >= 0 && _mem < _list.count) ? _mem - (_mem % Self.cols) : 0
        follow(a, prev: nil, animate: false)
        _cur = a
        _flash = 0
        return true
    }

    override func loseFocus() {
        _mem = _cur >= 0 ? _cur : _mem
        _cur = -1
    }

    private func follow(_ k: Int, prev: Int?, animate: Bool) {
        _track = false
        let maxScroll = scrollMax
        let s = _scroll.target
        let row = k / Self.cols
        let last = ((_list.count + Self.cols - 1) / Self.cols) - 1
        let y = 109.0 + (Float(row) * 139.0) - s
        if (prev == nil || row > prev!) && y > 804.0 {
            var v = Float(row - 5) * 139.0
            if row == last {
                v -= 69.5
            }
            _scroll.to(v, maxScroll, animate)
        } else if (prev == nil || row < prev!) && y < 178.5 {
            _scroll.to(row == 0 ? 0.0 : (Float(row - 1) * 139.0) + 69.5, maxScroll, animate)
        }
    }

    private func showGrid(_ sub: Int?, curPos: Int, scroll: Float, fadeOld: Bool) {
        _old = fadeOld ? OldGrid(list: _list, sub: _sub, scroll: _scroll.pos) : nil
        _sub = sub
        rebuild()
        _in = 0
        let row = max(curPos, 0) / Self.cols
        var k = Int(ceil(scroll + 0.001) + 0.001) / 139
        let y = 103.0 + (Float(row) * 139.0)
        while y - (Float(k) * 139.0) < 109.0 {
            k -= 1
        }
        while y - (Float(k) * 139.0) >= 804.0 {
            k += 1
        }

        _scroll.to(Float(k) * 139.0, scrollMax, animate: false)
        _mem = curPos
        if _cur >= 0 || !host.sideFocus {
            _cur = min(max(curPos, 0), max(_list.count - 1, 0))
            _flash = 0
        }
    }

    func viewerClosed(_ group: Int, _ pos: Int) {
        let sub = (_pickMain == group) ? (_sub != nil) : (_unlocked[group].count > 1)
        if sub {
            showGrid(group, curPos: pos, scroll: _pickSubScroll, fadeOld: false)
        } else {
            let main = (0..<_unlocked.count).filter { !_unlocked[$0].isEmpty }
            showGrid(nil, curPos: max(main.firstIndex(of: group) ?? 0, 0), scroll: _pickMainScroll, fadeOld: false)
        }
        _pickMain = group
        _in = Self.fadeFrames
        _old = nil
    }

    override func tick() {
        _scroll.step()
        _flash += 1.0
        if _in < Self.fadeFrames {
            _in += 1.0
        } else {
            _old = nil
        }

        if _track && _cur >= 0 {
            keepCursor()
        }
    }

    private func keepCursor() {
        let s = trunc(_scroll.pos)
        let col = _cur % Self.cols
        var row = _cur / Self.cols
        var y = 103.0 + (Float(row) * 139.0) - s
        while y < 103.0 {
            y += 139.0
            row += 1
        }
        while y >= 943.0 && row > 0 {
            y -= 139.0
            row -= 1
        }

        let k = col + (row * Self.cols)
        if k < _list.count && k != _cur {
            _cur = k
            _mem = k
            _flash = 0
            host.sound(.cursor)
        }
    }

    override func pointerOver(_ x: Float, _ y: Float) -> Bool {
        if y < Self.clipTop || y >= Self.clipBottom {
            return false
        }

        for k in 0..<_list.count {
            if Self.cell(k, _scroll.pos).contains(x, y) {
                if k != _cur {
                    _cur = k
                    _flash = 0
                    host.sound(.cursor)
                }
                return true
            }
        }
        return false
    }

    override func move(_ dx: Int, _ dy: Int, _ fresh: Bool) {
        if _list.isEmpty {
            return
        }
        if _cur < 0 {
            _cur = 0
            return
        }

        let n = _list.count
        let k = _cur
        let col = k % Self.cols
        let row = k / Self.cols
        var next = k

        if dx < 0 {
            if col == 0 {
                host.toSide()
                return
            }
            next = k - 1
        } else if dx > 0 {
            if col >= Self.cols - 1 || k + 1 >= n {
                return
            }
            next = k + 1
        } else if dy < 0 {
            if row == 0 {
                return
            }
            next = k - Self.cols
        } else {
            if k + Self.cols >= n {
                return
            }
            next = k + Self.cols
        }

        follow(next, prev: row, animate: dy != 0)
        _cur = next
        _mem = next
        _flash = 0
        host.sound(.cursor)
    }

    override func wheel(_ steps: Int) {
        if steps == 0 || scrollMax <= 0 {
            return
        }
        _scroll.to(_scroll.target - (Float(steps) * 139.0), scrollMax, true)
        _track = true
    }

    private static let pageScroll: Float = 5.0 * 139.0

    override func stepPointer(_ input: UiInput) -> Bool {
        let maxScroll = scrollMax
        let use = _bar.step(input, fraction: maxScroll > 0 ? _scroll.pos / maxScroll : 0.0, height: 610.0, canScroll: maxScroll > 0)
        if let dragged = use.fraction {
            _scroll.over(dragged * maxScroll, maxScroll, 6.0)
            _track = true
        } else if use.page != 0 {
            _scroll.to(_scroll.target + (Float(use.page) * Self.pageScroll), maxScroll, true)
            _track = true
        }
        return use.consumed
    }

    override func activate() {
        if _cur < 0 || _cur >= _list.count {
            return
        }

        host.sound(.decide)
        if let g = _sub {
            _pickSubScroll = _scroll.pos
            host.openViewer(self, g, _cur)
            return
        }

        let group = _list[_cur]
        _pickMain = group
        _pickMainScroll = _scroll.pos
        if _unlocked[group].count > 1 {
            showGrid(group, curPos: 0, scroll: 0, fadeOld: true)
            _cur = 0
            _flash = 0
        } else {
            host.openViewer(self, group, 0)
        }
    }

    override func cancel() -> Bool {
        if _sub == nil {
            return false
        }
        let main = (0..<_unlocked.count).filter { !_unlocked[$0].isEmpty }
        showGrid(nil, curPos: max(main.firstIndex(of: _pickMain) ?? 0, 0), scroll: _pickMainScroll, fadeOld: true)
        _cur = _mem
        _flash = 0
        return true
    }

    private static let thumbSource = RectF(0, 0, 231, 130)

    override func draw(_ p: UiPainter, alpha: Float, focused: Bool) {
        p.withClip(RectF(0, Self.clipTop, 1920, Self.clipBottom - Self.clipTop)) {
            let u = min(max(_in / Self.fadeFrames, 0.0), 1.0)
            if let old = _old, _in < Self.fadeFrames {
                p.withAlpha((1.0 - u) * (1.0 - u)) {
                    drawGrid(p, old.list, old.sub, old.scroll, -1, 0)
                }
            }

            p.withAlpha(_in < Self.fadeFrames ? u * u : 1.0) {
                drawGrid(p, _list, _sub, _scroll.pos, focused ? _cur : -1, _flash)
            }
        }

        if scrollMax > 0 {
            UiWidgets.scrollBar(p, _scroll.pos / scrollMax, 610.0, 1.0, _bar)
        }
    }

    private func drawGrid(_ p: UiPainter, _ list: [Int], _ sub: Int?, _ scroll: Float, _ cursor: Int, _ flash: Float) {
        for k in 0..<list.count {
            let rc = Self.cell(k, scroll)
            if rc.bottom < Self.clipTop || rc.y > Self.clipBottom {
                continue
            }

            let cg: GalleryCg
            if let g = sub {
                cg = host.model.groups[g][_unlocked[g][list[k]]]
            } else {
                cg = host.model.groups[list[k]][_unlocked[list[k]][0]]
            }

            p.sprite(GallerySheets.cgThumb(cg.row.thumbnail), Self.thumbSource, rc)
            if k == cursor {
                let at = RectF(rc.x - 8.0, rc.y - 6.0, 248.0, 144.0)
                p.sprite(GallerySheets.cgCursor, RectF(8, 8, 248, 144), at)
                let a = 1.0 - (flash / 15.0)
                if a > 0 {
                    p.sprite(GallerySheets.cgCursor, RectF(264, 8, 248, 144), at, a)
                }
            }
        }
    }
}

/// The CG viewer: a full-screen light grey layer under the picture.
final class GalleryCgViewer: UiScreen {
    private static let frames: Float = 30.0

    private let _panel: GalleryCgPanel
    private let _flat: [(group: Int, pos: Int)]
    private var _pictures: [Int: UiPicture?] = [:]
    private var _group: Int
    private var _pos: Int
    private var _zoom: Float = 0
    private var _pan: (x: Float, y: Float) = (0, 0)
    private var _previous: (group: Int, pos: Int, zoom: Float, pan: (x: Float, y: Float))? = nil
    private var _switchT: Float = frames
    private var _guidePhase: Int = 1
    private var _guideT: Float = 0
    private var _drag: (x: Float, y: Float)? = nil
    private var _press: (x: Float, y: Float)? = nil
    private var _pressMoved: Bool = false
    private var _notified: Bool = false

    init(_ panel: GalleryCgPanel, _ group: Int, _ pos: Int) {
        self._panel = panel
        self._flat = panel.flat()
        self._group = group
        self._pos = pos
        super.init()
        startHidden()
    }

    var group: Int { _group }
    var pos: Int { _pos }
    var zoom: Float { _zoom }

    override var opaque: Bool { fade >= 1.0 && !closing }
    override var fadeInStep: Float { 1.0 / Self.frames }
    override var fadeOutStep: Float { 1.0 / Self.frames }

    private var current: GalleryCg { _panel.entry(_group, _pos) }

    override func close() {
        if closing {
            return
        }
        if !_notified {
            _notified = true
            _panel.viewerClosed(_group, _pos)
        }
        _guidePhase = (_guidePhase == 1 || _guidePhase == 2) ? 3 : _guidePhase
        _guideT = 0
        super.close()
    }

    static func geometry(_ w: Float, _ h: Float, _ zoom: Float, _ pan: (x: Float, y: Float)) -> (rect: RectF, zoom: Float, pan: (x: Float, y: Float)) {
        let fit = min(UiMetrics.width / w, UiMetrics.height / h)
        let maxZoom = max(fit, 1.0)
        let s = zoom <= 0 ? fit : min(max(zoom, fit), maxZoom)
        let dw = w * s
        let dh = h * s
        let mx = abs((dw - UiMetrics.width) / 2.0)
        let my = abs((dh - UiMetrics.height) / 2.0)
        let clamped = (x: min(max(pan.x, -mx), mx), y: min(max(pan.y, -my), my))
        return (
            RectF(((UiMetrics.width - dw) / 2.0) + clamped.x, ((UiMetrics.height - dh) / 2.0) + clamped.y, dw, dh),
            s,
            clamped
        )
    }

    private func `switch`(_ d: Int) {
        if _flat.count < 2 || _switchT < Self.frames {
            return
        }
        guard let i = _flat.firstIndex(where: { $0.group == _group && $0.pos == _pos }) else {
            return
        }

        let nextIdx = (((i + d) % _flat.count) + _flat.count) % _flat.count
        let (g2, p2) = _flat[nextIdx]
        ctx.sound(.cursor)
        _previous = (_group, _pos, _zoom, _pan)
        _switchT = 0
        let a = _panel.entry(_group, _pos)
        let b = _panel.entry(g2, p2)
        _group = g2
        _pos = p2
        if a.row.width != b.row.width || a.row.height != b.row.height {
            _zoom = 0
            _pan = (0, 0)
        }
        showGuide()
    }

    private func showGuide() {
        if _guidePhase == 2 {
            _guideT = 0
        } else if _guidePhase != 1 {
            _guidePhase = 1
            _guideT = 0
        }
    }

    override func step(_ input: UiInput) {
        _guideT += 1.0 / 60.0
        switch _guidePhase {
        case 1 where _guideT >= 0.5:
            _guidePhase = 2
            _guideT = 0
        case 2 where _guideT >= 2.0:
            _guidePhase = 3
            _guideT = 0
        case 3 where _guideT >= 0.5:
            _guidePhase = 0
            _guideT = 0
        default:
            break
        }

        if _switchT < Self.frames {
            _switchT += 1.0
        } else {
            _previous = nil
        }

        if closing || fade < 1.0 {
            return
        }

        if input.cancel {
            ctx.sound(.buzzer)
            close()
            return
        }

        let horizontal = (input.leftPressed || input.rightPressed || input.l1 || input.r1) && !input.upPressed && !input.downPressed
        if horizontal {
            self.switch(input.leftPressed || input.l1 ? -1 : 1)
            return
        }

        let zoomStep: Float = input.up ? 1.12 : (input.down ? (1.0 / 1.12) : (input.wheel > 0 ? 1.12 : (input.wheel < 0 ? (1.0 / 1.12) : 1.0)))
        let cg = current
        let (w, h): (Float, Float) = (Float(max(cg.row.width, 1)), Float(max(cg.row.height, 1)))
        let (_, calculatedZoom, calculatedPan) = Self.geometry(w, h, _zoom, _pan)
        var newZoom = calculatedZoom
        var newPan = calculatedPan
        if zoomStep != 1.0 {
            newZoom *= zoomStep
        }

        if input.pointerHeld && input.pointerActive {
            if let last = _drag, input.pointerMoved {
                newPan = (newPan.x + (input.pointerX - last.x), newPan.y + (input.pointerY - last.y))
            }
            if let start = _press, abs(input.pointerX - start.x) + abs(input.pointerY - start.y) >= 16.0 {
                _pressMoved = true
            }
            if input.click {
                _press = (input.pointerX, input.pointerY)
                _pressMoved = false
            }
            _drag = (input.pointerX, input.pointerY)
        } else {
            _drag = nil
            if let start = _press {
                _press = nil
                if !_pressMoved && input.pointerActive && !input.cancel {
                    self.switch(start.x < UiMetrics.width / 4.0 ? -1 : 1)
                    return
                }
            }
        }

        let (_, z, p) = Self.geometry(w, h, newZoom, newPan)
        _zoom = z
        _pan = p
    }

    private func pictureOf(_ cg: GalleryCg) -> UiPicture? {
        let key = (cg.group * 1000) + cg.index
        if let existing = _pictures[key] {
            return existing
        }
        let found = ctx.assets.tables.findPicture(cg.row.name)
        let pic = found.map { UiPicture($0.archive, $0.entry) }
        _pictures[key] = pic
        return pic
    }

    private func drawPicture(_ p: UiPainter, _ group: Int, _ pos: Int, _ zoom: Float, _ pan: (x: Float, y: Float), _ alpha: Float) {
        let cg = _panel.entry(group, pos)
        guard let pic = pictureOf(cg) else {
            return
        }

        let (w, h): (Float, Float) = (Float(max(cg.row.width, 1)), Float(max(cg.row.height, 1)))
        let (rect, _, _) = Self.geometry(w, h, zoom, pan)
        let strip: Float = cg.languageStrip ? Float(ctx.language.rawValue) : 0
        p.picture(pic, RectF(Float(cg.row.x), Float(cg.row.y) + (Float(cg.row.height) * strip), w, h), rect, alpha)
    }

    override func draw(_ p: UiPainter) {
        let a = fade * fade
        p.withAlpha(a) {
            p.cover(0.85, 0.85)
            drawPicture(p, _group, _pos, _zoom, _pan, 1.0)
            if let prev = _previous, _switchT < Self.frames {
                drawPicture(p, prev.group, prev.pos, prev.zoom, prev.pan, 1.0 - (_switchT / Self.frames))
            }
        }

        let ga: Float
        switch _guidePhase {
        case 1: ga = (_guideT / 0.5) * (_guideT / 0.5)
        case 2: ga = 1.0
        case 3: ga = (1.0 - (_guideT / 0.5)) * (1.0 - (_guideT / 0.5))
        default: ga = 0
        }

        if ga > 0 {
            UiWidgets.guide(p, 9, (1.0 - ga) * 25.0, ga * a, decideIsCross: ctx.services.decideIsCross)
        }
    }
}
