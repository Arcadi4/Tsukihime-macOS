import Foundation
import TsukiCore
import TsukiEngine

/// The STMA loop points (knife `motion_loops.rs`). The PS4 has no data table for them: the loop point of a motion id is a compiled
/// switch, `int loop_point(int id)` at VA 0xC1C70 (0 = no loop, 1 = loop the whole motion, n > 1 = loop from n ms;
/// docs/formats/layers.md 8.1). This type runs that function in `TinyX86` for every id 1..24192, which gives the 2,027 looping
/// motions of the retail build. Port of `tsuki.engine_tables.read_motion_loops`; the result equals the unicorn extraction in
/// samples/misc_layer_state_and_motions.
public struct MotionLoopTable: Sendable {
    /// The function's virtual address.
    public static let functionVa: Int = 0xC1C70

    /// The highest motion id.
    public static let maxMotionId: Int = 24192

    /// The looping motion ids with their loop point (ids without a loop are absent).
    public let loops: [Int: Int]

    public init(loops: [Int: Int]) {
        self.loops = loops
    }

    /// Evaluates the function for every motion id.
    public static func read(_ reader: EbootReader) throws -> MotionLoopTable {
        let cpu = TinyX86(reader.read)
        var loops: [Int: Int] = [:]
        let count = reader.layout.motionCount
        if count >= 1 {
            for id in 1...count {
                let v = try cpu.run(reader.layout.motionLoopFunction, UInt64(id)).eax
                if v != 0 {
                    guard v <= UInt32(Int32.max) else {
                        throw TsukiError.format("motion \(id): loop point 0x\(String(v, radix: 16)) overflows Int")
                    }

                    loops[id] = Int(v)
                }
            }
        }

        return MotionLoopTable(loops: loops)
    }

    /// The loop point of a motion id: 0 = no loop, 1 = the whole motion, n > 1 = from n ms.
    public func loopPoint(_ motionId: Int) -> Int {
        loops[motionId] ?? 0
    }
}

/// A (last column, F word) pair of `JumpClearTable`: a jump to a column at or before `lastRow` zeroes `word`.
public struct JumpClearPair: Equatable, Sendable {
    /// The last flowchart column the word is cleared at.
    public let lastRow: Int
    /// The F word number.
    public let word: Int

    public init(lastRow: Int, word: Int) {
        self.lastRow = lastRow
        self.word = word
    }
}

/// The F words the flowchart jump zeroes by column (knife `game.rs` `JUMP_CLEARS`, sub_95800): the PS4 function at VA 0xBA700
/// compares the column with 203, 184, 176, 161, ... and stores zero into chapter words F054..F074. Evaluated with `TinyX86`. Port of
/// `tsuki.engine_tables.read_jump_clears`.
public struct JumpClearTable: Sendable {
    /// The function's virtual address.
    public static let functionVa: Int = 0xBA700

    /// The F word array F000..F1199 (u16 each).
    public static let fWordsBase: Int = 0x164B1D0

    /// The last flowchart column (277 columns).
    public static let maxRow: Int = 276

    /// (last column, F word) pairs: a jump to a column at or before the last column zeroes the word. Sorted by descending
    /// column, then word.
    public let pairs: [JumpClearPair]

    public init(pairs: [JumpClearPair]) {
        self.pairs = pairs
    }

    /// The F word numbers the jump to column `row` zeroes.
    public static func wordsClearedAtRow(_ reader: EbootReader, row: Int) throws -> [Int] {
        let cpu = TinyX86(reader.read)
        var words: [Int] = []
        for store in try cpu.run(reader.layout.jumpClearFunction, UInt64(bitPattern: Int64(row))).stores {
            let off = store.address &- reader.layout.fWordsBase
            if store.value != 0 || off < 0 || (off & 1) != 0 {
                throw TsukiError.format(
                    "the jump-clear function at 0x\(String(reader.layout.jumpClearFunction, radix: 16)) stores "
                        + "0x\(String(store.value, radix: 16)) at 0x\(String(store.address, radix: 16)), "
                        + "not a zero into the F array")
            }

            for w in 0..<(store.size / 2) {
                words.append(off / 2 + w)
            }
        }

        return words
    }

