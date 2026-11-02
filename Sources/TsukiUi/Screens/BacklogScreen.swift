// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Ported from knife (https://github.com/AuroraWright/knife) by AuroraWright: knife/src/ui.rs (Screen::Backlog: key_nav, shoulder, backlog_to, draw), knife/src/game.rs (backlog_quads)
import Foundation
import TsukiCore
import TsukiEngine

/// The backlog: the history ring one page at a time over the frozen, blurred scene darkened to 75 %.
public final class BacklogScreen: UiScreen {
    private var _blocks: [TextBlock] = []
    private var _positions: [(x: Double, y: Double)] = []
    private var _blocksFor: Int = -1
    private let _bar = UiScrollBar()
    private var _page: Int = 0
    private var _jump: Bool = false
    private var _jumpPage: Int = 0

    /// Creates the backlog on the newest page.
    public override init() {
        super.init()
        startHidden()
    }

    /// The page shown: 0 is the newest.
    public var page: Int { _page }
    public var Page: Int { page }

    /// Number of pages.
    public var count: Int { ctx.services.backlog.count }
    public var Count: Int { count }

    public override var fadeInStep: Float { 0.05 }
    public override var FadeInStep: Float { fadeInStep }

    public override var fadeOutStep: Float { 0.05 }
    public override var FadeOutStep: Float { fadeOutStep }

    private static var style: TextStyle {
        TextStyle(
            canvasW: 640,
            canvasH: 344.7,
            sx: 0.74,
            sy: 0.74,
            width: 474,
            height: 220,
            leading: 9,
            spacing: 0,
            colour: TextStyle.white,
            drawFlags: BlockDraw.always | BlockDraw.outline
        )
    }

    public override func onOpened() {
        ctx.sound(.open)
    }
    public override func OnOpened() {
        onOpened()
    }

    public override func onClosed() {
        if _jump {
            ctx.services.backlogJump(_jumpPage)
            root?.clear()
        }
    }
    public override func OnClosed() {
        onClosed()
    }

    private func goTo(_ next: Int) {
        let maxCount = max(0, count - 1)
        let clamped = min(max(next, 0), maxCount)
        if clamped != _page {
            _page = clamped
            ctx.sound(.cursor)
        }
    }

    public override func step(_ input: UiInput) {
        if closing || root?.top !== self {
            return
        }

        let maxCount = max(0, count - 1)
        let toggle = input.shell.contains(.backlog) && input.wheel == 0
        if input.cancel || input.triangle || input.l2 || toggle {
            ctx.sound(.buzzer)
            close()
            return
        }

        let use = _bar.step(
            input,
            fraction: maxCount > 0 ? 1.0 - (Float(_page) / Float(maxCount)) : 0.0,
            height: 608.0,
            canScroll: maxCount > 0
        )
        if let dragged = use.fraction {
            goTo(Int(round((1.0 - dragged) * Float(maxCount))))
        } else if use.page != 0 {
            goTo(_page - (use.page * UiInput.pageSteps))
        }

        if use.consumed {
            return
        }

        if input.up {
            goTo(_page < maxCount ? _page + 1 : (input.upPressed ? 0 : _page))
        } else if input.down {
            goTo(_page > 0 ? _page - 1 : (input.downPressed ? maxCount : _page))
        } else if input.leftPressed || input.l1 {
            goTo(maxCount)
        } else if input.rightPressed || input.r1 {
            goTo(0)
        }

        if input.wheel > 0 {
            goTo(_page + 1)
        } else if input.wheel < 0 {
            goTo(_page - 1)
        }

        if input.shell.contains(.replayVoice) {
            replayVoice(-1)
        }

        if input.click && input.pointerActive && input.pointerX < 543.0 * 3.0 {
            let msg = messageAt(input.pointerY)
            if msg >= 0 && ctx.services.backlog.count > _page && ctx.services.backlog[_page].messages[msg].voiceId >= 0 {
                replayVoice(msg)
            } else {
                askJump()
            }
        } else if input.decide && !input.click {
            askJump()
        }
    }
    public override func Step(_ input: UiInput) {
        step(input)
    }

    private func replayVoice(_ message: Int) {
        let pages = ctx.services.backlog
        guard _page < pages.count else { return }

        let msgs = pages[_page].messages
        var voice = -1
        if message >= 0 && message < msgs.count {
            voice = msgs[message].voiceId
        } else {
            for m in msgs {
                if m.voiceId >= 0 {
                    voice = m.voiceId
                    break
                }
            }
        }

        if voice >= 0 {
            ctx.services.playBacklogVoice(voice)
        }
    }

    private func askJump() {
        let pages = ctx.services.backlog
        guard _page < pages.count, pages[_page].jumpable else {
            ctx.sound(.buzzer)
            return
        }

        let page = _page
        root?.push(ConfirmDialog(.backlogJump, { [weak self] yes in
            if yes {
                self?._jump = true
                self?._jumpPage = page
                self?.close()
            }
        }))
    }

    private func messageAt(_ py: Float) -> Int {
        layout()
        let ty = py / (UiMetrics.height / 344.7)
        for i in 0..<_blocks.count {
            let top = Float(_positions[i].y)
            let nLines = max(1, _blocks[i].nLines)
            let lineHeightsSum = Float(_blocks[i].lineHeight.prefix(nLines).reduce(0, +))
            let leadingSum = Float(_blocks[i].leading * max(0, _blocks[i].nLines - 1))
            let bottom = top + lineHeightsSum + leadingSum
            if ty >= top && ty < bottom {
                return i
            }
        }
        return -1
    }

    private func layout() {
        if _blocksFor == _page && !_blocks.isEmpty {
            return
        }

        let pages = ctx.services.backlog
        _blocksFor = _page
        if _page >= pages.count {
            _blocks = []
            _positions = []
            return
        }

        let msgs = pages[_page].messages
        _blocks = msgs.enumerated().map { j, m in
            ctx.text.layout(m.text, Self.style, 79 + min(j, 10))
        }
        _positions = MessageWindow.pagePositions(_blocks, ctx.language, blankBefore: msgs.map { $0.blankBefore })
    }

    public override func draw(_ p: UiPainter) {
        p.withAlpha(fade) {
            p.cover(0.75)
            layout()
            let style = Self.style
            for i in 0..<_blocks.count {
                ctx.text.drawBlock(p, _blocks[i], style, Float(_positions[i].x), Float(_positions[i].y))
            }

            let n = count
            if n > 1 {
                UiWidgets.scrollBar(p, 1.0 - (Float(_page) / Float(n - 1)), 608.0, 1.0, _bar)
            }

            UiWidgets.guide(p, UiWidgets.guideBacklog, decideIsCross: ctx.services.decideIsCross)
        }
    }
    public override func Draw(_ p: UiPainter) {
        draw(p)
    }
}
