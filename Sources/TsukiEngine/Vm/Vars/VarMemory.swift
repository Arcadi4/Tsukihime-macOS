import Foundation
import TsukiCore

/// Engine addresses of the variable side of the VM (docs/formats/vm_variables.md 2.1; `tsuki.vm_vars`).
public enum VarAddresses {
    /// var_F (u16[1200]).
    public static let f = Vars.fVa
    /// var_Z (u16[1400]).
    public static let z = Vars.zVa
    /// var_G (u16[2000]).
    public static let g = Vars.gVa
    /// The first byte after var_G.
    public static let afterG = 0x164D5C0
    /// The scratch copy of the argument being decoded (0x40 bytes, VA 0x16543C0).
    public static let argBuffer = 0x16543C0
    /// F823: message counter of the page; `C<n>` = F[F823 + n].
    public static let messageIndexVar = Vars.messageIndexVar
    /// F1118: 0 = `_SELA` opens its save prompt (and clears it).
    public static let savePromptVar = 1118
    /// F929: non-zero blocks History_Snapshot.
    public static let snapshotGateVar = 929
    /// F1102: non-zero blocks History_Snapshot except for kinds 0 and 11.
    public static let snapshotModeVar = 1102

    /// Address of F[`n`] (no bounds check, as in the engine).
    public static func ofF(_ n: Int) -> Int { f + 2 * n }

    /// Address of G[`n`] (no bounds check, as in the engine).
    public static func ofG(_ n: Int) -> Int { g + 2 * n }

    /// `F[12]` / `Z[0]` / `G[3]` for an address inside the three arrays, else the address in hex
    /// (`tsuki.vm_vars.address_name`; the slice traces name their writes this way).
    public static func name(_ va: Int) -> String {
        if va >= f && va < f + 2 * Vars.fCount && (va - f) % 2 == 0 {
            return "F[\((va - f) / 2)]"
        }
        if va >= z && va < z + 2 * Vars.zCount && (va - z) % 2 == 0 {
            return "Z[\((va - z) / 2)]"
        }
        if va >= g && va < g + 2 * Vars.gCount && (va - g) % 2 == 0 {
            return "G[\((va - g) / 2)]"
        }
        return "0x\(String(va, radix: 16))"
    }
}

/// A read or a write of one 16-bit word.
public enum VarAccessKind: UInt8, Sendable {
    /// A read.
    case read = 0
    /// A write.
    case write = 1
}

/// One logged variable access: kind, engine address, value read or written.
public struct VarAccess: Equatable, Sendable {
    /// Read or write.
    public let kind: VarAccessKind
    /// Engine address of the word.
    public let va: Int
    /// The value read or the (16-bit) value written.
    public let value: UInt16

    public init(kind: VarAccessKind, va: Int, value: UInt16) {
        self.kind = kind
        self.va = va
        self.value = value
    }
}

/// What `VarMemory` does with a word outside var_F / var_Z / var_G.
public enum OutOfBlockPolicy: UInt8, Sendable {
    /// Throw `VarAccessException` (RUNTIME_REQUIREMENTS item 6: "port: reject out-of-range"; the retail scripts
    /// never form such an address).
    case reject = 0
    /// Keep the word in a side table, as the engine's flat memory would (its neighbours are other engine
    /// state). Used by the differential tests, which address words around the arrays on purpose.
    case flat = 1
}

/// An operand formed an address outside the three variable arrays under `OutOfBlockPolicy.reject`.
public struct VarAccessException: Error, CustomStringConvertible {
    public let message: String

    public init() {
        message = ""
    }

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

/// The variable memory the VM commands address: 16-bit words keyed by engine address, the way the engine forms
/// them (`base + 2 * n` with no bounds check; docs/formats/vm_variables.md 2.2). Words of var_F / var_Z / var_G
/// live in a `Vars` block; any other address follows the `OutOfBlockPolicy`. Port of `tsuki.vm_vars.VarMemory`;
/// `log` records every access in program order like its `log`.
public final class VarMemory {
    private var outside: [Int: UInt16] = [:]
    private let outsideInit: ((Int) -> UInt16)?

    /// Creates a memory over `block`.
    /// - Parameters:
    ///   - block: the F / Z / G block (shared, not copied).
    ///   - policy: what happens to an address outside the block.
    ///   - outsideInit: under `.flat`, the value of an outside word never written (default 0).
    public init(_ block: Vars, policy: OutOfBlockPolicy = .reject, outsideInit: ((Int) -> UInt16)? = nil) {
        self.block = block
        self.policy = policy
        self.outsideInit = outsideInit
    }

    /// Creates a memory over a new zeroed block.
    public convenience init() {
        self.init(Vars())
    }

    /// The F / Z / G words.
    public let block: Vars
    /// What happens to an address outside the block.
    public let policy: OutOfBlockPolicy
    /// When not nil, every `read` and `write` is appended here.
    public var log: [VarAccess]?
    /// Number of accesses (peeks included) to words outside the block so far.
    public private(set) var outOfBlockAccesses = 0

    /// The value of the word at `va` without logging.
    public func peek(_ va: Int) throws -> UInt16 {
        var word = 0
        if VarMemory.tryWord(va, &word) {
            return block.getWord(word)
        }
        try outsideAccess(va)
        return outside[va] ?? outsideInit?(va) ?? 0
    }

    /// Reads the word at `va` (logged).
    public func read(_ va: Int) throws -> UInt16 {
        let value = try peek(va)
        log?.append(VarAccess(kind: .read, va: va, value: value))
        return value
    }

    /// Writes the low 16 bits of `value` to `va` (logged).
    public func write(_ va: Int, _ value: Int) throws {
        let word = UInt16(truncatingIfNeeded: value)
        try poke(va, word)
        log?.append(VarAccess(kind: .write, va: va, value: word))
    }

    /// Sets a word without logging (set-up).
    public func poke(_ va: Int, _ value: UInt16) throws {
        var word = 0
        if VarMemory.tryWord(va, &word) {
            block.setWord(word, value)
            return
        }
        try outsideAccess(va)
        outside[va] = value
    }

    /// Word index of `va` in the block, when it is an even address inside it.
    public static func tryWord(_ va: Int, _ word: inout Int) -> Bool {
        let d = va - Vars.fVa
        if d >= 0 && d < 2 * Vars.wordCount && (d & 1) == 0 {
            word = d >> 1
            return true
        }
        word = -1
        return false
    }

    private func outsideAccess(_ va: Int) throws {
        outOfBlockAccesses += 1
        if policy == .reject {
            throw VarAccessException(
                "variable address 0x\(String(va, radix: 16)) is outside var_F / var_Z / var_G (vm_variables.md 2.2)")
        }
    }
}
