import Foundation
import TsukiCore
import TsukiEngine

/// What the UI is doing, for the game host: story with no screen, the title, or an overlay screen over the story.
public enum UiMode: Sendable {
    /// No screen is open: the story runs (the mode panel and banners may still show).
    case story
    /// The boot sequence or the title screen is on top; the host runs no story.
    case title
    /// A system screen (menu, config, save / load, backlog, dialog) is open over the story or the title.
    case overlay

    public static let Story = UiMode.story
    public static let Title = UiMode.title
    public static let Overlay = UiMode.overlay
}

/// The owner of the screens (ARCHITECTURE 9.1).
public final class UiRoot {
    private var _stack: [UiScreen] = []
    private var _painter: UiPainter!
    private var _previousPointer: PointerState = PointerState()
    private var _banner: UiBanner?
    private var _blurFrames: Int = 0
    private var _toast: UiToast?

    /// Creates a root over a game data source and the game services.
    public init(data: GameData, services: GameServices, parts: UiPictureSource? = nil) {
        let assets = UiAssets(data: data, language: services.language, parts: parts)
        self._painter = UiPainter(assets)
        self.context = UiContext(root: self, services: services, assets: assets)
    }

    /// The shared context.
    public private(set) var context: UiContext!
    public var Context: UiContext { context }

    /// The painter.
    public var painter: UiPainter { _painter }
    public var Painter: UiPainter { painter }

    /// The open screens, bottom first.
    public var stack: [UiScreen] { _stack }
    public var Stack: [UiScreen] { stack }

    /// The screen that gets the input, or nil.
    public var top: UiScreen? { _stack.last }
    public var Top: UiScreen? { top }

    /// True while a screen is open.
    public var active: Bool { !_stack.isEmpty }
    public var Active: Bool { active }

    /// The mode banner on show, or nil.
    public var banner: UiBanner? { _banner }
    public var Banner: UiBanner? { banner }

    /// The port's toast on show, or nil.
    public var toast: UiToast? { _toast }
    public var Toast: UiToast? { toast }

    /// True while the toast must not be drawn.
    public var hideToast: Bool = false
    public var HideToast: Bool { get { hideToast } set { hideToast = newValue } }

    /// What the UI is doing.
    public var mode: UiMode {
        guard let first = _stack.first else {
            return .story
        }
        if first is TitleScreen || first is BootScreen {
            return .title
        }
        return .overlay
    }
    public var Mode: UiMode { mode }

    /// True while the system menu or the backlog covers the story.
    public var blurScene: Bool {
        mode == .overlay && _stack.contains(where: { $0 is SystemMenuScreen || $0 is BacklogScreen })
    }
    public var BlurScene: Bool { blurScene }

    /// The strength of the blurred scene behind the system menu and the backlog.
    public var blurAlpha: Float {
        min(1.0, Float(_blurFrames) / Float(UiMenuBlur.fadeFrames))
    }
    public var BlurAlpha: Float { blurAlpha }

    /// The first screen of the given type in the stack, or nil.
    public func find<T: UiScreen>(_ type: T.Type) -> T? {
        for s in _stack {
            if let match = s as? T {
                return match
            }
        }
        return nil
    }
    public func Find<T: UiScreen>(_ type: T.Type) -> T? { find(type) }

    /// Pushes a screen on top.
    @discardableResult
    public func push<T: UiScreen>(_ screen: T) -> T {
        screen.root = self
        _stack.append(screen)
        screen.onOpened()
        return screen
    }
    @discardableResult
    public func Push<T: UiScreen>(_ screen: T) -> T { push(screen) }

    /// Opens the system menu over the story.
    @discardableResult
    public func openSystemMenu() -> Bool {
        if active {
            return false
        }
        push(SystemMenuScreen())
        return true
    }
    @discardableResult
    public func OpenSystemMenu() -> Bool { openSystemMenu() }

    /// Opens the backlog.
    @discardableResult
    public func openBacklog() -> Bool {
        if active || context.services.backlog.isEmpty {
            return false
        }
        push(BacklogScreen())
        return true
    }
    @discardableResult
    public func OpenBacklog() -> Bool { openBacklog() }

    /// Opens the mode panel.
    @discardableResult
    public func openModePanel() -> Bool {
        if active || !context.services.panelAllowed {
            return false
        }
        push(ModePanelScreen())
        return true
    }
    @discardableResult
    public func OpenModePanel() -> Bool { openModePanel() }

    /// The host calls this when a replay started from the gallery has ended.
    @discardableResult
    public func returnToGallery() -> Bool {
        if active || context.assets.gallery == nil {
            return false
        }
        context.titleIntroShown = true
        let title = push(TitleScreen())
        title.resumeInGallery()
        return true
    }
    @discardableResult
    public func ReturnToGallery() -> Bool { returnToGallery() }

