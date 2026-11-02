import Foundation
import CommonCrypto
import TsukiCore
import TsukiData

public final class DecodeAllCommand: CliCommand {
    private static let triplets = ["allpac0", "allpac1", "allpac1_2", "allpac2", "allpac3", "allpac4", "parts"]
    private static let standalone = ["allscr.mrg", "ft_en.mrg", "ft_ja.mrg", "ft_ko.mrg", "ft_zc.mrg", "ft_zt.mrg"]

    public var name: String { "decode-all" }
    public var summary: String { "decode every MZX0 stream and check sizes; --pictures: every picture's SHA-1; --bench-pictures: decoder throughput per stage; options: --game DIR, --only a,b, --threads N, --hashes FILE, --picture-hashes FILE, --expect FILE, --complete" }

    public init() {}

    private final class Tally {
        var streams: Int64 = 0
        var compressed: Int64 = 0
        var decompressed: Int64 = 0
        var maxOvershoot: Int = 0
        var failures: Int64 = 0
        var samples: [String] = []

        func merge(_ o: Tally) {
            streams += o.streams
            compressed += o.compressed
            decompressed += o.decompressed
            maxOvershoot = max(maxOvershoot, o.maxOvershoot)
            failures += o.failures
            if samples.count < 10 {
                samples.append(contentsOf: o.samples.prefix(10 - samples.count))
            }
        }

        func fail(_ message: String) {
            failures += 1
            if samples.count < 10 {
                samples.append(message)
            }
        }
    }

    private final class Worker {
        let source: String
        let hashWriter: FileHandle?
        var buffer: [UInt8] = [UInt8](repeating: 0, count: 1 << 20)
        let tally = Tally()

        init(source: String, hashWriter: FileHandle?) {
            self.source = source
            self.hashWriter = hashWriter
        }

        func container(_ c: MzpContainer, _ label: String, _ path: String, invert: Bool) {
            for i in 0..<c.count {
                let p = path.isEmpty ? "\(i)" : "\(path)/\(i)"
                if c.isNested(i) {
                    if let child = try? c.child(i) {
                        container(child, label, p, invert: invert)
                    }
                } else if Mzx.isMzx(c.head(i, count: 8)) {
                    if let sec = try? c.section(i) {
                        stream(sec, "\(label)/\(p)", invert: invert)
                    }
                }
            }
        }

        func stream(_ section: ByteSpan, _ label: String, invert: Bool) {
            do {
                let declared = try Mzx.declaredSize(section)
                let req = Mzx.bufferSize(declared)
                if buffer.count < req {
                    buffer = [UInt8](repeating: 0, count: req)
                }

                let stats = try Mzx.decode(section, into: &buffer, invert: invert)
                tally.streams += 1
                tally.compressed += Int64(section.count)
                tally.decompressed += Int64(declared)
                tally.maxOvershoot = max(tally.maxOvershoot, stats.overshoot)
                if stats.consumed != section.count {
                    tally.fail("\(label): consumed \(stats.consumed) of \(section.count) section bytes")
                }
                writeHash(label, Array(buffer.prefix(declared)))
            } catch {
                tally.fail("\(label): \(error)")
            }
        }

        func voice(_ entry: MrgEntry, _ span: ByteSpan) {
            let label = "\(source)#\(entry.index)"
            do {
                let lv = try Lv.parse(span)
                let body = span.slice(lv.bodyOffset, span.count - lv.bodyOffset)
                guard Mzx.isMzx(body) else {
                    tally.fail("\(label): no MZX0 body")
                    return
                }

                let declared = try Mzx.declaredSize(body)
                let req = Mzx.bufferSize(declared)
                if buffer.count < req {
                    buffer = [UInt8](repeating: 0, count: req)
                }

                let stats = try Mzx.decode(body, into: &buffer)
                let exact = Int64(lv.bodyOffset + stats.consumed)
                tally.streams += 1
                tally.compressed += Int64(stats.consumed)
                tally.decompressed += Int64(declared)
                tally.maxOvershoot = max(tally.maxOvershoot, stats.overshoot)

                if entry.sizeSectors != Int((exact / Int64(Mzp.sector)) + 1) {
                    tally.fail("\(label): HED4 sectors \(entry.sizeSectors) != exact \(exact) / 0x800 + 1")
                }

                let data = Array(buffer.prefix(declared))
                if declared < 12 || Array(data.prefix(4)) != Array("RIFF".utf8) {
                    tally.fail("\(label): RIFF header missing in declared MZX size \(declared)")
                } else {
                    let riffSize = Int(data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) })
                    if riffSize + 8 != declared {
                        tally.fail("\(label): RIFF size does not equal the declared MZX size \(declared)")
                    }
                }

