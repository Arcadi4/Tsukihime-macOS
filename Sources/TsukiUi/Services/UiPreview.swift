import Foundation
import TsukiCore
import TsukiEngine

/// Builds a menu screen in a known state for the screenshot tool and the tests: a `UiRoot` over a game data source and a
/// `PreviewServices`, with the named screen open and stepped until its fades have settled.
public enum UiPreview {
    private static let names: [String] = [
        "boot",
        "title",
        "title-nosave",
        "title-press",
        "title-cursor",
        "title-exit",
        "caution",
        "caution1",
        "caution2",
        "menu",
        "save",
        "load",
        "config-system",
        "config-sound",
        "config-controls",
        "config-controls-cursor",
        "config-controls-bottom",
        "config-display",
        "config-display-full",
        "config-port",
        "config-port-half",
        "config-sound-port",
        "toast",
        "confirm",
        "confirm-quickload",
        "popup",
        "backlog",
        "mode",
        "banner",
        "fills",
        "guides",
        "guide-cells",
        "gallery-cg",
        "gallery-cg-group",
        "gallery-cg-view",
        "gallery-cg-strip",
        "gallery-music",
        "gallery-music-play",
        "gallery-movies",
        "gallery-endings",
        "gallery-confirm",
        "gallery-locked",
        "flowchart-gallery",
        "flowchart-game",
        "config-system-drag",
        "save-drag",
        "gallery-music-drag",
        "flowchart-gallery-drag",
        "story-prompt-save",
        "story-prompt-cursor",
        "story-prompt-system",
        "story-prompt-fade",
    ]

    /// The names `open` understands.
    public static var screens: [String] { names }
    public static var Screens: [String] { screens }

