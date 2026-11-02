import Foundation
import TsukiCore
import TsukiData

public enum ExitCode {
    public static let ok: Int = 0
    public static let failed: Int = 1
    public static let usage: Int = 2
}

public protocol CliWriter: AnyObject {
    func write(_ string: String)
    func writeLine(_ string: String)
}

extension CliWriter {
    public func writeLine(_ string: String = "") {
        write(string + "\n")
    }
}
func latin1(_ bytes: [UInt8]) -> String {
    String(bytes: bytes, encoding: .isoLatin1) ?? ""
}

func latin1(_ bytes: ByteSpan) -> String {
    EbootReader.latin1(bytes)
}


public final class StandardCliWriter: CliWriter {
    private let handle: FileHandle

    public init(handle: FileHandle) {
        self.handle = handle
    }

    public func write(_ string: String) {
        if let data = string.data(using: .utf8) {
            handle.write(data)
        }
    }
}

public final class StringCliWriter: CliWriter {
    public private(set) var text = ""

    public init() {}

    public func write(_ string: String) {
        text += string
    }
}

public protocol CliCommand {
    var name: String { get }
    var summary: String { get }
    func run(_ args: [String], output: CliWriter, error: CliWriter) -> Int
}

public typealias ICliCommand = CliCommand

public enum CliApp {
    public static let commands: [CliCommand] = [
        VerifyCommand(),
        MzxBenchCommand(),
        DecodeAllCommand(),
        CensusCommand(),
        PlayCommand(),
        UiShotCommand(),
        UiExitArtCommand(),
        EffectShotCommand(),
        FaceIconCommand(),
        ReleaseCheckCommand(),
    ]

    @discardableResult
    public static func run(
        _ rawArgs: [String],
        output: CliWriter = StandardCliWriter(handle: .standardOutput),
        error: CliWriter = StandardCliWriter(handle: .standardError)
    ) -> Int {
        var args = rawArgs
        if let first = args.first,
           first.hasSuffix("/tsuki") || first.hasSuffix("/TsukiCli") || first == "tsuki" || first == "TsukiCli" || first.contains("/.build/") {
            args = Array(args.dropFirst())
        }

        if args.isEmpty || args[0] == "-h" || args[0] == "--help" || args[0] == "help" {
            printUsage(args.isEmpty ? error : output)
            return args.isEmpty ? ExitCode.usage : ExitCode.ok
        }

        let cmdName = args[0]
        guard let command = commands.first(where: { $0.name.caseInsensitiveCompare(cmdName) == .orderedSame }) else {
            error.writeLine("unknown command '\(cmdName)'")
            printUsage(error)
            return ExitCode.usage
        }

        do {
            return command.run(Array(args.dropFirst()), output: output, error: error)
        } catch let err {
            error.writeLine("\(command.name): \(err.localizedDescription)")
            return ExitCode.usage
        }
    }

    private static func printUsage(_ w: CliWriter) {
        w.writeLine("usage: Tsuki.Cli <command> [options]")
        for c in commands {
            let padded = c.name.padding(toLength: 12, withPad: " ", startingAt: 0)
            w.writeLine("  \(padded) \(c.summary)")
        }
        w.writeLine("  (dump, trace, explore, render-checkpoint, save-check: later milestones)")
        w.writeLine("The game folder comes from --game <dir>, else the environment variable TSUKI_GAME_DIR (there is no built-in default path).")
    }
}
