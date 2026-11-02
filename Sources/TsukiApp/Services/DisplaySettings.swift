import Foundation
import TsukiEngine
import TsukiPlatform
import TsukiUi

/// What the display settings need from the window.
public protocol DisplayWindow: AnyObject {
    var fullscreen: Bool { get }
    var size: (width: Int, height: Int) { get }
    var maximized: Bool { get }
    var workArea: (width: Int, height: Int) { get }
    func setFullscreen(_ fullscreen: Bool) -> Bool
    func resize(width: Int, height: Int) -> (width: Int, height: Int)
}

public typealias IDisplayWindow = DisplayWindow

/// The display settings over the game window.
public final class DisplaySettings: UiDisplaySettings {
    private let window: DisplayWindow
    private let config: ConfigBlock
    private let commit: () -> Void
    private let settingsPath: String?
    private let log: ((String) -> Void)?
    private var windowed: (width: Int, height: Int)
    private var reference: (width: Int, height: Int)

    public init(
        window: DisplayWindow,
        config: ConfigBlock,
        commit: @escaping () -> Void,
        settingsPath: String?,
        windowedSize: (width: Int, height: Int),
        log: ((String) -> Void)? = nil
    ) {
        self.window = window
        self.config = config
        self.commit = commit
        self.settingsPath = settingsPath
        self.log = log
        self.windowed = windowedSize
        self.reference = windowedSize
    }

    public var fullscreen: Bool {
        get { window.fullscreen }
        set {
            guard window.fullscreen != newValue else { return }
            if !window.setFullscreen(newValue) {
                log?("window mode: platform refused \(newValue ? "fullscreen" : "windowed")")
                return
            }
            remember(newValue)
        }
    }

    public var windowSize: (width: Int, height: Int) {
        get { windowed }
        set {
            if window.fullscreen {
                fullscreen = false
            }
            windowed = window.resize(width: newValue.width, height: newValue.height)
            log?("window size: \(windowed.width) x \(windowed.height) (config screen)")
            _ = saveWindowSize(chosen: true)
        }
    }

    public var sizeChoices: [(width: Int, height: Int)] {
        let (w, h) = window.workArea
        return WindowFit.presetsFor(workWidth: w, workHeight: h)
    }

    public var remembered: Bool {
        config.readU8(AppSettings.windowModeOffset) == 1
    }

    public func noteFullscreen(_ fullscreen: Bool) {
        remember(fullscreen)
    }

    public func noteResized() {
        if window.fullscreen || window.maximized {
            return
        }
        let (w, h) = window.size
        if w >= WindowFit.minWidth && h >= WindowFit.minHeight {
            windowed = (w, h)
        }
    }

    @discardableResult
    public func saveWindowSize(chosen: Bool = false) -> Bool {
        guard let settingsPath = settingsPath, (chosen || windowed != reference) else {
            return false
        }
        let (w, h) = windowed
        let ok = AppSettings.update(settingsPath) { s in
            var copy = s
            copy.windowWidth = w
            copy.windowHeight = h
            return copy
        }
        if ok {
            reference = windowed
            log?("window size \(w) x \(h) saved to settings.ini")
        } else {
            log?("settings.ini not written (window size)")
        }
        return ok
    }

    private func remember(_ fullscreen: Bool) {
        let wanted: UInt8 = fullscreen ? 1 : 0
        guard config.readU8(AppSettings.windowModeOffset) != wanted else { return }
        config.writeU8(AppSettings.windowModeOffset, wanted)
        commit()
        log?("window mode: \(fullscreen ? "fullscreen" : "windowed") (remembered)")
    }
}

/// The game window as the display settings see it.
public final class AppDisplayWindow: DisplayWindow {
    private let window: GameWindow

    public init(window: GameWindow) {
        self.window = window
    }

    public var fullscreen: Bool {
        window.fullscreenRequested
    }

    public var size: (width: Int, height: Int) {
        window.windowSize
    }

    public var maximized: Bool {
        window.isMaximized
    }

    public var workArea: (width: Int, height: Int) {
        let d = WindowPlacement.displayOf(window: window)
        return (d.workWidth, d.workHeight)
    }

    public func setFullscreen(_ fullscreen: Bool) -> Bool {
        window.setFullscreen(fullscreen)
    }

    public func resize(width: Int, height: Int) -> (width: Int, height: Int) {
        let placed = WindowPlacement.resize(window: window, width: width, height: height)
        return (placed.width, placed.height)
    }
}
