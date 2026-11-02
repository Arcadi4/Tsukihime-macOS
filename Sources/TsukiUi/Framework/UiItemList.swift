import Foundation

/// One selectable item of a screen: its hit rectangle in canvas pixels, an id the screen understands, and whether it can be selected.
public struct UiItem: Equatable, Sendable {
    public var rect: RectF
    public var id: Int
    public var enabled: Bool

    public var Rect: RectF { rect }
    public var Id: Int { id }
    public var Enabled: Bool { enabled }

    public init(rect: RectF, id: Int, enabled: Bool = true) {
        self.rect = rect
        self.id = id
        self.enabled = enabled
    }

    public init(_ rect: RectF, _ id: Int, _ enabled: Bool = true) {
        self.init(rect: rect, id: id, enabled: enabled)
    }
}

/// The cursor of a menu: items with hit rectangles, a focused index (-1 = none), keyboard moves that wrap and skip disabled items, and the pointer rule of
/// the PS4 menus: the pointer moving over an item gives it the focus (docs/formats/system_flow.md 4.4 "pointer hover selects"), a click on an item acts on it.
public final class UiItemList {
    private var _items: [UiItem] = []

    /// The items in cursor order.
    public var items: [UiItem] { _items }
    public var Items: [UiItem] { _items }

    /// The focused item index, or -1.
    public var cursor: Int = -1
    public var Cursor: Int { get { cursor } set { cursor = newValue } }

    /// The id of the focused item, or -1.
    public var focusedId: Int {
        cursor >= 0 && cursor < _items.count ? _items[cursor].id : -1
    }
    public var FocusedId: Int { focusedId }

    /// Number of items.
    public var count: Int { _items.count }
    public var Count: Int { count }

    public init() {}

    /// Removes every item (the cursor stays where it was).
    public func clear() { _items.removeAll() }
    public func Clear() { clear() }

    /// Adds an item.
    public func add(_ rect: RectF, _ id: Int, _ enabled: Bool = true) {
        _items.append(UiItem(rect: rect, id: id, enabled: enabled))
    }
    public func Add(_ rect: RectF, _ id: Int, _ enabled: Bool = true) {
        add(rect, id, enabled)
    }

    /// The index of the item with `id`, or -1.
    public func indexOf(_ id: Int) -> Int {
        _items.firstIndex(where: { $0.id == id }) ?? -1
    }
    public func IndexOf(_ id: Int) -> Int {
        indexOf(id)
    }

    /// The index of the enabled item under the point, or -1.
    public func hitTest(_ x: Float, _ y: Float) -> Int {
        for i in stride(from: _items.count - 1, through: 0, by: -1) {
            if _items[i].enabled && _items[i].rect.contains(x, y) {
                return i
            }
        }
        return -1
    }
    public func HitTest(_ x: Float, _ y: Float) -> Int {
        hitTest(x, y)
    }

    /// Applies the pointer: when it moved over an item the cursor goes there. A pointer that is over nothing leaves the cursor where it is (the keys' focus is
    /// not taken away).
    public func hover(_ input: UiInput) -> Bool {
        if !input.pointerMoved {
            return false
        }
        let hit = hitTest(input.pointerX, input.pointerY)
        if hit < 0 || hit == cursor {
            return false
        }
        cursor = hit
        return true
    }
    public func Hover(_ input: UiInput) -> Bool {
        hover(input)
    }

    /// The index of the enabled item the pointer clicked, or -1.
    public func clicked(_ input: UiInput) -> Int {
        input.click && input.pointerActive ? hitTest(input.pointerX, input.pointerY) : -1
    }
    public func Clicked(_ input: UiInput) -> Int {
        clicked(input)
    }

    /// Moves the cursor by `delta` (+1 / -1) over the enabled items. From no focus it goes to the first (down) or last (up).
    public func move(_ delta: Int, wrap: Bool = true) -> Bool {
        let n = _items.count
        if n == 0 || delta == 0 {
            return false
        }

        let step = delta > 0 ? 1 : -1
        var at = cursor
        if at < 0 || at >= n {
            at = step > 0 ? -1 : n
        }

        for _ in 0..<n {
            at += step
            if at < 0 || at >= n {
                if !wrap {
                    return false
                }
                at = (at % n + n) % n
            }

            if _items[at].enabled {
                let changed = at != cursor
                cursor = at
                return changed
            }
        }

        return false
    }
    public func Move(_ delta: Int, _ wrap: Bool = true) -> Bool {
        move(delta, wrap: wrap)
    }

    /// Moves the cursor to the first enabled item.
    public func first() -> Bool {
        for i in 0..<_items.count {
            if _items[i].enabled {
                let changed = cursor != i
                cursor = i
                return changed
            }
        }
        return false
    }
    public func First() -> Bool {
        first()
    }

    /// Moves the cursor to the last enabled item.
    public func last() -> Bool {
        for i in stride(from: _items.count - 1, through: 0, by: -1) {
            if _items[i].enabled {
                let changed = cursor != i
                cursor = i
                return changed
            }
        }
        return false
    }
    public func Last() -> Bool {
        last()
    }
}
