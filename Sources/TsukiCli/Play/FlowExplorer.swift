import Foundation
import TsukiCore
import TsukiData
import TsukiEngine

public final class PathNode {
    public let parent: PathNode?
    public let script: Int
    public let option: Int

    public init(parent: PathNode?, script: Int, option: Int) {
        self.parent = parent
        self.script = script
        self.option = option
    }
}

public final class ProfileRun {
    public let previous: ProfileRun?
    public let path: PathNode?

    public init(previous: ProfileRun?, path: PathNode?) {
        self.previous = previous
        self.path = path
    }
}

public final class ExploreResult {
    public var first: [Int: ProfileRun] = [:]
    public var expansions: Int64 = 0
    public var states: Int64 = 0
    public var profiles: Int = 0
    public var budgetHit: Bool = false
    public var ends: [Int: ProfileRun] = [:]

    public func chainOf(_ k: Int) -> [[Int]] {
        guard let run = first[k] else { return [] }
        return Self.chainOf(run)
    }

    public static func chainOf(_ run: ProfileRun) -> [[Int]] {
        var runs: [ProfileRun] = []
        var cur: ProfileRun? = run
        while let r = cur {
            runs.append(r)
            cur = r.previous
        }
        runs.reverse()

        var result: [[Int]] = []
        for r in runs {
            var options: [Int] = []
            var p = r.path
            while let node = p {
                options.append(node.option)
                p = node.parent
            }
            options.reverse()
            result.append(options)
        }
        return result
    }
}

public final class FlowExplorer {
    private static let varWords = Vars.wordCount
    private static let gBase = Vars.gWord

    private let scripts: FlowScripts
    private let flow: GameFlowTables
    private let relevant: Set<Int>
    private let relevantList: [Int]

    public init(scripts: FlowScripts, flow: GameFlowTables) {
        self.scripts = scripts
        self.flow = flow
        self.relevant = Self.analyze(scripts, flow.sceneCount)
        self.relevantList = self.relevant.sorted()
    }

    public var relevantWords: Set<Int> { relevant }

    private static func wordOf(_ op: VarOperand) -> Int {
        switch op.kind {
        case .f:
            return op.index
        case .g:
            return gBase + op.index
        default:
            return -1
        }
    }

    private static func analyze(_ scripts: FlowScripts, _ count: Int) -> Set<Int> {
        var relevant = Set<Int>()
        var copies: [(from: Int, to: Int)] = []

        for k in 0..<count {
            let image = scripts.script(k)
            let bytes = image.bytes
            let span = ByteSpan(bytes)
            var pos = 0
            while pos < span.count {
                guard let seg = try? ScriptSegmenter.read(span, pos) else { break }
                pos = seg.end
                guard let st = ScriptSegmenter.statement(k, span, seg) else { continue }

                let name = st.name.description
                switch name {
                case "IF__":
                    let a = SceneGraph.args(st)
                    for i in [0, 2] {
                        if i < a.count {
                            let w = wordOf(VarOperand.parse(a[i], .value))
                            if w >= 0 { relevant.insert(w) }
                        }
                    }
                case "GOTS":
                    let a = SceneGraph.args(st)
                    if let first = a.first {
                        let w = wordOf(VarOperand.parse(first, .gots))
                        if w >= 0 { relevant.insert(w) }
                    }
                case "WKST":
                    let a = SceneGraph.args(st)
                    if a.count >= 3 {
                        let to = wordOf(VarOperand.parse(a[0], .wkTarget))
                        let from = wordOf(VarOperand.parse(a[2], .value))
                        if to >= 0 && from >= 0 {
                            copies.append((from: from, to: to))
                        }
                    }
                default:
                    break
                }
            }
        }

        var changed = true
        while changed {
            changed = false
            for c in copies {
                if relevant.contains(c.to) && !relevant.contains(c.from) {
                    relevant.insert(c.from)
                    changed = true
                }
            }
        }
        return relevant
    }

    private final class FlowHost: ScriptHost {
        let owner: FlowExplorer
        let vars: VarState
        var choiceOpen = false
        var ended = false
        var missing = false
        var entered: Set<Int> = []
        var script: Int = 0

        init(owner: FlowExplorer, vars: VarState) {
            self.owner = owner
            self.vars = vars
        }

        func dispatch(_ st: Statement) -> StepResult {
            let name = st.name.description
            switch name {
            case "SELD":
                choiceOpen = true
                return .yield
            case "SELA":
                reset()
                return .continue
            case "SELS":
                _ = try? VarCommands.choiceStore(vars, 1)
                reset()
                return .continue
            case "END_", "RTM_", "RTMN":
                ended = true
                return .halt
            case "IFSC":
                return jumpToLabel(st, argIndex: 1, condition: true)
            case "IFLA":
                let langVal = InlineReader.readInt16(st, 0)
                return jumpToLabel(st, argIndex: 1, condition: langVal != Int(Language.en.rawValue))
            case "RDST":
                let n = StageArgs(st).expr(0)
                if n >= 0 && n <= 0x23F {
                    let w = Vars.gWord + 110 + (n >> 4)
                    let cur = vars.memory.block.getWord(w)
                    vars.memory.block.setWord(w, cur | UInt16(1 << (n & 15)))
                }
                return .continue
            default:
                break
            }

            if st.name.first == UInt8(ascii: "J") {
                return jump(st)
            }

            return .continue
        }

