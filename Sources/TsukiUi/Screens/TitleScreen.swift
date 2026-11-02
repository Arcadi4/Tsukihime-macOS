// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Ported from knife (https://github.com/AuroraWright/knife) by AuroraWright: knife/src/ui.rs (Intro, enter_title, draw_title, title_entries, title_slot, act: NewGame / Continue) and knife/src/fx.rs (LogoFx)
import Foundation
import TsukiCore
import TsukiEngine

/// The title menu's items.
public enum TitleItem: Int, Sendable {
    case `continue` = 0
    case newGame = 1
    case load = 2
    case config = 3
    case gallery = 5
    case exit = 7
}

/// What the title is doing.
public enum TitlePhase: Int, Sendable {
    case fadeIn
    case idle
    case intro
    case caution
    case whiteOut
    case loading
    case leaving
}

/// The G002 title stage rule.
public enum TitleStageRule {
    public static func advance(_ g2: Int, _ storyStarted: Bool, _ bit560: Bool, _ bit383: Bool, _ bit562: Bool) -> Int {
        if !storyStarted {
            return g2
        }

        var stage = g2
        if stage < 0 || stage > 5 {
            stage = 0
        }

        switch stage {
        case 0: return bit560 ? 1 : 0
        case 1: return bit383 ? 3 : 1
        case 3: return bit562 ? 5 : 3
        case 2, 4: return 0
        default: return stage
        }
    }

    public static func Advance(_ g2: Int, _ storyStarted: Bool, _ bit560: Bool, _ bit383: Bool, _ bit562: Bool) -> Int {
        advance(g2, storyStarted, bit560, bit383, bit562)
    }
}

/// The title screen.
public final class TitleScreen: UiScreen {
    private static let loopPoint: Double = 8.0333
    public static let idleFrames: Int = 3600
    public static let IdleFrames: Int = idleFrames
    private static let screenW: Float = UiMetrics.width

    private let _items = UiItemList()
    private var _shards: [Shard] = []
    private var _dots: [Dot] = []
    private var _shardAcc: Float = 0
    private var _g2: Int = 0
    private var _movieStarted: Bool = false
    private var _passed: Bool = false
    private var _seekDue: Bool = false
    private var _black: Float = 1.0
    private var _white: Float = 0
    private var _menuAlpha: Float = 0
    private var _logo: Float = 0
    private var _logoRising: Bool = true
    private var _grow: Float = 0
    private var _pulse: Float = 0
    private var _clock: Float = 0
    private var _frame: Int = 0
    private var _introStep: Int = 0
    private var _introT: Int = 0
    private var _cautionIdx: Int = 0
    private var _cautionStep: Int = 0
    private var _cautionT: Int = 0
    private var _cautionA: Float = 0
    private var _cover: Float = 0
    private var _entries: [TitleItem] = []
    private var _loadSlot: Int = -1
    private var _popup: MessagePopup?
    private var _quitDialog: ConfirmDialog?
    private var _idleFrames: Int = 0
    private var _idleHidden: Bool = false
    private var _wokeFromIdle: Bool = false
    private var _started: Bool = false

    public override init() {
        super.init()
    }

    /// The title is on show.
    public var idle: Bool { phase == .idle }
    public var Idle: Bool { idle }

    /// What the title is doing.
    public private(set) var phase: TitlePhase = .fadeIn
    public var Phase: TitlePhase { phase }

    /// The cursor item, or null while there is none.
    public var cursor: TitleItem? {
        if _items.cursor >= 0 && _items.cursor < _entries.count {
            return _entries[_items.cursor]
        }
        return nil
    }
    public var Cursor: TitleItem? { cursor }

    /// True while the logo and the menu have faded out after idle frames with no input.
    public var idleHidden: Bool { _idleHidden }
    public var IdleHidden: Bool { idleHidden }

    /// True while PRESS ANY BUTTON shows instead of the menu.
    public private(set) var pressMode: Bool = false
    public var PressMode: Bool { pressMode }

    /// The G002 title stage after the rule step.
    public var stage: Int { _g2 }
    public var Stage: Int { stage }

    /// The still behind the menu.
    public var still: UiSheet {
        if pressMode {
            return UiSheets.titleBg0
        }
        let table = ctx.assets.tables.titleBackgroundTable
        let clamped = min(max(_g2, 0), 5)
        let t = clamped < table.count ? table[clamped] : 1
        return UiSheets.titleStill(t)
    }
    public var Still: UiSheet { still }

