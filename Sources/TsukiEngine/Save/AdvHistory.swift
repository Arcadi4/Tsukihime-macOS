import Foundation
import TsukiCore

/// Loads the decoded bytes of a script (the text the history record's command offsets point into). Only a rewind to a
/// message needs it, to copy the statement text out for the re-display (adv_state.md 3.2).
public typealias ScriptBytesProvider = (UInt16) -> [UInt8]

/// The history ring of 800 `HistoryRecord`s, the scene stack of 300, the slot staging and the counters the
/// PS4 keeps around them (docs/formats/adv_state.md 2-5, 7.1). `push` is History_Push (VA 0x7AF90),
/// `restore` is History_Restore (VA 0x7C6D0); rewind, previous scene, backlog and slot loading are in
/// `AdvHistoryNavigation.swift`. The class holds records and indices only: every live engine variable a record
/// captures lives in an `AdvLiveState` that the caller passes in.
public final class AdvHistory {
    /// Records in the ring (the PS4 allocates 808 and wraps at 800; VA 0x7B44C).
    public static let ringCount = 800

    /// Records in the scene stack (300; SceneStack_Push shifts the stack down when it is full).
    public static let sceneStackCount = 300

    /// The highest F index the history lists use (the PS4 skips larger entries; 0x4B0).
    public static let maxListedF = 0x4B0

    /// The record kinds of adv_state.md 2.3.
    public enum Kinds {
        /// A message marker (`_ZM`): the rewind target and backlog entry.
        public static let message: UInt16 = 0

        /// The first layer change since the last commit.
        public static let layerChange: UInt16 = 1

        /// Music commands.
        public static let music: UInt16 = 2

        /// Sound-effect commands.
        public static let soundEffect: UInt16 = 3

        /// Scene start (`_ATSV`).
        public static let sceneStart: UInt16 = 6

        /// Choice save point (`_ATSV(1)`).
        public static let choiceSavePoint: UInt16 = 7

        /// Never pushed in v01.01; the backlog still lists it.
        public static let unused8: UInt16 = 8

        /// Commit point of a pending layer change.
        public static let commit: UInt16 = 9

        /// Never pushed in v01.01; the backlog still lists it.
        public static let unused11: UInt16 = 11

        /// Choice start (`_SELD`).
        public static let choiceStart: UInt16 = 12

        /// Choice line (`_SELR`).
        public static let choiceLine: UInt16 = 13
    }

    private var ring: [HistoryRecord?] = [HistoryRecord?](repeating: nil, count: AdvHistory.ringCount)
    private var stack: [HistoryRecord?] = [HistoryRecord?](repeating: nil, count: AdvHistory.sceneStackCount)

    /// Creates an empty history (equal to the state after the PS4 ring clear at boot).
    public init() {
        self.staging = SlotImage()
    }

    // -- indices (RAM 0x120A6E8..0x120A6F2, 0x164B1C0, 0x174DE04/08) ---------------------------------------------------

    /// The i16 serial counter (RAM 0x120A6EA): the serial of the next pushed record.
    public var serialCounter: Int16 = 0

    /// Index of the newest record (RAM 0x120A6EC, "cur").
    public var cur: Int = 0

    /// Index the next push writes (RAM 0x120A6EE).
    public var next: Int = 0

    /// True once the ring has wrapped (RAM 0x120A6F0).
    public var wrapped: Bool = false

    /// Index of the oldest valid record once the ring is full (RAM 0x120A6F2).
    public var oldest: Int = 0

    /// The record the rewind is positioned on (RAM 0x120A6E8); follows `cur` while not rewinding.
    public var rewindCursor: Int = 0

    /// Scene-stack top index, -1 = empty (RAM 0x164B1C0).
    public var stackTop: Int = -1

    /// Messages left before the scene counts as started (RAM 0x174DE04): 2 right after a scene start, 0 after a load,
    /// down by one per message marker (the interpreter calls `onMessageShown`).
    public var sceneMessageCounter: Int = 0

    /// The "just loaded" word (RAM 0x174DE08): 1 right after a slot load, 2 after a scene restore, cleared by `_ATSV`.
    public var afterLoad: Int = 0

    /// The slot staging (RAM 0x12031E0): the save image of the current page, kept current while playing (adv_state.md 7.1).
    public let staging: SlotImage

    /// When true, a push reproduces the PS4 bug of record +0x36BC (adv_state.md 2.1): the live bytes 0x1654330 take the
    /// ring slot's old bytes and the record keeps them. The default saves the live bytes in the record, as a port should.
    /// The oracle tests set it.
    public var ps4StaleSeBytes: Bool = false

