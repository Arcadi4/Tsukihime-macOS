import Foundation
import TsukiCore
import TsukiEngine

/// Where one 16-byte lookup table lives in the analysed eboot (`font_eboot.LOOKUP_SPECS`; docs/formats/fonts.md 5.1).
public struct FontLookupSpec: Equatable, Sendable {
    /// Table name.
    public let name: String
    /// Data VA of the first record.
    public let va: Int
    /// Records (the binary search's high index + 1 in VA 0x10810).
    public let count: Int
    /// Text VA of a `lea r64, [rip+disp32]` that loads the table; 0 for a table located by content.
    public let leaSite: Int

    public init(name: String, va: Int, count: Int, leaSite: Int) {
        self.name = name
        self.va = va
        self.count = count
        self.leaSite = leaSite
    }
}

/// Where one 10-byte glyph record table lives in the analysed eboot (`font_eboot.RECORD_SPECS`; docs/formats/fonts.md 5.2).
public struct FontRecordSpec: Equatable, Sendable {
    /// Table name.
    public let name: String
    /// Text VA of the first record.
    public let va: Int
    /// Records that belong to the table.
    public let count: Int
    /// Text VA of the 7-byte `lea rcx, [rip+disp32]` that loads the table; 0 for a table located by content.
    public let leaSite: Int

    public init(name: String, va: Int, count: Int, leaSite: Int) {
        self.name = name
        self.va = va
        self.count = count
        self.leaSite = leaSite
    }
}

/// A lookup table as stored: `{u64 key, s16 glyph index, u16 0, u32 0}` sorted by key.
public struct FontLookupData: Sendable {
    /// Where it comes from.
    public let spec: FontLookupSpec
    /// The packed UTF-8 keys in table order.
    public let keys: [UInt64]
    /// The glyph index of each key.
    public let indices: [Int16]

    public init(spec: FontLookupSpec, keys: [UInt64], indices: [Int16]) {
        self.spec = spec
        self.keys = keys
        self.indices = indices
    }
}

/// The glyph-map tables in `eboot.bin` (docs/formats/fonts.md 5; a port of `tsuki.font_eboot.EbootFontTables`): 16 sorted lookup
/// arrays (17,423 entries together), 17 arrays of 10-byte glyph records, the first texture slot of the wide grid per language and the 39
/// `[tag]` names. `toEngineTables()` hands them to the text layout; `verify()` is the self-check of RR 3.3 item 2.
public struct EbootFontData {
    /// Text VA of the wide-grid base slots, a u16 per language (ja, en, zc, zt, ko).
    public static let wideBaseVa = 0x187E2E

    /// Text VA of the `lea rdx, [rip+...]` that loads `wideBaseVa`.
    public static let wideBaseSite = 0x111F7

    /// Text VA of the 39 tag names, 11 bytes each.
    public static let tagsVa = 0x187C80

    /// Text VA of the `lea r15, [rip+...]` that loads `tagsVa`.
    public static let tagsSite = 0x117B1

    /// Bytes per tag record.
    public static let tagStride = 11

    /// Number of tags.
    public static let tagCount = 39

    /// The wide-grid base slots of the analysed build.
    public static let expectedWideBase = [59, 59, 59, 57, 59]

    /// The 16 lookup tables. Counts are the immediate high index + 1 from the binary-search setup in VA 0x10810.
    public static let lookupSpecs: [FontLookupSpec] = [
        FontLookupSpec(name: "narrow", va: 0x626C10, count: 109, leaSite: 0x108C8),
        FontLookupSpec(name: "ja_s1", va: 0x6272E0, count: 701, leaSite: 0x10C91),
        FontLookupSpec(name: "en_s1", va: 0x629EB0, count: 111, leaSite: 0x10D9E),
        FontLookupSpec(name: "zc_s1", va: 0x62A5A0, count: 769, leaSite: 0x10CEE),
        FontLookupSpec(name: "zt_s1", va: 0x62D5B0, count: 1631, leaSite: 0x10D49),
        FontLookupSpec(name: "ko_s1", va: 0x633BA0, count: 1, leaSite: 0x10C29),
        FontLookupSpec(name: "ja_s2", va: 0x633BB0, count: 1174, leaSite: 0x10848),
        FontLookupSpec(name: "en_s2", va: 0x638510, count: 82, leaSite: 0x10DFE),
        FontLookupSpec(name: "zc_s2", va: 0x638A30, count: 1434, leaSite: 0x10930),
        FontLookupSpec(name: "zt_s2", va: 0x63E3D0, count: 1631, leaSite: 0x109A1),
        FontLookupSpec(name: "ko_s2", va: 0x6449C0, count: 1, leaSite: 0x10A0C),
        FontLookupSpec(name: "ja_wide", va: 0x6449D0, count: 2795, leaSite: 0x10F7E),
        FontLookupSpec(name: "en_wide", va: 0x64F880, count: 6, leaSite: 0x110F7),
        FontLookupSpec(name: "zc_wide", va: 0x64F8E0, count: 3403, leaSite: 0x10FDE),
        FontLookupSpec(name: "zt_wide", va: 0x65CD90, count: 3570, leaSite: 0x1103E),
        FontLookupSpec(name: "ko_wide", va: 0x66ACB0, count: 5, leaSite: 0x1109E),
    ]

