import Foundation
import TsukiCore

/// The 52 commands whose handler reads its arguments with the object parser instead of the inline
/// readers (docs/formats/script.md 3.2; `OBJ_COMMANDS` in `tools/tsuki/script_tables.py`, found by
/// walking every handler of the main interpreter).
public enum ObjectCommands {
    /// The names in alphabetical order.
    public static let names: [String] = [
        "CLO4", "CLO5", "FADE", "FADS", "FCCL", "FCLN", "FCSP", "FLNT", "FLOP", "FLSP", "MSQK",
        "RDAS", "RDED", "RDST", "RTST", "SACL", "SBAS", "SCH2", "SELA", "SELS", "SGMA", "SHK2",
        "SHS2", "SNX2", "SNX3", "SOXY", "SPFC", "SPMA", "SPRD", "SQK2", "SQS2", "SSS2", "SSW2",
        "STBR", "STCC", "STCF", "STCH", "STCL", "STCP", "STEC", "STGS", "STMA", "STNS", "STRA",
        "STRC", "STRR", "STRT", "STTR", "STZ4", "TOMP", "WTSV", "WTTR",
    ]

    private static let set: Set<UInt32> = Set(names.map { key($0) })

    /// The name of TOMP, whose handler reads the movie id with the partial-strtol getter (VA 0xE3C0).
    public static let tomp = CommandName(value: key("TOMP"))

    /// True when the command reads its arguments with the object parser.
    public static func contains(_ name: CommandName) -> Bool {
        set.contains(name.value)
    }

    /// Packs a literal name; the table is fixed text, so a wrong name is a programming error.
    private static func key(_ name: String) -> UInt32 {
        let bytes = Array(name.utf8)
        precondition(bytes.count == 4 && bytes.allSatisfy { $0 < 0x80 },
                     "a command name is 4 ASCII characters")
        return UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
    }
}