    /// Opens screen `name` and steps it `frames` frames (a default per screen when negative).
    public static func open(_ name: String, data: GameData, services: PreviewServices, frames: Int = -1, parts: UiPictureSource? = nil) -> UiRoot {
        var screenName = name
        let root = UiRoot(data: data, services: services, parts: parts)
        var settle = 90

        let drag = screenName.hasSuffix("-drag")
        if drag {
            screenName = String(screenName.dropLast(5))
        }

        switch screenName {
        case "boot":
            root.push(BootScreen())
            settle = 60
        case "title":
            root.context.titleIntroShown = true
            root.push(TitleScreen())
            settle = 200
        case "title-nosave":
            root.context.titleIntroShown = true
            var t = services.title
            t.continueSlot = -1
            services.title = t
            root.push(TitleScreen())
            settle = 200
        case "title-cursor":
            root.context.titleIntroShown = true
            root.push(TitleScreen())
            run(root, 200)
            run(root, 1, down: true)
            settle = 30
        case "title-exit":
            root.context.titleIntroShown = true
            root.push(TitleScreen())
            run(root, 200)
            var f = InputFrame(frame: root.context.frame + 1)
            f.pressed = .up
            f.repeated = .up
            f.held = .up
            root.step(f)
            settle = 30
        case "title-press":
            var t = services.title
            t.storyStarted = false
            t.continueSlot = -1
            services.title = t
            root.push(TitleScreen())
            settle = 160
        case "caution", "caution1":
            var t = services.title
            t.storyStarted = false
            t.continueSlot = -1
            services.title = t
            root.push(TitleScreen())
            run(root, 140)
            var f1 = InputFrame(frame: root.context.frame + 1)
            f1.pressed = .decide
            root.step(f1)
            settle = 200
            if screenName == "caution1" {
                run(root, 260)
                var f2 = InputFrame(frame: root.context.frame + 1)
                f2.pressed = .decide
                root.step(f2)
                settle = 200
            }
        case "caution2":
            root.push(TitleScreen())
            run(root, 66)
            services.introMoviePlaying = false
            settle = 100
        case "menu":
            root.push(SystemMenuScreen())
        case "save", "load":
            root.push(SystemMenuScreen())
            run(root, 40)
            root.push(SaveLoadScreen(save: screenName == "save"))
            settle = 80
        case "config-system", "config-sound", "config-controls", "config-controls-cursor", "config-controls-bottom",
             "config-display", "config-display-full", "config-port", "config-port-half", "config-sound-port":
            root.push(SystemMenuScreen())
            run(root, 40)
            for word in data.eboot.ui.voiceRowWords {
                services.setGlobal(word, 7)
            }

            let config = root.push(ConfigScreen())
            if screenName == "config-sound" || screenName == "config-sound-port" || screenName == "config-controls" || screenName == "config-controls-cursor" || screenName == "config-controls-bottom" {
                config.change(Ctl(kind: .tab, index: (screenName == "config-sound" || screenName == "config-sound-port") ? 1 : 2), 0)
            }

            settle = 120
            if screenName == "config-controls-cursor" {
                run(root, 60)
                press(root, .down)
                press(root, .right)
                settle = 30
            } else if screenName == "config-controls-bottom" {
                run(root, 60)
                config.scrollNow(config.scrollMaximum)
                settle = 20
            } else if screenName == "config-display" || screenName == "config-display-full" {
                run(root, 60)
                if let display = services.display, screenName == "config-display-full" {
                    display.fullscreen = true
                }
                config.scrollNow(config.scrollMaximum)
                config.cursorTo(Ctl(kind: .display, index: screenName == "config-display-full" ? 1 : 0))
                settle = 20
            } else if screenName == "config-port" || screenName == "config-port-half" {
                run(root, 60)
                if let port = services.port {
                    port.copyTextToClipboard = true
                    port.textWebSocket = true
                }
                if screenName == "config-port-half" {
                    config.windowOpacityPercent = 50
                }
                config.scrollNow(config.scrollMaximum)
                config.cursorTo(Ctl(kind: .opacity))
                settle = 20
            } else if screenName == "config-sound-port" {
                run(root, 60)
                if let port = services.port {
                    port.muteInBackground = true
                }
                config.cursorTo(Ctl(kind: .backgroundMute, index: 1))
                settle = 20
            }
        case "toast":
            root.push(ModePanelScreen())
            run(root, 30)
            root.showToast(PortText.get(.screenshotSaved, services.language))
            settle = UiToast.fadeInFrames + 4
        case "mode":
            root.push(ModePanelScreen())
            settle = 30
        case "banner":
            root.push(ModePanelScreen())
            run(root, 30)
            root.showBanner(.quickSave)
            settle = 22
        case "fills":
            root.push(FillTestScreen())
        case "guides":
            root.push(GuidesScreen())
        case "guide-cells":
            root.push(GuideCellsScreen())
        case let g where g.hasPrefix("gallery-") || g.hasPrefix("flowchart-"):
            settle = openGallery(screenName, root: root, data: data, services: services)
        case "backlog":
            services.setBacklog(samplePages(data, language: services.language))
            root.push(BacklogScreen())
            settle = 40
        case "confirm":
            root.push(SystemMenuScreen())
            run(root, 40)
            root.push(SaveLoadScreen(save: true))
            run(root, 40)
            root.push(ConfirmDialog(.overwrite, { _ in }))
            settle = 40
        case "confirm-quickload":
            root.push(ModePanelScreen())
            run(root, 30)
            root.push(ConfirmDialog(.quickLoad, { _ in }, thumbnailSlot: 139))
            settle = 40
        case "story-prompt-save", "story-prompt-cursor", "story-prompt-system", "story-prompt-fade":
            switch screenName {
            case "story-prompt-cursor":
                services.storyPrompt = UiStoryPrompt(messageId: 216, cursor: 1, alpha: 1.0, scale: 1.0)
            case "story-prompt-system":
                services.storyPrompt = UiStoryPrompt(messageId: 1449, cursor: 0, alpha: 1.0, scale: 1.0)
            case "story-prompt-fade":
                services.storyPrompt = UiStoryPrompt(messageId: 216, cursor: -1, alpha: 0.5, scale: 1.025)
            default:
                services.storyPrompt = UiStoryPrompt(messageId: 216, cursor: -1, alpha: 1.0, scale: 1.0)
            }
            settle = 2
        case "popup":
            root.push(SystemMenuScreen())
            run(root, 40)
            root.push(MessagePopup(root.context.sysmes(193), frames: 600.0))
            settle = 40
        default:
            fatalError("unknown screen '\(screenName)'; the screens are \(names.joined(separator: ", "))")
        }

        run(root, frames < 0 ? settle : frames)
        if drag {
            let y = UiScrollBar.thumbTop(0.0, travel: 608.0) + 140.0
            root.step(UiInput.pointerFrame(x: 1855.0, y: y, held: .left, pressed: .left, wheel: 0, frame: root.context.frame + 1))
            for i in 1...12 {
                root.step(UiInput.pointerFrame(x: 1855.0, y: y + (Float(i) * 12.0), held: .left, pressed: [], wheel: 0, frame: root.context.frame + 1))
            }
        }

        return root
    }
    public static func Open(_ name: String, _ data: GameData, _ services: PreviewServices, _ frames: Int = -1, _ parts: UiPictureSource? = nil) -> UiRoot {
        open(name, data: data, services: services, frames: frames, parts: parts)
    }

