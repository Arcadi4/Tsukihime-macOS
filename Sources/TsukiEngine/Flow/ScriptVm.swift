import Foundation
import TsukiCore

/// The scripts and label tables the VM can switch to (a jump to another scene, a load).
public protocol FlowScripts: AnyObject {
    /// Script `k` (`GameData.script`).
    func script(_ k: Int) -> ScriptImage

    /// The label table of script `k` (allscr section 1, child k).
    func labels(_ k: Int) -> LabelTable
}

/// Why `ScriptVm.step` returned.
public enum StepEnd: UInt8, Sendable {
    /// A statement yielded; the next call resumes at `ScriptVm.position`.
    case yielded = 0
    /// 1000 segments ran without a yield (VA 0x95EB0 budget).
    case budget = 1
    /// The host halted the VM.
    case halted = 2
    /// The cursor reached the end of the script.
    case endOfScript = 3
}

/// What the VM did with a statement (for traces).
public enum FlowAction: UInt8, Sendable {
    /// A variable command (WK*, SEL* variable side).
    case variables = 0
    /// A flow command (IF__, GOTO, GOTS, IFNX) that did not jump.
    case noJump = 1
    /// A flow command that jumped to `FlowStep.target`.
    case jump = 2
    /// A marker (`_Z*`); `ZM` also went to the host.
    case marker = 3
    /// Dispatched to the host.
    case host = 4
}

/// One executed statement, as reported to `ScriptVm.observer`.
public struct FlowStep {
    /// Script number.
    public let script: Int
    /// Segment start.
    public let offset: Int
    /// Statement (segment) index in the script, or -1 when the cursor was not at a segment start.
    public let index: Int
    /// The 4 name bytes.
    public let name: CommandName
    /// What the VM did.
    public let action: FlowAction
    /// Variable writes of the statement in program order (address, value).
    public let writes: [(va: Int, value: UInt16)]
    /// The label text of a jump, or nil.
    public let goto: [UInt8]?
    /// The jump target, or `ScriptPosition.none`.
    public let target: ScriptPosition
    /// How the VM goes on.
    public let result: StepKind

    public init(script: Int, offset: Int, index: Int, name: CommandName, action: FlowAction,
                writes: [(va: Int, value: UInt16)], goto: [UInt8]?, target: ScriptPosition, result: StepKind) {
        self.script = script
        self.offset = offset
        self.index = index
        self.name = name
        self.action = action
        self.writes = writes
        self.goto = goto
        self.target = target
        self.result = result
    }

    /// The display name: the 4 name bytes, or `ZM` / `ZZ` / `ZY` / `ZD` for markers (`tsuki.script.Command.name`).
    public var displayName: String {
        let s = name.description
        return s.first == "Z" ? String(s.prefix(2)) : s
    }
}

/// A jump to a label the script's table does not have (the engine reads garbage; no retail label is missing).
public struct ScriptFlowException: Error, CustomStringConvertible {
    public let message: String

    public init() {
        message = ""
    }

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

/// The main interpreter loop (ScriptStep, eboot VA 0x95E60; docs/formats/script.md 3.1, 3.6, 3.7; engine.md 5.2): it
/// segments from the cursor, runs at most 1000 segments per `step` call, and executes the VM's own commands itself:
/// the variables (`VarCommands`), the flow commands `_IF__` (jumps when its condition is false), `_GOTO`, `_GOTS`,
/// `_IFNX`, the variable side of `_SEL*` and the common marker processing. Every other command goes to
/// `ScriptHost.dispatch`, whose result (and target, e.g. for `_JUMP`) the loop follows.
///
/// Frame behaviour of the jumps, measured under unicorn on the eboot's own handlers (docs/status/wave2/C2.md):
/// `_IF__` and `_GOTO` yield with the cursor at the label (the next call starts there); `_GOTS` and `_IFNX` continue
/// at the label in the same call; a true `_IF__` and an `_IFNX` without label continue with the next statement.
public final class ScriptVm {
    private static let wkst = key("WKST")
    private static let wkad = key("WKAD")
    private static let wkor = key("WKOR")
    private static let wkof = key("WKOF")
    private static let wkbo = key("WKBO")
    private static let ifName = key("IF__")
    private static let gotoName = key("GOTO")
    private static let gots = key("GOTS")
    private static let ifnx = key("IFNX")
    private static let seld = key("SELD")
    private static let sela = key("SELA")
    private static let sels = key("SELS")
    private static let selr = key("SELR")

