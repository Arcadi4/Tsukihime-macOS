import Foundation
import TsukiCore
import TsukiEngine

/// One timed key of a focus-line (`FCLN`) effect; `timeMs` -1 marks an unused key. Positions are in 1280x720 units.
public struct FclnKey: Equatable, Sendable {
    /// Key time in ms, -1 = unused.
    public let timeMs: Int
    /// Centre x.
    public let centreX: Int
    /// Centre y.
    public let centreY: Int
    /// Inner radius of the lines.
    public let radiusMin: Int
    /// Outer radius of the lines.
    public let radiusMax: Int
    /// Fewest lines.
    public let countMin: Int
    /// Most lines.
    public let countMax: Int
    /// 0..255.
    public let alpha: Int
    /// Interval at which the lines are rolled again.
    public let rerollMs: Int

    public init(
        timeMs: Int, centreX: Int, centreY: Int, radiusMin: Int, radiusMax: Int, countMin: Int, countMax: Int, alpha: Int,
        rerollMs: Int
    ) {
        self.timeMs = timeMs
        self.centreX = centreX
        self.centreY = centreY
        self.radiusMin = radiusMin
        self.radiusMax = radiusMax
        self.countMin = countMin
        self.countMax = countMax
        self.alpha = alpha
        self.rerollMs = rerollMs
    }
}

/// The focus-line effects of `_FCLN` (knife `game/focus.rs` `LINES`, dword_35153C): 30 effects x 4 keys x 9 `i32` at text VA 0x216BC0.
/// 118 of the 120 keys equal knife's. Port of `tsuki.engine_tables.read_fcln_lines`.
public struct FclnLineTable: Sendable {
    /// Text VA.
    public static let va: Int = 0x216BC0

    /// Number of effects.
    public static let effects: Int = 30

    /// Keys per effect.
    public static let keysPerEffect: Int = 4

    private let keys: [FclnKey]

    public init(keys: [FclnKey]) {
        self.keys = keys
    }

    /// Reads the table.
    public static func read(_ reader: EbootReader) throws -> FclnLineTable {
        let raw = try reader.read(reader.layout.fclnLines, 36 * effects * keysPerEffect)
        var keys: [FclnKey] = []
        keys.reserveCapacity(effects * keysPerEffect)
        for k in 0..<(effects * keysPerEffect) {
            keys.append(FclnKey(
                timeMs: Int(raw.i32(36 * k)),
                centreX: Int(raw.i32(36 * k + 4)),
                centreY: Int(raw.i32(36 * k + 8)),
                radiusMin: Int(raw.i32(36 * k + 12)),
                radiusMax: Int(raw.i32(36 * k + 16)),
                countMin: Int(raw.i32(36 * k + 20)),
                countMax: Int(raw.i32(36 * k + 24)),
                alpha: Int(raw.i32(36 * k + 28)),
                rerollMs: Int(raw.i32(36 * k + 32))))
        }

        return FclnLineTable(keys: keys)
    }

    /// Key `key` (0..3) of effect `effect` (0..29; effect 0 is FCLN effect 4).
    public func get(effect: Int, key: Int) throws -> FclnKey {
        guard effect >= 0, effect < Self.effects else {
            throw TsukiError.bounds("FCLN effect \(effect) outside 0..<\(Self.effects)")
        }

        guard key >= 0, key < Self.keysPerEffect else {
            throw TsukiError.bounds("FCLN key \(key) outside 0..<\(Self.keysPerEffect)")
        }

        return keys[effect * Self.keysPerEffect + key]
    }
}

/// One falling-note kind of the `FCLN` effects 1..3 (knife `game/focus.rs` `NOTES`, `NOTE_V`, `NOTE_JITTER`, `NOTE_FLOOR`).
public struct FclnNote: Equatable, Sendable {
    /// Image number (57, 58, 59).
    public let image: Int
    /// Animation frames (24, 20, 16).
    public let frames: Int
    /// The frame order of the animation (`frames` entries).
    public let sequence: [Int]
    /// Frame width.
    public let width: Int
    /// Frame height.
    public let height: Int
    /// Ticks per animation frame.
    public let step: Int
    /// Initial x velocity (-0.4).
    public let vx: Float
    /// Initial y velocity (4.0).
    public let vy: Float
    /// Per-frame x jitter (0.005).
    public let jitterX: Float
    /// Per-frame y jitter (0.005).
    public let jitterY: Float
    /// A small term (about 1e-5) that knife does not use.
    public let drift: Float
    /// Acceleration (0.001, 0.0002, 0.0015).
    public let accel: Float
    /// The y at which a note ends (450).
    public let floor: Int

    public init(
        image: Int, frames: Int, sequence: [Int], width: Int, height: Int, step: Int, vx: Float, vy: Float, jitterX: Float,
        jitterY: Float, drift: Float, accel: Float, floor: Int
    ) {
        self.image = image
        self.frames = frames
        self.sequence = sequence
        self.width = width
        self.height = height
        self.step = step
        self.vx = vx
        self.vy = vy
        self.jitterX = jitterX
        self.jitterY = jitterY
        self.drift = drift
        self.accel = accel
        self.floor = floor
    }
}

/// The three falling-note records of `FCLN` effects 1..3: 0x58 bytes each at data VA 0x8734A0. Port of
/// `tsuki.engine_tables.read_fcln_notes`.
public enum FclnNoteTable {
    /// Data VA of the first record.
    public static let va: Int = 0x8734A0

    /// Bytes per record.
    public static let stride: Int = 0x58

    /// Number of records.
    public static let count: Int = 3

    /// Reads the three records.
    public static func read(_ reader: EbootReader) throws -> [FclnNote] {
        var notes: [FclnNote] = []
        notes.reserveCapacity(count)
        for k in 0..<count {
            let b = try reader.read(reader.layout.fclnNotes + stride * k, stride)
            let frames = Int(b.u16(2))
            guard frames >= 1, frames <= 24 else {
                throw TsukiError.format("falling note \(k): \(frames) frames")
            }

            var sequence = [Int](repeating: 0, count: frames)
            for f in 0..<frames {
                sequence[f] = Int(b.i16(4 + 2 * f))
            }

            notes.append(FclnNote(
                image: Int(b.u16(0)),
                frames: frames,
                sequence: sequence,
                width: Int(b.i16(0x36)),
                height: Int(b.i16(0x38)),
                step: Int(b.i16(0x3A)),
                vx: b.f32(0x3C),
                vy: b.f32(0x40),
                jitterX: b.f32(0x44),
                jitterY: b.f32(0x48),
                drift: b.f32(0x4C),
                accel: b.f32(0x50),
                floor: Int(b.i32(0x54))))
        }

        return notes
    }
}