    public override var opaque: Bool { true }
    public override var Opaque: Bool { true }

    private var needsIntro: Bool {
        let titleInfo = ctx.services.title
        return titleInfo.prologueSeen && titleInfo.storyStarted && !ctx.titleIntroShown
    }

    public override func onOpened() {
        ctx.backdrop.reset()
        let info = ctx.services.title
        let s = ctx.services
        pressMode = !info.storyStarted
        _g2 = TitleStageRule.advance(info.titleStage, info.storyStarted, s.sceneBit(560), s.sceneBit(383), s.sceneBit(562))
        if _g2 != info.titleStage {
            s.setGlobal(2, _g2)
        }

        if !info.prologueSeen {
            phase = .leaving
            _started = true
            s.startScene(260)
            return
        }

        if needsIntro {
            phase = .intro
            _introStep = 0
        } else {
            beginTitle()
        }

        buildEntries()
    }
    public override func OnOpened() {
        onOpened()
    }

    private func beginTitle() {
        phase = .fadeIn
        _black = 1.0
        _logo = 0
        _logoRising = true
        let s = ctx.services
        let info = ctx.services.title
        if info.storyStarted {
            let table = ctx.assets.tables.titleBackgroundTable
            let clamped = min(max(_g2, 0), 5)
            let t = clamped < table.count ? table[clamped] : 1
            if t - 1 < 4 {
                s.startTitleMovie(t - 1)
                _movieStarted = true
            }
        }

        s.playBgm(_g2 == 5 ? 72 : 2)
        buildEntries()
    }

    private func buildEntries() {
        var list: [TitleItem] = []
        if ctx.services.title.continueSlot >= 0 {
            list.append(.continue)
        }
        list.append(contentsOf: [.newGame, .load, .config, .gallery, .exit])
        _entries = list
        _items.clear()
        let count = _entries.count
        for i in 0..<count {
            let slot = Self.itemRect(i, count)
            let six = count >= 6
            let top: Float = six ? slot.y + (4.0 * UiMetrics.unitY) : (trunc(slot.y / UiMetrics.unitY) + 4.0) * UiMetrics.unitY
            let height: Float = (six ? Self.sixRowPitch : 22.0) * UiMetrics.unitY
            _items.add(RectF(trunc(272.0) * UiMetrics.unitX, top, 99.0 * UiMetrics.unitX, height), _entries[i].rawValue)
        }

        if _items.cursor < 0 || _items.cursor >= _entries.count {
            _items.cursor = pressMode ? -1 : 0
        }
    }

    public static func itemRect(_ i: Int, _ n: Int) -> RectF {
        if n >= 6 {
            return RectF(272.0 * UiMetrics.unitX, (sixRowTop + (Float(i) * sixRowPitch)) * UiMetrics.unitY, 296.0, 72.0)
        }
        let y0: Float = n >= 5 ? 298.66666 : 312.35553
        return RectF(272.0 * UiMetrics.unitX, (y0 + (Float(i) * 23.22963)) * UiMetrics.unitY, 296.0, 72.0)
    }
    public static func ItemRect(_ i: Int, _ n: Int) -> RectF {
        itemRect(i, n)
    }

    public static let sixRowTop: Float = 297.0
    public static let SixRowTop: Float = sixRowTop
    public static let sixRowPitch: Float = 19.6
    public static let SixRowPitch: Float = sixRowPitch
    public static let itemInkTop: Float = 28.0
    public static let ItemInkTop: Float = itemInkTop
    public static let copyrightInkTop: Float = 1035.0
    public static let CopyrightInkTop: Float = copyrightInkTop

    private static func cell(_ item: TitleItem, _ col: Int) -> RectF {
        let y: Float
        switch item {
        case .continue: y = 376.0
        case .newGame: y = 24.0
        case .load: y = 112.0
        case .config: y = 200.0
        default: y = 288.0
        }
        return RectF(24.0 + (312.0 * Float(col)), y, 296.0, 72.0)
    }

    public override func stepBackground() {
        step(UiInput.empty)
    }
    public override func StepBackground() {
        stepBackground()
    }

