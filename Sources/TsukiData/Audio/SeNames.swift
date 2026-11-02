import Foundation
import TsukiCore
import TsukiEngine

/// What a sound-effect name resolves to (engine VA 0xCC790).
public struct SeLookup: Equatable, Sendable {
    /// 0 for section 0 (`S00..S07`), 2 for sections 2 and 3.
    public let kind: Int

    /// Kind 0: the record in section 0. Kind 2: the `vse.hed` entry (below 10000), or 10000 + the
    /// record of section 3.
    public let index: Int

    public init(kind: Int, index: Int) {
        self.kind = kind
        self.index = index
    }

    /// Kind 2 with an index below 10000: the name of an entry of `vse.hed`.
    public var isVseEntry: Bool { kind == 2 && index < SeNames.sectionThreeBase }
}

/// `se_nam.mrg`: four NAM32 name tables the engine loads at boot (docs/formats/audio.md 4.1) and the
/// name lookup of engine VA 0xCC790 (4.2). Section 2 holds one name per `vse` entry, so `lookup`
/// turns the name in a `_SEPL` or `_SEFI` call into the vse entry.
public struct SeNames: Sendable {
    /// Kind-2 indices from this value on name records of section 3 (no data on the PS4).
    public static let sectionThreeBase = 10_000

    /// Lookup flag: skip section 0.
    public static let skipSectionZero = 1

    /// Lookup flag: skip section 3.
    public static let skipSectionThree = 2

    /// The file the four tables come from.
    public static let defaultPath = "image/se_nam.mrg"

    private static let keyLength = 28

    /// The four name tables (8, 2, 1,327 and 67 records in the retail data).
    public let sections: [[String]]

    /// Upper-cased name to first record, per section: the engine scan stops at the first equal name.
    private let first: [[String: Int]]

    private init(sections: [[String]]) {
        self.sections = sections
        var first: [[String: Int]] = []
        first.reserveCapacity(sections.count)
        for names in sections {
            var map: [String: Int] = [:]
            map.reserveCapacity(names.count)
            for (index, name) in names.enumerated() {
                let upper = SeNames.upper(name)
                if map[upper] == nil { map[upper] = index }
            }
            first.append(map)
        }
        self.first = first
    }

    /// Number of names in section 2: the number of vse entries (1,327 in the retail data).
    public var vseCount: Int { sections[2].count }

    /// Reads the four tables from `image/se_nam.mrg` (a few kilobytes).
    public static func open(_ files: GameFiles, path: String = SeNames.defaultPath) throws -> SeNames {
        try fromMemory(try files.readAll(path))
    }

    /// Reads the tables from a container that is already in memory. Throws when the file is not an
    /// mrgd00 container of four NAM32 sections.
    public static func fromMemory(_ file: ByteSpan) throws -> SeNames {
        let container = try MzpContainer.parse(file)
        guard container.count == 4 else {
            throw TsukiError.format("se_nam.mrg has \(container.count) sections, expected 4")
        }
        var sections: [[String]] = []
        sections.reserveCapacity(4)
        for i in 0..<4 {
            sections.append(try NamTable.parseNam32(container.section(i)).names)
        }
        return SeNames(sections: sections)
    }

    /// Resolves a name like the engine: unless `flags & 1` section 0, unless `flags & 2` section 3,
    /// then section 2. The name is cut after the last backslash, at the first `.` and after 28
    /// characters, and upper-cased (a..z only).
    public func lookup(_ name: String, flags: Int = 0) -> SeLookup? {
        let key = SeNames.key(name)
        if flags & SeNames.skipSectionZero == 0, let index = first[0][key] {
            return SeLookup(kind: 0, index: index)
        }
        if flags & SeNames.skipSectionThree == 0, let index = first[3][key] {
            return SeLookup(kind: 2, index: SeNames.sectionThreeBase + index)
        }
        if let index = first[2][key] {
            return SeLookup(kind: 2, index: index)
        }
        return nil
    }

    /// The `vse.hed` entry named `name` (section 2), or -1; what `_SEPL` plays.
    public func vseIndex(_ name: String) -> Int {
        first[2][SeNames.key(name)] ?? -1
    }

    /// The lookup key of a script name (engine VA 0xCC7AD..0xCC80F).
    public static func key(_ name: String) -> String {
        var base = name
        if let separator = base.lastIndex(of: "\\") {
            base = String(base[base.index(after: separator)...])
        }
        if let dot = base.firstIndex(of: ".") {
            base = String(base[..<dot])
        }
        var units = Array(base.utf16)
        if units.count > keyLength { units.removeLast(units.count - keyLength) }
        for i in units.indices where units[i] >= 0x61 && units[i] <= 0x7A {
            units[i] -= 32
        }
        return String(decoding: units, as: UTF16.self)
    }

    private static func upper(_ string: String) -> String {
        var units = Array(string.utf16)
        for i in units.indices where units[i] >= 0x61 && units[i] <= 0x7A {
            units[i] -= 32
        }
        return String(decoding: units, as: UTF16.self)
    }
}
