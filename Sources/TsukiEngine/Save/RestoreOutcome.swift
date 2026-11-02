import Foundation
import TsukiCore

/// What a restore asks the BGM to do (kind-2 tail, VA 0x7D742).
public enum BgmRestoreAction: UInt8, Sendable {
    /// The record kind does not touch the music.
    case none = 0

    /// Start `RestoreOutcome.bgmTrack` at `RestoreOutcome.bgmVolume` (VA 0x98C0, then 0x9CE0).
    case start = 1

    /// Stop the music (VA 0x9A90): the record's track is negative.
    case stop = 2
}

/// One loop-SE channel of a kind 3..5 restore (tail at VA 0x7D575): the channel restarts when its loop id is not
/// negative and `seVolB` is above 0 (calls 0xAA80, 0xAD60, 0xA300, 0xA9E0, 0xAA50), otherwise it stops (0xAAB0).
public struct LoopSeRestore: Equatable, Sendable {
    /// Channel 0..19.
    public let channel: Int

    /// True to restart the loop, false to stop the channel.
    public let restart: Bool

    /// The loop SE id (0x1654240[i]).
    public let loopSeId: Int16

    /// Sign-extended byte 0x1654330[i] (argument of 0xAD60).
    public let volume: Int8

    /// Sign-extended word 0x1654270[i] (the pitch argument of 0xA300, converted to float by the engine).
    public let pitch: Int16

    /// Word 0x16542D0[i] (argument of 0xA9E0).
    public let arrC: Int16

    /// Word 0x1654300[i] (argument of 0xAA50).
    public let arrD: Int16

    public init(channel: Int, restart: Bool, loopSeId: Int16, volume: Int8, pitch: Int16, arrC: Int16, arrD: Int16) {
        self.channel = channel
        self.restart = restart
        self.loopSeId = loopSeId
        self.volume = volume
        self.pitch = pitch
        self.arrC = arrC
        self.arrD = arrD
    }
}

/// The kind-0 re-display of a rewind (adv_state.md 3.2): the statement text was copied out of the script into
/// `AdvLiveState.redisplayText`, and the engine lays it out again (name plate, message box) and resumes the
/// script at the record's `resumeOffset`.
public struct RedisplayInfo: Equatable, Sendable {
    /// The statement text (after `;_ZMbbbll(`) up to `)`, `@e` or `@n` (at most 0x300 bytes).
    public let text: [UInt8]

    /// 0 = the statement ended at `)` or after 0x300 bytes, 1 = `@n` (no click wait), 2 = `@e` (or forced by the instant-page latch).
    public let endCode: Int

    /// The record's name-plate state (0x1C bytes) that the engine lays out as the name plate.
    public let namePlate: [UInt8]

    public init(text: [UInt8], endCode: Int, namePlate: [UInt8]) {
        self.text = text
        self.endCode = endCode
        self.namePlate = namePlate
    }
}

/// The side effects of one `AdvHistory.restore` that are not variable copies (those are already in the
/// `AdvLiveState`): effect slots to stop, music and sound to restart, the stage to rebuild, the message
/// to re-display, the staging snapshot. The interpreter and the stage perform them (docs/formats/adv_state.md 3.1, 3.2).
public final class RestoreOutcome {
    public init(index: Int, kind: UInt16, fromHistory: Bool) {
        self.index = index
        self.kind = kind
        self.fromHistory = fromHistory
    }

    /// Ring (or scene-stack) index that was restored.
    public let index: Int

    /// The record's kind (adv_state.md 2.3).
    public let kind: UInt16

    /// True for a rewind (the kind-0 re-display runs); false for loads, previous scene and backlog jumps.
    public let fromHistory: Bool

    /// True when the record belongs to another script: `AdvLiveState.scriptNumber` was set and the interpreter must load and decode that script.
    public var reloadScript: Bool = false

    /// Bit i = stop effect slot i (it was active and the record says it was not; VA 0x5C080).
    public var stopEffectSlots: UInt16 = 0

    /// True when config +0x4C is set: the UI hook at VA 0x423D0 runs; config +0x04 (`liveValue04`) already took the record's value when that is at most 0x100.
    public var config04Hook: Bool = false

    /// The music action of a kind-2 record.
    public var bgm: BgmRestoreAction = .none

    /// BGM track of a `BgmRestoreAction.start`.
    public var bgmTrack: Int16 = 0

    /// BGM volume word of a `BgmRestoreAction.start`.
    public var bgmVolume: Int16 = 0

    /// The 20 loop-SE channels of a kind 3..5 record; nil for other kinds.
    public var loopSe: [LoopSeRestore]? = nil

    /// True for kinds 1 and 9: the stage rebuilds its layers from `AdvLiveState.committed` (VA 0xE98D0, 0x7DD10 ...) and then returns to `AdvLiveState.scene`.
    public var rebuildFromCommitted: Bool = false

    /// True for kind 0 when the F967 rule reset F967 (VA 0x7D52C: also WaitFlags |= 0x200).
    public var f967Reset: Bool = false

    /// True when a kind-0 restore found VA 0x86AA24 set and cleared it: the engine flushes pending effects (VA 0x75CD0(1)).
    public var flushPending: Bool = false

    /// True for kinds 6 and 7 when the record was the scene-stack top and the stack was popped (the scene counters were cleared).
    public var scenePopped: Bool = false

    /// For kind 7 (choice save point): the record's message text (up to the NUL) that the engine shows again (VA 0x7B790).
    public var showRecordText: [UInt8]? = nil

    /// The kind-0 re-display of a rewind (nil for other restores).
    public var redisplay: RedisplayInfo? = nil

    /// True when the restore refreshed the slot staging (Staging_SetSnapshot, VA 0x73980).
    public var stagingUpdated: Bool = false
}
