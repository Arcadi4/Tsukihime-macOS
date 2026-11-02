import AppKit
import Foundation
import Metal
import MetalKit
import QuartzCore

/// How to create the window.
public struct WindowOptions: Sendable {
    public var title: String
    public var width: Int
    public var height: Int
    public var hidden: Bool
    public var resizable: Bool
    public var swapInterval: Int
    public var fullscreen: Bool

    public init(
        title: String = "Tsukihime",
        width: Int = 1280,
        height: Int = 720,
        hidden: Bool = false,
        resizable: Bool = true,
        swapInterval: Int = 1,
        fullscreen: Bool = false
    ) {
        self.title = title
        self.width = width
        self.height = height
        self.hidden = hidden
        self.resizable = resizable
        self.swapInterval = swapInterval
        self.fullscreen = fullscreen
    }
}

/// The content view hosting CAMetalLayer / MTKView, capturing input and managing letterboxing.
public final class GameMetalView: MTKView {
    public private(set) var mouseLocation: CGPoint = .zero
    public private(set) var mouseButtons: UInt8 = 0
    public private(set) var wheelDelta: Int = 0
    public private(set) var isMouseInside: Bool = false

    private var keyStates: Set<UInt16> = []
    private var modifierFlags: NSEvent.ModifierFlags = []
    private let stateLock = NSLock()

    public override var acceptsFirstResponder: Bool { true }

    public override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device ?? MTLCreateSystemDefaultDevice())
        commonInit()
    }

    public required init(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        colorPixelFormat = .bgra8Unorm
        isPaused = true
        enableSetNeedsDisplay = false
        autoresizingMask = [.width, .height]

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layer?.contentsScale = window?.backingScaleFactor ?? 2.0
    }

    // MARK: - Mouse Events

    public override func mouseEntered(with event: NSEvent) {
        stateLock.withLock {
            isMouseInside = true
            updateMousePosition(with: event)
        }
    }

    public override func mouseExited(with event: NSEvent) {
        stateLock.withLock {
            isMouseInside = false
        }
    }

    public override func mouseMoved(with event: NSEvent) {
        stateLock.withLock {
            updateMousePosition(with: event)
        }
    }

    public override func mouseDown(with event: NSEvent) {
        stateLock.withLock {
            mouseButtons |= 0x1
            updateMousePosition(with: event)
        }
    }

    public override func mouseUp(with event: NSEvent) {
        stateLock.withLock {
            mouseButtons &= ~0x1
            updateMousePosition(with: event)
        }
    }

    public override func rightMouseDown(with event: NSEvent) {
        stateLock.withLock {
            mouseButtons |= 0x2
            updateMousePosition(with: event)
        }
    }

    public override func rightMouseUp(with event: NSEvent) {
        stateLock.withLock {
            mouseButtons &= ~0x2
            updateMousePosition(with: event)
        }
    }

    public override func otherMouseDown(with event: NSEvent) {
        stateLock.withLock {
            if event.buttonNumber == 2 {
                mouseButtons |= 0x4
            }
            updateMousePosition(with: event)
        }
    }

    public override func otherMouseUp(with event: NSEvent) {
        stateLock.withLock {
            if event.buttonNumber == 2 {
                mouseButtons &= ~0x4
            }
            updateMousePosition(with: event)
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        stateLock.withLock {
            updateMousePosition(with: event)
        }
    }

    public override func rightMouseDragged(with event: NSEvent) {
        stateLock.withLock {
            updateMousePosition(with: event)
        }
    }

    public override func scrollWheel(with event: NSEvent) {
        stateLock.withLock {
            // Positive away from user
            if event.scrollingDeltaY > 0 {
                wheelDelta += 1
            } else if event.scrollingDeltaY < 0 {
                wheelDelta -= 1
            }
        }
    }

    private func updateMousePosition(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        // Flip Y to top-left origin
        let topDownY = bounds.height - loc.y
        mouseLocation = CGPoint(x: loc.x, y: topDownY)
    }

    // MARK: - Keyboard Events

    public override func keyDown(with event: NSEvent) {
        stateLock.withLock {
            keyStates.insert(event.keyCode)
            modifierFlags = event.modifierFlags
        }
    }

    public override func keyUp(with event: NSEvent) {
        stateLock.withLock {
            keyStates.remove(event.keyCode)
            modifierFlags = event.modifierFlags
        }
    }

    public override func flagsChanged(with event: NSEvent) {
        stateLock.withLock {
            modifierFlags = event.modifierFlags
        }
    }

    // MARK: - Snapshot Input State

    public func snapshotInput() -> (keys: Set<UInt16>, modifiers: NSEvent.ModifierFlags, mouseLoc: CGPoint, buttons: UInt8, wheel: Int, inside: Bool) {
        stateLock.withLock {
            let wheel = wheelDelta
            wheelDelta = 0
            return (keyStates, modifierFlags, mouseLocation, mouseButtons, wheel, isMouseInside)
        }
    }
}

