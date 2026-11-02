import Foundation
import TsukiCore

extension GameHost {
    private static let sceneSeenWord = 110
    private static let sceneDoneWord = 300
    private static let edgeSeenWord = 400
    private static let routeNodeWord = 201
    private static let routeEdgeWord = 600
    private static let maxNodeBit = 0x23F
    private static let firstEdgeId = 564
    private static let edgeBits = 704

    func resetMarks() {
        staffTask = false
    }

    private func getBit(_ firstWord: Int, _ bit: Int) -> Bool {
        ((vars.getG(firstWord + (bit >> 4)) >> (bit & 15)) & 1) != 0
    }

    private func setBit(_ firstWord: Int, _ bit: Int) {
        let w = firstWord + (bit >> 4)
        vars.setG(w, vars.getG(w) | UInt16(1 << (bit & 15)))
    }

    private func playBit(_ firstWord: Int, _ bit: Int) -> Bool {
        ((vars.getF(firstWord + (bit >> 3)) >> (bit & 7)) & 1) != 0
    }

    private func setPlayBit(_ firstWord: Int, _ bit: Int) {
        let w = firstWord + (bit >> 3)
        vars.setF(w, vars.getF(w) | UInt16(1 << (bit & 7)))
    }

    /// scene_seen(n): the node was reached in any playthrough (`_RDST`).
    public func isSceneReached(_ n: Int) -> Bool {
        n >= 0 && n <= Self.maxNodeBit && getBit(Self.sceneSeenWord, n)
    }

    /// scene_done(n): the node was completed (`_RDED`).
    public func isSceneDone(_ n: Int) -> Bool {
        n >= 0 && n <= Self.maxNodeBit && getBit(Self.sceneDoneWord, n)
    }

    /// edge_seen(id) for an edge id 564..1267.
    public func isEdgeSeen(_ id: Int) -> Bool {
        id >= Self.firstEdgeId && id < Self.firstEdgeId + Self.edgeBits && getBit(Self.edgeSeenWord, id - Self.firstEdgeId)
    }

    func allEndingsDone() -> Bool {
        for n in 533...556 {
            if !isSceneDone(n) {
                return false
            }
        }
        return true
    }

    func cmdRdst(_ st: Statement) -> StepResult {
        let n = StageArgs(st).expr(0)
        if n >= 0 && n <= Self.maxNodeBit {
            setBit(Self.sceneSeenWord, n)
        }
        return StepResult.continue
    }

    func cmdRtst(_ st: Statement) -> StepResult {
        let n = StageArgs(st).expr(0)
        if n >= 0 && n <= Self.maxNodeBit {
            setPlayBit(Self.routeNodeWord, n)
            if (n >= 533 && n <= 557) || f(24) != 0 {
                setF(110, n)
            }
        }
        return StepResult.continue
    }

    func cmdRded(_ st: Statement) -> StepResult {
        let n = StageArgs(st).expr(0)
        if n >= 0 && n <= Self.maxNodeBit && n == f(110) && playBit(Self.routeNodeWord, n) {
            setBit(Self.sceneDoneWord, n)
            endSceneSkip()
            nodeCompleted?(n)
            if archiveMode {
                return scriptEnd(reason: .returnToTitle, keepBgm: false)
            }
        }
        return StepResult.continue
    }

    func cmdRdas(_ st: Statement) -> StepResult {
        let n = StageArgs(st).expr(0)
        if n >= 0 && n <= Self.maxNodeBit && !archiveMode && isSceneDone(n) && config.autoSkipCleared != 0 {
            autoSkipOffered?(n)
        }
        return StepResult.continue
    }

    func markSceneJump(fromScript: Int, toSceneId: Int) {
        let from = flow.nodeOfScript(fromScript)
        let toScript = flow.scriptOfSceneId(toSceneId)
        let to = toScript < 0 ? -1 : flow.nodeOfScript(toScript)
        if to >= 1 && from >= 1 && from <= 530 {
            for e in flow.edges {
                if e.from == from && e.to == to {
                    for id in e.globalIds {
                        if id >= Self.firstEdgeId && id - Self.firstEdgeId < Self.edgeBits {
                            setBit(Self.edgeSeenWord, id - Self.firstEdgeId)
                        }
                    }
                    for id in e.playthroughIds {
                        if id >= Self.firstEdgeId && id - Self.firstEdgeId < Self.edgeBits {
                            setPlayBit(Self.routeEdgeWord, id - Self.firstEdgeId)
                        }
                    }
                    break
                }
            }
            setF(110, to)
        }
    }

    func cmdXstp() -> StepResult {
        staffTask = true
        setF(36, 1)
        return StepResult.continue
    }

    func cmdXrsm() -> StepResult {
        if staffTask {
            staffTask = false
            setF(36, 0)
        }
        return StepResult.continue
    }

    // MARK: - Flowchart Jump

    /// Jumps to flowchart node `node` (an RTST bit): returns false when the node has no scene to start.
    public func jumpToNode(_ node: Int) -> Bool {
        for row in flow.nodes {
            if row.scene == node && row.scriptScene >= 0 {
                return jumpToRecord(column: row.column, node: node, sceneId: row.scriptScene)
            }
        }
        return false
    }

    /// The flowchart jump for the record under the cursor: column `column`, node `node`, scene id `sceneId`.
    public func jumpToRecord(column: Int, node: Int, sceneId: Int) -> Bool {
        if sceneId >= 0 && flow.scriptOfSceneId(sceneId) < 0 {
            return false
        }

        let nodes = flow.nodes
        for i in stride(from: nodes.count - 1, through: 0, by: -1) {
            let r = nodes[i]
            if r.column <= column || r.group < 1 {
                break
            }

            if r.scene != 0 && abs(r.scene) < Self.maxNodeBit + 1 {
                clearPlayBit(firstWord: Self.routeNodeWord, bit: abs(r.scene))
            }

            let e = r.link - Self.firstEdgeId
            if e >= 0 && e < Self.edgeBits {
                clearPlayBit(firstWord: Self.routeEdgeWord, bit: e)
            }
        }

        for (limit, word) in flow.jumpClears {
            if column <= limit {
                setF(word, 0)
            }
        }

        setF(110, node)
        setF(26, sceneId)
        setF(1103, 1)
        let zeroes = [823, 847, 1104, 1105, 1106, 1107, 1108, 1109, 1110, 1111, 1112, 1113]
        for w in zeroes {
            setF(w, 0)
        }

        if sceneId < 0 {
            return false
        }

        let words = flow.jumpKeepWords.map { (w: $0, v: vars.getF($0)) }
        let bytes = flow.jumpKeepBytes.map { (w: $0, v: UInt16(bitPattern: Int16(Int8(truncatingIfNeeded: vars.getF($0))))) }
        let bits = flow.jumpKeepBits.filter { vars.getF($0) != 0 }

        profile.clearPlaythrough()
        resetRuntime()
        for (w, v) in words + bytes {
            vars.setF(w, v)
        }

        for w in bits {
            vars.setF(w, 1)
        }

        setF(110, node)
        setF(26, sceneId)

        if !enterScene(sceneId, label: nil, jump: false) {
            phase = .ended
            endReason = .missingScene
            return false
        }

        return true
    }

    private func clearPlayBit(firstWord: Int, bit: Int) {
        let w = firstWord + (bit >> 3)
        vars.setF(w, vars.getF(w) & ~UInt16(1 << (bit & 7)))
    }
}
