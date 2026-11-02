import Foundation
import TsukiCore
import TsukiEngine
import TsukiMedia
import TsukiUi
public struct StepReport: Sendable {
    public let frame: Int64
    public let storyStepped: Bool
    public let uiMode: UiMode
    public let rewound: Bool

    public init(frame: Int64, storyStepped: Bool, uiMode: UiMode, rewound: Bool) {
        self.frame = frame
        self.storyStepped = storyStepped
        self.uiMode = uiMode
        self.rewound = rewound
    }
}

public struct StepTimes: Sendable {
    public let movies: Double
    public let ui: Double
    public let story: Double
    public let media: Double
    public let rest: Double
    public let draw: Double

    public init(movies: Double, ui: Double, story: Double, media: Double, rest: Double, draw: Double = 0) {
        self.movies = movies
        self.ui = ui
        self.story = story
        self.media = media
        self.rest = rest
        self.draw = draw
    }
}

public final class AppRuntime {
    private static let rewindPeriod = 8
    private static let autoSkipCountdownFrames = 4
    private static let topEdgeUnits: Int16 = 12
    private static let bottomEdgeUnits: Int16 = 436
    private static let gestureUnits: Int16 = 45
    private static let storyThumbnailGap: Int64 = 180
    private static let brightThumbnailAge: Int64 = 6000
    private static let brightLuma: Double = 14.0

    private let audio: AudioCommandPlayer?
    private let movies: MovieHost?
    private let frozen: DisplayList = DisplayList(capacity: 2048)
    private var heldThumbnail: (width: Int, height: Int, rgba: [UInt8])?
    private var storyThumbnail: (width: Int, height: Int, rgba: [UInt8])?
    private var brightThumbnail: (width: Int, height: Int, rgba: [UInt8])?
    private var brightThumbnailFrame: Int64 = 0
    private var storyThumbnailFrame: Int64 = -storyThumbnailGap
    private weak var thumbnailHost: GameHost?
    private var thumbnailRestores: Int = 0
    private var rewindHold: Int = 0
    private var topArmed: Bool = true
    private var hiddenByPointer: Bool = false
    private var gestureStart: (x: Int16, y: Int16)?
    private var gesture: Int = 0
    private var openSaveScreen: Bool = false
    private weak var promptSave: SaveLoadScreen?
    private var ending: Bool = false
    private var autoSkipOffered: Bool = false
    private var autoSkipCountdown: Int = 0
    private var closeDialog: ConfirmDialog?
    private var frozenSceneCount: Int = 0
    private var lastPointerX: Int16 = -1
    private var lastPointerY: Int16 = -1

    public let services: AppServices
    public let ui: UiRoot

    public var host: GameHost { services.host }
    public private(set) var frame: Int64 = 0
    public var grab: (() -> (width: Int, height: Int, rgba: [UInt8])?)?
    public var logged: ((String) -> Void)?
    public var exitRequested: Bool { services.quitRequested }
    public private(set) var closeConfirmed: Bool = false
    public private(set) var last: StepReport = StepReport(frame: 0, storyStepped: false, uiMode: .story, rewound: false)
    public private(set) var lastTimes: StepTimes = StepTimes(movies: 0, ui: 0, story: 0, media: 0, rest: 0, draw: 0)

    public init(services: AppServices, ui: UiRoot, audio: AudioCommandPlayer?, movies: MovieHost?) {
        self.services = services
        self.ui = ui
        self.audio = audio
        self.movies = movies

        services.ui = ui
        services.frameCapture = { [weak self] in
            self?.heldThumbnail ?? self?.grab?()
        }
        services.saveScreenRequested = { [weak self] in
            self?.openSaveScreen = true
        }
        services.storyEnded = { [weak self] reason in
            self?.onStoryEnded(reason)
        }
        hookHost(services.host)
        services.hostReplaced = { [weak self] newHost in
            self?.hookHost(newHost)
        }
    }

    private func hookHost(_ host: GameHost) {
        host.autoSkipOffered = { [weak self] _ in
            self?.autoSkipOffered = true
        }
    }

    private func offerAutoSkip(_ story: Bool) {
        if !story || services.replayActive {
            autoSkipOffered = false
            autoSkipCountdown = 0
            return
        }

        if autoSkipOffered && !ui.active {
            autoSkipOffered = false
            if services.config.skipConfirm != 0 {
                beginOverlay()
                _ = ui.push(ConfirmDialog(.nextScene, { [weak self] yes in
                    if yes {
                        self?.services.nextScene()
                    }
                }))
            } else {
                autoSkipCountdown = Self.autoSkipCountdownFrames
            }
        }

        if autoSkipCountdown > 0 {
            autoSkipCountdown -= 1
            if autoSkipCountdown == 0 {
                services.nextScene()
            }
        }
    }

