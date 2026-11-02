import Foundation
import TsukiCore
import TsukiEngine

/// One HED/NAM/MRG triplet of the analysed build (docs/formats/containers.md 1, 2.2, 7.3).
public struct TripletSpec {
    /// Base name in `image/`.
    public let name: String
    /// HED8 or HED4.
    public let format: HedFormat
    /// Entry count (FORMATS 2).
    public let entries: Int
    /// True when the archive has a `.nam` file with one name per entry.
    public let hasNam: Bool
    /// False only for bgm.hed, which simply ends (containers.md 2.1).
    public let hasTerminator: Bool
    /// Entry indices at which bank 1, 2, ... start (containers.md 2.2).
    public let bankStarts: [Int]

    public init(name: String, format: HedFormat, entries: Int, hasNam: Bool, hasTerminator: Bool, bankStarts: [Int]) {
        self.name = name
        self.format = format
        self.entries = entries
        self.hasNam = hasNam
        self.hasTerminator = hasTerminator
        self.bankStarts = bankStarts
    }
}

/// One standalone mrgd00 file of the analysed build (containers.md 8).
public struct StandaloneSpec: Sendable {
    /// File name in `image/`.
    public let fileName: String
    /// Section count (FORMATS 2).
    public let sections: Int

    public init(fileName: String, sections: Int) {
        self.fileName = fileName
        self.sections = sections
    }
}

/// What the analysed CUSA47999 build looks like: the numbers of FORMATS section 2 and RR 3.3, written
/// down once so that the build check and the tests agree. A different data release breaks them.
public enum AnalysedBuild {
    /// The 12 triplet archives, 49,620 entries in all.
    public static let triplets: [TripletSpec] = [
        TripletSpec(name: "allpac0", format: .hed8, entries: 2449, hasNam: true, hasTerminator: true, bankStarts: [474, 992]),
        TripletSpec(name: "allpac1", format: .hed8, entries: 9968, hasNam: true, hasTerminator: true,
                    bankStarts: [311, 799, 1403, 2212, 3449, 3725, 4197, 5033, 6199, 7280, 9115]),
        TripletSpec(name: "allpac1_2", format: .hed8, entries: 4317, hasNam: true, hasTerminator: true, bankStarts: [2503, 3417, 3681, 4221]),
        TripletSpec(name: "allpac2", format: .hed8, entries: 14745, hasNam: true, hasTerminator: true, bankStarts: []),
        TripletSpec(name: "allpac3", format: .hed8, entries: 136, hasNam: true, hasTerminator: true, bankStarts: []),
        TripletSpec(name: "allpac4", format: .hed8, entries: 37, hasNam: true, hasTerminator: true, bankStarts: []),
        TripletSpec(name: "parts", format: .hed8, entries: 24, hasNam: false, hasTerminator: true, bankStarts: []),
        TripletSpec(name: "bgm", format: .hed8, entries: 132, hasNam: false, hasTerminator: false, bankStarts: []),
        TripletSpec(name: "vse", format: .hed8, entries: 1327, hasNam: false, hasTerminator: true, bankStarts: []),
        TripletSpec(name: "vag", format: .hed8, entries: 19, hasNam: false, hasTerminator: true, bankStarts: []),
        TripletSpec(name: "voice", format: .hed4, entries: 16464, hasNam: true, hasTerminator: true, bankStarts: []),
        TripletSpec(name: "voice2", format: .hed4, entries: 2, hasNam: true, hasTerminator: true, bankStarts: []),
    ]

    /// The 8 standalone mrgd00 files, 891 sections in all.
    public static let standalone: [StandaloneSpec] = [
        StandaloneSpec(fileName: "allscr.mrg", sections: 552),
        StandaloneSpec(fileName: "script_text.mrg", sections: 10),
        StandaloneSpec(fileName: "ft_en.mrg", sections: 65),
        StandaloneSpec(fileName: "ft_ja.mrg", sections: 65),
        StandaloneSpec(fileName: "ft_ko.mrg", sections: 65),
        StandaloneSpec(fileName: "ft_zc.mrg", sections: 65),
        StandaloneSpec(fileName: "ft_zt.mrg", sections: 65),
        StandaloneSpec(fileName: "se_nam.mrg", sections: 4),
    ]

    /// Triplet entries over all 12 archives.
    public static let tripletEntryTotal = 49_620

    /// Sections over all standalone files.
    public static let standaloneSectionTotal = 891

    /// Scripts: allscr.mrg sections 3...551 (549 names in section 0).
    public static let scripts = 549

    /// Text lines per language in script_text.mrg.
    public static let textLines = 43_969

    /// Voice entries in voice.hed.
    public static let voices = 16_464

    /// Movie files in `image/movie`.
    public static let movieFiles = 134

    /// Names in se_nam.mrg section 2: one per vse entry (containers.md 7.3).
    public static let vseNames = 1_327

    /// The language order of script_text.mrg table pairs (text.md 2).
    public static let textLanguages: [String] = ["ja", "en", "zc", "zt", "ko"]

    /// SELF magic at the start of eboot.bin (RR 3.3 item 2).
    public static let selfMagic: [UInt8] = [0x4F, 0x15, 0x3D, 0x1D]

    /// File offset of the string "Hunex Consumer Library": text VA 0x2DA510 + 0x2280 (RR 3.3 item 2).
    public static let hunexStringOffset = 0x2DA510 + 0x2280

    /// The string the build check expects at `hunexStringOffset`.
    public static let hunexString: [UInt8] = Array("Hunex Consumer Library".utf8)
}
