// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Ported from knife (https://github.com/AuroraWright/knife) by AuroraWright: knife/src/ui.rs (draw_menu_base, menu items and input)
import Foundation
import TsukiCore
import TsukiEngine

/// The five tabs of the system menu.
public enum MenuTab: Int, Sendable {
    case save = 0
    case load = 1
    case config = 2
    case flowChart = 3
    case title = 4
}

/// The system menu (TRIANGLE in the story; docs/formats/system_flow.md "System menu", knife `Screen::Menu`).
public final class SystemMenuScreen: UiScreen {
    private let _items = UiItemList()
    private var _focus: Bool = false
    private var _toTitle: Bool = false
    private var _titleWait: Float = 0

    public override init() {
        super.init()
        startHidden()
    }

    /// The screen opened from this menu that is still on show (not closing), or null.
    private var sub: ISubMenu? {
        guard let root = root else { return nil }
        for screen in root.stack.reversed() {
            if let s = screen as? ISubMenu, let ui = screen as? UiScreen, !ui.closing {
                return s
            }
        }
        return nil
    }

    /// The tab a screen opened from this menu belongs to, or -1 (the menu draws it as open).
    public var openTab: Int { sub?.tab ?? -1 }
    public var OpenTab: Int { openTab }

    /// The cursor line and light show on the remembered tab (the tabs have the focus while a submenu is open).
    public var sideFocus: Bool { sub?.side.active ?? false }
    public var SideFocus: Bool { sideFocus }

    public override var finished: Bool {
        super.finished && !_toTitle
    }
    public override var Finished: Bool { finished }

    public override var fadeInStep: Float { 1.0 / 18.0 }
    public override var FadeInStep: Float { fadeInStep }

    public override var fadeOutStep: Float { 1.0 / 30.0 }
    public override var FadeOutStep: Float { fadeOutStep }

    /// The hit rectangle of tab `i`.
    public static func tabRect(_ i: Int) -> RectF {
        let x: Float = trunc(26.667)
        let y: Float = trunc(43.556 + (Float(i) * 31.111))
        return RectF(x * UiMetrics.unitX, y * UiMetrics.unitY, 75.0 * UiMetrics.unitX, 30.0 * UiMetrics.unitY)
    }
    public static func TabRect(_ i: Int) -> RectF {
        tabRect(i)
    }

    public override func onOpened() {
        for i in 0..<5 {
            _items.add(Self.tabRect(i), i)
        }
        _items.cursor = ctx.menuTab
        ctx.sound(.open)
        ctx.backdrop.fade(0.0555)
    }
    public override func OnOpened() {
        onOpened()
    }

    public override func close() {
        if closing {
            return
        }
        super.close()
        if (root?.stack.count ?? 0) <= 1 {
            ctx.backdrop.fade(-1.0 / 30.0)
        }
    }
    public override func Close() {
        close()
    }

    public override func onClosed() {
        if let root = root, !root.active {
            ctx.backdrop.fade(0)
        }
    }
    public override func OnClosed() {
        onClosed()
    }

    public override func step(_ input: UiInput) {
        if _toTitle {
            _titleWait += 1
            if root?.banner == nil && fade <= 0 {
                _toTitle = false
                ctx.services.returnToTitle()
                root?.clear()
            }
            return
        }

        if closing {
            return
        }

        if input.cancel || input.square || input.l2 {
            ctx.sound(.buzzer)
            close()
            return
        }

        let before = ctx.menuTab
        if input.up || input.down {
            ctx.menuTab = (ctx.menuTab + (input.up ? 4 : 1)) % 5
            _focus = true
        }

        if input.pointerMoved {
            let hit = _items.hitTest(input.pointerX, input.pointerY)
            if hit >= 0 {
                ctx.menuTab = hit
                _focus = true
            }
        }

        if ctx.menuTab != before {
            ctx.sound(.cursor)
        }

        if input.click {
            let hit = _items.hitTest(input.pointerX, input.pointerY)
            if hit >= 0 {
                ctx.menuTab = hit
                _focus = true
                if let tab = MenuTab(rawValue: hit) {
                    act(tab)
                }
            }
        } else if input.decide {
            if let tab = MenuTab(rawValue: ctx.menuTab) {
                act(tab)
            }
        }
    }
    public override func Step(_ input: UiInput) {
        step(input)
    }

