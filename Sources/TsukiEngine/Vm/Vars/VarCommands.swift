import Foundation
import TsukiCore

/// Operand positions with different first-byte dispatches (docs/formats/vm_variables.md 3).
public enum OperandRole: UInt8, Sendable {
    /// WKST, WKAD target: `C F G _`.
    case wkTarget = 0
    /// WKOR, WKOF target (and every Script_Prefetch target): `F G _`.
    case orTarget = 1
    /// WKBO target: `F G`.
    case boTarget = 2
    /// Value (WKST, WKAD, WKOR, WKOF value, IF__ both sides): `F G _`, everything else literal.
    case value = 3
    /// GOTS selector: `_` + 3 digit bytes.
    case gots = 4
    /// SELD / SELA / SELS target: `_D` + 3 digit bytes.
    case choice = 5
}

/// The variable commands of the script VM with the engine's exact read / write semantics: `_WKST`, `_WKAD`,
/// `_WKOR`, `_WKOF`, `_WKBO`, `_IF__`, `_GOTS`, `_SELD`, `_SELA`, `_SELS`, `_SELR`, the choice result store and
/// the History_Snapshot gate (docs/formats/vm_variables.md 3-5). Byte-exact port of `tsuki.vm_vars`
/// (`execute`, `choice_store`, `snapshot_gate`), which reproduces the engine on 61,000 fuzzed statements under
/// unicorn (`tsuki.misc_vm_variables_errata`).
///
/// Statements are read from a byte span and the position of the first name byte (the byte after `_`); the first
/// argument byte is `namePos + 5`. Bytes past the end of the span read as 0 and a copy loop stops there as at a
/// `;`, exactly as in the reference.
public enum VarCommands {
    /// Names the main interpreter (ScriptStep) handles here.
    public static let handledMain: [String] = [
        "WKST", "WKAD", "WKOR", "WKOF", "WKBO", "IF__", "GOTS", "SELD", "SELA", "SELS", "SELR",
    ]

    /// Names Script_Prefetch (VA 0x9B760) handles here.
    public static let handledPrefetch: [String] = ["WKST", "WKAD", "WKOR", "WKOF", "IF__"]

    private static let maxSkip = 500
    private static let backtick: UInt8 = 0x60

    private static let wkst = key("WKST")
    private static let wkad = key("WKAD")
    private static let wkor = key("WKOR")
    private static let wkof = key("WKOF")
    private static let wkbo = key("WKBO")
    private static let ifName = key("IF__")
    private static let gots = key("GOTS")
    private static let seld = key("SELD")
    private static let sela = key("SELA")
    private static let sels = key("SELS")
    private static let selr = key("SELR")

    /// Packs a literal name; the table is fixed text, so a wrong name is a programming error.
    private static func key(_ name: String) -> UInt32 {
        let bytes = Array(name.utf8)
        precondition(bytes.count == 4 && bytes.allSatisfy { $0 < 0x80 },
                     "a command name is 4 ASCII characters")
        return UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
    }

    /// Runs the variable semantics of the statement whose four name bytes start at `buf[namePos]` (the byte after
    /// `_`). `prefetch` selects Script_Prefetch's handlers (VA 0x9B760: no `C` targets, no WKBO / GOTS / SEL*).
    /// Other names return `.notHandled` and change nothing.
    public static func execute(_ buf: ByteSpan, _ namePos: Int, _ state: VarState,
                               prefetch: Bool = false) throws -> VarEffect {
        if namePos < 0 || namePos + 4 > buf.count {
            return .notHandled
        }

        let name = UInt32(buf[namePos]) << 24 | UInt32(buf[namePos + 1]) << 16
            | UInt32(buf[namePos + 2]) << 8 | UInt32(buf[namePos + 3])
        let p0 = namePos + 5
        if name == wkst {
            return try wkSt(buf, p0, state, prefetch)
        }
        if name == wkad {
            return try rmw(buf, p0, state, prefetch ? .orTarget : .wkTarget, .add)
        }
        if name == wkor {
            return try rmw(buf, p0, state, .orTarget, .or)
        }
        if name == wkof {
            return try rmw(buf, p0, state, .orTarget, .andNot)
        }
        if name == ifName {
            return try ifCommand(buf, p0, state)
        }
        if prefetch {
            return .notHandled
        }
        if name == wkbo {
            return try wkBo(buf, p0, state)
        }
        if name == gots {
            return try gotsCommand(buf, p0, state)
        }
        if name == seld {
            return try selD(buf, p0, state)
        }
        if name == sela {
            return try selA(buf, p0, state)
        }
        if name == sels {
            return VarEffect(handled: true, yielded: true,
                             choiceUi: twoAnswerDialog(buf, p0, state, ChoiceMode.twoButtons.rawValue))
        }
        if name == selr {
            return try selR(buf, p0, state)
        }
        return .notHandled
    }