    /// Backlog pages made of real script lines.
    public static func samplePages(_ data: GameData, language: Language) -> [BacklogPage] {
        var id = 3
        var pages: [BacklogPage] = []
        for p in 0..<8 {
            var msgs: [BacklogMessage] = []
            let count = 2 + (p % 3)
            while msgs.count < count && id < data.textLineCount {
                let lineSpan = data.textLine(language, id)
                id += 1
                if lineSpan.count > 4 && lineSpan[0] != UInt8(ascii: "$") {
                    let bytes = Array(lineSpan)
                    msgs.append(BacklogMessage(text: bytes, blankBefore: 0, voiceId: msgs.isEmpty ? 100 + p : -1))
                }
            }
            pages.append(BacklogPage(messages: msgs, jumpable: p != 5))
        }
        return pages
    }
    public static func SamplePages(_ data: GameData, _ language: Language) -> [BacklogPage] {
        samplePages(data, language: language)
    }

    private static func openGallery(_ name: String, root: UiRoot, data: GameData, services: PreviewServices) -> Int {
        let profile: String
        switch name {
        case "gallery-endings", "gallery-cg-strip": profile = "full"
        case "gallery-locked": profile = "none"
        default: profile = "mid"
        }
        services.believe(data, profile: profile)

        if name == "flowchart-game" {
            root.push(SystemMenuScreen())
            run(root, 40)
            root.push(FlowchartScreen(gallery: false))
            return 60
        }

        root.push(GalleryScreen())
        run(root, 40)
        guard let gallery = root.top as? GalleryScreen else {
            return 60
        }

        switch name {
        case "gallery-cg":
            press(root, .right)
            return 80
        case "gallery-cg-group", "gallery-cg-view":
            press(root, .right)
            guard let cg = gallery.panel as? GalleryCgPanel else { return 80 }
            var pick = 0
            for k in 0..<cg.count {
                let g = groupAt(cg, k)
                if cg.unlocked[g].count > (name == "gallery-cg-group" ? 1 : 0) {
                    pick = k
                    break
                }
            }
            moveTo(root, position: pick)
            press(root, .decide)
            run(root, 40)
            if name == "gallery-cg-view" {
                press(root, .decide)
                run(root, 40)
                return 50
            }
            return 80

        case "gallery-cg-strip":
            press(root, .right)
            guard let cg = gallery.panel as? GalleryCgPanel else { return 50 }
            var foundG = 0
            var foundK = 0
            outer: for g in 0..<cg.unlocked.count {
                for k in 0..<cg.unlocked[g].count {
                    if cg.entry(g, k).languageStrip {
                        foundG = g
                        foundK = k
                        break outer
                    }
                }
            }
            var main: [Int] = []
            for i in 0..<cg.unlocked.count {
                if !cg.unlocked[i].isEmpty {
                    main.append(i)
                }
            }
            if let mainIdx = main.firstIndex(of: foundG) {
                moveTo(root, position: mainIdx)
            }
            press(root, .decide)
            if cg.sub != nil {
                run(root, 40)
                moveTo(root, position: foundK)
                press(root, .decide)
            }
            run(root, 60)
            return 50

        case "gallery-music", "gallery-music-play":
            press(root, .down)
            press(root, .decide)
            run(root, 100)
            if name == "gallery-music-play" {
                guard let music = gallery.panel as? GalleryMusicPanel else { return 270 }
                var row = 0
                for i in 1..<music.unlocked.count {
                    if music.unlocked[i] {
                        row = i
                        break
                    }
                }
                for _ in 0..<row {
                    press(root, .down)
                }
                press(root, .decide)
                return 270
            }
            return 80

        case "gallery-movies":
            press(root, .down)
            press(root, .down)
            press(root, .down)
            press(root, .decide)
            return 100

        case "gallery-endings":
            for _ in 0..<4 {
                press(root, .down)
            }
            press(root, .decide)
            run(root, 100)
            press(root, .down)
            press(root, .down)
            return 80

        case "gallery-confirm":
            for _ in 0..<4 {
                press(root, .down)
            }
            press(root, .decide)
            run(root, 100)
            press(root, .decide)
            return 40

        case "gallery-locked":
            press(root, .down)
            press(root, .down)
            press(root, .decide)
            return 40

        default:
            press(root, .down)
            press(root, .down)
            press(root, .decide)
            return 60
        }
    }

