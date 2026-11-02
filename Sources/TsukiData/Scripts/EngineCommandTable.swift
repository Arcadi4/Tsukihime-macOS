import Foundation

/// How a main-interpreter handler ends the interpreter's per-frame batch (`script_tables.ENGINE_MAIN`).
public enum FrameBehaviour: Sendable {
    /// The handler always ends the batch (returns to the caller).
    case yield

    /// The handler never ends the batch.
    case `continue`

    /// The handler ends the batch on some paths only (waits, jumps, scan mode).
    case mixed
}

/// The command names the main interpreter (VA 0x95E60) dispatches, with each handler's address and
/// frame behaviour (docs/formats/script.md 3.1, engine.md 5.3; `ENGINE_MAIN`, `ENGINE_ALIASES` and
/// `KEEP_BGM_FLAG_VA` of `script_tables.py`). The table is not stored in the eboot (the dispatch is a
/// compare tree), so it is a constant of this build, produced by emulating the dispatch for every
/// first letter and every 24-bit suffix breakpoint and cross-checked by brute force over all
/// 26 x 37^3 names. The handler address is the start of the basic block that holds the first
/// instruction with a side effect.
public enum EngineCommandTable {
    /// Entries of `main`: 110 names plus the two prefix rules `J*` and `Z*`.
    public static let entryCount = 112

    /// The byte the script-end cleanup clears instead of stopping the BGM; `_RTM2` and `_RTMN` set it
    /// (VA 0x174DE0C).
    public static let keepBgmFlagVa = 0x174DE0C