    /// Runs one statement text such as `"_WKST(C847,eq,0);"` (Latin-1; for tests and tools).
    public static func executeText(_ statement: String, _ state: VarState,
                                   prefetch: Bool = false) throws -> VarEffect {
        let bytes = latin1(statement)
        return try execute(ByteSpan(bytes), (bytes.firstIndex(of: 0x5F) ?? -1) + 1, state, prefetch: prefetch)
    }

    /// History_Snapshot's entry test (VA 0x7AF9B..0x7AFD7), in the engine's order: scan mode -> no; F929 != 0 ->
    /// no; F1102 != 0 and `kind` not 0 or 11 -> no (F1102 is read only when F929 == 0); block byte != 0 -> no.
    public static func snapshotGate(_ state: VarState, _ kind: Int) throws -> Bool {
        if state.scanMode {
            return false
        }

        let memory = state.memory
        if try memory.read(VarAddresses.ofF(VarAddresses.snapshotGateVar)) != 0 {
            return false
        }
        if try memory.read(VarAddresses.ofF(VarAddresses.snapshotModeVar)) != 0 && !(kind == 0 || kind == 0xB) {
            return false
        }
        return state.snapshotBlock == 0
    }

    /// The choice UI's result store when the player confirms line `cursor` (u16 VA 0x17506A2), by choice mode
    /// (dispatch VA 0xA6180): list (mode 1 and any mode other than 2 / 3) stores values[s16 cursor] (0 for a cursor
    /// outside the registered lines); two buttons (mode 2) store the cursor itself when it is 0 or 1; the save
    /// prompt (mode 3) stores nothing. Kind 'F' writes var_F[s16 index], kind 'Z' var_Z[s16 index], any other kind
    /// nothing. Returns the address written, or nil.
    public static func choiceStore(_ state: VarState, _ cursor: Int) throws -> Int? {
        if state.choiceMode == ChoiceMode.savePrompt.rawValue {
            return nil
        }

        let value: Int
        if state.choiceMode == ChoiceMode.twoButtons.rawValue {
            if (cursor & 0xFFFF) > 1 {
                return nil
            }
            value = cursor & 0xFFFF
        } else {
            let i = Int(Int16(truncatingIfNeeded: cursor))
            value = i >= 0 && i < state.choiceValues.count ? Int(state.choiceValues[i]) : 0
        }

        let a: Int
        if state.choiceKind == 0x46 {
            a = VarAddresses.f + 2 * Int(Int16(truncatingIfNeeded: Int(state.choiceIndex)))
        } else if state.choiceKind == 0x5A {
            a = VarAddresses.z + 2 * Int(Int16(truncatingIfNeeded: Int(state.choiceIndex)))
        } else {
            return nil
        }

        try state.memory.write(a, value)
        return a
    }

    // -----------------------------------------------------------------------------------------------------------
    // argument access (the inlined copies of the inline reader's loops)
    // -----------------------------------------------------------------------------------------------------------

    private static func at(_ buf: ByteSpan, _ i: Int) -> UInt8 {
        i >= 0 && i < buf.count ? buf[i] : 0
    }

