// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Ported from knife (https://github.com/AuroraWright/knife) by AuroraWright: knife/src/ui.rs (cGalleryMusic)
import Foundation
import TsukiCore
import TsukiEngine

/// Text on the gallery screens, positioned in canvas pixels.
enum GalleryText {
    static func draw(
        _ p: UiPainter,
        _ ctx: UiContext,
        _ text: String,
        _ a: Double,
        _ b: Double,
        _ x: Float,
        _ y: Float,
        _ width: Float,
        _ alpha: Float = 1.0,
        flags: Int = BlockDraw.always | BlockDraw.outline,
        colour: Int = TextStyle.white,
        leading: Int = -1
    ) {
        var style = TextStyle.slot(a, b)
        style.width = Int(width / UiMetrics.unitX)
        style.drawFlags = flags
        style.colour = colour
        if leading >= 0 {
            style.leading = leading
        }
        ctx.text.draw(p, text, style, x / UiMetrics.unitX, y / UiMetrics.unitY, alpha)
    }
}

/// The music player.
final class GalleryMusicPanel: GalleryPanel {
    public static let scrollRange: Float = 4720.0
    public static let ScrollRange: Float = scrollRange

    private static let clipTop: Float = 109.0
    private static let clipBottom: Float = 1014.0
    private static let controls: [(x: Float, y: Float)] = [
        (1432.0, 576.0), (1512.0, 576.0), (1592.0, 576.0), (1672.0, 576.0), (1512.0, 656.0), (1592.0, 656.0)
    ]

    private let _scroll = ListScroll()
    private let _bar = UiScrollBar()
    private var _volumeDrag: Bool = false
    private var _ok: [Bool] = []
    private var _zone: Zone = .row
    private var _row: Int = 0
    private var _btn: Int = 0
    private var _volFrom: Int = 0
    private var _percent: Int = 100
    private var _playing: Int = -1
    private var _last: Int = -1
    private var _paused: Bool = false
    private var _repeat: Bool = false
    private var _clock: Float = 0
    private var _fade: Float? = nil
    private var _bgOffset: Float = 0
    private var _pointerX: Float = 0
    private var _blink: Float = 0

    private enum Zone {
        case row
        case control
        case volume
    }

    override var mode: GalleryMode { .music }
    override var selectable: Bool { !_ok.isEmpty }
    override var guideIndex: Int { _zone == .row ? 0 : 10 }

    var playing: Int { _playing }
    var paused: Bool { _paused }
    var `repeat`: Bool { _repeat }
    var row: Int { _row }
    var scroll: Float { _scroll.pos }
    var bar: UiScrollBar { _bar }
    var volume: Float { Float(_percent) / 100.0 }
    var clock: Float { _clock }
    var unlocked: [Bool] { _ok }
    var controlCursor: Int { _zone == .control ? _btn : -1 }
    var onVolume: Bool { _zone == .volume }

    private var tracks: [GalleryTrackRow] { host.model.tables.tracks }
    private var gain: Float { Float(_percent) / 100.0 }

    override func show() {
        let s = host.services
        let bgm = s.playingBgm
        if bgm > 0 && bgm <= 0x417 {
            s.markBgmHeard(bgm)
        }
        _ok = host.model.tracksUnlocked(s, mark: s)
        s.stopMusic()
        _scroll.set(0)
        _bgOffset = 0
        _row = 0
        _btn = 0
        _zone = .row
        _playing = -1
        _paused = false
    }

    override func takeFocus() -> Bool {
        if _ok.isEmpty {
            return false
        }
        if _zone != .row {
            _zone = .control
        } else {
            follow(_row, prev: nil, animate: false)
        }
        return true
    }

    override func loseFocus() {}

    override func leave() {
        if _playing >= 0 {
            stop()
        }
    }

    private func play(_ i: Int) {
        _paused = false
        _fade = nil
        host.services.playMusic(tracks[i].bgm, volume: gain)
        _playing = i
        _last = i
        _clock = 0
    }

    private func stop() {
        _paused = false
        _fade = nil
        _clock = 0
        if _playing >= 0 {
            _playing = -1
            host.services.stopMusic()
        }
    }