    /// Every command name the main interpreter accepts, to (handler VA, frame behaviour); `J*` and
    /// `Z*` stand for every name starting with that letter.
    public static let main: [String: (handlerVa: Int, behaviour: FrameBehaviour)] = [
        "ATSV": (0x95F5D, FrameBehaviour.mixed),
        "CLO2": (0x9A887, FrameBehaviour.yield),
        "CLO3": (0x9A8B8, FrameBehaviour.yield),
        "CLO4": (0x9A8E7, FrameBehaviour.yield),
        "CLO5": (0x9A939, FrameBehaviour.yield),
        "EIF_": (0x96EFC, FrameBehaviour.`continue`),
        "ELS_": (0x96F2A, FrameBehaviour.`continue`),
        "END_": (0x9AB42, FrameBehaviour.yield),
        "FADE": (0x97973, FrameBehaviour.mixed),
        "FADS": (0x9B06D, FrameBehaviour.yield),
        "FCCL": (0x982B5, FrameBehaviour.mixed),
        "FCLN": (0x96D12, FrameBehaviour.mixed),
        "FCSP": (0x982A2, FrameBehaviour.mixed),
        "FLNT": (0x9606A, FrameBehaviour.mixed),
        "FLOP": (0x982C8, FrameBehaviour.mixed),
        "FLSP": (0x9715E, FrameBehaviour.mixed),
        "GOTO": (0x96E3F, FrameBehaviour.mixed),
        "GOTS": (0x9609A, FrameBehaviour.mixed),
        "IFF_": (0x97FC8, FrameBehaviour.`continue`),
        "IFJP": (0x9806F, FrameBehaviour.mixed),
        "IFLA": (0x96D4F, FrameBehaviour.mixed),
        "IFNX": (0x97F00, FrameBehaviour.`continue`),
        "IFSC": (0x96185, FrameBehaviour.mixed),
        "IFUR": (0x98161, FrameBehaviour.mixed),
        "IF__": (0x9708D, FrameBehaviour.mixed),
        "J*": (0x961DC, FrameBehaviour.mixed),
        "MFAD": (0x978F5, FrameBehaviour.mixed),
        "MPLY": (0x96E2C, FrameBehaviour.`continue`),
        "MSAD": (0x9AECE, FrameBehaviour.yield),
        "MSQK": (0x962D3, FrameBehaviour.`continue`),
        "MSTP": (0x978BD, FrameBehaviour.`continue`),
        "MVOL": (0x978AA, FrameBehaviour.`continue`),
        "PGST": (0x9637E, FrameBehaviour.mixed),
        "RDAS": (0x98118, FrameBehaviour.`continue`),
        "RDED": (0x9813B, FrameBehaviour.mixed),
        "RDST": (0x96DFF, FrameBehaviour.`continue`),
        "RTM2": (0x97FBC, FrameBehaviour.`continue`),
        "RTMN": (0x9643E, FrameBehaviour.mixed),
        "RTM_": (0x97174, FrameBehaviour.mixed),
        "RTST": (0x97131, FrameBehaviour.`continue`),
        "SACL": (0x99591, FrameBehaviour.`continue`),
        "SBAS": (0x99609, FrameBehaviour.`continue`),
        "SCH2": (0x98226, FrameBehaviour.`continue`),
        "SEAC": (0x99846, FrameBehaviour.`continue`),
        "SEFD": (0x99859, FrameBehaviour.`continue`),
        "SEFI": (0x98C8F, FrameBehaviour.`continue`),
        "SELA": (0x9B1B6, FrameBehaviour.yield),
        "SELD": (0x9B1DC, FrameBehaviour.yield),
        "SELR": (0x9936D, FrameBehaviour.`continue`),
        "SELS": (0x9B435, FrameBehaviour.yield),
        "SEP3": (0x99934, FrameBehaviour.`continue`),
        "SEPL": (0x98C8F, FrameBehaviour.`continue`),
        "SEPN": (0x996CB, FrameBehaviour.`continue`),
        "SESP": (0x996E1, FrameBehaviour.`continue`),
        "SEVL": (0x98C07, FrameBehaviour.`continue`),
        "SGMA": (0x99568, FrameBehaviour.`continue`),
        "SHAF": (0x99581, FrameBehaviour.`continue`),
        "SHAK": (0x971D5, FrameBehaviour.mixed),
        "SHAS": (0x9980A, FrameBehaviour.`continue`),
        "SHK2": (0x9982D, FrameBehaviour.`continue`),
        "SHOK": (0x98C44, FrameBehaviour.`continue`),
        "SHS2": (0x99673, FrameBehaviour.`continue`),
        "SNOW": (0x9968C, FrameBehaviour.`continue`),
        "SNX2": (0x98289, FrameBehaviour.`continue`),
        "SNX3": (0x9986C, FrameBehaviour.`continue`),
        "SOXY": (0x99885, FrameBehaviour.`continue`),
        "SPFC": (0x98CD0, FrameBehaviour.`continue`),
        "SPMA": (0x9929C, FrameBehaviour.`continue`),
        "SPRC": (0x992B6, FrameBehaviour.`continue`),
        "SPRD": (0x96A28, FrameBehaviour.`continue`),
        "SQK2": (0x992C7, FrameBehaviour.`continue`),
        "SQS2": (0x992E0, FrameBehaviour.`continue`),
        "SSS2": (0x986CF, FrameBehaviour.`continue`),
        "SSW2": (0x99D4B, FrameBehaviour.`continue`),
        "STBR": (0x990C2, FrameBehaviour.`continue`),
        "STCC": (0x97EED, FrameBehaviour.`continue`),
        "STCF": (0x9B448, FrameBehaviour.yield),
        "STCG": (0x99A4F, FrameBehaviour.`continue`),
        "STCH": (0x99AB7, FrameBehaviour.`continue`),
        "STCL": (0x99AF0, FrameBehaviour.`continue`),
        "STCP": (0x99B03, FrameBehaviour.`continue`),
        "STEC": (0x9991B, FrameBehaviour.`continue`),
        "STGS": (0x99065, FrameBehaviour.`continue`),
        "STMA": (0x9969F, FrameBehaviour.`continue`),
        "STNS": (0x996B8, FrameBehaviour.`continue`),
        "STPV": (0x983AB, FrameBehaviour.`continue`),
        "STRA": (0x97264, FrameBehaviour.`continue`),
        "STRC": (0x9952F, FrameBehaviour.`continue`),
        "STRR": (0x99542, FrameBehaviour.`continue`),
        "STRT": (0x99555, FrameBehaviour.`continue`),
        "STTR": (0x99947, FrameBehaviour.`continue`),
        "STZ4": (0x99038, FrameBehaviour.`continue`),
        "TOMP": (0x96F4C, FrameBehaviour.mixed),
        "TOMW": (0x9AB56, FrameBehaviour.yield),
        "TRPY": (0x96FC3, FrameBehaviour.`continue`),
        "VCLR": (0x97277, FrameBehaviour.`continue`),
        "VCWT": (0x96504, FrameBehaviour.mixed),
        "VPL2": (0x968B2, FrameBehaviour.mixed),
        "VPLY": (0x968B2, FrameBehaviour.mixed),
        "WKAD": (0x97AE6, FrameBehaviour.`continue`),
        "WKBO": (0x97BB8, FrameBehaviour.`continue`),
        "WKOF": (0x96B98, FrameBehaviour.`continue`),
        "WKOR": (0x9798B, FrameBehaviour.`continue`),
        "WKST": (0x96566, FrameBehaviour.`continue`),
        "WNTY": (0x972F5, FrameBehaviour.`continue`),
        "WTSV": (0x9AF36, FrameBehaviour.yield),
        "WTTM": (0x9AC1A, FrameBehaviour.yield),
        "WTTR": (0x9AFD1, FrameBehaviour.yield),
        "WT__": (0x9AC1A, FrameBehaviour.yield),
        "XRSM": (0x96E52, FrameBehaviour.`continue`),
        "XSTP": (0x965E5, FrameBehaviour.`continue`),
        "Z*": (0x96615, FrameBehaviour.mixed),
    ]

    /// Names that share a handler with another name.
    public static let aliases: [String: String] = [
        "SEFI": "SEPL",
        "VPL2": "VPLY",
        "WT__": "WTTM",
    ]

    /// The handler of a four-character command name, or nil when the main interpreter ignores the
    /// command (for example `DMMY`, `NOP_`, `IFP4`, `SNX4`).
    public static func handler(_ name: String) -> (handlerVa: Int, behaviour: FrameBehaviour)? {
        if let first = name.first, first == "J" || first == "Z" {
            return main[String(first) + "*"]
        }
        return main[name]
    }

    /// True when the main interpreter dispatches the name.
    public static func isEngineCommand(_ name: String) -> Bool {
        handler(name) != nil
    }
}