    /// Start of argument `index` (that many commas skipped, at most 500 bytes each), or -1 when `)` or `;` comes
    /// first. Same loop as the inline reader VA 0x76690 (`tsuki.vm_vars.arg_start`).
    public static func argStart(_ buf: ByteSpan, _ p0: Int, _ index: Int) -> Int {
        var p = p0
        for _ in 0..<index {
            var k = 0
            while k < maxSkip {
                let c = at(buf, p + k)
                if c == 0x29 || c == 0x3B {
                    return -1
                }
                if c == 0x2C {
                    p += k + 1
                    break
                }
                k += 1
            }
            if k == maxSkip {
                p += maxSkip
            }
        }
        return p
    }

    /// The handlers' argument copy into the scratch buffer (VA 0x96566..0x965A7 and others): a leading backtick
    /// skips 5 bytes, then bytes are copied up to the first `)` `,` `;` (NUL is copied like any byte; the span end
    /// stops it) and a NUL is appended when there is room. A missing argument only stores NUL at buffer[0]. Returns
    /// buffer[0] (`tsuki.vm_vars.copy_arg`).
    public static func copyArg(_ buf: ByteSpan, _ p0: Int, _ index: Int, _ state: VarState) -> UInt8 {
        let p = index > 0 ? argStart(buf, p0, index) : p0
        if p < 0 {
            state.argBuffer[0] = 0
            return 0
        }

        copyFrom(buf, p, &state.argBuffer)
        return state.argBuffer[0]
    }

    private static func copyFrom(_ buf: ByteSpan, _ p: Int, _ ab: inout [UInt8]) {
        var p = p
        if at(buf, p) == backtick {
            p += 5
        }

        var k = 0
        while true {
            let i = p + k
            let c = i < buf.count ? at(buf, i) : 0x3B
            if c == 0x29 || c == 0x2C || c == 0x3B {
                break
            }
            if k < ab.count {
                ab[k] = c
            }
            k += 1
        }

        if k < ab.count {
            ab[k] = 0
        }
    }

    // -----------------------------------------------------------------------------------------------------------
    // operand -> address
    // -----------------------------------------------------------------------------------------------------------

    /// True when an `_` operand value selects G[n-600] (VA 0x9880F: n in 600..700 mod 2^16).
    public static func underscoreIsG(_ n: Int) -> Bool {
        ((n - 701) & 0xFFFF) > 0xFF9A
    }

    /// `_` operands: n in 600..700 (mod 2^16) selects G[n-600], everything else F[s16 n].
    public static func underscoreAddress(_ n: Int) -> Int {
        underscoreIsG(n)
            ? VarAddresses.g + 2 * ((n & 0xFFFF) - 600)
            : VarAddresses.f + 2 * Int(Int16(truncatingIfNeeded: n))
    }

    /// Address read for a value operand with first byte `first` and inline value `n`, or nil for a literal
    /// (dispatch VA 0x987E3 and its copies).
    public static func valueAddress(_ first: UInt8, _ n: Int) -> Int? {
        switch first {
        case 0x46:
            return VarAddresses.f + 2 * Int(Int16(truncatingIfNeeded: n))
        case 0x47:
            return VarAddresses.g + 2 * Int(Int16(truncatingIfNeeded: n))
        case 0x5F:
            return underscoreAddress(n)
        default:
            return nil
        }
    }

    /// Address written by a target operand in `role`, or nil when the command does nothing. A `C` target reads
    /// F823 (logged) to form F[F823 + n].
    public static func targetAddress(_ first: UInt8, _ n: Int, _ role: OperandRole,
                                     _ memory: VarMemory) throws -> Int? {
        if first == 0x43 && role == .wkTarget {
            let b = Int(Int16(truncatingIfNeeded: Int(try memory.read(VarAddresses.ofF(VarAddresses.messageIndexVar)))))
            return VarAddresses.f + 2 * (b + Int(Int16(truncatingIfNeeded: n)))
        }
        if first == 0x46 {
            return VarAddresses.f + 2 * Int(Int16(truncatingIfNeeded: n))
        }
        if first == 0x47 {
            return VarAddresses.g + 2 * Int(Int16(truncatingIfNeeded: n))
        }
        if first == 0x5F && (role == .wkTarget || role == .orTarget) {
            return underscoreAddress(n)
        }
        return nil
    }

