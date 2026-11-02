import TsukiCore
import TsukiEngine
import Foundation

/// One control of a config row: its item id, type code and position in 640x448 units (-9999 where
/// the Sound tab places it at run time).
public struct ConfigControl: Equatable, Sendable {
    /// Item id (grid +0x280).
    public let item: Int
    /// Type code (grid +0x78): 1 test button, 2 check box, 3 / 4 / 5 the left / middle / right control
    /// of a slider row (knife's minus button, slider, plus button [H]), 6..10 radio groups.
    public let kind: Int
    /// Position x (+0x488).
    public let x: Float
    /// Position y.
    public let y: Float

    public init(item: Int, kind: Int, x: Float, y: Float) {
        self.item = item
        self.kind = kind
        self.x = x
        self.y = y
    }
}

/// One config row.
public struct ConfigRow: Equatable, Sendable {
    /// The controls of the row, left to right.
    public let controls: [ConfigControl]
    /// Current value (+0x900).
    public let current: Int
    /// Slider maximum (+0x968).
    public let maximum: Int

    public init(controls: [ConfigControl], current: Int, maximum: Int) {
        self.controls = controls
        self.current = current
        self.maximum = maximum
    }
}

/// One config tab's data-driven page.
public struct ConfigPage: Equatable, Sendable {
    /// First item id.
    public let firstItem: Int
    /// Last item id.
    public let lastItem: Int
    /// The rows.
    public let rows: [ConfigRow]

    public init(firstItem: Int, lastItem: Int, rows: [ConfigRow]) {
        self.firstItem = firstItem
        self.lastItem = lastItem
        self.rows = rows
    }
}

/// The config screen's layout (knife `ui.rs` `conf_layout_at`, dword_46CDB0 + 628 * tab): the PS4
/// keeps two pages of 0x9D0 bytes (628 `i32`) at data VA 0x66E890 (System tab, Sound tab) with the
/// item and type grids, the control positions (the floats knife inlines), current values and slider
/// maxima (docs/formats/adv_state.md 9.1).
public enum ConfigPageTable {
    /// Data VA of page 0.
    public static let va: Int = 0x66E890
    /// Bytes per page.
    public static let stride: Int = 0x9D0
    /// Number of pages with content.
    public static let pageCount: Int = 2
    /// The x/y value of a control that is placed at run time.
    public static let unusedPosition: Float = -9999

    private static let rowLimit = 26

    /// Reads the two pages.
    public static func read(_ reader: EbootReader) throws -> [ConfigPage] {
        var pages: [ConfigPage] = []
        pages.reserveCapacity(pageCount)
        for page in 0..<pageCount {
            let b = try reader.read(reader.layout.configPages + stride * page, stride)
            let first = Int(b.i32(0))
            let last = Int(b.i32(4))
            let rowCount = Int(b.i32(12))
            guard (0...rowLimit).contains(rowCount) else {
                throw TsukiError.format("config page \(page): \(rowCount) rows")
            }

            var rows: [ConfigRow] = []
            rows.reserveCapacity(rowCount)
            for r in 0..<rowCount {
                let k = Int(b.i32(0x10 + 4 * r))
                guard (0...5).contains(k) else {
                    throw TsukiError.format("config page \(page) row \(r): \(k) controls")
                }

                var controls: [ConfigControl] = []
                controls.reserveCapacity(k)
                for c in 0..<k {
                    controls.append(ConfigControl(
                        item: Int(b.i32(0x280 + 20 * r + 4 * c)),
                        kind: Int(b.i32(0x78 + 20 * r + 4 * c)),
                        x: b.f32(0x488 + 40 * r + 8 * c),
                        y: b.f32(0x488 + 40 * r + 8 * c + 4)))
                }

                rows.append(ConfigRow(
                    controls: controls,
                    current: Int(b.i32(0x900 + 4 * r)),
                    maximum: Int(b.i32(0x968 + 4 * r))))
            }

            pages.append(ConfigPage(firstItem: first, lastItem: last, rows: rows))
        }

        return pages
    }
}

/// The STMA field-enable masks (knife `exe.rs` `motion_masks`): `u64[24193]` at text VA 0x245130,
/// indexed by motion id (entry 0 unused; the engine's accessor at 0xC1C40 returns 0 outside
/// 1..24192). The Python side reads the same table in
/// `misc_layer_state_and_motions.MotionTable`.
public struct MotionFieldMasks: Sendable {
    /// Text VA.
    public static let va: Int = 0x245130
    /// Number of entries.
    public static let count: Int = 24193

    /// The mask of every motion id (index = id).
    public let masks: [UInt64]

    public init(masks: [UInt64]) {
        self.masks = masks
    }

    /// Reads the table.
    public static func read(_ reader: EbootReader) throws -> MotionFieldMasks {
        let count = reader.layout.motionCount + 1
        let raw = try reader.read(reader.layout.motionMasks, 8 * count)
        var masks = [UInt64](repeating: 0, count: count)
        for k in 0..<count {
            masks[k] = raw.u64(8 * k)
        }

        return MotionFieldMasks(masks: masks)
    }

    /// The mask of a motion id; 0 for ids outside 1..24192.
    public func mask(of motionId: Int) -> UInt64 {
        motionId >= 1 && motionId < masks.count ? masks[motionId] : 0
    }
}
