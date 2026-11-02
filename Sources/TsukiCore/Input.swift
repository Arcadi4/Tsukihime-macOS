import Foundation

/// The PS4 game input word (docs/formats/adv_state.md 10.1).
public struct PadButtons: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let l2 = PadButtons(rawValue: 0x1)
    public static let r2 = PadButtons(rawValue: 0x2)
    public static let l1 = PadButtons(rawValue: 0x4)
    public static let r1 = PadButtons(rawValue: 0x8)
    public static let triangle = PadButtons(rawValue: 0x10)
    /// CIRCLE, or CROSS with the enter-button setting.
    public static let decide = PadButtons(rawValue: 0x20)
    /// The other of CIRCLE and CROSS.
    public static let cancel = PadButtons(rawValue: 0x40)
    public static let square = PadButtons(rawValue: 0x80)
    /// Never set by the pad; actions bound to it are unbound.
    public static let unbound = PadButtons(rawValue: 0x100)
    public static let l3 = PadButtons(rawValue: 0x200)
    public static let r3 = PadButtons(rawValue: 0x400)
    public static let options = PadButtons(rawValue: 0x800)
    public static let up = PadButtons(rawValue: 0x1000)
    public static let right = PadButtons(rawValue: 0x2000)
    public static let down = PadButtons(rawValue: 0x4000)
    public static let left = PadButtons(rawValue: 0x8000)
    public static let stickUp = PadButtons(rawValue: 0x10000)
    public static let stickRight = PadButtons(rawValue: 0x20000)
    public static let stickDown = PadButtons(rawValue: 0x40000)
    public static let stickLeft = PadButtons(rawValue: 0x80000)
    public static let touchPadClick = PadButtons(rawValue: 0x100000)

    public static let dpad: PadButtons = [.up, .right, .down, .left]
    public static let sticks: PadButtons = [.stickUp, .stickRight, .stickDown, .stickLeft]
}

/// Mouse buttons of the pointer (engine.md 8.5).
public struct PointerButtons: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let left = PointerButtons(rawValue: 0x1)
    public static let right = PointerButtons(rawValue: 0x2)
    public static let middle = PointerButtons(rawValue: 0x4)
}

/// Player-shell actions with no PS4 button in preset 0, or keyboard conventions (ARCHITECTURE 9.4).
public struct ShellActions: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let backlog = ShellActions(rawValue: 0x1)
    public static let rewind = ShellActions(rawValue: 0x2)
    public static let fastForward = ShellActions(rawValue: 0x4)
    public static let skipToggle = ShellActions(rawValue: 0x8)
    public static let autoToggle = ShellActions(rawValue: 0x10)
    public static let hideWindow = ShellActions(rawValue: 0x20)
    public static let quickSave = ShellActions(rawValue: 0x40)
    public static let quickLoad = ShellActions(rawValue: 0x80)
    public static let nextScene = ShellActions(rawValue: 0x100)
    public static let previousScene = ShellActions(rawValue: 0x200)
    public static let replayVoice = ShellActions(rawValue: 0x400)
    public static let systemMenu = ShellActions(rawValue: 0x800)
    public static let deleteData = ShellActions(rawValue: 0x1000)
    public static let pageUp = ShellActions(rawValue: 0x2000)
    public static let pageDown = ShellActions(rawValue: 0x4000)
    /// Some keyboard key went down, whatever it is. Not an action: what "PRESS ANY KEY" reads.
    public static let anyKey = ShellActions(rawValue: 0x8000)
}

/// The pointer in the PS4's 640 x 448 logical space (engine.md 8.5).
public struct PointerState: Sendable {
    public var x: Int16
    public var y: Int16
    public var active: Bool
    public var held: PointerButtons
    public var pressed: PointerButtons
    public var wheel: Int
    /// Canvas-pixel coordinates when known more finely than x/y; NaN otherwise.
    public var canvasX: Float
    public var canvasY: Float

    public init(x: Int16 = 0, y: Int16 = 0, active: Bool = false,
                held: PointerButtons = [], pressed: PointerButtons = [], wheel: Int = 0,
                canvasX: Float = .nan, canvasY: Float = .nan) {
        self.x = x
        self.y = y
        self.active = active
        self.held = held
        self.pressed = pressed
        self.wheel = wheel
        self.canvasX = canvasX
        self.canvasY = canvasY
    }
}

/// Input of one 60 Hz logic step. Logic reads input only from here, never from devices or the clock.
public struct InputFrame: Sendable {
    public var frame: Int64
    public var held: PadButtons
    public var pressed: PadButtons
    /// Newly pressed or d-pad auto-repeat (repeat delay and period of engine.md 8.5).
    public var repeated: PadButtons
    public var analogR2: Int16
    public var analogL2: Int16
    public var stickAX: Int16
    public var stickAY: Int16
    public var stickBX: Int16
    public var stickBY: Int16
    public var pointer: PointerState
    public var shellHeld: ShellActions
    public var shellPressed: ShellActions
    /// W/S/A/D direction bits, menus only (aliases of the d-pad there, not in the story).
    public var menuHeld: PadButtons
    public var menuPressed: PadButtons
    public var menuRepeated: PadButtons

    public init(frame: Int64 = 0, held: PadButtons = [], pressed: PadButtons = [],
                repeated: PadButtons = [], analogR2: Int16 = 0, analogL2: Int16 = 0,
                stickAX: Int16 = 0, stickAY: Int16 = 0, stickBX: Int16 = 0, stickBY: Int16 = 0,
                pointer: PointerState = PointerState(), shellHeld: ShellActions = [],
                shellPressed: ShellActions = [], menuHeld: PadButtons = [],
                menuPressed: PadButtons = [], menuRepeated: PadButtons = []) {
        self.frame = frame
        self.held = held
        self.pressed = pressed
        self.repeated = repeated
        self.analogR2 = analogR2
        self.analogL2 = analogL2
        self.stickAX = stickAX
        self.stickAY = stickAY
        self.stickBX = stickBX
        self.stickBY = stickBY
        self.pointer = pointer
        self.shellHeld = shellHeld
        self.shellPressed = shellPressed
        self.menuHeld = menuHeld
        self.menuPressed = menuPressed
        self.menuRepeated = menuRepeated
    }

    /// `held & ~previous`: newly pressed bits.
    public static func edges(previous: PadButtons, held: PadButtons) -> PadButtons {
        PadButtons(rawValue: held.rawValue & ~previous.rawValue)
    }
}