    private func loop(_ i: Int) -> (start: Float, end: Float) {
        (Float(tracks[i].loopStart / 48) / 1000.0, Float(tracks[i].loopEnd / 48) / 1000.0)
    }

    override func tick() {
        _scroll.step()
        _blink += 1.0 / 60.0
        let o = -trunc(_scroll.pos)
        if o >= -200.0 {
            _bgOffset = o
        } else if o < -4465.0 {
            _bgOffset = o + 4265.0 - 326.0
        }

        if _playing < 0 || _paused {
            return
        }

        _clock += 1.0 / 60.0
        let (start, end) = loop(_playing)
        if _repeat {
            if end > start {
                while _clock > end {
                    _clock -= (end - start)
                }
            }
        } else {
            let fadeAt = tracks[_playing].lengthMs == 0 ? end - 1.5 : end
            if _fade == nil && _clock > fadeAt {
                host.services.fadeOutBgm(1.5)
                _fade = 1.5
            }
        }

        if let f = _fade {
            let nextFade = f - (1.0 / 60.0)
            _fade = nextFade
            if nextFade <= 0 {
                stop()
                return
            }
        }

        _clock = min(_clock, end)
    }

    private func follow(_ row: Int, prev: Int?, animate: Bool) {
        let s = _scroll.target
        let y = 173.0 + (Float(row) * 59.0) - s
        if (prev == nil || row > prev!) && y > 940.0 {
            _scroll.to(Float(row - 13) * 59.0, Self.scrollRange, animate)
        } else if (prev == nil || row < prev!) && y < 232.0 {
            _scroll.to(row == 0 ? 0.0 : Float(row - 1) * 59.0, Self.scrollRange, animate)
        }
    }

    override func wheel(_ steps: Int) {
        if steps == 0 {
            return
        }
        _scroll.to(_scroll.target - (Float(steps) * 59.0 * 3.0), Self.scrollRange, true)
    }

    private static let volumeRect = RectF(1376.0, 768.0, 448.0, 72.0)
    private static let pageScroll: Float = 13.0 * 59.0

    private func volumeFrom(_ x: Float) {
        let v = min(max((x - 1412.0) / 364.0, 0.0), 1.0)
        let percent = Int(round(v * 20.0)) * 5
        if percent != _percent {
            _percent = percent
            host.services.setMusicVolume(gain)
        }
    }

    override func stepPointer(_ input: UiInput) -> Bool {
        let use = _bar.step(input, fraction: _scroll.pos / Self.scrollRange, height: 610.0, canScroll: true)
        if let dragged = use.fraction {
            _scroll.over(dragged * Self.scrollRange, Self.scrollRange, 6.0)
        } else if use.page != 0 {
            _scroll.to(_scroll.target + (Float(use.page) * Self.pageScroll), Self.scrollRange, true)
        }

        if use.consumed {
            _volumeDrag = false
            return true
        }

        if _volumeDrag {
            if input.pointerHeld {
                volumeFrom(input.pointerX)
                return true
            }
            _volumeDrag = false
        }

        if input.click && input.over(Self.volumeRect) {
            _volumeDrag = true
            _pointerX = input.pointerX
            setZone(.volume, _btn)
            volumeFrom(input.pointerX)
            return true
        }

        return false
    }

    private static func rowRect(_ i: Int, _ scroll: Float) -> RectF {
        let y = 131.0 + (Float(i) * 59.0) - trunc(scroll)
        let y0 = min(max(y, clipTop), clipBottom)
        let y1 = min(max(y + 44.0, y0), clipBottom)
        return RectF(438.0, y0, 860.0, y1 - y0)
    }

    override func pointerOver(_ x: Float, _ y: Float) -> Bool {
        _pointerX = x
        for k in 0..<Self.controls.count {
            if RectF(Self.controls[k].x, Self.controls[k].y, 88.0, 80.0).contains(x, y) {
                setZone(.control, k)
                return true
            }
        }

        if Self.volumeRect.contains(x, y) {
            setZone(.volume, _btn)
            return true
        }

        for i in 0..<_ok.count {
            if Self.rowRect(i, _scroll.pos).contains(x, y) {
                setZone(.row, i)
                return true
            }
        }

        return false
    }