    public var closeDialogOpen: Bool {
        if let d = closeDialog, d.waiting, ui.stack.contains(where: { $0 === d }) {
            return true
        }
        return false
    }

    @discardableResult
    public func requestClose() -> Bool {
        if closeDialogOpen {
            closeConfirmed = true
            services.requestQuit()
            return true
        }
        if let top = ui.top as? ConfirmDialog, top.waiting, top.messageId(ui.context.assets) == TitleScreen.quitMessage {
            closeConfirmed = true
            services.requestQuit()
            return true
        }

        beginOverlay()
        closeDialog = ui.push(ConfirmDialog(messageId: TitleScreen.quitMessage, noFirst: true, answer: { [weak self] yes in
            if yes {
                self?.closeConfirmed = true
                self?.services.requestQuit()
            }
        }))
        return false
    }

    public func start() {
        _ = ui.push(BootScreen())
    }

    private func onStoryEnded(_ reason: EndReason) {
        ending = true
        logged?("story ended: \(reason)")
    }

    public func step(raw: InputFrame, nominalTimestamp: Int64, list: DisplayList) -> StepReport {
        let t0 = Date()
        frame += 1
        services.tick()

        let clocks = movies?.step(timestamp: nominalTimestamp) ?? []
        let t1 = Date()
        host.setMovieClocks(clocks)
        services.updateMovieClocks(clocks)

        var input = raw
        let uiWasActive = ui.active
        var story = services.storyActive && host.phase == .running

        if !story || host !== thumbnailHost || host.restoreCount != thumbnailRestores {
            storyThumbnail = nil
            brightThumbnail = nil
            storyThumbnailFrame = -Self.storyThumbnailGap
            thumbnailHost = host
            thumbnailRestores = host.restoreCount
        }

        updateGesture(raw: raw, allowed: story && !ui.active && !host.choiceOpen && !host.movieActive)
        if story && !ui.active {
            input = routeStoryInput(raw: raw)
        } else if !ui.active {
            heldThumbnail = nil
        }

        if openSaveScreen && !ui.active {
            openSaveScreen = false
            beginOverlay()
            let bright: (width: Int, height: Int, rgba: [UInt8])? = (frame - brightThumbnailFrame <= Self.brightThumbnailAge) ? brightThumbnail : nil
            heldThumbnail = bright ?? storyThumbnail ?? heldThumbnail
            promptSave = ui.push(SaveLoadScreen(save: true))
        }

        if story && !ui.active && host.promptOpen && ui.storyPromptConfirmClicked(raw.pointer) {
            input.pressed.insert(.decide)
            input.pointer.pressed.remove(.left)
        }

        if !ui.active && services.takePendingTitle() {
            services.stopStoryOutputs()
            _ = ui.push(TitleScreen())
            story = false
        }

        var uiInput = input
        if !uiWasActive {
            uiInput.pressed = []
            uiInput.repeated = []
            uiInput.menuPressed = []
            uiInput.menuRepeated = []
            uiInput.shellPressed = []
            uiInput.pointer.pressed = []
            uiInput.pointer.wheel = 0
        }
        ui.step(uiInput)

        if let promptSave = promptSave, !ui.stack.contains(where: { $0 === promptSave }) {
            self.promptSave = nil
            host.savePromptScreenClosed()
        }

        let t2 = Date()

        if services.storyActive && ui.mode == .title && host.phase == .running {
            ui.clear()
            services.stopTitleMovie()
        }

        let panelDrive = (ui.top is ModePanelScreen) && (services.fastForwardHeld || services.rewindHeld)
        var rewound = false
        var stepped = false
        list.reset(frame: frame)
        story = services.storyActive && host.phase == .running

        if story && (!ui.active || panelDrive) {
            var gi = ui.active ? InputFrame(frame: frame) : input
            if services.fastForwardHeld || gesture > 0 {
                gi.shellHeld.insert(.fastForward)
            }

            rewound = rewind(raw: raw)
            hoverChoice(raw: raw)
            let auto = host.autoMode
            let skip = host.skipLatch
            _ = host.step(gi, list: list)
            stepped = true

            if host.autoMode && !auto {
                ui.showBanner(.auto)
            }
            if host.skipLatch && !skip {
                ui.showBanner(.skip)
            }

            copyFrozen(list: list)
            noteStoryFrame()
        } else if story && ui.active {
            let keep = ui.blurScene ? min(frozenSceneCount, frozen.commands.count) : frozen.commands.count
            for i in 0..<keep {
                list.add(frozen.commands[i])
            }
        }

        if stepped || story {
            services.noteStoryStep()
        }

        offerAutoSkip(story)
        let t3 = Date()

        services.performHostAudio()
        let movieCommands = host.takeMovieCommands()
        if !movieCommands.isEmpty {
            movies?.perform(movieCommands)
        }

        audio?.pump()
        let t4 = Date()

        services.checkStoryEnd()
        if services.storyActive && host.phase == .notStarted {
            logged?("story host not started: back to the title")
            services.returnToTitle()
        }

        if ending {
            ending = false
            endStory()
        }

        let t4b = Date()
        ui.draw(list)
        list.seal()
        let t5 = Date()

        lastTimes = StepTimes(
            movies: t1.timeIntervalSince(t0) * 1000.0,
            ui: t2.timeIntervalSince(t1) * 1000.0,
            story: t3.timeIntervalSince(t2) * 1000.0,
            media: t4.timeIntervalSince(t3) * 1000.0,
            rest: t4b.timeIntervalSince(t4) * 1000.0,
            draw: t5.timeIntervalSince(t4b) * 1000.0
        )
        last = StepReport(frame: frame, storyStepped: stepped, uiMode: ui.mode, rewound: rewound)
        return last
    }

