import Foundation
import TsukiCore

/// Why `ObjectExpression.tryEvaluate` has no value: the cases where the PS4 code would crash or return stack garbage.
public enum ExpressionError: UInt8, Sendable {
    /// No error.
    case none = 0
    /// Division or remainder by zero, or INT_MIN / -1 (an `idiv` fault).
    case divisionFault = 1
    /// A unary operator without an operand.
    case unaryWithoutOperand = 2
    /// A binary operator without two operands.
    case binaryWithoutOperands = 3
    /// The evaluation stack is empty at the end.
    case emptyStack = 4
    /// A tokenizer stop inside `{...}`: the engine dereferences address 1.
    case insideBraces = 5
}

/// The expression evaluator behind the integer getters of the object parser (eboot text VA 0xDA50 with the tokenizer
/// at VA 0xDE30; docs/formats/script.md 3.3a). Port of `tsuki.script.obj_expr`; the reference was checked against the
/// eboot's own code under emulation on all 35,474 distinct retail argument texts.
///
/// A C-like expression over decimal numbers with the operators `+ - * / % << >> < <= > >= == != & ^ | && || ! ~`,
/// 32-bit signed wrap-around arithmetic, `{}` for grouping (the round brackets delimit arguments) and
/// **right-associative** chains of equal precedence: `10-3-2` is 9. The tokenizer stops without error at the first
/// byte it does not know (`242.25` is 242, `img1728` is 0, `0x10` is 0, a tag `` `017:100 `` is 0), keeping what it has
/// already emitted but not the pending operators (`5-` is 5).
public enum ObjectExpression {
    // Operator codes of the tokenizer: high nibble 2 = unary, 3 = binary; the next nibble is the precedence level
    // (lower binds tighter).
    private static let unaryPlus = 0x2200_0001
    private static let unaryNegate = 0x2200_0002
    private static let unaryNot = 0x2200_0003
    private static let unaryComplement = 0x2200_0004
    private static let mul = 0x3300_0001
    private static let div = 0x3300_0002
    private static let mod = 0x3300_0003
    private static let add = 0x3400_0001
    private static let sub = 0x3400_0002
    private static let shl = 0x3500_0001
    private static let shr = 0x3500_0002
    private static let lt = 0x3600_0001
    private static let le = 0x3600_0002
    private static let gt = 0x3600_0003
    private static let ge = 0x3600_0004
    private static let eq = 0x3700_0001
    private static let ne = 0x3700_0002
    private static let bitAnd = 0x3800_0001
    private static let bitXor = 0x3900_0001
    private static let bitOr = 0x3A00_0001
    private static let logicalAnd = 0x3B00_0001
    private static let logicalOr = 0x3C00_0001

    private static let operandMarker = 0x1000_0000

    private static let stop = -1
    private static let braceError = -2

    /// Evaluates one argument text; false (with the reason in `error`) where the engine has no defined value.
    public static func tryEvaluate(_ arg: ByteSpan, value: inout Int, error: inout ExpressionError) -> Bool {
        value = 0
        error = .none
        var tokenizer = Tokenizer(arg)
        let r = tokenizer.run(0, 0)
        if r == braceError {
            error = .insideBraces
            return false
        }

        // r == stop: the tokenizer stopped at an unknown byte; what was emitted so far is evaluated.
        let tokens = tokenizer.tokens
        if tokens.isEmpty {
            return true
        }

        var stack: [Int32] = []
        stack.reserveCapacity((arg.count / 2) + 4)
        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            if t == operandMarker {
                stack.append(Int32(truncatingIfNeeded: tokens[i + 1]))
                i += 2
                continue
            }

            let kind = t >> 28
            if kind == 2 {
                if stack.isEmpty {
                    error = .unaryWithoutOperand
                    return false
                }

                let x = stack[stack.count - 1]
                switch t {
                case unaryNegate:
                    stack[stack.count - 1] = 0 &- x
                case unaryNot:
                    stack[stack.count - 1] = x == 0 ? 1 : 0
                case unaryComplement:
                    stack[stack.count - 1] = ~x
                default:
                    stack[stack.count - 1] = x
                }
            } else if kind == 3 {
                if stack.count < 2 {
                    error = .binaryWithoutOperands
                    return false
                }

                let b = stack.removeLast()
                let a = stack[stack.count - 1]
                var result: Int32 = 0
                if !apply(t, a, b, &result) {
                    error = .divisionFault
                    return false
                }
                stack[stack.count - 1] = result
            }
            i += 1
        }

        if stack.isEmpty {
            error = .emptyStack
            return false
        }

