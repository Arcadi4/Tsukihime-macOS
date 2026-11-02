import Foundation
import TsukiCore

/// The keyboard keys the game binds.
public enum PcKey: Int, Sendable, CaseIterable {
    case enter
    case keypadEnter
    case space
    case z
    case x
    case escape
    case up
    case down
    case left
    case right
    case q
    case e
    case pageUp
    case pageDown
    case delete
    case backspace
    case leftCtrl
    case rightCtrl
    case tab
    case a
    case h
    case m
    case n
    case b
    case v
    case i
    case f5
    case f9
    case w
    case s
    case d
    case other
}

/// A set of held keys.
public struct KeySet: Sendable, Equatable {
    public let bits: UInt64

    public init(bits: UInt64 = 0) {
        self.bits = bits
    }

    public static let none = KeySet(bits: 0)

    public static func of(_ keys: PcKey...) -> KeySet {
        var b: UInt64 = 0
        for k in keys {
            b |= (1 << UInt64(k.rawValue))
        }
        return KeySet(bits: b)
    }

    public func has(_ key: PcKey) -> Bool {
        (bits & (1 << UInt64(key.rawValue))) != 0
    }

    public func with(_ key: PcKey) -> KeySet {
        KeySet(bits: bits | (1 << UInt64(key.rawValue)))
    }
}

/// The pointer of one step in the PS4 pointer space of 640 x 448 units.
public struct PointerSample: Sendable, Equatable {
    public let x: Int16
    public let y: Int16
    public let inside: Bool
    public let held: PointerButtons
    public let wheel: Int
    public let canvasX: Float
    public let canvasY: Float

    public init(
        x: Int16,
        y: Int16,
        inside: Bool,
        held: PointerButtons,
        wheel: Int,
        canvasX: Float = .nan,
        canvasY: Float = .nan
    ) {
        self.x = x
        self.y = y
        self.inside = inside
        self.held = held
        self.wheel = wheel
        self.canvasX = canvasX
        self.canvasY = canvasY
    }
}

/// One documented binding.
public struct Binding: Sendable, Equatable {
    public let input: String
    public let action: String

    public init(input: String, action: String) {
        self.input = input
        self.action = action
    }
}

/// The input mapping onto the PS4 input word.
public final class InputMapper: @unchecked Sendable {
    public static let repeatDelay = 24
    public static let repeatPeriod = 6

    private static let stickThreshold: Int16 = 80
    private static let triggerOn: Int16 = 8192

    private var hold: [Int] = [0, 0, 0, 0]
    private var menuHold: [Int] = [0, 0, 0, 0]
    private var previous: PadButtons = []
    private var previousMenu: PadButtons = []
    private var previousShell: ShellActions = []
    private var previousPointer: PointerButtons = []

    public static let bindings: [Binding] = [
        Binding(input: "Enter / Space / Z / left click", action: "advance the text, decide in menus"),
        Binding(input: "Esc / right click", action: "system menu in the story; back in menus"),
        Binding(input: "X", action: "back in menus; hide or show the message window in the story"),
        Binding(input: "Arrow keys", action: "move the cursor; Up opens the mode panel in the story"),
        Binding(input: "W / A / S / D", action: "move the cursor in the menus"),
        Binding(input: "Q / E", action: "previous / next tab or page in menus"),
        Binding(input: "Ctrl (held)", action: "fast-forward"),
        Binding(input: "Tab / middle click", action: "toggle latched skip"),
        Binding(input: "A", action: "toggle auto mode"),
        Binding(input: "H", action: "hide or show the message window"),
        Binding(input: "Mouse wheel up / Page Up / I", action: "backlog (in the story)"),
        Binding(input: "Mouse wheel / Page Up / Page Down", action: "scroll lists and pages in menus"),
        Binding(input: "Backspace (held)", action: "rewind (back in menus)"),
        Binding(input: "F5 / F9", action: "quick save / quick load"),
        Binding(input: "N / B", action: "next / previous scene"),
        Binding(input: "V", action: "replay the voice"),
        Binding(input: "M", action: "system menu"),
        Binding(input: "Delete", action: "delete the slot under the cursor in the save list"),
        Binding(input: "Gamepad", action: "south = decide, east = cancel, west = system menu, north = backlog, shoulders = auto / skip, triggers = rewind / fast-forward, start = quick save"),
    ]

    public init() {}

