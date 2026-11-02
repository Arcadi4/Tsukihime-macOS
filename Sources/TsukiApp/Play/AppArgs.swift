import Foundation
import TsukiCore
import TsukiUi

public enum AppMode: Sendable {
    case play
    case skeleton
    case smoke
    case pickFolder
}

public final class AppArgs: @unchecked Sendable {
    public static let usage = """
usage: Tsukihime [--game DIR] [--lang ja|en|zc|zt] [--save-dir DIR] [--fullscreen | --windowed] [--movies real|virtual] [--log FILE]
                 [--prompts auto|keyboard|playstation|xbox]   (button prompts for this run; the Controls tab of the config screen sets and saves them)
       verification: --hidden --mute --autoplay [click|skip|auto] [--choices first|last|random[:seed]|list:i,j] [--fast]
                     [--script "60:Enter;120:Esc+Down;200:click=960,540;300:shot=name;400:log" | --script @file] [--shot-at f,f,...] [--shot-dir DIR]
                     [--shot-on-choice] [--exit-after FRAMES] [--no-save] [--mem-log SECONDS]
                     [--screenshot-dir DIR]   (where F12 saves)   [--clipboard-file FILE]   (the copied text goes there, not to the clipboard)
       other:        --skeleton [--seconds N] | --smoke [--visible] [--report FILE] | --pick-folder [--timeout S]
"""

    public var mode: AppMode = .play
    public var visible: Bool = false
    public var fullscreen: Bool = false
    public var windowed: Bool = false
    public var windowModeChoice: Bool? {
        fullscreen ? true : windowed ? false : nil
    }

    public var reportPath: String?
    public var seconds: Double = 0
    public var timeoutSeconds: Double = 50
    public var gameDir: String?
    public var saveDir: String?
    public var language: Int?
    public var hidden: Bool = false
    public var mute: Bool = false
    public var fast: Bool = false
    public var autoplay: String?
    public var choices: String = "first"
    public var script: String?
    public var shotAt: [Int64] = []
    public var shotDir: String?
    public var screenshotDir: String?
    public var clipboardFile: String?
    public var shotOnChoice: Bool = false
    public var exitAfter: Int64 = 0
    public var virtualMovies: Bool = false
    public var logFile: String?
    public var noSave: Bool = false
    public var memLogSeconds: Double = 0
    public var prompts: PromptSetting?
    public var sweepDir: String?
    public var sweepEvery: Int = 0
    public var sweepScene: Int = 20
    public var sweepChanges: Int = 0
    public var sweepMessages: Int = 0
    public var exitAfterEnds: Int = 0
    public var sweepTour: String?
    public var tourUntilEnd: Bool = false
    public var tourCap: Int = 6000
    public var sweepScale: Int = 4
    public var sweepMax: Int = 200_000

    public init() {}

