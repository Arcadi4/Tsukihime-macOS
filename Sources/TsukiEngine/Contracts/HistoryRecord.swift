import Foundation
import TsukiCore

/// One history record (0x3A10 bytes): the state before a state-changing command, used by the history ring, the
/// scene stack and both states of a save slot (adv_state.md 2.1).
///
/// The two `SceneState` views at +0x0058 and +0x1A60 arrive with the scene-state port; this block keeps their
/// bytes and the field map entries.
public final class HistoryRecord: StateBlock {
    /// Size of the block in bytes (0x3A10).
    public static let size = 0x3A10

    /// Every byte of the block in exactly one field, in offset order.
    public static let fields: [StateField] = [
        StateField(name: "RingIndex", oracleName: "ring_index", offset: 0x0000, size: 0x4,
                   kind: .scalar, type: "i32"),
        StateField(name: "Serial", oracleName: "serial", offset: 0x0004, size: 0x4,
                   kind: .scalar, type: "i32"),
        StateField(name: "CmdOffset", oracleName: "cmd_offset", offset: 0x0008, size: 0x8,
                   kind: .scalar, type: "u64"),
        StateField(name: "ResumeOffset", oracleName: "resume_offset", offset: 0x0010, size: 0x8,
                   kind: .scalar, type: "u64"),
        StateField(name: "Script", oracleName: "script", offset: 0x0018, size: 0x2,
                   kind: .scalar, type: "u16"),
        StateField(name: "TextBlock", oracleName: "text_block", offset: 0x001A, size: 0x2,
                   kind: .scalar, type: "i16"),
        StateField(name: "TextLine", oracleName: "text_line", offset: 0x001C, size: 0x2,
                   kind: .scalar, type: "i16"),
        StateField(name: "Speaker", oracleName: "speaker", offset: 0x001E, size: 0x1,
                   kind: .scalar, type: "i8"),
        StateField(name: "Var1654208", oracleName: "var_1654208", offset: 0x001F, size: 0x1,
                   kind: .scalar, type: "i8"),
        StateField(name: "Unused20", oracleName: "unused_20", offset: 0x0020, size: 0x4,
                   kind: .unused, type: "bytes"),
        StateField(name: "Kind", oracleName: "mode", offset: 0x0024, size: 0x2,
                   kind: .scalar, type: "u16"),
        StateField(name: "BgmTrack", oracleName: "bgm_track", offset: 0x0026, size: 0x2,
                   kind: .scalar, type: "i16"),
        StateField(name: "LoopSeIds", oracleName: "loop_se_ids", offset: 0x0028, size: 0x28,
                   kind: .array, type: "i16", count: 20),
        StateField(name: "Unused50", oracleName: "unused_50", offset: 0x0050, size: 0x2,
                   kind: .unused, type: "bytes"),
        StateField(name: "SceneWord", oracleName: "scene_word", offset: 0x0052, size: 0x2,
                   kind: .scalar, type: "u16"),
        StateField(name: "Unused54", oracleName: "unused_54", offset: 0x0054, size: 0x4,
                   kind: .unused, type: "bytes"),
        StateField(name: "SceneState", oracleName: "scene_state", offset: 0x0058, size: 0x1A08,
                   kind: .block, type: "SceneState"),
        StateField(name: "SceneCommitted", oracleName: "scene_committed", offset: 0x1A60, size: 0x1A08,
                   kind: .block, type: "SceneState"),
        StateField(name: "State174DAB0", oracleName: "state_174dab0", offset: 0x3468, size: 0x40,
                   kind: .bytes, type: "bytes"),
        StateField(name: "Var174D940", oracleName: "var_174d940", offset: 0x34A8, size: 0x2,
                   kind: .scalar, type: "u16"),
        StateField(name: "FU16", oracleName: "f_u16", offset: 0x34AA, size: 0x4E,
                   kind: .array, type: "u16", count: 39),
        StateField(name: "Unused34F8", oracleName: "unused_34f8", offset: 0x34F8, size: 0x2,
                   kind: .unused, type: "bytes"),
        StateField(name: "FBoolBit", oracleName: "f_bool_bits", offset: 0x34FA, size: 0x6,
                   kind: .bits, type: "bit", count: 43),
        StateField(name: "Unused3500", oracleName: "unused_3500", offset: 0x3500, size: 0x1,
                   kind: .unused, type: "bytes"),
        StateField(name: "FS8", oracleName: "f_s8", offset: 0x3501, size: 0x12C,
                   kind: .array, type: "i8", count: 300),
        StateField(name: "Unused362D", oracleName: "unused_362d", offset: 0x362D, size: 0x3,
                   kind: .unused, type: "bytes"),
        StateField(name: "VoiceId", oracleName: "voice_id", offset: 0x3630, size: 0x4,
                   kind: .scalar, type: "i32"),
        StateField(name: "VoiceCharacter", oracleName: "voice_character", offset: 0x3634, size: 0x2,
                   kind: .scalar, type: "i16"),
        StateField(name: "EffectActiveBits", oracleName: "effect_active_bits", offset: 0x3636, size: 0x2,
                   kind: .scalar, type: "u16"),
        StateField(name: "EffectBlockingBits", oracleName: "effect_blocking_bits", offset: 0x3638, size: 0x2,
                   kind: .scalar, type: "u16"),
        StateField(name: "Flags363A", oracleName: "flags_363a", offset: 0x363A, size: 0x2,
                   kind: .scalar, type: "u16"),
        StateField(name: "BgmVolume", oracleName: "bgm_volume", offset: 0x363C, size: 0x2,
                   kind: .scalar, type: "i16"),
        StateField(name: "Config04", oracleName: "config_04", offset: 0x363E, size: 0x2,
                   kind: .scalar, type: "u16"),
        StateField(name: "Var3640", oracleName: "var_3640", offset: 0x3640, size: 0x1,
                   kind: .scalar, type: "u8"),
        StateField(name: "Var165420A", oracleName: "var_165420a", offset: 0x3641, size: 0x1,
                   kind: .scalar, type: "i8"),
        StateField(name: "SeVolA", oracleName: "se_vol_a", offset: 0x3642, size: 0x14,
                   kind: .array, type: "i8", count: 20),
        StateField(name: "Unused3656", oracleName: "unused_3656", offset: 0x3656, size: 0x1,
                   kind: .unused, type: "bytes"),
        StateField(name: "SeVolB", oracleName: "se_vol_b", offset: 0x3657, size: 0x14,
                   kind: .array, type: "i8", count: 20),
        StateField(name: "Unused366B", oracleName: "unused_366b", offset: 0x366B, size: 0x1,
                   kind: .unused, type: "bytes"),
        StateField(name: "SeArrC", oracleName: "se_arr_c", offset: 0x366C, size: 0x28,
                   kind: .array, type: "i16", count: 20),
        StateField(name: "SeArrD", oracleName: "se_arr_d", offset: 0x3694, size: 0x28,
                   kind: .array, type: "i16", count: 20),
        StateField(name: "SeArrEStale", oracleName: "se_arr_e_stale", offset: 0x36BC, size: 0x14,
                   kind: .array, type: "u8", count: 20),
        StateField(name: "Channel", oracleName: "channels", offset: 0x36D0, size: 0x1E0,
                   kind: .array, type: "bytes", count: 20),
        StateField(name: "Window164FD00", oracleName: "window_164fd00", offset: 0x38B0, size: 0x32,
                   kind: .bytes, type: "bytes"),
        StateField(name: "Window164FD40", oracleName: "window_164fd40", offset: 0x38E2, size: 0x1C,
                   kind: .bytes, type: "bytes"),
        StateField(name: "MessageText", oracleName: "message_text", offset: 0x38FE, size: 0xFA,
                   kind: .bytes, type: "bytes"),
        StateField(name: "Unused39F8", oracleName: "unused_39f8", offset: 0x39F8, size: 0x18,
                   kind: .unused, type: "bytes"),
    ]

