import Foundation
import TsukiCore
import TsukiData

final class PictureSweep {
    private static let triplets = ["allpac0", "allpac1", "allpac1_2", "allpac2", "allpac3", "allpac4", "parts"]
    private static let standalone = ["allscr.mrg", "ft_en.mrg", "ft_ja.mrg", "ft_ko.mrg", "ft_zc.mrg", "ft_zt.mrg"]

    internal static let tsvHeader =
        "label\tname\tformat\twidth\theight\tshown_width\tshown_height\ttile_w\ttile_h\ttiles_x\ttiles_y\tattr\tlive_tiles\tsha1\tstratum"

    private let imageFolder: String
    private let threads: Int
    private let expect: [String: Expected]?
    private let complete: Bool
    private let sources: Set<String>?
    private let output: CliWriter
    private let labels: Set<String>?

    internal struct Expected: Equatable {
        var name: String
        var format: String
        var width: Int
        var height: Int
        var shownWidth: Int
        var shownHeight: Int
        var tileW: Int
        var tileH: Int
        var tilesX: Int
        var tilesY: Int
        var attr: Int
        var liveTiles: Int
        var sha1: String
    }

    internal struct Found {
        let sourceIndex: Int
        let entry: Int
        let path: [Int]
        let label: String
        let name: String
        let header: ImageHeader
        let liveTiles: Int
        let sha1: String
    }

    internal init(
        imageFolder: String,
        threads: Int,
        expect: [String: Expected]?,
        complete: Bool,
        sources: Set<String>?,
        output: CliWriter
    ) {
        self.imageFolder = imageFolder
        self.threads = threads
        self.expect = expect
        self.complete = complete
        self.sources = sources
        self.output = output
        self.labels = (!complete && expect != nil) ? Set(expect!.keys) : nil
    }

    private func wants(_ source: String) -> Bool {
        guard let s = sources else { return true }
        let withoutExt = (source as NSString).deletingPathExtension
        return s.contains(source) || s.contains(withoutExt)
    }

    internal static func loadExpected(_ path: String) throws -> [String: Expected] {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        var map: [String: Expected] = [:]
        let lines = content.components(separatedBy: .newlines)
        guard let first = lines.first, first.hasPrefix("label\t") else {
            throw TsukiError.format("\(path): not an oracle pictures.tsv (no header)")
        }

        for line in lines.dropFirst() {
            if line.isEmpty { continue }
            let f = line.components(separatedBy: "\t")
            guard f.count >= 14 else {
                throw TsukiError.format("\(path): row with \(f.count) columns: \(line)")
            }
            func parseI(_ i: Int) -> Int { Int(f[i]) ?? 0 }
            map[f[0]] = Expected(
                name: f[1], format: f[2], width: parseI(3), height: parseI(4),
                shownWidth: parseI(5), shownHeight: parseI(6), tileW: parseI(7),
                tileH: parseI(8), tilesX: parseI(9), tilesY: parseI(10),
                attr: parseI(11), liveTiles: parseI(12), sha1: f[13]
            )
        }
        return map
    }

    internal static func formatName(_ f: PixelFormat) -> String {
        switch f {
        case .pal4: return "pal4"
        case .pal8: return "pal8"
        case .hep8: return "hep8"
        default: return "rgb565lo+a"
        }
    }

    internal func run(_ tsv: FileHandle?) -> Int64 {
        var all: [Found] = []
        var failures: Int64 = 0
        var totalPixels: Int64 = 0
        var totalTiles: Int64 = 0
        var totalBytes: Int64 = 0
        let sw = Date()

        let srcPad = "source".padding(toLength: 12, withPad: " ", startingAt: 0)
        output.writeLine("\(srcPad)  pictures      tiles    RGBA MB   fail  seconds    Mpx/s")

        func report(name: String, found: [Found], tiles: Int64, pixels: Int64, bytes: Int64, fail: Int64, seconds: Double) {
            let padded = name.padding(toLength: 12, withPad: " ", startingAt: 0)
            let mpx = seconds > 0 ? Double(pixels) / seconds / 1e6 : 0
            let mb = Double(bytes) / 1e6
            output.writeLine(String(format: "%@ %9d %10d %10.0f %6d %8.1f %8.0f",
                                    padded, found.count, tiles, mb, fail, seconds, mpx))
            all.append(contentsOf: found)
            failures += fail
            totalPixels += pixels
            totalTiles += tiles
            totalBytes += bytes
        }

        for s in 0..<Self.triplets.count {
            let name = Self.triplets[s]
            if !wants(name) { continue }

            let t0 = Date()
            guard let archive = try? Archive.open(basePath: (imageFolder as NSString).appendingPathComponent(name)) else {
                continue
            }

            var found: [Found] = []
            var fail: Int64 = 0
            var tiles: Int64 = 0
            var pixels: Int64 = 0
            var bytes: Int64 = 0
            let hasher = PictureHasher()

            for e in 0..<archive.index.count {
                guard let container = try? archive.container(e) else {
                    fail += 1
                    continue
                }
                let entryName = archive.index.entries[e].name ?? ""
                process(top: container, source: name, sourceIndex: s, entry: e, name: entryName,
                        hasher: hasher, found: &found, fail: &fail, pixels: &pixels)
            }

            for f in found {
                tiles += Int64(f.liveTiles)
                bytes += Int64(f.liveTiles) * Int64(f.header.tileRgbaBytes)
            }
            report(name: name, found: found, tiles: tiles, pixels: pixels, bytes: bytes, fail: fail, seconds: Date().timeIntervalSince(t0))
        }

        for s in 0..<Self.standalone.count {
            let name = Self.standalone[s]
            if !wants(name) { continue }

            let t0 = Date()
            let path = (imageFolder as NSString).appendingPathComponent(name)
            guard let mrg = try? StandaloneMrg.open(path) else {
                continue
            }

            var found: [Found] = []
            var fail: Int64 = 0
            var tiles: Int64 = 0
            var pixels: Int64 = 0
            var bytes: Int64 = 0
            let hasher = PictureHasher()

            for e in 0..<mrg.container.count {
                if mrg.container.isNested(e) {
                    if let child = try? mrg.container.child(e) {
                        process(top: child, source: name, sourceIndex: Self.triplets.count + s, entry: e, name: "",
                                hasher: hasher, found: &found, fail: &fail, pixels: &pixels)
                    }
                }
            }

            for f in found {
                tiles += Int64(f.liveTiles)
                bytes += Int64(f.liveTiles) * Int64(f.header.tileRgbaBytes)
            }
            report(name: name, found: found, tiles: tiles, pixels: pixels, bytes: bytes, fail: fail, seconds: Date().timeIntervalSince(t0))
        }

        all.sort(by: { Self.compare($0, $1) < 0 })
        if let tsv = tsv {
            if let hData = (Self.tsvHeader + "\n").data(using: .utf8) {
                tsv.write(hData)
            }
            for f in all {
                if let rData = (Self.row(f) + "\n").data(using: .utf8) {
                    tsv.write(rData)
                }
            }
        }

        let totPad = "total".padding(toLength: 12, withPad: " ", startingAt: 0)
        let elapsed = Date().timeIntervalSince(sw)
        let totMpx = elapsed > 0 ? Double(totalPixels) / elapsed / 1e6 : 0
        let totMb = Double(totalBytes) / 1e6
        output.writeLine(String(format: "%@ %9d %10d %10.0f %6d %8.1f %8.0f",
                                totPad, all.count, totalTiles, totMb, failures, elapsed, totMpx))

        if expect != nil {
            failures += compareExpected(all)
        }

        return failures
    }