    public func map(frame: Int64, keys: KeySet, pad: PadSnapshot, pointer: PointerSample) -> InputFrame {
        var held: PadButtons = []

        if keys.has(.enter) || keys.has(.keypadEnter) || keys.has(.space) || keys.has(.z) || pad.south {
            held.insert(.decide)
        }
        if keys.has(.escape) || keys.has(.x) || pad.east {
            held.insert(.cancel)
        }
        if keys.has(.up) || pad.up {
            held.insert(.up)
        }
        if keys.has(.down) || pad.down {
            held.insert(.down)
        }
        if keys.has(.left) || pad.left {
            held.insert(.left)
        }
        if keys.has(.right) || pad.right {
            held.insert(.right)
        }
        if keys.has(.q) || pad.leftShoulder {
            held.insert(.l1)
        }
        if keys.has(.e) || pad.rightShoulder {
            held.insert(.r1)
        }
        if keys.has(.backspace) || pad.leftTrigger >= Self.triggerOn {
            held.insert(.l2)
        }
        if pad.rightTrigger >= Self.triggerOn {
            held.insert(.r2)
        }
        if pad.north {
            held.insert(.triangle)
        }
        if keys.has(.m) || pad.west {
            held.insert(.square)
        }
        if pad.start {
            held.insert(.options)
        }
        if pad.leftStick {
            held.insert(.l3)
        }
        if pad.rightStick {
            held.insert(.r3)
        }
        if pad.back {
            held.insert(.touchPadClick)
        }

        let ax = Int16(pad.leftX >> 8)
        let ay = Int16(pad.leftY >> 8)
        if ay < -Self.stickThreshold {
            held.insert(.stickUp)
        }
        if ay > Self.stickThreshold {
            held.insert(.stickDown)
        }
        if ax < -Self.stickThreshold {
            held.insert(.stickLeft)
        }
        if ax > Self.stickThreshold {
            held.insert(.stickRight)
        }

        let pressed = held.subtracting(previous)
        var repeated = pressed

        let dirs: [PadButtons] = [
            [.up, .stickUp],
            [.down, .stickDown],
            [.left, .stickLeft],
            [.right, .stickRight],
        ]

        for i in 0..<dirs.count {
            if held.intersection(dirs[i]).isEmpty {
                hold[i] = 0
                continue
            }

            hold[i] += 1
            if hold[i] > Self.repeatDelay && (hold[i] - Self.repeatDelay) % Self.repeatPeriod == 0 {
                repeated.formUnion(held.intersection(dirs[i]))
            }
        }

        // Menu arrow aliases: W/S/A/D
        var menuHeld: PadButtons = []
        if keys.has(.w) { menuHeld.insert(.up) }
        if keys.has(.s) { menuHeld.insert(.down) }
        if keys.has(.a) { menuHeld.insert(.left) }
        if keys.has(.d) { menuHeld.insert(.right) }

        let menuPressed = menuHeld.subtracting(previousMenu)
        var menuRepeated = menuPressed

        let menuDirs: [PadButtons] = [.up, .down, .left, .right]
        for i in 0..<menuDirs.count {
            let bit = menuDirs[i]
            if !menuHeld.contains(bit) {
                menuHold[i] = 0
                continue
            }

            menuHold[i] += 1
            if menuHold[i] > Self.repeatDelay && (menuHold[i] - Self.repeatDelay) % Self.repeatPeriod == 0 {
                menuRepeated.insert(bit)
            }
        }

        previousMenu = menuHeld

        var shellHeld: ShellActions = []
        if keys.has(.pageUp) || keys.has(.i) || pointer.wheel > 0 { shellHeld.insert(.backlog) }
        if keys.has(.backspace) { shellHeld.insert(.rewind) }
        if keys.has(.leftCtrl) || keys.has(.rightCtrl) || pad.rightTrigger >= Self.triggerOn { shellHeld.insert(.fastForward) }
        if keys.has(.tab) || pointer.held.contains(.middle) { shellHeld.insert(.skipToggle) }
        if keys.has(.a) { shellHeld.insert(.autoToggle) }
        if keys.has(.h) { shellHeld.insert(.hideWindow) }
        if keys.has(.f5) || pad.start { shellHeld.insert(.quickSave) }
        if keys.has(.f9) { shellHeld.insert(.quickLoad) }
        if keys.has(.n) { shellHeld.insert(.nextScene) }
        if keys.has(.b) { shellHeld.insert(.previousScene) }
        if keys.has(.v) { shellHeld.insert(.replayVoice) }
        if keys.has(.escape) || keys.has(.m) || pad.west { shellHeld.insert(.systemMenu) }
        if keys.has(.delete) { shellHeld.insert(.deleteData) }
        if keys.has(.pageUp) { shellHeld.insert(.pageUp) }
        if keys.has(.pageDown) { shellHeld.insert(.pageDown) }
        if keys.has(.other) { shellHeld.insert(.anyKey) }

        let shellPressed = shellHeld.subtracting(previousShell)
        let pointerPressed = pointer.held.subtracting(previousPointer)

        previous = held
        previousShell = shellHeld
        previousPointer = pointer.held

        let analogR2: Int16 = pad.rightTrigger >= Self.triggerOn ? (pad.rightTrigger >> 7) : 0
        let analogL2: Int16 = pad.leftTrigger >= Self.triggerOn ? (pad.leftTrigger >> 7) : 0
        let stickBX = Int16(pad.rightX >> 8)
        let stickBY = Int16(pad.rightY >> 8)

        let pointerState = PointerState(
            x: pointer.x,
            y: pointer.y,
            active: pointer.inside,
            held: pointer.held,
            pressed: pointerPressed,
            wheel: pointer.wheel,
            canvasX: pointer.canvasX,
            canvasY: pointer.canvasY
        )

        return InputFrame(
            frame: frame,
            held: held,
            pressed: pressed,
            repeated: repeated,
            analogR2: analogR2,
            analogL2: analogL2,
            stickAX: ax,
            stickAY: ay,
            stickBX: stickBX,
            stickBY: stickBY,
            pointer: pointerState,
            shellHeld: shellHeld,
            shellPressed: shellPressed,
            menuHeld: menuHeld,
            menuPressed: menuPressed,
            menuRepeated: menuRepeated
        )
    }
}
