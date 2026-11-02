import TsukiCore
import TsukiEngine
import Foundation

/// One message window type: the PS4 image slot and its origin in 1280x720 units.
public struct WindowType: Equatable, Sendable {
    /// PS4 image slot (knife's slot numbers belong to another texture list and differ).
    public let slot: UInt32
    /// Origin x.
    public let x: Float
    /// Origin y.
    public let y: Float

    public init(slot: UInt32, x: Float, y: Float) {
        self.slot = slot
        self.x = x
        self.y = y
    }
}

/// The message window placement tables (knife `game.rs` `WINDOWS` / `EN_WINDOWS`, `WINDOW_DX`,
/// `WINDOW_DY`; docs/formats/textbox.md 7): the 56 window types at text VA 0x2006C0
/// (`{u32 slot; f32 x; f32 y}`; the origins equal knife's overseas table 56 of 56), the x offsets
/// chosen by F1106 (27 floats at 0x2005B0) and the y offsets chosen by F1107 (37 floats at
/// 0x200620).
public struct MessageWindowTable: Sendable {
    /// Text VA of the window types.
    public static let typesVa: Int = 0x2006C0
    /// Number of window types.
    public static let typeCount: Int = 56
    /// Text VA of the x offsets.
    public static let dxVa: Int = 0x2005B0
    /// Number of x offsets.
    public static let dxCount: Int = 27
    /// Text VA of the y offsets.
    public static let dyVa: Int = 0x200620
    /// Number of y offsets.
    public static let dyCount: Int = 37

    /// The window types.
    public let types: [WindowType]
    /// X offsets by F1106.
    public let dx: [Float]
    /// Y offsets by F1107.
    public let dy: [Float]

    public init(types: [WindowType], dx: [Float], dy: [Float]) {
        self.types = types
        self.dx = dx
        self.dy = dy
    }

    /// Reads the three tables.
    public static func read(_ reader: EbootReader) throws -> MessageWindowTable {
        let count = reader.layout.windowTypeCount
        let raw = try reader.read(reader.layout.windowTypes, 12 * count)
        var types: [WindowType] = []
        types.reserveCapacity(count)
        for k in 0..<count {
            let o = 12 * k
            types.append(WindowType(slot: raw.u32(o), x: raw.f32(o + 4), y: raw.f32(o + 8)))
        }

        return MessageWindowTable(
            types: types,
            dx: try readFloats(reader, reader.layout.windowDx, dxCount),
            dy: try readFloats(reader, reader.layout.windowDy, dyCount))
    }

    /// Reads `count` little-endian `f32` values at a VA.
    static func readFloats(_ reader: EbootReader, _ va: Int, _ count: Int) throws -> [Float] {
        let raw = try reader.read(va, 4 * count)
        var values = [Float](repeating: 0, count: count)
        for k in 0..<count {
            values[k] = raw.f32(4 * k)
        }
        return values
    }
}

/// The six soft-clip radii (knife `stage.rs` `RADII`, dword_34D81C): `f32[6]` = 10, 32, 40, 64, 128,
/// 256 at text VA 0x200590, the texel sizes of the `alphagradation` corner textures.
public enum SoftClipRadii {
    /// Text VA.
    public static let va: Int = 0x200590

    /// Reads the six radii.
    public static func read(_ reader: EbootReader) throws -> [Float] {
        try MessageWindowTable.readFloats(reader, reader.layout.clipRadii, 6)
    }
}