    /// The 17 glyph record tables, selected in `get_glyph` (VA 0x11150).
    public static let recordSpecs: [FontRecordSpec] = [
        FontRecordSpec(name: "ja_s0", va: 0x177370, count: 104, leaSite: 0x1146E),
        FontRecordSpec(name: "ja_s2", va: 0x177780, count: 1174, leaSite: 0x11315),
        FontRecordSpec(name: "ja_s1", va: 0x17A560, count: 701, leaSite: 0x114A3),
        FontRecordSpec(name: "en_s0", va: 0x17C0D0, count: 109, leaSite: 0x11479),
        FontRecordSpec(name: "en_s2", va: 0x17C520, count: 82, leaSite: 0x113B5),
        FontRecordSpec(name: "en_s3", va: 0x17C860, count: 111, leaSite: 0x114CB),
        FontRecordSpec(name: "en_s4", va: 0x17CCC0, count: 111, leaSite: 0x114D6),
        FontRecordSpec(name: "en_s5", va: 0x17D120, count: 111, leaSite: 0x114E1),
        FontRecordSpec(name: "en_s1", va: 0x17D580, count: 111, leaSite: 0x114C0),
        FontRecordSpec(name: "zc_s0", va: 0x17D9E0, count: 109, leaSite: 0x11484),
        FontRecordSpec(name: "zc_s2", va: 0x17DE30, count: 1434, leaSite: 0x113D8),
        FontRecordSpec(name: "zc_s1", va: 0x181640, count: 769, leaSite: 0x114AC),
        FontRecordSpec(name: "zt_s0", va: 0x183450, count: 109, leaSite: 0x1148F),
        FontRecordSpec(name: "zt_s1", va: 0x1838A0, count: 1631, leaSite: 0x113F1),
        FontRecordSpec(name: "ko_s0", va: 0x187860, count: 103, leaSite: 0x1149A),
        FontRecordSpec(name: "ko_s2", va: 0x187C66, count: 1, leaSite: 0x11414),
        FontRecordSpec(name: "ko_s1", va: 0x187C70, count: 1, leaSite: 0x114B5),
    ]

    private let eboot: EbootReader

    /// The lookup tables in `lookupSpecs` order.
    public let lookups: [FontLookupData]

    /// For each record table in `recordSpecs` order: the bytes from its first record to the end of the file-backed text segment, so
    /// that a record index past the table reads the neighbouring data like the engine does (fonts.md 5.2).
    public let recordImages: [ByteSpan]

    /// First texture slot of the wide grid for ja, en, zc, zt, ko.
    public let wideBase: [Int]

    /// The 39 `[tag]` names.
    public let tags: [String]

    /// Total lookup entries: 17,423 in the analysed build.
    public var lookupEntryCount: Int { lookups.reduce(0) { $0 + $1.keys.count } }

    private init(eboot: EbootReader, lookups: [FontLookupData], recordImages: [ByteSpan], wideBase: [Int], tags: [String]) {
        self.eboot = eboot
        self.lookups = lookups
        self.recordImages = recordImages
        self.wideBase = wideBase
        self.tags = tags
    }

    /// Reads every table from a parsed eboot.
    /// - Throws: `TsukiError.format` when a table is not file-backed.
    public static func read(_ eboot: EbootReader) throws -> EbootFontData {
        let layout = eboot.layout

        var lookups: [FontLookupData] = []
        lookups.reserveCapacity(layout.fontLookups.count)
        for spec in layout.fontLookups {
            let raw = try eboot.read(spec.va, 16 * spec.count)
            var keys = [UInt64](repeating: 0, count: spec.count)
            var indices = [Int16](repeating: 0, count: spec.count)
            for i in 0..<spec.count {
                keys[i] = raw.u64(16 * i)
                indices[i] = raw.i16(16 * i + 8)
            }
            lookups.append(FontLookupData(spec: spec, keys: keys, indices: indices))
        }

        var images: [ByteSpan] = []
        images.reserveCapacity(layout.fontRecords.count)
        for spec in layout.fontRecords {
            _ = try eboot.read(spec.va, 10 * spec.count)
            guard eboot.fileOffset(spec.va) != nil else {
                throw TsukiError.format("record table \(spec.name): VA 0x\(String(spec.va, radix: 16)) is not file-backed")
            }
            guard let segment = eboot.segments.first(where: { spec.va >= $0.start && spec.va < $0.end }) else {
                throw TsukiError.format("record table \(spec.name): VA 0x\(String(spec.va, radix: 16)) is not mapped")
            }
            images.append(try eboot.read(spec.va, segment.end - spec.va))
        }

        var wide = [Int](repeating: 0, count: 5)
        let wideRaw = try eboot.read(layout.fontWideBase, 10)
        for i in 0..<5 {
            wide[i] = Int(wideRaw.u16(2 * i))
        }

        var tags = [String](repeating: "", count: tagCount)
        for i in 0..<tagCount {
            let record = try eboot.read(layout.fontTags + tagStride * i, tagStride)
            tags[i] = String(asciiZ: record)
        }

        return EbootFontData(eboot: eboot, lookups: lookups, recordImages: images, wideBase: wide, tags: tags)
    }

