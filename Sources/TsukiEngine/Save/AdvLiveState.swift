import Foundation
import TsukiCore

extension HistoryRecord {
    /// +0x0058, 0x1A08 bytes, scene_state: a view of the SceneState in this block.
    public var sceneState: SceneState {
        SceneState(storage: storage, offset: offset + 0x0058)
    }

    /// +0x1A60, 0x1A08 bytes, scene_committed: a view of the SceneState in this block.
    public var sceneCommitted: SceneState {
        SceneState(storage: storage, offset: offset + 0x1A60)
    }
}

/// The "RAM side" of the history record: every live engine variable that `History_Push` (VA 0x7AF90) copies
/// into a record and `History_Restore` (VA 0x7C6D0) copies back (docs/formats/adv_state.md 2.1, 3). The PS4 code
/// reads and writes these at fixed addresses; the port keeps them in one object so that the history ring, the
/// interpreter (package K3) and the save code agree on what a record means. The interpreter either keeps its
/// own variables in this object, or copies them in before a push and out after a restore.
public final class AdvLiveState {
    /// Sound channels in the history record (loop SE ids, volume arrays, channel table).
    public static let soundChannels = 20

    /// Bytes of one entry of the channel table (RAM 0x16543F0).
    public static let channelEntrySize = 0x18

    /// Bytes of the current-message buffer (RAM 0x174D9B0, record +0x38FE): 0xF8 text bytes and two spare.
    public static let messageTextSize = 0xFA

    /// Bytes of the statement-text buffers of the kind-0 re-display (RAM 0x16537E0, 0x1653AF0).
    public static let redisplayBufferSize = 0x300

    /// Creates a state with new zeroed blocks (config at its boot defaults).
    public init() {
        self.vars = Vars()
        self.config = ConfigBlock.createBootDefaults()
        self.scene = SceneState()
        self.committed = SceneState()
        resetSound()
    }

    /// Creates a state over existing blocks (the interpreter's variables, the system block's config, the stage's scene copies).
    public init(vars: Vars, config: ConfigBlock, scene: SceneState, committed: SceneState) {
        self.vars = vars
        self.config = config
        self.scene = scene
        self.committed = committed
        resetSound()
    }

    /// The sound-array resets of Slot_Load (VA 0xA2DD8..0xA2EB0), also the state of a new game: no loop SEs (id -1), pitch word
    /// 100 on every channel, the other sound arrays and the channel table cleared (the table's entries get -1 in the fields the
    /// engine uses as "none"), no BGM.
    public func resetSound() {
        for i in 0..<AdvLiveState.soundChannels {
            loopSeIds[i] = -1
            seVolA[i] = 100
            seVolB[i] = 0
            seArrC[i] = 0
            seArrD[i] = 0
            seArrE[i] = 0
            let base = i * AdvLiveState.channelEntrySize
            channels[base] = 0
            channels[base + 1] = 0
            channels[base + 2] = 0
            channels[base + 3] = 0
            channels[base + 4] = 0xFF
            channels[base + 5] = 0xFF
            channels[base + 6] = 0
            channels[base + 7] = 0
            for j in 8..<16 {
                channels[base + j] = 0xFF
            }
            for j in 13..<21 {
                channels[base + j] = 0xFF
            }
            channels[base + 0x15] = 0
            channels[base + 0x16] = 0
            channels[base + 0x17] = 0
        }
        bgmTrack = -1
    }

    // -- blocks ------------------------------------------------------------------------------------------------

    /// F / Z / G (RAM 0x164B1D0). Push reads F; restore writes F (lists), a slot load clears F and Z.
    public let vars: Vars

    /// The live config (RAM 0x66C578; the system block's config). Push reads +0x04, restore writes it when +0x4C is set.
    public let config: ConfigBlock

    /// The script-side scene state (RAM 0x16500C0).
    public let scene: SceneState

    /// The committed scene copy (RAM 0x1651AC8).
    public let committed: SceneState

    // -- script position and text --------------------------------------------------------------------------------

    /// Current script number (RAM 0x86AA18). A restore of a record of another script sets it and asks for a reload.
    public var scriptNumber: UInt16 = 0

    /// script_ptr (RAM 0x16543B0) as an offset from the start of the decoded script. Restore sets it to the record's
    /// `cmdOffset` (the command runs again), or to `resumeOffset` for a rewind to a message.
    public var scriptOffset: UInt64 = 0

    /// Message block of the current text (RAM 0x1654344 as an i32; a record keeps the low word).
    public var textBlock: Int = 0

    /// Message line of the current text (RAM 0x1654348).
    public var textLine: Int = 0

