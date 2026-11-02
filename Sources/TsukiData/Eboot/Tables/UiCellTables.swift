import TsukiCore
import TsukiEngine
import Foundation

/// A cell of a UI sheet in texels, four `i16`: (x0, y0, x1, y1) unless the table says (x, y, w, h).
public struct UiCell: Equatable, Sendable {
    /// First value (x0 or x).
    public let a: Int
    /// Second value (y0 or y).
    public let b: Int
    /// Third value (x1 or w).
    public let c: Int
    /// Fourth value (y1 or h).
    public let d: Int

    public init(_ a: Int, _ b: Int, _ c: Int, _ d: Int) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
    }
}

/// The UI language selection of the cell tables that exist in three variants.
public enum PhaseTitleSet: Int, CaseIterable, Sendable {
    /// Japanese (and the fallback).
    case ja = 0
    /// English.
    case en = 1
    /// Chinese and Korean (the PS4 code uses this set for every language but ja and en).
    case zh = 2
}

/// A banner pop-in scale key (x scale, y scale), sampled over t * 9.
public struct BannerKey: Equatable, Sendable {
    public let x: Float
    public let y: Float

    public init(x: Float, y: Float) {
        self.x = x
        self.y = y
    }
}

/// The UI texture cell tables that knife copies from the Switch executable (`ui.rs`,
/// `flow_table.rs`), found in the PS4 eboot as arrays of four `i16`. Each reader returns the cells of
/// one table; the sheet each belongs to is named in the member's summary. The language rules are
/// those of the PS4 code: savetitle and flow titles use the English table when the language is
/// English (1), phase titles the English table for English, the Japanese one for Japanese (0) and the
/// third table for every other language.
public enum UiCellTables {
    /// Data VAs of the two savetitle tables (38 phases): other languages, English.
    public static let saveTitleVa: [Int] = [0x7A85C0, 0x7A86F0]
    /// Data VAs of the three system_phasetitle tables (38 phases): ja, en, zh.
    public static let phaseTitleVa: [Int] = [0x7A6E70, 0x7A6FA0, 0x7A70D0]
    /// Text VAs of the two flow_phasetitle tables (30 chapter labels, x y w h): other languages, English.
    public static let flowTitleVa: [Int] = [0x1A3EE0, 0x1A3FD0]
    /// Text VA of the 12 flow_line_merge cells (x y w h) by connector kind 0..11.
    public static let flowLineVa: Int = 0x1A40C0
    /// Data VA of the 20 conf_faceicon cells (x0 y0 x1 y1), one per config voice row.
    public static let voiceFaceVa: Int = 0x66E6B0
    /// Data VAs of the 20 conf_name cells: other languages, English.
    public static let voiceNameVa: [Int] = [0x66E750, 0x66E7F0]
    /// Data VA of the 23 help_key icon cells.
    public static let guideIconVa: Int = 0x7A6190
    /// Data VA of the first language block of the help_txt word cells (27 cells per language, 0xD8 bytes).
    public static let guideWordVa: Int = 0x7A6250
    /// Data VAs of the two mode banner cells.
    public static let bannerRectVa: [Int] = [0x781B10, 0x781B20]
    /// Data VA of the 10 banner scale keys (f32 x, f32 y).
    public static let bannerKeyVa: Int = 0x781AC0

    /// Savetitle cells by phase F023 (38), (x0, y0, x1, y1). Phases 16 and 18 of the non-English table
    /// are 571 wide (knife's Japanese table: 560).
    public static func readSaveTitleCells(_ reader: EbootReader, english: Bool) throws -> [UiCell] {
        try readCells(reader, reader.layout.saveTitleCells[english ? 1 : 0], 38)
    }

    /// system_phasetitle cells by phase index (38), (x0, y0, x1, y1).
    public static func readPhaseTitleCells(_ reader: EbootReader, set: PhaseTitleSet) throws -> [UiCell] {
        try readCells(reader, reader.layout.phaseTitleCells[set.rawValue], 38)
    }

    /// Flowchart chapter-label cells (x, y, w, h) by chapter_label index (30). Index 29 is zero in the
    /// PS4 table.
    public static func readFlowTitleCells(_ reader: EbootReader, english: Bool) throws -> [UiCell] {
        try readCells(reader, reader.layout.flowTitleCells[english ? 1 : 0], 30)
    }

    /// Flowchart connector cells (x, y, w, h) by connector kind 0..11 (the grey half; knife's lit half
    /// is not in the PS4 table).
    public static func readFlowLineCells(_ reader: EbootReader) throws -> [UiCell] {
        try readCells(reader, reader.layout.flowLineCells, 12)
    }

    /// conf_faceicon cells per config voice row (20).
    public static func readVoiceFaceCells(_ reader: EbootReader) throws -> [UiCell] {
        try readCells(reader, reader.layout.voiceFaceCells, 20)
    }

    /// conf_name cells per config voice row (20).
    public static func readVoiceNameCells(_ reader: EbootReader, english: Bool) throws -> [UiCell] {
        try readCells(reader, reader.layout.voiceNameCells[english ? 1 : 0], 20)
    }

    /// help_key icon cells (23): 0..6 pad directions, 7 A, 8 Y, 9 X, 10 B ... (knife's order; the PS4
    /// icons differ from index 13).
    public static func readGuideIconCells(_ reader: EbootReader) throws -> [UiCell] {
        try readCells(reader, reader.layout.guideIconCells, 23)
    }

    /// help_txt word cells of one language (0 ja, 1 en, 2 zc, 3 zt, 4 ko): 27 cells (back, select,
    /// move, ... scroll).
    public static func readGuideWordCells(_ reader: EbootReader, language: Int) throws -> [UiCell] {
        guard (0...4).contains(language) else {
            throw TsukiError.bounds("guide word language \(language)")
        }
        return try readCells(reader, reader.layout.guideWordCells + 27 * 8 * language, 27)
    }

    /// The two mode banner cells of the PS4 build (x0, y0, x1, y1).
    public static func readBannerCells(_ reader: EbootReader) throws -> [UiCell] {
        var cells: [UiCell] = []
        cells.reserveCapacity(reader.layout.bannerRects.count)
        for va in reader.layout.bannerRects {
            cells.append(try readCells(reader, va, 1)[0])
        }
        return cells
    }

    /// The banner pop-in scale keys (x scale, y scale), sampled over t * 9.
    public static func readBannerKeys(_ reader: EbootReader) throws -> [BannerKey] {
        let f = try MessageWindowTable.readFloats(reader, reader.layout.bannerKeys, 20)
        return (0..<10).map { BannerKey(x: f[2 * $0], y: f[2 * $0 + 1]) }
    }

    /// Reads `count` cells at a VA.
    public static func readCells(_ reader: EbootReader, _ va: Int, _ count: Int) throws -> [UiCell] {
        let raw = try reader.read(va, 8 * count)
        var cells: [UiCell] = []
        cells.reserveCapacity(count)
        for k in 0..<count {
            let o = 8 * k
            cells.append(UiCell(
                Int(raw.i16(o)), Int(raw.i16(o + 2)), Int(raw.i16(o + 4)), Int(raw.i16(o + 6))))
        }

        return cells
    }
}
