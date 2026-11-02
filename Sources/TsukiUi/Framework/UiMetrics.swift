import Foundation
import TsukiCore

/// A rectangle in canvas pixels (x, y, width, height).
public struct RectF: Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var w: Float
    public var h: Float

    public var X: Float { get { x } set { x = newValue } }
    public var Y: Float { get { y } set { y = newValue } }
    public var W: Float { get { w } set { w = newValue } }
    public var H: Float { get { h } set { h = newValue } }

    public init(x: Float, y: Float, w: Float, h: Float) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    public init(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        self.init(x: x, y: y, w: w, h: h)
    }

    public static let zero = RectF(0, 0, 0, 0)

    /// Right edge.
    public var right: Float { x + w }
    public var Right: Float { right }

    /// Bottom edge.
    public var bottom: Float { y + h }
    public var Bottom: Float { bottom }

    /// A rectangle from corners (x0, y0) and (x1, y1).
    public static func fromCorners(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float) -> RectF {
        RectF(x0, y0, x1 - x0, y1 - y0)
    }
    public static func FromCorners(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float) -> RectF {
        fromCorners(x0, y0, x1, y1)
    }

    /// True when (px, py) is inside (left and top inclusive, right and bottom exclusive).
    public func contains(_ px: Float, _ py: Float) -> Bool {
        px >= x && px < x + w && py >= y && py < y + h
    }
    public func Contains(_ px: Float, _ py: Float) -> Bool {
        contains(px, py)
    }

    /// The rectangle moved by (dx, dy).
    public func offset(_ dx: Float, _ dy: Float) -> RectF {
        RectF(x + dx, y + dy, w, h)
    }
    public func Offset(_ dx: Float, _ dy: Float) -> RectF {
        offset(dx, dy)
    }

    /// The overlap with `o`, or an empty rectangle.
    public func intersect(_ o: RectF) -> RectF {
        let x0 = max(x, o.x)
        let y0 = max(y, o.y)
        let x1 = min(right, o.right)
        let y1 = min(bottom, o.bottom)
        return x1 > x0 && y1 > y0 ? RectF(x0, y0, x1 - x0, y1 - y0) : RectF(x0, y0, 0, 0)
    }
    public func Intersect(_ o: RectF) -> RectF {
        intersect(o)
    }

    /// True when the rectangle has no area.
    public var isEmpty: Bool { w <= 0 || h <= 0 }
    public var IsEmpty: Bool { isEmpty }
}

/// The UI canvas: the 1920 x 1080 frame. The PS4 screens lay out in 640 x 448 units (3 px per unit across, 1080 / 448 = 2.4107 px down;
/// docs/formats/archives_ui_movies.md 7.5), in 960 x 540 / 960 x 544 units (2 px), or directly in pixels, as knife's ui.rs does.
public enum UiMetrics {
    /// Canvas width in pixels.
    public static let width: Float = 1920.0
    public static let Width: Float = width

    /// Canvas height in pixels.
    public static let height: Float = 1080.0
    public static let Height: Float = height

    /// Pixels per unit across in the 640 x 448 space.
    public static let unitX: Float = width / 640.0
    public static let UnitX: Float = unitX

    /// Pixels per unit down in the 640 x 448 space.
    public static let unitY: Float = height / 448.0
    public static let UnitY: Float = unitY

    /// The 640 x 448 x coordinate in pixels.
    @inline(__always)
    public static func x(_ units: Float) -> Float { units * unitX }
    @inline(__always)
    public static func X(_ units: Float) -> Float { x(units) }

    /// The 640 x 448 y coordinate in pixels.
    @inline(__always)
    public static func y(_ units: Float) -> Float { units * unitY }
    @inline(__always)
    public static func Y(_ units: Float) -> Float { y(units) }

    /// The pixel rectangle of a 640 x 448 rectangle (x, y, w, h in units).
    public static func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> RectF {
        RectF(x * unitX, y * unitY, w * unitX, h * unitY)
    }
    public static func Rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> RectF {
        rect(x, y, w, h)
    }

    /// The screen rectangle.
    public static var screen: RectF { RectF(0, 0, width, height) }
    public static var Screen: RectF { screen }
}

/// How a sprite is combined with what is under it.
public enum UiBlend: UInt8, Sendable {
    /// Normal alpha-over (draw effect 0).
    case alpha = 0

    /// The additive surface mode of the menu glows (draw effect 11, `ps_add`; docs/formats/system_flow.md 2).
    case psAdd = 11

    /// The additive blend state of the title moon glow (draw effect 52; system_flow.md 2).
    case add = 52

    public static let Alpha = UiBlend.alpha
    public static let PsAdd = UiBlend.psAdd
    public static let Add = UiBlend.add
}