    /// Removes every screen at once.
    public func clear() {
        for s in _stack.reversed() {
            s.onClosed()
        }
        _stack.removeAll()
    }
    public func Clear() { clear() }

    /// Shows the mode banner.
    public func showBanner(_ kind: BannerKind) {
        _banner = UiBanner(kind)
    }
    public func ShowBanner(_ kind: BannerKind) { showBanner(kind) }

    /// A button while the banner holds sends it away.
    public func dismissBanner() {
        _banner?.sendAway()
    }
    public func DismissBanner() { dismissBanner() }

    /// Shows a toast with `text`.
    public func showToast(_ text: String, brief: Bool = true) {
        _toast = UiToast(text, brief: brief)
    }
    public func ShowToast(_ text: String, _ brief: Bool = true) { showToast(text, brief: brief) }

    /// Steps the UI by one 60 Hz frame.
    public func step(_ frame: InputFrame) {
        context.frame += 1
        if context.services.language != context.assets.language {
            context.assets.setLanguage(context.services.language)
        }

        _blurFrames = blurScene ? _blurFrames + 1 : 0
        let input = applyGuideClick(UiInput.from(frame, previous: _previousPointer))
        _previousPointer = frame.pointer

        let screens = _stack
        for s in screens {
            s.stepFade()
        }

        if !screens.isEmpty {
            if screens.count > 1 {
                for i in 0..<(screens.count - 1) {
                    if _stack.contains(where: { $0 === screens[i] }) {
                        screens[i].stepBackground()
                    }
                }
            }
            if let last = screens.last, _stack.contains(where: { $0 === last }) {
                last.step(input)
            }
        }

        var i = _stack.count - 1
        while i >= 0 {
            if i >= _stack.count {
                i -= 1
                continue
            }
            if _stack[i].finished {
                let s = _stack.remove(at: i)
                s.onClosed()
            }
            i -= 1
        }

        context.backdrop.update()
        if let b = _banner {
            b.step()
            if b.done {
                _banner = nil
            }
        }

        if let t = _toast {
            t.step()
            if t.done {
                _toast = nil
            }
        }
    }
    public func Step(_ frame: InputFrame) { step(frame) }

    private func applyGuideClick(_ input: UiInput) -> UiInput {
        guard input.click && input.pointerActive else {
            return input
        }

        for h in _painter.guideHits {
            guard h.rect.contains(input.pointerX, input.pointerY) else {
                continue
            }

            var u = input
            u.click = false
            u.decide = false
            switch h.action {
            case .back:
                u.cancel = true
                return u
            case .confirm:
                u.decide = true
                return u
            case .deleteData:
                u.deleteData = true
                return u
            case .shoulders:
                if input.pointerX < h.rect.x + (h.rect.w / 2.0) {
                    u.l1 = true
                } else {
                    u.r1 = true
                }
                return u
            case .none:
                return u
            }
        }

        return input
    }

    /// Appends the quads of the open screens and the banner to `list`.
    public func draw(_ list: DisplayList) {
        if blurScene {
            UiMenuBlur.append(list, blurAlpha)
        }

        _painter.begin(list)
        _painter.promptStyle = context.services.promptStyle

        var first = 0
        if !_stack.isEmpty {
            for i in stride(from: _stack.count - 1, through: 0, by: -1) {
                if _stack[i].opaque {
                    first = i
                    break
                }
            }
        }

        for i in first..<_stack.count {
            _stack[i].draw(_painter)
        }

        _banner?.draw(_painter, context)

        if _stack.isEmpty, let prompt = context.services.storyPrompt {
            UiStoryPromptView.draw(_painter, context, prompt)
        }

        if let t = _toast, !hideToast {
            t.draw(_painter)
        }
    }
    public func Draw(_ list: DisplayList) { draw(list) }

    /// True when a left click went down on the Confirm word of the story prompt's guide line.
    public func storyPromptConfirmClicked(_ pointer: PointerState) -> Bool {
        if !_stack.isEmpty || !pointer.active || !pointer.pressed.contains(.left) || context.services.storyPrompt == nil {
            return false
        }

        let px: Float = pointer.canvasX.isNaN ? (Float(pointer.x) + 0.5) * UiMetrics.unitX : pointer.canvasX
        let py: Float = pointer.canvasY.isNaN ? (Float(pointer.y) + 0.5) * UiMetrics.unitY : pointer.canvasY

        for h in _painter.guideHits {
            if h.action == .confirm && h.rect.contains(px, py) {
                return true
            }
        }

        return false
    }
    public func StoryPromptConfirmClicked(_ pointer: PointerState) -> Bool {
        storyPromptConfirmClicked(pointer)
    }
}
