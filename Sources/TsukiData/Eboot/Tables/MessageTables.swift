import Foundation
import TsukiCore
import TsukiEngine

/// The confirm-dialog and help message ids (knife `ui.rs` `DIALOG_SYSMES`, dword_3C9340): `i32[55]` at text VA 0x2D2D40, -1 = no message.
/// The first 26 are the confirm dialogs (knife's 24 plus two the PS4 inserts after dialog 20); the rest are the ending-list prompts
/// (docs/formats/gallery.md 1, "help messages"). The ids are ui_text ids; knife's SYSMES numbers are the Japanese ones and differ from
/// 217 on by one (`ps4SysmesId`). Port of `tsuki.engine_tables.read_dialog_messages`.
public struct DialogMessageTable: Sendable {
    /// Text VA.
    public static let va: Int = 0x2D2D40

    /// Number of entries.
    public static let count: Int = 55

    /// The overseas SYSMES table has one message more from this number on.
    public static let sysmesOverseasInsert: Int = 217

    /// The ui_text id of each entry, -1 = none.
    public let ids: [Int]

    public init(ids: [Int]) {
        self.ids = ids
    }

    /// Reads the table.
    public static func read(_ reader: EbootReader) throws -> DialogMessageTable {
        DialogMessageTable(ids: try VoiceSpeakerTable.readInts(reader, reader.layout.dialogMessages, count))
    }

    /// knife's (Japanese) SYSMES message number as the PS4 ui_text id.
    public static func ps4SysmesId(_ knifeId: Int) -> Int {
        knifeId >= sysmesOverseasInsert ? knifeId + 1 : knifeId
    }
}

/// The config SE test list (knife `game.rs` `TEST_SES`): 14 inline 13-byte sound effect names at text VA 0x1A6774 (`moon_se02009` ...).
/// Port of `tsuki.engine_tables.read_test_se_names`.
public enum TestSeNames {
    /// Text VA.
    public static let va: Int = 0x1A6774

    /// Number of names.
    public static let count: Int = 14

    /// Reads the names.
    public static func read(_ reader: EbootReader) throws -> [String] {
        var names: [String] = []
        names.reserveCapacity(count)
        for k in 0..<count {
            let record = try reader.read(reader.layout.testSeNames + 13 * k, 13)
            names.append(String(asciiZ: record))
        }

        return names
    }
}

/// An 8-bit RGB colour, the 5 and 6 bit channels of an RGB565 word expanded by bit replication.
public struct TextColour: Equatable, Sendable {
    public let r: UInt8
    public let g: UInt8
    public let b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }
}

/// The message colours of `@c1`..`@c5` (knife `text.rs` `fill_colour`; docs/formats/text.md 6): `u16[6]` RGB565 at text VA 0x2D34C0,
/// word 0 the default colour, words 1..5 the five fill colours. Port of `tsuki.engine_tables.read_text_colours`.
public enum TextColourTable {
    /// Text VA.
    public static let va: Int = 0x2D34C0

    /// Reads the five fill colours as 8-bit (r, g, b), the 5 and 6 bit channels expanded by bit replication.
    public static func read(_ reader: EbootReader) throws -> [TextColour] {
        let raw = try reader.read(reader.layout.textColours, 12)
        var colours: [TextColour] = []
        colours.reserveCapacity(5)
        for k in 0..<5 {
            let w = Int(raw.u16(2 * (k + 1)))
            let r5 = w >> 11, g6 = (w >> 5) & 63, b5 = w & 31
            colours.append(TextColour(
                r: UInt8((r5 << 3) | (r5 >> 2)),
                g: UInt8((g6 << 2) | (g6 >> 4)),
                b: UInt8((b5 << 3) | (b5 >> 2))))
        }

        return colours
    }
}
