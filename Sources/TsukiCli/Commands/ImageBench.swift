import Foundation
import TsukiCore
import TsukiData

public enum ImageBench {
    private static let subjects: [(archive: String, name: String, label: String)] = [
        ("allpac1", "IMG1481.MZP", "HEP8"),
        ("allpac1", "IMG1481_20_00.MZP", "RGB565+LO+A"),
        ("allpac0", "BLACK.MZP", "PAL8"),
    ]

    public static func run(folder: String, reps: Int, threads: Int, output: CliWriter, error: CliWriter) -> Int {
        output.writeLine("best of \(reps); threads for the parallel rows: \(threads)")
        let picPadded = "picture".padding(toLength: 14, withPad: " ", startingAt: 0)
        let stagePadded = "stage".padding(toLength: 26, withPad: " ", startingAt: 0)
        output.writeLine("\(picPadded) \(stagePadded)        ms     Mpx/s  MB/s out")

        for subject in subjects {
            let archivePath = (folder as NSString).appendingPathComponent("image/" + subject.archive)
            let archive: Archive
            do {
                archive = try Archive.open(basePath: archivePath)
            } catch let err {
                error.writeLine("decode-all --bench-pictures: cannot open \(subject.archive): \(err)")
                return ExitCode.usage
            }

            guard let index = archive.find(subject.name) else {
                error.writeLine("decode-all --bench-pictures: \(subject.archive) has no \(subject.name)")
                return ExitCode.usage
            }

            let container: MzpContainer
            do {
                container = try archive.container(index)
            } catch let err {
                error.writeLine("decode-all --bench-pictures: \(subject.name) container error: \(err)")
                return ExitCode.usage
            }

            let image: ImageMzp
            do {
                image = try ImageMzp.open(container)
            } catch let err {
                error.writeLine("decode-all --bench-pictures: \(subject.name) error: \(err)")
                return ExitCode.usage
            }
            let h = image.header
            let live = (0..<h.tiles).filter { h.isLive($0) }
            let pixels = Int64(live.count) * Int64(h.tilePixels)
            let title = "\(subject.label) \(subject.name)"
            let storedMb = Double(pixels * 4) / 1e6
            output.writeLine(String(format: "%@: %@, %d live tiles, %.0f MB of stored RGBA",
                                    title, h.describe(), live.count, storedMb))

            // Stage 1: MZX0 only
            var raw: [[UInt8]] = Array(repeating: [], count: live.count)
            let mzx = best(reps) {
                for k in 0..<live.count {
                    let sec = image.container.section(1 + live[k])
                    raw[k] = (try? Mzx.decompress(sec).toArray()) ?? []
                }
            }
            row(output, picture: subject.label, stage: "MZX0 only", ms: mzx, pixels: pixels, bytes: pixels * 4)

            // Stage 2: conversion only
            var rgba = [UInt8](repeating: 0, count: h.tileRgbaBytes)
            let levels: [SimdLevel] = h.format == .rgb565LoA
                ? [.scalar, .vector128, .vector256]
                : [.auto]

            for level in levels {
                let conv = best(reps) {
                    for k in 0..<live.count {
                        if !raw[k].isEmpty {
                            try? TileConverter.convert(h, raw: ByteSpan(raw[k]), rgba: &rgba, simd: level)
                        }
                    }
                }
                row(output, picture: subject.label, stage: "convert \(level)", ms: conv, pixels: pixels, bytes: pixels * 4)
            }

            // Stage 3: whole decodes
            let one = best(reps) {
                _ = try? image.toPicture(maxDegreeOfParallelism: 1)
            }
            row(output, picture: subject.label, stage: "ToPicture, 1 thread", ms: one, pixels: pixels, bytes: pixels * 4)

            let many = best(reps) {
                _ = try? image.toPicture(maxDegreeOfParallelism: threads)
            }
            row(output, picture: subject.label, stage: "ToPicture, \(threads) threads", ms: many, pixels: pixels, bytes: pixels * 4)

            let hasher = PictureHasher()
            let shown = Int64(h.displayWidth) * Int64(h.displayHeight)
            let sha = best(reps) {
                _ = try? hasher.hash(image)
            }
            row(output, picture: subject.label, stage: "stream SHA-1, 1 thread", ms: sha, pixels: shown, bytes: shown * 4)
        }

        return ExitCode.ok
    }

    private static func best(_ reps: Int, _ action: () -> Void) -> Double {
        action() // warm-up
        var best = Double.greatestFiniteMagnitude
        for _ in 0..<reps {
            let start = Date()
            action()
            let ms = Date().timeIntervalSince(start) * 1000.0
            if ms < best {
                best = ms
            }
        }
        return best
    }

    private static func row(_ output: CliWriter, picture: String, stage: String, ms: Double, pixels: Int64, bytes: Int64) {
        let picPadded = picture.padding(toLength: 14, withPad: " ", startingAt: 0)
        let stagePadded = stage.padding(toLength: 26, withPad: " ", startingAt: 0)
        let mpx = ms > 0 ? Double(pixels) / ms / 1e3 : 0
        let mbs = ms > 0 ? Double(bytes) / ms / 1e3 : 0
        output.writeLine(String(format: "%@ %@ %9.2f %9.0f %9.0f", picPadded, stagePadded, ms, mpx, mbs))
    }
}