    public override func step(_ input: UiInput) {
        _frame += 1
        _clock += 1.0 / 60.0
        _pulse += 1.0
        _grow = min(1.0, _grow + 0.1)
        reclaimTitle(input)
        stepFx()
        stepMovie()

        switch phase {
        case .intro:
            stepIntro(input)
            return
        case .caution:
            stepCaution(input)
            return
        case .whiteOut:
            _white += 1.0 / 60.0
            if _white > 1.2 {
                begin(110)
            }
            return
        case .loading:
            stepLoading()
            return
        case .leaving:
            stepLeaving()
            return
        default:
            break
        }

        stepTitle(input)
    }
    public override func Step(_ input: UiInput) {
        step(input)
    }

    private func begin(_ scene: Int) {
        if _started {
            return
        }
        _started = true
        ctx.services.startScene(scene)
        root?.clear()
    }

    private func reclaimTitle(_ input: UiInput) {
        _wokeFromIdle = false
        if root?.top !== self || (phase != .idle && phase != .fadeIn) {
            _idleFrames = 0
            _idleHidden = false
            return
        }

        let backdrop = ctx.backdrop
        if backdrop.visible && backdrop.speed >= 0 {
            backdrop.fade(-0.02)
        }

        let touched = input.pointerMoved || input.any || input.up || input.down || input.left || input.right || input.wheel != 0
        if touched {
            _wokeFromIdle = _idleHidden
            _idleFrames = 0
            _idleHidden = false
        } else if phase == .idle && !pressMode && _menuAlpha >= 1.0 {
            _idleFrames += 1
            if _idleFrames >= Self.idleFrames {
                _idleHidden = true
            }
        }

        if touched && phase == .idle && _menuAlpha >= 1.0 {
            if backdrop.visible {
                backdrop.reset()
            }
            _logo = 1.0
            _logoRising = false
        }
    }

    private func stepFx() {
        let covered = (root?.top !== self && root?.top !== _quitDialog) || ctx.backdrop.visible || _idleHidden
        if (phase == .idle || phase == .fadeIn) && _black < 0.5 {
            _logoRising = !covered
            _logo = min(max(_logo + (covered ? -1.0 / 60.0 : 1.0 / 120.0), 0.0), 1.0)
        }
        updateParticles()
    }

    private func stepMovie() {
        if !_movieStarted {
            return
        }
        let t = ctx.services.titleMovieTime
        if t > Self.loopPoint {
            _passed = true
            _seekDue = true
        } else if t >= 0 && t < Self.loopPoint && _passed && _seekDue {
            ctx.services.seekTitleMovie(Self.loopPoint)
            _seekDue = false
        }
    }

    private func stepTitle(_ input: UiInput) {
        if phase == .fadeIn {
            _black = max(0.0, _black - (1.0 / 120.0))
            if _black <= 0 {
                phase = .idle
            }
        }

        _menuAlpha = min(1.0, max(_menuAlpha, 1.0 - _black))
        if root?.top !== self {
            return
        }

        if input.cancel && _menuAlpha >= 1.0 && !_wokeFromIdle {
            askToQuit()
            return
        }

        if pressMode {
            if input.any && _menuAlpha >= 1.0 {
                _logo = 1.0
                ctx.sound(.start)
                ctx.services.fadeOutBgm(1.5)
                phase = .caution
                _cautionIdx = 0
                _cautionStep = 0
                _cautionT = 0
                _cover = 0
            }
            return
        }

        if _menuAlpha < 1.0 {
            return
        }

        let before = _items.cursor
        if input.up {
            _items.move(-1)
        } else if input.down {
            _items.move(1)
        }

        _items.hover(input)
        if _items.cursor != before {
            _grow = 0
            _logo = 1.0
            _logoRising = false
            ctx.sound(.cursor)
        }

        if _wokeFromIdle {
            return
        }

        let hit = _items.clicked(input)
        if hit >= 0 {
            _items.cursor = hit
            choose(_entries[hit])
        } else if input.decide && !input.click && _items.cursor >= 0 {
            choose(_entries[_items.cursor])
        }
    }

