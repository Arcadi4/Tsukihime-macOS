import Foundation
import TsukiCore

extension GameHost {
    private static let layerChangeNames: Set<String> = [
        "STCH", "SCH2", "STCC", "STBR", "STCL", "STCP", "STRT", "STZ4", "STRR", "STGS", "STRA", "STNS", "STEC", "SNX2", "SNX3",
        "SQK2", "SQS2", "SHK2", "SHS2", "SSW2", "SSS2", "STMA", "SPMA",
    ]

    func dispatchStage(_ st: Statement) -> StepResult {
        let name = st.name.description
        if Self.layerChangeNames.contains(name) {
            noteLayerChange(st)
        }

        switch name {
        case "FADS":
            push(.layerBatchStart, st)
            setF(996, 0)
            setF(997, 0)
            setF(985, 0)
            let a = StageArgs(st)
            let ms = a.has(1) ? a.expr(1) : 0
            let hide = a.has(3) ? a.expr(3) : -1
            if hide == 1 || (hide == 2 && ms >= 2 && wait.textFadeStep >= 0.0) {
                setF(1103, 1)
            }

            _ = stage.execute(st)
            copyCommitted()
            setF(Self.layerBatchFlagVar, 0)
            wait.bits &= ~WaitBits.system
            wait.bits |= WaitBits.fads
            markDisplayedPictures()
            return StepResult.yield

        case "STCF":
            let a = StageArgs(st)
            let l = a.has(0) ? a.expr(0) : 0
            if l >= 0 && l <= 39 {
                wait.stcfLayers |= 1 &<< l
                wait.stcfMask[l] = UInt8(truncatingIfNeeded: a.has(1) ? a.expr(1) : 0x3F)
            }

            wait.bits |= WaitBits.stcf
            return StepResult.yield

        case "STMA":
            _ = stage.execute(st)
            if stage.motionWaitRequested {
                stage.motionWaitRequested = false
                setF(1103, 1)
            }
            return StepResult.continue

        case "MSQK", "SHOK", "SHAF", "STPV":
            _ = stage.execute(st)
            return StepResult.continue

        case "SPFC", "SPRD", "SPRC":
            return StepResult.continue

        default:
            if !stage.execute(st) {
                return cmdUnknown(st)
            }
            return StepResult.continue
        }
    }

    /// The 0x4AB80 predicate of `_STCF`: whether layer `layer` still has a tween (or motion) selected by `mask`.
    func stcfPending(layer: Int, mask: Int) -> Bool {
        guard layer >= 0 && layer < stage.drawn.count else { return false }
        let r = stage.drawn[layer]
        if (mask & 0x01) != 0 && r.twMove.counter > 0 {
            return true
        }
        if (mask & 0x02) != 0 && r.twScale.counter > 0 {
            return true
        }
        if (mask & 0x04) != 0 && r.twRot.counter > 0 {
            return true
        }
        if (mask & 0x08) != 0 && r.twAlpha.counter > 0 {
            return true
        }
        if (mask & 0x20) != 0 && r.motionId > 0 && r.motionPause == 0 {
            if let mr = stage.motions.get(Int(r.motionId)) {
                if mr.end > mr.start && mr.duration > 0 && stage.motions.loop(Int(r.motionId)) == 0 {
                    if Int(MotionMath.motionTimeMs(r.motionFrames, Int(r.motionDivisor))) < mr.duration {
                        return true
                    }
                }
            }
        }
        return false
    }

    // -- the gallery marks of the picture commands ----------------------------------------------------------------------------------

    func cmdStcg(_ st: Statement) -> StepResult {
        let name = argText(st, 0)
        let pic = stage.catalog.lookup(name)
        markPictureSeen(pic)
        return StepResult.continue
    }

    /// The layer commit marks every displayed picture as seen (gallery.md 2.2; VA 0x7E0F1).
    func markDisplayedPictures() {
        for l in 0..<StageRuntime.layerCount {
            let pic = Int(stage.scene.getPic(l))
            if pic >= 0 {
                markPictureSeen(pic)
            }
        }
    }

    func markPictureSeen(_ pic: Int) {
        let seen = flow.pictureSeenIndex(pic)
        if seen >= 0 && seen < SystemBlock.pictureSeenBits {
            systemData.setPictureSeen(seen, true)
        }
    }
}
