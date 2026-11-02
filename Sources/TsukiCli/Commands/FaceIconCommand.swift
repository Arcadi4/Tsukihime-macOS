import Foundation
import TsukiCore
import TsukiEngine
import TsukiData

public final class FaceIconCommand: CliCommand {
    public var name: String { "face-icon" }
    public var summary: String { "build the Arcueid icon (K23) from the game folder into DIR/icons/tsukihime.ico; face-icon --game DIR --out DIR [--force]" }

    public init() {}

    public func run(_ args: [String], output: CliWriter, error: CliWriter) -> Int {
        var game: String? = nil
        var outDir: String? = nil
        var force = false

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--game":
                if i + 1 < args.count {
                    i += 1
                    game = args[i]
                }
            case "--out":
                if i + 1 < args.count {
                    i += 1
                    outDir = args[i]
                }
            case "--force":
                force = true
            default:
                error.writeLine("face-icon: unexpected argument '\(arg)'")
                return ExitCode.usage
            }
            i += 1
        }

        guard let outDir = outDir, !outDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.writeLine("face-icon: --out DIR is required (the icon goes to DIR/icons/tsukihime.ico)")
            return ExitCode.usage
        }

        guard let folder = GameFolderLocator.resolve(game) else {
            error.writeLine("face-icon: no game folder; pass --game <dir> or set TSUKI_GAME_DIR to the CUSA47999 folder")
            return ExitCode.usage
        }

        let fm = FileManager.default
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: folder, isDirectory: &isDir) {
            error.writeLine("face-icon: no game folder; pass --game <dir> or set TSUKI_GAME_DIR to the CUSA47999 folder")
            return ExitCode.usage
        }

        if force {
            let stamp = FaceIconCache.stampPath(outDir)
            try? fm.removeItem(atPath: stamp)
        }

        var built = false
        let path = FaceIconCache.ensure(outDir, gameFolder: folder, open: {
            let source = try GameFolderSource.open(folder)
            guard let record = FaceIcon.findRecord(source.catalog),
                  let faceId = try? source.catalog.nameIndex.find(FaceIcon.faceLayer),
                  let bodyId = try? source.catalog.nameIndex.find(record.name0) else {
                throw TsukiError.state("Arcueid face/body layer not found in catalog")
            }
            let face = source.picture(faceId)
            let body = source.picture(bodyId)
            return (face, body, record.layerX, record.layerY)
        }, log: { line in
            if line.hasPrefix("face icon: built") {
                built = true
            }
            output.writeLine(line)
        })

        guard let path = path else {
            error.writeLine("face-icon: the Arcueid icon could not be built from \(folder)")
            return ExitCode.failed
        }

        output.writeLine("face-icon: \(path)\(built ? "" : " (current)")")
        return ExitCode.ok
    }
}
