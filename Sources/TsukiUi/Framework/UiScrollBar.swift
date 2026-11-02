import Foundation

/// What the pointer did to a `UiScrollBar` in one step.
public struct ScrollBarUse: Sendable {
    public var consumed: Bool
    public var fraction: Float?
    public var page: Int

    public var Consumed: Bool { consumed }
    public var Fraction: Float? { fraction }
    public var Page: Int { page }

    public init(consumed: Bool = false, fraction: Float? = nil, page: Int = 0) {
        self.consumed = consumed
        self.fraction = fraction
        self.page = page
    }
}

/// The mouse side of the lists' scroll bar (package K12).
public final class UiScrollBar {
    /// Left edge of the area that grabs the pointer.
    public static let zoneX: Float = 1831.0
    public static let ZoneX: Float = zoneX

    /// Width of the grab area.
    public static let zoneW: Float = 48.0
    public static let ZoneW: Float = zoneW

    /// Top of the track area (the thumb's rest position).
    public static let zoneTop: Float = 99.0
    public static let ZoneTop: Float = zoneTop

    /// Height of the track area (the 888 px track plus the thumb's overhang).
    public static let zoneH: Float = 896.0
    public static let ZoneH: Float = zoneH

    /// The thumb sprite is 288 px tall; its lit part starts 8 px below the sprite's top and is 276 px tall.
    public static let thumbHitTop: Float = 8.0
    public static let ThumbHitTop: Float = thumbHitTop

    /// Height of the part of the thumb that grabs.
    public static let thumbHitH: Float = 276.0
    public static let ThumbHitH: Float = thumbHitH

    /// Frames a held track click waits before it repeats (the d-pad's repeat delay).
    public static let repeatDelay: Int = 24
    public static let RepeatDelay: Int = repeatDelay

    /// Frames between repeats of a held track click.
    public static let repeatPeriod: Int = 6
    public static let RepeatPeriod: Int = repeatPeriod

    private var _drag: Bool = false
    private var _grab: Float = 0
    private var _page: Int = 0
    private var _held: Int = 0

    /// True while the thumb is being dragged or a track click is held.
    public var pressed: Bool { _drag || _page != 0 }
    public var Pressed: Bool { pressed }

    /// True while the thumb is being dragged.
    public var dragging: Bool { _drag }
    public var Dragging: Bool { dragging }

    /// The pointer is over the thumb (or has it grabbed).
    public private(set) var hover: Bool = false
    public var Hover: Bool { hover }

    public init() {}

    /// The top of the thumb sprite at `fraction` of `travel`.
    public static func thumbTop(_ fraction: Float, travel: Float) -> Float {
        (min(max(fraction, 0.0), 1.0) * travel) + zoneTop
    }
    public static func ThumbTop(_ fraction: Float, _ travel: Float) -> Float {
        thumbTop(fraction, travel: travel)
    }

    /// The area in which the bar takes the pointer.
    public static var zone: RectF {
        RectF(zoneX, zoneTop, zoneW, zoneH)
    }
    public static var Zone: RectF { zone }

    /// The part of the thumb that grabs, at `fraction` of `travel`.
    public static func thumbRect(_ fraction: Float, travel: Float) -> RectF {
        RectF(zoneX, thumbTop(fraction, travel: travel) + thumbHitTop, zoneW, thumbHitH)
    }
    public static func ThumbRect(_ fraction: Float, _ travel: Float) -> RectF {
        thumbRect(fraction, travel: travel)
    }

    /// Lets go of the thumb and any held track click.
    public func release() {
        _drag = false
        _page = 0
        _held = 0
        hover = false
    }
    public func Release() { release() }

    /// One 60 Hz step of the bar.
    public func step(_ input: UiInput, fraction: Float, travel: Float, enabled: Bool) -> ScrollBarUse {
        if !enabled || travel <= 0.0 {
            release()
            return ScrollBarUse()
        }

        let top = Self.thumbTop(fraction, travel: travel)
        let thumb = Self.thumbRect(fraction, travel: travel)

        if _drag {
            if input.pointerHeld {
                hover = true
                return ScrollBarUse(consumed: true, fraction: min(max((input.pointerY - _grab - Self.zoneTop) / travel, 0.0), 1.0), page: 0)
            }
            _drag = false
        }

        if _page != 0 {
            let beyond = _page < 0 ? input.pointerY < thumb.y : input.pointerY >= thumb.bottom
            if !input.pointerHeld || !input.pointerActive || !beyond || !Self.zone.contains(input.pointerX, input.pointerY) {
                _page = 0
                _held = 0
            } else {
                _held += 1
                let again = _held >= Self.repeatDelay && (_held - Self.repeatDelay) % Self.repeatPeriod == 0
                hover = false
                return ScrollBarUse(consumed: true, fraction: nil, page: again ? _page : 0)
            }
        }

        hover = input.over(thumb)
        if input.click && input.pointerActive && Self.zone.contains(input.pointerX, input.pointerY) {
            if thumb.contains(input.pointerX, input.pointerY) {
                _drag = true
                _grab = input.pointerY - top
                hover = true
                return ScrollBarUse(consumed: true, fraction: nil, page: 0)
            }

            _page = input.pointerY < thumb.y ? -1 : 1
            _held = 0
            return ScrollBarUse(consumed: true, fraction: nil, page: _page)
        }

        return ScrollBarUse()
    }
    @discardableResult
    public func step(_ input: UiInput, fraction: Float, height: Float, canScroll: Bool) -> ScrollBarUse {
        step(input, fraction: fraction, travel: height, enabled: canScroll)
    }
    @discardableResult
    public func step(_ input: UiInput, _ fraction: Float, _ height: Float, _ canScroll: Bool) -> ScrollBarUse {
        step(input, fraction: fraction, travel: height, enabled: canScroll)
    }
    public func Step(_ input: UiInput, _ fraction: Float, _ travel: Float, _ enabled: Bool) -> ScrollBarUse {
        step(input, fraction: fraction, travel: travel, enabled: enabled)
    }
}
