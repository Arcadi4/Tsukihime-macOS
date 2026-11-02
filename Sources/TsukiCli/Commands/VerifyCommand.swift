import Foundation
import TsukiCore
import TsukiData

public final class VerifyCommand: CliCommand {
    public var name: String { "verify" }
    public var summary: String { "check the game folder against the analysed build (eboot SHA-256, FORMATS 2 counts); options: --game DIR, -v" }

    public init() {}

    public func run(_ args: [String], output: CliWriter, error: CliWriter) -> Int {
        var game: String? = nil
        var verbose = false

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--game":
                if i + 1 < args.count {
                    i += 1
                    game = args[i]
                }
            case "-v", "--verbose":
                verbose = true
            default:
                error.writeLine("verify: unexpected argument '\(arg)'")
                return ExitCode.usage
            }
            i += 1
        }

        guard let folder = GameFolderLocator.resolve(game) else {
            error.writeLine("verify: no game folder; pass --game <dir> or set TSUKI_GAME_DIR to the CUSA47999 folder")
            return ExitCode.usage
        }

        let fm = FileManager.default
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: folder, isDirectory: &isDir) {
            error.writeLine("verify: the folder '\(folder)' does not exist")
            return ExitCode.usage
        }

        let layout = GameLayoutResolver.resolve(folder)
        output.writeLine("layout: \(layout.describe())")
        if !layout.isGame {
            error.writeLine("verify: " + GameLayoutException(layout).description)
            return ExitCode.failed
        }

        let start = Date()
        let report: BuildReport
        do {
            report = try BuildCheck.run(layout)
        } catch let err {
            error.writeLine("verify: \(err)")
            return ExitCode.failed
        }
        let elapsedMs = Date().timeIntervalSince(start) * 1000.0

        output.write(BuildReportFormatter.format(report, verbose: verbose))
        output.writeLine(String(format: "checked in %.0f ms", elapsedMs))
        return (report.accepted || report.usable) ? ExitCode.ok : ExitCode.failed
    }
}
