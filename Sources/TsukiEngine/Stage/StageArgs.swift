import Foundation
import TsukiCore

/// The arguments of one layer statement as the object parser gives them to the handlers: `has(i)` (VA 0xD8C0),
/// `expr(i)` (0xDA50) and the raw text of an argument. An argument whose expression has no defined engine value
/// reads as 0, like the oracle's `_Args.expr`. Variable operands (`C<n>`, `F<n>`) are the caller's concern:
/// the VM expands them before a statement reaches the stage.
public struct StageArgs {
    private let buf: ByteSpan
    private let ranges: [ArgRange]
    public let count: Int
    public let statement: Statement

    public init(_ statement: Statement) {
        self.statement = statement
        self.buf = statement.args
        var r = [ArgRange](repeating: ArgRange(start: 0, end: 0), count: ObjectParser.maxArguments)
        let (status, n) = ObjectParser.split(statement, into: &r)
        if status == .ok {
            self.count = n
        } else {
            self.count = 0
        }
        self.ranges = r
    }

    /// `has(i)`: the argument exists and is not empty.
    public func has(_ i: Int) -> Bool {
        ObjectParser.has(ranges, count, i)
    }

    /// `expr(i)`: the 32-bit value of the argument expression, 0 for an absent argument or an undefined expression.
    public func expr(_ i: Int) -> Int {
        guard has(i) else { return 0 }
        var v = 0
        var err = ExpressionError.none
        return ObjectExpression.tryEvaluate(ranges[i].slice(buf), value: &v, error: &err) ? v : 0
    }

    /// The argument text (ISO-8859-1), "" when absent.
    public func str(_ i: Int) -> String {
        guard i < count else { return "" }
        let slice = ranges[i].slice(buf)
        return String(slice.map { Character(UnicodeScalar($0)) })
    }

    /// An argument as the inline readers see it: present test of the statement's textual argument list.
    public func inlinePresent(_ i: Int) -> Bool {
        InlineReader.isPresent(statement, i)
    }

    /// The 16-bit inline value of argument `i`.
    public func inline16(_ i: Int) -> Int {
        InlineReader.readInt16(statement, i)
    }
}
