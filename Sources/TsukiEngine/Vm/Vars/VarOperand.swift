import Foundation
import TsukiCore

/// What a statically decoded operand addresses.
public enum OperandKind: UInt8, Sendable {
    /// The command ignores the operand / does nothing.
    case none = 0
    /// The literal value `VarOperand.index`.
    case literal = 1
    /// F[`VarOperand.index`].
    case f = 2
    /// G[`VarOperand.index`].
    case g = 3
    /// F[F823 + `VarOperand.index`].
    case c = 4
}

/// A statically decoded operand (for dumps, census and tools; port of `tsuki.vm_vars.Operand` / `parse_operand`).
/// The executing path is `VarCommands`, which reads the same bytes in the engine's order.
public struct VarOperand: Equatable, Sendable, CustomStringConvertible {
    /// What the operand addresses.
    public let kind: OperandKind
    /// Variable index, or the literal value.
    public let index: Int

    public init(kind: OperandKind, index: Int) {
        self.kind = kind
        self.index = index
    }

    /// The address the operand forms (C with the given F823), or nil for a literal / nothing.
    public func address(_ f823: Int = 0) -> Int? {
        switch kind {
        case .f:
            return VarAddresses.f + 2 * index
        case .g:
            return VarAddresses.g + 2 * index
        case .c:
            return VarAddresses.f + 2 * (Int(Int16(truncatingIfNeeded: f823)) + index)
        default:
            return nil
        }
    }

    /// Same text as the reference's `str(Operand)`: `F[12]`, `F[F823+847]`, `lit(3)`, `none(0)`.
    public var description: String {
        switch kind {
        case .f: return "F[\(index)]"
        case .g: return "G[\(index)]"
        case .c: return "F[F823+\(index)]"
        case .literal: return "lit(\(index))"
        default: return "none(\(index))"
        }
    }

    /// Decodes one argument text (an optional `` `NNN: `` tag included) the way the engine does in `role`.
    public static func parse(_ raw: ByteSpan, _ role: OperandRole) -> VarOperand {
        let body = raw.count > 0 && raw[0] == 0x60
            ? (raw.count > 5 ? raw.slice(5, raw.count - 5) : ByteSpan())
            : raw
        let first: UInt8 = body.count > 0 ? body[0] : 0
        if role == .gots || role == .choice {
            if first != 0x5F {
                return VarOperand(kind: .none, index: 0)
            }

            let d = VarCommands.threeDigits(body)
            if role == .choice {
                return body.count > 1 && body[1] == 0x44
                    ? VarOperand(kind: .f, index: Int(Int16(truncatingIfNeeded: d)))
                    : VarOperand(kind: .none, index: d)
            }

            return VarCommands.underscoreIsG(d) ? underscore(d) : VarOperand(kind: .f, index: d)
        }

        let n = InlineReader.readText(raw)
        let allowed: Bool
        switch role {
        case .value:
            allowed = first == 0x46 || first == 0x47 || first == 0x5F
        case .wkTarget:
            allowed = first == 0x43 || first == 0x46 || first == 0x47 || first == 0x5F
        case .orTarget:
            allowed = first == 0x46 || first == 0x47 || first == 0x5F
        default:
            allowed = first == 0x46 || first == 0x47
        }

        if first == 0 || !allowed {
            return VarOperand(kind: role == .value ? .literal : .none, index: n)
        }

        switch first {
        case 0x43:
            return VarOperand(kind: .c, index: Int(Int16(truncatingIfNeeded: n)))
        case 0x5F:
            return underscore(n)
        case 0x46:
            return VarOperand(kind: .f, index: Int(Int16(truncatingIfNeeded: n)))
        default:
            return VarOperand(kind: .g, index: Int(Int16(truncatingIfNeeded: n)))
        }
    }

    /// Decodes an ASCII / Latin-1 argument text.
    public static func parse(_ text: String, _ role: OperandRole) -> VarOperand {
        parse(ByteSpan(latin1(text)), role)
    }

    private static func underscore(_ n: Int) -> VarOperand {
        VarCommands.underscoreIsG(n)
            ? VarOperand(kind: .g, index: (n & 0xFFFF) - 600)
            : VarOperand(kind: .f, index: Int(Int16(truncatingIfNeeded: n)))
    }

    /// Latin-1 bytes of a string; characters outside it become `?`, as `Encoding.Latin1` does.
    private static func latin1(_ text: String) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(text.unicodeScalars.count)
        for scalar in text.unicodeScalars {
            bytes.append(scalar.value <= 0xFF ? UInt8(scalar.value) : UInt8(ascii: "?"))
        }
        return bytes
    }
}

/// How a history record / save slot keeps one F value (docs/formats/vm_variables.md 2.4; adv_state.md 2.1).
public enum HistoryStorage: UInt8, Sendable {
    /// Not kept: 0 after loading a slot, unchanged by a rewind.
    case none = 0
    /// Kept exactly.
    case u16 = 1
    /// Kept as its low byte, restored sign-extended.
    case s8 = 2
    /// Kept as a bit, restored as value != 0.
    case bool = 3
}

/// The F values a history record keeps (port of `tsuki.vm_vars.history_storage` / `history_roundtrip` /
/// `history_after_rewind`), over the index lists of `HistoryRecord`. The restore order is u16, s8, bool, so an
/// index in two lists ends with the later list's storage (F967: s8, F991: bool).
public enum HistoryVars {
    private static let table: [HistoryStorage] = build()

    /// How F[`index`] is kept.
    public static func storage(_ index: Int) -> HistoryStorage {
        index >= 0 && index < table.count ? table[index] : .none
    }

    /// F[`index`] after saving `value` and loading the slot again.
    public static func roundTrip(_ index: Int, _ value: Int) -> UInt16 {
        switch storage(index) {
        case .u16:
            return UInt16(truncatingIfNeeded: value)
        case .s8:
            return UInt16(truncatingIfNeeded: Int(Int8(truncatingIfNeeded: value)))
        case .bool:
            return (value & 0xFFFF) != 0 ? 1 : 0
        case .none:
            return 0
        }
    }

    /// F[`index`] after a rewind to a record taken when it was `saved`; `current` is its value before the rewind.
    public static func afterRewind(_ index: Int, _ saved: Int, _ current: Int) -> UInt16 {
        storage(index) == .none ? UInt16(truncatingIfNeeded: current) : roundTrip(index, saved)
    }

    private static func build() -> [HistoryStorage] {
        var t = [HistoryStorage](repeating: .none, count: Vars.fCount + 1)
        for i in HistoryRecord.fU16Indices {
            t[i] = .u16
        }
        for i in HistoryRecord.fS8Indices {
            t[i] = .s8
        }
        for i in HistoryRecord.fBoolIndices {
            t[i] = .bool
        }
        return t
    }
}