    private func choose(_ item: TitleItem) {
        let s = ctx.services
        _logo = 1.0
        switch item {
        case .continue:
            let slot = s.title.continueSlot
            if slot < 0 {
                ctx.sound(.buzzer)
                _popup = root?.push(MessagePopup(ctx.sysmes(193), frames: 480.0))
                return
            }
            ctx.sound(.decide)
            _loadSlot = slot
            _popup = root?.push(MessagePopup(ctx.sysmes(184), held: true))
            phase = .loading
        case .newGame:
            ctx.sound(.start)
            s.fadeOutBgm(1.5)
            if s.title.prologueSeen {
                phase = .whiteOut
                _white = 0
            } else {
                begin(260)
            }
        case .load:
            ctx.sound(.decide)
            root?.push(SaveLoadScreen(save: false))
        case .config:
            ctx.sound(.decide)
            root?.push(ConfigScreen())
        case .gallery:
            ctx.sound(.decide)
            ctx.backdrop.fade(0.02)
            phase = .leaving
            _loadSlot = -2
        case .exit:
            askToQuit()
        }
    }

    private func askToQuit() {
        if let q = _quitDialog, !q.finished {
            return
        }
        if _started {
            return
        }

        ctx.sound(.open)
        _quitDialog = root?.push(ConfirmDialog(Self.quitMessage, true, { [weak self] yes in
            if yes {
                self?.ctx.services.requestQuit()
            }
        }))
    }

    public static let quitMessage: Int = 236
    public static let QuitMessage: Int = quitMessage

    public func beginLoad(_ slot: Int) {
        ctx.services.fadeOutBgm(1.5)
        _loadSlot = slot
        _black = 0
        phase = .leaving
    }
    public func BeginLoad(_ slot: Int) {
        beginLoad(slot)
    }

    private func enterGallery(afterReplay: Bool) {
        ctx.services.stopTitleMovie()
        _movieStarted = false
        _passed = false
        _seekDue = false
        phase = .idle
        _started = false
        _loadSlot = -1
        _black = 1.0
        _menuAlpha = 0
        root?.push(GalleryScreen(afterReplay: afterReplay))
    }

    public func resumeInGallery() {
        enterGallery(afterReplay: true)
    }
    public func ResumeInGallery() {
        resumeInGallery()
    }

    public func returnFromGallery() {
        ctx.backdrop.fade(-0.02)
        beginTitle()
        _menuAlpha = 0
        if let i = _entries.firstIndex(of: .gallery) {
            _items.cursor = i
        }
    }
    public func ReturnFromGallery() {
        returnFromGallery()
    }

    private func stepLoading() {
        if let p = _popup, p.fullyShown {
            p.release()
            _popup = nil
            ctx.services.fadeOutBgm(1.5)
            _black = 0
            phase = .leaving
        }
    }

    private func stepLeaving() {
        if _started {
            return
        }

        _black += _loadSlot == -2 ? 0.02 : 0.01
        if _black < 1.2 {
            return
        }

        _started = true
        if _loadSlot == -2 {
            ctx.services.openGallery()
            if ctx.assets.gallery != nil {
                enterGallery(afterReplay: false)
            }
            return
        }

        if ctx.services.load(_loadSlot) {
            ctx.services.resumeLoaded()
            root?.clear()
        } else {
            _started = false
            _black = 0
            phase = .idle
            _popup = root?.push(MessagePopup(ctx.sysmes(190), frames: 480.0))
        }
    }

    private func stepIntro(_ input: UiInput) {
        let s = ctx.services
        switch _introStep {
        case 0:
            _white = min(1.2, _white + (1.0 / 60.0))
            _introT += 1
            if _introT >= 61 {
                s.startIntroMovie(38)
                _introStep = 1
                _introT = 0
                _white = 1.0
            }
        case 1:
            _introT += 1
            if _introT > 30 {
                _white = max(0.0, _white - (1.0 / 60.0))
            }
            if input.any && _introT > 120 && s.introMoviePlaying {
                s.stopIntroMovie()
            }
            if !s.introMoviePlaying && _introT > 2 {
                _introStep = 2
                _introT = 0
                _cautionA = 0
            }
        case 2:
            _cautionA = min(1.0, _cautionA + 0.025)
            if _cautionA >= 1.0 {
                _introT += 1
            }
            if _cautionA >= 1.0 && (_introT >= 480 || input.any) {
                _introStep = 3
            }
        case 3:
            _cautionA -= 0.025
            if _cautionA <= 0 {
                ctx.titleIntroShown = true
                _white = 0
                beginTitle()
            }
        default:
            break
        }
    }

