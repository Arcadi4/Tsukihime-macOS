import Foundation
import TsukiCore

/// The result of one rewind step (`AdvHistory.rewindStep`).
public final class RewindResult {
    public init() {}

    /// True when the rewind moved to an earlier page (the PS4 calls VA 0x56730(1)); false when there was nothing earlier.
    public var stepped: Bool = false

    /// The ring index the step landed on (the cursor does not move when `stepped` is false).
    public var target: Int = 0

    /// Every restore the step performed, newest record first; the last one is the target.
    public var restores: [RestoreOutcome] = []

    /// The scene re-sync (VA 0x7E4E0) after the target: the engine rebuilds the stage from the live scene / committed copy and restarts the music and loop SEs from the live variables.
    public var resync: Bool = false

    /// True when the undone cursor record was a kind-1 record: the engine flushes pending effects (VA 0x75CD0(1)).
    public var flushPending: Bool = false

    /// OR of the effect slots the restores stopped.
    public var stopEffectSlots: UInt16 {
        restores.reduce(0) { $0 | $1.stopEffectSlots }
    }
}

/// The result of a scene restore (previous scene, slot load, `0x7E790`).
public final class SceneRestoreResult {
    public init(_ restore: RestoreOutcome) {
        self.restore = restore
    }

    /// The History_Restore of the scene record.
    public let restore: RestoreOutcome

    /// The record's voice to replay when voice is enabled (VA 0x7EB19): voice id and the speaker's config row; the id is negative when there is none.
    public var replayVoiceId: Int = -1

    /// See `replayVoiceId`: the record's voice_character (the config row is looked up by VA 0x3D2D0).
    public var replayVoiceCharacter: Int16 = -1

    /// What the scene counters want after the restore: F967 = scene word +0x19A6 + 1 with the 0x495C0 / 0x5C380 calls, or F967 = 0
    /// (0x7EB72..0x7EBE1). True when the word was not negative.
    public var sceneBoundValid: Bool = false
}

extension AdvHistory {
    // -- re-sync (VA 0x7E4E0) -----------------------------------------------------------------------------------------

    /// 0x7E4E0(index), run after the History_Restore of a rewind target, a backlog jump and a scene restore: the committed
    /// copy and the scene state take the record's, window words follow F931, and the engine restarts BGM and loop SEs from
    /// the live variables (VA 0x7E620) and rebuilds the stage layers.
    public func resyncScene(_ index: Int, _ live: AdvLiveState) {
        let rec = record(index)
        live.sceneWord = rec.sceneWord
        live.committed.copy(from: rec.sceneCommitted)
        live.scene.copy(from: rec.sceneState)
        let f931 = live.fSigned(AdvLiveState.FIndex.windowStyle)
        if f931 >= 0 {
            live.scene.textWindowB = f931
        }
        live.scene.textWindowA = live.scene.textWindowB
    }

    // -- rewind (adv_state.md 5.1) ----------------------------------------------------------------------------------

    /// True when a rewind step has somewhere to go (the newest record is not alone).
    public var canRewind: Bool {
        isValid(cur) && count >= 2
    }

    /// Number of valid records in the ring (those between the oldest and `cur`).
    public var count: Int {
        let n = cur - oldest
        if n <= -2 {
            return wrapped ? n + AdvHistory.ringCount + 1 : 0
        }
        return max(0, n + 1)
    }

    /// One step of the held rewind action (Adv_Rewind VA 0xA2020, after its wait checks pass): undoes the newest record
    /// unless it is a message / choice record, walks back to the previous page start (a kind-0 record with no blocking
    /// effect and F823 <= 1), undoes every record in between (each with `History_Restore(j, 1)`), and restores
    /// the target with the re-display of its line. Nothing is re-executed; ordinary script execution continues from the
    /// target's `resumeOffset`. The caller checks the pending-wait conditions of Adv_Rewind first.
    ///
    /// - Parameters:
    ///   - live: The live variables.
    ///   - scripts: Decoded scripts for the re-display.
    public func rewindStep(live: AdvLiveState, scripts: @escaping ScriptBytesProvider) -> RewindResult {
        let result = RewindResult()
        let c = rewindCursor
        if isValid(c) {
            let kind = record(c).kind
            if kind != Kinds.message && kind != Kinds.choiceStart && kind != Kinds.choiceLine {
                result.restores.append(restore(c, true, live, scripts))
                result.flushPending = (kind == Kinds.layerChange)
            }
        }

        // find the target t
        var t = c
        while true {
            t -= 1
            if t < 0 {
                if !wrapped {
                    t = 0
                    break
                }
                t = AdvHistory.ringCount - 1
            }

            let r = record(t)
            if r.serial < 0 {
                t = c
                break
            }

            if r.effectBlockingBits != 0 || r.kind != Kinds.message {
                continue
            }

            if AdvHistory.recordF8(r, AdvLiveState.FIndex.pageMessage) <= 1 {
                break
            }
        }

        // undo every command in between: j = c - 1 down to t + 1 (a signed compare, as the PS4 does: across a wrap
        // from the low indices to the high ones the loop does not run)
        var j = c - 1
        while t < j {
            result.restores.append(restore(j, true, live, scripts))
            j -= 1
        }

        if !isValid(t) || t == c {
            result.stepped = false
            result.target = c
            return result
        }

        rewindCursor = t
        result.restores.append(restore(t, true, live, scripts))
        resyncScene(cur, live)
        result.stepped = true
        result.resync = true
        result.target = t
        return result
    }

