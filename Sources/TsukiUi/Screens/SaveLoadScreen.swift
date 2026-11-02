// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Ported from knife (https://github.com/AuroraWright/knife) by AuroraWright: knife/src/ui.rs (Screen::SaveLoad)
import Foundation
import TsukiCore
import TsukiEngine

/// The save and load list.
public final class SaveLoadScreen: UiScreen, ISubMenu {
    private static let visible: Int = 4

    // route of phases 11..36 for the info panel: 0 Arcueid, 1 Ciel, else neutral
    private static let infoRoute: [UInt8] = [2, 1, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0, 1, 1, 1, 1, 1]

    private let _items = UiItemList()
    private let _bar = UiScrollBar()
    private var _list: [Int] = []
    private var _scroll: Int = 0
    private var _row: Int = 0
    private var _flash: Float = 0
    private var _popup: MessagePopup?
    private var _saveWait: Float = -1
    private var _deleteWait: Float = -1
    private var _savedSlot: Int = -1
    private var _loadSlot: Int = -1
    private var _loadClosing: Bool = false

    /// Creates the list for saving (true) or loading.
    public init(save: Bool) {
        self.save = save
        super.init()
        self._side = SideFocus(self, save ? 0 : 1)
        startHidden()
    }

    public init(_ save: Bool) {
        self.save = save
        super.init()
        self._side = SideFocus(self, save ? 0 : 1)
        startHidden()
    }

    /// True for the save list, false for the load list.
    public let save: Bool
    public var Save: Bool { save }

    public var tab: Int { save ? 0 : 1 }
    public var Tab: Int { tab }

    private var _side: SideFocus!
    public var side: SideFocus { _side }
    public var Side: SideFocus { side }

    /// The slot numbers of the list in display order.
    public var list: [Int] { _list }
    public var List: [Int] { _list }

    /// The first visible list entry.
    public var scroll: Int { _scroll }
    public var Scroll: Int { scroll }

    /// The slot under the cursor, or -1.
    public var cursorSlot: Int {
        _row + _scroll < _list.count ? _list[_row + _scroll] : -1
    }
    public var CursorSlot: Int { cursorSlot }

    /// True while the list was opened from the title screen.
    public var fromTitle: Bool {
        guard let root = root, !root.stack.isEmpty else { return false }
        return root.stack[0] is TitleScreen
    }
    public var FromTitle: Bool { fromTitle }

    public override var fadeInStep: Float { 0.024 }
    public override var FadeInStep: Float { fadeInStep }

    public override var fadeOutStep: Float { 0.048 }
    public override var FadeOutStep: Float { fadeOutStep }

    /// Canvas position of list frame `i`.
    public static func framePosition(_ i: Int) -> (x: Float, y: Float) {
        (133.667 * 3.0, (36.919 * UiMetrics.unitY) + (93.748 * UiMetrics.unitY * Float(i)))
    }
    public static func FramePosition(_ i: Int) -> (x: Float, y: Float) {
        framePosition(i)
    }

    public override func onOpened() {
        rebuild(resetCursor: true)
        if fromTitle {
            ctx.backdrop.fade(0.02)
        }
        _row = 0
        _scroll = 0
    }
    public override func OnOpened() {
        onOpened()
    }

    /// Rebuilds the list from the slots.
    public func rebuild(resetCursor: Bool) {
        let slots = ctx.services.slots
        let maxIndex = save ? 100 : 139
        let used = slots.filter { $0.used && $0.index < maxIndex }
            .sorted { a, b in
                if a.date != b.date {
                    return a.date > b.date
                }
                return a.index > b.index
            }
            .map { $0.index }

        _list = []
        if save {
            let freeList = slots.filter { $0.index < 100 && !$0.used }.map { $0.index }
            if let free = freeList.min() {
                _list.append(free)
            }
        }
        _list.append(contentsOf: used)

        let maxScroll = max(0, _list.count - Self.visible)
        _scroll = min(_scroll, maxScroll)
        _row = min(_row, max(0, min(_list.count - _scroll, Self.visible) - 1))
        if resetCursor {
            _row = 0
            _scroll = 0
        }

        buildItems()
    }
    public func Rebuild(_ resetCursor: Bool) {
        rebuild(resetCursor: resetCursor)
    }

    private func buildItems() {
        _items.clear()
        for i in 0..<Self.visible {
            if _scroll + i < _list.count {
                let pos = Self.framePosition(i)
                _items.add(RectF(pos.x + 32.0, pos.y + 28.0, 898.0, 212.0), _list[_scroll + i])
            }
        }

        if fromTitle {
            _items.add(RectF(0, 0, 360.0, UiMetrics.height), -1)
        }

        _items.cursor = min(_row, max(0, min(_list.count - _scroll, Self.visible) - 1))
    }