/// An AppKit NSWindow hosting a CAMetalLayer / MTKView for Metal compositing.
public final class GameWindow: NSObject, NSWindowDelegate, @unchecked Sendable {
    public let nsWindow: NSWindow
    public let metalView: GameMetalView

    public private(set) var title: String
    public private(set) var isHidden: Bool
    public private(set) var fullscreenRequested: Bool

    public var metalLayer: CAMetalLayer {
        metalView.layer as! CAMetalLayer
    }

    public var isFullscreen: Bool {
        nsWindow.styleMask.contains(.fullScreen)
    }

    public var isMaximized: Bool {
        nsWindow.isZoomed
    }

    public var windowSize: (width: Int, height: Int) {
        let contentRect = nsWindow.contentRect(forFrameRect: nsWindow.frame)
        return (Int(contentRect.width), Int(contentRect.height))
    }

    public var pixelSize: (width: Int, height: Int) {
        let scale = nsWindow.backingScaleFactor
        let (w, h) = windowSize
        return (Int(Double(w) * scale), Int(Double(h) * scale))
    }

    public var viewport: Viewport {
        let (pw, ph) = pixelSize
        return Viewport.fit(windowWidth: pw, windowHeight: ph)
    }

    private init(window: NSWindow, metalView: GameMetalView, options: WindowOptions) {
        self.nsWindow = window
        self.metalView = metalView
        self.title = options.title
        self.isHidden = options.hidden
        self.fullscreenRequested = options.fullscreen
        super.init()
        window.delegate = self
    }

    /// Creates and configures the game window.
    public static func create(options: WindowOptions) throws -> GameWindow {
        let device = MTLCreateSystemDefaultDevice()
        guard let device = device else {
            throw PlatformError("Metal is not supported on this device")
        }

        var styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if options.resizable {
            styleMask.insert(.resizable)
        }

        let rect = NSRect(x: 0, y: 0, width: options.width, height: options.height)
        let window = NSWindow(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)
        window.title = options.title
        window.center()

        let metalView = GameMetalView(frame: rect, device: device)
        window.contentView = metalView
        window.makeFirstResponder(metalView)

        let gameWindow = GameWindow(window: window, metalView: metalView, options: options)

        if !options.hidden {
            window.makeKeyAndOrderFront(nil)
        }

        if options.fullscreen {
            gameWindow.setFullscreen(true)
        }

        return gameWindow
    }

    public func show() {
        nsWindow.makeKeyAndOrderFront(nil)
        isHidden = false
    }

    public func hide() {
        nsWindow.orderOut(nil)
        isHidden = true
    }

    public func close() {
        nsWindow.close()
    }

    public func setTitle(_ title: String) -> Bool {
        self.title = title
        nsWindow.title = title
        return true
    }

    @discardableResult
    public func setFullscreen(_ fullscreen: Bool) -> Bool {
        fullscreenRequested = fullscreen
        if isFullscreen != fullscreen {
            nsWindow.toggleFullScreen(nil)
        }
        return true
    }

    @discardableResult
    public func toggleFullscreen() -> Bool {
        setFullscreen(!fullscreenRequested)
    }

    // MARK: - NSWindowDelegate

    public func windowWillEnterFullScreen(_ notification: Notification) {
        fullscreenRequested = true
    }

    public func windowWillExitFullScreen(_ notification: Notification) {
        fullscreenRequested = false
    }

    public func windowDidResignKey(_ notification: Notification) {
        // Can pause or release modifiers if needed
    }
}
