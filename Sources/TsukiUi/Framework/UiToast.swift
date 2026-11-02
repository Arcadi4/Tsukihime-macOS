import Foundation

/// A toast: one short line of text in a small rounded box at the bottom left, shown briefly.
public final class UiToast {
    /// Frames a brief toast stays fully visible (1.2 s; with the fades the toast is on show for 1.5 s).
    public static let holdFrames: Int = 72
    public static let HoldFrames: Int = holdFrames

    /// Frames a long toast stays fully visible (2.5 s): for a notice with an address or an error in it.
    public static let longHoldFrames: Int = 150
    public static let LongHoldFrames: Int = longHoldFrames

    /// Frames of the fade-in.
    public static let fadeInFrames: Int = 6
    public static let FadeInFrames: Int = fadeInFrames

    /// Frames of the fade-out.
    public static let fadeOutFrames: Int = 12
    public static let FadeOutFrames: Int = fadeOutFrames

    private static let margin: Float = 40.0
    private static let bottom: Float = UiMetrics.height - 72.0
    private static let paddingX: Float = 18.0
    private static let height: Float = 40.0
    private static let border: Float = 2.0
    private static let scale: Double = 0.32

    private let _hold: Int
    private var _frame: Int = 0

    public init(_ text: String, brief: Bool = true) {
        self.text = text
        self._hold = brief ? Self.holdFrames : Self.longHoldFrames
    }

    /// The words.
    public let text: String
    public var Text: String { text }

    /// Frames this toast stays fully visible.
    public var hold: Int { _hold }
    public var Hold: Int { hold }

    /// The alpha 0..1 of this frame.
    public var alpha: Float {
        if _frame < Self.fadeInFrames {
            return Float(_frame) / Float(Self.fadeInFrames)
        }
        if _frame < Self.fadeInFrames + _hold {
            return 1.0
        }
        return max(0.0, 1.0 - (Float(_frame - Self.fadeInFrames - _hold) / Float(Self.fadeOutFrames)))
    }
    public var Alpha: Float { alpha }

    /// True once the toast has gone.
    public var done: Bool {
        _frame >= Self.fadeInFrames + _hold + Self.fadeOutFrames
    }
    public var Done: Bool { done }

    public func step() {
        _frame += 1
    }
    public func Step() { step() }

    /// The box the toast draws (the text's width plus the padding).
    public func box(_ p: UiPainter) -> RectF {
        let w = UiPrompts.textWidth(p, text, scale: Self.scale) + (2.0 * Self.paddingX)
        return RectF(Self.margin, Self.bottom - Self.height, w, Self.height)
    }
    public func Box(_ p: UiPainter) -> RectF { box(p) }

    public func draw(_ p: UiPainter) {
        let a = alpha
        if a <= 0.0 {
            return
        }
        let r = box(p)
        p.fillRounded(r, radius: 10.0, r: 0.62, g: 0.86, b: 1.0, a: 0.8 * a)
        p.fillRounded(RectF(r.x + Self.border, r.y + Self.border, r.w - (2.0 * Self.border), r.h - (2.0 * Self.border)), radius: 8.0, r: 0.03, g: 0.07, b: 0.16, a: 0.9 * a, smooth: false)
        UiPrompts.drawText(p, text, r.x + Self.paddingX, r.y + (r.h / 2.0), a, scale: Self.scale)
    }
    public func Draw(_ p: UiPainter) { draw(p) }
}