    /// GOTS / SELD / SELA / SELS index: bytes 2..4 as decimal digits without any check
    /// (b2*100 + b3*10 + b4 - 5328).
    public static func threeDigits(_ b: ByteSpan) -> Int {
        Int(at(b, 2)) * 100 + Int(at(b, 3)) * 10 + Int(at(b, 4)) - 0x14D0
    }

    private static func operandValue(_ first: UInt8, _ n: Int, _ memory: VarMemory) throws -> Int {
        if let va = valueAddress(first, n) {
            return Int(try memory.read(va))
        }
        return n & 0xFFFF
    }

    private static func wkValue(_ buf: ByteSpan, _ p0: Int, _ index: Int, _ state: VarState) throws -> Int {
        let first = copyArg(buf, p0, index, state)
        let n = InlineReader.readInt16(buf, p0, index)
        return try operandValue(first, n, state.memory)
    }

    // -----------------------------------------------------------------------------------------------------------
    // handlers
    // -----------------------------------------------------------------------------------------------------------

    private enum RmwOp: UInt8 {
        case add
        case or
        case andNot
    }

    /// ScriptStep 0x96566 / Script_Prefetch 0x9BFA2: target = value; only a leading 'e' of argument 1 makes
    /// argument 2 the value.
    private static func wkSt(_ buf: ByteSpan, _ p0: Int, _ state: VarState, _ prefetch: Bool) throws -> VarEffect {
        let first0 = copyArg(buf, p0, 0, state)
        let n0 = InlineReader.readInt16(buf, p0, 0)
        let first1 = copyArg(buf, p0, 1, state)
        let value: Int
        if first1 == 0x65 {
            value = try wkValue(buf, p0, 2, state)
        } else {
            value = try operandValue(first1, InlineReader.readInt16(buf, p0, 1), state.memory)
        }
        if let a = try targetAddress(first0, n0, prefetch ? .orTarget : .wkTarget, state.memory) {
            try state.memory.write(a, value)
        }
        return .done
    }

    private static func rmw(_ buf: ByteSpan, _ p0: Int, _ state: VarState, _ role: OperandRole,
                            _ op: RmwOp) throws -> VarEffect {
        let first0 = copyArg(buf, p0, 0, state)
        let n0 = InlineReader.readInt16(buf, p0, 0)
        let value = try wkValue(buf, p0, 1, state)
        if let a = try targetAddress(first0, n0, role, state.memory) {
            let old = Int(try state.memory.read(a))
            let result: Int
            switch op {
            case .add:
                result = old + value
            case .or:
                result = old | value
            case .andNot:
                result = old & ~value
            }
            try state.memory.write(a, result)
        }
        return .done
    }

    /// VA 0x97BB8: target |= 1 << (int(arg1) & 31), 16-bit store; argument 1 is never a variable and not copied.
    private static func wkBo(_ buf: ByteSpan, _ p0: Int, _ state: VarState) throws -> VarEffect {
        let first0 = copyArg(buf, p0, 0, state)
        let n0 = InlineReader.readInt16(buf, p0, 0)
        let bit = Int((UInt32(1) << UInt32(InlineReader.readInt16(buf, p0, 1) & 31)) & 0xFFFF)
        if let a = try targetAddress(first0, n0, .boTarget, state.memory) {
            try state.memory.write(a, Int(try state.memory.read(a)) | bit)
        }
        return .done
    }

