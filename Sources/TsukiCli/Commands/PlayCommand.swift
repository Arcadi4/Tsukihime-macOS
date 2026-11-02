import Foundation
import TsukiCore
import TsukiEngine
import TsukiData

public final class PlayCommand: CliCommand {
    public var name: String { "play" }
    public var summary: String {
        "play the game headless: --policy first|last|random[:seed]|list:i,j  --mode click|skip|auto  --until-first-choice  --games N  --trace FILE  --coverage [--no-aim] [--no-jump] [--explore-budget N]  --explore  (see docs/status/knife/K3.md)"
    }

    public init() {}

    private final class Options {
        var game: String?
        var language: Language = .en
        var policy: String = "first"
        var mode: PlayMode = .click
        var maxFrames: Int64 = 20_000_000
        var maxGames: Int = 1
        var untilFirstChoice: Bool = false
        var tracePath: String?
        var traceVars: Bool = false
        var textSpeed: Int?
        var seed: Int = 1
        var scene: Int?
        var coverage: Bool = false
        var maxRuns: Int = 200
        var patience: Int = 6
        var verbose: Bool = false
        var strict: Bool = false
        var noAim: Bool = false
        var noJump: Bool = false
        var explore: Bool = false
        var exploreDump: String?
        var listScenes: Bool = false
        var aim: Bool = false
        var exploreBudget: Int64 = 1_000_000
        var target: String?
        var globals: [(index: Int, value: Int)] = []
        var maxRounds: Int = 12
        var maxAimRuns: Int = 3000
    }

    private final class Report {
        var firstChoice: String?
        var exceptions: [String] = []
        var messages: Int64 = 0
        var movies: Int64 = 0
    }

    public func run(_ args: [String], output: CliWriter, error: CliWriter) -> Int {
        guard let o = parse(args, error: error) else {
            return ExitCode.usage
        }

        guard let folder = GameFolderLocator.resolve(o.game) else {
            error.writeLine("play: no game folder; pass --game <dir> or set TSUKI_GAME_DIR")
            return ExitCode.usage
        }

        let ebootPath = (folder as NSString).appendingPathComponent("eboot.bin")
        if !FileManager.default.fileExists(atPath: ebootPath) {
            error.writeLine("play: no game folder; pass --game <dir> or set TSUKI_GAME_DIR")
            return ExitCode.usage
        }

        let rig: HeadlessRig
        do {
            rig = try HeadlessRig.open(folder)
        } catch let err {
            error.writeLine("play: \(err)")
            return ExitCode.failed
        }
        defer { rig.dispose() }

        if !rig.source.build.isAnalysedBuild {
            error.writeLine("play: \(folder) is not the analysed build (eboot.bin SHA-256 \(rig.source.build.ebootSHA256)); run `verify` first")
            return ExitCode.failed
        }

        let scriptCount = (try? rig.source.scripts.count) ?? 549
        let scriptNames = (try? rig.source.scripts.names) ?? []

        if o.listScenes {
            let flowTables = rig.source.eboot.gameFlow
            let jumps = SceneGraph.build(rig.services.scripts, flowTables)
            for k in 0..<scriptCount {
                let sName = k < scriptNames.count ? scriptNames[k] : "\(k)"
                let succ = jumps.successors(k).map(String.init).joined(separator: ",")
                output.writeLine("\(k)\t\(sName)\tscene \(flowTables.sceneId(k))\tnode \(flowTables.nodeOfScript(k))\tjumps \(succ)")
            }
            return ExitCode.ok
        }

        var traceHandle: FileHandle? = nil
        if let tp = o.tracePath {
            FileManager.default.createFile(atPath: tp, contents: nil)
            traceHandle = FileHandle(forWritingAtPath: tp)
        }
        defer { try? traceHandle?.close() }

        if o.explore {
            var reached = Set<Int>()
            exploreAndReplay(rig: rig, o: o, output: output, reached: &reached)
            return ExitCode.ok
        }

        return o.coverage ? runCoverage(rig: rig, o: o, output: output, trace: traceHandle) : runSession(rig: rig, o: o, output: output, trace: traceHandle)
    }

