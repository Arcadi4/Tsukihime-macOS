import Foundation

/// The rectangle of the canvas inside a window, in window pixels.
public struct Viewport: Sendable, Equatable {
    public static let canvasWidth: Int = 1920
    public static let canvasHeight: Int = 1080
    public static let pointerWidth: Int = 640
    public static let pointerHeight: Int = 448

    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// The letterboxed rectangle for a window of the given pixel size.
    public static func fit(windowWidth: Int, windowHeight: Int) -> Viewport {
        let ww = max(1, windowWidth)
        let wh = max(1, windowHeight)
        let s = min(Float(ww) / Float(canvasWidth), Float(wh) / Float(canvasHeight))
        let w = max(1, Int(Float(canvasWidth) * s))
        let h = max(1, Int(Float(canvasHeight) * s))
        return Viewport(x: (ww - w) / 2, y: (wh - h) / 2, width: w, height: h)
    }

    /// True when the window point lies inside the canvas.
    public func contains(x: Float, y: Float) -> Bool {
        x >= Float(self.x) && y >= Float(self.y) && x < Float(self.x + self.width) && y < Float(self.y + self.height)
    }

    /// The canvas pixel under a window point (not clamped).
    public func toCanvas(x: Float, y: Float) -> (x: Float, y: Float) {
        let cx = (x - Float(self.x)) * Float(Self.canvasWidth) / Float(self.width)
        let cy = (y - Float(self.y)) * Float(Self.canvasHeight) / Float(self.height)
        return (cx, cy)
    }

    /// The PS4 pointer (0..639, 0..447) under a window point.
    public func toPointer(x: Float, y: Float) -> (inside: Bool, x: Int16, y: Int16) {
        let (cx, cy) = toCanvas(x: x, y: y)
        let rawPx = Int(cx * Float(Self.pointerWidth) / Float(Self.canvasWidth))
        let rawPy = Int(cy * Float(Self.pointerHeight) / Float(Self.canvasHeight))
        let px = Int16(max(0, min(Self.pointerWidth - 1, rawPx)))
        let py = Int16(max(0, min(Self.pointerHeight - 1, rawPy)))
        return (contains(x: x, y: y), px, py)
    }
}