        func reset() {
            vars.choiceMode = ChoiceMode.none.rawValue
            vars.choiceCount = 0
            vars.choiceValues.removeAll()
            vars.choiceLocked.removeAll()
            choiceOpen = false
        }

        private func jumpToLabel(_ st: Statement, argIndex: Int, condition: Bool) -> StepResult {
            guard condition else { return .continue }
            let a = SceneGraph.args(st)
            guard argIndex < a.count && !a[argIndex].isEmpty else { return .continue }
            let off = owner.scripts.labels(script).find(a[argIndex])
            return off < 0 ? .continue : .continueAt(ScriptPosition(script: script, offset: off))
        }

        private func jump(_ st: Statement) -> StepResult {
            let a = SceneGraph.args(st)
            let id = (a.count > 0 ? Int(a[0]) : nil) ?? -1
            var k = owner.flow.scriptOfSceneId(id)
            if k < 0 {
                k = owner.flow.scriptOfSceneId(110)
            }

            var offset = 0
            if a.count > 1 && !a[1].isEmpty {
                offset = owner.scripts.labels(k).find(a[1])
                if offset < 0 {
                    missing = true
                    return .halt
                }
            }

            script = k
            entered.insert(k)
            return .continueAt(ScriptPosition(script: k, offset: offset))
        }
    }

    private final class Snapshot {
        var words: [UInt16] = []
        var script: Int = 0
        var cursor: Int = 0
        var count: Int = 0
        var values: [UInt16] = []
        var locked: [Bool] = []
        var kind: UInt8 = 0
        var index: UInt16 = 0
        var id: Int16 = 0
        var mode: UInt32 = 0
        var path: PathNode?
        var chain: ProfileRun?
        var depth: Int = 0
    }

    private var pending: [(words: [UInt16], chain: ProfileRun?)] = []
    private var predecessors: [[Int]] = []

    private static func key(_ s: Snapshot) -> UInt64 {
        var h: UInt64 = 14695981039346656037
        h = (h ^ UInt64(UInt32(s.script))) &* 1099511628211
        h = (h ^ UInt64(UInt32(s.cursor))) &* 1099511628211
        for w in s.words {
            h = (h ^ UInt64(w)) &* 1099511628211
        }
        return h
    }

    private func profileKey(_ words: [UInt16]) -> UInt64 {
        var h: UInt64 = 14695981039346656037
        for i in 0..<relevantList.count {
            if relevantList[i] >= Self.gBase {
                h = (h ^ UInt64(words[i])) &* 1099511628211
            }
        }
        return h
    }

    private func distancesTo(_ reached: Set<Int>) -> [Int] {
        let n = flow.sceneCount
        var dist = [Int](repeating: Int.max, count: n)
        var q = [Int]()
        for k in 0..<n {
            if !reached.contains(k) {
                dist[k] = 0
                q.append(k)
            }
        }
        var head = 0
        while head < q.count {
            let t = q[head]
            head += 1
            for p in predecessors[t] {
                if dist[p] == Int.max {
                    dist[p] = dist[t] + 1
                    q.append(p)
                }
            }
        }
        return dist
    }

    private func words(_ vars: Vars) -> [UInt16] {
        var w = [UInt16](repeating: 0, count: relevantList.count)
        for i in 0..<w.count {
            w[i] = vars.getWord(relevantList[i])
        }
        return w
    }

    private func capture(_ vm: ScriptVm, _ state: VarState, _ vars: Vars, _ path: PathNode?, _ chain: ProfileRun?, _ depth: Int) -> Snapshot {
        let s = Snapshot()
        s.words = words(vars)
        s.script = vm.image.index
        s.cursor = vm.cursor
        s.count = state.choiceCount
        s.values = state.choiceValues
        s.locked = state.choiceLocked
        s.kind = state.choiceKind
        s.index = state.choiceIndex
        s.id = state.choiceId
        s.mode = state.choiceMode
        s.path = path
        s.chain = chain
        s.depth = depth
        return s
    }

    private func restore(_ s: Snapshot, _ vm: ScriptVm, _ state: VarState, _ vars: Vars, _ host: FlowHost) {
        vars.clear()
        for i in 0..<relevantList.count {
            vars.setWord(relevantList[i], s.words[i])
        }
        vm.seek(ScriptPosition(script: s.script, offset: s.cursor))
        state.choiceCount = s.count
        state.choiceValues = s.values
        state.choiceLocked = s.locked
        state.choiceKind = s.kind
        state.choiceIndex = s.index
        state.choiceId = s.id
        state.choiceMode = s.mode
        host.script = s.script
        host.choiceOpen = true
    }

