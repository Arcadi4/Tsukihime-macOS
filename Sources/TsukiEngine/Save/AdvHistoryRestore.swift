import Foundation
import TsukiCore

extension AdvHistory {
    /// History_Restore (VA 0x7C6D0): copies ring record `index` back into the live variables (the
    /// common part, adv_state.md 3.1), runs the tail of its kind (2.3, 3.2), moves `cur` / `next`
    /// to it and refreshes the slot staging. The command at the record's `cmdOffset` runs again: afterwards
    /// `AdvLiveState.scriptOffset` is that offset, except for a rewind to a message
    /// (`fromHistory`, kind 0), which re-displays the line and resumes at `resumeOffset`.
    ///
    /// - Parameters:
    ///   - index: Ring index 0..799.
    ///   - fromHistory: True only for rewind steps; loads, previous scene and backlog jumps pass false.
    ///   - live: The live variables to overwrite.
    ///   - scripts: Gives the decoded script of the record; needed only for a rewind to a message (kind 0, `fromHistory`).
    /// - Returns: The side effects the interpreter and the stage perform.
    @discardableResult
    public func restore(_ index: Int, _ fromHistory: Bool, _ live: AdvLiveState, _ scripts: ScriptBytesProvider? = nil) -> RestoreOutcome {
        let rec = record(index)
        let kind = rec.kind
        if fromHistory && kind == Kinds.message && scripts == nil {
            preconditionFailure("a rewind to a message needs the script bytes for the re-display")
        }

        let o = RestoreOutcome(index: index, kind: kind, fromHistory: fromHistory)

        // ---- common part (3.1) -------------------------------------------------------------------------------
        live.word1750646 = 0
        for j in 0..<min(rec.messageText.count, live.messageText.count) {
            live.messageText[j] = rec.messageText[j]
        }
        live.textFade = 1.0
        live.var1653E24 = 0
        live.scriptOffset = rec.cmdOffset
        live.textBlock = Int(rec.textBlock)
        live.textLine = Int(rec.textLine)
        live.speaker = UInt16(bitPattern: Int16(rec.speaker))
        live.var1654208 = UInt16(bitPattern: Int16(rec.var1654208))
        live.var165420A = UInt16(bitPattern: Int16(rec.var165420A))
        for j in 0..<min(rec.state174DAB0.count, live.state174DAB0.count) {
            live.state174DAB0[j] = rec.state174DAB0[j]
        }
        live.var174D940 = rec.var174D940
        live.bgmTrack = rec.bgmTrack
        live.bgmVolume = rec.bgmVolume

        for i in 0..<AdvLiveState.soundChannels {
            live.loopSeIds[i] = rec.getLoopSeIds(i)
            live.seVolA[i] = UInt16(bitPattern: Int16(rec.getSeVolA(i)))
            live.seVolB[i] = UInt16(bitPattern: Int16(rec.getSeVolB(i)))
            live.seArrC[i] = rec.getSeArrC(i)
            live.seArrD[i] = rec.getSeArrD(i)
            live.seArrE[i] = rec.getSeArrEStale(i)

            let srcBase = 0x36D0 + i * 24
            let dstBase = i * AdvLiveState.channelEntrySize
            live.channels[dstBase + 0] = rec.readU8(srcBase + 0)
            live.channels[dstBase + 1] = rec.readU8(srcBase + 1)
            live.channels[dstBase + 2] = rec.readU8(srcBase + 2)
            live.channels[dstBase + 4] = rec.readU8(srcBase + 4)
            live.channels[dstBase + 5] = rec.readU8(srcBase + 5)
            for j in 8..<22 {
                live.channels[dstBase + j] = rec.readU8(srcBase + j)
            }
        }

        live.sceneWord = rec.sceneWord
        live.scene.copy(from: rec.sceneState)
        live.voiceId = rec.voiceId
        live.var16541FC = rec.voiceId
        live.var1654200 = rec.voiceId

        // effect slots that were not active in the record are stopped (VA 0x5C080)
        let recordActive = rec.effectActiveBits
        for s in 0..<14 {
            let bit = UInt16(1 << s)
            if (recordActive & bit) == 0 && (live.effectActiveBits & bit) != 0 {
                o.stopEffectSlots |= bit
            }
        }

        live.effectActiveBits = UInt16(live.effectActiveBits & ~o.stopEffectSlots)

        if live.config.restoreLiveValueGate != 0 {
            o.config04Hook = true
            if rec.config04 <= 0x100 {
                live.config.liveValue04 = rec.config04
            }
        }

        if rec.script != live.scriptNumber {
            live.scriptNumber = rec.script
            o.reloadScript = true
        }

        // F lists: u16, then s8, then bool (the later list wins where an index is in two)
        for k in 0..<HistoryRecord.fU16Indices.count {
            let idx = HistoryRecord.fU16Indices[k]
            if idx >= 0 && idx <= AdvHistory.maxListedF {
                live.vars.setWord(idx, rec.getFU16(k))
            }
        }

        for k in 0..<HistoryRecord.fS8Indices.count {
            let idx = HistoryRecord.fS8Indices[k]
            if idx >= 0 && idx <= AdvHistory.maxListedF {
                live.vars.setWord(idx, UInt16(bitPattern: Int16(rec.getFS8(k))))
            }
        }

        for k in 0..<HistoryRecord.fBoolIndices.count {
            let idx = HistoryRecord.fBoolIndices[k]
            if idx >= 0 && idx <= AdvHistory.maxListedF {
                live.vars.setWord(idx, rec.getFBoolBit(k) ? 1 : 0)
            }
        }

        for j in 0..<min(rec.window164FD00.count, live.window164FD00.count) {
            live.window164FD00[j] = rec.window164FD00[j]
        }
        if kind != Kinds.message {
            live.window164FD40[0] = 0
        } else {
            for j in 0..<min(rec.window164FD40.count, live.window164FD40.count) {
                live.window164FD40[j] = rec.window164FD40[j]
            }
        }

        let plate = live.window164FD40[0] != 0 ? 1 : 0
        live.var16541EC = plate
        live.var16541F0 = plate

        cur = index
        next = index + 1
        if next >= AdvHistory.ringCount {
            next = 0
            wrapped = true
        }

        live.var16541E4 = Int(Int8(bitPattern: live.scene.byte19A4))

        // F967 rule (0x7D513): kept only when it equals scene word +0x19A6 + 1; values <= 0 are kept
        let f967 = live.fSigned(AdvLiveState.FIndex.sceneBase)
        if f967 > 0 && live.scene.f967Base + 1 != f967 {
            live.vars.setWord(AdvLiveState.FIndex.sceneBase, 0)
            live.waitFlags |= 0x200
            o.f967Reset = true
        }

        // ---- kind tails (2.3, 3.2) ---------------------------------------------------------------------------
        switch kind {
        case Kinds.message:
            restoreMessageTail(rec: rec, live: live, fromHistory: fromHistory, scripts: scripts, o: o)
        case Kinds.layerChange, Kinds.commit:
            live.committed.copy(from: rec.sceneCommitted)
            live.sceneWord = rec.sceneWord
            o.rebuildFromCommitted = true
        case Kinds.music:
            if live.bgmTrack < 0 {
                o.bgm = .stop
            } else {
                o.bgm = .start
                o.bgmTrack = live.bgmTrack
                o.bgmVolume = live.bgmVolume
            }
        case 3, 4, 5:
            o.loopSe = loopSeRestores(live: live)
        case Kinds.sceneStart:
            popSceneStackIf(index: index, o: o)
        case Kinds.choiceSavePoint:
            popSceneStackIf(index: index, o: o)
            o.showRecordText = nulTerminated(rec.messageText)
        default:
            break
        }

        if rec.effectBlockingBits == 0 && kind != Kinds.unused11 && kind != Kinds.choiceStart
            && live.fSigned(AdvLiveState.FIndex.pageMessage) <= 1 {
            staging.setSnapshot(rec, stackTop + 1, stackTopRecord)
            o.stagingUpdated = true
        }

        return o
    }