    private func parse(_ args: [String], error: CliWriter) -> Options? {
        let o = Options()
        var i = 0
        while i < args.count {
            let a = args[i]
            func nextArg() -> String? {
                if i + 1 < args.count {
                    i += 1
                    return args[i]
                }
                return nil
            }

            switch a {
            case "--game":
                o.game = nextArg()
            case "--lang":
                let l = (nextArg() ?? "").lowercased()
                switch l {
                case "ja": o.language = .ja
                case "en": o.language = .en
                case "zc": o.language = .zc
                case "zt": o.language = .zt
                default: o.language = .en
                }
            case "--policy":
                o.policy = nextArg() ?? "first"
            case "--mode":
                let m = (nextArg() ?? "").lowercased()
                switch m {
                case "skip": o.mode = .skip
                case "auto": o.mode = .auto
                default: o.mode = .click
                }
            case "--max-frames":
                if let v = nextArg(), let n = Int64(v) { o.maxFrames = n }
            case "--games":
                if let v = nextArg(), let n = Int(v) { o.maxGames = n }
            case "--until-first-choice":
                o.untilFirstChoice = true
            case "--trace":
                o.tracePath = nextArg()
            case "--trace-vars":
                o.traceVars = true
            case "--text-speed":
                if let v = nextArg(), let n = Int(v) { o.textSpeed = n }
            case "--seed":
                if let v = nextArg(), let n = Int(v) { o.seed = n }
            case "--scene":
                if let v = nextArg(), let n = Int(v) { o.scene = n }
            case "--coverage":
                o.coverage = true
            case "--max-runs":
                if let v = nextArg(), let n = Int(v) { o.maxRuns = n }
            case "--patience":
                if let v = nextArg(), let n = Int(v) { o.patience = n }
            case "-v", "--verbose":
                o.verbose = true
            case "--strict":
                o.strict = true
            case "--no-aim":
                o.noAim = true
            case "--no-jump":
                o.noJump = true
            case "--explore":
                o.explore = true
            case "--explore-dump":
                o.exploreDump = nextArg()
            case "--list-scenes":
                o.listScenes = true
            case "--aim":
                o.aim = true
            case "--explore-budget":
                if let v = nextArg(), let n = Int64(v) { o.exploreBudget = n }
            case "--target":
                o.target = nextArg()
            case "--set-g":
                if let v = nextArg() {
                    let parts = v.split(separator: "=").map(String.init)
                    if parts.count == 2, let idx = Int(parts[0]), let val = Int(parts[1]) {
                        o.globals.append((idx, val))
                    }
                }
            default:
                error.writeLine("play: unexpected argument '\(a)'")
                return nil
            }
            i += 1
        }
        return o
    }

    private func createHost(_ rig: HeadlessRig, _ o: Options, _ profile: GameProfile?) -> GameHost {
        let options = GameOptions()
        options.language = o.language
        options.virtualMovies = true
        options.strictCommands = o.strict
        options.randomSeed = UInt32(truncatingIfNeeded: o.seed)
        options.recordUnknownCommands = !o.strict
        let host = GameHost(services: rig.services, options: options, profile: profile)
        if let speed = o.textSpeed {
            host.config.unseenTextSpeed = UInt16(speed)
            host.config.seenTextSpeed = UInt16(speed)
        }
        if o.mode == .skip {
            host.config.fastForwardReadOnly = 0
        }
        for (index, value) in o.globals {
            host.vars.setG(index, UInt16(truncatingIfNeeded: value))
        }
        return host
    }

