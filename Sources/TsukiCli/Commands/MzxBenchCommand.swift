import Foundation
import TsukiCore
import TsukiData

public final class MzxBenchCommand: CliCommand {
    private static let classNames = ["tile", "voice", "script", "font"]

    public var name: String { "bench-mzx" }
    public var summary: String { "single-thread MZX0 throughput on samples/golden_data/bench/streams.bin; options: --pack FILE, --rounds N" }

    public init() {}

    private struct BenchStream {
        let kind: Int
        let invert: Bool
        let declared: Int
        let data: [UInt8]
    }

    public func run(_ args: [String], output: CliWriter, error: CliWriter) -> Int {
        var pack: String? = nil
        var rounds = 7

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--pack":
                if i + 1 < args.count {
                    i += 1
                    pack = args[i]
                }
            case "--rounds":
                if i + 1 < args.count, let r = Int(args[i + 1]), r > 0 {
                    i += 1
                    rounds = r
                }
            default:
                error.writeLine("bench-mzx: unexpected argument '\(arg)'")
                return ExitCode.usage
            }
            i += 1
        }

        pack = pack ?? findPack()
        guard let pack = pack, FileManager.default.fileExists(atPath: pack) else {
            error.writeLine("bench-mzx: stream pack not found; run tests/Tsuki.Tests.Data/Oracle/gen_golden_data.py --parts bench or pass --pack FILE")
            return ExitCode.usage
        }

        let streams: [BenchStream]
        do {
            streams = try load(pack)
        } catch let err {
            error.writeLine("bench-mzx: \(err)")
            return ExitCode.usage
        }

        let cpus = ProcessInfo.processInfo.activeProcessorCount
        output.writeLine("\(streams.count) streams from \(pack); best of \(rounds) rounds, 1 thread, \(cpus) logical CPUs")
        let pythonPath = ((pack as NSString).deletingLastPathComponent as NSString).appendingPathComponent("python.json")
        let python = loadPython(pythonPath)

        var totalOut: Int64 = 0
        var totalReuse: Double = 0
        var totalAlloc: Double = 0

        for kind in 0..<Self.classNames.count {
            let sub = streams.filter { $0.kind == kind }
            if sub.isEmpty { continue }

            let outBytes = sub.reduce(Int64(0)) { $0 + Int64($1.declared) }
            let inBytes = sub.reduce(Int64(0)) { $0 + Int64($1.data.count) }
            let maxDecl = sub.map(\.declared).max() ?? 0
            var buffer = [UInt8](repeating: 0, count: Mzx.bufferSize(maxDecl))

            let reuse = best(rounds) {
                for s in sub {
                    _ = try? Mzx.decode(ByteSpan(s.data), into: &buffer, invert: s.invert)
                }
            }

            let alloc = best(rounds) {
                for s in sub {
                    _ = try? Mzx.decompress(ByteSpan(s.data), invert: s.invert)
                }
            }

            totalOut += outBytes
            totalReuse += reuse
            totalAlloc += alloc
            let py = pythonText(python, Self.classNames[kind])

            let paddedKind = Self.classNames[kind].padding(toLength: 7, withPad: " ", startingAt: 0)
            let inMb = Double(inBytes) / 1e6
            let outMb = Double(outBytes) / 1e6
            let reuseSpeed = Double(outBytes) / reuse / 1e6
            let allocSpeed = Double(outBytes) / alloc / 1e6
            output.writeLine(String(format: "  %@ %4d streams  %8.1f MB in -> %9.1f MB out   Swift reuse buffer %7.0f MB/s   Swift allocating %7.0f MB/s%@",
                                    paddedKind, sub.count, inMb, outMb, reuseSpeed, allocSpeed, py))
        }

        let totMb = Double(totalOut) / 1e6
        let totReuseSpeed = Double(totalOut) / totalReuse / 1e6
        let totAllocSpeed = Double(totalOut) / totalAlloc / 1e6
        output.writeLine(String(format: "  all     %4d streams  %9.1f MB out   Swift reuse buffer %7.0f MB/s   Swift allocating %7.0f MB/s",
                                streams.count, totMb, totReuseSpeed, totAllocSpeed))
        return ExitCode.ok
    }

    private func best(_ rounds: Int, _ work: () -> Void) -> Double {
        work() // warm-up
        var best = Double.greatestFiniteMagnitude
        for _ in 0..<rounds {
            let start = Date()
            work()
            let elapsed = Date().timeIntervalSince(start)
            if elapsed < best {
                best = elapsed
            }
        }
        return best
    }

    private func pythonText(_ python: [String: Any]?, _ cls: String) -> String {
        guard let root = python,
              let classes = root["classes"] as? [String: Any],
              let c = classes[cls] as? [String: Any] else {
            return ""
        }
        var text = ""
        if let nb = c["numba"] as? [String: Any], let mb = nb["mb_per_s"] as? Double {
            text += String(format: "   python numba %.0f MB/s", mb)
        }
        if let py = c["python"] as? [String: Any], let mb = py["mb_per_s"] as? Double {
            text += String(format: "   python pure %.0f MB/s", mb)
        }
        return text
    }

    private func loadPython(_ path: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private func load(_ path: String) throws -> [BenchStream] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard data.count >= 8, data.prefix(4) == Data("MZXB".utf8) else {
            throw TsukiError.format("\(path) is not a stream pack")
        }

        let count = Int(data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) })
        var list: [BenchStream] = []
        list.reserveCapacity(count)

        var pos = 8
        for _ in 0..<count {
            guard pos + 12 <= data.count else { break }
            let kind = Int(data[pos])
            let invert = data[pos + 1] != 0
            let declared = Int(data.withUnsafeBytes { $0.load(fromByteOffset: pos + 4, as: UInt32.self) })
            let len = Int(data.withUnsafeBytes { $0.load(fromByteOffset: pos + 8, as: UInt32.self) })
            pos += 12
            guard pos + len <= data.count else { break }
            let streamData = [UInt8](data[pos..<(pos + len)])
            list.append(BenchStream(kind: kind, invert: invert, declared: declared, data: streamData))
            pos += len
        }

        return list
    }

    private func findPack() -> String? {
        let fm = FileManager.default
        var cur = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while cur.path != "/" {
            let candidate = cur.appendingPathComponent("samples/golden_data/bench/streams.bin").path
            if fm.fileExists(atPath: candidate) {
                return candidate
            }
            cur = cur.deletingLastPathComponent()
        }
        return nil
    }
}
