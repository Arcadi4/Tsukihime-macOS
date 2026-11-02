import Foundation
import TsukiCore

/// The script variables (vm_variables.md 2.1): var_F u16[1200], var_Z u16[1400] and var_G u16[2000],
/// contiguous as on the PS4, with the F / G / C operand index arithmetic of vm_variables.md 2.2.
public final class Vars: StateBlock {
    /// Size of the block in bytes (0x23F0).
    public static let size = 0x23F0

    /// Number of F variables (var_F u16[1200]).
    public static let fCount = 1200
    /// Number of Z variables (var_Z u16[1400]).
    public static let zCount = 1400
    /// Number of G variables (var_G u16[2000]).
    public static let gCount = 2000
    /// Word index of Z[0] in the block (F[1200 + i] = Z[i]).
    public static let zWord = 1200
    /// Word index of G[0] in the block (F[2600 + i] = Z[1400 + i] = G[i]).
    public static let gWord = 2600
    /// Number of u16 words in the block.
    public static let wordCount = 4600
    /// VA of var_F (word 0).
    public static let fVa = 0x164B1D0
    /// VA of var_Z.
    public static let zVa = 0x164BB30
    /// VA of var_G.
    public static let gVa = 0x164C620
    /// F823: message counter of the page; `C<n>` = F[F823 + n] (vm_variables.md 2.3).
    public static let messageIndexVar = 823

    /// Every byte of the block in exactly one field, in offset order.
    public static let fields: [StateField] = [
        StateField(name: "F", oracleName: "var_F", offset: 0x0000, size: 0x960,
                   kind: .array, type: "u16", count: 1200),
        StateField(name: "Z", oracleName: "var_Z", offset: 0x0960, size: 0xAF0,
                   kind: .array, type: "u16", count: 1400),
        StateField(name: "G", oracleName: "var_G", offset: 0x1450, size: 0xFA0,
                   kind: .array, type: "u16", count: 2000),
    ]

    /// Creates a zeroed block.
    public init() {
        super.init(size: Vars.size)
    }

    /// Creates a view of the `size` bytes of storage at `offset` (shared, not copied).
    public init(storage: ByteStorage, offset: Int = 0) {
        super.init(storage: storage, offset: offset, length: Vars.size)
    }

    /// A copy of the block in a new array.
    public func clone() -> Vars {
        let copy = Vars()
        copy.copy(from: self)
        return copy
    }

    /// True when word index `word` (0 = F[0]) lies in the block.
    public static func inBlock(_ word: Int) -> Bool {
        word >= 0 && word < wordCount
    }

    /// Word index of the operand `F<n>`: the engine adds 2 * s16(n) to var_F with no bounds check
    /// (vm_variables.md 2.2), so `F1200` is Z[0], `F65535` is the word before F[0] (-1) and
    /// `F70000` is G[1864]. The result can lie outside the block.
    public static func fWordOfOperand(_ n: Int) -> Int {
        Int(Int16(truncatingIfNeeded: n))
    }

    /// Word index of the operand `G<n>`: var_G + 2 * s16(n) (`G-1` is Z[1399], `G2000` is outside).
    public static func gWordOfOperand(_ n: Int) -> Int {
        gWord + Int(Int16(truncatingIfNeeded: n))
    }

    /// Word index of the target `C<n>` of `_WKST` / `_WKAD` while F823 = `f823`: var_F + 2 * (s16(F823) +
    /// s16(n)), a 64-bit sum with no clamp (vm_variables.md 2.2; tsuki.vm_vars.target_address).
    public static func cWordOfOperand(_ f823: UInt16, _ n: Int) -> Int {
        Int(Int16(bitPattern: f823)) + Int(Int16(truncatingIfNeeded: n))
    }

    /// The engine VA of word `word`.
    public static func vaOfWord(_ word: Int) -> Int {
        fVa + 2 * word
    }

    /// The word index of an engine VA inside the block (even addresses only).
    public static func tryWordOfVa(_ va: Int, _ word: inout Int) -> Bool {
        let d = va - fVa
        if d >= 0 && d < 2 * wordCount && (d & 1) == 0 {
            word = d >> 1
            return true
        }
        word = -1
        return false
    }

    /// Word `word` of the block (0 = F[0]); traps outside the block.
    public func getWord(_ word: Int) -> UInt16 {
        readU16(2 * StateBlock.checkIndex(word, Vars.wordCount))
    }

    /// Sets word `word` of the block; traps outside the block.
    public func setWord(_ word: Int, _ value: UInt16) {
        writeU16(2 * StateBlock.checkIndex(word, Vars.wordCount), value)
    }

    /// F[`index`]; indices 1200..4599 reach Z and G as on the PS4.
    public func getF(_ index: Int) -> UInt16 { getWord(index) }

    /// Sets F[`index`] (aliasing as in `getF`).
    public func setF(_ index: Int, _ value: UInt16) { setWord(index, value) }

    /// Z[`index`] (negative indices reach F, indices from 1400 reach G).
    public func getZ(_ index: Int) -> UInt16 { getWord(Vars.zWord + index) }

    /// Sets Z[`index`].
    public func setZ(_ index: Int, _ value: UInt16) { setWord(Vars.zWord + index, value) }

    /// G[`index`] (negative indices reach Z and F).
    public func getG(_ index: Int) -> UInt16 { getWord(Vars.gWord + index) }

    /// Sets G[`index`].
    public func setG(_ index: Int, _ value: UInt16) { setWord(Vars.gWord + index, value) }

    /// Word index of `C<n>` with the current F823.
    public func cWord(_ n: Int) -> Int { Vars.cWordOfOperand(getF(Vars.messageIndexVar), n) }

    /// The value of `C<n>` = F[F823 + n].
    public func getC(_ n: Int) -> UInt16 { getWord(cWord(n)) }

    /// Sets `C<n>` = F[F823 + n].
    public func setC(_ n: Int, _ value: UInt16) { setWord(cWord(n), value) }
}