    public func explore(maxExpansions: Int64 = 5_000_000) -> ExploreResult {
        let graph = SceneGraph.build(scripts, flow)
        predecessors = Array(repeating: [], count: flow.sceneCount)
        for k in 0..<flow.sceneCount {
            for t in graph.successors(k) {
                predecessors[t].append(k)
            }
        }

        let result = ExploreResult()
        var reached = Set<Int>()
        var dist = distancesTo(reached)

        // Simple binary heap priority queue
        var frontier: [(snap: Snapshot, priority: (dist: Int, depth: Int))] = []

        func enqueue(_ snap: Snapshot, priority: (dist: Int, depth: Int)) {
            frontier.append((snap, priority))
            var idx = frontier.count - 1
            while idx > 0 {
                let parent = (idx - 1) / 2
                let p1 = frontier[idx].priority
                let p2 = frontier[parent].priority
                if p1.dist < p2.dist || (p1.dist == p2.dist && p1.depth < p2.depth) {
                    frontier.swapAt(idx, parent)
                    idx = parent
                } else {
                    break
                }
            }
        }

        func dequeue() -> Snapshot? {
            guard !frontier.isEmpty else { return nil }
            let item = frontier[0].snap
            let last = frontier.removeLast()
            if !frontier.isEmpty {
                frontier[0] = last
                var idx = 0
                while true {
                    let left = 2 * idx + 1
                    let right = 2 * idx + 2
                    var smallest = idx
                    if left < frontier.count {
                        let p1 = frontier[left].priority
                        let p2 = frontier[smallest].priority
                        if p1.dist < p2.dist || (p1.dist == p2.dist && p1.depth < p2.depth) {
                            smallest = left
                        }
                    }
                    if right < frontier.count {
                        let p1 = frontier[right].priority
                        let p2 = frontier[smallest].priority
                        if p1.dist < p2.dist || (p1.dist == p2.dist && p1.depth < p2.depth) {
                            smallest = right
                        }
                    }
                    if smallest != idx {
                        frontier.swapAt(idx, smallest)
                        idx = smallest
                    } else {
                        break
                    }
                }
            }
            return item
        }

        var visited = Set<UInt64>()
        var profileSeen = Set<UInt64>()
        let vars = Vars()
        let state = VarState(VarMemory(vars, policy: .flat))
        let host = FlowHost(owner: self, vars: state)
        let vm = ScriptVm(scripts, state, MarkerState(SystemBlock()), flow.scriptOfSceneId(110))

        func enter(_ script: Int, _ chain: ProfileRun?, _ path: PathNode?) {
            if reached.insert(script).inserted {
                result.first[script] = ProfileRun(previous: chain, path: path)
                dist = distancesTo(reached)
            }
        }

        func advance(_ path: PathNode?, _ chain: ProfileRun?, _ depth: Int) {
            var guardCount = 0
            while guardCount < 100_000 {
                guardCount += 1
                host.entered.removeAll()
                let end = (try? vm.step(host)) ?? .halted
                for k in host.entered {
                    enter(k, chain, path)
                }
                host.script = vm.image.index
                if host.choiceOpen {
                    let snap = capture(vm, state, vars, path, chain, depth)
                    enqueue(snap, priority: (dist[snap.script], depth))
                    return
                }

                if host.ended || host.missing || end == .endOfScript || end == .halted {
                    if host.ended {
                        if result.ends[vm.image.index] == nil {
                            result.ends[vm.image.index] = ProfileRun(previous: chain, path: path)
                        }
                        let next = words(vars)
                        if profileSeen.insert(profileKey(next)).inserted {
                            pending.append((next, ProfileRun(previous: chain, path: path)))
                        }
                    }
                    host.ended = false
                    host.missing = false
                    return
                }
            }
        }

        func startPlaythrough(_ words: [UInt16], _ chain: ProfileRun?) {
            vars.clear()
            for i in 0..<relevantList.count {
                if relevantList[i] >= Self.gBase {
                    vars.setWord(relevantList[i], words[i])
                }
            }
            let start = flow.scriptOfSceneId(110)
            vm.seek(ScriptPosition(script: start, offset: 0))
            host.script = start
            host.reset()
            host.ended = false
            host.missing = false
            enter(start, chain, nil)
            advance(nil, chain, 0)
        }

        let initial = [UInt16](repeating: 0, count: relevantList.count)
        profileSeen.insert(profileKey(initial))
        pending.append((initial, nil))

        while (!pending.isEmpty || !frontier.isEmpty) && result.expansions < maxExpansions {
            if !pending.isEmpty {
                let (words, chain) = pending.removeFirst()
                result.profiles += 1
                startPlaythrough(words, chain)
                continue
            }

            guard let s = dequeue() else { break }
            if !visited.insert(Self.key(s)).inserted {
                continue
            }

            result.states += 1
            for option in 0..<s.count {
                if s.mode == ChoiceMode.list.rawValue && s.locked.count > option && s.locked[option] {
                    continue
                }
                result.expansions += 1
                restore(s, vm, state, vars, host)
                _ = try? VarCommands.choiceStore(state, option)
                host.reset()
                let path = PathNode(parent: s.path, script: s.script, option: option)
                advance(path, s.chain, s.depth + 1)
            }
        }

        result.budgetHit = result.expansions >= maxExpansions
        return result
    }
}