    /// The pending scene-jump request (RAM 0x16541F8): 1 = next scene, -1 = previous scene, 0 = none. Set by
    /// `requestSceneJump` after the confirmation dialog and consumed by `takeSceneJumpRequest`.
    public internal(set) var sceneJumpRequest: Int = 0

    /// True while the next-scene skip runs (RAM 0x120A6D2): Adv_Update runs Script_Step in a loop with every wait cleared until a
    /// command ends the skip (`_ATSV`, an unread or flagged message, `_JUMP`, `_RDED` / `_RTMN` / `_RTM_`, `_TOMP`,
    /// `_END_`, `_SELD`; adv_state.md 5.2). The interpreter sets it when it takes a next-scene request.
    public var nextSceneRunning: Bool = false

    // -- records -------------------------------------------------------------------------------------------------

    /// The ring record `index` (0..799), created cleared on first use.
    public func record(_ index: Int) -> HistoryRecord {
        precondition(index >= 0 && index < AdvHistory.ringCount, "ring index must be in 0..\(AdvHistory.ringCount - 1), got \(index)")
        if let r = ring[index] {
            return r
        }
        let r = AdvHistory.newClearedRecord(index)
        ring[index] = r
        return r
    }

    /// The newest record (`cur`).
    public var newest: HistoryRecord {
        record(cur)
    }

    /// The scene-stack record `index` (0..299).
    public func stackRecord(_ index: Int) -> HistoryRecord {
        precondition(index >= 0 && index < AdvHistory.sceneStackCount, "scene stack index must be in 0..\(AdvHistory.sceneStackCount - 1), got \(index)")
        if let r = stack[index] {
            return r
        }
        let r = HistoryRecord()
        stack[index] = r
        return r
    }

    /// The scene-stack top record, or nil when the stack is empty.
    public var stackTopRecord: HistoryRecord? {
        stackTop >= 0 ? stackRecord(stackTop) : nil
    }

    private static func newClearedRecord(_ index: Int) -> HistoryRecord {
        let r = HistoryRecord()
        r.ringIndex = Int32(index)
        r.serial = -1
        return r
    }

    /// The ring clear of VA 0x7AF10 / 0xA2D50: every record gets its own index and serial -1 and loses its message text
    /// and window bytes (other bytes stay, as on the PS4); the indices and the scene-stack top reset; the current
    /// message buffer is emptied.
    ///
    /// - Parameter live: When given, its message buffer's first byte (RAM 0x174D9B0) is cleared.
    public func clear(live: AdvLiveState? = nil) {
        for i in 0..<AdvHistory.ringCount {
            if let r = ring[i] {
                r.ringIndex = Int32(i)
                r.serial = -1
                r.writeU8(0x38FE, 0) // messageText[0] = 0
                r.writeU8(0x38B0, 0) // window164FD00[0] = 0
                r.writeU8(0x38E2, 0) // window164FD40[0] = 0
            }
        }

        cur = 0
        next = 0
        wrapped = false
        oldest = 0
        rewindCursor = 0
        stackTop = -1
        if let live = live {
            live.messageText[0] = 0
        }
    }

    /// True when ring record `index` holds a pushed record (serial >= 0).
    public func isValid(_ index: Int) -> Bool {
        index >= 0 && index < AdvHistory.ringCount && record(index).serial >= 0
    }

    /// The index before `index` in the ring, wrapping 0 to 799 only once the ring has wrapped.
    func before(_ index: Int) -> Int {
        index > 0 ? index - 1 : (wrapped ? AdvHistory.ringCount - 1 : -1)
    }

    // -- push ----------------------------------------------------------------------------------------------------