    public static func tryParse(_ args: [String], result: inout AppArgs?, error: inout String?) -> Bool {
        let a = AppArgs()
        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--smoke":
                a.mode = .smoke
            case "--skeleton":
                a.mode = .skeleton
            case "--pick-folder":
                a.mode = .pickFolder
            case "--visible":
                a.visible = true
            case "--fullscreen":
                a.fullscreen = true
                a.windowed = false
            case "--windowed":
                a.windowed = true
                a.fullscreen = false
            case "--hidden":
                a.hidden = true
            case "--mute":
                a.mute = true
            case "--fast":
                a.fast = true
            case "--shot-on-choice":
                a.shotOnChoice = true
            case "--no-save":
                a.noSave = true
            case "--autoplay":
                a.autoplay = "skip"
                if i + 1 < args.count && (args[i + 1] == "click" || args[i + 1] == "skip" || args[i + 1] == "auto") {
                    i += 1
                    a.autoplay = args[i]
                }
            case "--report" where i + 1 < args.count:
                i += 1
                a.reportPath = args[i]
            case "--log" where i + 1 < args.count:
                i += 1
                a.logFile = args[i]
            case "--game" where i + 1 < args.count:
                i += 1
                a.gameDir = args[i]
            case "--save-dir" where i + 1 < args.count:
                i += 1
                a.saveDir = args[i]
            case "--shot-dir" where i + 1 < args.count:
                i += 1
                a.shotDir = args[i]
            case "--screenshot-dir" where i + 1 < args.count:
                i += 1
                a.screenshotDir = args[i]
            case "--clipboard-file" where i + 1 < args.count:
                i += 1
                a.clipboardFile = args[i]
            case "--choices" where i + 1 < args.count:
                i += 1
                a.choices = args[i]
            case "--script" where i + 1 < args.count:
                i += 1
                a.script = args[i]
            case "--sweep-dir" where i + 1 < args.count:
                i += 1
                a.sweepDir = args[i]
            case "--sweep-every" where i + 1 < args.count:
                i += 1
                if let se = Int(args[i]) { a.sweepEvery = se }
            case "--sweep-scene" where i + 1 < args.count:
                i += 1
                if let ss = Int(args[i]) { a.sweepScene = ss }
            case "--sweep-messages" where i + 1 < args.count:
                i += 1
                if let sn = Int(args[i]) { a.sweepMessages = sn }
            case "--exit-after-ends" where i + 1 < args.count:
                i += 1
                if let ea = Int(args[i]) { a.exitAfterEnds = ea }
            case "--sweep-tour" where i + 1 < args.count:
                i += 1
                a.sweepTour = args[i]
            case "--tour-end":
                a.tourUntilEnd = true
            case "--tour-cap" where i + 1 < args.count:
                i += 1
                if let tc = Int(args[i]) { a.tourCap = tc }
            case "--sweep-changes" where i + 1 < args.count:
                i += 1
                if let sc = Int(args[i]) { a.sweepChanges = sc }
            case "--sweep-scale" where i + 1 < args.count:
                i += 1
                if let sd = Int(args[i]), sd >= 1 { a.sweepScale = sd }
            case "--sweep-max" where i + 1 < args.count:
                i += 1
                if let sm = Int(args[i]) { a.sweepMax = sm }
            case "--prompts" where i + 1 < args.count:
                i += 1
                var p = PromptSetting.auto
                if PromptStyles.tryParse(args[i], setting: &p) {
                    a.prompts = p
                } else {
                    error = "--prompts takes auto, keyboard, playstation or xbox"
                    return false
                }
            case "--lang" where i + 1 < args.count:
                i += 1
                switch args[i].lowercased() {
                case "ja": a.language = 0
                case "en": a.language = 1
                case "zc": a.language = 2
                case "zt": a.language = 3
                default:
                    error = "--lang takes ja, en, zc or zt"
                    return false
                }
            case "--movies" where i + 1 < args.count:
                i += 1
                let m = args[i]
                if m != "real" && m != "virtual" {
                    error = "--movies takes real or virtual"
                    return false
                }
                a.virtualMovies = (m == "virtual")
            case "--shot-at" where i + 1 < args.count:
                i += 1
                let parts = args[i].split(separator: ",")
                for p in parts {
                    let s = p.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let f = Int64(s), f >= 1 else {
                        error = "--shot-at takes a comma list of frame numbers"
                        return false
                    }
                    a.shotAt.append(f)
                }
            case "--exit-after" where i + 1 < args.count:
                i += 1
                if let n = Int64(args[i]), n > 0 {
                    a.exitAfter = n
                }
            case "--mem-log" where i + 1 < args.count:
                i += 1
                if let ml = Double(args[i]), ml > 0 {
                    a.memLogSeconds = ml
                }
            case "--seconds" where i + 1 < args.count:
                i += 1
                if let s = Double(args[i]), s > 0 {
                    a.seconds = s
                }
            case "--timeout" where i + 1 < args.count:
                i += 1
                if let t = Double(args[i]), t > 0 {
                    a.timeoutSeconds = t
                }
            default:
                error = "unknown or incomplete argument: " + arg
                return false
            }
            i += 1
        }

        if a.hidden && !a.shotAt.isEmpty && a.shotDir == nil {
            error = "--shot-at needs --shot-dir"
            return false
        }

        result = a
        return true
    }
}