    private func runSession(rig: HeadlessRig, o: Options, output: CliWriter, trace: FileHandle?) -> Int {
        let host = createHost(rig, o, nil)
        var policy: ChoicePolicy = (try? ChoicePolicy.parse(o.policy)) ?? FirstPolicy()

        let scriptCount = (try? rig.source.scripts.count) ?? 549
        let scriptNames = (try? rig.source.scripts.names) ?? []

        if let targetName = o.target {
            if let k = scriptNames.firstIndex(of: targetName) {
                let graph = SceneGraph.build(rig.services.scripts, rig.source.eboot.gameFlow)
                let path = graph.path(0, k)
                let pathDesc = path?.map { $0 < scriptNames.count ? scriptNames[$0] : "\($0)" }.joined(separator: " > ") ?? "none"
                output.writeLine("target \(targetName): path \(pathDesc)")
                policy = TargetPolicy(graph: graph, path: path ?? [], fallback: RandomPolicy(seed: o.seed))
            }
        }

        let player = AutoPlayer(policy: policy, mode: o.mode)
        let report = Report()
        attach(host: host, rig: rig, o: o, trace: trace, player: player, report: report)

        writeTrace(trace, "# boot: fresh profile, language \(o.language), system data created, title screen (G002 = \(host.vars.getG(2)))")
        let start = Date()
        var stop = false

        for game in 0..<o.maxGames where !stop {
            let sceneId = o.scene ?? host.newGameSceneId()
            writeTrace(trace, "# title: NEW GAME -> scene \(sceneId)")
            let sName = sceneName(rig: rig, sceneId: sceneId)
            output.writeLine("game \(game + 1): New Game -> scene \(sceneId) (\(sName))")
            host.newGame(sceneId)
            var startFrames = host.frame
            do {
                stop = play(host: host, player: player, o: o, report: report, trace: trace, startFrames: &startFrames)
            } catch {
                report.exceptions.append("\(error)")
                output.writeLine("EXCEPTION \(error)")
                stop = true
            }

            output.writeLine("  ended: \(host.endReason), frames \(host.frame), statements \(host.dispatchCount), choices \(player.choicesTaken), scenes reached \(host.scriptsReached.count)")
            if o.untilFirstChoice && report.firstChoice != nil {
                stop = true
            }
        }

        printSummary(rig: rig, host: host, report: report, output: output, elapsed: Date().timeIntervalSince(start))
        return (report.exceptions.isEmpty && host.unknownCommands.isEmpty) ? ExitCode.ok : ExitCode.failed
    }

    private func sceneName(rig: HeadlessRig, sceneId: Int) -> String {
        let k = rig.source.eboot.gameFlow.scriptOfSceneId(sceneId)
        if k >= 0, let names = try? rig.source.scripts.names, k < names.count {
            return names[k]
        }
        return "?"
    }

