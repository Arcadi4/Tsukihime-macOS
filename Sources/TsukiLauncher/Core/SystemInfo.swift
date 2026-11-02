import Foundation
import AppKit
import Metal

/// One monitor.
public struct MonitorEntry: Sendable, Equatable, Identifiable {
    public var id: Int { index }
    public let index: Int
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
    public let primary: Bool
    public let name: String
    public let workWidth: Int
    public let workHeight: Int

    public init(
        index: Int,
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        primary: Bool,
        name: String,
        workWidth: Int = 0,
        workHeight: Int = 0
    ) {
        self.index = index
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.primary = primary
        self.name = name
        self.workWidth = workWidth
        self.workHeight = workHeight
    }

    public var label: String {
        let prim = primary ? "  ·  primary" : ""
        return "Display \(index)  ·  \(width) × \(height)\(prim)"
    }

    public var workArea: (width: Int, height: Int) {
        workWidth > 0 && workHeight > 0 ? (workWidth, workHeight) : (width, height)
    }
}

/// Monitors and video adapters on macOS.
public enum SystemInfo {
    public static func videoAdapters() -> [String] {
        let devices = MTLCopyAllDevices()
        if devices.isEmpty {
            return ["Apple Silicon / Metal GPU"]
        }
        return devices.map(\.name)
    }

    public static func monitors() -> [MonitorEntry] {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return [
                MonitorEntry(index: 1, x: 0, y: 0, width: 1920, height: 1080, primary: true, name: "Main Display", workWidth: 1920, workHeight: 1050)
            ]
        }

        var results: [MonitorEntry] = []
        for (i, screen) in screens.enumerated() {
            let frame = screen.frame
            let visible = screen.visibleFrame
            let isPrimary = (screen == NSScreen.main) || (i == 0)
            let name = screen.localizedName
            results.append(
                MonitorEntry(
                    index: i + 1,
                    x: Int(frame.origin.x),
                    y: Int(frame.origin.y),
                    width: Int(frame.width),
                    height: Int(frame.height),
                    primary: isPrimary,
                    name: name,
                    workWidth: Int(visible.width),
                    workHeight: Int(visible.height)
                )
            )
        }
        return results
    }
}