    private static func groupAt(_ cg: GalleryCgPanel, _ k: Int) -> Int {
        var seen = -1
        for g in 0..<cg.unlocked.count {
            if !cg.unlocked[g].isEmpty {
                seen += 1
                if seen == k {
                    return g
                }
            }
        }
        return 0
    }

    private static func moveTo(_ root: UiRoot, position: Int) {
        for _ in 0..<(position / GalleryCgPanel.cols) {
            press(root, .down)
        }
        for _ in 0..<(position % GalleryCgPanel.cols) {
            press(root, .right)
        }
    }

    /// One frame with `buttons` newly pressed, then a quiet frame.
    public static func press(_ root: UiRoot, _ buttons: PadButtons) {
        var f1 = InputFrame(frame: root.context.frame + 1)
        f1.pressed = buttons
        f1.repeated = buttons
        f1.held = buttons
        root.step(f1)

        let f2 = InputFrame(frame: root.context.frame + 1)
        root.step(f2)
    }
    public static func Press(_ root: UiRoot, _ buttons: PadButtons) { press(root, buttons) }

    /// Steps the root `frames` frames with no input.
    public static func run(_ root: UiRoot, _ frames: Int, down: Bool = false) {
        for i in 0..<frames {
            let b: PadButtons = (down && i == 0) ? .down : []
            var f = InputFrame(frame: root.context.frame + 1)
            f.pressed = b
            f.repeated = b
            f.held = b
            root.step(f)
        }
    }
    public static func Run(_ root: UiRoot, _ frames: Int, _ down: Bool = false) {
        run(root, frames, down: down)
    }
}

/// A test screen with flat fills of known colour and alpha.
final class FillTestScreen: UiScreen {
    override func step(_ input: UiInput) {}

    override func draw(_ painter: UiPainter) {
        let alphas: [Float] = [1.0, 0.75, 0.5, 0.25]
        let colours: [[Float]] = [[0.0, 0.0, 0.0], [1.0, 1.0, 1.0], [1.0, 0.0, 0.0], [0.0, 0.0, 1.0]]
        for r in 0..<colours.count {
            for c in 0..<alphas.count {
                painter.fill(RectF(Float(100 + (c * 200)), Float(100 + (r * 200)), 150.0, 150.0), r: colours[r][0], g: colours[r][1], b: colours[r][2], a: alphas[c])
            }
        }
    }
}

/// Draws every cell of the guide icon sheet and the guide word sheet with its index.
final class GuideCellsScreen: UiScreen {
    override func step(_ input: UiInput) {}

    override func draw(_ painter: UiPainter) {
        painter.fill(UiMetrics.screen, r: 0.1, g: 0.2, b: 0.35, a: 1.0)
        let assets = painter.assets
        let style = TextStyle.menu(0.4)
        let icons = assets.tables.guideIconCells
        for i in 0..<icons.count {
            let c = icons[i]
            let x = Float(60 + ((i % 8) * 220))
            let y = Float(40 + ((i / 8) * 130))
            painter.sprite(UiSheets.guideIcons, RectF.fromCorners(Float(c.x0), Float(c.y0), Float(c.x1), Float(c.y1)), RectF(x, y, Float(c.width * 2), Float(c.height * 2)))
            ctx.text.draw(painter, String(i), style, x / UiMetrics.unitX, (y + 80.0) / UiMetrics.unitY)
        }

        let words = assets.tables.guideWordCells(assets.language)
        for i in 0..<words.count {
            let c = words[i]
            let x = Float(60 + ((i % 3) * 600))
            let y = Float(440 + ((i / 3) * 70))
            painter.sprite(UiSheets.guideWords, RectF.fromCorners(Float(c.x0), Float(c.y0), Float(c.x1), Float(c.y1)), RectF(x + 60.0, y, Float(c.width) * 1.5, Float(c.height) * 1.5))
            ctx.text.draw(painter, String(i), style, x / UiMetrics.unitX, y / UiMetrics.unitY)
        }
    }
}

/// Draws the twelve button guides one above the other, each with its index on the left.
final class GuidesScreen: UiScreen {
    override func step(_ input: UiInput) {}

    override func draw(_ painter: UiPainter) {
        painter.fill(UiMetrics.screen, r: 0.08, g: 0.14, b: 0.26, a: 1.0)
        let style = TextStyle.menu(0.4)
        for g in 0..<12 {
            let dy = Float(-(11 - g)) * 27.0
            UiWidgets.guide(painter, g, dy: dy, alpha: 1.0, decideIsCross: ctx.services.decideIsCross)
            ctx.text.draw(painter, String(g), style, 4.0, 424.36 + dy + 2.0)
        }
    }
}
