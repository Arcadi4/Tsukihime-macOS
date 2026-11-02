import Foundation
import TsukiCore

extension SystemBlock {
    /// The live config block stored at system block +0x0004.
    public var config: ConfigBlock {
        ConfigBlock(storage: storage, offset: offset + 0x0004)
    }
}

/// The persistent system data (the PS4 system block, 0x18AC bytes; adv_state.md 7.5, engine.md 7.3): the config, the
/// persistent G variables G[0..499], the unlock bit sets (pictures seen, BGM heard), the read-text table, the latest
/// slot and the choice-taken bytes. The game keeps the live copies of all but G and the config in RAM and merges them
/// into the block when it saves; here the block is the one copy, so the unlock bits, readmax and choice-taken bytes
/// are read and written on it directly, and only G needs the explicit sync with the interpreter's variables
/// (`loadGlobalsInto` at start-up, `captureGlobalsFrom` before a save).
public final class SystemData {
    /// The highest text block that readmax records (blocks 0xFB4 and above are never recorded; engine.md 5.6).
    public static let readmaxBlocks = SystemBlock.readmaxCount

    /// The persistent G variables (G[0..499]).
    public static let persistentGlobals = SystemBlock.gCount

    /// Creates fresh system data: magic and used flag set, the config at its boot defaults, the rest zero.
    public init() {
        self.block = SystemData.createFreshBlock()
    }

    /// Wraps an existing block (read from a save file); the block is not copied.
    public init(_ block: SystemBlock) {
        self.block = block
    }

    /// The block (the layout of save image offset 0).
    public let block: SystemBlock

    /// The configuration (the live one: pass it to `AdvLiveState`).
    public var config: ConfigBlock {
        block.config
    }

    /// The slot "Continue" loads: the newest manual or auto save (updated by `SaveStore`).
    public var latestSlot: Int {
        Int(block.latestSlot)
    }

    private static func createFreshBlock() -> SystemBlock {
        let block = SystemBlock()
        block.magic = SystemBlock.magicValue
        block.used = 1
        block.config.copy(from: ConfigBlock.createBootDefaults())
        return block
    }

    // -- read text (adv_state.md 6; engine.md 5.6) -------------------------------------------------------------------------

    /// "Is this line read" (VA 0x75C90): `readmax[block] != 0 and (line <= readmax[block] or block >= 0xFB4)`.
    /// Blocks outside 0..0xFFF read as unread.
    public func isRead(_ block: Int, _ line: Int) -> Bool {
        guard block >= 0 && block < SystemData.readmaxBlocks else {
            return false
        }
        let max = Int(self.block.getReadmax(block))
        return max != 0 && line <= max
    }

    /// Labeled overload for `isRead`.
    public func isRead(block: Int, line: Int) -> Bool {
        isRead(block, line)
    }

    /// The Z handler's read mark (VA 0x96615): before it switches to a new label, the previous one counts as read:
    /// `if line > readmax[block] and block <= 0xFB3: readmax[block] = line` (the value is a byte).
    public func markRead(_ block: Int, _ line: Int) {
        guard block >= 0 && block < SystemData.readmaxBlocks else {
            return
        }
        if line > Int(self.block.getReadmax(block)) {
            self.block.setReadmax(block, UInt8(min(line, 255)))
        }
    }

    /// Labeled overload for `markRead`.
    public func markRead(block: Int, line: Int) {
        markRead(block, line)
    }

    // -- G variables ------------------------------------------------------------------------------------------------------

    /// Boot / load: G[0..499] of the interpreter's variables take the saved values (VA 0x6F470).
    public func loadGlobalsInto(_ vars: Vars) {
        for i in 0..<SystemData.persistentGlobals {
            vars.setG(i, block.getG(i))
        }
    }

    /// Before a save: the block takes G[0..499] of the interpreter's variables (VA 0x6FF2D).
    public func captureGlobalsFrom(_ vars: Vars) {
        for i in 0..<SystemData.persistentGlobals {
            block.setG(i, vars.getG(i))
        }
    }

    /// The load fix-up of config +0x24 (VA 0x6FE94): a negative language (the boot value 0xFFFF) becomes the system
    /// language (0 ja, 1 en, 2 zc, 3 zt).
    public func applyLanguageFixup(_ systemLanguage: Int) {
        if config.language < 0 {
            config.language = Int16(systemLanguage)
        }
    }

