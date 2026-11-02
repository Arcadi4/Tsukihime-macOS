import Foundation
import TsukiCore

/// The kind of device the player touched last. The mouse counts as the keyboard.
public enum InputDevice: Sendable, Equatable {
    /// The keyboard or the mouse.
    case keyboard
    /// A PlayStation pad.
    case playStationPad
    /// Any other pad: Xbox pads and other generic pads.
    case xboxPad
}

/// Maps a gamepad type to the prompt family it should show.
public enum PadKinds {
    /// Sony's USB vendor id.
    public static let sonyVendor: UInt16 = 0x054C

    public static func fromType(_ type: String?, vendorId: UInt16 = 0) -> InputDevice {
        let t = (type ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t == "ps3" || t == "ps4" || t == "ps5" || t.contains("playstation") || t.contains("dualsense") || t.contains("dualshock") {
            return .playStationPad
        }
        if (t.isEmpty || t == "unknown" || t == "standard") && vendorId == sonyVendor {
            return .playStationPad
        }
        return .xboxPad
    }
}

/// Follows the last input device.
public final class InputDeviceTracker: @unchecked Sendable {
    public static let stickDeadZone: Int16 = 12000
    public static let triggerDeadZone: Int16 = 8192
    public static let pointerMoveUnits: Int = 2

    private var _keys: KeySet = .none
    private var _padBits: UInt64 = 0
    private var _buttons: PointerButtons = []
    private var _x: Int16 = -1
    private var _y: Int16 = -1

    public private(set) var last: InputDevice = .keyboard

    public init() {}

    public func update(keys: KeySet, pad: PadSnapshot, pointer: PointerSample, padKind: InputDevice) -> InputDevice {
        var keyboard = (keys.bits & ~_keys.bits) != 0
        _keys = keys

        if pointer.inside {
            if pointer.wheel != 0 || !pointer.held.subtracting(_buttons).isEmpty {
                keyboard = true
            }

            if _x >= 0 && (abs(Int(pointer.x - _x)) + abs(Int(pointer.y - _y)) >= Self.pointerMoveUnits) {
                keyboard = true
            }

            _x = pointer.x
            _y = pointer.y
        } else {
            _x = -1
        }

        _buttons = pointer.held
        let bits = Self.activeBits(pad)
        let padUsed = (bits & ~_padBits) != 0
        _padBits = bits

        if padUsed {
            last = padKind == .keyboard ? .xboxPad : padKind
        } else if keyboard {
            last = .keyboard
        }

        return last
    }

    public static func hasActivity(pad: PadSnapshot) -> Bool {
        activeBits(pad) != 0
    }

    public static func activeBits(_ s: PadSnapshot) -> UInt64 {
        var b: UInt64 = 0
        func set(_ on: Bool, _ bit: Int) {
            if on {
                b |= (1 << UInt64(bit))
            }
        }

        set(s.south, 0)
        set(s.east, 1)
        set(s.west, 2)
        set(s.north, 3)
        set(s.leftShoulder, 4)
        set(s.rightShoulder, 5)
        set(s.start, 6)
        set(s.back, 7)
        set(s.leftStick, 8)
        set(s.rightStick, 9)
        set(s.up, 10)
        set(s.down, 11)
        set(s.left, 12)
        set(s.right, 13)
        set(s.leftTrigger >= triggerDeadZone, 14)
        set(s.rightTrigger >= triggerDeadZone, 15)
        set(s.leftX < -stickDeadZone, 16)
        set(s.leftX > stickDeadZone, 17)
        set(s.leftY < -stickDeadZone, 18)
        set(s.leftY > stickDeadZone, 19)
        set(s.rightX < -stickDeadZone, 20)
        set(s.rightX > stickDeadZone, 21)
        set(s.rightY < -stickDeadZone, 22)
        set(s.rightY > stickDeadZone, 23)

        return b
    }
}