    private func popSceneStackIf(index: Int, o: RestoreOutcome) {
        if stackTop >= 0 && Int(stackRecord(stackTop).ringIndex) == index {
            stackTop -= 1
            sceneMessageCounter = 0
            afterLoad = 0
            o.scenePopped = true
        }
    }

    private func nulTerminated(_ text: ByteSpan) -> [UInt8] {
        var result: [UInt8] = []
        for b in text {
            if b == 0 { break }
            result.append(b)
        }
        return result
    }

    private func loopSeRestores(live: AdvLiveState) -> [LoopSeRestore] {
        var list: [LoopSeRestore] = []
        list.reserveCapacity(AdvLiveState.soundChannels)
        for i in 0..<AdvLiveState.soundChannels {
            let id = live.loopSeIds[i]
            let restart = id >= 0 && Int16(bitPattern: live.seVolB[i]) > 0
            list.append(LoopSeRestore(
                channel: i,
                restart: restart,
                loopSeId: id,
                volume: Int8(bitPattern: live.seArrE[i]),
                pitch: Int16(bitPattern: live.seVolA[i]),
                arrC: live.seArrC[i],
                arrD: live.seArrD[i]
            ))
        }
        return list
    }

    /// The kind-0 tail (VA 0x7D6F2, adv_state.md 3.2).
    private func restoreMessageTail(rec: HistoryRecord, live: AdvLiveState, fromHistory: Bool, scripts: ScriptBytesProvider?, o: RestoreOutcome) {
        if live.var86AA24 != 0 {
            o.flushPending = true
            live.var86AA24 = 0
        }

        live.redisplayLength = 0
        live.var174DE00 = 0
        let f931 = live.fSigned(AdvLiveState.FIndex.windowStyle)
        if f931 >= 0 {
            live.scene.textWindowB = f931
        }

        live.scene.textWindowA = live.scene.textWindowB
        if !fromHistory {
            return
        }

        // re-display of the line (rewind only)
        live.restoredFromHistory = 1
        live.var1654208 = 0
        live.var16541F4 = 0
        let script = scripts!(rec.script)
        var (text, end, reachedEnd) = AdvHistory.extractStatementText(script: script, cmdOffset: rec.cmdOffset)

        for j in 0..<min(text.count, live.redisplayText.count) {
            live.redisplayText[j] = text[j]
        }
        if text.count < live.redisplayText.count {
            live.redisplayText[text.count] = 0
        }

        live.redisplayLength = UInt16(text.count)
        for j in 0..<min(live.redisplayText.count, live.redisplayCopy.count) {
            live.redisplayCopy[j] = live.redisplayText[j]
        }

        var namePlate = [UInt8](repeating: 0, count: rec.window164FD40.count)
        for j in 0..<rec.window164FD40.count {
            namePlate[j] = rec.window164FD40[j]
        }
        for j in 0..<min(live.window164FD40.count, live.window164FD60.count) {
            live.window164FD60[j] = live.window164FD40[j]
        }
        live.window164FD40[0] = 0

        live.scene.textWindowA = live.scene.textWindowB
        live.var16541D8 = 1
        live.var16541FC = -1
        live.waitFlags70 |= 1

        if reachedEnd && live.pageEndInstantLatch && live.fSigned(AdvLiveState.FIndex.lastMessage) != 1 {
            end = 2
        }

        if end == 1 {
            live.word1653E08 = 0
            live.var16541F4 = 1
        } else {
            let addFlags = (end == 2 ? 0x140 : 0x500) | live.waitFlags70
            live.waitFlags |= addFlags
        }

        live.textBlock = Int(rec.textBlock)
        live.textBlock2 = Int(rec.textBlock)
        live.textLine = Int(rec.textLine)
        live.textLine2 = Int(rec.textLine)
        live.var1654200 = -1
        live.scriptOffset = rec.resumeOffset
        o.redisplay = RedisplayInfo(text: text, endCode: end, namePlate: namePlate)
    }