    private static func key(_ name: String) -> UInt32 {
        let bytes = Array(name.utf8)
        precondition(bytes.count == 4 && bytes.allSatisfy { $0 < 0x80 },
                     "a command name is 4 ASCII characters")
        return UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
    }

    private let scripts: FlowScripts
    private var scriptImage: ScriptImage
    private var labels: LabelTable

    /// Creates a VM at offset `offset` of script `script`.
    public init(_ scripts: FlowScripts, _ vars: VarState, _ markers: MarkerState, _ script: Int,
                _ offset: Int = 0) {
        self.scripts = scripts
        self.vars = vars
        self.markers = markers
        scriptImage = scripts.script(script)
        labels = scripts.labels(script)
        cursor = offset
    }

    /// The variable state.
    public let vars: VarState

    /// The marker state (read tracking).
    public let markers: MarkerState

    /// The script being run.
    public var image: ScriptImage { scriptImage }

    /// The byte offset of the next segment.
    public private(set) var cursor: Int

    /// The position of the next segment.
    public var position: ScriptPosition {
        ScriptPosition(script: scriptImage.index, offset: cursor)
    }

    /// The local-label flag (VA 0x165420C), set to 1 by a `_ZY` marker.
    public var localLabelFlag = 0

    /// When set, called for every executed statement (allocates the write list; for traces and tests).
    public var observer: ((FlowStep) -> Void)?

    /// Moves the cursor (a load, a rewind, a scene change by the caller).
    public func seek(_ position: ScriptPosition) {
        if position.script != scriptImage.index {
            scriptImage = scripts.script(position.script)
            labels = scripts.labels(position.script)
        }
        cursor = position.offset
    }

    /// One ScriptStep call: runs segments until a statement yields or halts, or 1000 segments ran.
    public func step(_ host: ScriptHost) throws -> StepEnd {
        for _ in 0..<Statement.segmentsPerStep {
            let bytes = scriptImage.span
            if cursor >= bytes.count {
                return .endOfScript
            }

            let seg = try ScriptSegmenter.read(bytes, cursor)
#if DEBUG
            if seg.truncated {
                throw ScriptFlowException(
                    "script \(scriptImage.index): no ';' within 0x\(String(Statement.maxSegmentBytes, radix: 16)) bytes at 0x\(String(seg.start, radix: 16))")
            }
#endif
            cursor = seg.end
            guard let st = ScriptSegmenter.statement(scriptImage.index, bytes, seg) else {
                continue
            }

            let result = try execute(st, seg, host)
            if result.hasTarget {
                seek(result.target)
            }

            if result.kind == .yield {
                return .yielded
            }

            if result.kind == .halt {
                return .halted
            }
        }

        return .budget
    }

    private func execute(_ st: Statement, _ seg: ScriptSegment, _ host: ScriptHost) throws -> StepResult {
        let outer = vars.memory.log
        var log: [VarAccess]?
        if observer != nil {
            log = []
            vars.memory.log = log
        }

        defer {
            if let log = log {
                if var outer = outer {
                    outer.append(contentsOf: log)
                    vars.memory.log = outer
                } else {
                    vars.memory.log = nil
                }
            }
        }
        return try run(st, seg, host, log)
    }