    private var busy: Bool {
        _popup != nil || _saveWait >= 0 || _deleteWait >= 0 || _loadSlot >= 0 || closing || (root?.top is ConfirmDialog) || (root?.top is MessagePopup)
    }

    public override func stepBackground() {
        _flash = max(0.0, _flash - 0.2)
        stepFlows()
    }
    public override func StepBackground() {
        stepBackground()
    }

    public override func step(_ input: UiInput) {
        _flash = max(0.0, _flash - 0.2)
        stepFlows()
        if closing || root?.top !== self {
            return
        }

        if side.step(input, ctx) {
            return
        }

        if busy {
            return
        }

        if input.cancel {
            ctx.sound(.buzzer)
            close()
            return
        }

        if side.clickOnTab(input, ctx) {
            return
        }

        let range = max(0, _list.count - Self.visible)
        let use = _bar.step(
            input,
            fraction: range > 0 ? Float(_scroll) / Float(range) : 0.0,
            height: 608.0,
            canScroll: range >= 1
        )
        if let dragged = use.fraction {
            setScroll(Int(round(dragged * Float(range))))
        } else if use.page != 0 {
            setScroll(_scroll + (use.page * Self.visible))
        }

        if use.consumed {
            return
        }

        if input.left && side.menu != nil {
            side.enter()
            return
        }

        let count = _list.count
        let cur = _row + _scroll
        var next = cur
        if (input.up || input.down) && count > 0 {
            let dy = input.up ? -1 : 1
            if cur + dy >= 0 && cur + dy < count {
                next = cur + dy
            } else if input.upPressed || input.downPressed {
                next = dy < 0 ? count - 1 : 0
            } else {
                next = cur
            }
        }

        if input.wheel != 0 && count > 0 {
            let clampedWheel = min(max(input.wheel, -50), 50)
            next = min(max(cur - clampedWheel, 0), count - 1)
        }

        if input.pointerMoved {
            let hit = _items.hitTest(input.pointerX, input.pointerY)
            if hit >= 0 && _items.items[hit].id >= 0 {
                next = _scroll + hit
            }
        }

        if next != cur {
            if next < _scroll {
                _scroll = next
            } else if next >= _scroll + Self.visible {
                _scroll = next + 1 - Self.visible
            }
            _row = next - _scroll
            _flash = 1.0
            ctx.sound(.cursor)
            buildItems()
        }

        if input.triangle || input.deleteData {
            deleteKey()
            return
        }

        if input.square {
            copyKey()
            return
        }

        let clicked = _items.clicked(input)
        if clicked >= 0 {
            let id = _items.items[clicked].id
            if id < 0 {
                ctx.sound(.buzzer)
                close()
                return
            }
            _row = clicked
            choose(id)
        } else if input.decide && !input.click {
            chooseCursor()
        }
    }
    public override func Step(_ input: UiInput) {
        step(input)
    }

    private func setScroll(_ to: Int) {
        let maxScroll = max(0, _list.count - Self.visible)
        let clamped = min(max(to, 0), maxScroll)
        if clamped == _scroll {
            return
        }
        _scroll = clamped
        _row = min(_row, max(0, min(_list.count - _scroll, Self.visible) - 1))
        _flash = 1.0
        buildItems()
    }

    private func chooseCursor() {
        if _list.isEmpty {
            if !save {
                ctx.sound(.buzzer)
                popup(ctx.sysmes(193), 480.0)
            }
            return
        }
        choose(_list[_scroll + _row])
    }

    private func slot(_ index: Int) -> UiSlot {
        ctx.services.slots[index]
    }

    private func choose(_ slotIndex: Int) {
        if save {
            if slot(slotIndex).used {
                root?.push(ConfirmDialog(.overwrite, { [weak self] yes in
                    if yes {
                        self?.doSave(slotIndex)
                    }
                }))
            } else {
                doSave(slotIndex)
            }
        } else if slot(slotIndex).used {
            root?.push(ConfirmDialog(.load, { [weak self] yes in
                if yes {
                    guard let self = self else { return }
                    self._popup = self.root?.push(MessagePopup(self.ctx.sysmes(184), held: true))
                    self._loadSlot = slotIndex
                }
            }))
        }
    }

    private func popup(_ text: String, _ frames: Float) {
        root?.push(MessagePopup(text, frames: frames))
    }

