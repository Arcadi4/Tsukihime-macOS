import Foundation
import TsukiCore

/// One glyph record of the eboot: `{u16 texture slot, u16 x, u16 y, s16 w, u16 h}`, 10 bytes
/// (docs/formats/fonts.md 5).
public struct GlyphRect: Sendable {
    /// Texture slot (font page = slot - 0x21).
    public let tex: Int
    /// Left edge in the atlas page.
    public let x: Int
    /// Top edge in the atlas page.
    public let y: Int
    /// Width, signed like the engine's s16.
    public let w: Int
    /// Height.
    public let h: Int

    public init(tex: Int, x: Int, y: Int, w: Int, h: Int) {
        self.tex = tex
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

/// A sorted `{u64 key, s16 glyph index, u16 0, u32 0}` lookup table (eboot VA 0x10810): the key is
/// the character's UTF-8 bytes packed big-endian. A found key whose index is negative counts as
/// missing, like the engine (fonts.md 5.1).
public struct GlyphLookupTable: Sendable {
    /// Table name, for example `narrow` or `ja_wide`.
    public let name: String

    private let index: [UInt64: Int16]

    /// Creates a table from its entries.
    /// - Parameters:
    ///   - name: Table name, for example `narrow` or `ja_wide`.
    ///   - keys: The packed UTF-8 keys.
    ///   - indices: The glyph index of each key (same length).
    public init(name: String, keys: [UInt64], indices: [Int16]) {
        precondition(keys.count == indices.count, "keys and indices differ in length")
        self.name = name
        var index: [UInt64: Int16] = [:]
        index.reserveCapacity(keys.count)
        for i in 0..<keys.count {
            index[keys[i]] = indices[i]
        }
        self.index = index
    }

    /// Number of entries.
    public var count: Int { index.count }

    /// Glyph index of `key`, or -1 when the key is missing or its index is negative.
    public func get(_ key: UInt64) -> Int {
        guard let value = index[key], value >= 0 else { return -1 }
        return Int(value)
    }
}

/// An array of 10-byte glyph records the engine indexes without a bounds check. The table holds the
/// bytes from its first record to the end of the executable image segment, so an index past `count`
/// reads the neighbouring data exactly like the game (fonts.md 5.2).
public struct GlyphRecordTable {
    /// Table name, for example `ja_s0`.
    public let name: String

    /// Records that belong to the table.
    public let count: Int

    private let image: ByteSpan

    /// Creates a record table.
    /// - Parameters:
    ///   - name: Table name, for example `ja_s0`.
    ///   - count: Records that belong to the table.
    ///   - image: Bytes from the first record on; at least `10 * count`, longer to cover reads past
    ///     the end.
    public init(name: String, count: Int, image: ByteSpan) {
        precondition(image.count >= 10 * count,
                     "\(name): \(image.count) bytes hold fewer than \(count) records")
        self.name = name
        self.count = count
        self.image = image
    }

    /// True when `index` is inside the table proper.
    public func inRange(_ index: Int) -> Bool {
        index >= 0 && index < count
    }

    /// Reads record `index`, past the end of the table too, as far as the image reaches.
    /// - Throws: ``TsukiError/bounds(_:)`` when the record lies beyond the supplied image bytes.
    public func get(_ index: Int) throws -> GlyphRect {
        let offset = 10 * index
        guard offset >= 0, offset + 10 <= image.count else {
            throw TsukiError.bounds(
                "\(name): record \(index) lies beyond the supplied image bytes (\(image.count))")
        }
        return GlyphRect(
            tex: Int(image.u16(offset)),
            x: Int(image.u16(offset + 2)),
            y: Int(image.u16(offset + 4)),
            w: Int(image.i16(offset + 6)),
            h: Int(image.u16(offset + 8)))
    }

    /// Packs records into the 10-byte form (the tail past the table is left to the caller).
    public static func pack(_ records: [GlyphRect]) -> [UInt8] {
        var writer = ByteWriter(reserving: 10 * records.count)
        for record in records {
            writer.u16(UInt16(truncatingIfNeeded: record.tex))
            writer.u16(UInt16(truncatingIfNeeded: record.x))
            writer.u16(UInt16(truncatingIfNeeded: record.y))
            writer.i16(Int16(truncatingIfNeeded: record.w))
            writer.u16(UInt16(truncatingIfNeeded: record.h))
        }
        return writer.bytes
    }
}

/// All glyph-map data the text layout needs, from eboot.bin (fonts.md 5): the 16 lookup tables, the
/// 17 record tables, the first texture slot of the wide grid per language (the 39 `[tag]` names are
/// constants, ``standardTagNames``).
public final class FontTables {
    /// Number of `[tag]` glyph names (fonts.md 5.5).
    public static let tagCount = 39

    /// The 39 `[tag]` glyph names in table order (VA 0x187C80): seven symbols, `[ber00]`..`[ber30]`
    /// and `[zap00]`. They are constants of this build.
    public static let standardTagNames: [String] =
        ["[heart]", "[heart2]", "[star]", "[star2]", "[edia]", "[dummy]", "[onpu]"]
        + (0..<31).map { "[ber" + String(format: "%02d", $0) + "]" }
        + ["[zap00]"]

    static let standardTagBytes: [[UInt8]] = standardTagNames.map { Array($0.utf8) }

    /// Language names of the table families, by engine language index.
    static let langNames = ["ja", "en", "zc", "zt", "ko"]

    private let lookupTables: [String: GlyphLookupTable]
    private let recordTables: [String: GlyphRecordTable]
    private var perLanguage: [LanguageGlyphs?] = Array(repeating: nil, count: 5)

    /// First texture slot of the wide grid per language (VA 0x187E2E).
    public let wideBase: [Int]

    /// Creates the table set.
    /// - Parameters:
    ///   - lookups: Lookup tables by name (`narrow`, `ja_s1`, `ja_wide`, ...).
    ///   - records: Record tables by name (`ja_s0`, `en_s3`, ...).
    ///   - wideBase: First texture slot of the wide grid for ja, en, zc, zt, ko.
    public init(lookups: [GlyphLookupTable], records: [GlyphRecordTable], wideBase: [Int]) {
        precondition(wideBase.count == 5, "wideBase needs 5 entries")
        var lookupTables: [String: GlyphLookupTable] = [:]
        lookupTables.reserveCapacity(lookups.count)
        for table in lookups {
            precondition(lookupTables[table.name] == nil, "duplicate lookup table \(table.name)")
            lookupTables[table.name] = table
        }
        var recordTables: [String: GlyphRecordTable] = [:]
        recordTables.reserveCapacity(records.count)
        for table in records {
            precondition(recordTables[table.name] == nil, "duplicate record table \(table.name)")
            recordTables[table.name] = table
        }
        self.lookupTables = lookupTables
        self.recordTables = recordTables
        self.wideBase = wideBase
    }

    /// The `[tag]` names as ASCII bytes, in table order.
    var tags: [[UInt8]] { Self.standardTagBytes }

    /// A lookup table by name.
    public func lookup(_ name: String) -> GlyphLookupTable {
        guard let table = lookupTables[name] else {
            preconditionFailure("lookup table \(name)")
        }
        return table
    }

    /// A record table by name.
    public func records(_ name: String) -> GlyphRecordTable {
        guard let table = recordTables[name] else {
            preconditionFailure("record table \(name)")
        }
        return table
    }

    /// The glyph resolver of one language (cached).
    public func `for`(_ language: Language) -> LanguageGlyphs {
        let i = Int(language.rawValue)
        precondition(i >= 0 && i < 5, "language index \(i)")
        if let cached = perLanguage[i] {
            return cached
        }
        let glyphs = LanguageGlyphs(tables: self, language: i)
        perLanguage[i] = glyphs
        return glyphs
    }

    func tryLookup(_ name: String) -> GlyphLookupTable? { lookupTables[name] }

    func tryRecords(_ name: String) -> GlyphRecordTable? { recordTables[name] }
}
