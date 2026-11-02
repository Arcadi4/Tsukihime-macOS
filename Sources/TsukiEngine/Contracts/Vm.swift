import Foundation
import TsukiCore

/// A script position: script number k and a byte offset into its decoded bytes.
public struct ScriptPosition: Equatable, Sendable {
    /// Script number k (allscr.mrg section k + 3).
    public var script: Int
    /// Byte offset in the decoded script, equal to the PS4 offset.
    public var offset: Int

    public init(script: Int, offset: Int) {
        self.script = script
        self.offset = offset
    }

    public static let none = ScriptPosition(script: -1, offset: -1)

    public var isNone: Bool { script < 0 }
}

/// The 4 name bytes after the first `_` of a segment, packed big-endian: the first letter selects
/// the dispatch table entry, the other three form the 24-bit key.
public struct CommandName: Equatable, Hashable, Sendable, CustomStringConvertible {
    public var value: UInt32

    public init(value: UInt32) {
        self.value = value
    }

    /// The first name byte (dispatch letter).
    public var first: UInt8 { UInt8(truncatingIfNeeded: value >> 24) }

    /// The 24-bit key of the other three bytes.
    public var key: UInt32 { value & 0x00FF_FFFF }

    public static func fromBytes(_ name: ByteSpan) throws -> CommandName {
        guard name.count >= 4 else {
            throw TsukiError.format("a command name has 4 bytes")
        }
        return CommandName(value: UInt32(name[0]) << 24 | UInt32(name[1]) << 16
                           | UInt32(name[2]) << 8 | UInt32(name[3]))
    }

    /// Packs a 4-character ASCII name such as "WKST".
    public static func fromAscii(_ name: String) throws -> CommandName {
        let bytes = Array(name.utf8)
        guard bytes.count == 4, bytes.allSatisfy({ $0 < 0x80 }) else {
            throw TsukiError.format("a command name is 4 ASCII characters")
        }
        return CommandName(value: UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16
                           | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
    }

    public var description: String {
        var out = ""
        for i in 0..<4 {
            let b = UInt8(truncatingIfNeeded: value >> UInt32(24 - 8 * i))
            out.append(b >= 0x20 && b < 0x7F ? Character(UnicodeScalar(b)) : "?")
        }
        return out
    }
}

/// One decoded statement: a segment whose name passed the tokenizer.
public struct Statement {
    /// At most this many bytes per segment (0x300).
    public static let maxSegmentBytes = 0x300
    /// At most this many segments run per step.
    public static let segmentsPerStep = 1000

    /// Script number k.
    public let script: Int
    /// Offset of the segment start (the PS4 offset).
    public let offset: Int
    /// Offset just after the segment.
    public let end: Int
    public let name: CommandName
    /// Raw bytes from name + 4 up to `end`.
    public let args: ByteSpan

    public init(script: Int, offset: Int, end: Int, name: CommandName, args: ByteSpan) {
        self.script = script
        self.offset = offset
        self.end = end
        self.name = name
        self.args = args
    }

    public var position: ScriptPosition { ScriptPosition(script: script, offset: offset) }
    public var next: ScriptPosition { ScriptPosition(script: script, offset: end) }
}

/// What the VM does after a statement.
public enum StepKind: UInt8, Sendable {
    case `continue` = 0
    case yield = 1
    case halt = 2
}

/// The result of one statement. Resuming always continues after the statement or at `target`, so no
/// command runs twice; a waiting handler yields and keeps its wait state in the host.
public struct StepResult: Sendable {
    public var kind: StepKind
    public var target: ScriptPosition

    public init(kind: StepKind, target: ScriptPosition = .none) {
        self.kind = kind
        self.target = target
    }

    public static let `continue` = StepResult(kind: .continue)
    public static let yield = StepResult(kind: .yield)
    public static let halt = StepResult(kind: .halt)

    public var hasTarget: Bool { !target.isNone }

    public static func continueAt(_ target: ScriptPosition) -> StepResult {
        StepResult(kind: .continue, target: target)
    }

    public static func yieldAt(_ target: ScriptPosition) -> StepResult {
        StepResult(kind: .yield, target: target)
    }
}

/// The command side of the VM: the VM decodes a statement and dispatches it.
public protocol ScriptHost: AnyObject {
    func dispatch(_ statement: Statement) -> StepResult
}
