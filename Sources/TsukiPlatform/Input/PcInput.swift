import AppKit
import Foundation
import TsukiCore

/// Produces the InputFrame of each logic step.
public protocol InputSource: AnyObject {
    func sample(frame: Int64) -> InputFrame
    var lastDevice: InputDevice { get }
}

/// Keyboard, mouse and gamepad input of a window.
public final class PcInput: InputSource, @unchecked Sendable {
    public let window: GameWindow
    public var pads: GamepadSet?

    private let mapper = InputMapper()
    private let tracker = InputDeviceTracker()
    private var wheelAccumulator: Int = 0

    public init(window: GameWindow, pads: GamepadSet? = nil) {
        self.window = window
        self.pads = pads
    }

    public var lastDevice: InputDevice {
        tracker.last
    }

    public func addWheel(steps: Int) {
        wheelAccumulator += steps
    }

    public func sample(frame: Int64) -> InputFrame {
        let (keyCodes, modifiers, mouseLoc, buttons, viewWheel, inside) = window.metalView.snapshotInput()
        let keys = classifyKeys(keyCodes: keyCodes, modifiers: modifiers)

        let padSnapshot = pads?.poll() ?? PadSnapshot()
        let pointer = readPointer(mouseLoc: mouseLoc, buttons: buttons, wheel: viewWheel + wheelAccumulator, inside: inside)
        wheelAccumulator = 0

        _ = tracker.update(keys: keys, pad: padSnapshot, pointer: pointer, padKind: pads?.activeKind ?? .xboxPad)
        return mapper.map(frame: frame, keys: keys, pad: padSnapshot, pointer: pointer)
    }

    private func classifyKeys(keyCodes: Set<UInt16>, modifiers: NSEvent.ModifierFlags) -> KeySet {
        // If Command is held, ignore keys (system shortcuts take precedence)
        if modifiers.contains(.command) {
            return .none
        }

        var set = KeySet.none

        for code in keyCodes {
            switch code {
            case 0x24: set = set.with(.enter)
            case 0x4C: set = set.with(.keypadEnter)
            case 0x31: set = set.with(.space)
            case 0x06: set = set.with(.z)
            case 0x07: set = set.with(.x)
            case 0x35: set = set.with(.escape)
            case 0x7E: set = set.with(.up)
            case 0x7D: set = set.with(.down)
            case 0x7B: set = set.with(.left)
            case 0x7C: set = set.with(.right)
            case 0x0C: set = set.with(.q)
            case 0x0E: set = set.with(.e)
            case 0x74: set = set.with(.pageUp)
            case 0x79: set = set.with(.pageDown)
            case 0x75: set = set.with(.delete)
            case 0x33: set = set.with(.backspace)
            case 0x30: set = set.with(.tab)
            case 0x00: set = set.with(.a)
            case 0x04: set = set.with(.h)
            case 0x2E: set = set.with(.m)
            case 0x2D: set = set.with(.n)
            case 0x0B: set = set.with(.b)
            case 0x09: set = set.with(.v)
            case 0x22: set = set.with(.i)
            case 0x60: set = set.with(.f5)
            case 0x65: set = set.with(.f9)
            case 0x0D: set = set.with(.w)
            case 0x01: set = set.with(.s)
            case 0x02: set = set.with(.d)
            default:
                // Exclude screenshot keys F12 (0x6F) from AnyKey
                if code != 0x6F {
                    set = set.with(.other)
                }
            }
        }

        if modifiers.contains(.control) {
            set = set.with(.leftCtrl)
        }

        return set
    }

    private func readPointer(mouseLoc: CGPoint, buttons: UInt8, wheel: Int, inside: Bool) -> PointerSample {
        let (ww, wh) = window.windowSize
        let (pw, ph) = window.pixelSize

        let sx = ww > 0 ? Float(pw) / Float(ww) : 1.0
        let sy = wh > 0 ? Float(ph) / Float(wh) : 1.0

        let view = Viewport.fit(windowWidth: pw, windowHeight: ph)
        let (isInside, px, py) = view.toPointer(x: Float(mouseLoc.x) * sx, y: Float(mouseLoc.y) * sy)
        let (cx, cy) = view.toCanvas(x: Float(mouseLoc.x) * sx, y: Float(mouseLoc.y) * sy)

        let clampedCx = max(0, min(Float(Viewport.canvasWidth) - 0.01, cx))
        let clampedCy = max(0, min(Float(Viewport.canvasHeight) - 0.01, cy))

        let focused = window.nsWindow.isKeyWindow

        var held: PointerButtons = []
        if (buttons & 0x1) != 0 {
            held.insert(.left)
        }
        if (buttons & 0x2) != 0 {
            held.insert(.right)
        }
        if (buttons & 0x4) != 0 {
            held.insert(.middle)
        }

        return PointerSample(
            x: px,
            y: py,
            inside: inside && isInside && focused,
            held: held,
            wheel: wheel,
            canvasX: clampedCx,
            canvasY: clampedCy
        )
    }
}
