import Foundation
import TsukiCore
import TsukiEngine
import TsukiData
import TsukiUi

public final class UiExitArtCommand: CliCommand {
    public var name: String { "exit-art" }
    public var summary: String { "compose the title's EXIT cell from the UI sheet and write it as PNG for inspection; exit-art [--lang ja|en|zc|zt] [--game DIR] [--out DIR]" }

    public init() {}

    public func run(_ args: [String], output: CliWriter, error: CliWriter) -> Int {
        var game: String? = nil
        var outDir: String? = nil
        var lang = Language.en

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
            case "--lang":
                if i + 1 < args.count {
                    i += 1
                    let l = args[i].lowercased()
                    switch l {
                    case "ja": lang = .ja
                    case "en": lang = .en
                    case "zc": lang = .zc
                    case "zt": lang = .zt
                    default:
                        error.writeLine("unknown language '\(l)'")
                        return ExitCode.usage
                    }
                }
            default:
                error.writeLine("exit-art: unexpected argument '\(arg)'")
                return ExitCode.usage
            }
            i += 1
        }

        guard let folder = GameFolderLocator.resolve(game) else {
            error.writeLine("exit-art: no game folder; pass --game <dir> or set TSUKI_GAME_DIR")
            return ExitCode.usage
        }

        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: folder, isDirectory: &isDir) || !isDir.boolValue {
            error.writeLine("exit-art: the folder '\(folder)' does not exist")
            return ExitCode.usage
        }

        let out = outDir ?? (findRoot() as NSString).appendingPathComponent("scratch/exit-art")
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

        let data: GameFolderSource
        do {
            data = try GameFolderSource.open(folder)
        } catch let err {
            error.writeLine("exit-art: \(err)")
            return ExitCode.failed
        }

        let sheet = data.uiSheet(UiSheets.titleMenu.set, lang, UiSheets.titleMenu.child)
        let rgba = UiComposed.assemble(sheet)
        let suffix = lang.code
        var ok = true

        for column in 0..<2 {
            let look = column == 0 ? "normal" : "cursor"
            var layout: ExitLayout? = nil
            guard let cell = TitleExitArt.composeState(rgba, column, layout: &layout), let layout = layout else {
                output.writeLine("\(look): the sheet is not the art the composer expects; the title falls back to the glyph font")
                ok = false
                continue
            }

            let cellFile = (out as NSString).appendingPathComponent("exit_\(suffix)_\(look).png")
            try? PngWriter.write(cellFile, width: TitleExitArt.cellWidth, height: TitleExitArt.cellHeight, rgba: cell)

            let letterRanges = layout.letters.map { "\($0.left)..\($0.right)" }.joined(separator: " ")
            output.writeLine(String(format: "%@: gap %d, centre %.1f, rows %d..%d, letters %@, E from %@, I from %@, glow sum %.2f -> %@",
                                    look, layout.gap, layout.centre, layout.rowTop, layout.rowBottom,
                                    letterRanges, layout.eSource, layout.iSource, layout.glowSum, cellFile))

            let x0 = 24 + (312 * column)
            let tops = [376, 24, 112, 200, 288]
            var strip = [UInt8](repeating: 0, count: TitleExitArt.cellWidth * TitleExitArt.cellHeight * 6 * 4)

            for k in 0..<6 {
                for y in 0..<TitleExitArt.cellHeight {
                    for x in 0..<TitleExitArt.cellWidth {
                        let src = k < 5 ? ((((tops[k] + y) * TitleExitArt.sheetWidth) + x0 + x) * 4) : (((y * TitleExitArt.cellWidth) + x) * 4)
                        let pr: UInt8
                        let pg: UInt8
                        let pb: UInt8
                        let pa: UInt8
                        if k < 5 {
                            pr = rgba[src]
                            pg = rgba[src + 1]
                            pb = rgba[src + 2]
                            pa = rgba[src + 3]
                        } else {
                            pr = cell[src]
                            pg = cell[src + 1]
                            pb = cell[src + 2]
                            pa = cell[src + 3]
                        }

                        let o = ((((k * TitleExitArt.cellHeight) + y) * TitleExitArt.cellWidth) + x) * 4
                        let a = Float(pa) / 255.0
                        strip[o] = UInt8(round((Float(pr) * a) + (24.0 * (1.0 - a))))
                        strip[o + 1] = UInt8(round((Float(pg) * a) + (30.0 * (1.0 - a))))
                        strip[o + 2] = UInt8(round((Float(pb) * a) + (60.0 * (1.0 - a))))
                        strip[o + 3] = 255
                    }
                }
            }

            var cells = [UInt8](repeating: 0, count: TitleExitArt.cellWidth * TitleExitArt.cellHeight * 5 * 4)
            for k in 0..<5 {
                for y in 0..<TitleExitArt.cellHeight {
                    let srcStart = (((tops[k] + y) * TitleExitArt.sheetWidth) + x0) * 4
                    let dstStart = (((k * TitleExitArt.cellHeight) + y) * TitleExitArt.cellWidth) * 4
                    cells.replaceSubrange(dstStart..<(dstStart + TitleExitArt.cellWidth * 4),
                                          with: rgba[srcStart..<(srcStart + TitleExitArt.cellWidth * 4)])
                }
            }

            try? PngWriter.write((out as NSString).appendingPathComponent("cells_\(suffix)_\(look).png"),
                                 width: TitleExitArt.cellWidth, height: TitleExitArt.cellHeight * 5, rgba: cells)

            let names = ["NEW GAME", "LOAD GAME", "CONFIG", "GALLERY", "CONTINUE"]
            let wordTops = [24, 112, 200, 288, 376]
            for word in 0..<5 {
                guard let painted = TitleExitArt.repaintGlow(rgba, column, word) else {
                    continue
                }

                var source = [UInt8](repeating: 0, count: TitleExitArt.cellWidth * TitleExitArt.cellHeight * 4)
                for y in 0..<TitleExitArt.cellHeight {
                    let srcStart = (((wordTops[word] + y) * TitleExitArt.sheetWidth) + x0) * 4
                    let dstStart = y * TitleExitArt.cellWidth * 4
                    source.replaceSubrange(dstStart..<(dstStart + TitleExitArt.cellWidth * 4),
                                           with: rgba[srcStart..<(srcStart + TitleExitArt.cellWidth * 4)])
                }

                var top = 0
                var bottom = 0
                let letters = TitleExitArt.segment(source, rowTop: &top, rowBottom: &bottom)
                var sum: Int64 = 0
                var n = 0, maxDiff = 0, over8 = 0
                for y in 0..<TitleExitArt.cellHeight {
                    for x in 0..<TitleExitArt.cellWidth {
                        let inBox = y >= top - 1 && y <= bottom + 1 && letters.contains(where: { x >= $0.left - 1 && x <= $0.right + 1 })
                        if inBox { continue }

                        let o = (((y * TitleExitArt.cellWidth) + x) * 4) + 3
                        let diff = abs(Int(painted[o]) - Int(source[o]))
                        sum += Int64(diff)
                        n += 1
                        maxDiff = max(maxDiff, diff)
                        if diff > 8 { over8 += 1 }
                    }
                }

                let meanAlpha = n > 0 ? Double(sum) / Double(n) : 0
                let paddedName = names[word].padding(toLength: 9, withPad: " ", startingAt: 0)
                output.writeLine(String(format: "%@: glow model on %@: mean alpha error %.2f, max %d, %d of %d pixels off by more than 8",
                                        look, paddedName, meanAlpha, maxDiff, over8, n))
            }

            let stripFile = (out as NSString).appendingPathComponent("exit_strip_\(suffix)_\(look).png")
            try? PngWriter.write(stripFile, width: TitleExitArt.cellWidth, height: TitleExitArt.cellHeight * 6, rgba: strip)
            let scaledStrip = scale(strip, width: TitleExitArt.cellWidth, height: TitleExitArt.cellHeight * 6, k: 3)
            try? PngWriter.write((out as NSString).appendingPathComponent("exit_strip_\(suffix)_\(look)_3x.png"),
                                 width: TitleExitArt.cellWidth * 3, height: TitleExitArt.cellHeight * 6 * 3, rgba: scaledStrip)
            output.writeLine("\(look): strip -> \(stripFile) (and _3x)")
        }

        return ok ? ExitCode.ok : ExitCode.failed
    }

    private func scale(_ rgba: [UInt8], width: Int, height: Int, k: Int) -> [UInt8] {
        var big = [UInt8](repeating: 0, count: width * k * height * k * 4)
        for y in 0..<height {
            for x in 0..<width {
                let src = (y * width + x) * 4
                let r = rgba[src]
                let g = rgba[src + 1]
                let b = rgba[src + 2]
                let a = rgba[src + 3]
                for dy in 0..<k {
                    for dx in 0..<k {
                        let dst = (((y * k + dy) * width * k) + (x * k + dx)) * 4
                        big[dst] = r
                        big[dst + 1] = g
                        big[dst + 2] = b
                        big[dst + 3] = a
                    }
                }
            }
        }
        return big
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
