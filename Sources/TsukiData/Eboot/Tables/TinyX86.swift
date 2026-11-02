import Foundation
import TsukiCore
import TsukiEngine

/// Reads `count` bytes at a virtual address of the analysed image (see `EbootReader.read`).
public typealias CodeReader = (_ va: Int, _ count: Int) throws -> ByteSpan

/// One store the interpreted code made. The interpreter never writes memory; it only logs the stores.
public struct X86Store: Equatable, Sendable {
    /// The effective address.
    public let address: Int
    /// 1, 2, 4 or 8 bytes.
    public let size: Int
    /// The stored value (zero extended to the store size).
    public let value: UInt64

    public init(address: Int, size: Int, value: UInt64) {
        self.address = address
        self.size = size
        self.value = value
    }
}

/// The state after `TinyX86.run` reached its `ret`.
public struct X86Result {
    /// The 16 general registers (rax, rcx, rdx, rbx, rsp, rbp, rsi, rdi, r8..r15).
    public let registers: [UInt64]
    /// The stores in program order.
    public let stores: [X86Store]

    /// The 32-bit return value (`eax`).
    public var eax: UInt32 { UInt32(truncatingIfNeeded: registers[0]) }
}

/// A tiny x86-64 interpreter for the two branch-only table functions of the eboot: the STMA loop switch (VA 0xC1C70) and the
/// flowchart-jump clears (VA 0xBA700). It supports exactly the instruction forms those functions use and throws on anything
/// else, so a different build fails loudly instead of being misread. Port of `tsuki.engine_tables.TinyX86`.
///
/// Supported: xor / add / cmp on registers and immediates, lea (SIB and rip-relative), movsxd, mov r32 imm32, mov [mem] imm
/// (16, 32, 64 bit), jcc rel8 / rel32, jmp rel8 / rel32 / r64, ret and the nop forms.
public final class TinyX86 {
    private static let rax = 0
    private static let rdi = 7

    private let read: CodeReader
    private var buffer = [UInt8](repeating: 0, count: 16)

    /// Creates an interpreter over a memory reader.
    public init(_ read: @escaping CodeReader) {
        self.read = read
    }

    private enum Op {
        case ret
        case nop
        case jcc
        case jmp
        case jmpReg
        case xor
        case add
        case cmp
        case lea
        case movsxd
        case movImm
        case storeImm
    }

    private struct Mem {
        var rip = false
        var base = 0
        var index = 0
        var scale = 0
        var disp = 0
    }

    private struct Insn {
        var op: Op
        var length: Int
        var cc: Int
        var rel: Int
        var dst: Int
        var src: Int
        var srcIsImm: Bool
        var imm: Int64
        var width: Int
        var mem: Mem
        var size: Int
    }