    /// Copy of `textBlock` written by the kind-0 re-display (RAM 0x165434C).
    public var textBlock2: Int = 0

    /// Copy of `textLine` written by the kind-0 re-display (RAM 0x1654350).
    public var textLine2: Int = 0

    /// Speaker / name-colour index (RAM 0x164FCF6; a record keeps the low byte, restore sign-extends it).
    public var speaker: UInt16 = 0

    /// RAM 0x1654208 (a record keeps the low byte).
    public var var1654208: UInt16 = 0

    /// RAM 0x165420A (record +0x3641).
    public var var165420A: UInt16 = 0

    /// The current message text buffer (RAM 0x174D9B0, `messageTextSize` bytes).
    public var messageText: [UInt8] = [UInt8](repeating: 0, count: AdvLiveState.messageTextSize)

    /// RAM 0x174DAB0, 0x40 bytes (record +0x3468; meaning not traced).
    public var state174DAB0: [UInt8] = [UInt8](repeating: 0, count: 0x40)

    /// RAM 0x174D940 (record +0x34A8; meaning not traced).
    public var var174D940: UInt16 = 0

    /// RAM 0x16500BE (record +0x52).
    public var sceneWord: UInt16 = 0

    // -- sound -------------------------------------------------------------------------------------------------

    /// BGM track (RAM 0x16545D0), -1 = none.
    public var bgmTrack: Int16 = -1

    /// BGM volume word (RAM 0x1654238).
    public var bgmVolume: Int16 = 0

    /// Loop SE id per channel (RAM 0x1654240, i16[20]); -1 = none.
    public var loopSeIds: [Int16] = [Int16](repeating: 0, count: AdvLiveState.soundChannels)

    /// Per-channel word 0x1654270[i] (record keeps the low byte; the restore passes it as the SE pitch).
    public var seVolA: [UInt16] = [UInt16](repeating: 0, count: AdvLiveState.soundChannels)

    /// Per-channel word 0x16542A0[i] (record keeps the low byte; a loop SE restarts only while it is above 0).
    public var seVolB: [UInt16] = [UInt16](repeating: 0, count: AdvLiveState.soundChannels)

    /// i16[20] at RAM 0x16542D0 (passed to 0xA9E0 when a loop SE restarts).
    public var seArrC: [Int16] = [Int16](repeating: 0, count: AdvLiveState.soundChannels)

    /// i16[20] at RAM 0x1654300 (passed to 0xAA50 when a loop SE restarts).
    public var seArrD: [Int16] = [Int16](repeating: 0, count: AdvLiveState.soundChannels)

    /// u8[20] at RAM 0x1654330 (the volume of a restarted loop SE; see `AdvHistory.ps4StaleSeBytes`).
    public var seArrE: [UInt8] = [UInt8](repeating: 0, count: AdvLiveState.soundChannels)

    /// The channel table (RAM 0x16543F0, 20 x 0x18 bytes); push and restore move only some bytes of each entry.
    public var channels: [UInt8] = [UInt8](repeating: 0, count: AdvLiveState.soundChannels * AdvLiveState.channelEntrySize)

    /// The voice of the line (RAM 0x1654204; push stores -1 in the record, voice play stores the line's voice there).
    public var voiceId: Int32 = -1

    /// RAM 0x16541FC (written by every restore from the record's voice id; -1 after a kind-0 re-display).
    public var var16541FC: Int32 = -1

    /// RAM 0x1654200 (same rule as `var16541FC`).
    public var var1654200: Int32 = -1

    // -- message window ---------------------------------------------------------------------------------------

    /// Window state (RAM 0x164FD00, 0x32 bytes).
    public var window164FD00: [UInt8] = [UInt8](repeating: 0, count: 0x32)

    /// Name-plate state (RAM 0x164FD40, 0x1C bytes); a restore of a non-message record clears byte 0.
    public var window164FD40: [UInt8] = [UInt8](repeating: 0, count: 0x1C)

    /// Name-plate state after a kind-0 re-display moved it on (RAM 0x164FD60, 0x1C bytes).
    public var window164FD60: [UInt8] = [UInt8](repeating: 0, count: 0x1C)

    // -- flags written by a restore (wait model, re-display); mapped by the interpreter ------------------------------

    /// RAM 0x16541EC: 1 when the name plate has text (written together with `var16541F0`).
    public var var16541EC: Int = 0

    /// RAM 0x16541F0 (see `var16541EC`).
    public var var16541F0: Int = 0

    /// RAM 0x16541E4 (restore: sign-extended scene byte +0x19A4).
    public var var16541E4: Int = 0