    private func setZone(_ zone: Zone, _ index: Int) {
        let changed = zone != _zone || (zone == .row && index != _row) || (zone == .control && index != _btn)
        _zone = zone
        if zone == .row {
            _row = index
        } else if zone == .control {
            _btn = index
        }
        if changed {
            host.sound(.cursor)
        }
    }

    override func move(_ dx: Int, _ dy: Int, _ fresh: Bool) {
        switch _zone {
        case .row:
            moveRow(dx, dy, fresh)
        case .control:
            moveControl(dx, dy)
        default:
            if dx != 0 {
                _percent = min(max(_percent + dx, 0), 100)
                host.services.setMusicVolume(gain)
            } else if dy < 0 {
                setZone(.control, _volFrom)
            }
        }
    }

    private func moveRow(_ dx: Int, _ dy: Int, _ fresh: Bool) {
        if dx < 0 {
            host.toSide()
            return
        }
        if dx > 0 {
            setZone(.control, _btn)
            return
        }

        let n = _ok.count
        if n == 0 { return }
        let t = _row + dy
        if t < 0 || t >= n {
            if !fresh {
                return
            }
        }

        let next = ((t % n) + n) % n
        follow(next, prev: _row, animate: true)
        setZone(.row, next)
    }

    private func moveControl(_ dx: Int, _ dy: Int) {
        let k = _btn
        if dx < 0 && (k == 0 || k == 4) {
            _btn = 0
            follow(_row, prev: nil, animate: false)
            setZone(.row, _row)
            return
        }

        var next = k
        if dx < 0 {
            next = k - 1
        } else if dx > 0 && (k <= 2 || k == 4) {
            next = k + 1
        } else if dx == 0 && dy < 0 && k >= 4 {
            next = k - 3
        } else if dx == 0 && dy > 0 {
            if k <= 1 {
                next = 4
            } else if k <= 3 {
                next = 5
            } else {
                _volFrom = k
                setZone(.volume, k)
                return
            }
        }

        if next != k {
            setZone(.control, next)
        }
    }

    override func activate() {
        switch _zone {
        case .row:
            host.sound(.decide)
            if _playing != _row && _ok[_row] {
                play(_row)
            } else {
                stop()
            }
        case .control:
            host.sound(.decide)
            control(_btn)
        default:
            if _pointerX > 0 {
                let v = min(max((_pointerX - 1412.0) / 364.0, 0.0), 1.0)
                _percent = Int(round(v * 20.0)) * 5
                host.services.setMusicVolume(gain)
            }
        }
    }

    private func stepNeighbor(_ from: Int, _ d: Int) -> Int? {
        let n = _ok.count
        if n <= 1 { return nil }
        for j in 1..<n {
            let t = ((from + (d * j) % n) + n) % n
            if _ok[t] {
                return t
            }
        }
        return nil
    }

    private func control(_ k: Int) {
        let cur = _playing >= 0 ? _playing : (_last >= 0 ? _last : 0)
        var target: Int? = nil
        switch k {
        case 0:
            target = _row
        case 1 where _playing >= 0:
            _paused = !_paused
            host.services.pauseMusic(_paused)
        case 2:
            stop()
        case 3:
            _repeat = !_repeat
        case 4:
            target = stepNeighbor(cur, -1)
        case 5:
            target = stepNeighbor(cur, 1)
        default:
            break
        }

        if let t = target {
            if _ok[t] {
                play(t)
            } else {
                stop()
            }
        }
    }

    override func draw(_ p: UiPainter, alpha: Float, focused: Bool) {
        let ctx = host.context
        let listRow = focused && _zone == .row ? _row : -1
        p.withClip(RectF(0, Self.clipTop, 1920, Self.clipBottom - Self.clipTop)) {
            p.spriteAt(GallerySheets.musicList, 392.0, 106.0 + _bgOffset)
            let scroll = trunc(_scroll.pos)
            for i in 0..<_ok.count {
                let y = 109.0 + (Float(i) * 59.0) - scroll
                if y + 64.0 < Self.clipTop || y > Self.clipBottom {
                    continue
                }
                p.spriteAt(GallerySheets.musicLine, 408.0, y + 64.0)
                let title = ctx.message(_ok[i] ? tracks[i].titleUi : 245).replacingOccurrences(of: "^", with: "")
                GalleryText.draw(p, ctx, title, 0.44444, 0.49778, 438.0, y + 22.0, 860.0, listRow == i ? 1.0 : 0.5)
            }
        }

        UiWidgets.scrollBar(p, _scroll.pos / Self.scrollRange, 610.0, 1.0, _bar)
        drawPanel(p, ctx, focused)
    }