    private func hoverChoice(raw: InputFrame) {
        guard host.choiceSelectable && raw.pointer.active else { return }
        if raw.pointer.x == lastPointerX && raw.pointer.y == lastPointerY && raw.pointer.pressed.isEmpty {
            return
        }

        lastPointerX = raw.pointer.x
        lastPointerY = raw.pointer.y
        let line = host.choiceLineAt(canvasY(raw.pointer))
        if line >= 0 {
            host.hoverChoice(line)
        }
    }

    private func canvasY(_ p: PointerState) -> Double {
        Double(p.canvasY.isNaN ? (Float(p.y) + 0.5) * UiMetrics.unitY : p.canvasY)
    }

    private func updateGesture(raw: InputFrame, allowed: Bool) {
        let p = raw.pointer
        if !allowed || !p.active || !p.held.contains(.left) {
            gestureStart = nil
            gesture = 0
            return
        }

        if gestureStart == nil && p.pressed.contains(.left) && p.x >= 121 && p.x <= 519 && p.y >= 125 && p.y <= 383 {
            gestureStart = (p.x, p.y)
        }

        if let s = gestureStart {
            let dx = p.x - s.x
            gesture = dx >= Self.gestureUnits ? 1 : dx <= -Self.gestureUnits ? -1 : 0
        }
    }

    private func copyFrozen(list: DisplayList) {
        frozen.reset(frame: frame)
        frozenSceneCount = 0
        var index = 0
        for c in list.commands {
            if c.kind != .capture {
                frozen.add(c)
                if index < host.sceneCommandCount {
                    frozenSceneCount += 1
                }
            }
            index += 1
        }
    }

    private func endStory() {
        services.stopStoryOutputs()
        if host.replayRequested && ui.returnToGallery() {
            return
        }
        if !ui.active {
            _ = ui.push(TitleScreen())
        }
    }

    private func noteStoryFrame() {
        guard grab != nil, frame - storyThumbnailFrame >= Self.storyThumbnailGap,
              !host.choiceOpen, !host.movieActive, !host.skipLatch, !services.fastForwardHeld,
              !host.pageMessages.isEmpty, host.wait.windowAlpha >= 0.99, host.textFade >= 1.0, host.f(1103) == 0 else {
            return
        }

        storyThumbnailFrame = frame
        storyThumbnail = grab?()
        if let g = storyThumbnail, meanLuma(g.rgba) >= Self.brightLuma {
            brightThumbnail = g
            brightThumbnailFrame = frame
        }
    }

    private func meanLuma(_ rgba: [UInt8]) -> Double {
        var sum: Int64 = 0
        var i = 0
        while i + 2 < rgba.count {
            sum += Int64(rgba[i]) + Int64(rgba[i + 1]) + Int64(rgba[i + 2])
            i += 4
        }
        return rgba.count < 4 ? 0 : Double(sum) / 3.0 / Double(rgba.count / 4)
    }

    private func beginOverlay() {
        heldThumbnail = grab?()
    }