    /// Copies the statement text of the kind-0 re-display out of the script (VA 0x7D8B3): from `cmdOffset + 0xA`
    /// (after `;_ZMbbbll(`) up to `)`, `@e` or `@n`, at most 0x300 bytes. Bytes past the end of the
    /// script read as 0.
    ///
    /// - Returns: The text, the end code (1 = `@n`, 2 = `@e`, else 0) and whether the text ended at `)` or at 0x300 bytes.
    public static func extractStatementText(script: [UInt8], cmdOffset: UInt64) -> (text: [UInt8], endCode: Int, reachedEnd: Bool) {
        var buf = [UInt8](repeating: 0, count: AdvLiveState.redisplayBufferSize)
        var n = 0
        var end = 0
        var reached = true
        let start = Int(cmdOffset) + 0xA
        while n < buf.count {
            let c = at(script, start + n)
            if c == UInt8(ascii: "@") {
                let d = at(script, start + n + 1)
                if d == UInt8(ascii: "e") {
                    end = 2
                    reached = false
                    break
                }
                if d == UInt8(ascii: "n") {
                    end = 1
                    reached = false
                    break
                }
            } else if c == UInt8(ascii: ")") {
                break
            }

            buf[n] = c
            n += 1
        }

        return (Array(buf[0..<n]), end, reached)
    }

    private static func at(_ s: [UInt8], _ i: Int) -> UInt8 {
        i >= 0 && i < s.count ? s[i] : 0
    }
}
