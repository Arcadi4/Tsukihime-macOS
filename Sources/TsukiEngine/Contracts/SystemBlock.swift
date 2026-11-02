import Foundation
import TsukiCore

/// The persistent system block (0x18AC bytes, save image offset 0, staging RAM 0x1201660): config, G[0..499],
/// unlock bits, readmax, latest slot (adv_state.md 7.5; engine.md 7.3).
///
/// The config block at +0x0004 is part of the field map; its typed view arrives with the config port, so this
/// block exposes it as bytes only.
public final class SystemBlock: StateBlock {
    /// Size of the block in bytes (0x18AC).
    public static let size = 0x18AC

    /// The magic word at +0 (and at the start of every stored block): 0x2AF8.
    public static let magicValue: UInt16 = 0x2AF8

    /// Number of entries of G.
    public static let gCount = 500
    /// Number of bits of UnlockBit.
    public static let unlockBitCount = 4192
    /// Number of entries of Readmax.
    public static let readmaxCount = 4020
    /// Number of entries of ChoiceTaken.
    public static let choiceTakenCount = 280

    /// picture_seen occupies unlock bits 0..3199 (gallery.md 2.2).
    public static let pictureSeenBits = 3200
    /// bgm_heard(track) is unlock bit 0xC80 + track (gallery.md 2, `_MPLY` 0x87250).
    public static let bgmHeardFirstBit = 0xC80
    /// bgm_heard covers tracks 0..0x207.
    public static let bgmHeardTracks = 0x208

    /// Every byte of the block in exactly one field, in offset order.
    public static let fields: [StateField] = [
        StateField(name: "Magic", oracleName: "system+0x0", offset: 0x0000, size: 0x2,
                   kind: .scalar, type: "u16"),
        StateField(name: "Used", oracleName: "system+0x2", offset: 0x0002, size: 0x2,
                   kind: .scalar, type: "u16"),
        StateField(name: "Config", oracleName: "system+0x4", offset: 0x0004, size: 0x140,
                   kind: .block, type: "ConfigBlock"),
        StateField(name: "G", oracleName: "system+0x144", offset: 0x0144, size: 0x3E8,
                   kind: .array, type: "u16", count: 500),
        StateField(name: "UnlockBit", oracleName: "system+0x52C", offset: 0x052C, size: 0x20C,
                   kind: .bits, type: "bit", count: 4192),
        StateField(name: "Readmax", oracleName: "system+0x738", offset: 0x0738, size: 0xFB4,
                   kind: .array, type: "u8", count: 4020),
        StateField(name: "Unused16EC", oracleName: "system+0x16EC", offset: 0x16EC, size: 0x2,
                   kind: .unused, type: "bytes"),
        StateField(name: "LatestSlot", oracleName: "system+0x16EE", offset: 0x16EE, size: 0x2,
                   kind: .scalar, type: "u16"),
        StateField(name: "Unused16F0", oracleName: "system+0x16F0", offset: 0x16F0, size: 0x2,
                   kind: .unused, type: "bytes"),
        StateField(name: "Word16F2", oracleName: "system+0x16F2", offset: 0x16F2, size: 0x2,
                   kind: .scalar, type: "u16"),
        StateField(name: "ChoiceTaken", oracleName: "system+0x16F4", offset: 0x16F4, size: 0x118,
                   kind: .array, type: "u8", count: 280),
        StateField(name: "Unused180C", oracleName: "system+0x180C", offset: 0x180C, size: 0xA0,
                   kind: .unused, type: "bytes"),
    ]

    /// Creates a zeroed block.
    public init() {
        super.init(size: SystemBlock.size)
    }

    /// Creates a view of the `size` bytes of storage at `offset` (shared, not copied).
    public init(storage: ByteStorage, offset: Int = 0) {
        super.init(storage: storage, offset: offset, length: SystemBlock.size)
    }

    /// A copy of the block in a new array.
    public func clone() -> SystemBlock {
        let copy = SystemBlock()
        copy.copy(from: self)
        return copy
    }

    /// +0x0000 u16 system+0x0: u16 magic 0x2AF8 (stamped by SaveImage_WriteBlock).
    public var magic: UInt16 {
        get { readU16(0x0000) }
        set { writeU16(0x0000, newValue) }
    }