    private func rewind(raw: InputFrame) -> Bool {
        let held = raw.held.contains(.l2) || raw.shellHeld.contains(.rewind) || services.rewindHeld || gesture < 0
        if !held {
            rewindHold = 0
            return false
        }

        rewindHold += 1
        if rewindHold != 1 && rewindHold % Self.rewindPeriod != 0 {
            return false
        }

        let ok = host.rewindStep()
        if ok {
            host.setSkipLatch(false)
            logged?("rewind: script \(host.script) offset \(host.machine.cursor)")
        }
        return ok
    }

    private func routeStoryInput(raw: InputFrame) -> InputFrame {
        var input = raw
        let sp = raw.shellPressed
        let pp = raw.pressed
        let right = raw.pointer.pressed.contains(.right)
        let movie = host.movieActive
        let choice = host.choiceOpen
        let ptr = raw.pointer

        let inTop = ptr.active && ptr.y < Self.topEdgeUnits
        let inBottom = ptr.active && ptr.y > Self.bottomEdgeUnits
        if !ptr.active || ptr.y >= Self.topEdgeUnits + 10 {
            topArmed = true
        }

        var mouseShell: ShellActions = []
        if !choice && !movie {
            if inBottom && !hiddenByPointer && !host.windowHidden {
                mouseShell.insert(.hideWindow)
                hiddenByPointer = true
            } else if !inBottom && hiddenByPointer {
                hiddenByPointer = false
                if host.windowHidden {
                    mouseShell.insert(.hideWindow)
                }
            }
        } else if !inBottom {
            hiddenByPointer = false
        }

        if ptr.pressed.contains(.left) && ((inBottom && host.windowHidden && !choice) || (host.choiceSelectable && host.choiceKind == .list && host.choiceLineAt(canvasY(ptr)) < 0)) {
            input.pointer.pressed.remove(.left)
        }

        let menuKey = sp.contains(.systemMenu) || pp.contains(.square) || right
        if menuKey && !movie {
            if !ui.active {
                beginOverlay()
                _ = ui.openSystemMenu()
            }
            return strip(input)
        }

        if !choice && !movie && (pp.contains(.triangle) || sp.contains(.backlog)) && !services.backlog.isEmpty {
            beginOverlay()
            if ui.openBacklog() {
                return strip(input)
            }
        }

        if !choice && !movie && (pp.contains(.up) || (inTop && topArmed)) && services.panelAllowed {
            beginOverlay()
            if ui.openModePanel() {
                topArmed = false
                return strip(input)
            }
        }

        if sp.contains(.quickSave) && !movie {
            if services.quickSave() {
                ui.showBanner(.quickSave)
            }
        }

        if sp.contains(.quickLoad) && !movie && services.hasQuickSave {
            beginOverlay()
            _ = ui.push(ConfirmDialog(kind: .quickLoad, answer: { [weak self] yes in
                if yes && (self?.services.quickLoad() ?? false) {
                    self?.ui.clear()
                }
            }, thumbnailSlot: 139))
            return strip(input)
        }

        if sp.contains(.nextScene) && services.panelAllowed && services.sceneJumpEnabled {
            beginOverlay()
            _ = ui.push(ConfirmDialog(kind: .nextScene, answer: { [weak self] yes in
                if yes {
                    self?.services.nextScene()
                }
            }))
            return strip(input)
        }

        if sp.contains(.previousScene) && services.panelAllowed && services.sceneJumpEnabled && host.canGoToPreviousScene {
            beginOverlay()
            _ = ui.push(ConfirmDialog(kind: .prevScene, answer: { [weak self] yes in
                if yes {
                    self?.services.previousScene()
                }
            }))
            return strip(input)
        }

        if sp.contains(.replayVoice) {
            services.replayVoice()
        }

        let mask: PadButtons = [.square, .triangle, .l2]
        input.held.subtract(mask)
        input.pressed.subtract(mask)
        input.repeated.subtract(mask)
        input.shellPressed.formUnion(mouseShell)
        return input
    }

    private func strip(_ input: InputFrame) -> InputFrame {
        let mask: PadButtons = [.cancel, .square, .triangle, .l2, .decide, .up]
        var res = input
        res.held.subtract(mask)
        res.pressed.subtract(mask)
        res.repeated.subtract(mask)
        res.pointer.held.subtract([.right, .left])
        res.pointer.pressed.subtract([.right, .left])
        res.pointer.wheel = 0
        res.shellPressed = []
        return res
    }
}
