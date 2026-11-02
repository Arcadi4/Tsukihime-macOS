import Foundation
import TsukiCore

/// The input of one 60 Hz UI step in the terms the menus use (docs/formats/adv_state.md 10; knife `ui/pad.rs`): PS4 pad actions, the pointer in canvas pixels,
/// and the wheel. Keyboard and mouse reach the UI as `InputFrame` bits (Tsuki.Platform maps them), so there is one path.
public struct UiInput: Sendable {
    /// The 60 Hz frame counter.
    public var frame: Int64 = 0
    public var Frame: Int64 { frame }

    /// Decide was newly pressed, or the left button clicked: confirm the item under the cursor.
    public var decide: Bool = false
    public var Decide: Bool { decide }

    /// Cancel was newly pressed, or the right button clicked: go back.
    public var cancel: Bool = false
    public var Cancel: Bool { cancel }

    /// The left button was newly pressed (a click on whatever is under the pointer).
    public var click: Bool = false
    public var Click: Bool { click }

    /// The right button was newly pressed.
    public var rightClick: Bool = false
    public var RightClick: Bool { rightClick }

    /// The left button was held in the previous step and is up now (package K12: a click that was not a drag acts on release in the screens that also drag).
    public var pointerReleased: Bool = false
    public var PointerReleased: Bool { pointerReleased }

    /// Up was pressed or auto-repeated (d-pad or left stick).
    public var up: Bool = false
    public var Up: Bool { up }

    /// Down was pressed or auto-repeated.
    public var down: Bool = false
    public var Down: Bool { down }

    /// Left was pressed or auto-repeated.
    public var left: Bool = false
    public var Left: Bool { left }

    /// Right was pressed or auto-repeated.
    public var right: Bool = false
    public var Right: Bool { right }

    /// Up was newly pressed (not a repeat).
    public var upPressed: Bool = false
    public var UpPressed: Bool { upPressed }

    /// Down was newly pressed (not a repeat).
    public var downPressed: Bool = false
    public var DownPressed: Bool { downPressed }

    /// Left was newly pressed (not a repeat).
    public var leftPressed: Bool = false
    public var LeftPressed: Bool { leftPressed }

    /// Right was newly pressed (not a repeat).
    public var rightPressed: Bool = false
    public var RightPressed: Bool { rightPressed }

    /// Decide is held (a held decide with left / right drags a config slider).
    public var decideHeld: Bool = false
    public var DecideHeld: Bool { decideHeld }

    /// The left button is held over the screen.
    public var pointerHeld: Bool = false
    public var PointerHeld: Bool { pointerHeld }

    /// L1 was newly pressed (previous page / tab).
    public var l1: Bool = false
    public var L1: Bool { l1 }

    /// R1 was newly pressed (next page / tab).
    public var r1: Bool = false
    public var R1: Bool { r1 }

    /// L2 was newly pressed.
    public var l2: Bool = false
    public var L2: Bool { l2 }

    /// R2 was newly pressed.
    public var r2: Bool = false
    public var R2: Bool { r2 }

    /// TRIANGLE (the north button) was newly pressed: the backlog button (knife X; the config controls picture says Log = TRIANGLE) and the save list's delete.
    public var triangle: Bool = false
    public var Triangle: Bool { triangle }

    /// SQUARE (the west button) was newly pressed: the system menu button (knife Y; the config controls picture says System Menu = SQUARE).
    public var square: Bool = false
    public var Square: Bool { square }

    /// OPTIONS was newly pressed.
    public var options: Bool = false
    public var Options: Bool { options }

    /// Any pad button or a click was newly pressed (PRESS ANY BUTTON, notices).
    public var any: Bool = false
    public var `Any`: Bool { any }

    /// The pointer is inside the game area.
    public var pointerActive: Bool = false
    public var PointerActive: Bool { pointerActive }

    /// The pointer x in canvas pixels (to the pixel when the source reports it, else the centre of its 640 x 448 unit).
    public var pointerX: Float = 0
    public var PointerX: Float { pointerX }

    /// The pointer y in canvas pixels.
    public var pointerY: Float = 0
    public var PointerY: Float { pointerY }

    /// The pointer moved since the previous step (hover takes the cursor only then).
    public var pointerMoved: Bool = false
    public var PointerMoved: Bool { pointerMoved }

    /// The middle button was newly pressed.
    public var middleClick: Bool = false
    public var MiddleClick: Bool { middleClick }

    /// The wheel steps this frame, positive = up (away from the user). Page Up and Page Down add `pageSteps` steps up or down, so every list that
    /// scrolls with the wheel scrolls a page with them (package K9).
    public var wheel: Int = 0
    public var Wheel: Int { wheel }

    /// The wheel steps a Page Up or Page Down press stands for.
    public static let pageSteps: Int = 5
    public static let PageSteps: Int = pageSteps

    /// Delete was newly pressed: delete the data under the cursor (the pad's TRIANGLE does the same in the save list, as its guide says).
    public var deleteData: Bool = false
    public var DeleteData: Bool { deleteData }

    /// The raw held buttons.
    public var held: PadButtons = []
    public var Held: PadButtons { held }

    /// The raw newly pressed buttons.
    public var pressed: PadButtons = []
    public var Pressed: PadButtons { pressed }

    /// The shell actions newly pressed (backlog, quick save, ...).
    public var shell: ShellActions = []
    public var Shell: ShellActions { shell }

    public init() {}
    public static let empty = UiInput()
    public static let Empty = empty

