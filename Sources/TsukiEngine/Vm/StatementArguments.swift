import Foundation
import TsukiCore

/// What `StatementArguments.value` found.
public enum ArgValueKind: UInt8, Sendable {
    /// An integer value.
    case value = 0
    /// The argument is missing or empty for an object-parser command: the handler uses its own default
    /// (`Command.value` returns None).
    case absent = 1
    /// The expression has no defined engine value (`ArgValue.error` says why).
    case undefined = 2
    /// The argument list cannot be split (`SplitStatus` is not `.ok`).
    case splitError = 3
}

/// An integer argument as its command's handler reads it.
public struct ArgValue: Equatable, Sendable {
    /// What was found.
    public let kind: ArgValueKind
    /// The integer when `kind` is `.value`, else 0.
    public let value: Int
    /// The reason when `kind` is `.undefined`.
    public let error: ExpressionError

    public init(kind: ArgValueKind, value: Int, error: ExpressionError = .none) {
        self.kind = kind
        self.value = value
        self.error = error
    }

    /// True when an integer was read.
    public var hasValue: Bool { kind == .value }

    /// The integer, or `fallback` when the argument is absent or has no defined value.
    public func or(_ fallback: Int) -> Int { hasValue ? value : fallback }
}

/// Argument access for a `Statement` (docs/formats/script.md 3.2): which reader the command uses and the position
/// conventions of `Statement.args`, whose first byte is the separator after the four name bytes. Port of
/// `tsuki.script.Command.int_arg`, `present`, `obj_args`, `expr_arg` and `value`.
public enum StatementArguments {
    /// The integer argument `index` read the way the command's PS4 handler reads it: object-parser commands
    /// (`ObjectCommands`) go through `ObjectExpression` (TOMP through the partial strtol getter); every other command
    /// through the 16-bit `InlineReader`.
    public static func value(_ statement: Statement, _ index: Int) -> ArgValue {
        if !ObjectCommands.contains(statement.name) {
            return ArgValue(kind: .value, value: InlineReader.readInt16(statement, index))
        }

        var ranges = [ArgRange](repeating: ArgRange(start: 0, end: 0), count: ObjectParser.maxArguments)
        let (status, count) = ObjectParser.split(statement, into: &ranges)
        if status != .ok {
            return ArgValue(kind: .splitError, value: 0)
        }
        if !ObjectParser.has(ranges, count, index) {
            return ArgValue(kind: .absent, value: 0)
        }

        let arg = ranges[index].slice(statement.args)
        if statement.name == ObjectCommands.tomp {
            return ObjectParser.partialInt(arg).map { ArgValue(kind: .value, value: $0) }
                ?? ArgValue(kind: .absent, value: 0)
        }

        var v = 0
        var error = ExpressionError.none
        return ObjectExpression.tryEvaluate(arg, value: &v, error: &error)
            ? ArgValue(kind: .value, value: v)
            : ArgValue(kind: .undefined, value: 0, error: error)
    }

    /// The object-parser value of argument `index` regardless of the command (`expr_arg`): absent when the argument is
    /// missing or empty.
    public static func objectValue(_ statement: Statement, _ index: Int) -> ArgValue {
        var ranges = [ArgRange](repeating: ArgRange(start: 0, end: 0), count: ObjectParser.maxArguments)
        let (status, count) = ObjectParser.split(statement, into: &ranges)
        if status != .ok {
            return ArgValue(kind: .splitError, value: 0)
        }
        if !ObjectParser.has(ranges, count, index) {
            return ArgValue(kind: .absent, value: 0)
        }

        var v = 0
        var error = ExpressionError.none
        return ObjectExpression.tryEvaluate(ranges[index].slice(statement.args), value: &v, error: &error)
            ? ArgValue(kind: .value, value: v)
            : ArgValue(kind: .undefined, value: 0, error: error)
    }

    /// The 32-bit inline value of argument `index` (`int_arg(i, 32)`).
    public static func int32(_ statement: Statement, _ index: Int) -> Int {
        InlineReader.readInt32(statement, index)
    }

    /// The 16-bit inline value of argument `index` (`int_arg(i)`).
    public static func int16(_ statement: Statement, _ index: Int) -> Int {
        InlineReader.readInt16(statement, index)
    }

    /// The inline "present" test (`present(i)`).
    public static func present(_ statement: Statement, _ index: Int) -> Bool {
        InlineReader.isPresent(statement, index)
    }

    /// The textual arguments of the statement as byte ranges inside `Statement.args` (`Command.args`), appended to
    /// `ranges`; returns the index in `Statement.args` of the terminating `)` or `;`.
    public static func splitText(_ statement: Statement, _ ranges: inout [ArgRange]) -> Int {
        ArgumentList.split(statement.args, ArgumentList.startIn(statement), into: &ranges)
    }
}