    // -- previous / next scene (adv_state.md 5.2, 5.3) -----------------------------------------------------------------

    /// 0x75420(direction): requests a next (1) or previous (-1) scene. A next-scene request is dropped while wait-flag bit 0x10 is set.
    public func requestSceneJump(_ direction: Int, waitFlag10: Bool) {
        sceneJumpRequest = direction == 1 ? (waitFlag10 ? 0 : 1) : direction
    }

    /// Returns the pending scene-jump request and clears it (VA 0xA2B40).
    public func takeSceneJumpRequest() -> Int {
        let r = sceneJumpRequest
        sceneJumpRequest = 0
        return r
    }

    /// Ends the next-scene skip at an `_ATSV` (VA 0x96CBD): returns true when it was running, in which case the engine restarts
    /// BGM and loop SEs from the live variables (VA 0x7E620) because the skip silenced them.
    public func endNextScene() -> Bool {
        let was = nextSceneRunning
        nextSceneRunning = false
        return was
    }

    /// Previous scene (action 24, VA 0xA23F0..0xA25C4): restarts the current scene, or the one before it within its first
    /// two messages. The caller has done the confirmation dialog.
    ///
    /// - Parameters:
    ///   - live: The live variables.
    ///   - effectBlockingBits: Bit i = effect slot i is blocking (VA 0x5C680).
    ///   - waitFlag10: Bit 0x10 of the wait flags (VA 0x1653E00): set while a movie-like task holds the engine.
    ///   - flushPending: True when the PS4 calls 0x75CD0(1) before restoring (out parameter for the interpreter).
    /// - Returns: The scene restore, or nil when there is nothing to go back to.
    public func previousScene(live: AdvLiveState, effectBlockingBits: UInt16, waitFlag10: Bool, flushPending: inout Bool) -> SceneRestoreResult? {
        flushPending = false
        let blocking = (effectBlockingBits & 0x3FFF) != 0
        var top = stackTop
        if !blocking && waitFlag10 {
            if top < 2 {
                return nil
            }
            flushPending = true
            top -= 1
        } else {
            if top <= 0 {
                return nil
            }

            if sceneMessageCounter > 0 {
                if top < 2 {
                    return nil
                }
                top -= 1
            }

            flushPending = true
        }

        return restoreSceneRecord(top, live)
    }

    /// True when the previous-scene action would restore something now (the mode panel button is lit).
    public func canGoToPreviousScene(effectBlockingBits: UInt16, waitFlag10: Bool) -> Bool {
        let blocking = (effectBlockingBits & 0x3FFF) != 0
        if !blocking && waitFlag10 {
            return stackTop >= 2
        }

        return stackTop > 0 && !(sceneMessageCounter > 0 && stackTop < 2)
    }

    /// VA 0x7E790(n): restores scene-stack record `n`. The ring record is restored in place when the ring
    /// still holds it (same serial), else the ring is rebuilt around the stack record. Afterwards the stack top is n-1.
    public func restoreSceneRecord(_ n: Int, _ live: AdvLiveState) -> SceneRestoreResult {
        let r = stackRecord(n)
        let i = Int(r.ringIndex)
        let restoreIndex: Int
        let outcome: RestoreOutcome
        live.redisplayLength = 0
        live.word1750646 = 0
        let inRing = i >= 0 && i < AdvHistory.ringCount && (i < cur || wrapped) && record(i).serial == r.serial
        if inRing {
            outcome = restore(i, false, live)
            restoreIndex = i
        } else {
            clear(live: live)
            record(0).copy(from: r)
            outcome = restore(0, false, live)
            restoreIndex = 0
        }

        stackTop = n - 1
        live.waitFlags = 0
        live.waitFlags70 = 0
        resyncScene(restoreIndex, live)
        let rec = record(restoreIndex)
        let result = SceneRestoreResult(outcome)
        result.replayVoiceId = Int(rec.voiceId)
        result.replayVoiceCharacter = rec.voiceCharacter
        result.sceneBoundValid = live.scene.f967Base >= 0

        if live.scene.f967Base >= 0 {
            live.vars.setWord(AdvLiveState.FIndex.sceneBase, UInt16(live.scene.f967Base + 1))
        } else {
            live.vars.setWord(AdvLiveState.FIndex.sceneBase, 0)
            live.waitFlags |= 0x200
        }

        sceneMessageCounter = 2
        afterLoad = 2
        rewindCursor = cur
        return result
    }

    // -- backlog (adv_state.md 5.4, 5.5) ----------------------------------------------------------------------------