    private func stepCaution(_ input: UiInput) {
        switch _cautionStep {
        case 0:
            _cover = min(1.0, _cover + (1.0 / 60.0))
            if _cover >= 1.0 {
                _cautionStep = 1
            }
        case 1:
            _cover = max(0.0, _cover - (1.0 / 60.0))
            if _cover <= 0 {
                _cautionStep = 2
                _cautionT = 0
            }
        case 2:
            _cautionT += 1
            if _cautionT >= 720 || (_cautionT > 240 && input.any) {
                _cautionStep = 3
            }
        case 3:
            _cover = min(1.0, _cover + (1.0 / 60.0))
            if _cover >= 1.0 {
                if _cautionIdx == 0 {
                    _cautionIdx = 1
                    _cautionStep = 1
                } else {
                    phase = .whiteOut
                    _white = 0
                }
            }
        default:
            break
        }
    }

    // MARK: - Particles

    private struct Shard {
        var kind: Int
        var scale: Float
        var life: Float
        var age: Float
        var vx: Float
        var vy: Float
        var alpha: Float
        var angle: Float
        var spin: Float
        var x: Float
        var y: Float
    }

    private struct Dot {
        var kind: Int
        var alpha: Float
        var life: Float
        var age: Float
        var x: Float
        var y: Float
    }

    private func spawnParams() -> (cy: Float, w: Float, h: Float, dw: Float, dy: Float) {
        switch ctx.language {
        case .en:
            return (260.25, 675.0, 50.0, 675.0, 319.375)
        case .zc, .zt:
            return (334.5, 135.0, 75.0, 150.0, 395.375)
        default:
            return (340.5, 135.0, 75.0, 150.0, 399.38)
        }
    }

    private var clipY: Float {
        ctx.language == .en ? 519.0 : 680.0
    }

    private func updateParticles() {
        if phase != .idle && phase != .fadeIn {
            return
        }

        let r = ctx.random
        let spawn = spawnParams()
        _shardAcc += 1.0
        while _shardAcc >= 2.0 {
            _shardAcc -= 2.0
            if _shards.count >= 120 {
                continue
            }
            let vy = (r.next() * 0.45) + 0.13333
            let dir = cos(((r.next() * 20.0) + 80.0) * Float.pi / 180.0)
            _shards.append(Shard(
                kind: r.int(0, 2),
                scale: r.range(0.3, 0.75),
                life: floor((r.next() * 150.0) + 120.0),
                age: 0,
                vx: vy * dir,
                vy: vy,
                alpha: (r.next() * 0.5) + 0.5,
                angle: r.next() * 640.0 * Float.pi / 180.0,
                spin: ((r.next() * 2.5) + 0.5) * Float.pi / 180.0,
                x: 480.0 - (spawn.w * 0.5) + (spawn.w * r.next()),
                y: spawn.cy - (spawn.h * 0.5) + (spawn.h * r.next())
            ))
        }

        var k = 0
        while k < 4 && _dots.count < 200 {
            _dots.append(Dot(
                kind: r.int(0, 2),
                alpha: r.range(0.25, 1.0),
                life: floor((r.next() * 42.0) + 18.0),
                age: 0,
                x: (spawn.dw * -0.5) + 480.0 + (spawn.dw * r.next()),
                y: spawn.dy + (r.next() * -215.25)
            ))
            k += 1
        }

        for i in 0..<_shards.count {
            _shards[i].x += _shards[i].vx
            _shards[i].y -= _shards[i].vy
            _shards[i].angle += _shards[i].spin
            _shards[i].age += 1.0
        }
        _shards.removeAll { $0.age > $0.life }

        for i in 0..<_dots.count {
            _dots[i].age += 1.0
        }
        _dots.removeAll { $0.age > $0.life }
    }