    /// IF__ operator (VA 0x9A474..0x9A64C): first byte e/n/g/l, a second byte 'e' makes g/l inclusive; signed
    /// 16-bit compares.
    public static func condition(_ op0: UInt8, _ op1: UInt8, _ lhs: Int, _ rhs: Int) -> Bool {
        let a = Int(Int16(truncatingIfNeeded: lhs))
        let b = Int(Int16(truncatingIfNeeded: rhs))
        switch op0 {
        case 0x65:
            return a == b
        case 0x6E:
            return a != b
        case 0x67:
            return op1 == 0x65 ? a >= b : a > b
        case 0x6C:
            return op1 == 0x65 ? a <= b : a < b
        default:
            return false
        }
    }

    /// ScriptStep 0x9708D / Script_Prefetch 0x9BAD5: `_IF__(lhs,op,rhs,label)` continues when `lhs op rhs` holds
    /// and jumps to `label` when it does NOT hold (a structured if: the label ends the block).
    private static func ifCommand(_ buf: ByteSpan, _ p0: Int, _ state: VarState) throws -> VarEffect {
        if state.skipCounter != 0 {
            return .done
        }

        let lhs = try wkValue(buf, p0, 0, state)
        let rhs = try wkValue(buf, p0, 2, state)
        _ = copyArg(buf, p0, 1, state)
        if condition(state.argBuffer[0], state.argBuffer[1], lhs, rhs) {
            return .done
        }

        if !InlineReader.isPresent(buf, p0, 3) {
            return .done
        }

        _ = copyArg(buf, p0, 3, state)
        return VarEffect(handled: true, goto: state.argText.toArray())
    }

    /// VA 0x9609A: computed goto. Selector `_?ddd`: v = F[ddd] (or G[ddd-600]); the label is argument s16(v + 1),
    /// argument 0 itself when that is <= 0, the empty text when the argument does not exist.
    private static func gotsCommand(_ buf: ByteSpan, _ p0: Int, _ state: VarState) throws -> VarEffect {
        if state.scanMode {
            return VarEffect(handled: true, yielded: true)
        }

        if state.skipCounter != 0 {
            return .done
        }

        if copyArg(buf, p0, 0, state) != 0x5F {
            return .done
        }

        let n = threeDigits(ByteSpan(state.argBuffer))
        let v: UInt16
        if underscoreIsG(n) {
            v = try state.memory.read(VarAddresses.g + 2 * ((n & 0xFFFF) - 600))
        } else {
            v = try state.memory.read(VarAddresses.f + 2 * n)
        }

        let k = Int(Int16(truncatingIfNeeded: Int(v) + 1))
        let p = k > 0 ? argStart(buf, p0, k) : p0
        if p < 0 {
            state.argBuffer[0] = 0
        } else {
            copyFrom(buf, p, &state.argBuffer)
        }
        return VarEffect(handled: true, goto: state.argText.toArray())
    }

    /// SELD / SELS / SELA target decode: only a target starting with `_` is stored, kind 'F' when byte 1 is 'D',
    /// else 'G'; index = 3 digit bytes. Any other target leaves the previous kind / index in place.
    private static func choiceTarget(_ b: ByteSpan, _ state: VarState) {
        if at(b, 0) != 0x5F {
            return
        }

        state.choiceKind = at(b, 1) == 0x44 ? 0x46 : 0x47
        state.choiceIndex = UInt16(truncatingIfNeeded: threeDigits(b))
    }

    /// ScriptStep's SELD (VA 0x9B1DC): in scan mode it yields at once; else mode 1, target, choice id, UI set-up,
    /// yield.
    private static func selD(_ buf: ByteSpan, _ p0: Int, _ state: VarState) throws -> VarEffect {
        if state.scanMode {
            return VarEffect(handled: true, yielded: true)
        }

        state.choiceMode = ChoiceMode.list.rawValue
        _ = copyArg(buf, p0, 0, state)
        choiceTarget(ByteSpan(state.argBuffer), state)
        var point: Int?
        if InlineReader.isPresent(buf, p0, 1) {
            state.choiceId = Int16(truncatingIfNeeded: InlineReader.readInt16(buf, p0, 1))
            point = Int(state.choiceId)
        } else {
            state.choiceId = -1
        }

        return VarEffect(handled: true, yielded: true, choiceUi: true, choicePoint: point)
    }