    private func attach(host: GameHost, rig: HeadlessRig, o: Options, trace: FileHandle?, player: AutoPlayer, report: Report) {
        let scriptNames = (try? rig.source.scripts.names) ?? []

        host.sceneEntered = { k, id in
            let name = k < scriptNames.count ? scriptNames[k] : "\(k)"
            self.writeTrace(trace, String(format: "F%08d SCENE %d script %d %@", host.frame, id, k, name))
        }

        host.messageStarted = { script, offset, read in
            report.messages += 1
            if trace != nil {
                let text = host.currentMessage != nil ? (String(bytes: host.currentMessage!.text, encoding: .utf8) ?? "").replacingOccurrences(of: "\n", with: "\\n") : ""
                let end = host.currentMessage?.end != nil
                self.writeTrace(trace, String(format: "F%08d MSG script %d @0x%x %@ F823=%d F799=%d end=%@ %@",
                                          host.frame, script, offset, read ? "read" : "new", host.f(823), host.f(799),
                                          end ? "true" : "false", self.trunc(text)))
            }
        }

        host.waitStarted = { kind, ms in
            self.writeTrace(trace, String(format: "F%08d WAIT %@ %d", host.frame, kind, ms))
        }

        host.movieStarted = { id in
            report.movies += 1
            self.writeTrace(trace, String(format: "F%08d MOVIE start %d", host.frame, id))
        }

        host.movieEnded = { id in
            self.writeTrace(trace, String(format: "F%08d MOVIE end %d", host.frame, id))
        }

        host.choiceDecided = { kind, point, value, cursor in
            self.writeTrace(trace, String(format: "F%08d CHOICE %@ point %d -> line %d value %d", host.frame, "\(kind)", point, cursor, value))
        }

        player.chose = { point, pick, value, count in
            let s = host.script
            let name = s < scriptNames.count ? scriptNames[s] : "\(s)"
            let lineChoices = host.choiceLines.map { "\($0.value)\($0.locked ? "L" : "")" }.joined(separator: ", ")
            self.writeTrace(trace, String(format: "F%08d PICK script %d %@ point %d: line %d of [%@] G003=%d",
                                      host.frame, s, name, point, pick, lineChoices, host.vars.getG(3)))
            if report.firstChoice == nil {
                report.firstChoice = "script \(s) (\(name)), choice point \(point), \(count) lines, picked \(pick)"
            }
        }
    }

    private func trunc(_ s: String) -> String {
        s.count <= 60 ? s : String(s.prefix(60)) + "..."
    }

    private func writeTrace(_ trace: FileHandle?, _ line: String) {
        guard let trace = trace, let data = (line + "\n").data(using: .utf8) else { return }
        trace.write(data)
    }

    private func play(host: GameHost, player: AutoPlayer, o: Options, report: Report, trace: FileHandle?, startFrames: inout Int64) -> Bool {
        let limit = host.frame + o.maxFrames
        while host.phase == .running {
            let input = player.next(host)
            _ = host.step(input)
            if o.untilFirstChoice && report.firstChoice != nil {
                return true
            }
            if host.frame >= limit {
                writeTrace(trace, "# frame limit \(o.maxFrames) reached in script \(host.script)")
                return true
            }
        }
        writeTrace(trace, String(format: "F%08d END %@", host.frame, "\(host.endReason)"))
        return false
    }

    private func printSummary(rig: HeadlessRig, host: GameHost, report: Report, output: CliWriter, elapsed: Double) {
        let scriptCount = (try? rig.source.scripts.count) ?? 549
        output.writeLine(String(format: "summary: %d frames, %d statements dispatched to the host, %d messages, %d movies, %.1f s",
                                host.frame, host.dispatchCount, report.messages, report.movies, elapsed))
        output.writeLine("  scenes reached: \(host.scriptsReached.count) of \(scriptCount)")
        if let fc = report.firstChoice {
            output.writeLine("  first choice: \(fc)")
        }
        let unkDesc = host.unknownCommands.isEmpty ? "none" : host.unknownCommands.map { "\($0.key) x\($0.value)" }.joined(separator: ", ")
        output.writeLine("  unknown commands: \(unkDesc)")
        output.writeLine("  exceptions: \(report.exceptions.isEmpty ? "none" : "")")
        for e in report.exceptions {
            output.writeLine("    \(e)")
        }
    }

    private final class ChoicePolicyHolder: ChoicePolicy {
        var current: ChoicePolicy = FirstPolicy()
        override func pick(_ host: GameHost, point: Int) -> Int {
            current.pick(host, point: point)
        }
    }

    private final class Cov {
        let rig: HeadlessRig
        let o: Options
        let host: GameHost
        let player: AutoPlayer
        let report: Report
        let output: CliWriter
        let playCmd: PlayCommand
        var runCount = 0

        init(rig: HeadlessRig, o: Options, host: GameHost, player: AutoPlayer, report: Report, output: CliWriter, playCmd: PlayCommand) {
            self.rig = rig
            self.o = o
            self.host = host
            self.player = player
            self.report = report
            self.output = output
            self.playCmd = playCmd
        }