    /// History_Push (VA 0x7AF90): writes the record at `next` from the live variables and advances the
    /// ring. Nothing happens (false) in scan mode, while F929 or byte 0x16541F4 is set, or while F1102 is set for a
    /// kind other than 0 and 11. The command runs after the push: the record holds the state *before* it.
    ///
    /// - Parameters:
    ///   - live: The live variables the record captures.
    ///   - cmdOffset: Offset of the pushing statement in the decoded script (Script_Step passes name - 2, the `;` before the `_`).
    ///   - resumeOffset: Offset where a rewind resumes (the end of the statement).
    ///   - kind: The record kind (`Kinds`).
    /// - Returns: True when a record was pushed.
    @discardableResult
    public func push(live: AdvLiveState, cmdOffset: UInt64, resumeOffset: UInt64, kind: UInt16) -> Bool {
        if live.scanMode != 0 || live.f(AdvLiveState.FIndex.pushBlock) != 0 || live.var16541F4 != 0 {
            return false
        }

        if live.f(AdvLiveState.FIndex.onlyMessages) != 0 && kind != Kinds.message && kind != Kinds.unused11 {
            return false
        }

        let k = next
        let rec = record(k)
        live.restoredFromHistory = 0
        cur = k
        rewindCursor = k

        rec.serial = Int32(serialCounter)
        let advanced = Int16(truncatingIfNeeded: Int(serialCounter) + 1)
        serialCounter = advanced <= 0 ? 0 : advanced

        rec.cmdOffset = cmdOffset
        rec.resumeOffset = resumeOffset
        rec.script = live.scriptNumber
        rec.textBlock = Int16(truncatingIfNeeded: live.textBlock)
        rec.textLine = Int16(truncatingIfNeeded: live.textLine)
        rec.speaker = Int8(bitPattern: UInt8(truncatingIfNeeded: live.speaker))
        rec.var1654208 = Int8(bitPattern: UInt8(truncatingIfNeeded: live.var1654208))
        rec.kind = kind
        rec.bgmTrack = live.bgmTrack
        for i in 0..<AdvLiveState.soundChannels {
            rec.setLoopSeIds(i, live.loopSeIds[i])
        }

        rec.sceneWord = live.sceneWord

        // 0x7B283 / 0x7B2A2: a live write of the low byte of F995 into scene +0x19A3, copied with the block.
        live.scene.f995Low = UInt8(truncatingIfNeeded: live.f(AdvLiveState.FIndex.low995))
        rec.sceneState.copy(from: live.scene)
        rec.sceneCommitted.copy(from: live.committed)
        rec.slice(0x3468, 0x40).copy(from: ByteSpan(live.state174DAB0))
        rec.var174D940 = live.var174D940

        AdvHistory.copyFLists(live: live, rec: rec)

        rec.voiceId = -1
        rec.voiceCharacter = -1
        rec.effectActiveBits = live.effectActiveBits
        rec.effectBlockingBits = live.effectBlockingBits
        rec.flags363A = live.lastMessageOfPage ? 1 : 0
        rec.bgmVolume = live.bgmVolume
        rec.config04 = live.config.liveValue04

        for i in 0..<AdvLiveState.soundChannels {
            rec.setSeVolA(i, Int8(bitPattern: UInt8(truncatingIfNeeded: live.seVolA[i])))
            rec.setSeVolB(i, Int8(bitPattern: UInt8(truncatingIfNeeded: live.seVolB[i])))
            rec.setSeArrC(i, live.seArrC[i])
            rec.setSeArrD(i, live.seArrD[i])
            if ps4StaleSeBytes {
                live.seArrE[i] = rec.getSeArrEStale(i)
            } else {
                rec.setSeArrEStale(i, live.seArrE[i])
            }

            let srcBase = i * AdvLiveState.channelEntrySize
            let dstBase = 0x36D0 + i * 24
            rec.writeU8(dstBase + 0, live.channels[srcBase + 0])
            rec.writeU8(dstBase + 1, live.channels[srcBase + 1])
            rec.writeU8(dstBase + 2, live.channels[srcBase + 2])
            rec.writeU8(dstBase + 4, live.channels[srcBase + 4])
            rec.writeU8(dstBase + 5, live.channels[srcBase + 5])
            for j in 8..<22 {
                rec.writeU8(dstBase + j, live.channels[srcBase + j])
            }
        }

        rec.slice(0x38B0, 0x32).copy(from: ByteSpan(live.window164FD00))
        rec.slice(0x38E2, 0x1C).copy(from: ByteSpan(live.window164FD40))
        rec.writeU8(0x38FE, 0) // messageText[0] = 0

        var nextIdx = k + 1
        if nextIdx >= AdvHistory.ringCount {
            nextIdx = 0
            wrapped = true
        }

        next = nextIdx
        if nextIdx == oldest {
            oldest = nextIdx < AdvHistory.ringCount - 1 ? nextIdx + 1 : 0
        }

        record(nextIdx).serial = -1
        return true
    }

    /// The F lists of a push: u16 values, "not zero" bits and low bytes (adv_state.md 2.1).
    private static func copyFLists(live: AdvLiveState, rec: HistoryRecord) {
        for k in 0..<min(HistoryRecord.fU16Count, HistoryRecord.fU16Indices.count) {
            rec.setFU16(k, live.vars.getWord(HistoryRecord.fU16Indices[k]))
        }

        for k in 0..<HistoryRecord.fBoolIndices.count {
            let idx = HistoryRecord.fBoolIndices[k]
            rec.setFBoolBit(k, idx >= 0 && idx <= AdvHistory.maxListedF && live.vars.getWord(idx) != 0)
        }

        for k in 0..<HistoryRecord.fS8Indices.count {
            let idx = HistoryRecord.fS8Indices[k]
            if idx >= 0 && idx <= AdvHistory.maxListedF {
                rec.setFS8(k, Int8(bitPattern: UInt8(truncatingIfNeeded: live.vars.getWord(idx))))
            }
        }
    }