    private func drawParticles(_ p: UiPainter, _ a: Float) {
        if a <= 0 {
            return
        }

        let shardW: [Float] = [33.0, 32.0, 29.0]
        let shardH: [Float] = [44.0, 55.0, 45.0]
        let dotAt: [[Int]] = [[15, 20], [14, 26], [13, 21]]

        p.withClip(RectF(0, 0, UiMetrics.width, clipY)) {
            for d in _dots {
                var t = 2.0 * d.age / d.life
                t = t > 1.0 ? 2.0 - t : t
                let at = dotAt[d.kind]
                p.sprite(
                    UiSheets.titleShard(d.kind),
                    RectF(Float(at[0]), Float(at[1]), 1, 1),
                    RectF((d.x * 2.0) - 0.5, (d.y * 2.0) - 0.5, 1, 1),
                    a * d.alpha * t
                )
            }

            for s in _shards {
                let (k, dim) = UiBackdrop.phase(s.age, s.life)
                let w = shardW[s.kind] * s.scale * k * cos(s.angle)
                let h = shardH[s.kind] * s.scale * k
                p.sprite(
                    UiSheets.titleShard(s.kind),
                    RectF(0, 0, shardW[s.kind], shardH[s.kind]),
                    RectF((s.x * 2.0) - (abs(w) / 2.0), (s.y * 2.0) - (h / 2.0), abs(w), h),
                    a * s.alpha * dim,
                    .alpha,
                    flipX: w < 0
                )
            }
        }
    }

    // MARK: - Drawing

    public override func draw(_ p: UiPainter) {
        if phase == .leaving && _started && !ctx.services.title.prologueSeen {
            p.cover(1.0)
            return
        }

        if phase == .intro {
            drawIntro(p)
            return
        }

        if phase == .caution {
            drawTitle(p)
            drawCaution(p)
            return
        }

        drawTitle(p)
        if phase == .whiteOut {
            p.cover(min(1.0, _white), gray: 1.0)
        } else if _black > 0 {
            p.cover(min(1.0, _black))
        }
    }
    public override func Draw(_ p: UiPainter) {
        draw(p)
    }

    private func drawIntro(_ p: UiPainter) {
        p.cover(1.0, gray: _introStep >= 2 ? 0.0 : 1.0)
        if _introStep == 1 && ctx.services.introMoviePlaying {
            p.quad(TextureRef.movieFrame(ctx.services.introMovieSlot), 0, 0, Self.screenW, UiMetrics.height, 0, 0, 1, 1, UiPainter.pack(1.0))
            p.cover(min(1.0, _white), gray: 1.0)
        } else if _introStep == 0 {
            p.cover(min(1.0, _white), gray: 1.0)
        } else if _introStep >= 2 {
            drawCautionPicture(p, "caution2", _cautionA)
        }
    }

    private func drawCaution(_ p: UiPainter) {
        p.cover(_cover)
        if _cautionStep == 1 || _cautionStep == 2 || _cautionStep == 3 {
            p.cover(1.0)
            drawCautionPicture(p, _cautionIdx == 0 ? "caution" : "caution1", 1.0)
            p.cover(_cover)
        }
    }

    private func drawCautionPicture(_ p: UiPainter, _ kind: String, _ alpha: Float) {
        let suffix = ["ja", "en", "zc", "zt"]
        let langVal = ctx.language.rawValue
        let lang = suffix[langVal < 4 ? Int(langVal) : 1]
        let name: String
        if kind == "caution" {
            name = "caution_\(lang).mzp"
        } else if ctx.language == .ja {
            name = "\(kind).mzp"
        } else {
            name = "\(kind)_\(lang).mzp"
        }

        if let found = ctx.assets.tables.findPicture(name) {
            p.picture(UiPicture(found.archive, found.entry), UiMetrics.screen, alpha)
        }
    }