    /// The tables in the form the text layout reads (`FontTables`).
    public func toEngineTables() -> FontTables {
        let lookupTables = lookups.map {
            GlyphLookupTable(name: $0.spec.name, keys: $0.keys, indices: $0.indices)
        }
        let recordTables = eboot.layout.fontRecords.enumerated().map {
            GlyphRecordTable(name: $0.element.name, count: $0.element.count, image: recordImages[$0.offset])
        }
        return FontTables(lookups: lookupTables, records: recordTables, wideBase: wideBase)
    }

    /// The self-check of RR 3.3 item 2: the code still loads every table from the expected address, the lookup keys are strictly sorted and their
    /// indices a permutation, the tag names and the wide-grid bases are the documented ones (`EbootFontTables.verify`; fonts.md 10.7).
    /// An empty list means this eboot matches the analysed layout; another build fails loudly instead of rendering junk.
    public func verify() -> [String] {
        var issues: [String] = []
        let layout = eboot.layout
        for (i, spec) in layout.fontLookups.enumerated() {
            checkLea(&issues, "lookup", spec.name, spec.leaSite, spec.va)
            guard i < lookups.count else { continue }
            let data = lookups[i]

            var sorted = true
            if data.keys.count > 1 {
                for k in 1..<data.keys.count where data.keys[k - 1] >= data.keys[k] {
                    sorted = false
                    break
                }
            }
            if !sorted {
                issues.append("lookup \(spec.name): keys not strictly sorted")
            }

            // The Python tool checks the dictionary built from the table: duplicates collapse, so a duplicate key also breaks the permutation.
            var byKey: [UInt64: Int16] = [:]
            byKey.reserveCapacity(data.keys.count)
            for k in 0..<data.keys.count {
                byKey[data.keys[k]] = data.indices[k]
            }
            let values = byKey.values.sorted()
            if values.count != spec.count || values.enumerated().contains(where: { $0.offset != Int($0.element) }) {
                issues.append("lookup \(spec.name): indices are not a permutation of 0..\(spec.count - 1)")
            }
        }

        for spec in layout.fontRecords {
            checkLea(&issues, "records", spec.name, spec.leaSite, spec.va)
        }

        if layout.isAnalysed, ripTarget(Self.wideBaseSite) != Self.wideBaseVa {
            issues.append("wide base table reference moved")
        }

        if layout.isAnalysed, ripTarget(Self.tagsSite) != Self.tagsVa {
            issues.append("tag table reference moved")
        }

        if tags != FontTables.standardTagNames {
            issues.append("tag names differ: (\(tags.map { "'" + $0 + "'" }.joined(separator: ", ")))")
        }

        if wideBase != Self.expectedWideBase {
            issues.append("unexpected wide texture bases (\(wideBase.map(String.init).joined(separator: ", ")))")
        }

        return issues
    }

    // A table located by content (package K25) has no lea site of its own: the locator proved the reference, so there is nothing to check here.
    private func checkLea(_ issues: inout [String], _ kind: String, _ name: String, _ site: Int, _ expected: Int) {
        if site == 0 {
            return
        }

        guard let target = ripTarget(site) else {
            issues.append("\(kind) \(name): lea at 0x\(String(site, radix: 16)) is not file-backed")
            return
        }
        if target != expected {
            issues.append("\(kind) \(name): lea at 0x\(String(site, radix: 16)) -> 0x\(String(target, radix: 16)), expected 0x\(String(expected, radix: 16))")
        }
    }

    /// The target of a 7-byte `lea reg, [rip+disp32]` at a text VA; nil when the site is not readable.
    private func ripTarget(_ insnVa: Int) -> Int? {
        guard let displacement = try? eboot.i32(insnVa + 3) else { return nil }
        return insnVa + 7 + Int(displacement)
    }
}
