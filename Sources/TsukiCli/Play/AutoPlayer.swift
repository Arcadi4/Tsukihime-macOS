import Foundation
import TsukiCore
import TsukiEngine

public class ChoicePolicy {
    public func pick(_ host: GameHost, point: Int) -> Int {
        fatalError("abstract")
    }

    public static func unlocked(_ host: GameHost) -> [Int] {
        var l: [Int] = []
        for i in 0..<host.choiceLines.count {
            if !host.choiceLines[i].locked {
                l.append(i)
            }
        }
        if l.isEmpty {
            for i in 0..<host.choiceLines.count {
                l.append(i)
            }
        }
        return l
    }

    public static func parse(_ text: String) throws -> ChoicePolicy {
        let p = text.split(separator: ":", maxSplits: 1).map(String.init)
        switch p[0].lowercased() {
        case "first":
            return FirstPolicy()
        case "last":
            return LastPolicy()
        case "random":
            let seed = p.count > 1 ? (Int(p[1]) ?? 1) : 1
            return RandomPolicy(seed: seed)
        case "list":
            let picks = p.count > 1
                ? p[1].split(separator: ",").compactMap { Int($0) }
                : []
            return ListPolicy(picks: picks)
        default:
            throw TsukiError.format("unknown choice policy '\(text)' (first, last, random[:seed], list:i,j,...)")
        }
    }
}

public final class FirstPolicy: ChoicePolicy {
    public override func pick(_ host: GameHost, point: Int) -> Int {
        Self.unlocked(host)[0]
    }
}

public final class LastPolicy: ChoicePolicy {
    public override func pick(_ host: GameHost, point: Int) -> Int {
        Self.unlocked(host).last!
    }
}

public final class RandomPolicy: ChoicePolicy {
    private var seed: UInt64

    public init(seed: Int) {
        self.seed = UInt64(seed)
    }

    private func nextRandom(_ bound: Int) -> Int {
        // Linear congruential generator
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let val = Int((seed >> 32) & 0x7FFFFFFF)
        return val % bound
    }

    public override func pick(_ host: GameHost, point: Int) -> Int {
        let u = Self.unlocked(host)
        return u[nextRandom(u.count)]
    }
}

public final class ListPolicy: ChoicePolicy {
    private let picks: [Int]
    private var nextIdx = 0

    public init(picks: [Int]) {
        self.picks = picks
    }

    public override func pick(_ host: GameHost, point: Int) -> Int {
        let u = Self.unlocked(host)
        let want = nextIdx < picks.count ? picks[nextIdx] : 0
        nextIdx += 1
        return u.contains(want) ? want : u[0]
    }
}

public final class CoveragePolicy: ChoicePolicy {
    private var taken: [String: Int] = [:]
    private var seed: UInt64

    public init(seed: Int = 1) {
        self.seed = UInt64(seed)
    }

    public var distinct: Int { taken.count }

    private func nextRandom(_ bound: Int) -> Int {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let val = Int((seed >> 32) & 0x7FFFFFFF)
        return val % bound
    }

    public override func pick(_ host: GameHost, point: Int) -> Int {
        let u = Self.unlocked(host)
        var best = u[0]
        var bestCount = Int.max
        var ties: [Int] = []

        for i in u {
            let key = "\(point),\(host.choiceLines[i].value)"
            let c = taken[key] ?? 0
            if c < bestCount {
                bestCount = c
                ties.removeAll()
                ties.append(i)
            } else if c == bestCount {
                ties.append(i)
            }
        }

        best = ties[ties.count == 1 ? 0 : nextRandom(ties.count)]
        let key = "\(point),\(host.choiceLines[best].value)"
        taken[key] = (taken[key] ?? 0) + 1
        return best
    }
}

public final class TargetPolicy: ChoicePolicy {
    private let graph: SceneGraph
    private let path: [Int]
    private let fallback: ChoicePolicy

    public init(graph: SceneGraph, path: [Int], fallback: ChoicePolicy) {
        self.graph = graph
        self.path = path
        self.fallback = fallback
    }

    public override func pick(_ host: GameHost, point: Int) -> Int {
        let s = host.script
        if let at = path.firstIndex(of: s), at + 1 < path.count {
            if let block = graph.blockAt(s, host.machine.cursor) {
                for i in 0..<host.choiceLines.count {
                    let l = host.choiceLines[i]
                    if !l.locked, let next = block.nextScriptByValue[l.value], next == path[at + 1] {
                        return i
                    }
                }
            }
        }
        return fallback.pick(host, point: point)
    }
}

public enum PlayMode: Sendable {
    case click
    case skip
    case auto
}

public final class AutoPlayer {
    private let policy: ChoicePolicy
    private let mode: PlayMode
    private let dialogAnswer: Int
    private var held: PadButtons = []
    private var frame: Int64 = 0

    public private(set) var choicesTaken = 0
    public var chose: ((Int, Int, Int, Int) -> Void)?

    public init(policy: ChoicePolicy, mode: PlayMode, dialogAnswer: Int = 1) {
        self.policy = policy
        self.mode = mode
        self.dialogAnswer = dialogAnswer
    }

    public func next(_ host: GameHost) -> InputFrame {
        frame += 1
        if host.choiceSelectable {
            let point = host.choicePoint
            if host.choiceKind == .list {
                let pick = policy.pick(host, point: point)
                let value = host.choiceLines[pick].value
                let count = host.choiceLines.count
                _ = host.choose(pick)
                choicesTaken += 1
                chose?(point, pick, value, count)
            } else {
                let answer = host.choiceKind == .savePrompt ? 0 : dialogAnswer
                _ = host.choose(answer)
                choicesTaken += 1
                chose?(point, answer, answer, 2)
            }
        }

        var nextHeld: PadButtons = []
        switch mode {
        case .click:
            nextHeld = (frame & 1) == 0 ? .decide : []
        case .skip:
            nextHeld = (frame & 1) == 0 ? .decide : []
            if !host.movieActive {
                host.setSkipLatch(true)
            }
        case .auto:
            host.setAutoMode(true)
        }

        let pressed = nextHeld.subtracting(held)
        held = nextHeld
        return InputFrame(frame: frame, held: held, pressed: pressed, repeated: pressed)
    }
}
