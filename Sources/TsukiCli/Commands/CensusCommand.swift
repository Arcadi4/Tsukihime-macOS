import Foundation
import TsukiCore
import TsukiData
import TsukiMedia

public final class CensusCommand: CliCommand {
    public var name: String { "census" }
    public var summary: String { "resolve every reference of the 549 scripts (pictures, audio, movies, text, fonts); options: --game DIR, --threads N, --no-targets, --no-glyphs, --sample N, --refs FILE, -v" }

    public init() {}

    public func run(_ args: [String], output: CliWriter, error: CliWriter) -> Int {
        var game: String? = nil
        var refs: String? = nil
        var targets = true
        var glyphs = true
        var verbose = false
        var threads = ProcessInfo.processInfo.activeProcessorCount
        var sample = 48

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--game":
                if i + 1 < args.count { i += 1; game = args[i] }
            case "--refs":
                if i + 1 < args.count { i += 1; refs = args[i] }
            case "--threads":
                if i + 1 < args.count, let t = Int(args[i + 1]), t > 0 { i += 1; threads = t }
            case "--sample":
                if i + 1 < args.count, let s = Int(args[i + 1]) { i += 1; sample = s }
            case "--no-targets":
                targets = false
            case "--no-glyphs":
                glyphs = false
            case "-v", "--verbose":
                verbose = true
            default:
                error.writeLine("census: unexpected argument '\(arg)'")
                return ExitCode.usage
            }
            i += 1
        }

        guard let folder = GameFolderLocator.resolve(game) else {
            error.writeLine("census: no game folder; pass --game <dir> or set TSUKI_GAME_DIR")
            return ExitCode.usage
        }

        let ebootPath = (folder as NSString).appendingPathComponent("eboot.bin")
        if !FileManager.default.fileExists(atPath: ebootPath) {
            error.writeLine("census: no game folder; pass --game <dir> or set TSUKI_GAME_DIR")
            return ExitCode.usage
        }

        let source: GameFolderSource
        do {
            source = try GameFolderSource.open(folder, audioDecoder: MediaAudioDecoder(), decodeParallelism: max(1, threads / 4))
        } catch let err {
            error.writeLine("census: \(err)")
            return ExitCode.failed
        }
        defer { source.dispose() }

        if !source.build.isAnalysedBuild {
            error.writeLine("census: \(folder) is not the analysed build (eboot.bin SHA-256 \(source.build.ebootSHA256)); run `verify` first")
            return ExitCode.failed
        }

        let options = CensusOptions(
            parallelism: threads,
            checkTargets: targets,
            checkGlyphs: glyphs,
            decodeAudioSample: sample,
            decodePictureSample: sample
        )
        let report = ReferenceCensus.run(source, options: options)
        printReport(report, output: output, verbose: verbose)

        if let refs = refs {
            let lines = report.references.map(\.line).joined(separator: "\n")
            try? lines.write(toFile: refs, atomically: true, encoding: .utf8)
            output.writeLine("wrote \(report.references.count) reference lines to \(refs)")
        }

        return report.isClean ? ExitCode.ok : ExitCode.failed
    }

    private func printReport(_ report: CensusReport, output: CliWriter, verbose: Bool) {
        output.writeLine(String(format: "census T0: %d scripts, %d statements, %d references, %.1f s",
                                report.scripts, report.statements, report.references.count, report.elapsed))
        let kPad = "kind".padding(toLength: 7, withPad: " ", startingAt: 0)
        output.writeLine("\(kPad)  references  distinct  resolved  allowed  failed")

        for t in report.totals {
            let name = t.kind.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0)
            output.writeLine(String(format: "%@ %12d %9d %9d %8d %7d",
                                    name, t.references, t.distinct, t.resolved, t.allowed, t.unexpected))
        }

        if !report.checks.isEmpty {
            output.writeLine("targets read through the source:")
            for c in report.checks {
                output.writeLine("  \(c.name): \(c.checked) checked, \(c.failed) failed")
            }
        }

        if !report.glyphs.isEmpty {
            output.writeLine("glyphs of the referenced text lines:")
            for g in report.glyphs {
                output.writeLine("  \(g.language): \(g.lines) lines, \(g.distinctCharacters) distinct characters (\(g.occurrences) occurrences), \(g.missing.count) without a glyph, \(g.pagesUsed) pages used, \(g.outOfPage) outside their page")
            }
        }

        let allowed = report.findings.filter(\.allowed)
        output.writeLine("allow-listed: \(allowed.count)")
        for f in allowed where verbose || f.check != "motion" {
            let d = f.detail.replacingOccurrences(of: "\t", with: " ")
            output.writeLine("  \(f.check): \(d) (\(f.allowedBecause ?? ""))")
        }

        if !verbose && allowed.contains(where: { $0.check == "motion" }) {
            let motionCount = allowed.filter { $0.check == "motion" }.count
            output.writeLine("  motion: \(motionCount) (id 0 and one id past the table; -v lists them)")
        }

        let failures = report.failures
        output.writeLine("failures: \(failures.count)")
        let displayed = verbose ? failures : Array(failures.prefix(40))
        for f in displayed {
            let d = f.detail.replacingOccurrences(of: "\t", with: " ")
            output.writeLine("  \(f.check): \(d)")
        }

        output.writeLine(failures.isEmpty ? "census T0: every reference resolves except the allow-list" : "census T0: FAILED")
    }
}
