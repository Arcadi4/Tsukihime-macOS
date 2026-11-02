// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Ported from knife (https://github.com/AuroraWright/knife) by AuroraWright: knife/src/ui.rs (cGallery hub)
import Foundation
import TsukiCore
import TsukiEngine

/// One mode of the gallery: CG grid, music player, movie cards or ending list.
class GalleryPanel {
    /// The hub the panel sits in.
    var host: GalleryScreen!

    /// The mode.
    var mode: GalleryMode { fatalError("must be overridden") }

    /// The guide index while the content has the focus.
    var guideIndex: Int { 10 }

    /// True when the content has something to select.
    var selectable: Bool { false }

    /// Binds the panel to its hub.
    func attach(_ host: GalleryScreen) {
        self.host = host
    }

    /// The mode came on screen: its list starts at the top.
    func show() {}

    /// The content takes the focus; false when there is nothing to select.
    func takeFocus() -> Bool { false }

    /// The content gives the focus up.
    func loseFocus() {}

    /// The mode goes away.
    func leave() {}

    /// One 60 Hz frame.
    func tick() {}

    /// The pointer moved or clicked at (x, y).
    func pointerOver(_ x: Float, _ y: Float) -> Bool { false }

    /// The pointer's own controls of the panel.
    func stepPointer(_ input: UiInput) -> Bool { false }

    /// An arrow.
    func move(_ dx: Int, _ dy: Int, _ fresh: Bool) {}

    /// Decide on the entry under the cursor.
    func activate() {}

    /// Cancel inside the content.
    func cancel() -> Bool { false }

    /// The wheel.
    func wheel(_ steps: Int) {}

    /// Draws the content.
    func draw(_ p: UiPainter, alpha: Float, focused: Bool) {}
}

/// The gallery hub screen.
public final class GalleryScreen: UiScreen {
    private static let contentFrames: Float = 30.0
    private let _afterReplay: Bool
    private var _buttons: [RectF] = []
    private var _panel: GalleryPanel!
    private var _next: GalleryPanel?
    private var _switching: Bool = false
    private var _nextFocus: Bool = false
    private var _switch: Float = 0
    private var _switchingOut: Bool = false
    private var _side: Bool = true
    private var _tab: Int = 0
    private var _replay: (scene: Int, node: Int)?
    private var _blink: Float = 0
    private var _guide: Int = 10
    private var _guideNext: Int = 10
    private var _guideDir: Int = 0
    private var _guideT: Float = 0

    public init(afterReplay: Bool = false) {
        self._afterReplay = afterReplay
        super.init()
        startHidden()
        var buttons: [RectF] = []
        for i in 0..<6 {
            buttons.append(RectF(80, 160.0 + (Float(i) * 80.0), 256, 96))
        }
        self._buttons = buttons
    }

    public override var opaque: Bool { true }
    public override var Opaque: Bool { true }

    public override var fadeInStep: Float { 0.04 }
    public override var FadeInStep: Float { fadeInStep }

    public override var fadeOutStep: Float { 0.04 }
    public override var FadeOutStep: Float { fadeOutStep }

    /// The mode shown.
    public var mode: GalleryMode { _panel.mode }
    public var Mode: GalleryMode { mode }

    /// The focus is on the mode buttons.
    public var sideFocus: Bool { _side }
    public var SideFocus: Bool { sideFocus }

    /// The button under the cursor.
    public var tab: Int { _tab }
    public var Tab: Int { tab }

    /// True while the content changes between two modes.
    public var switching: Bool { _switching }
    public var Switching: Bool { switching }

    var panel: GalleryPanel { _panel }
    var model: GalleryModel!
    var context: UiContext { ctx }
    var services: IGameServices { ctx.services }

    public override func onOpened() {
        guard let galleryTables = ctx.assets.gallery else {
            fatalError("the data has no gallery tables")
        }
        model = GalleryModel.for(galleryTables)
        ctx.backdrop.fade(0.04)
        let memory = ctx.gallery
        let first = memory.mode
        let node = _afterReplay ? memory.node : -1
        memory.mode = -1

        let start: GalleryMode
        if first == 1 || first == 3 || first == 4 {
            start = GalleryMode(rawValue: first) ?? .cg
        } else {
            start = .cg
        }

        _panel = create(start)
        _panel.show()
        _tab = start.rawValue
        if start == .endings && _afterReplay && node >= 0, let endings = _panel as? GalleryEndingsPanel {
            endings.focus(node)
        }

        if _afterReplay && node >= 0 && first != 2 && _panel.takeFocus() {
            _side = false
        }

        memory.node = -1
        if first == 2 {
            root?.push(FlowchartScreen(gallery: true, node: _afterReplay ? node : -1))
        }
    }
    public override func OnOpened() {
        onOpened()
    }