    // -- follow-up writes of the commands that push ----------------------------------------------------------------------

    /// After a push, the message commands (`_ZM` 0x92380, `_MSAD` 0x92B60, 0x7B5C0) copy the current message
    /// buffer into the newest record and clear its tail byte +0x39F6; `_ATSV` does the same (adv_state.md 2.5).
    ///
    /// - Parameter text: The text (at most 0xF8 bytes are kept; the rest of the 0xFA bytes is zeroed).
    public func setNewestMessageText(_ text: [UInt8]) {
        let win = newest.slice(0x38FE, 0xFA)
        win.copy(from: ByteSpan([UInt8](repeating: 0, count: 0xFA)))
        let count = min(text.count, 0xF8)
        for j in 0..<count {
            win[j] = text[j]
        }
    }

    /// Span overload for `setNewestMessageText`.
    public func setNewestMessageText(_ text: ByteSpan) {
        let win = newest.slice(0x38FE, 0xFA)
        win.copy(from: ByteSpan([UInt8](repeating: 0, count: 0xFA)))
        let count = min(text.count, 0xF8)
        for j in 0..<count {
            win[j] = text[j]
        }
    }

    /// Voice play stores the line's voice, the speaker's config row and the speaker byte in the newest record (not while
    /// `AdvLiveState.restoredFromHistory` is set, i.e. for a line re-displayed by a rewind; the caller checks).
    public func setNewestVoice(voiceId: Int32, voiceCharacter: Int16, speaker: Int8) {
        let r = newest
        r.voiceId = voiceId
        r.voiceCharacter = voiceCharacter
        r.speaker = speaker
    }

    /// Messages count down the scene-start counter: the `_ZM` handler decrements it (VA 0x92414) while it is above 0.
    /// "Previous scene" uses it to tell whether fewer than two messages were shown since the scene started.
    public func onMessageShown() {
        if sceneMessageCounter > 0 {
            sceneMessageCounter -= 1
        }
    }

    // -- scene stack -----------------------------------------------------------------------------------------------

    /// SceneStack_Push (VA 0x7E2E0), called by `_ATSV` after its kind-6 / kind-7 push: copies the newest record onto
    /// the scene stack (shifting the stack down by one when it is full) and sets the scene-message counter to 2.
    /// Nothing happens while any effect slot is blocking.
    ///
    /// - Parameter effectBlockingBits: Bit i = effect slot i is blocking (OR of VA 0x5C680(i) for i < 14).
    /// - Returns: True when the record was pushed.
    @discardableResult
    public func pushSceneStack(effectBlockingBits: UInt16) -> Bool {
        if (effectBlockingBits & 0x3FFF) != 0 {
            return false
        }

        if stackTop >= AdvHistory.sceneStackCount - 1 {
            for i in 0..<(AdvHistory.sceneStackCount - 1) {
                stackRecord(i).copy(from: stackRecord(i + 1))
            }
            stackTop = AdvHistory.sceneStackCount - 1
        } else {
            stackTop += 1
        }

        stackRecord(stackTop).copy(from: newest)
        sceneMessageCounter = 2
        return true
    }

    // -- staging -----------------------------------------------------------------------------------------------------

    /// Staging_SetSnapshot with the caller condition of adv_state.md 7.1: the record is copied into the slot staging only
    /// when its effect_blocking_bits are 0, its kind is not 11 or 12, and the live F823 is at most 1 (the first message of a
    /// page). The scene-stack top becomes state B. Called by the message and `_ATSV` commands (with the newest
    /// record) and at the end of every restore.
    ///
    /// - Returns: True when the staging was updated.
    @discardableResult
    public func updateStaging(_ record: HistoryRecord, _ live: AdvLiveState) -> Bool {
        if record.effectBlockingBits != 0 || record.kind == Kinds.unused11 || record.kind == Kinds.choiceStart
            || live.fSigned(AdvLiveState.FIndex.pageMessage) > 1 {
            return false
        }

        staging.setSnapshot(record, stackTop + 1, stackTopRecord)
        return true
    }

    /// The record's copy of an F variable kept in the s8 list (VA 0x765C0), or 0 when the list does not hold it.
    public static func recordF8(_ record: HistoryRecord, _ fIndex: Int) -> Int {
        guard let k = HistoryRecord.fS8Indices.firstIndex(of: fIndex) else {
            return 0
        }
        return Int(record.getFS8(k))
    }
}
