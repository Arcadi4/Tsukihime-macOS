import Foundation
import TsukiCore
import TsukiEngine

/// One UI texture registration record (0x18 bytes; docs/formats/archives_ui_movies.md 7.3): which child of which
/// allpac3 archive goes into which engine texture slot.
public struct UiTexRecord: Sendable {
    /// VA of the record.
    public let va: Int
    /// +0x00, 0 in the file.
    public let state: Int
    /// +0x04, the engine texture slot; a negative slot ends the table.
    public let texSlot: Int
    /// +0x08, the base name such as `conf_parts.mrg`; the localising loader inserts `_<lang>`.
    public let name: String
    /// +0x10, the section index inside the archive (clamped to the last child by VA 0xEB350).
    public let child: Int
    /// +0x14, -1 in every live record.
    public let child2: Int

    public init(va: Int, state: Int, texSlot: Int, name: String, child: Int, child2: Int) {
        self.va = va
        self.state = state
        self.texSlot = texSlot
        self.name = name
        self.child = child
        self.child2 = child2
    }
}

/// A header-less array of `UiTexRecord` and the record that ended it.
public struct UiTexTable: Sendable {
    /// VA of the first record.
    public let va: Int
    /// The records before the terminator.
    public let records: [UiTexRecord]
    /// The 24 bytes of the terminating record.
    public let terminator: [UInt8]

    public init(va: Int, records: [UiTexRecord], terminator: [UInt8]) {
        self.va = va
        self.records = records
        self.terminator = terminator
    }
}

/// The UI texture registration tables of eboot.bin (21 tables, 220 records) and the engine rules that turn their names
/// into allpac3 archives. A port of `tsuki.catalog_eboot.Eboot.ui_table(s)` and the loaders of `tsuki.catalog`
/// (`localize_parts_name`, `ui_child_index`, `lang_index_from_system`).
public enum UiTextureTables {
    /// The asset language suffixes in engine order.
    public static let languages = ["ja", "en", "zc", "zt", "ko"]

    /// Reads the table at `va` up to its terminator (a negative slot or a name pointer outside the text segment).
    public static func read(_ eb: EbootReader, _ va: Int) throws -> UiTexTable {
        var records: [UiTexRecord] = []
        var k = 0
        while true {
            let recordVa = va + EbootAddresses.uiRecordSize * k
            let head = try eb.read(recordVa, EbootAddresses.uiRecordSize)
            let state = Int(head.i32(0))
            let texSlot = Int(head.i32(4))
            let pointer = head.u64(8)
            if texSlot < 0 || !eb.isTextPointer(Int(pointer)) {
                return UiTexTable(va: va, records: records, terminator: head.toArray())
            }

            records.append(UiTexRecord(va: recordVa, state: state, texSlot: texSlot,
                                       name: eb.cString(Int(pointer), limit: 64),
                                       child: Int(head.i32(16)), child2: Int(head.i32(20))))
            k += 1
        }
    }

    /// All 21 tables, in the order of `EbootAddresses.uiTables`.
    public static func readAll(_ eb: EbootReader) throws -> [UiTexTable] {
        try eb.layout.uiTables.map { try read(eb, $0) }
    }

    /// PS4 system language to asset language (VA 0x3ED90 / 0x407F0): 0 (Japanese) is ja, 11 (Simplified Chinese) zc, 10
    /// (Traditional Chinese) zt, anything else en. The in-game option overrides this when it is below 4; 4 (ko) is never selected.
    public static func langIndexFromSystem(_ systemLanguage: Int) -> Int {
        switch systemLanguage {
        case 0: return 0
        case 11: return 2
        case 10: return 3
        default: return 1
        }
    }

    /// The UI loader's name rule (VA 0xC2AF0): strip a trailing `.mrg` or `.MRG` (only if the name has at least 5
    /// characters) and append `_<suffix>.mrg`. A `lang` outside 0..4 is replaced by the language of
    /// `systemLanguage` (default 1 = English), as VA 0xC2C56 does.
    public static func localizePartsName(_ name: String, lang: Int, systemLanguage: Int = 1) -> String {
        var language = lang
        if language < 0 || language >= 5 {
            language = langIndexFromSystem(systemLanguage)
        }

        let hasExtension = name.count >= 5 && (name.hasSuffix(".mrg") || name.hasSuffix(".MRG"))
        let stem = hasExtension ? String(name.dropLast(4)) : name
        return "\(stem)_\(languages[language]).mrg"
    }

    /// The child that is actually loaded for a registration record (VA 0xEB350): an index past the end selects the last child
    /// (a signed compare), which is how the selecttxt record (child 89 of 83) gets its digit column.
    public static func childIndex(_ child: Int, _ childCount: Int) -> Int {
        childCount > child ? child : childCount - 1
    }
}