    public override func onClosed() {
        _panel.leave()
        ctx.backdrop.fade(0)
        if let r = _replay {
            _replay = nil
            ctx.services.replayScene(r.scene, node: r.node)
            root?.clear()
            return
        }
        root?.find(TitleScreen.self)?.returnFromGallery()
    }
    public override func OnClosed() {
        onClosed()
    }

    public override func close() {
        if closing {
            return
        }
        ctx.gallery.mode = _panel.mode.rawValue
        _panel.leave()
        ctx.backdrop.fade(-0.04)
        super.close()
    }
    public override func Close() {
        close()
    }

    private func create(_ mode: GalleryMode) -> GalleryPanel {
        let p: GalleryPanel
        switch mode {
        case .music:
            p = GalleryMusicPanel()
        case .movies:
            p = GalleryMoviesPanel()
        case .endings:
            p = GalleryEndingsPanel()
        default:
            p = GalleryCgPanel()
        }
        p.attach(self)
        return p
    }

    func sound(_ sound: UiSound) {
        ctx.sound(sound)
    }

    func toSide() {
        _panel.loseFocus()
        _side = true
        _tab = _panel.mode.rawValue
    }

    func openViewer(_ cg: GalleryCgPanel, _ group: Int, _ pos: Int) {
        root?.push(GalleryCgViewer(cg, group, pos))
    }

    func replay(_ scene: Int, _ node: Int) {
        ctx.gallery.node = node >= 0 ? node : scene
        if scene >= 0 {
            _replay = (scene, node)
        }
        close()
    }

    func replayFromChart(_ scene: Int, _ node: Int) {
        ctx.gallery.mode = GalleryMode.flowchart.rawValue
        ctx.gallery.node = node >= 0 ? node : scene
        if scene >= 0 {
            _replay = (scene, node)
        }
        _panel.leave()
        ctx.backdrop.fade(-0.04)
        super.close()
    }

    private var busy: Bool {
        fade < 1.0 || closing || _switching
    }

    private var wantedGuide: Int {
        _side ? 10 : _panel.guideIndex
    }

    public override func step(_ input: UiInput) {
        _blink += 1.0 / 60.0
        stepGuide()
        _panel.tick()
        if _switching {
            stepSwitch()
            return
        }

        if busy {
            return
        }

        if _panel.stepPointer(input) {
            _side = false
            return
        }

        let button = buttonAt(input)
        if input.pointerMoved {
            if button >= 0 {
                _tab = button
                _side = true
            } else if _panel.pointerOver(input.pointerX, input.pointerY) {
                _side = false
            }
        }

        if input.click {
            if button >= 0 {
                _tab = button
                _side = true
                act(button)
                return
            }
            if _panel.pointerOver(input.pointerX, input.pointerY) {
                _side = false
                _panel.activate()
                return
            }
        }

        if input.wheel != 0 {
            _panel.wheel(input.wheel)
        }

        let dx = (input.left ? -1 : 0) + (input.right ? 1 : 0)
        let dy = (input.up ? -1 : 0) + (input.down ? 1 : 0)
        let fresh = input.upPressed || input.downPressed || input.leftPressed || input.rightPressed
        if _side {
            stepSide(input, dx, dy, fresh)
            return
        }

        if input.cancel {
            sound(.buzzer)
            if !_panel.cancel() {
                toSide()
            }
            return
        }

        if dx != 0 || dy != 0 {
            _panel.move(dx, dy, fresh)
        } else if input.decide && !input.click {
            _panel.activate()
        }
    }
    public override func Step(_ input: UiInput) {
        step(input)
    }

    private func buttonAt(_ input: UiInput) -> Int {
        if !input.pointerActive {
            return -1
        }
        for i in 0..<_buttons.count {
            if _buttons[i].contains(input.pointerX, input.pointerY) {
                return i
            }
        }
        return -1
    }

    private func stepSide(_ input: UiInput, _ dx: Int, _ dy: Int, _ fresh: Bool) {
        if input.cancel {
            sound(.buzzer)
            close()
            return
        }

        let before = _tab
        if dy != 0 {
            let t = _tab + dy
            if (t >= 0 && t < 6) || fresh {
                _tab = ((t % 6) + 6) % 6
            }
        } else if dx > 0 {
            _tab = _panel.mode.rawValue
            if _panel.takeFocus() {
                _side = false
            }
            return
        } else if input.decide {
            act(_tab)
            return
        }

        if _tab != before {
            sound(.cursor)
        }
    }

    private func act(_ tab: Int) {
        switch tab {
        case 5:
            sound(.buzzer)
            close()
        case 2:
            openChart()
        default:
            if tab == _panel.mode.rawValue {
                if _panel.takeFocus() {
                    _side = false
                    sound(.decide)
                }
            } else if let newMode = GalleryMode(rawValue: tab) {
                sound(.decide)
                beginSwitch(newMode)
            }
        }
    }

