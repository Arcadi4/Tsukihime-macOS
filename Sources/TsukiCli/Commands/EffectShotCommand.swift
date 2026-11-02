import Foundation
import Metal
import TsukiCore
import TsukiEngine
import TsukiData
import TsukiRender

public final class EffectShotCommand: CliCommand {
    private static let defaultScripts: [String: [Int]] = [
        "noise": [62, 57, 58],
        "haze": [61, 57, 62],
        "rule": [57, 58, 62],
        "mask": [57, 62, 58],
        "grade": [57, 62, 58],
        "focus": [62, 57, 58],
        "ghost": [58, 62, 57],
        "choice": [57, 58, 62],
    ]

    public var name: String { "effect-shot" }
    public var summary: String { "render a real scene with a screen effect to PNGs through the GPU compositor; effect-shot <noise|haze|rule|mask|grade|focus|ghost|choice> [--script K] [--lang en] [--shots N] [--every M]" }

    public init() {}

    public func run(_ args: [String], output: CliWriter, error: CliWriter) -> Int {
        var effect: String? = nil
        var game: String? = nil
        var outDir: String? = nil
        var script: Int? = nil
        var shots = 3
        var every = 8
        var maxFrames = 40_000
        var off = false
        var lang = Language.en

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--game":
                if i + 1 < args.count { i += 1; game = args[i] }
            case "--out":
                if i + 1 < args.count { i += 1; outDir = args[i] }
            case "--script":
                if i + 1 < args.count { i += 1; script = Int(args[i]) }
            case "--shots":
                if i + 1 < args.count { i += 1; shots = Int(args[i]) ?? 3 }
            case "--every":
                if i + 1 < args.count { i += 1; every = Int(args[i]) ?? 8 }
            case "--max-frames":
                if i + 1 < args.count { i += 1; maxFrames = Int(args[i]) ?? 40_000 }
            case "--off":
                off = true
            case "--lang":
                if i + 1 < args.count {
                    i += 1
                    let l = args[i].lowercased()
                    switch l {
                    case "ja": lang = .ja
                    case "en": lang = .en
                    case "zc": lang = .zc
                    case "zt": lang = .zt
                    default: break
                    }
                }
            default:
                if arg.hasPrefix("-") || effect != nil {
                    error.writeLine("effect-shot: unexpected argument '\(arg)'")
                    return ExitCode.usage
                }
                effect = arg
            }
            i += 1
        }

        guard let effect = effect, Self.defaultScripts[effect] != nil else {
            error.writeLine("effect-shot: name an effect: " + Self.defaultScripts.keys.sorted().joined(separator: ", "))
            return ExitCode.usage
        }

        guard let folder = GameFolderLocator.resolve(game) else {
            error.writeLine("effect-shot: no game folder; pass --game <dir> or set TSUKI_GAME_DIR to the CUSA47999 folder")
            return ExitCode.usage
        }

        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: folder, isDirectory: &isDir) || !isDir.boolValue {
            error.writeLine("effect-shot: no game folder; pass --game <dir> or set TSUKI_GAME_DIR to the CUSA47999 folder")
            return ExitCode.usage
        }

        let out = outDir ?? (findRoot() as NSString).appendingPathComponent("scratch/K7")
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

        let data: GameFolderSource
        do {
            data = try GameFolderSource.open(folder)
        } catch let err {
            error.writeLine("effect-shot: \(err)")
            return ExitCode.failed
        }

        let ebootBytes = (try? [UInt8](Data(contentsOf: URL(fileURLWithPath: (folder as NSString).appendingPathComponent("eboot.bin"))))) ?? []
        let ebootReader = try? EbootReader.parse(ByteSpan(ebootBytes))
        let grader = (try? ebootReader.flatMap { try? TileGrader.fromEboot($0) }) ?? nil

        guard let device = MTLCreateSystemDefaultDevice() else {
            error.writeLine("effect-shot: Metal not supported")
            return ExitCode.failed
        }

        guard let compositor = try? MetalCompositor(device: device, width: 1920, height: 1080) else {
            error.writeLine("effect-shot: cannot create compositor")
            return ExitCode.failed
        }

        let cache = TextureCache(device: device, capacityBytes: 3 << 30)
        cache.grader = grader
        let plainCache = TextureCache(device: device, capacityBytes: 3 << 30)

        var variants: [(suffix: String, executor: DisplayListExecutor, provider: GameTextureProvider)] = [
            ("", DisplayListExecutor(compositor: compositor, textures: cache), GameTextureProvider(data: data, cache: cache))
        ]
        if effect == "grade" {
            variants.append(("_plain", DisplayListExecutor(compositor: compositor, textures: plainCache), GameTextureProvider(data: data, cache: plainCache)))
        }

        let candidates = script != nil ? [script!] : Self.defaultScripts[effect]!
        for k in candidates {
            let start = Date()
            let scripts = ScriptCache(data)
            let services = GameServices(data: data, scripts: scripts)
            services.layouts = data.layouts
            let options = GameOptions()
            options.language = lang
            options.virtualMovies = true
            let host = GameHost(services: services, options: options)
            let player = AutoPlayer(policy: FirstPolicy(), mode: .skip)

            host.newGame(data.eboot.gameFlow.sceneId(k))
            var startFrames: Int64 = 0
            var n = 0
            var reached = false
            let cond = condition(effect)

            while host.phase == GamePhase.running && n < maxFrames {
                n += 1
                let input = player.next(host)
                _ = host.step(input)
                if cond(host) {
                    reached = true
                    break
                }
            }

            if !reached {
                output.writeLine(String(format: "effect %@ in script %03d: not reached in %d frames", effect, k, n))
                continue
            }

            let ms = Int(Date().timeIntervalSince(start) * 1000.0)
            output.writeLine(String(format: "effect %@: scene reached in script %03d at frame %d (%d ms); rendering %d shots every %d frames",
                                    effect, k, host.frame, ms, shots, every))
            renderShots(effect: effect, script: k, host: host, compositor: compositor, variants: variants, outDir: out, shots: shots, every: every, off: off, output: output)
            return ExitCode.ok
        }

        return ExitCode.failed
    }

    private func condition(_ effect: String) -> (GameHost) -> Bool {
        switch effect {
        case "noise":
            return { h in Self.anyLayer(h) { $0.stns >= 1 && $0.stns <= 12 && $0.alpha > 0.1 } }
        case "haze":
            return { h in Self.anyLayer(h) { $0.stra > 0 && $0.alpha > 0.5 } }
        case "rule":
            return { h in Self.anyLayer(h) { $0.sttr >= 0 && $0.alpha > 0.05 } }
        case "mask":
            return { h in Self.anyLayer(h) { r in
                r.mask >= 0 && r.alpha > 0.5 && h.stage.drawn[r.mask].used != 0 && h.stage.drawn[r.mask].alpha > 0.5
            } }
        case "grade":
            return { h in Self.anyLayer(h) { r in
                r.gradeKey != 0 && r.alpha > 0.5 && h.stage.drawn.filter { $0.used != 0 && $0.alpha > 0.5 }.count >= 2
            } }
        case "focus":
            return { h in h.focusEffect.mode == .on }
        case "ghost":
            return { h in h.ghostEffect.mode == 4 && h.ghostEffect.alpha >= 0.9 }
        case "choice":
            return { h in h.choiceSelectable }
        default:
            return { _ in false }
        }
    }

    private static func anyLayer(_ host: GameHost, predicate: (LayerRecord) -> Bool) -> Bool {
        for r in host.stage.drawn {
            if r.used != 0 && r.pic >= 0 && r.zOrder > 0 && predicate(r) {
                return true
            }
        }
        return false
    }

    private func renderShots(
        effect: String, script: Int, host: GameHost, compositor: MetalCompositor,
        variants: [(suffix: String, executor: DisplayListExecutor, provider: GameTextureProvider)],
        outDir: String, shots: Int, every: Int, off: Bool, output: CliWriter
    ) {
        host.setSkipLatch(false)
        if off {
            host.ghostEffect.reset()
            host.focusEffect.reset()
            host.stage.effectPasses = false
        }
        host.setAutoMode(false)

        var n: Int64 = 0
        var shot = 0
        let list = DisplayList(capacity: 4096)

        while shot < shots && n < 20_000 {
            n += 1
            var input = InputFrame(frame: n)
            if effect == "choice" {
                if shot == 1 && n % Int64(every) == 1 {
                    input.pressed = .down
                    input.repeated = .down
                    input.held = .down
                } else if shot == 2 && n % Int64(every) == 1 {
                    input.pressed = .decide
                    input.repeated = .decide
                    input.held = .decide
                }
            }

            list.reset(frame: n)
            _ = host.step(input, list: list)
            list.seal()

            let take = (n % Int64(every)) == 0
            for variant in variants {
                variant.provider.upload(list)
                if n == 1 {
                    compositor.clear(target: 0, r: 0, g: 0, b: 0, a: 255)
                }

                let stats = variant.executor.execute(list)
                if !take { break }

                var pixels = compositor.readTarget(0)
                var a = 3
                while a < pixels.count {
                    pixels[a] = 255
                    a += 4
                }

                let file = (outDir as NSString).appendingPathComponent(String(format: "%@_%03d_%d%@%@.png",
                                                                             effect, script, shot, variant.suffix, off ? "_off" : ""))
                try? PngWriter.write(file, width: 1920, height: 1080, rgba: pixels)
                output.writeLine(String(format: "  shot %d%@: frame %d, %d commands, %d quads, %d missing textures, %d unresolved -> %@",
                                        shot, variant.suffix, host.frame, list.commands.count, stats.draws, stats.missingTextures, variant.provider.missing.count, file))
            }

            if take {
                shot += 1
            }
        }
    }

    private func findRoot() -> String {
        let fm = FileManager.default
        var cur = URL(fileURLWithPath: fm.currentDirectoryPath)
        while cur.path != "/" {
            let slnx = cur.appendingPathComponent("src/Tsuki.slnx").path
            let pkg = cur.appendingPathComponent("Package.swift").path
            if fm.fileExists(atPath: slnx) || fm.fileExists(atPath: pkg) {
                return cur.path
            }
            cur = cur.deletingLastPathComponent()
        }
        return fm.currentDirectoryPath
    }
}