        value = Int(stack[stack.count - 1])
        return true
    }

    /// Evaluates one argument text; nil where the engine has no defined value.
    public static func evaluate(_ arg: ByteSpan) -> Int? {
        var value = 0
        var error = ExpressionError.none
        return tryEvaluate(arg, value: &value, error: &error) ? value : nil
    }

    private static func apply(_ code: Int, _ a: Int32, _ b: Int32, _ result: inout Int32) -> Bool {
        switch code {
        case mul:
            result = a &* b
        case div, mod:
            if b == 0 || (a == Int32.min && b == -1) {
                return false
            }
            result = code == div ? a / b : a % b
        case add:
            result = a &+ b
        case sub:
            result = a &- b
        case shl:
            result = a << Int(b & 31)
        case shr:
            result = a >> Int(b & 31)
        case lt:
            result = a < b ? 1 : 0
        case le:
            result = a <= b ? 1 : 0
        case gt:
            result = a > b ? 1 : 0
        case ge:
            result = a >= b ? 1 : 0
        case eq:
            result = a == b ? 1 : 0
        case ne:
            result = a != b ? 1 : 0
        case bitAnd:
            result = a & b
        case bitXor:
            result = a ^ b
        case bitOr:
            result = a | b
        case logicalAnd:
            result = a != 0 && b != 0 ? 1 : 0
        case logicalOr:
            result = (a | b) != 0 ? 1 : 0
        default:
            result = a
        }
        return true
    }

    private static func level(_ code: Int) -> Int {
        (code >> 24) & 0xF
    }

    /// VA 0xDE30: a shunting-yard over the argument bytes producing postfix tokens (an operand is the marker followed
    /// by its value). One operator stack is shared by the nesting levels; a level only touches the entries above its
    /// base.
    private struct Tokenizer {
        private let s: ByteSpan
        private var out: [Int] = []
        private var ops: [Int] = []

        init(_ s: ByteSpan) {
            self.s = s
            out.reserveCapacity(2 * s.count + 4)
            ops.reserveCapacity(s.count + 5)
        }

        /// The tokens emitted so far.
        var tokens: [Int] { out }

        private func at(_ i: Int) -> UInt8 {
            i >= 0 && i < s.count ? s[i] : 0
        }

        /// Tokenizes from `p` up to the terminator `term`. Returns the position where it stopped, `stop` at an
        /// unknown byte (pending operators are abandoned), or `braceError` when a stop happened inside `{...}`.
        mutating func run(_ start: Int, _ term: UInt8) -> Int {
            let baseOps = ops.count
            var p = start
            var c = at(p)
            if c == 0 || c == term || p >= s.count {
                return finish(baseOps, p)
            }

            var after = false // false: expecting an operand; true: just after an operand
            while true {
                c = at(p)
                if after && (c == 0 || c == term || p >= s.count) {
                    return finish(baseOps, p)
                }

                if c >= 0x30 && c <= 0x39 {
                    let v = strtol10(&p)
                    out.append(operandMarker)
                    out.append(Int(Int32(truncatingIfNeeded: v)))
                    after = true
                    continue
                }

                if c == 0x7B { // '{'
                    let r = run(p + 1, 0x7D)
                    if r < 0 {
                        return braceError
                    }
                    p = r + 1
                    after = true
                    continue
                }

                if s.count - p < 2 {
                    return stop // an operator as the last byte: stop without flushing
                }

                let next = at(p + 1)
                let code: Int
                switch c {
                case 0x21: // '!'
                    code = next == 0x3D ? ne : unaryNot
                    if next == 0x3D { p += 1 }
                case 0x25: // '%'
                    code = mod
                case 0x26: // '&'
                    code = next == 0x26 ? logicalAnd : bitAnd
                    if next == 0x26 { p += 1 }
                case 0x2A: // '*'
                    code = mul
                case 0x2B: // '+'
                    code = after ? add : unaryPlus
                case 0x2D: // '-'
                    code = after ? sub : unaryNegate
                case 0x2F: // '/'
                    code = div
                case 0x3C: // '<'
                    code = next == 0x3D ? le : next == 0x3C ? shl : lt
                    if next == 0x3D || next == 0x3C { p += 1 }
                case 0x3D: // '='
                    if next != 0x3D {
                        return stop // a lone '='
                    }
                    code = eq
                    p += 1
                case 0x3E: // '>'
                    code = next == 0x3D ? ge : next == 0x3E ? shr : gt
                    if next == 0x3D || next == 0x3E { p += 1 }
                case 0x5E: // '^'
                    code = bitXor
                case 0x7C: // '|'
                    code = next == 0x7C ? logicalOr : bitOr
                    if next == 0x7C { p += 1 }
                case 0x7E: // '~'
                    code = unaryComplement
                default:
                    return stop // any other byte (letters, '.', '`', space, '(', ...)
                }

                let opLevel = level(code)
                while ops.count > baseOps && opLevel > level(ops[ops.count - 1]) {
                    out.append(ops.removeLast())
                }

                ops.append(code)
                p += 1
                c = at(p)
                if c == 0 || c == term || p >= s.count {
                    return finish(baseOps, p)
                }

                after = false
            }
        }

        private mutating func finish(_ baseOps: Int, _ p: Int) -> Int {
            while ops.count > baseOps {
                out.append(ops.removeLast())
            }
            return p
        }

        /// C `strtol(s + p, &end, 10)` for a string that starts with a digit (the only way VA 0xDE30 calls it): the
        /// value clamped to a 64-bit long; `p` moves to the end of the digits.
        private mutating func strtol10(_ p: inout Int) -> Int64 {
            var v: UInt64 = 0
            let cap = UInt64(Int64.max)
            while p < s.count && s[p] >= 0x30 && s[p] <= 0x39 {
                let d = UInt64(s[p] - 0x30)
                v = v <= (cap - d) / 10 ? (v * 10) + d : cap
                p += 1
            }
            return Int64(v)
        }
    }
}