    /// RAM 0x16541D8 (the kind-0 re-display sets it to 1).
    public var var16541D8: Int = 0

    /// RAM byte 0x16541F4. A push does nothing while it is set (`AdvHistory.push`); the kind-0 re-display
    /// sets it to 1 for a line ending in `@n` and clears it otherwise.
    public var var16541F4: UInt8 = 0

    /// RAM byte 0x174D9A8: "the line was re-displayed by a rewind". A push clears it, a kind-0 re-display sets it.
    public var restoredFromHistory: UInt8 = 0

    /// RAM byte 0x174DE00 (cleared by a kind-0 restore).
    public var var174DE00: UInt8 = 0

    /// RAM word 0x1653AE0: length of the re-displayed statement text (0 after any other restore step).
    public var redisplayLength: UInt16 = 0

    /// RAM dword 0x86AA24 (a kind-0 restore flushes pending effects when it is set and clears it).
    public var var86AA24: UInt32 = 0

    /// The text fade value (RAM 0x86AA1C), set to 1.0 by every restore.
    public var textFade: Float = 1.0

    /// RAM word 0x1750646 (cleared by every restore).
    public var word1750646: UInt16 = 0

    /// RAM dword 0x1653E24 (cleared by every restore).
    public var var1653E24: UInt32 = 0

    /// RAM qword 0x1653E00: the wait / pending-effect flag word of Adv_Update (wait_model.md).
    public var waitFlags: UInt64 = 0

    /// RAM qword 0x1653E70: second flag word (bit 0 is set by a kind-0 re-display).
    public var waitFlags70: UInt64 = 0

    /// RAM word 0x1653E08 (cleared by a re-display of a line ending in `@n`).
    public var word1653E08: UInt16 = 0

    /// RAM 0x16537E0: statement text of the kind-0 re-display (NUL-terminated unless it is 0x300 bytes long).
    public var redisplayText: [UInt8] = [UInt8](repeating: 0, count: AdvLiveState.redisplayBufferSize)

    /// RAM 0x1653AF0: a copy of `redisplayText`.
    public var redisplayCopy: [UInt8] = [UInt8](repeating: 0, count: AdvLiveState.redisplayBufferSize)

    // -- queries and gates the engine answers by calling other functions -----------------------------------------

    /// Scan mode (RAM byte 0x174DE48): pushes are suppressed while it is set.
    public var scanMode: UInt8 = 0

    /// Bit i = effect slot i is active (VA 0x5C660 for i < 14). A push stores it; a restore stops the slots that
    /// are active here and clear in the record (`RestoreOutcome.stopEffectSlots`).
    public var effectActiveBits: UInt16 = 0

    /// Bit i = effect slot i is blocking (VA 0x5C680: active and its motion flag 8 clear). A push stores it.
    public var effectBlockingBits: UInt16 = 0

    /// True when the last message of the page is shown (the WNTY word 0xDF08DC bit 0, read by VA 0x53620 at a push).
    public var lastMessageOfPage: Bool = false

    /// The "display end of page instantly" latch (VA 0x56140), read by the kind-0 re-display to decide the end code.
    public var pageEndInstantLatch: Bool = false

    // -- helpers -------------------------------------------------------------------------------------------------

    /// F[`index`] as an unsigned word.
    public func f(_ index: Int) -> UInt16 {
        vars.getWord(index)
    }

    /// F[`index`] as a signed word.
    public func fSigned(_ index: Int) -> Int16 {
        Int16(bitPattern: vars.getWord(index))
    }

    /// The F indices the history code reads or writes by name (adv_state.md 2.1, 3, 7.3).
    public enum FIndex {
        /// F823: message index of the page; the staging snapshot and the rewind stop need it <= 1.
        public static let pageMessage = 823

        /// F799: 1 = the last message of its page.
        public static let lastMessage = 799

        /// F929: while non-zero no history record is pushed.
        public static let pushBlock = 929

        /// F931: copied to scene +0x1984 by a kind-0 restore when not negative.
        public static let windowStyle = 931

        /// F967: scene-bound value, reset by the restore rule when it disagrees with scene +0x19A6.
        public static let sceneBase = 967

        /// F991: a layer change is pending (kind 1 pushed, kind 9 not yet).
        public static let layerPending = 991

        /// F995: its low byte is stored in scene +0x19A3 at every push.
        public static let low995 = 995

        /// F1102: while non-zero only kinds 0 and 11 are pushed.
        public static let onlyMessages = 1102

        /// F1118: set in manual and auto saves (Slot_Store).
        public static let savedMarker = 1118
    }
}