    /// F indices kept exactly (u16) in `getFU16`, entry k = F[fU16Indices[k]] (eboot list VA 0x2160E0, 39
    /// entries). Restore order u16, s8, bool: an index in two lists ends with the later list's value
    /// (adv_state.md 2.1; tsuki.vm_vars.HISTORY_*).
    public static let fU16Indices: [Int] = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 22, 991, 985, 954, 967, 966, 965,
        964, 931, 932, 933, 934, 935, 936, 937, 938, 939, 859, 860, 861, 862, 863, 864,
        865, 866, 867, 868, 869, 110, 1122,
    ]

    /// F indices kept as a bit (value != 0) in `getFBoolBit`, bit k = F[fBoolIndices[k]] (eboot list VA
    /// 0x216580, 43 entries). Restore order u16, s8, bool.
    public static let fBoolIndices: [Int] = [
        998, 997, 996, 994, 993, 991, 992, 988, 987, 986, 984, 822, 1103, 1104, 929, 983,
        975, 460, 500, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66,
        67, 68, 69, 70, 71, 72, 73, 74, 1118, 1123, 28,
    ]

    /// F indices kept as their low byte (restored sign-extended) in `getFS8`, entry k = F[fS8Indices[k]]
    /// (eboot list VA 0x2165F0, 276 entries; the list ends at the first negative entry).
    public static let fS8Indices: [Int] = [
        298, 1100, 989, 982, 967, 963, 962, 1101, 981, 799, 800, 801, 802, 803, 804, 805,
        806, 807, 808, 809, 810, 811, 812, 813, 814, 815, 816, 817, 818, 819, 820, 821,
        823, 824, 825, 826, 827, 828, 829, 830, 831, 832, 833, 834, 835, 836, 837, 838,
        839, 840, 841, 842, 843, 844, 845, 846, 847, 848, 849, 850, 851, 852, 853, 854,
        855, 856, 857, 858, 870, 871, 872, 873, 874, 875, 876, 877, 878, 879, 880, 23,
        50, 51, 52, 53, 75, 76, 77, 78, 79, 80, 81, 24, 25, 26, 27, 31,
        32, 33, 1105, 1106, 1107, 1108, 1110, 1111, 1112, 1113, 1109, 501, 100, 101, 1098, 201,
        202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217,
        218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233,
        234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249,
        250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260, 261, 262, 263, 264, 265,
        266, 267, 268, 269, 270, 271, 272, 199, 200, 995, 600, 601, 602, 603, 604, 605,
        606, 607, 608, 609, 610, 611, 612, 613, 614, 615, 616, 617, 618, 619, 620, 621,
        622, 623, 624, 625, 626, 627, 628, 629, 630, 631, 632, 633, 634, 635, 636, 637,
        638, 639, 640, 641, 642, 643, 644, 645, 646, 647, 648, 649, 650, 651, 652, 653,
        654, 655, 656, 657, 658, 659, 660, 661, 662, 663, 664, 665, 666, 667, 668, 669,
        670, 671, 672, 673, 674, 675, 676, 677, 678, 679, 680, 681, 682, 683, 684, 685,
        686, 687, 1120, 1121,
    ]

    /// Creates a zeroed block.
    public init() {
        super.init(size: HistoryRecord.size)
    }

    /// Creates a view of the `size` bytes of storage at `offset` (shared, not copied).
    public init(storage: ByteStorage, offset: Int = 0) {
        super.init(storage: storage, offset: offset, length: HistoryRecord.size)
    }

    /// A copy of the block in a new array.
    public func clone() -> HistoryRecord {
        let copy = HistoryRecord()
        copy.copy(from: self)
        return copy
    }

    /// +0x0000 i32 ring_index: written by the ring/scene clear loops with the record's own index.
    public var ringIndex: Int32 {
        get { readI32(0x0000) }
        set { writeI32(0x0000, newValue) }
    }

    /// +0x0004 i32 serial: (i16) of the history counter before it is advanced; the following ring record gets -1.
    public var serial: Int32 {
        get { readI32(0x0004) }
        set { writeI32(0x0004, newValue) }
    }

    /// +0x0008 u64 cmd_offset: start of the pushing command in the decoded script.
    public var cmdOffset: UInt64 {
        get { readU64(0x0008) }
        set { writeU64(0x0008, newValue) }
    }

    /// +0x0010 u64 resume_offset: second pointer argument (text lines pass the position after the message).
    public var resumeOffset: UInt64 {
        get { readU64(0x0010) }
        set { writeU64(0x0010, newValue) }
    }

    /// +0x0018 u16 script.
    public var script: UInt16 {
        get { readU16(0x0018) }
        set { writeU16(0x0018, newValue) }
    }

    /// +0x001A i16 text_block.
    public var textBlock: Int16 {
        get { readI16(0x001A) }
        set { writeI16(0x001A, newValue) }
    }

    /// +0x001C i16 text_line.
    public var textLine: Int16 {
        get { readI16(0x001C) }
        set { writeI16(0x001C, newValue) }
    }

    /// +0x001E i8 speaker.
    public var speaker: Int8 {
        get { readI8(0x001E) }
        set { writeI8(0x001E, newValue) }
    }

    /// +0x001F i8 var_1654208.
    public var var1654208: Int8 {
        get { readI8(0x001F) }
        set { writeI8(0x001F, newValue) }
    }

    /// +0x0024 u16 mode (HISTORY_MODES).
    public var kind: UInt16 {
        get { readU16(0x0024) }
        set { writeU16(0x0024, newValue) }
    }

    /// +0x0026 i16 bgm_track.
    public var bgmTrack: Int16 {
        get { readI16(0x0026) }
        set { writeI16(0x0026, newValue) }
    }

    /// Number of entries of LoopSeIds.
    public static let loopSeIdsCount = 20

    /// +0x0028, i16 x 20, loop_se_ids[index].
    public func getLoopSeIds(_ index: Int) -> Int16 {
        readI16(0x0028 + 2 * StateBlock.checkIndex(index, HistoryRecord.loopSeIdsCount))
    }

    /// Sets loop_se_ids[index].
    public func setLoopSeIds(_ index: Int, _ value: Int16) {
        writeI16(0x0028 + 2 * StateBlock.checkIndex(index, HistoryRecord.loopSeIdsCount), value)
    }

    /// +0x0052 u16 scene_word.
    public var sceneWord: UInt16 {
        get { readU16(0x0052) }
        set { writeU16(0x0052, newValue) }
    }

    /// +0x3468, 0x40 bytes, state_174dab0.
    public var state174DAB0: ByteSpan { slice(0x3468, 0x40).span }

    /// +0x34A8 u16 var_174d940.
    public var var174D940: UInt16 {
        get { readU16(0x34A8) }
        set { writeU16(0x34A8, newValue) }
    }

    /// Number of entries of FU16.
    public static let fU16Count = 39

    /// +0x34AA, u16 x 39, f_u16[index]: exact copy of F[fU16Indices[index]].
    public func getFU16(_ index: Int) -> UInt16 {
        readU16(0x34AA + 2 * StateBlock.checkIndex(index, HistoryRecord.fU16Count))
    }

    /// Sets f_u16[index].
    public func setFU16(_ index: Int, _ value: UInt16) {
        writeU16(0x34AA + 2 * StateBlock.checkIndex(index, HistoryRecord.fU16Count), value)
    }

    /// Number of bits of FBoolBit.
    public static let fBoolBitCount = 43

    /// +0x34FA, bit `bit` of f_bool_bits (bit k = byte k / 8, bit k % 8): bit k = (F[fBoolIndices[k]] != 0).
    public func getFBoolBit(_ bit: Int) -> Bool {
        getBit(0x34FA, StateBlock.checkIndex(bit, HistoryRecord.fBoolBitCount))
    }

    /// Sets bit `bit` of f_bool_bits.
    public func setFBoolBit(_ bit: Int, _ value: Bool) {
        setBit(0x34FA, StateBlock.checkIndex(bit, HistoryRecord.fBoolBitCount), value)
    }

    /// Number of entries of FS8.
    public static let fS8Count = 300

    /// +0x3501, i8 x 300, f_s8[index]: low byte of F[fS8Indices[index]] (276 used, +0x3501..+0x3614).
    public func getFS8(_ index: Int) -> Int8 {
        readI8(0x3501 + StateBlock.checkIndex(index, HistoryRecord.fS8Count))
    }

    /// Sets f_s8[index].
    public func setFS8(_ index: Int, _ value: Int8) {
        writeI8(0x3501 + StateBlock.checkIndex(index, HistoryRecord.fS8Count), value)
    }

    /// +0x3630 i32 voice_id.
    public var voiceId: Int32 {
        get { readI32(0x3630) }
        set { writeI32(0x3630, newValue) }
    }

    /// +0x3634 i16 voice_character.
    public var voiceCharacter: Int16 {
        get { readI16(0x3634) }
        set { writeI16(0x3634, newValue) }
    }

    /// +0x3636 u16 effect_active_bits: bit i = effect slot i active.
    public var effectActiveBits: UInt16 {
        get { readU16(0x3636) }
        set { writeU16(0x3636, newValue) }
    }

    /// +0x3638 u16 effect_blocking_bits.
    public var effectBlockingBits: UInt16 {
        get { readU16(0x3638) }
        set { writeU16(0x3638, newValue) }
    }

    /// +0x363A u16 flags_363a: bit 0 = WNTY (last message of the page), other bits 0.
    public var flags363A: UInt16 {
        get { readU16(0x363A) }
        set { writeU16(0x363A, newValue) }
    }

    /// +0x363C i16 bgm_volume.
    public var bgmVolume: Int16 {
        get { readI16(0x363C) }
        set { writeI16(0x363C, newValue) }
    }

    /// +0x363E u16 config_04.
    public var config04: UInt16 {
        get { readU16(0x363E) }
        set { writeU16(0x363E, newValue) }
    }

    /// +0x3640 u8 var_3640.
    public var var3640: UInt8 {
        get { readU8(0x3640) }
        set { writeU8(0x3640, newValue) }
    }

    /// +0x3641 i8 var_165420a.
    public var var165420A: Int8 {
        get { readI8(0x3641) }
        set { writeI8(0x3641, newValue) }
    }

    /// Number of entries of SeVolA.
    public static let seVolACount = 20

    /// +0x3642, i8 x 20, se_vol_a[index].
    public func getSeVolA(_ index: Int) -> Int8 {
        readI8(0x3642 + StateBlock.checkIndex(index, HistoryRecord.seVolACount))
    }

    /// Sets se_vol_a[index].
    public func setSeVolA(_ index: Int, _ value: Int8) {
        writeI8(0x3642 + StateBlock.checkIndex(index, HistoryRecord.seVolACount), value)
    }

    /// Number of entries of SeVolB.
    public static let seVolBCount = 20

    /// +0x3657, i8 x 20, se_vol_b[index].
    public func getSeVolB(_ index: Int) -> Int8 {
        readI8(0x3657 + StateBlock.checkIndex(index, HistoryRecord.seVolBCount))
    }

    /// Sets se_vol_b[index].
    public func setSeVolB(_ index: Int, _ value: Int8) {
        writeI8(0x3657 + StateBlock.checkIndex(index, HistoryRecord.seVolBCount), value)
    }

    /// Number of entries of SeArrC.
    public static let seArrCCount = 20

    /// +0x366C, i16 x 20, se_arr_c[index].
    public func getSeArrC(_ index: Int) -> Int16 {
        readI16(0x366C + 2 * StateBlock.checkIndex(index, HistoryRecord.seArrCCount))
    }

    /// Sets se_arr_c[index].
    public func setSeArrC(_ index: Int, _ value: Int16) {
        writeI16(0x366C + 2 * StateBlock.checkIndex(index, HistoryRecord.seArrCCount), value)
    }

    /// Number of entries of SeArrD.
    public static let seArrDCount = 20

    /// +0x3694, i16 x 20, se_arr_d[index].
    public func getSeArrD(_ index: Int) -> Int16 {
        readI16(0x3694 + 2 * StateBlock.checkIndex(index, HistoryRecord.seArrDCount))
    }

    /// Sets se_arr_d[index].
    public func setSeArrD(_ index: Int, _ value: Int16) {
        writeI16(0x3694 + 2 * StateBlock.checkIndex(index, HistoryRecord.seArrDCount), value)
    }

    /// Number of entries of SeArrEStale.
    public static let seArrEStaleCount = 20

    /// +0x36BC, u8 x 20, se_arr_e_stale[index]: copied record -> RAM on every push (engine bug: the live array
    /// is overwritten with stale ring bytes).
    public func getSeArrEStale(_ index: Int) -> UInt8 {
        readU8(0x36BC + StateBlock.checkIndex(index, HistoryRecord.seArrEStaleCount))
    }

    /// Sets se_arr_e_stale[index].
    public func setSeArrEStale(_ index: Int, _ value: UInt8) {
        writeU8(0x36BC + StateBlock.checkIndex(index, HistoryRecord.seArrEStaleCount), value)
    }

    /// Number of entries of Channel.
    public static let channelCount = 20

    /// +0x36D0, 20 x 0x18 bytes, channels: entry `index` (bytes +0..+2, +4..+5, +8..+0x15 are copied).
    public func channel(_ index: Int) -> ByteSpan {
        slice(0x36D0 + 24 * StateBlock.checkIndex(index, HistoryRecord.channelCount), 0x18).span
    }

    /// +0x38B0, 0x32 bytes, window_164fd00.
    public var window164FD00: ByteSpan { slice(0x38B0, 0x32).span }

    /// +0x38E2, 0x1C bytes, window_164fd40.
    public var window164FD40: ByteSpan { slice(0x38E2, 0x1C).span }

    /// +0x38FE, 0xFA bytes, message_text.
    public var messageText: ByteSpan { slice(0x38FE, 0xFA).span }
}