    /// Backlog_Open (VA 0x3BFB0): the backlog is the history ring. Returns the ring indices of the messages of the earlier
    /// pages, newest first: records of kind 0, 8, 11 or 12 walking back from `cur`, with trailing choice
    /// records dropped and the current page (everything before the first earlier page-end record, F799 == 1) removed.
    /// An empty list means there is nothing to show.
    public func backlogEntries() -> [Int] {
        var list: [Int] = []
        var n = cur - oldest
        if n <= -2 {
            if !wrapped {
                return list
            }
            n += AdvHistory.ringCount + 1
            if n <= 0 {
                return list
            }
        } else {
            n += 1
            if n <= 0 {
                return list
            }
        }

        var i = cur
        while n > 0 {
            let kind = record(i).kind
            if kind <= 12 && ((0x1901 >> kind) & 1) != 0 {
                list.append(i)
            }

            i = wrapped && i <= 0 ? i + 799 : i - 1
            n -= 1
        }

        if list.count <= 1 {
            return []
        }

        // drop trailing kind-12 entries from the oldest end, keeping list[0]
        var count = list.count
        while count > 1 && record(list[count - 1]).kind == Kinds.choiceStart {
            count -= 1
        }

        if count < list.count {
            list.removeSubrange(count..<list.count)
        }
        if list.count <= 1 {
            return []
        }

        var k = -1
        for q in 1..<list.count {
            if AdvHistory.recordF8(record(list[q]), AdvLiveState.FIndex.lastMessage) == 1 {
                k = q
                break
            }
        }

        if k < 0 {
            return []
        }

        list.removeSubrange(0..<k)
        return list
    }

    /// Backlog jump (VA 0x3CC70, adv_state.md 5.5): restores the entry's record (`History_Restore(i, 0)`, so the
    /// command runs again) after discarding the scene starts of the newer records. The caller has stopped the music and
    /// voice. The next push overwrites the entry's ring slot.
    ///
    /// - Parameters:
    ///   - ringIndex: An index from `backlogEntries`.
    ///   - live: The live variables.
    /// - Returns: The restore, or nil when the entry is not a valid jump target (the PS4 plays its error sound).
    public func backlogJump(_ ringIndex: Int, _ live: AdvLiveState) -> RestoreOutcome? {
        if ringIndex < 0 || ringIndex >= AdvHistory.ringCount {
            return nil
        }

        var i = ringIndex
        if record(i).kind == Kinds.choiceStart {
            i = i >= 1 ? i - 1 : AdvHistory.ringCount - 1
            if record(i).kind != Kinds.choiceLine {
                return nil
            }
        }

        if i != cur {
            var c = cur
            while true {
                if c < 0 {
                    c = AdvHistory.ringCount - 1
                }

                let r = record(c)
                if r.serial < 0 {
                    break
                }

                if (r.kind & ~1) == 6 && stackTop >= 0 && Int(stackRecord(stackTop).ringIndex) == c {
                    stackTop -= 1
                }

                c -= 1
                if c == i {
                    break
                }
            }
        }

        live.waitFlags = 0
        live.waitFlags70 = 0
        live.word1653E08 = 0
        live.var16541FC = -1
        let outcome = restore(i, false, live)
        next = cur
        rewindCursor = cur
        resyncScene(i, live)
        return outcome
    }

    // -- slot load (adv_state.md 7.3) ----------------------------------------------------------------------------------

    /// Loads a stored slot the way Slot_Load (VA 0xA2D10) does, not the scan-mode fallback: the slot becomes the staging,
    /// the ring and the live script variables are reset, state A becomes the scene-stack record n (state B record n-1),
    /// and 0x7E790(n) restores it. The saved line is not re-displayed: `AdvLiveState.scriptOffset` is the
    /// record's `cmdOffset` and the page's first message statement runs again, pushing a new record over ring slot 0.
    ///
    /// - Parameters:
    ///   - slot: The slot to load (copied into the staging).
    ///   - live: The live variables.
    /// - Throws: `TsukiError.format` when the slot lacks its end marker or state-B flag is out of range.
    public func loadSlot(_ slot: SlotImage, _ live: AdvLiveState) throws -> SceneRestoreResult {
        if slot.endMarker != SlotImage.magic {
            throw TsukiError.format("the slot has no end marker (a scan-mode save of an older build is not supported)")
        }

        if slot.hasStateB < 0 || slot.hasStateB > 1 {
            throw TsukiError.format("slot state-B flag \(slot.hasStateB) is not 0 or 1")
        }

        staging.copy(from: slot)
        live.word1750646 = 0
        clear(live: live)
        for w in 0..<(Vars.zWord + Vars.zCount) {
            live.vars.setWord(w, 0)
        }

        live.resetSound()
        live.scene.word199A = 0
        live.scene.word199C = 0
        live.scene.word199E = 0

        let n = Int(staging.hasStateB)
        let stackN = stackRecord(n)
        stackN.copy(from: slot.stateA.bytes)
        if n >= 1 {
            let below = stackRecord(n - 1)
            below.slice(0, SlotImage.stateBSize).copy(from: slot.stateB)
            below.writeU8(0x38FE, 0) // messageText[0] = 0
        }

        let result = restoreSceneRecord(n, live)
        cur = 0
        next = 0
        rewindCursor = 0
        sceneMessageCounter = 0
        afterLoad = 1
        return result
    }
}