    private func run(_ st: Statement, _ seg: ScriptSegment, _ host: ScriptHost,
                     _ log: [VarAccess]?) throws -> StepResult {
        let s = scriptImage.span.slice(seg.start, seg.end - seg.start)
        let namePos = seg.nameStart - seg.start
        let name = st.name.value
        var action: FlowAction
        var result: StepResult
        var label: [UInt8]?
        if st.name.first == UInt8(ascii: "Z") {
            action = .marker
            result = try marker(st, seg, host)
        } else if name == ScriptVm.wkst || name == ScriptVm.wkad || name == ScriptVm.wkor
                    || name == ScriptVm.wkof || name == ScriptVm.wkbo {
            _ = try VarCommands.execute(s, namePos, vars)
            action = .variables
            result = .continue
        } else if name == ScriptVm.ifName {
            label = try VarCommands.execute(s, namePos, vars).goto
            if let label = label {
                (action, result) = (.jump, .yieldAt(try lookup(label)))
            } else {
                (action, result) = (.noJump, .continue)
            }
        } else if name == ScriptVm.gotoName {
            if vars.skipCounter != 0 {
                (action, result) = (.noJump, .continue)
            } else {
                _ = VarCommands.copyArg(s, namePos + 5, 0, vars)
                label = vars.argText.toArray()
                (action, result) = (.jump, .yieldAt(try lookup(label!)))
            }
        } else if name == ScriptVm.gots {
            let e = try VarCommands.execute(s, namePos, vars)
            label = e.goto
            if e.yielded {
                (action, result) = (.noJump, .yield)
            } else if let label = label {
                (action, result) = (.jump, .continueAt(try lookup(label)))
            } else {
                (action, result) = (.noJump, .continue)
            }
        } else if name == ScriptVm.ifnx {
            if InlineReader.isPresent(s, namePos + 5, 1) {
                _ = VarCommands.copyArg(s, namePos + 5, 1, vars)
                label = vars.argText.toArray()
                (action, result) = (.jump, .continueAt(try lookup(label!)))
            } else {
                (action, result) = (.noJump, .continue)
            }
        } else if name == ScriptVm.seld || name == ScriptVm.sela || name == ScriptVm.sels
                    || name == ScriptVm.selr {
            let e = try VarCommands.execute(s, namePos, vars)
            let h = host.dispatch(st)
            action = .variables
            result = e.yielded
                ? StepResult(kind: h.kind == .halt ? .halt : .yield, target: h.target)
                : h
        } else {
            action = .host
            result = host.dispatch(st)
        }

        if let observer = observer {
            var writes: [(va: Int, value: UInt16)] = []
            if let log = log {
                for a in log where a.kind == .write {
                    writes.append((a.va, a.value))
                }
            }

            let index = ScriptVm.binarySearch(scriptImage.segmentStarts, seg.start)
            observer(FlowStep(script: scriptImage.index, offset: seg.start, index: index < 0 ? -1 : index,
                              name: st.name, action: action, writes: writes, goto: label,
                              target: result.target, result: result.kind))
        }

        return result
    }

    /// Marker processing (VA 0x96615..0x96750): read tracking with the decoded ids, then `ZM` goes to the host (it
    /// displays the message and yields), `ZY` copies its label (from name + 8) to the argument buffer and sets the
    /// local-label flag, `ZZ` / `ZD` do nothing more.
    private func marker(_ st: Statement, _ seg: ScriptSegment, _ host: ScriptHost) throws -> StepResult {
        let script = scriptImage.span
        if let ids = ScriptSegmenter.readMarkerId(script, seg) {
            markers.enter(ids.block, ids.sub)
        }

        let kind = UInt8(truncatingIfNeeded: st.name.value >> 16)
        if kind == UInt8(ascii: "M") {
            return host.dispatch(st)
        }

        if kind == UInt8(ascii: "Y") {
            let s = script.slice(seg.start, seg.end - seg.start)
            let p = seg.nameStart - seg.start + 8
            var k = 0
            let room = vars.argBuffer.count - 1
            while p + k < s.count && s[p + k] != 0x29 && s[p + k] != 0x2C && s[p + k] != 0x3B && k < room {
                vars.argBuffer[k] = s[p + k]
                k += 1
            }

            vars.argBuffer[k] = 0
            localLabelFlag = 1
        }

        return .continue
    }

    private func lookup(_ label: [UInt8]) throws -> ScriptPosition {
        let offset = labels.find(ByteSpan(label))
        if offset < 0 {
            let text = String(label.map { Character(UnicodeScalar($0)) })
            throw ScriptFlowException(
                "script \(scriptImage.index): label '\(text)' is not in its label table")
        }
        return ScriptPosition(script: scriptImage.index, offset: offset)
    }

    /// Index of `target` in `values`, or the complement of its insertion point when absent (`BinarySearch`).
    private static func binarySearch(_ values: [Int], _ target: Int) -> Int {
        var lo = 0
        var hi = values.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if values[mid] == target {
                return mid
            } else if values[mid] < target {
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return ~lo
    }
}
