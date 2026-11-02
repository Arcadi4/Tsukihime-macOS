import Foundation

/// The state of the connected gamepads at one instant (merged over all pads).
public struct PadSnapshot: Sendable, Equatable {
    public var south: Bool
    public var east: Bool
    public var west: Bool
    public var north: Bool
    public var leftShoulder: Bool
    public var rightShoulder: Bool
    public var start: Bool
    public var back: Bool
    public var leftStick: Bool
    public var rightStick: Bool
    public var up: Bool
    public var down: Bool
    public var left: Bool
    public var right: Bool
    public var leftTrigger: Int16
    public var rightTrigger: Int16
    public var leftX: Int16
    public var leftY: Int16
    public var rightX: Int16
    public var rightY: Int16

    public init(
        south: Bool = false,
        east: Bool = false,
        west: Bool = false,
        north: Bool = false,
        leftShoulder: Bool = false,
        rightShoulder: Bool = false,
        start: Bool = false,
        back: Bool = false,
        leftStick: Bool = false,
        rightStick: Bool = false,
        up: Bool = false,
        down: Bool = false,
        left: Bool = false,
        right: Bool = false,
        leftTrigger: Int16 = 0,
        rightTrigger: Int16 = 0,
        leftX: Int16 = 0,
        leftY: Int16 = 0,
        rightX: Int16 = 0,
        rightY: Int16 = 0
    ) {
        self.south = south
        self.east = east
        self.west = west
        self.north = north
        self.leftShoulder = leftShoulder
        self.rightShoulder = rightShoulder
        self.start = start
        self.back = back
        self.leftStick = leftStick
        self.rightStick = rightStick
        self.up = up
        self.down = down
        self.left = left
        self.right = right
        self.leftTrigger = leftTrigger
        self.rightTrigger = rightTrigger
        self.leftX = leftX
        self.leftY = leftY
        self.rightX = rightX
        self.rightY = rightY
    }

    /// Combines two snapshots: buttons OR-ed, each axis the one of larger magnitude.
    public func merge(_ o: PadSnapshot) -> PadSnapshot {
        PadSnapshot(
            south: south || o.south,
            east: east || o.east,
            west: west || o.west,
            north: north || o.north,
            leftShoulder: leftShoulder || o.leftShoulder,
            rightShoulder: rightShoulder || o.rightShoulder,
            start: start || o.start,
            back: back || o.back,
            leftStick: leftStick || o.leftStick,
            rightStick: rightStick || o.rightStick,
            up: up || o.up,
            down: down || o.down,
            left: left || o.left,
            right: right || o.right,
            leftTrigger: Self.big(leftTrigger, o.leftTrigger),
            rightTrigger: Self.big(rightTrigger, o.rightTrigger),
            leftX: Self.big(leftX, o.leftX),
            leftY: Self.big(leftY, o.leftY),
            rightX: Self.big(rightX, o.rightX),
            rightY: Self.big(rightY, o.rightY)
        )
    }

    private static func big(_ a: Int16, _ b: Int16) -> Int16 {
        abs(Int(a)) >= abs(Int(b)) ? a : b
    }
}