                writeHash(label + "/lv", data)
            } catch {
                tally.fail("\(label): \(error)")
            }
        }

        private func writeHash(_ label: String, _ data: [UInt8]) {
            guard let hw = hashWriter else { return }
            var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            data.withUnsafeBytes { ptr in
                _ = CC_SHA256(ptr.baseAddress, CC_LONG(data.count), &hash)
            }
            let hex = hash.map { String(format: "%02x", $0) }.joined()
            let line = "\(label)\t\(hex)\n"
            if let lineData = line.data(using: .utf8) {
                hw.write(lineData)
            }
        }
    }

    public func run(_ args: [String], output: CliWriter, error: CliWriter) -> Int {
        var game: String? = nil
        var hashes: String? = nil
        var pictures = false
        var benchPictures = false
        var reps = 7
        var complete = false
        var pictureHashes: String? = nil
        var expect: String? = nil
        var only: Set<String>? = nil
        var threads = ProcessInfo.processInfo.activeProcessorCount

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--game":
                if i + 1 < args.count {
                    i += 1
                    game = args[i]
                }
            case "--only":
                if i + 1 < args.count {
                    i += 1
                    only = Set(args[i].components(separatedBy: ",").map { $0.lowercased() })
                }
            case "--threads":
                if i + 1 < args.count, let t = Int(args[i + 1]), t > 0 {
                    i += 1
                    threads = t
                }
            case "--hashes":
                if i + 1 < args.count {
                    i += 1
                    hashes = args[i]
                }
            case "--pictures":
                pictures = true
            case "--complete":
                complete = true
            case "--bench-pictures":
                benchPictures = true
            case "--reps":
                if i + 1 < args.count, let r = Int(args[i + 1]), r > 0 {
                    i += 1
                    reps = r
                }
            case "--picture-hashes":
                if i + 1 < args.count {
                    i += 1
                    pictureHashes = args[i]
                }
            case "--expect":
                if i + 1 < args.count {
                    i += 1
                    expect = args[i]
                }
            default:
                error.writeLine("decode-all: unexpected argument '\(arg)'")
                return ExitCode.usage
            }
            i += 1
        }

        if !pictures && (complete || pictureHashes != nil || expect != nil) {
            error.writeLine("decode-all: --picture-hashes, --expect and --complete need --pictures")
            return ExitCode.usage
        }

        guard let folder = GameFolderLocator.resolve(game) else {
            error.writeLine("decode-all: no game folder; pass --game <dir> or set TSUKI_GAME_DIR")
            return ExitCode.usage
        }

        let imagePath = (folder as NSString).appendingPathComponent("image")
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: imagePath, isDirectory: &isDir) || !isDir.boolValue {
            error.writeLine("decode-all: no game folder; pass --game <dir> or set TSUKI_GAME_DIR")
            return ExitCode.usage
        }

        if benchPictures {
            return ImageBench.run(folder: folder, reps: reps, threads: threads, output: output, error: error)
        }

        if pictures {
            var expected: [String: PictureSweep.Expected]? = nil
            if let exp = expect {
                do {
                    expected = try PictureSweep.loadExpected(exp)
                } catch let err {
                    error.writeLine("decode-all: \(err)")
                    return ExitCode.usage
                }
            }

            var tsv: FileHandle? = nil
            if let ph = pictureHashes {
                FileManager.default.createFile(atPath: ph, contents: nil)
                tsv = FileHandle(forWritingAtPath: ph)
            }
            let failed = PictureSweep(imageFolder: imagePath, threads: threads, expect: expected, complete: complete, sources: only, output: output).run(tsv)
            try? tsv?.close()
            return failed == 0 ? ExitCode.ok : ExitCode.failed
        }

        var hashWriter: FileHandle? = nil
        if let h = hashes {
            FileManager.default.createFile(atPath: h, contents: nil)
            hashWriter = FileHandle(forWritingAtPath: h)
        }

        var failures: Int64 = 0
        let total = Tally()
        let sw = Date()
        let srcPad = "source".padding(toLength: 16, withPad: " ", startingAt: 0)
        output.writeLine("\(srcPad)    streams      compressed     decompressed max over   fail  seconds  MB/s out")

        func report(name: String, t: Tally, seconds: Double) {
            let padded = name.padding(toLength: 16, withPad: " ", startingAt: 0)
            let mbs = seconds > 0 ? Double(t.decompressed) / seconds / 1e6 : 0
            output.writeLine(String(format: "%@ %10d %15d %16d %8d %6d %8.1f %9.0f",
                                    padded, t.streams, t.compressed, t.decompressed, t.maxOvershoot, t.failures, seconds, mbs))
            for s in t.samples {
                output.writeLine("    " + s)
            }
            failures += t.failures
            total.merge(t)
        }

        for name in Self.triplets {
            if let o = only, !o.contains(name.lowercased()) { continue }

            let t0 = Date()
            guard let archive = try? Archive.open(basePath: (imagePath as NSString).appendingPathComponent(name)) else {
                continue
            }

            let w = Worker(source: name, hashWriter: hashWriter)
            for e in 0..<archive.index.count {
                if let container = try? archive.container(e) {
                    w.container(container, "\(name)#\(e)", "", invert: false)
                }
            }
            report(name: name, t: w.tally, seconds: Date().timeIntervalSince(t0))
        }

        for name in ["voice", "voice2"] {
            if let o = only, !o.contains(name.lowercased()) { continue }

            let t0 = Date()
            guard let archive = try? Archive.open(basePath: (imagePath as NSString).appendingPathComponent(name)) else {
                continue
            }

            let w = Worker(source: name, hashWriter: hashWriter)
            for e in 0..<archive.index.count {
                let entry = archive.index.entries[e]
                w.voice(entry, archive.sectorSpan(e))
            }
            report(name: name, t: w.tally, seconds: Date().timeIntervalSince(t0))
        }

        for file in Self.standalone {
            let withoutExt = (file as NSString).deletingPathExtension
            if let o = only, !o.contains(file.lowercased()) && !o.contains(withoutExt.lowercased()) {
                continue
            }

            let t0 = Date()
            guard let mrg = try? StandaloneMrg.open((imagePath as NSString).appendingPathComponent(file)) else {
                continue
            }

            let w = Worker(source: file, hashWriter: hashWriter)
            let isScripts = file == "allscr.mrg"
            for s in 0..<mrg.container.count {
                if mrg.container.isNested(s) {
                    if let child = try? mrg.container.child(s) {
                        w.container(child, "\(file)#\(s)", "", invert: false)
                    }
                } else if Mzx.isMzx(mrg.container.head(s, count: 8)) {
                    if let sec = try? mrg.container.section(s) {
                        w.stream(sec, "\(file)#\(s)", invert: isScripts && s >= 3)
                    }
                }
            }
            report(name: file, t: w.tally, seconds: Date().timeIntervalSince(t0))
        }

        try? hashWriter?.close()
        let totPad = "total".padding(toLength: 16, withPad: " ", startingAt: 0)
        let elapsed = Date().timeIntervalSince(sw)
        let totMbs = elapsed > 0 ? Double(total.decompressed) / elapsed / 1e6 : 0
        output.writeLine(String(format: "%@ %10d %15d %16d %8d %6d %8.1f %9.0f",
                                totPad, total.streams, total.compressed, total.decompressed, total.maxOvershoot, total.failures, elapsed, totMbs))
        return failures == 0 ? ExitCode.ok : ExitCode.failed
    }
}