        func once(_ what: String, node: Int? = nil) -> Int {
            once(what, start: { [weak self] in
                guard let self = self else { return false }
                if let n = node {
                    return self.host.jumpToNode(n)
                }
                self.host.newGame(self.host.newGameSceneId())
                return true
            }, sceneIdForLog: nil)
        }

        func once(_ what: String, start: () -> Bool, sceneIdForLog: Int?) -> Int {
            runCount += 1
            let before = host.scriptsReached.count
            if !start() {
                let padded = what.padding(toLength: 22, withPad: " ", startingAt: 0)
                output.writeLine(String(format: "run %3d %@: nothing to start", runCount, padded))
                return 0
            }

            let sceneId = sceneIdForLog ?? host.sceneId
            var startFrames = host.frame
            let statements = host.dispatchCount
            let choices = player.choicesTaken
            var failure = ""
            var fs = startFrames
            _ = playCmd.play(host: host, player: player, o: o, report: report, trace: nil, startFrames: &fs)

            let gained = host.scriptsReached.count - before
            let scriptCount = (try? rig.source.scripts.count) ?? 549
            let paddedWhat = what.padding(toLength: 22, withPad: " ", startingAt: 0)
            let paddedEnd = "\(host.endReason)".padding(toLength: 14, withPad: " ", startingAt: 0)
            output.writeLine(String(format: "run %3d %@: scene %4d -> %@ %9d frames %9d stmts %3d choices  +%3d scenes = %3d/%d %@",
                                    runCount, paddedWhat, sceneId, paddedEnd,
                                    host.frame - startFrames, host.dispatchCount - statements, player.choicesTaken - choices,
                                    gained, host.scriptsReached.count, scriptCount, failure))
            return gained
        }
    }

