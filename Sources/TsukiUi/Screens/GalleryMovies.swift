// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Ported from knife (https://github.com/AuroraWright/knife) by AuroraWright: knife/src/ui.rs (cGalleryMovie)
import Foundation
import TsukiCore
import TsukiEngine

/// The movie gallery.
final class GalleryMoviesPanel: GalleryPanel {
    private static let cardY: [Float] = [312.0, 8.0, 160.0]

    private var _items: [Int] = []
    private var _cur: Int = -1

    override var mode: GalleryMode { .movies }
    override var selectable: Bool { !_items.isEmpty }

    var items: [Int] { _items }
    var cursor: Int { _cur }

    static func rect(_ k: Int) -> RectF {
        RectF(384.0 + (Float(k % 6) * 240.0), 104.0 + (Float(k / 6) * 160.0), 248.0, 144.0)
    }

    override func show() {
        _items = (0..<GalleryModel.movies.count).filter { GalleryModel.movieUnlocked($0, host.services) }
        _cur = -1
    }

    override func takeFocus() -> Bool {
        if _items.isEmpty {
            return false
        }
        _cur = 0
        return true
    }

    override func loseFocus() {
        _cur = -1
    }

    override func tick() {}

    override func pointerOver(_ x: Float, _ y: Float) -> Bool {
        for k in 0..<_items.count {
            if Self.rect(k).contains(x, y) {
                if k != _cur {
                    _cur = k
                    host.sound(.cursor)
                }
                return true
            }
        }
        return false
    }

    override func move(_ dx: Int, _ dy: Int, _ fresh: Bool) {
        if _cur < 0 {
            _cur = 0
            return
        }

        if dx < 0 {
            if _cur == 0 {
                host.toSide()
            } else {
                _cur -= 1
                host.sound(.cursor)
            }
        } else if dx > 0 && _cur + 1 < _items.count {
            _cur += 1
            host.sound(.cursor)
        }
    }

    override func activate() {
        if _cur < 0 || _cur >= _items.count {
            return
        }
        host.sound(.decide)
        host.root?.push(GalleryMoviePlayer(_items[_cur]))
    }

    override func draw(_ p: UiPainter, alpha: Float, focused: Bool) {
        for k in 0..<_items.count {
            let sx: Float = focused && _cur == k ? 264.0 : 8.0
            p.sprite(GallerySheets.movieCards, RectF(sx, Self.cardY[_items[k]], 248, 144), Self.rect(k))
        }
    }
}

/// The gallery's movie player.
public final class GalleryMoviePlayer: UiScreen {
    private static let curtainFrames: Float = 30.0
    private let _item: Int
    private var _restore: Int = 0
    private var _phase: Int = 0
    private var _t: Float = 0
    private var _frames: Float = 0
    private var _skip: Bool = true
    private var _bgm2: Bool = false
    private var _started: Bool = false

    public init(item: Int) {
        self._item = item
        super.init()
    }

    public init(_ item: Int) {
        self._item = item
        super.init()
    }

    public var phase: Int { _phase }
    public var Phase: Int { phase }

    public var item: Int { _item }
    public var Item: Int { item }

    private var white: Bool {
        _item == 1 && _frames < 30.0 && _phase < 2
    }

    public override var opaque: Bool { _phase == 1 }
    public override var Opaque: Bool { opaque }

    public override func onOpened() {
        let s = ctx.services
        _restore = s.playingBgm
        s.fadeOutBgm(0.5)
    }
    public override func OnOpened() {
        onOpened()
    }

    public override func step(_ input: UiInput) {
        let s = ctx.services
        switch _phase {
        case 0:
            _t += 1.0
            if _t >= Self.curtainFrames {
                let movie = GalleryModel.movies[_item].movie
                s.startIntroMovie(movie)
                _started = true
                _phase = 1
                _t = 0
            }
        case 1:
            _frames += 1.0
            if _item == 0 && _frames >= 360.0 && !_bgm2 {
                _bgm2 = true
                s.playBgm(2)
            }
            if _skip && (input.cancel || input.options) && s.introMoviePlaying {
                _skip = false
                s.stopIntroMovie()
            }
            if _started && !s.introMoviePlaying && _frames > 2.0 {
                _phase = 2
                _t = 0
            }
        default:
            _t += 1.0
            if _t >= Self.curtainFrames {
                if _restore > 0 {
                    s.playBgm(_restore)
                }
                close()
            }
        }
    }
    public override func Step(_ input: UiInput) {
        step(input)
    }

    public override func draw(_ p: UiPainter) {
        let u = min(max(_t / Self.curtainFrames, 0.0), 1.0)
        let a: Float
        switch _phase {
        case 0: a = u * (2.0 - u)
        case 1: a = 1.0
        default: a = (1.0 - u) * (1.0 - u)
        }
        let c: Float = white ? 1.0 : 0.0
        p.cover(a, gray: c)
        if _phase == 1 && ctx.services.introMoviePlaying {
            p.quad(TextureRef.movieFrame(ctx.services.introMovieSlot), 0, 0, UiMetrics.width, UiMetrics.height, 0, 0, 1, 1, UiPainter.pack(1.0))
        }
    }
    public override func Draw(_ p: UiPainter) {
        draw(p)
    }
}