    private func doSave(_ slotIndex: Int) {
        if ctx.services.save(slotIndex) {
            _popup = root?.push(MessagePopup(ctx.sysmes(183), held: true, minimumFrames: 30.0))
            _saveWait = 0
            _savedSlot = slotIndex
            _popup?.release()
        } else {
            popup(ctx.sysmes(189), 480.0)
            rebuild(resetCursor: false)
        }
    }

    private func copyKey() {
        let currentSlot = cursorSlot
        if currentSlot < 0 || !slot(currentSlot).used {
            ctx.sound(.buzzer)
            return
        }

        root?.push(ConfirmDialog(.copy, { [weak self] yes in
            guard let self = self else { return }
            if !yes {
                return
            }
            if self.ctx.services.copy(currentSlot) {
                self.ctx.sound(.done)
                self.rebuild(resetCursor: false)
            } else {
                self.ctx.sound(.buzzer)
                self.popup(self.ctx.sysmes(189), 480.0)
            }
        }))
    }

    private func deleteKey() {
        if !save && _list.isEmpty {
            return
        }
        let currentSlot = cursorSlot
        if currentSlot < 0 {
            return
        }
        if !slot(currentSlot).used {
            popup(ctx.sysmes(193), 480.0)
            return
        }

        root?.push(ConfirmDialog(.delete, { [weak self] yes in
            guard let self = self else { return }
            if yes {
                self._popup = self.root?.push(MessagePopup(self.ctx.sysmes(188), held: true))
                self.ctx.services.delete(currentSlot)
                self._deleteWait = 0
            }
        }))
    }

    private func stepFlows() {
        if let p = _popup, p.closing || p.finished {
            _popup = nil
        }

        if _saveWait >= 0 {
            let n = _saveWait + 1.0
            if _saveWait < 30.0 && n >= 30.0 {
                ctx.sound(.done)
            }

            if n >= 30.0 + 41.0 {
                _saveWait = -1
                rebuild(resetCursor: false)
                selectSlot(_savedSlot)
            } else {
                _saveWait = n
            }
        }

        if _deleteWait >= 0 {
            let n = _deleteWait + 1.0
            if _deleteWait < 1.0 && n >= 1.0 {
                ctx.sound(.done)
            }

            if n >= 17.0 {
                _deleteWait = -1
                _popup?.release()
                rebuild(resetCursor: false)
                popup(ctx.message(217), 300.0)
            } else {
                _deleteWait = n
            }
        }

        if _loadSlot >= 0, let p = _popup, p.fullyShown {
            let slotIndex = _loadSlot
            _loadSlot = -1
            p.release()
            if fromTitle {
                _loadClosing = true
                close()
                if let root = root, !root.stack.isEmpty, let t = root.stack[0] as? TitleScreen {
                    t.beginLoad(slotIndex)
                }
            } else if ctx.services.load(slotIndex) {
                root?.clear()
            } else {
                popup(ctx.sysmes(190), 480.0)
            }
        }
    }

    private func selectSlot(_ slotIndex: Int) {
        guard let i = _list.firstIndex(of: slotIndex) else {
            return
        }
        _scroll = min(max(i, 0), max(0, _list.count - Self.visible))
        _row = min(i - _scroll, Self.visible - 1)
        buildItems()
    }

    /// True when the load closed over the title to hand the slot to the title.
    public var loadHandedToTitle: Bool { _loadClosing }
    public var LoadHandedToTitle: Bool { loadHandedToTitle }

    public override func onClosed() {
        _popup?.release()
    }
    public override func OnClosed() {
        onClosed()
    }

    public override func draw(_ p: UiPainter) {
        p.withAlpha(fade) {
            p.sprite(UiSheets.savePanel, RectF(0, 0, 1560, 1080), RectF(360, 0, 1560, 1080))
            var selected: UiSlot? = nil
            let cursorRow = min(_row, max(0, min(_list.count - _scroll, Self.visible) - 1))
            for i in 0..<Self.visible {
                if _scroll + i >= _list.count {
                    break
                }
                let slotIndex = _list[_scroll + i]
                let pos = Self.framePosition(i)
                let hover = (i == cursorRow) && !side.active
                let win = hover ? RectF(31, 336, 960, 272) : RectF(32, 32, 960, 272)
                p.sprite(UiSheets.saveFrame, win, RectF(pos.x, pos.y, 960, 272))
                if hover && _flash > 0 {
                    p.sprite(UiSheets.saveFrame, RectF(31, 336, 960, 272), RectF(pos.x, pos.y, 960, 272), _flash, .psAdd)
                }

                let d = slot(slotIndex)
                if !d.used {
                    continue
                }

                if hover {
                    selected = d
                }

                drawEntry(p, d, pos.x, pos.y)
            }

            if let sel = selected {
                drawInfo(p, sel)
            }

            let range = max(0, _list.count - Self.visible)
            if range >= 1 {
                UiWidgets.scrollBar(p, Float(_scroll) / Float(range), 608.0, 1.0, _bar)
            }

            UiWidgets.guide(p, UiWidgets.guideSaveList, decideIsCross: ctx.services.decideIsCross)
        }
    }
    public override func Draw(_ p: UiPainter) {
        draw(p)
    }

