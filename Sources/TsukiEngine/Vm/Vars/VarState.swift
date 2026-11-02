import Foundation
import TsukiCore

/// Choice modes (dword VA 0x17506B0; docs/formats/vm_variables.md 4.5).
public enum ChoiceMode: UInt32, Sendable {
    /// No choice set up yet (the eboot image value).
    case none = 0
    /// `_SELD`: list of `_SELR` lines.
    case list = 1
    /// `_SELS`: two buttons.
    case twoButtons = 2
    /// `_SELA`: the "save your progress?" prompt.
    case savePrompt = 3
}

/// The engine state the variable commands touch (port of `tsuki.vm_vars.VarState`): the variable memory, the
/// argument scratch buffer, the if-block skip counter, scan mode, the snapshot block byte and the choice globals.
public final class VarState {
    /// Size of the argument scratch buffer (VA 0x16543C0).
    public static let argBufferSize = 0x40

    /// Creates a state over `memory`.
    public init(_ memory: VarMemory) {
        self.memory = memory
    }

    /// Creates a state over a new zeroed block (out-of-block addresses rejected).
    public convenience init() {
        self.init(VarMemory())
    }

    /// The variable memory.
    public let memory: VarMemory

    /// Scratch copy of the argument being decoded (VA 0x16543C0, 0x40 bytes); also the label text of a jump.
    public var argBuffer = [UInt8](repeating: 0, count: VarState.argBufferSize)

    /// If-block skip counter (VA 0x165420E; `IFF_`/`ELS_`/`EIF_`, always 0 in retail).
    public var skipCounter: UInt16 = 0

    /// Save-restore scan mode (byte VA 0x174DE48).
    public var scanMode = false

    /// "Message continues" byte (VA 0x16541F4); non-zero blocks History_Snapshot.
    public var snapshotBlock: UInt8 = 0

    /// Array of the pending choice target (u8 VA 0x1750648): `'F'` 0x46, `'G'` 0x47, or 0.
    public var choiceKind: UInt8 = 0

    /// Index of the pending choice target (u16 VA 0x175064A).
    public var choiceIndex: UInt16 = 0

    /// `_SELD` argument 1 (choice id), -1 when absent (i16 VA 0x1750698).
    public var choiceId: Int16 = -1

    /// `_SELR` lines registered for the next `_SELD` (u16 VA 0x1750646).
    public var choiceCount = 0

    /// Per-line result values, `_SELR` argument 0 (u16 table VA 0x1750630).
    public var choiceValues: [UInt16] = []

    /// Per-line "locked" flags, `_SELR` argument 2 == 1 (byte table VA 0x175064C).
    public var choiceLocked: [Bool] = []

    /// Choice mode (u32 VA 0x17506B0), see `ChoiceMode`.
    public var choiceMode: UInt32 = 0

    /// The argument buffer up to its first NUL (the whole buffer when it has none): the text a jump looks up.
    public var argText: ByteSpan {
        let n = argBuffer.firstIndex(of: 0) ?? VarState.argBufferSize
        return ByteSpan(argBuffer).slice(0, n)
    }
}

/// What a variable command did (port of `tsuki.vm_vars.Effect`).
public struct VarEffect {
    /// The interpreter has a case for the name.
    public let handled: Bool
    /// The label text handed to the label lookup (VA 0x794D0), or nil for no jump; may be empty (`_GOTS` past its
    /// last label).
    public let goto: [UInt8]?
    /// ScriptStep returns to its caller (VA 0x9B516).
    public let yielded: Bool
    /// History_Snapshot passed its gate (body VA 0x7AFDD).
    public let snapshot: Bool
    /// The choice UI was set up (VA 0xA5DF0).
    public let choiceUi: Bool
    /// `_SELD`: s16 argument 1 passed to VA 0xB8620 (flowchart marks), else nil.
    public let choicePoint: Int?

    public init(handled: Bool, goto: [UInt8]? = nil, yielded: Bool = false, snapshot: Bool = false,
                choiceUi: Bool = false, choicePoint: Int? = nil) {
        self.handled = handled
        self.goto = goto
        self.yielded = yielded
        self.snapshot = snapshot
        self.choiceUi = choiceUi
        self.choicePoint = choicePoint
    }

    /// No variable semantics (the name is not a variable command).
    public static let notHandled = VarEffect(handled: false)

    /// Handled, nothing else.
    public static let done = VarEffect(handled: true)

    /// True when the command asks for a label lookup.
    public var hasGoto: Bool { goto != nil }
}
