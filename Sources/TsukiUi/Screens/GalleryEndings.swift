// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Ported from knife (https://github.com/AuroraWright/knife) by AuroraWright: knife/src/ui.rs (cGalleryEnding)
import Foundation
import TsukiCore
import TsukiEngine

/// The ending list.
final class GalleryEndingsPanel: GalleryPanel {
    private var _ok: [Bool] = []
    private var _all: Bool = false
    private var _cur: Int = -1

    override var mode: GalleryMode { .endings }
    override var selectable: Bool { _ok.contains(true) }

    var cursor: Int { _cur }
    var reached: [Bool] { _ok }

    static func position(_ i: Int) -> (col: Int, row: Int) {
        i < 3 ? (i, 0) : ((i - 3) % 8, ((i - 3) / 8) + 1)
    }

    static func entryAt(_ c: Int, _ r: Int) -> Int {
        r == 0 ? c : 3 + c + (8 * (r - 1))
    }

    func buttonRect(_ i: Int) -> RectF {
        if i >= _ok.count || !_ok[i] {
            return RectF.zero
        }
        if i < 3 {
            return RectF(720.0 + (Float(i) * 480.0), 128.0, 112.0, 112.0)
        }
        if i == 24 {
            return RectF(1702.0, 894.0, 112.0, 112.0)
        }
        let b = i - 3
        return RectF((Float(b & 7) * 180.0) + 384.0, (Float(b >> 3) * 96.0) + 680.0, 88.0, 88.0)
    }

    override func show() {
        let n = host.model.endingCount
        var ok = [Bool](repeating: false, count: n)
        for i in 0..<n {
            ok[i] = host.model.endingUnlocked(i, host.services)
        }
        _ok = ok
        _all = n > 0 && host.model.allEndings(host.services)
        _cur = -1
    }

    func focus(_ scene: Int) {
        for i in 0..<_ok.count {
            if host.model.tables.endings[i].scriptScene == scene && _ok[i] {
                _cur = i
                return
            }
        }
    }

    override func takeFocus() -> Bool {
        if _cur >= 0 && _cur < _ok.count && _ok[_cur] {
            return true
        }
        guard let first = _ok.firstIndex(of: true) else {
            return false
        }
        _cur = first
        return true
    }

    override func loseFocus() {
        _cur = -1
    }

    override func tick() {}

    override func pointerOver(_ x: Float, _ y: Float) -> Bool {
        for i in 0..<_ok.count {
            if buttonRect(i).contains(x, y) {
                if i != _cur {
                    _cur = i
                    host.sound(.cursor)
                }
                return true
            }
        }
        return false
    }

    private func isOk(_ c: Int, _ r: Int) -> Bool {
        let valid = r == 0 ? c < 3 : (r <= 3 && c < 8 && (r < 3 || c <= 5))
        if !valid {
            return false
        }
        let e = Self.entryAt(c, r)
        return e < _ok.count && _ok[e]
    }

    func nextEntry(_ i: Int, _ dx: Int, _ dy: Int) -> Int? {
        let (col, row) = Self.position(i)
        if dx < 0 {
            if col - 1 >= 0 {
                for c in stride(from: col - 1, through: 0, by: -1) {
                    if isOk(c, row) {
                        return Self.entryAt(c, row)
                    }
                }
            }
            return -1
        }

        if dx > 0 {
            let last = row == 0 ? 2 : 7
            if col + 1 <= last {
                for c in (col + 1)...last {
                    if isOk(c, row) {
                        return Self.entryAt(c, row)
                    }
                }
            }
            return nil
        }

        let qa = _all
        func nearest(_ r: Int) -> Int? {
            if r == 0 {
                let want = row == 0 ? col : (col < 3 ? 0 : (col < 6 ? 1 : 2))
                var best0: (c: Int, d: Int)? = nil
                for c in 0..<3 {
                    if isOk(c, 0) {
                        let d = abs(want - c)
                        if best0 == nil || d < best0!.d {
                            best0 = (c, d)
                        }
                    }
                }
                return best0?.c
            }

            let fromCols = [2, 5, 7]
            let from = row == 0 ? fromCols[col] : col

            if qa && r == 3 && dy > 0 && (col & ~1) == 6 && row > 0 {
                return 5
            }

            if qa && r == 2 && dy < 0 && row == 3 && col == 5 {
                return 7
            }

            let cols = r == 3 ? 5 : 8
            var best: (c: Int, d: Int)? = nil
            for c in 0..<cols {
                if isOk(c, r) {
                    let d = abs(from - c)
                    if best == nil || d <= best!.d {
                        best = (c, d)
                    }
                }
            }
            return best?.c
        }

        let rows: [Int] = dy < 0 ? Array(stride(from: row - 1, through: 0, by: -1)) : Array((row + 1)...3)
        for r in rows {
            if let c = nearest(r) {
                return Self.entryAt(c, r)
            }
        }
        return nil
    }

    override func move(_ dx: Int, _ dy: Int, _ fresh: Bool) {
        if _cur < 0 {
            _ = takeFocus()
            return
        }

        guard let next = nextEntry(_cur, dx, dx != 0 ? 0 : dy) else {
            return
        }

        if next < 0 {
            host.toSide()
            return
        }

        _cur = next
        host.sound(.cursor)
    }

    override func activate() {
        if _cur < 0 || _cur >= _ok.count || !_ok[_cur] {
            return
        }

        host.sound(.decide)
        let row = host.model.tables.endings[_cur]
        host.root?.push(ConfirmDialog(row.messageUi, true, { [weak self] yes in
            if yes {
                self?.host.replay(row.scriptScene, -1)
            }
        }))
    }

    override func draw(_ p: UiPainter, alpha: Float, focused: Bool) {
        for e in 0..<min(_ok.count, 24) {
            let ok = _ok[e]
            let hov = focused && _cur == e
            if e < 3 {
                p.spriteAt(ok ? GallerySheets.endingCard(e) : GallerySheets.endingCardLocked, 416.0 + (Float(e) * 480.0), 120.0)
                if ok {
                    p.spriteAt(GallerySheets.endingButtons, RectF(hov ? 128.0 : 8.0, 8.0, 112.0, 112.0), 720.0 + (Float(e) * 480.0), 128.0)
                }
                continue
            }

            let b = e - 3
            let x: Float = (Float(b & 7) * 180.0) + 384.0
            let y: Float = (Float(b >> 3) * 96.0) + 680.0
            let y0: Float = ok ? 296.0 : 8.0
            p.spriteAt(GallerySheets.endingPlates, RectF((Float(b & 7) * 180.0) + 8.0, (Float(b >> 3) * 96.0) + y0, 180.0, 88.0), x, y)
            if ok {
                p.spriteAt(GallerySheets.endingPlateButtons, RectF(hov ? 104.0 : 8.0, 8.0, 88.0, 88.0), x, y)
            }
        }

        if _all && _ok.count == 25 {
            p.spriteAt(GallerySheets.endingButtons, RectF(focused && _cur == 24 ? 128.0 : 8.0, 8.0, 112.0, 112.0), 1702.0, 894.0)
        }
    }
}
