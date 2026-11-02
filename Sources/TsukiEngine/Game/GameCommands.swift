import Foundation
import TsukiCore

/// The command families the game host dispatches on (docs/formats/script.md 3.6, 4).
public enum Cmd: UInt8, Sendable {
    /// Not a command of the PS4 interpreter (the engine skips it).
    case unknown = 0

    // flow
    case jump, rtm, rtmn, rtm2, end, ifsc, ifur, ifla, ifjp, ifp4, ifnx, iff, els, eif, nop, atsv, rdst, rtst, rded, rdas, trpy, xstp, xrsm

    // messages and the window
    case zoneMessage, zoneDisabled, msad, wnty, pgst, clo2, clo3, clo4, clo5, wttm, wtsv, wttr

    // choices
    case selr, seld, sels, sela

    // sound and movies
    case sound, vcwt, tomp, tomw

    // stage family handled by the stage runtime
    case stage

    // screen effects of the host
    case fcln, fcsp, flnt, flop, flsp, fccl, fade, stcg, spfc, sprd, sprc, stpv

    // accepted, not implemented by the PS4 engine or not used by any script
    case ignored
}

/// The command-name table of the PS4 main interpreter: the 110 names plus `J*` and `Z*` of `ENGINE_MAIN`
/// (docs/formats/script.md 3.6; tools/tsuki/script_tables.py) and the six names the engine skips (`SNX4 FANX IFP4 DMMY STQK NOP_`).
public enum GameCommands {
    private static let table: [UInt32: Cmd] = build()

    /// The family of a command name; `Cmd.unknown` for a name the engine ignores.
    public static func classify(_ name: CommandName) -> Cmd {
        let first = name.first
        if first == UInt8(ascii: "J") {
            return .jump
        }

        if first == UInt8(ascii: "Z") {
            let second = UInt8((name.value >> 16) & 0xFF)
            switch second {
            case UInt8(ascii: "M"):
                return .zoneMessage
            case UInt8(ascii: "D"):
                return .zoneDisabled
            default:
                return .ignored
            }
        }

        return table[name.value] ?? .unknown
    }

    /// All names the table knows (for tests).
    public static var knownNames: [String] {
        names().map { $0.name }
    }

    private static func names() -> [(name: String, cmd: Cmd)] {
        var list: [(name: String, cmd: Cmd)] = []
        list.append(("JUMP", .jump))

        let one: [(String, Cmd)] = [
            ("RTM_", .rtm), ("RTMN", .rtmn), ("RTM2", .rtm2), ("END_", .end), ("IFSC", .ifsc), ("IFUR", .ifur),
            ("IFLA", .ifla), ("IFJP", .ifjp), ("IFP4", .ifp4), ("IFNX", .ifnx), ("IFF_", .iff), ("ELS_", .els),
            ("EIF_", .eif), ("NOP_", .nop), ("DMMY", .nop), ("ATSV", .atsv), ("RDST", .rdst), ("RTST", .rtst),
            ("RDED", .rded), ("RDAS", .rdas), ("TRPY", .trpy), ("XSTP", .xstp), ("XRSM", .xrsm),
            ("MSAD", .msad), ("WNTY", .wnty), ("PGST", .pgst), ("CLO2", .clo2), ("CLO3", .clo3), ("CLO4", .clo4),
            ("CLO5", .clo5), ("WTTM", .wttm), ("WT__", .wttm), ("WTSV", .wtsv), ("WTTR", .wttr),
            ("SELR", .selr), ("SELD", .seld), ("SELS", .sels), ("SELA", .sela),
            ("MPLY", .sound), ("MVOL", .sound), ("MFAD", .sound), ("MSTP", .sound), ("SEPL", .sound), ("SEFI", .sound),
            ("SEFD", .sound), ("SEVL", .sound), ("SESP", .sound), ("VPLY", .sound), ("VPL2", .sound), ("VCLR", .sound),
            ("VCWT", .vcwt), ("TOMP", .tomp), ("TOMW", .tomw),
            ("FCLN", .fcln), ("FCSP", .fcsp), ("FLNT", .flnt), ("FLOP", .flop), ("FLSP", .flsp), ("FCCL", .fccl),
            ("FADE", .fade), ("STCG", .stcg), ("SPFC", .spfc), ("SPRD", .sprd), ("SPRC", .sprc), ("STPV", .stpv),
            ("SNX4", .ignored), ("FANX", .ignored), ("STQK", .ignored),
            ("SEPN", .ignored), ("SEAC", .ignored), ("SEP3", .ignored), ("SHAK", .ignored), ("SHAS", .ignored),
            ("SNOW", .ignored), ("STRC", .ignored),
        ]
        list.append(contentsOf: one)

        // the variable and VM-internal commands never reach the host; they are listed so that the table is the whole of ENGINE_MAIN
        let ignored = ["WKST", "WKAD", "WKOR", "WKOF", "WKBO", "IF__", "GOTO", "GOTS"]
        for n in ignored {
            list.append((n, .ignored))
        }

        let stage = [
            "STCH", "SCH2", "STCC", "STCP", "STBR", "STEC", "SNX2", "SNX3", "STZ4", "STRT", "STRR", "STRA", "SOXY", "STGS", "STMA", "SPMA", "STNS",
            "STTR", "SACL", "SBAS", "STCL", "SQK2", "SHK2", "SSW2", "SQS2", "SHS2", "SSS2", "SGMA", "STCF", "FADS", "SHOK", "SHAF", "MSQK",
        ]
        for n in stage {
            list.append((n, .stage))
        }

        return list
    }

    private static func build() -> [UInt32: Cmd] {
        var d: [UInt32: Cmd] = [:]
        for (name, cmd) in names() {
            if let cn = try? CommandName.fromAscii(name) {
                d[cn.value] = cmd
            }
        }
        return d
    }
}