    private func drawPanel(_ p: UiPainter, _ ctx: UiContext, _ focused: Bool) {
        p.spriteAt(GallerySheets.musicPanel, 1368.0, 104.0)
        if _playing >= 0 {
            drawCredits(p, ctx, tracks[_playing])
        }

        for k in 0..<Self.controls.count {
            let active = (k == 0 && _playing >= 0 && !_paused) || (k == 1 && _paused) || (k == 3 && _repeat)
            let hover = focused && _zone == .control && _btn == k
            let sy: Float = active ? 184.0 : (hover ? 96.0 : 8.0)
            p.spriteAt(GallerySheets.musicButtons, RectF(8.0 + (96.0 * Float(k)), sy, 88.0, 80.0), Self.controls[k].x, Self.controls[k].y)
        }

        let length = _playing >= 0 ? loop(_playing).end : 0.0
        let elapsed = _playing >= 0 ? _clock : 0.0
        let secs = Int(elapsed)
        let timeStr = String(format: "%2d:%02d", secs / 60, secs % 60)
        GalleryText.draw(p, ctx, timeStr, 0.41667, 0.41481, 1548.0, 503.0, 400.0)
        let volStr = String(format: "%3d", _percent)
        GalleryText.draw(p, ctx, volStr, 0.41667, 0.41481, 1562.0, 878.0, 400.0)

        let blink = 0.5 + (0.5 * abs(sin(_blink * 3.0)))
        let sliders: [(y: Float, frac: Float)] = [
            (424.0, length > 0 ? min(elapsed / length, 1.0) : 0.0),
            (792.0, Float(_percent) / 100.0)
        ]
        for item in sliders {
            p.spriteAt(GallerySheets.musicSlider, 1392.0, item.y)
            let kx = 1376.0 + (item.frac * 364.0)
            p.spriteAt(GallerySheets.musicKnob, RectF(8, 8, 72, 72), kx, item.y - 24.0)
            if item.y > 500.0 && focused && _zone == .volume {
                p.sprite(GallerySheets.musicKnob, RectF(168, 8, 72, 72), RectF(kx, item.y - 24.0, 72, 72), blink, .add)
            }
        }
    }

    private func drawCredits(_ p: UiPainter, _ ctx: UiContext, _ track: GalleryTrackRow) {
        let english = ctx.language == .en
        let credits = [track.vocalUi, track.lyricsUi, track.composerUi, track.arrangerUi]
        var lineCount = 1
        for (k, c) in credits.enumerated() {
            if c >= 0 {
                lineCount += (english && k > 0) ? 2 : 1
            }
        }
        var y = 260.0 - (32.0 * Float(lineCount / 2)) - 16.0
        let pitch: Float = 30.0

        func centred(_ text: String, _ top: Float) {
            GalleryText.draw(p, ctx, text, 0.4, 0.49778, 1368.0, top, 448.0, 1.0, flags: BlockDraw.always | BlockDraw.outline | BlockDraw.center)
        }

        let titleParts = ctx.message(track.titleUi).split(separator: "^", omittingEmptySubsequences: false)
        for (i, part) in titleParts.enumerated() {
            centred(String(part), y + (Float(i) * pitch))
        }

        y += (pitch * Float(max(0, titleParts.count - 1))) + 58.0
        for (k, c) in credits.enumerated() {
            if c < 0 {
                continue
            }
            let label = ctx.message(246 + k)
            let name = ctx.message(c)
            let sep = (english && k > 0) ? "^" : " "
            let combined = "\(label)\(sep)\(name)"
            let parts = combined.split(separator: "^", omittingEmptySubsequences: false)
            for (n, part) in parts.enumerated() {
                centred(String(part), y + (Float(n) * pitch))
            }

            y += 32.0
            if english {
                y += k > 0 ? 32.0 : 4.0
            }
        }
    }
}