    /// The SELS helper VA 0xB82E0 (mode 2) / SELA helper VA 0xB8400 (mode 3). Scan mode: no change. Otherwise mode,
    /// target via the object parser (argument 0, at most 15 bytes, NUL-padded), id -1, count 2, values {0, 1}, UI
    /// set-up.
    private static func twoAnswerDialog(_ buf: ByteSpan, _ p0: Int, _ state: VarState, _ mode: UInt32) -> Bool {
        if state.scanMode {
            return false
        }

        state.choiceMode = mode
        var ranges = [ArgRange](repeating: ArgRange(start: 0, end: 0), count: ObjectParser.maxArguments)
        var target = [UInt8](repeating: 0, count: 15 + 5)
        let (status, count) = ObjectParser.split(buf, p0 - 1, into: &ranges)
        if status == .ok && count > 0 && ranges[0].start < ranges[0].end {
            let r = ranges[0]
            let end = Swift.min(Swift.min(r.end, r.start + 15), buf.count)
            if end > r.start {
                for k in 0..<(end - r.start) {
                    target[k] = buf[r.start + k]
                }
            }
        }

        choiceTarget(ByteSpan(target), state)
        state.choiceId = -1
        state.choiceCount = 2
        state.choiceValues.removeAll()
        state.choiceValues.append(0)
        state.choiceValues.append(1)
        return true
    }

    /// ScriptStep's SELA (VA 0x9B1B6): opens the save prompt only when F1118 == 0, then always F1118 = 0, and
    /// yields.
    private static func selA(_ buf: ByteSpan, _ p0: Int, _ state: VarState) throws -> VarEffect {
        let a = VarAddresses.ofF(VarAddresses.savePromptVar)
        var opened = false
        if try state.memory.read(a) == 0 {
            opened = twoAnswerDialog(buf, p0, state, ChoiceMode.savePrompt.rawValue)
        }

        try state.memory.write(a, 0)
        return VarEffect(handled: true, yielded: true, choiceUi: opened)
    }

    /// SELR's variable side (VA 0x9936D..0x99525): for the first line of a group the History_Snapshot gate (kind
    /// 0xD) and, when F823 > 0, C847 += 1 (also in scan mode); every line stores argument 0 as its value and
    /// argument 2 == 1 as its locked flag and counts itself. SELR does not yield.
    private static func selR(_ buf: ByteSpan, _ p0: Int, _ state: VarState) throws -> VarEffect {
        let value = InlineReader.readInt16(buf, p0, 0)
        var snap = false
        if state.choiceCount == 0 {
            snap = try snapshotGate(state, 0xD)
            let k = Int(Int16(truncatingIfNeeded: Int(try state.memory.read(
                VarAddresses.ofF(VarAddresses.messageIndexVar)))))
            if k > 0 {
                let a = VarAddresses.ofF(k + 847)
                try state.memory.write(a, Int(try state.memory.read(a)) + 1)
            }
        }

        truncate(&state.choiceValues, state.choiceCount)
        truncate(&state.choiceLocked, state.choiceCount)
        state.choiceValues.append(UInt16(truncatingIfNeeded: value))
        state.choiceLocked.append(InlineReader.readInt16(buf, p0, 2) == 1)
        state.choiceCount += 1
        return VarEffect(handled: true, snapshot: snap)
    }

    private static func truncate<T>(_ list: inout [T], _ count: Int) {
        if count >= 0 && list.count > count {
            list.removeSubrange(count..<list.count)
        }
    }

    /// Latin-1 bytes of a statement text; characters outside Latin-1 become `?`.
    private static func latin1(_ text: String) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(text.unicodeScalars.count)
        for scalar in text.unicodeScalars {
            bytes.append(scalar.value <= 0xFF ? UInt8(scalar.value) : UInt8(ascii: "?"))
        }
        return bytes
    }
}