    private func runCoverage(rig: HeadlessRig, o: Options, output: CliWriter, trace: FileHandle?) -> Int {
        if o.mode == .click { o.mode = .skip }
        let host = createHost(rig, o, nil)
        let coverage = CoveragePolicy(seed: o.seed)
        let holder = ChoicePolicyHolder()
        holder.current = coverage
        let player = AutoPlayer(policy: holder, mode: o.mode)
        let report = Report()
        attach(host: host, rig: rig, o: o, trace: trace, player: player, report: report)
        let start = Date()
        let cov = Cov(rig: rig, o: o, host: host, player: player, report: report, output: output, playCmd: self)

        let graph = SceneGraph.build(rig.services.scripts, rig.source.eboot.gameFlow)
        var staticReach = graph.reachable(0)
        staticReach.insert(2)
        let scriptCount = (try? rig.source.scripts.count) ?? 549
        let scriptNames = (try? rig.source.scripts.names) ?? []
        output.writeLine("static graph: \(staticReach.count) of \(scriptCount) scripts reachable from START_SCRIPT (plus the prologue 00_01 by New Game)")

        // Phase 1: coverage
        var stale = 0
        while cov.runCount < o.maxRuns && stale < o.patience {
            holder.current = coverage
            stale = cov.once("coverage") == 0 ? stale + 1 : 0
        }

        // Phase 2a: explore and replay
        if !o.noAim {
            exploreAndReplay(rig: rig, o: o, output: output, reached: &host.scriptsReached)
        }

        // Phase 2b: aim
        var round = 0
        var aimRuns = 0
        var failed = Set<Int>()
        while o.aim && !o.noAim && round < o.maxRounds && aimRuns < o.maxAimRuns {
            round += 1
            var targets: [(k: Int, path: [Int])] = []
            for k in 0..<scriptCount {
                if !host.scriptsReached.contains(k) && staticReach.contains(k) && !failed.contains(k) {
                    if let p = graph.path(0, k) {
                        targets.append((k, p))
                    }
                }
            }
            targets.sort(by: { $0.path.count < $1.path.count })
            output.writeLine("-- aim round \(round): \(targets.count) scenes to aim at")
            if targets.isEmpty { break }

            var gained = false
            for t in targets {
                if host.scriptsReached.contains(t.k) || aimRuns >= o.maxAimRuns { continue }
                aimRuns += 1
                holder.current = TargetPolicy(graph: graph, path: t.path, fallback: coverage)
                let name = t.k < scriptNames.count ? scriptNames[t.k] : "\(t.k)"
                if cov.once("aim \(name)") > 0 {
                    gained = true
                } else {
                    failed.insert(t.k)
                }
            }
            if !gained { break }
            failed.removeAll()
        }

        // Phase 3: flowchart jumps
        let fromTitle = host.scriptsReached
        let flow = rig.source.eboot.gameFlow
        var jumpRounds = 0
        var jumpFailed = Set<Int>()
        while !o.noJump && jumpRounds < o.maxRounds {
            jumpRounds += 1
            var targets: [Int] = []
            for k in 0..<scriptCount {
                if !host.scriptsReached.contains(k) && flow.nodeOfScript(k) >= 1 && !jumpFailed.contains(k) {
                    targets.append(k)
                }
            }
            output.writeLine("-- flowchart jump round \(jumpRounds): \(targets.count) scenes with a node to start from")
            if targets.isEmpty { break }

            var gained = false
            for k in targets {
                if host.scriptsReached.contains(k) { continue }
                holder.current = coverage
                let name = k < scriptNames.count ? scriptNames[k] : "\(k)"
                if cov.once("jump \(name)", node: flow.nodeOfScript(k)) > 0 {
                    gained = true
                } else {
                    jumpFailed.insert(k)
                }
            }
            if !gained { break }
            jumpFailed.removeAll()
        }

        // Phase 3b: Q&A endings
        for _ in 0..<12 where !o.noJump {
            let open = (533...556).filter { !host.isSceneDone($0) }
            if open.isEmpty { break }
            for n in open {
                holder.current = coverage
                _ = cov.once("ending \(n)", start: { host.startReplay(1000 + n - 533) }, sceneIdForLog: 3000)
            }
        }

        // Phase 4: special entries
        let beforeSpecial = host.scriptsReached
        if !o.noJump {
            for k in 0..<scriptCount {
                let name = k < scriptNames.count ? scriptNames[k] : "\(k)"
                if !host.scriptsReached.contains(k) && (k == 3 || k == 45 || k == 519 || name == "STAFFROLL" || name == "TEST_SCRIPT" || name.hasPrefix("JUMP")) {
                    let id = flow.sceneId(k)
                    holder.current = coverage
                    _ = cov.once("entry \(name)", start: {
                        host.newGame(id)
                        return true
                    }, sceneIdForLog: id)
                }
            }

            for replay in [1000, 1018, 2000, 750] {
                holder.current = coverage
                _ = cov.once("replay \(replay)", start: { host.startReplay(replay) }, sceneIdForLog: 3000)
            }
        }

        printSummary(rig: rig, host: host, report: report, output: output, elapsed: Date().timeIntervalSince(start))
        output.writeLine("  reached through a special entry (prologue 00_02, staff roll, debug menus, gallery replay): \(host.scriptsReached.count - beforeSpecial.count)")
        let qaDone = (533...556).filter(host.isSceneDone).count
        output.writeLine("  Q&A ending nodes completed: \(qaDone) of 24")
        output.writeLine("  reached by playing from the title: \(fromTitle.count); reached only through the Q&A replays, flowchart jumps and special entries: \(host.scriptsReached.count - fromTitle.count)")
        printMissing(rig: rig, host: host, output: output, staticReach: staticReach, graph: graph)
        return (report.exceptions.isEmpty && host.unknownCommands.isEmpty) ? ExitCode.ok : ExitCode.failed
    }

