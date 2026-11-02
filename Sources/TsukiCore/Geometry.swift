import Foundation

/// A rectangle in integer pixels.
public struct PixelRect: Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let zero = PixelRect(x: 0, y: 0, width: 0, height: 0)

    public func contains(_ px: Int, _ py: Int) -> Bool {
        px >= x && px < x + width && py >= y && py < y + height
    }
}