    /// Opens a tab (also called by a submenu whose side focus picked another tab).
    public func act(_ tab: MenuTab) {
        let s = ctx.services
        switch tab {
        case .save, .load:
            if s.savingDisabled {
                ctx.sound(.buzzer)
                return
            }
            ctx.sound(.decide)
            root?.push(SaveLoadScreen(save: tab == .save))
        case .config:
            ctx.sound(.decide)
            root?.push(ConfigScreen())
        case .flowChart:
            ctx.sound(.decide)
            s.openFlowchart()
            openChart(s)
        case .title:
            ctx.sound(.decide)
            if s.autoSaveForTitle() {
                root?.showBanner(.autoSave)
            }
            _toTitle = true
            ctx.backdrop.fade(-1.0 / 30.0)
            super.close()
        }
    }
    public func Act(_ tab: MenuTab) {
        act(tab)
    }

    private func openChart(_ s: IGameServices) {
        if s.replayActive && ctx.gallery.mode == GalleryMode.flowchart.rawValue {
            root?.push(ConfirmDialog(.endReplay, { yes in
                if yes {
                    s.endReplay()
                }
            }))
            return
        }

        if FlowchartScreen.available(ctx, gallery: false) {
            root?.push(FlowchartScreen(gallery: false))
        } else {
            root?.push(MessagePopup(ctx.message(1497), frames: 480.0))
        }
    }

    public override func draw(_ p: UiPainter) {
        ctx.backdrop.draw(p)
        p.withAlpha(fade) {
            Self.drawBase(
                p,
                ctx,
                open: openTab >= 0 ? openTab : -1,
                cursor: sideFocus || openTab < 0 ? ctx.menuTab : -1,
                focus: _focus || sideFocus ? ctx.menuTab : -1
            )
        }
    }
    public override func Draw(_ p: UiPainter) {
        draw(p)
    }

    public static func drawBase(_ p: UiPainter, _ ctx: UiContext, open: Int, cursor: Int, focus: Int) {
        let s = ctx.services
        p.sprite(UiSheets.titleBand, RectF(0, 0, UiMetrics.width, 392))
        p.sprite(UiSheets.sceneBand, RectF(752, 0, 1168, 80))
        p.sprite(UiSheets.underline, RectF(0, 72, UiMetrics.width, 16))
        let phases = ctx.assets.tables.phaseTitleCells(ctx.language)
        let phase = s.phase
        if phase >= 0 && phase < phases.count {
            let c = phases[phase]
            let src = RectF.fromCorners(Float(c.x0), Float(c.y0), Float(c.x1), Float(c.y1))
            p.sprite(UiSheets.phaseTitles, src, RectF(8, 0, src.w, src.h))
        }

        let title = ctx.message(396 + s.sceneTitle)
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var style = TextStyle.menu(0.36)
            style.width = 498
            style.colour = TextStyle.black
            style.drawFlags = BlockDraw.always | BlockDraw.right
            ctx.text.draw(p, title.replacingOccurrences(of: "^", with: ""), style, 110.0, 19.0)
        }

        p.sprite(UiSheets.menuWindow, RectF(0, 0, 312, UiMetrics.height), RectF(56, 3, 312, UiMetrics.height))
        let locked = s.savingDisabled
        for i in 0..<5 {
            let dst = RectF(80, 105.0 + (Float(i) * 75.0), 224, 88)
            if locked && i < 2 {
                p.sprite(UiSheets.menuButtons, RectF(24, 24.0 + (Float(i) * 104.0), 224, 88), dst, 143.0 / 255.0)
                continue
            }
            let col = open == i ? 2 : (focus == i ? 1 : 0)
            p.sprite(UiSheets.menuButtons, RectF(24.0 + (Float(col) * 240.0), 24.0 + (Float(i) * 104.0), 224, 88), dst)
        }

        if cursor >= 0 {
            let blink = 0.5 + (0.5 * abs(sin(Float(ctx.frame) / 60.0 * 3.0)))
            p.sprite(UiSheets.cursorLight, RectF(0, 0, 528, 240), RectF(0, 32.0 + (Float(cursor) * 75.0), 528, 240), blink, .psAdd)
            p.sprite(UiSheets.cursorLine, RectF(0, 0, 224, 56), RectF(86, 136.0 + (Float(cursor) * 75.0), 224, 56), 1.0, .psAdd)
        }
    }

    public static func DrawBase(_ p: UiPainter, _ ctx: UiContext, _ open: Int, _ cursor: Int, _ focus: Int) {
        drawBase(p, ctx, open: open, cursor: cursor, focus: focus)
    }
}
