import Foundation
import TsukiCore
import TsukiData
import TsukiEngine

public final class ChoiceBlock: Sendable {
    public let script: Int
    public let gotsOffset: Int
    public let nextScriptByValue: [Int: Int]

    public init(script: Int, gotsOffset: Int, nextScriptByValue: [Int: Int]) {
        self.script = script
        self.gotsOffset = gotsOffset
        self.nextScriptByValue = nextScriptByValue
    }
}

public final class SceneGraph {
    private var edges: [(from: Int, to: Int)] = []
    private var outEdges: [Int: [Int]] = [:]
    private var blocksMap: [String: ChoiceBlock] = [:]
    private var blocksOfList: [[ChoiceBlock]]

    private init(count: Int) {
        blocksOfList = Array(repeating: [], count: count)
    }

    public func blocksOf(_ script: Int) -> [ChoiceBlock] {
        guard script >= 0 && script < blocksOfList.count else { return [] }
        return blocksOfList[script]
    }

    public func successors(_ script: Int) -> [Int] {
        outEdges[script] ?? []
    }

    public func blockAt(_ script: Int, _ cursor: Int) -> ChoiceBlock? {
        guard script >= 0 && script < blocksOfList.count else { return nil }
        var best: ChoiceBlock? = nil
        for b in blocksOfList[script] {
            if b.gotsOffset >= cursor && (best == nil || b.gotsOffset < best!.gotsOffset) {
                best = b
            }
        }
        return best
    }

    public static func build(_ scripts: FlowScripts, _ flow: GameFlowTables) -> SceneGraph {
        let g = SceneGraph(count: flow.sceneCount)
        for k in 0..<flow.sceneCount {
            let image = scripts.script(k)
            let labels = scripts.labels(k)
            let bytes = image.bytes
            let span = ByteSpan(bytes)
            var jumps: [(offset: Int, target: Int)] = []
            var gots: [(offset: Int, labels: [String])] = []

            var pos = 0
            while pos < span.count {
                guard let seg = try? ScriptSegmenter.read(span, pos) else { break }
                pos = seg.end
                guard let st = ScriptSegmenter.statement(k, span, seg) else { continue }

                if st.name.first == UInt8(ascii: "J") {
                    let a = args(st)
                    if let first = a.first, let id = Int(first) {
                        let to = flow.scriptOfSceneId(id)
                        if to >= 0 {
                            jumps.append((st.offset, to))
                            g.addEdge(from: k, to: to)
                        }
                    }
                } else if st.name.description == "GOTS" {
                    let a = args(st)
                    if a.count > 1 {
                        gots.append((st.offset, Array(a.dropFirst())))
                    }
                }
            }

            for (offset, names) in gots {
                var map: [Int: Int] = [:]
                for v in 0..<names.count {
                    let at = labels.find(names[v])
                    if at < 0 { continue }
                    for (jo, target) in jumps {
                        if jo >= at {
                            map[v] = target
                            break
                        }
                    }
                }

                let block = ChoiceBlock(script: k, gotsOffset: offset, nextScriptByValue: map)
                g.blocksMap["\(k),\(offset)"] = block
                g.blocksOfList[k].append(block)
            }
        }
        return g
    }

    private func addEdge(from: Int, to: Int) {
        if outEdges[from] == nil {
            outEdges[from] = []
        }
        if !(outEdges[from]!.contains(to)) {
            outEdges[from]!.append(to)
            edges.append((from, to))
        }
    }

    public static func args(_ st: Statement) -> [String] {
        let span = st.args
        var ranges: [ArgRange] = []
        ranges.reserveCapacity(8)
        _ = ArgumentList.split(span, ArgumentList.startIn(st), into: &ranges)
        var result: [String] = []
        result.reserveCapacity(ranges.count)
        for r in ranges {
            let slice = span.slice(r.start, r.length)
            result.append(latin1(slice.toArray()))
        }
        return result
    }

    public func reachable(_ start: Int) -> Set<Int> {
        var seen = Set<Int>([start])
        var queue = [start]
        var head = 0
        while head < queue.count {
            let s = queue[head]
            head += 1
            for t in successors(s) {
                if seen.insert(t).inserted {
                    queue.append(t)
                }
            }
        }
        return seen
    }

    public func path(_ start: Int, _ target: Int, avoid: Set<Int>? = nil) -> [Int]? {
        var prev: [Int: Int] = [start: -1]
        var queue = [start]
        var head = 0
        while head < queue.count {
            let s = queue[head]
            head += 1
            if s == target { break }
            for t in successors(s) {
                if let avoid = avoid, avoid.contains(t) && t != target {
                    continue
                }
                if prev[t] == nil {
                    prev[t] = s
                    queue.append(t)
                }
            }
        }

        guard prev[target] != nil else { return nil }
        var result: [Int] = []
        var cur = target
        while cur != -1 {
            result.append(cur)
            cur = prev[cur]!
        }
        result.reverse()
        return result
    }
}