    private func process(
        top: MzpContainer, source: String, sourceIndex: Int, entry: Int, name: String,
        hasher: PictureHasher, found: inout [Found], fail: inout Int64, pixels: inout Int64
    ) {
        do {
            try PictureWalker.walk(top) { path, container in
                let label = PictureWalker.label(source, entry: entry, path: path)
                if let l = self.labels, !l.contains(label) {
                    return
                }

                do {
                    let image = try ImageMzp.open(container)
                    let sha1 = try hasher.hashHex(image)
                    var live = 0
                    for k in 0..<image.header.tiles {
                        if image.header.isLive(k) {
                            live += 1
                        }
                    }
                    found.append(Found(sourceIndex: sourceIndex, entry: entry, path: path, label: label, name: name, header: image.header, liveTiles: live, sha1: sha1))
                    pixels += Int64(image.header.displayWidth) * Int64(image.header.displayHeight)
                } catch {
                    fail += 1
                }
            }
        } catch {
            fail += 1
        }
    }

    private static func compare(_ a: Found, _ b: Found) -> Int {
        if a.sourceIndex != b.sourceIndex {
            return a.sourceIndex < b.sourceIndex ? -1 : 1
        }
        if a.entry != b.entry {
            return a.entry < b.entry ? -1 : 1
        }
        let minLen = min(a.path.count, b.path.count)
        for i in 0..<minLen {
            if a.path[i] != b.path[i] {
                return a.path[i] < b.path[i] ? -1 : 1
            }
        }
        if a.path.count != b.path.count {
            return a.path.count < b.path.count ? -1 : 1
        }
        return 0
    }

    private static func row(_ f: Found) -> String {
        let h = f.header
        return "\(f.label)\t\(f.name)\t\(formatName(h.format))\t\(h.width)\t\(h.height)\t\(h.displayWidth)\t\(h.displayHeight)\t\(h.tileWidth)\t\(h.tileHeight)\t\(h.tilesX)\t\(h.tilesY)\t\(h.attr)\t\(f.liveTiles)\t\(f.sha1)\t-"
    }

    private func compareExpected(_ all: [Found]) -> Int64 {
        guard let expect = expect else { return 0 }
        var equal: Int64 = 0
        var different: Int64 = 0
        var unlisted: Int64 = 0
        var seen = Set<String>()
        var messages: [String] = []

        for f in all {
            seen.insert(f.label)
            guard let want = expect[f.label] else {
                unlisted += 1
                continue
            }

            let h = f.header
            var got = Expected(
                name: f.name, format: Self.formatName(h.format), width: h.width, height: h.height,
                shownWidth: h.displayWidth, shownHeight: h.displayHeight, tileW: h.tileWidth,
                tileH: h.tileHeight, tilesX: h.tilesX, tilesY: h.tilesY, attr: h.attr,
                liveTiles: f.liveTiles, sha1: f.sha1
            )
            var wantCopy = want
            wantCopy.name = got.name
            if wantCopy == got {
                equal += 1
            } else {
                different += 1
                if messages.count < 10 {
                    messages.append(want.sha1 != got.sha1
                        ? "\(f.label): SHA-1 \(got.sha1) != oracle \(want.sha1)"
                        : "\(f.label): header facts differ")
                }
            }
        }

        var missing: Int64 = 0
        for k in expect.keys {
            if let hashIdx = k.firstIndex(of: "#") {
                let src = String(k[..<hashIdx])
                if wants(src) && !seen.contains(k) {
                    missing += 1
                }
            }
        }

        output.writeLine("oracle: \(expect.count) listed; equal \(equal), different \(different), listed but not decoded \(missing), decoded but not listed \(unlisted)")
        for m in messages {
            output.writeLine("    " + m)
        }

        var fail = different + missing
        if complete {
            fail += unlisted
        }
        return fail
    }
}