    // -- progress flags (docs/formats/gallery.md 2.1): bit sets that live in G words -----------------------------------------

    /// First G word of the scene_seen set (G[110..145]).
    public static let sceneSeenWord = 110

    /// First G word of the scene_done set (G[300..335]).
    public static let sceneDoneWord = 300

    /// First G word of the edge_seen set (G[400..443]); bit n - 564.
    public static let edgeSeenWord = 400

    /// The G word whose low 16 bits are the movie_seen flags (G[5]).
    public static let movieSeenWord = 5

    /// scene_seen(n), n at most 0x23F (the bit set of G[110..145]): the scene was started at least once (reads the interpreter's variables).
    public static func sceneSeen(_ vars: Vars, _ n: Int) -> Bool {
        getWordBit(vars, sceneSeenWord, n, 0x23F)
    }

    /// scene_done(n), n at most 0x23F (G[300..335]): the scene was finished (gates the flowchart nodes and the gallery).
    public static func sceneDone(_ vars: Vars, _ n: Int) -> Bool {
        getWordBit(vars, sceneDoneWord, n, 0x23F)
    }

    /// edge_seen(n), 564 <= n <= 1267 (G[400..443]): the flowchart edge was taken.
    public static func edgeSeen(_ vars: Vars, _ n: Int) -> Bool {
        n >= 564 && n <= 1267 && getWordBit(vars, edgeSeenWord, n - 564, 0xFFFF)
    }

    /// movie_seen(bit): bit 0..15 of G[5].
    public static func movieSeen(_ vars: Vars, _ bit: Int) -> Bool {
        bit >= 0 && bit < 16 && getWordBit(vars, movieSeenWord, bit, 15)
    }

    /// Sets scene_seen(n).
    public static func setSceneSeen(_ vars: Vars, _ n: Int) {
        setWordBit(vars, sceneSeenWord, n, 0x23F)
    }

    /// Sets scene_done(n).
    public static func setSceneDone(_ vars: Vars, _ n: Int) {
        setWordBit(vars, sceneDoneWord, n, 0x23F)
    }

    /// Sets edge_seen(n).
    public static func setEdgeSeen(_ vars: Vars, _ n: Int) {
        if n >= 564 && n <= 1267 {
            setWordBit(vars, edgeSeenWord, n - 564, 0xFFFF)
        }
    }

    /// Sets movie_seen(bit).
    public static func setMovieSeen(_ vars: Vars, _ bit: Int) {
        if bit >= 0 && bit < 16 {
            setWordBit(vars, movieSeenWord, bit, 15)
        }
    }

    private static func getWordBit(_ vars: Vars, _ firstWord: Int, _ n: Int, _ max: Int) -> Bool {
        if n < 0 || n > max {
            return false
        }
        let w = firstWord + (n >> 4)
        return ((Int(vars.getG(w)) >> (n & 15)) & 1) != 0
    }

    private static func setWordBit(_ vars: Vars, _ firstWord: Int, _ n: Int, _ max: Int) {
        if n < 0 || n > max {
            return
        }
        let w = firstWord + (n >> 4)
        vars.setG(w, vars.getG(w) | UInt16(1 << (n & 15)))
    }

    /// Marks picture `seenIndex` as seen (the gallery CG unlock; gallery.md 2.2). Indices outside 0..3199 are ignored.
    public func markPictureSeen(_ seenIndex: Int) {
        if seenIndex >= 0 && seenIndex < SystemBlock.pictureSeenBits {
            block.setPictureSeen(seenIndex, true)
        }
    }

    /// Marks BGM `track` as heard (the music player unlock). Tracks outside 0..0x207 are ignored.
    public func markBgmHeard(_ track: Int) {
        if track >= 0 && track < SystemBlock.bgmHeardTracks {
            block.setBgmHeard(track, true)
        }
    }

    /// Records that option `option` (0..7) of choice `choiceId` was taken (byte choiceId, bit option).
    public func markChoiceTaken(_ choiceId: Int, _ option: Int) {
        if choiceId >= 0 && choiceId < SystemBlock.choiceTakenCount && option >= 0 && option < 8 {
            let current = block.getChoiceTaken(choiceId)
            block.setChoiceTaken(choiceId, current | UInt8(1 << option))
        }
    }
}