    /// Executes from `rip` until `ret` with `rdi` set (the argument of both functions).
    /// - Parameters:
    ///   - rip: The function's virtual address.
    ///   - rdi: First integer argument.
    ///   - maxSteps: An upper bound against runaway code.
    /// - Throws: `TsukiError.format` when an instruction is not supported, or the step limit was reached.
    public func run(_ rip: Int, _ rdi: UInt64 = 0, maxSteps: Int = 4096) throws -> X86Result {
        var r = [UInt64](repeating: 0, count: 16)
        r[Self.rdi] = rdi
        var stores: [X86Store] = []
        var zf = false, sf = false, cf = false, of = false
        var at = rip
        for _ in 0..<maxSteps {
            let ins = try decode(at)
            var next = at + ins.length
            switch ins.op {
            case .ret:
                return X86Result(registers: r, stores: stores)
            case .nop:
                break
            case .jcc:
                if try Self.condition(ins.cc, zf: zf, sf: sf, cf: cf, of: of) {
                    next += ins.rel
                }
            case .jmp:
                next += ins.rel
            case .jmpReg:
                next = Int(bitPattern: UInt(truncatingIfNeeded: r[ins.dst]))
            case .xor:
                let v = Self.value(r, ins.dst, ins.width) ^ Self.value(r, ins.src, ins.width)
                Self.set(&r, ins.dst, v, ins.width)
                zf = v == 0
                sf = ((v >> (ins.width - 1)) & 1) != 0
                cf = false
                of = false
            case .add, .cmp:
                let m: UInt64 = ins.width == 64 ? .max : 0xFFFF_FFFF
                let a = Self.value(r, ins.dst, ins.width)
                let b = ins.srcIsImm ? UInt64(bitPattern: ins.imm) & m : Self.value(r, ins.src, ins.width)
                let top = ins.width - 1
                if ins.op == .add {
                    let res = (a &+ b) & m
                    zf = res == 0
                    sf = ((res >> top) & 1) != 0
                    cf = res < a
                    of = (((~(a ^ b)) & (a ^ res)) >> top & 1) != 0
                    Self.set(&r, ins.dst, res, ins.width)
                } else {
                    let res = (a &- b) & m
                    zf = res == 0
                    sf = ((res >> top) & 1) != 0
                    cf = a < b
                    of = (((a ^ b) & (a ^ res)) >> top & 1) != 0
                }
            case .lea:
                let address = Self.effectiveAddress(ins.mem, r, next)
                Self.set(&r, ins.dst, UInt64(bitPattern: Int64(address)), ins.width)
            case .movsxd:
                let span = try read(Self.effectiveAddress(ins.mem, r, next), 4)
                r[ins.dst] = UInt64(bitPattern: Int64(span.i32(0)))
            case .movImm:
                Self.set(&r, ins.dst, UInt64(bitPattern: ins.imm), ins.width)
            case .storeImm:
                let v: UInt64
                if ins.size == 8 {
                    v = UInt64(bitPattern: ins.imm)
                } else {
                    v = UInt64(bitPattern: ins.imm) & ((UInt64(1) << (8 * ins.size)) - 1)
                }

                stores.append(X86Store(address: Self.effectiveAddress(ins.mem, r, next), size: ins.size, value: v))
            }

            at = next
        }

        throw TsukiError.format("TinyX86: step limit reached")
    }

    private static func value(_ r: [UInt64], _ reg: Int, _ width: Int) -> UInt64 {
        width == 64 ? r[reg] : r[reg] & 0xFFFF_FFFF
    }

    private static func set(_ r: inout [UInt64], _ reg: Int, _ v: UInt64, _ width: Int) {
        r[reg] = width == 64 ? v : v & 0xFFFF_FFFF
    }

    private static func effectiveAddress(_ m: Mem, _ r: [UInt64], _ next: Int) -> Int {
        if m.rip {
            return next &+ m.disp
        }

        var a = m.disp
        if m.base >= 0 {
            a &+= Int(bitPattern: UInt(truncatingIfNeeded: r[m.base]))
        }

        if m.index >= 0 {
            a &+= Int(bitPattern: UInt(truncatingIfNeeded: r[m.index])) &* m.scale
        }

        return a
    }

    private static func condition(_ cc: Int, zf: Bool, sf: Bool, cf: Bool, of: Bool) throws -> Bool {
        let baseValue: Bool
        switch cc >> 1 {
        case 0: baseValue = of
        case 1: baseValue = cf
        case 2: baseValue = zf
        case 3: baseValue = cf || zf
        case 4: baseValue = sf
        case 5: throw TsukiError.format("TinyX86: parity conditions are not used by these tables")
        case 6: baseValue = sf != of
        default: baseValue = zf || (sf != of)
        }

        return (cc & 1) != 0 ? !baseValue : baseValue
    }

    /// A little-endian u16 of the decode buffer.
    private func bufferU16(_ offset: Int) -> UInt16 {
        UInt16(buffer[offset]) | UInt16(buffer[offset + 1]) << 8
    }

    /// A little-endian i32 of the decode buffer.
    private func bufferI32(_ offset: Int) -> Int32 {
        let v = UInt32(buffer[offset])
            | UInt32(buffer[offset + 1]) << 8
            | UInt32(buffer[offset + 2]) << 16
            | UInt32(buffer[offset + 3]) << 24
        return Int32(bitPattern: v)
    }