    /// +0x0002 u16 system+0x2: u16 = 1 (written by 0x6FEC0; the loader requires != 0).
    public var used: UInt16 {
        get { readU16(0x0002) }
        set { writeU16(0x0002, newValue) }
    }

    /// +0x0144, u16 x 500, system+0x144[index]: G variables G[0..499], persistent script flags.
    public func getG(_ index: Int) -> UInt16 {
        readU16(0x0144 + 2 * StateBlock.checkIndex(index, SystemBlock.gCount))
    }

    /// Sets system+0x144[`index`].
    public func setG(_ index: Int, _ value: UInt16) {
        writeU16(0x0144 + 2 * StateBlock.checkIndex(index, SystemBlock.gCount), value)
    }

    /// +0x052C, bit `bit` of system+0x52C (bit k = byte k / 8, bit k % 8): the unlock block right after var_G.
    public func getUnlockBit(_ bit: Int) -> Bool {
        getBit(0x052C, StateBlock.checkIndex(bit, SystemBlock.unlockBitCount))
    }

    /// Sets bit `bit` of system+0x52C.
    public func setUnlockBit(_ bit: Int, _ value: Bool) {
        setBit(0x052C, StateBlock.checkIndex(bit, SystemBlock.unlockBitCount), value)
    }

    /// picture_seen(`seenIndex`); false for a negative index (gallery.md: picture_seen(-1) is false).
    public func isPictureSeen(_ seenIndex: Int) -> Bool {
        seenIndex >= 0 && seenIndex < SystemBlock.pictureSeenBits && getUnlockBit(seenIndex)
    }

    /// Sets picture_seen(`seenIndex`); traps outside 0..<3200.
    public func setPictureSeen(_ seenIndex: Int, _ value: Bool) {
        setUnlockBit(StateBlock.checkIndex(seenIndex, SystemBlock.pictureSeenBits), value)
    }

    /// bgm_heard(`track`), track 0..0x207; false outside.
    public func isBgmHeard(_ track: Int) -> Bool {
        track >= 0 && track < SystemBlock.bgmHeardTracks
            && getUnlockBit(SystemBlock.bgmHeardFirstBit + track)
    }

    /// Sets bgm_heard(`track`); traps outside 0..<0x208.
    public func setBgmHeard(_ track: Int, _ value: Bool) {
        setUnlockBit(SystemBlock.bgmHeardFirstBit + StateBlock.checkIndex(track, SystemBlock.bgmHeardTracks), value)
    }

    /// +0x0738, u8 x 4020, system+0x738[index]: readmax[4020], highest read line per text block (engine.md 5.6).
    public func getReadmax(_ index: Int) -> UInt8 {
        readU8(0x0738 + StateBlock.checkIndex(index, SystemBlock.readmaxCount))
    }

    /// Sets system+0x738[`index`].
    public func setReadmax(_ index: Int, _ value: UInt8) {
        writeU8(0x0738 + StateBlock.checkIndex(index, SystemBlock.readmaxCount), value)
    }

    /// +0x16EE u16 system+0x16EE: index of the most recent slot (for 'Continue'; <= 0x8A when used).
    public var latestSlot: UInt16 {
        get { readU16(0x16EE) }
        set { writeU16(0x16EE, newValue) }
    }

    /// +0x16F2 u16 system+0x16F2: u16 copied from RAM 0x1202F16; meaning unknown.
    public var word16F2: UInt16 {
        get { readU16(0x16F2) }
        set { writeU16(0x16F2, newValue) }
    }

    /// +0x16F4, u8 x 280, system+0x16F4[index]: unknown block; the loader ORs +0x16F4..+0x1803 into RAM and reads
    /// +0x1804..+0x180B bytewise.
    public func getChoiceTaken(_ index: Int) -> UInt8 {
        readU8(0x16F4 + StateBlock.checkIndex(index, SystemBlock.choiceTakenCount))
    }

    /// Sets system+0x16F4[`index`].
    public func setChoiceTaken(_ index: Int, _ value: UInt8) {
        writeU8(0x16F4 + StateBlock.checkIndex(index, SystemBlock.choiceTakenCount), value)
    }

    /// choice_taken: bit `option` of byte `choiceId` (gallery.md 2, choice screen 0xA6647).
    public func isChoiceTaken(_ choiceId: Int, _ option: Int) -> Bool {
        (getChoiceTaken(choiceId) >> UInt8(StateBlock.checkIndex(option, 8))) & 1 != 0
    }
}