    private func exploreAndReplay(rig: HeadlessRig, o: Options, output: CliWriter, reached: inout Set<Int>) {
        let start = Date()
        let explorer = FlowExplorer(scripts: rig.services.scripts, flow: rig.source.eboot.gameFlow)
        let found = explorer.explore(maxExpansions: o.exploreBudget)
        let scriptCount = (try? rig.source.scripts.count) ?? 549
        let scriptNames = (try? rig.source.scripts.names) ?? []

        let budgetDesc = found.budgetHit ? " (budget hit)" : ""
        output.writeLine(String(format: "explorer: %d deciding variable words, %d choice states, %d expansions, %d profiles, %d of %d scripts reachable%@, %.1f s",
                                explorer.relevantWords.count, found.states, found.expansions, found.profiles, found.first.count, scriptCount, budgetDesc, Date().timeIntervalSince(start)))

        if let dumpPath = o.exploreDump {
            var lines: [String] = []
            for k in found.first.keys.sorted() {
                let sName = k < scriptNames.count ? scriptNames[k] : "\(k)"
                let chains = found.chainOf(k).map { $0.map(String.init).joined(separator: ",") }.joined(separator: " | ")
                lines.append("\(k)\t\(sName)\t\(chains)")
            }
            try? lines.joined(separator: "\n").write(toFile: dumpPath, atomically: true, encoding: .utf8)
            return
        }

        var order = Array(found.first.keys)
        order.sort { (a, b) -> Bool in
            let lenA = found.chainOf(a).reduce(0) { $0 + $1.count }
            let lenB = found.chainOf(b).reduce(0) { $0 + $1.count }
            if lenA != lenB { return lenA < lenB }
            return a < b
        }

        var done = Set<Int>()
        var mismatches: [Int] = []
        var sessions = 0

        for k in order {
            if done.contains(k) { continue }
            let chain = found.chainOf(k)
            let host = createHost(rig, o, nil)
            let holder = ChoicePolicyHolder()
            let player = AutoPlayer(policy: holder, mode: o.mode == .click ? .skip : o.mode)
            let report = Report()
            host.newGame(host.newGameSceneId())
            holder.current = FirstPolicy()
            var fs = host.frame
            _ = play(host: host, player: player, o: o, report: report, trace: nil, startFrames: &fs)

            for picks in chain {
                holder.current = ListPolicy(picks: picks)
                host.newGame(host.newGameSceneId())
                _ = play(host: host, player: player, o: o, report: report, trace: nil, startFrames: &fs)
            }

            sessions += 1
            done.formUnion(host.scriptsReached)
            reached.formUnion(host.scriptsReached)
            if !host.scriptsReached.contains(k) {
                mismatches.append(k)
            }
        }

        let misNames = mismatches.map { $0 < scriptNames.count ? scriptNames[$0] : "\($0)" }.joined(separator: " ")
        output.writeLine("replayed \(sessions) choice lists in the full engine: \(reached.count) scenes reached from the title; the explorer's list failed for \(mismatches.count): \(misNames)")
    }

    private func printMissing(rig: HeadlessRig, host: GameHost, output: CliWriter, staticReach: Set<Int>, graph: SceneGraph) {
        let scriptCount = (try? rig.source.scripts.count) ?? 549
        let scriptNames = (try? rig.source.scripts.names) ?? []
        var notReachable: [String] = []
        var gated: [String] = []

        for k in 0..<scriptCount {
            if host.scriptsReached.contains(k) { continue }
            let sName = k < scriptNames.count ? scriptNames[k] : "\(k)"
            let item = "\(k):\(sName)"
            if staticReach.contains(k) {
                gated.append(item)
            } else {
                notReachable.append(item)
            }
        }

        output.writeLine("  not reached and not reachable from the title by any jump (\(notReachable.count)): \(notReachable.joined(separator: " "))")
        output.writeLine("  not reached although a jump leads there (\(gated.count)): \(gated.joined(separator: " "))")
    }
}