    private func drawTitle(_ p: UiPainter) {
        let s = ctx.services
        let en = ctx.language == .en
        let t = s.titleMovieTime
        let movie = _movieStarted && t >= 0 && (t >= Self.loopPoint || !_passed)
        if movie {
            p.quad(TextureRef.movieFrame(s.titleMovieSlot), 0, 0, Self.screenW, UiMetrics.height, 0, 0, 1, 1, UiPainter.pack(1.0))
        } else if pressMode {
            p.sprite(UiSheets.titleBg0, RectF(0, 0, 2670, 1266), RectF(-375.0, -110.0, 2670, 1266))
        } else {
            p.sprite(still, UiMetrics.screen)
        }

        let la = _logo
        let hi = _logoRising ? la * la * la : la
        if phase == .idle || phase == .fadeIn || phase == .caution || phase == .loading || phase == .leaving || phase == .whiteOut {
            drawParticles(p, hi)
            let (lx, ly): (Float, Float) = en ? (35.0, 222.0) : (680.0, 72.0)
            let bands: [(y0: Int, y1: Int, w: Int)] = en ?
                [(0, 1, 1), (1, 330, 1850), (330, 440, 1850)] :
                [(0, 285, 560), (285, 570, 560), (570, 648, 560)]
            for k in 0..<3 {
                let (y0, y1, w) = bands[k]
                let alpha = _logoRising ? pow(la, Float(k + 1)) : la
                p.sprite(UiSheets.titleLogo, RectF(0, Float(y0), Float(w), Float(y1 - y0)), RectF(lx, ly + Float(y0), Float(w), Float(y1 - y0)), alpha)
            }

            if pressMode {
                let blink = 0.1 + (0.9 * UiEase.triangle(_pulse, 60.0))
                if p.promptStyle == .keyboard {
                    UiPrompts.drawPressAnyKey(p, _menuAlpha * blink)
                } else {
                    p.sprite(UiSheets.pressAnyButton, RectF(0, 0, 472, 88), RectF(724.0, 814.01, 472, 88), _menuAlpha * blink)
                }
            } else {
                let glow = UiEase.triangle(_clock * 0.5)
                p.sprite(UiSheets.titleGlow, RectF(0, 0, 488, 256), RectF(720.0, en ? 391.0 : 552.0, 488, 256), hi * glow, .add)
                drawMenu(p, hi)
            }
        }

        p.sprite(UiSheets.titleCopyright, RectF(0, 0, 184, 64), RectF(872.0, 1008.0, 184, 64))
        ctx.backdrop.draw(p)
    }

    private func drawMenu(_ p: UiPainter, _ lf: Float) {
        let n = _entries.count
        let y5: [Float] = [383.5, 411.5, 439.5, 467.0, 495.5]
        let y4: [Float] = [400.0, 428.0, 455.5, 484.0]
        for i in 0..<n {
            let slot = Self.itemRect(i, n)
            let hover = i == _items.cursor
            let alpha = min(max((2.0 * _menuAlpha) - (Float(i + 1) / Float(n)), 0.0), 1.0) * lf
            if _entries[i] == .exit {
                if !p.composed(hover ? UiComposedId.titleExitCursor : UiComposedId.titleExit, RectF(0, 0, Float(TitleExitArt.cellWidth), Float(TitleExitArt.cellHeight)), slot, alpha) {
                    drawExitLabel(p, slot, hover, alpha)
                }
            } else {
                let src = Self.cell(_entries[i], hover ? 1 : 0)
                p.sprite(UiSheets.titleMenu, src, slot, alpha)
            }

            if hover && _menuAlpha >= 1.0 {
                let w = 336.0 * _grow
                let y: Float = n >= 6 ? slot.y + 47.0 : (n >= 5 ? y5[i] : y4[min(i, 3)]) * 2.0
                p.sprite(UiSheets.titleUnderline, RectF(24, 24, 336, 8), RectF(966.0 - (w / 2.0), y, w, 8), _grow * _menuAlpha * lf)
            }
        }
    }

    private static let exitWhite = (r: 255, g: 255, b: 255)
    private static let exitWhiteGlow = (r: 192, g: 238, b: 254)
    private static let exitCyan = (r: 17, g: 222, b: 248)
    private static let exitCyanGlow = (r: 2, g: 221, b: 255)

    private func drawExitLabel(_ p: UiPainter, _ slot: RectF, _ hover: Bool, _ alpha: Float) {
        if alpha <= 0 {
            return
        }
        let style = Self.exitStyle(ctx.language)
        ctx.text.drawGlowLabel(
            p, "EXIT", style, slot.x + (slot.w / 2.0), slot.y + Self.exitTop(ctx.language),
            hover ? Self.exitCyan : Self.exitWhite,
            hover ? Self.exitCyanGlow : Self.exitWhiteGlow,
            alpha,
            hover ? 0.014 : 0.03
        )
    }

    private static func exitStyle(_ language: Language) -> TextStyle {
        var style = TextStyle.menu(exitScale(language))
        style.width = 600
        style.height = 100
        style.spacing = 2
        style.leading = 0
        return style
    }

    private static func exitScale(_ language: Language) -> Double {
        language == .zc || language == .zt ? 0.395 : 0.416
    }

    private static func exitTop(_ language: Language) -> Float {
        language == .zc || language == .zt ? 23.0 : 24.0
    }
}