    /// True when the pointer is over `r` (canvas pixels).
    public func over(_ r: RectF) -> Bool {
        pointerActive && r.contains(pointerX, pointerY)
    }
    public func Over(_ r: RectF) -> Bool {
        over(r)
    }

    /// Builds the UI input from an engine input frame. `previous` is the pointer of the previous step (for `pointerMoved`).
    public static func from(_ f: InputFrame, previous: PointerState) -> UiInput {
        let upBits: PadButtons = [.up, .stickUp]
        let downBits: PadButtons = [.down, .stickDown]
        let leftBits: PadButtons = [.left, .stickLeft]
        let rightBits: PadButtons = [.right, .stickRight]

        let rep = f.repeated.union(f.pressed).union(f.menuRepeated).union(f.menuPressed)
        let newly = f.pressed.union(f.menuPressed)
        let p = f.pointer
        let click = p.pressed.contains(.left)
        let rclick = p.pressed.contains(.right)
        var wheel = p.wheel
        let released = previous.held.contains(.left) && !p.held.contains(.left)

        let px: Float = p.canvasX.isNaN ? (Float(p.x) + 0.5) * UiMetrics.unitX : p.canvasX
        let py: Float = p.canvasY.isNaN ? (Float(p.y) + 0.5) * UiMetrics.unitY : p.canvasY

        let moved = p.active && (p.x != previous.x || p.y != previous.y
            || (!p.canvasX.isNaN && !previous.canvasX.isNaN && (abs(p.canvasX - previous.canvasX) >= 1.0 || abs(p.canvasY - previous.canvasY) >= 1.0)))

        if f.shellPressed.contains(.pageUp) {
            wheel += pageSteps
        }
        if f.shellPressed.contains(.pageDown) {
            wheel -= pageSteps
        }

        let anyPad: PadButtons = [
            .decide, .cancel, .triangle, .square, .l1, .r1, .l2, .r2, .options,
            .up, .stickUp, .down, .stickDown, .left, .stickLeft, .right, .stickRight
        ]

        var input = UiInput()
        input.frame = f.frame
        input.decide = !f.pressed.intersection([.decide]).isEmpty || click
        input.cancel = !f.pressed.intersection([.cancel]).isEmpty || rclick
        input.click = click
        input.rightClick = rclick
        input.pointerReleased = released
        input.up = !rep.intersection(upBits).isEmpty
        input.down = !rep.intersection(downBits).isEmpty
        input.left = !rep.intersection(leftBits).isEmpty
        input.right = !rep.intersection(rightBits).isEmpty
        input.upPressed = !newly.intersection(upBits).isEmpty
        input.downPressed = !newly.intersection(downBits).isEmpty
        input.leftPressed = !newly.intersection(leftBits).isEmpty
        input.rightPressed = !newly.intersection(rightBits).isEmpty
        input.decideHeld = !f.held.intersection([.decide]).isEmpty
        input.pointerHeld = p.held.contains(.left)
        input.l1 = !f.pressed.intersection([.l1]).isEmpty
        input.r1 = !f.pressed.intersection([.r1]).isEmpty
        input.l2 = !f.pressed.intersection([.l2]).isEmpty
        input.r2 = !f.pressed.intersection([.r2]).isEmpty
        input.triangle = !f.pressed.intersection([.triangle]).isEmpty
        input.square = !f.pressed.intersection([.square]).isEmpty
        input.options = !f.pressed.intersection([.options]).isEmpty
        input.any = !newly.intersection(anyPad).isEmpty || click || rclick || f.shellPressed.rawValue != 0
        input.pointerActive = p.active
        input.pointerX = px
        input.pointerY = py
        input.pointerMoved = moved
        input.middleClick = p.pressed.contains(.middle)
        input.wheel = wheel
        input.deleteData = f.shellPressed.contains(.deleteData)
        input.held = f.held
        input.pressed = f.pressed
        input.shell = f.shellPressed
        return input
    }
    public static func From(_ f: InputFrame, _ previous: PointerState) -> UiInput {
        from(f, previous: previous)
    }

    /// An input frame with the pointer at canvas pixel (x, y), for tests and the preview tool.
    public static func pointerAt(_ x: Float, _ y: Float, click: Bool = false, frame: Int64 = 0) -> InputFrame {
        pointerFrame(x: x, y: y, held: click ? .left : [], pressed: click ? .left : [], wheel: 0, frame: frame)
    }
    public static func PointerAt(_ x: Float, _ y: Float, _ click: Bool = false, _ frame: Int64 = 0) -> InputFrame {
        pointerAt(x, y, click: click, frame: frame)
    }

    /// An input frame with the pointer at canvas pixel (x, y), kept to the pixel, the given buttons held and newly pressed, and
    /// `wheel` wheel steps (tests and the preview tool).
    public static func pointerFrame(x: Float, y: Float, held: PointerButtons, pressed: PointerButtons, wheel: Int = 0, frame: Int64 = 0) -> InputFrame {
        let ux = Int16(clamping: Int(x / UiMetrics.unitX).clamped(to: 0...639))
        let uy = Int16(clamping: Int(y / UiMetrics.unitY).clamped(to: 0...447))
        var f = InputFrame(frame: frame)
        f.pointer = PointerState(
            x: ux, y: uy, active: true,
            held: held, pressed: pressed, wheel: wheel,
            canvasX: x, canvasY: y
        )
        return f
    }
    public static func PointerFrame(_ x: Float, _ y: Float, _ held: PointerButtons, _ pressed: PointerButtons, _ wheel: Int = 0, _ frame: Int64 = 0) -> InputFrame {
        pointerFrame(x: x, y: y, held: held, pressed: pressed, wheel: wheel, frame: frame)
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