    private func decode(_ rip: Int) throws -> Insn {
        let code = try read(rip, 16)
        code.withUnsafeBytes { src in
            buffer.withUnsafeMutableBytes { dst in
                dst.copyMemory(from: src)
            }
        }

        var i = 0
        var opsz16 = false
        while i < 16, buffer[i] == 0x66 {
            opsz16 = true
            i += 1
        }

        var rex = 0
        if i < 16, buffer[i] >= 0x40, buffer[i] <= 0x4F {
            rex = Int(buffer[i])
            i += 1
        }

        guard i < 16 else {
            throw TsukiError.format("TinyX86: truncated instruction at 0x\(Self.hexAddress(rip))")
        }

        let rexw = (rex & 8) != 0
        let rexr = (rex >> 2) & 1, rexx = (rex >> 1) & 1, rexb = rex & 1
        let op = Int(buffer[i])
        i += 1
        let width = rexw ? 64 : 32

        // Returns the reg field, and either the rm register (rmReg >= 0) or the memory operand.
        func displacement(_ mod: Int) -> Int {
            if mod == 1 {
                let d = Int(Int8(bitPattern: buffer[i]))
                i += 1
                return d
            }

            if mod == 2 {
                let d = Int(bufferI32(i))
                i += 4
                return d
            }

            return 0
        }

        func modRm() -> (reg: Int, rmReg: Int, mem: Mem) {
            let m = Int(buffer[i])
            i += 1
            let mod = m >> 6
            let reg = ((m >> 3) & 7) | (rexr << 3)
            let rm = m & 7
            if mod == 3 {
                return (reg, rm | (rexb << 3), Mem())
            }

            if rm == 4 {
                let sib = Int(buffer[i])
                i += 1
                let scale = 1 << (sib >> 6)
                let idx = ((sib >> 3) & 7) | (rexx << 3)
                let bas = (sib & 7) | (rexb << 3)
                let index = idx == 4 ? -1 : idx
                if (sib & 7) == 5, mod == 0 {
                    let d32 = Int(bufferI32(i))
                    i += 4
                    return (reg, -1, Mem(rip: false, base: -1, index: index, scale: scale, disp: d32))
                }

                return (reg, -1, Mem(rip: false, base: bas, index: index, scale: scale, disp: displacement(mod)))
            }

            if rm == 5, mod == 0 {
                let d32 = Int(bufferI32(i))
                i += 4
                return (reg, -1, Mem(rip: true, base: -1, index: -1, scale: 1, disp: d32))
            }

            return (reg, -1, Mem(rip: false, base: rm | (rexb << 3), index: -1, scale: 1, disp: displacement(mod)))
        }

        func make(
            _ o: Op, cc: Int = 0, rel: Int = 0, dst: Int = 0, src: Int = 0, srcImm: Bool = false,
            imm: Int64 = 0, width w: Int = 32, mem: Mem = Mem(), size: Int = 0
        ) -> Insn {
            Insn(op: o, length: i, cc: cc, rel: rel, dst: dst, src: src, srcIsImm: srcImm, imm: imm, width: w, mem: mem, size: size)
        }

        if op == 0xC3 {
            return make(.ret)
        }

        if op == 0x90 {
            return make(.nop)
        }

        if op >= 0x70, op <= 0x7F {
            let rel = Int(Int8(bitPattern: buffer[i]))
            i += 1
            return make(.jcc, cc: op & 15, rel: rel)
        }

        if op == 0x0F {
            let op2 = Int(buffer[i])
            i += 1
            if op2 >= 0x80, op2 <= 0x8F {
                let rel = Int(bufferI32(i))
                i += 4
                return make(.jcc, cc: op2 & 15, rel: rel)
            }

            if op2 == 0x1F {
                _ = modRm()
                return make(.nop)
            }

            throw TsukiError.format("TinyX86: opcode 0F \(Self.hexByte(op2)) at 0x\(Self.hexAddress(rip)) is not supported")
        }

        if op == 0xEB {
            let rel = Int(Int8(bitPattern: buffer[i]))
            i += 1
            return make(.jmp, rel: rel)
        }

        if op == 0xE9 {
            let rel = Int(bufferI32(i))
            i += 4
            return make(.jmp, rel: rel)
        }

        if op >= 0xB8, op <= 0xBF {
            let imm = Int64(UInt32(bitPattern: bufferI32(i)))
            i += 4
            return make(.movImm, dst: (op - 0xB8) | (rexb << 3), imm: imm, width: 32)
        }

        if op == 0x31 || op == 0x01 || op == 0x39 {
            let (reg, rmReg, _) = modRm()
            guard rmReg >= 0 else {
                throw TsukiError.format("TinyX86: memory operand of opcode \(Self.hexByte(op)) at 0x\(Self.hexAddress(rip)) is not supported")
            }

            let o: Op = op == 0x31 ? .xor : op == 0x01 ? .add : .cmp
            return make(o, dst: rmReg, src: reg, width: width)
        }

        if op == 0x81 || op == 0x83 {
            let (reg, rmReg, _) = modRm()
            let imm: Int64
            if op == 0x81 {
                imm = Int64(bufferI32(i))
                i += 4
            } else {
                imm = Int64(Int8(bitPattern: buffer[i]))
                i += 1
            }

            guard rmReg >= 0, (reg & 7) == 0 || (reg & 7) == 7 else {
                throw TsukiError.format("TinyX86: group-1 form at 0x\(Self.hexAddress(rip)) is not supported")
            }

            return make((reg & 7) == 0 ? .add : .cmp, dst: rmReg, srcImm: true, imm: imm, width: width)
        }

        if op == 0x3D {
            let imm = Int64(bufferI32(i))
            i += 4
            return make(.cmp, dst: Self.rax, srcImm: true, imm: imm, width: width)
        }

        if op == 0x8D {
            let (reg, rmReg, mem) = modRm()
            guard rmReg < 0 else {
                throw TsukiError.format("TinyX86: lea r,r at 0x\(Self.hexAddress(rip)) is not supported")
            }

            return make(.lea, dst: reg, width: width, mem: mem)
        }

        if op == 0x63, rexw {
            let (reg, rmReg, mem) = modRm()
            guard rmReg < 0 else {
                throw TsukiError.format("TinyX86: movsxd r,r at 0x\(Self.hexAddress(rip)) is not supported")
            }

            return make(.movsxd, dst: reg, mem: mem)
        }

        if op == 0xFF {
            let (reg, rmReg, _) = modRm()
            if (reg & 7) == 4, rmReg >= 0 {
                return make(.jmpReg, dst: rmReg)
            }

            throw TsukiError.format("TinyX86: opcode FF /\(reg & 7) at 0x\(Self.hexAddress(rip)) is not supported")
        }

        if op == 0xC7 {
            let (reg, rmReg, mem) = modRm()
            guard (reg & 7) == 0, rmReg < 0 else {
                throw TsukiError.format("TinyX86: opcode C7 form at 0x\(Self.hexAddress(rip)) is not supported")
            }

            if opsz16 {
                let imm16 = Int64(bufferU16(i))
                i += 2
                return make(.storeImm, imm: imm16, mem: mem, size: 2)
            }

            let imm32 = Int64(bufferI32(i))
            i += 4
            return make(.storeImm, imm: imm32, mem: mem, size: rexw ? 8 : 4)
        }

        throw TsukiError.format("TinyX86: opcode \(Self.hexByte(op)) at 0x\(Self.hexAddress(rip)) is not supported")
    }

    /// Hexadecimal digits of an address (callers write the `0x`).
    private static func hexAddress(_ value: Int) -> String {
        String(value, radix: 16)
    }

    private static func hexByte(_ value: Int) -> String {
        String(format: "%02X", value)
    }
}
