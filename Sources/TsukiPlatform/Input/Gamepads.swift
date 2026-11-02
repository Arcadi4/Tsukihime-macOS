import Foundation
import GameController

/// One open gamepad.
public struct GamepadInfo: Sendable, Equatable {
    public let instanceId: UInt32
    public let name: String
    public let type: String
    public let southLabel: String
    public let eastLabel: String
    public let vendorId: UInt16
    public let productId: UInt16

    public init(
        instanceId: UInt32,
        name: String,
        type: String,
        southLabel: String,
        eastLabel: String,
        vendorId: UInt16 = 0,
        productId: UInt16 = 0
    ) {
        self.instanceId = instanceId
        self.name = name
        self.type = type
        self.southLabel = southLabel
        self.eastLabel = eastLabel
        self.vendorId = vendorId
        self.productId = productId
    }
}

/// The gamepads currently connected, polled via Apple GameController framework.
public final class GamepadSet: @unchecked Sendable {
    public private(set) var activeKind: InputDevice = .xboxPad

    public init() {
        GCController.startWirelessControllerDiscovery()
    }

    public var connected: [GamepadInfo] {
        GCController.controllers().enumerated().map { index, controller in
            let kind = padKind(for: controller)
            let isPs = kind == .playStationPad
            return GamepadInfo(
                instanceId: UInt32(index + 1),
                name: controller.vendorName ?? "Controller",
                type: isPs ? "ps4" : "xboxone",
                southLabel: isPs ? "Cross" : "A",
                eastLabel: isPs ? "Circle" : "B"
            )
        }
    }

    /// Polls connected gamepads and returns the merged snapshot.
    public func poll() -> PadSnapshot {
        var merged = PadSnapshot()
        let controllers = GCController.controllers()

        for controller in controllers {
            guard let pad = controller.extendedGamepad else { continue }

            let south = pad.buttonA.isPressed
            let east = pad.buttonB.isPressed
            let west = pad.buttonX.isPressed
            let north = pad.buttonY.isPressed

            let leftShoulder = pad.leftShoulder.isPressed
            let rightShoulder = pad.rightShoulder.isPressed
            let start = pad.buttonMenu.isPressed
            let back = pad.buttonOptions?.isPressed ?? false

            let leftStick = pad.leftThumbstickButton?.isPressed ?? false
            let rightStick = pad.rightThumbstickButton?.isPressed ?? false

            let up = pad.dpad.up.isPressed
            let down = pad.dpad.down.isPressed
            let left = pad.dpad.left.isPressed
            let right = pad.dpad.right.isPressed

            let leftTrigger = Int16(clamping: Int(pad.leftTrigger.value * 32767.0))
            let rightTrigger = Int16(clamping: Int(pad.rightTrigger.value * 32767.0))

            // Invert Y axis: GameController yAxis is +1 up, but SDL/engine uses negative for up
            let leftX = Int16(clamping: Int(pad.leftThumbstick.xAxis.value * 32767.0))
            let leftY = Int16(clamping: Int(-pad.leftThumbstick.yAxis.value * 32767.0))
            let rightX = Int16(clamping: Int(pad.rightThumbstick.xAxis.value * 32767.0))
            let rightY = Int16(clamping: Int(-pad.rightThumbstick.yAxis.value * 32767.0))

            let snapshot = PadSnapshot(
                south: south,
                east: east,
                west: west,
                north: north,
                leftShoulder: leftShoulder,
                rightShoulder: rightShoulder,
                start: start,
                back: back,
                leftStick: leftStick,
                rightStick: rightStick,
                up: up,
                down: down,
                left: left,
                right: right,
                leftTrigger: leftTrigger,
                rightTrigger: rightTrigger,
                leftX: leftX,
                leftY: leftY,
                rightX: rightX,
                rightY: rightY
            )

            if InputDeviceTracker.hasActivity(pad: snapshot) {
                activeKind = padKind(for: controller)
            }

            merged = merged.merge(snapshot)
        }

        return merged
    }

    private func padKind(for controller: GCController) -> InputDevice {
        let name = (controller.vendorName ?? "").lowercased()
        let category = controller.productCategory.lowercased()
        if name.contains("dualshock") || name.contains("dualsense") || name.contains("playstation") || name.contains("sony") ||
            category.contains("dualshock") || category.contains("dualsense") {
            return .playStationPad
        }
        return .xboxPad
    }
}
