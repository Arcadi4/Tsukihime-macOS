import Foundation
import TsukiCore
import TsukiData

public struct ReleaseCheckResult: Sendable {
    public let problems: [String]
    public let notes: [String]

    public var ok: Bool { problems.isEmpty }

    public init(problems: [String], notes: [String]) {
        self.problems = problems
        self.notes = notes
    }
}

public enum ReleaseCheck {
    public static let personalNote = "PERSONAL_BUILD.txt"
    public static let programs: [String] = ["Tsukihime", "TsukihimeLauncher"]

    public static func run(
        folder: String,
        crescentIco: [UInt8],
        dump: ((String, [IconFrame]) -> Void)? = nil
    ) -> ReleaseCheckResult {
        var problems: [String] = []
        var notes: [String] = []

        let fm = FileManager.default
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: folder, isDirectory: &isDir) || !isDir.boolValue {
            problems.append("\(folder) is not a folder")
            return ReleaseCheckResult(problems: problems, notes: notes)
        }

        let mainExe = (folder as NSString).appendingPathComponent(programs[0] + ".exe")
        let mainBin = (folder as NSString).appendingPathComponent(programs[0])
        let linux = !fm.fileExists(atPath: mainExe) && fm.fileExists(atPath: mainBin)

        if !linux && !fm.fileExists(atPath: mainExe) {
            problems.append("\(programs[0]).exe is not in \(folder): not a published folder of the port")
        }

        if let enumerator = fm.enumerator(atPath: folder) {
            while let file = enumerator.nextObject() as? String {
                if (file as NSString).lastPathComponent == personalNote {
                    problems.append("\(file) is there: the folder is a personal build (it says so itself)")
                }
            }
        }

        let crescent = FaceIcon.decodeIco(ByteSpan(crescentIco))
        if crescent.isEmpty {
            problems.append("the crescent icon file could not be read, so the programs' icons cannot be compared")
        }

        for program in programs {
            let iconName = program + (linux ? ".dll" : ".exe")
            let iconPath = (folder as NSString).appendingPathComponent(iconName)
            if linux && program == programs[0] && !fm.fileExists(atPath: iconPath) {
                problems.append("\(iconName) is not in \(folder): the Linux player assembly is missing")
            }

            if fm.fileExists(atPath: iconPath) {
                if let group = try? PeIcons.iconGroup(iconPath) {
                    let frames = FaceIcon.decodeIco(ByteSpan(group))
                    dump?(program, frames)
                    if !crescent.isEmpty && sameFrames(crescent, frames) {
                        notes.append("\(iconName): the icon group is the crescent (\(frames.count) frames)")
                    } else if !crescent.isEmpty {
                        let sizes = frames.map { "\($0.size)" }.joined(separator: ", ")
                        problems.append("\(iconName) carries an icon that is not the port's crescent (\(frames.count) frames, \(sizes) px): a personal build")
                    }
                } else {
                    problems.append("\(iconName) carries no application icon group (id \(PeIcons.applicationIconGroup))")
                }
            }

            let dll = (folder as NSString).appendingPathComponent(program + ".dll")
            if fm.fileExists(atPath: dll) {
                if let marks = try? PeIcons.marks(dll) {
                    if marks.isPersonalBuild {
                        problems.append("\(program).dll carries the assembly attribute AssemblyMetadata(\"\(PeIcons.personalBuildKey)\", \"true\"): a personal build")
                    }

                    if let version = marks.informationalVersion, version.localizedCaseInsensitiveContains("-personal") {
                        problems.append("\(program).dll has the version \(version): a personal build")
                    } else {
                        notes.append("\(program).dll: version \(marks.informationalVersion ?? "(none)"), no personal mark")
                    }
                } else {
                    problems.append("\(program).dll carries no managed metadata")
                }
            }
        }

        return ReleaseCheckResult(problems: problems, notes: notes)
    }

    private static func sameFrames(_ a: [IconFrame], _ b: [IconFrame]) -> Bool {
        if a.count != b.count { return false }
        for i in 0..<a.count {
            if a[i].size != b[i].size || a[i].rgba != b[i].rgba {
                return false
            }
        }
        return true
    }
}

public final class ReleaseCheckCommand: CliCommand {
    public var name: String { "release-check" }
    public var summary: String { "refuse a folder that is a personal build (PERSONAL_BUILD.txt, a non-crescent icon, the TsukiPersonalBuild mark); release-check FOLDER [--icon FILE] [--dump DIR]" }

    public init() {}

    public func run(_ args: [String], output: CliWriter, error: CliWriter) -> Int {
        var folder: String? = nil
        var icon: String? = nil
        var dumpDir: String? = nil

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--icon":
                if i + 1 < args.count {
                    i += 1
                    icon = args[i]
                }
            case "--dump":
                if i + 1 < args.count {
                    i += 1
                    dumpDir = args[i]
                }
            default:
                if arg.hasPrefix("-") || folder != nil {
                    error.writeLine("release-check: unexpected argument '\(arg)'")
                    return ExitCode.usage
                }
                folder = arg
            }
            i += 1
        }

        guard let folder = folder else {
            error.writeLine("release-check: name the folder to be released")
            return ExitCode.usage
        }

        let fm = FileManager.default
        if icon == nil {
            if let root = findRoot() {
                let candidate = (root as NSString).appendingPathComponent("assets/icon/tsukihime.ico")
                if fm.fileExists(atPath: candidate) {
                    icon = candidate
                }
            }
        }

        guard let icon = icon, fm.fileExists(atPath: icon) else {
            error.writeLine("release-check: the crescent icon file was not found; pass --icon <assets/icon/tsukihime.ico>")
            return ExitCode.usage
        }

        guard let iconBytes = try? [UInt8](Data(contentsOf: URL(fileURLWithPath: icon))) else {
            error.writeLine("release-check: could not read icon file '\(icon)'")
            return ExitCode.usage
        }

        var dump: ((String, [IconFrame]) -> Void)? = nil
        if let dumpDir = dumpDir {
            try? fm.createDirectory(atPath: dumpDir, withIntermediateDirectories: true)
            dump = { program, frames in
                for f in frames {
                    let outPath = (dumpDir as NSString).appendingPathComponent("\(program)_\(f.size).png")
                    try? PngWriter.write(outPath, width: f.size, height: f.size, rgba: f.rgba)
                }
                output.writeLine("\(program).exe: \(frames.count) frames written to \(dumpDir)")
            }
        }

        let result = ReleaseCheck.run(folder: folder, crescentIco: iconBytes, dump: dump)
        for note in result.notes {
            output.writeLine("ok      " + note)
        }
        for problem in result.problems {
            output.writeLine("REFUSED " + problem)
        }

        output.writeLine(result.ok ? "RESULT: \(folder) may be released" : "RESULT: \(folder) must NOT be released (\(result.problems.count) problem(s))")
        return result.ok ? ExitCode.ok : ExitCode.failed
    }

    private func findRoot() -> String? {
        let fm = FileManager.default
        var cur = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while cur.path != "/" {
            let slnx = cur.appendingPathComponent("src/Tsuki.slnx").path
            let pkg = cur.appendingPathComponent("Package.swift").path
            if fm.fileExists(atPath: slnx) || fm.fileExists(atPath: pkg) {
                return cur.path
            }
            cur = cur.deletingLastPathComponent()
        }
        return nil
    }
}