    private func drawEntry(_ p: UiPainter, _ d: UiSlot, _ fx: Float, _ fy: Float) {
        if let thumb = ctx.services.thumbnail(d.index) {
            p.thumbnail(d.index, version: thumb.version, dst: RectF(fx + 52.0, fy + 56.0, 300.0 * 0.827 * 1.15, 53.0 * 1.092 * 1.15 * UiMetrics.unitY))
        }

        p.sprite(UiSheets.saveSceneTag, RectF(0, 0, 64, 24), RectF(fx + 359.0, fy + 192.0, 64, 24))

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmm"
        let stamp = formatter.string(from: d.date)
        let chars = Array(stamp)
        let gy = fy + 60.0
        let dateX: [Float] = [118.0, 123.5, 129.0, 134.5, 145.5, 151.0, 162.0, 167.5]
        let timeX: [Float] = [182.333, 187.833, 198.833, 204.333]

        for k in 0..<min(8, chars.count) {
            if let digit = Int(String(chars[k])) {
                Self.digit(p, UiSheets.saveDateDigits, digit, fx + (dateX[k] * 3.0), gy)
            }
        }

        Self.digit(p, UiSheets.saveDateDigits, 10, fx + (140.0 * 3.0), gy)
        Self.digit(p, UiSheets.saveDateDigits, 10, fx + (156.5 * 3.0), gy)

        for k in 0..<min(4, max(0, chars.count - 8)) {
            if let digit = Int(String(chars[8 + k])) {
                Self.digit(p, UiSheets.saveTimeDigits, digit, fx + (timeX[k] * 3.0), gy)
            }
        }

        Self.digit(p, UiSheets.saveTimeDigits, 10, fx + (193.333 * 3.0), gy)

        if d.index >= 100 {
            p.sprite(UiSheets.saveAuto, RectF(0, 0, 192, 32), RectF(fx + 744.0, fy + 26.0, 192, 32))
        }

        let titles = ctx.assets.tables.saveTitleCells(ctx.language)
        if !titles.isEmpty {
            let phase = min(max(d.phase, 0), titles.count - 1)
            let c = titles[phase]
            let src = RectF.fromCorners(Float(c.x0), Float(c.y0), Float(c.x1), Float(c.y1))
            p.sprite(UiSheets.saveTitles, src, RectF(fx + 359.0, fy + 121.0, src.w, src.h))
        }

        let scene = ctx.message(396 + d.sceneTitle)
        if !scene.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var style = TextStyle.menu(0.35)
            style.width = 190
            style.colour = TextStyle.black
            style.drawFlags = BlockDraw.always
            ctx.text.draw(p, scene.replacingOccurrences(of: "^", with: ""), style, (fx + 423.0) / UiMetrics.unitX, (fy + 188.0) / UiMetrics.unitY)
        }
    }

    private static func digit(_ p: UiPainter, _ sheet: UiSheet, _ d: Int, _ x: Float, _ y: Float) {
        p.sprite(sheet, RectF(Float(16 + (32 * d)), 16, 24, 32), RectF(x, y, 24, 32))
    }

    private func drawInfo(_ p: UiPainter, _ d: UiSlot) {
        let routeIndex = d.phase - 11
        let route: Int
        if routeIndex >= 0 && routeIndex < Self.infoRoute.count {
            route = Int(Self.infoRoute[routeIndex])
        } else {
            route = 2
        }

        let card: UiSheet
        switch route {
        case 0: card = UiSheets.saveInfoArc
        case 1: card = UiSheets.saveInfoCiel
        default: card = UiSheets.saveInfoUnknown
        }

        p.sprite(card, RectF(0, 0, 472, 712), RectF(1360, 95, 472, 712))
        if !d.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var style = TextStyle.menu(0.4)
            style.width = 130
            style.height = 80
            style.leading = 4
            style.colour = TextStyle.black
            style.drawFlags = BlockDraw.always
            ctx.text.draw(p, d.notes, style, 463.333, 259.259)
        }
    }
}