    /// Evaluates the function for every column and derives the (last column, word) pairs.
    public static func read(_ reader: EbootReader) throws -> JumpClearTable {
        var rowsOf: [Int: [Int]] = [:]
        for row in 0...maxRow {
            for word in try wordsClearedAtRow(reader, row: row) {
                rowsOf[word, default: []].append(row)
            }
        }

        var pairs: [JumpClearPair] = []
        pairs.reserveCapacity(rowsOf.count)
        for (word, rows) in rowsOf {
            guard let last = rows.max() else { continue }
            guard rows.count == last + 1 else {
                throw TsukiError.format("F\(Self.wordName(word)) is not cleared for every column up to \(last)")
            }

            pairs.append(JumpClearPair(lastRow: last, word: word))
        }

        pairs.sort { a, b in
            a.lastRow != b.lastRow ? b.lastRow < a.lastRow : a.word < b.word
        }
        return JumpClearTable(pairs: pairs)
    }

    /// `F054`-style word name for messages.
    private static func wordName(_ word: Int) -> String {
        let digits = String(word)
        return String(repeating: "0", count: max(0, 3 - digits.count)) + digits
    }
}

/// The three -1-terminated `i16` lists of F word numbers that survive a flowchart jump or are saved in a history record: kept whole
/// (`words`), kept as a signed byte (`bytes`) and kept as a flag (`bits`). knife: `game.rs` `JUMP_KEEP_*` and `save_tables.rs`
/// `F_WORDS / F_BYTES / F_BITS`. The PS4 lists contain knife's numbers in the same order plus PS4-only variables (967 in the words
/// and bytes, 501 in the bytes, 500 in the bits). Port of `tsuki.engine_tables.read_flow_keep_lists`.
public struct FlowKeepLists: Sendable {
    /// Text VA of the flow-jump copy (words, bytes, bits), used by the functions at 0x2A080 and 0x2A1D0.
    public static let flowJumpVa: [Int] = [0x1A4250, 0x1A42A0, 0x1A4500]

    /// Text VA of the history-record copy (words, bytes, bits), used by History_Push / _Restore.
    public static let historyVa: [Int] = [0x2160E0, 0x2165F0, 0x216580]

    private static let limit = 1024

    /// F words kept whole.
    public let words: [Int]
    /// F words kept as a signed byte.
    public let bytes: [Int]
    /// F words kept as a flag.
    public let bits: [Int]

    public init(words: [Int], bytes: [Int], bits: [Int]) {
        self.words = words
        self.bytes = bytes
        self.bits = bits
    }

    /// Reads the flow-jump copy (`history` false) or the history-record copy (true).
    public static func read(_ reader: EbootReader, history: Bool = false) throws -> FlowKeepLists {
        let at = history ? reader.layout.historyKeepLists : reader.layout.flowJumpKeepLists
        guard at.count >= 3 else {
            throw TsukiError.format("the \(history ? "history" : "flow-jump") keep-list table has \(at.count) entries, not 3")
        }

        return FlowKeepLists(
            words: try readList(reader, at[0]),
            bytes: try readList(reader, at[1]),
            bits: try readList(reader, at[2]))
    }

    private static func readList(_ reader: EbootReader, _ va: Int) throws -> [Int] {
        var list: [Int] = []
        while true {
            let v = Int(try reader.i16(va + 2 * list.count))
            if v == -1 {
                return list
            }

            list.append(v)
            if list.count > limit {
                throw TsukiError.format("the list at 0x\(String(va, radix: 16)) has no terminator")
            }
        }
    }
}
