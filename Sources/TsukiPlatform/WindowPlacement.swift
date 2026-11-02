import AppKit
import Foundation

/// One display as AppKit reports it.
public struct DisplayInfo: Sendable, Equatable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
    public let name: String
    public let workX: Int
    public let workY: Int
    public let workWidth: Int
    public let workHeight: Int

    public init(
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        name: String,
        workX: Int,
        workY: Int,
        workWidth: Int,
        workHeight: Int
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.name = name
        self.workX = workX
        self.workY = workY
        self.workWidth = workWidth
        self.workHeight = workHeight
    }
}

/// What WindowPlacement.place did.
public struct Placement: Sendable, CustomStringConvertible {
    public let display: DisplayInfo
    public let monitorMatched: Bool
    public let width: Int
    public let height: Int
    public let x: Int
    public let y: Int
    public let clamped: Bool

    public init(
        display: DisplayInfo,
        monitorMatched: Bool,
        width: Int,
        height: Int,
        x: Int,
        y: Int,
        clamped: Bool
    ) {
        self.display = display
        self.monitorMatched = monitorMatched
        self.width = width
        self.height = height
        self.x = x
        self.y = y
        self.clamped = clamped
    }

    public var description: String {
        "\(width) x \(height) at (\(x), \(y)) on \"\(display.name)\" \(display.width) x \(display.height) (work area \(display.workWidth) x \(display.workHeight) at (\(display.workX), \(display.workY)))\(clamped ? ", clamped to the work area" : "")"
    }
}

/// Display enumeration and window placement for macOS AppKit windows.
public enum WindowPlacement {
    /// Every display currently connected.
    public static func displays() -> [DisplayInfo] {
        NSScreen.screens.map(describe(screen:))
    }

    /// The display the window is on (the primary one when undefined).
    public static func displayOf(window: GameWindow) -> DisplayInfo {
        displayOf(screen: window.nsWindow.screen)
    }

    public static func displayOf(screen: NSScreen?) -> DisplayInfo {
        if let s = screen {
            return describe(screen: s)
        }
        if let primary = NSScreen.screens.first {
            return describe(screen: primary)
        }
        return DisplayInfo(x: 0, y: 0, width: 1920, height: 1080, name: "Default", workX: 0, workY: 0, workWidth: 1920, workHeight: 1080)
    }

    public static func windowSize(window: GameWindow) -> (width: Int, height: Int) {
        window.windowSize
    }

    /// Sizes and centres a window that is not fullscreen.
    @discardableResult
    public static func place(window: GameWindow, monitorX: Int? = nil, monitorY: Int? = nil, width: Int? = nil, height: Int? = nil) -> Placement {
        var target: DisplayInfo?
        if let mx = monitorX, let my = monitorY {
            for d in displays() {
                if d.x == mx && d.y == my {
                    target = d
                    break
                }
            }
        }

        let display = target ?? displayOf(window: window)
        let (cw, ch) = window.windowSize
        let rw = width ?? cw
        let rh = height ?? ch

        let (w, h) = WindowFit.clamp(width: rw, height: rh, workWidth: display.workWidth, workHeight: display.workHeight)
        window.nsWindow.minSize = NSSize(width: min(WindowFit.minWidth, w), height: min(WindowFit.minHeight, h))

        let (x, y) = WindowFit.centre(workX: display.workX, workY: display.workY, workWidth: display.workWidth, workHeight: display.workHeight, width: w, height: h)

        let newFrame = NSRect(x: x, y: y, width: w, height: h)
        window.nsWindow.setFrame(newFrame, display: true, animate: false)

        return Placement(display: display, monitorMatched: target != nil, width: w, height: h, x: x, y: y, clamped: w != rw || h != rh)
    }

    /// Resizes a window to width x height (clamped) and centres it on the display it is on.
    @discardableResult
    public static func resize(window: GameWindow, width: Int, height: Int) -> Placement {
        place(window: window, monitorX: nil, monitorY: nil, width: width, height: height)
    }

    private static func describe(screen: NSScreen) -> DisplayInfo {
        let f = screen.frame
        let vf = screen.visibleFrame
        return DisplayInfo(
            x: Int(f.origin.x),
            y: Int(f.origin.y),
            width: Int(f.size.width),
            height: Int(f.size.height),
            name: screen.localizedName,
            workX: Int(vf.origin.x),
            workY: Int(vf.origin.y),
            workWidth: Int(vf.size.width),
            workHeight: Int(vf.size.height)
        )
    }
}