    private func openChart() {
        if !services.sceneSeen(1) {
            sound(.cursor)
            root?.push(MessagePopup(ctx.message(1497), frames: 480.0))
            return
        }

        sound(.decide)
        ctx.gallery.previous = _panel.mode.rawValue
        _panel.leave()
        root?.push(FlowchartScreen(gallery: true, node: -1))
    }

    private func beginSwitch(_ mode: GalleryMode) {
        _next = create(mode)
        _nextFocus = true
        _switching = true
        _switchingOut = true
        _switch = 0
    }

    private func stepSwitch() {
        _switch += 1.0
        if _switchingOut {
            if _switch >= Self.contentFrames {
                _panel.leave()
                _panel = _next!
                _next = nil
                _panel.show()
                _side = true
                _tab = _panel.mode.rawValue
                _switchingOut = false
                _switch = 0
            }
            return
        }

        if _switch >= Self.contentFrames {
            _switching = false
            _switch = 0
            if _nextFocus && _panel.takeFocus() {
                _side = false
            }
        }
    }

    private var contentAlpha: Float {
        if !_switching {
            return 1.0
        }
        let u = min(max(_switch / Self.contentFrames, 0.0), 1.0)
        return _switchingOut ? (1.0 - u) * (1.0 - u) : u * u
    }

    private func stepGuide() {
        let want = wantedGuide
        if _guideDir < 0 {
            _guideNext = want
        } else if want != _guide {
            _guideDir = -1
            _guideT = 0
            _guideNext = want
        }

        if _guideDir != 0 {
            _guideT += 1.0 / 30.0
            if _guideT >= 1.0 {
                _guideT = 0
                if _guideDir < 0 {
                    _guide = _guideNext
                    _guideDir = 1
                } else {
                    _guideDir = 0
                }
            }
        }
    }

    private var guideAlpha: Float {
        if _guideDir < 0 {
            return (1.0 - _guideT) * (1.0 - _guideT)
        } else if _guideDir > 0 {
            return _guideT * _guideT
        }
        return 1.0
    }

    public override func draw(_ p: UiPainter) {
        p.cover(1.0)
        ctx.backdrop.draw(p)
        drawFrame(p, fade)
        p.withAlpha(fade * contentAlpha) {
            drawBanner(p, _panel.mode)
            _panel.draw(p, alpha: 1.0, focused: !_side)
        }
        drawButtons(p, fade)
        drawGuide(p, fade)
    }
    public override func Draw(_ p: UiPainter) {
        draw(p)
    }

    func drawFrame(_ p: UiPainter, _ alpha: Float) {
        p.withAlpha(alpha) {
            p.sprite(GallerySheets.panel, RectF(0, 0, 1560, 1080), RectF(365, 0, 1560, 1080))
            p.sprite(GallerySheets.underline, RectF(0, 0, 1920, 16), RectF(0, 72, 1920, 16))
        }
    }

    private func drawBanner(_ p: UiPainter, _ mode: GalleryMode) {
        if GallerySheets.hasTitle(mode, ctx.language) {
            p.spriteAt(GallerySheets.titleOf(mode), 64.0, 0)
        }
    }

    func drawButtons(_ p: UiPainter, _ alpha: Float) {
        p.withAlpha(alpha) {
            p.sprite(GallerySheets.menuWindow, RectF(0, 0, 312, 1080), RectF(56, 0, 312, 1080))
            let active = _panel.mode.rawValue
            for i in 0..<6 {
                let sx: Float = active == i ? 536.0 : (_tab == i ? 272.0 : 8.0)
                p.sprite(GallerySheets.menuButtons, RectF(sx, Float(8 + (104 * i)), 256, 96), RectF(80, Float(160 + (i * 80)), 256, 96))
            }

            if _side {
                let blink = 0.5 + (0.5 * abs(sin(_blink * 3.0)))
                p.sprite(GallerySheets.menuLight, RectF(0, 0, 528, 240), RectF(0, Float(96 + (_tab * 80)), 528, 240), alpha: blink, blend: .psAdd)
                p.sprite(GallerySheets.menuLine, RectF(0, 0, 304, 56), RectF(80, Float(192 + (_tab * 80)), 304, 56), alpha: 1.0, blend: .psAdd)
            }
        }
    }

    private func drawGuide(_ p: UiPainter, _ alpha: Float) {
        UiWidgets.guide(p, _guide, dy: (1.0 - guideAlpha) * 25.0, alpha: alpha * guideAlpha, decideIsCross: ctx.services.decideIsCross)
    }
}
