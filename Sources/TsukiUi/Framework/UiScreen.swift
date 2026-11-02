import Foundation

/// A menu screen: a state machine that steps once per 60 Hz frame and draws itself through a `UiPainter` (ARCHITECTURE 9.1). Screens stack on
/// the `UiRoot`; the top one gets the input. The base class keeps the content fade every PS4 screen has (knife `fade_speeds`: per-frame
/// steps in and out, the screen leaves when the fade-out ends).
open class UiScreen {
    /// The root that owns the screen (set when the screen is pushed).
    public internal(set) weak var root: UiRoot?
    public var Root: UiRoot {
        guard let root = root else {
            fatalError("UiScreen.root accessed before screen was pushed or after root was deallocated")
        }
        return root
    }

    /// The shared services, assets and drawing helpers.
    public var ctx: UiContext { Root.context }
    public var Ctx: UiContext { ctx }

    /// The content alpha 0..1 (rises while opening, falls while closing).
    public internal(set) var fade: Float = 1.0
    public var Fade: Float { fade }

    /// True once `close` was called.
    public private(set) var closing: Bool = false
    public var Closing: Bool { closing }

    /// True when the screen has finished closing and the root should remove it.
    open var finished: Bool { closing && fade <= 0.0 }
    public var Finished: Bool { finished }

    /// True when the screen draws the whole frame, so the screens below it are not drawn.
    open var opaque: Bool { false }
    public var Opaque: Bool { opaque }

    /// The fade-in step per frame (1 = instant).
    open var fadeInStep: Float { 1.0 }
    public var FadeInStep: Float { fadeInStep }

    /// The fade-out step per frame (1 = instant).
    open var fadeOutStep: Float { 1.0 }
    public var FadeOutStep: Float { fadeOutStep }

    public init() {}

    /// The screen starts at alpha 0 and fades in (set by screens with a fade-in step below 1).
    public func startHidden() {
        fade = 0.0
    }
    public func StartHidden() {
        startHidden()
    }

    /// Called once when the screen is pushed.
    open func onOpened() {}
    public func OnOpened() { onOpened() }

    /// Called once when the screen has been removed.
    open func onClosed() {}
    public func OnClosed() { onClosed() }

    /// Starts leaving: the content fades out, then `finished` becomes true.
    open func close() {
        if closing {
            return
        }
        closing = true
        if fadeOutStep >= 1.0 {
            fade = 0.0
        }
    }
    public func Close() { close() }

    /// One frame of the content fade; the root calls it before `step`.
    func stepFade() {
        if closing {
            fade = max(0.0, fade - fadeOutStep)
        } else if fade < 1.0 {
            fade = min(1.0, fade + fadeInStep)
        }
    }
    func StepFade() { stepFade() }

    /// One frame with the input; only the top screen gets this.
    open func step(_ input: UiInput) {}
    public func Step(_ input: UiInput) { step(input) }

    /// One frame for a screen that is covered by another (animations go on, input does not).
    open func stepBackground() {}
    public func StepBackground() { stepBackground() }

    /// Appends the screen's quads.
    open func draw(_ painter: UiPainter) {}
    public func Draw(_ painter: UiPainter) { draw(painter) }
}
