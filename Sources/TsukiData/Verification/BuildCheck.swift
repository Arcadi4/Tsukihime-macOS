import Foundation
import TsukiCore
import TsukiEngine

/// Confirms that a CUSA47999 folder is the analysed build before any table is read (RR 3.3,
/// ARCHITECTURE 4.1): eboot.bin by exact size and SHA-256, two structural probes, and the counts of
/// FORMATS section 2. Only small ranges of the archives are read (the .hed, the .nam, the lengths of
/// the .mrg files, a few sections of the standalone files), so it takes well under a second.
public enum BuildCheck {
    private static let maxHashedEbootBytes = 64 * 1024 * 1024
    private static let ebootPath = "eboot.bin"

    /// Checks the folder at `gameDirectory`.
    public static func run(_ gameDirectory: String) -> BuildReport {
        run(DirectoryGameFiles(root: gameDirectory))
    }

    /// Checks a resolved layout (the update over the base).
    public static func run(_ layout: GameLayout) throws -> BuildReport {
        run(try layout.openFiles())
    }

    /// Checks any view of a game folder.
    public static func run(_ files: GameFiles) -> BuildReport {
        let run = Runner(files)
        run.guardStep("eboot.bin") { try run.checkEboot() }
        for spec in AnalysedBuild.triplets {
            run.guardStep(spec.name) { try run.checkTriplet(spec) }
        }

        for spec in AnalysedBuild.standalone {
            run.guardStep(spec.fileName) { try run.checkStandalone(spec) }
        }

        run.guardStep("allscr.mrg names") { try run.checkScripts() }
        run.guardStep("script_text.mrg") { try run.checkText() }
        run.guardStep("se_nam.mrg") { try run.checkVseNames() }
        run.guardStep("image/movie") { run.checkMovies() }
        run.checkTotals()
        return BuildReport(source: files.description, info: run.info, checks: run.results, counts: run.counts,
                           identity: run.identity, locations: run.locations)
    }

    private final class Runner {
        let files: GameFiles
        private(set) var results: [CheckResult] = []
        let counts = BuildCounts()
        private(set) var info: BuildInfo?
        private(set) var identity: BuildIdentity?
        private(set) var locations: LocateResult?

        init(_ files: GameFiles) {
            self.files = files
        }

        /// True while the identity says the eboot is not a known release: count mismatches become
        /// notes, not failures.
        private var otherRelease: Bool { identity?.match == .unknown }

        /// Runs one check; a file that exists but cannot be read becomes a failed check, not a crash.
        func guardStep(_ what: String, _ check: () throws -> Void) {
            do {
                try check()
            } catch {
                let message = "\(error)"
                fail("io." + what, what + " readable", .fileMissing, "readable", message,
                     "\(what) could not be read: \(message)")
            }
        }

        private func pass(_ id: String, _ title: String, _ expected: String, _ actual: String) {
            results.append(CheckResult(id: id, title: title, status: .pass, failure: .none,
                                       expected: expected, actual: actual, message: ""))
        }

        private func fail(_ id: String, _ title: String, _ kind: BuildFailure, _ expected: String,
                          _ actual: String, _ message: String) {
            results.append(CheckResult(id: id, title: title, status: .fail, failure: kind,
                                       expected: expected, actual: actual, message: message))
        }

        private func note(_ id: String, _ title: String, _ expected: String, _ actual: String, _ message: String) {
            results.append(CheckResult(id: id, title: title, status: .note, failure: .none,
                                       expected: expected, actual: actual, message: message))
        }

        private func countCheck(_ id: String, _ title: String, _ expected: Int, _ actual: Int, _ what: String) {
            if expected == actual {
                pass(id, title, buildNumber(expected), buildNumber(actual))
            } else if otherRelease {
                note(id, title, buildNumber(expected), buildNumber(actual),
                     "\(what): found \(buildNumber(actual)), the verified build has \(buildNumber(expected)) (another data release).")
            } else {
                fail(id, title, .countMismatch, buildNumber(expected), buildNumber(actual),
                     "\(what): found \(buildNumber(actual)), the analysed build has \(buildNumber(expected)). This is a different data release.")
            }
        }

        // MARK: - eboot.bin (RR 3.3 items 1 and 2)

        func checkEboot() throws {
            if !files.exists(BuildCheck.ebootPath) {
                fail("eboot.present", "eboot.bin present", .ebootMissing, "present", "missing",
                     "eboot.bin was not found in \(files.description). Point the program at the CUSA47999 folder that holds eboot.bin and image\\.")
                return
            }

            pass("eboot.present", "eboot.bin present", "present", "present")
            let length = try files.length(of: BuildCheck.ebootPath)
            let sizeOk = length == BuildInfo.analysedEbootSize
            if sizeOk {
                pass("eboot.size", "eboot.bin size", buildNumber(BuildInfo.analysedEbootSize), buildNumber(length))
            } else {
                fail("eboot.size", "eboot.bin size", .ebootSizeMismatch,
                     buildNumber(BuildInfo.analysedEbootSize), buildNumber(length),
                     "eboot.bin is \(buildNumber(length)) bytes, the analysed build's is \(buildNumber(BuildInfo.analysedEbootSize)). "
                        + "This is another build or an incomplete copy; the addresses of the documents do not apply.")
            }

            if length > BuildCheck.maxHashedEbootBytes {
                fail("eboot.sha256", "eboot.bin SHA-256", .ebootHashMismatch, BuildInfo.analysedEbootSHA256,
                     "not computed", "eboot.bin is too large to be the analysed build; its hash was not computed.")
                return
            }

            let data = try files.readAll(BuildCheck.ebootPath)
            let sha = sha256Hex(data)
            info = BuildInfo(source: files.description, ebootSize: length, ebootSHA256: sha)
            let identified = BuildIdentity.identify(files, eboot: data)
            identity = identified
            if sha == BuildInfo.analysedEbootSHA256 {
                pass("eboot.sha256", "eboot.bin SHA-256", BuildInfo.analysedEbootSHA256, sha)
            } else {
                let how = sizeOk
                    ? "Its size matches but its content differs: the file is modified or damaged, or it is another build of the same size."
                    : "Its size differs too, so this is another build."
                fail("eboot.sha256", "eboot.bin SHA-256", .ebootHashMismatch, BuildInfo.analysedEbootSHA256, sha,
                     "The SHA-256 of eboot.bin is \(sha), not the verified build's. \(how) "
                        + "Its tables are looked for by content instead (package K25).")
            }

            // What the dump is, and whether every table can be found in this eboot.
            let verified = identified.match == .verified && identified.known == KnownBuilds.verified
            results.append(CheckResult(id: "eboot.identity", title: "build identity",
                                       status: verified ? .pass : .note, failure: .none,
                                       expected: KnownBuilds.verified.name, actual: identified.describe(),
                                       message: ""))

            // Structural probes: a self-test when the hash matches, diagnostics when it does not.
            let selfOk = data.count >= 4 && data.slice(0, 4).elementsEqual(AnalysedBuild.selfMagic)
            if selfOk {
                pass("eboot.probe.self", "SELF magic 4F 15 3D 1D", "4F153D1D", "4F153D1D")
            } else {
                let found = hexLower(data.slice(0, min(4, data.count)))
                fail("eboot.probe.self", "SELF magic 4F 15 3D 1D", .ebootProbeFailed, "4F153D1D", found,
                     "eboot.bin does not start with the PS4 SELF magic; it is not a PS4 executable.")
            }

            let hunex = AnalysedBuild.hunexString
            let at = AnalysedBuild.hunexStringOffset
            let hunexOk = data.count >= at + hunex.count && data.slice(at, hunex.count).elementsEqual(hunex)
            if hunexOk {
                pass("eboot.probe.hunex", "\"Hunex Consumer Library\" at text VA 0x2DA510", "found", "found")
            } else if BuildCheck.contains(data, hunex) {
                note("eboot.probe.hunex", "\"Hunex Consumer Library\" at text VA 0x2DA510", "found", "found elsewhere",
                     "The engine's name is in this eboot, at another place than in the verified build.")
            } else {
                let offset = String(at, radix: 16, uppercase: true)
                fail("eboot.probe.hunex", "\"Hunex Consumer Library\" at text VA 0x2DA510", .ebootProbeFailed,
                     "found", "not found",
                     "The string \"Hunex Consumer Library\" is not in eboot.bin (the verified build has it at file offset 0x\(offset)); "
                        + "this is not the game's engine.")
            }

            if !selfOk {
                return
            }

            if verified {
                pass("eboot.tables", "eboot tables", "at the documented addresses", "at the documented addresses")
                return
            }

            let located: LocateResult
            do {
                located = EbootLocator.locate(try EbootReader.parse(data))
            } catch {
                fail("eboot.tables", "eboot tables", .ebootProbeFailed, "every table located by content", "unreadable",
                     "eboot.bin cannot be read as a PS4 SELF: \(error)")
                return
            }

            locations = located
            if located.complete {
                note("eboot.tables", "eboot tables", "at the documented addresses", located.summary(),
                     "The eboot is not the verified one; \(located.summary()).")
            } else {
                let names = located.missing.map { $0.name }.joined(separator: ", ")
                fail("eboot.tables", "eboot tables", .ebootProbeFailed, "every table located by content", located.summary(),
                     "This copy (\(identified.shortName)) is a build the port does not know, and \(located.missing.count) "
                        + "of its tables could not be found: \(names). Please report it with the log file.")
            }
        }

        // MARK: - triplet archives (FORMATS 2, containers.md 2 and 3)

        func checkTriplet(_ spec: TripletSpec) throws {
            let id = "data." + spec.name
            let prefix = "image/" + spec.name
            let extensions = spec.hasNam ? [".hed", ".nam", ".mrg"] : [".hed", ".mrg"]
            var missing: [String] = []
            for ext in extensions where !files.exists(prefix + ext) {
                missing.append(spec.name + ext)
            }

            if !missing.isEmpty {
                let joined = missing.joined(separator: ", ")
                fail(id + ".files", spec.name + " files", .fileMissing, "all present", "missing " + joined,
                     "Required file\(missing.count > 1 ? "s" : "") missing from image\\: \(joined). The folder is incomplete.")
                return
            }

            pass(id + ".files", spec.name + " files", "all present", "all present")
            let index: ArchiveIndex
            do {
                index = try ArchiveIndex.load(files, base: prefix)
            } catch {
                if BuildCheck.isIOError(error) { throw error }
                fail(id + ".layout", spec.name + " layout", .layoutInvalid, "valid HED/NAM", "\(error)",
                     "\(spec.name).hed or .nam is not a valid table: \(error)")
                return
            }

            counts.setTripletEntries(spec.name, index.count)
            var problems: [String] = []
            if index.format != spec.format {
                problems.append("layout \(BuildCheck.formatName(index.format)) instead of \(BuildCheck.formatName(spec.format))")
            }

            problems.append(contentsOf: index.validate())
            let termLength = index.hed.terminator.count
            if spec.hasTerminator ? termLength == 0 : termLength != 0 {
                problems.append(spec.hasTerminator ? "no 0xFF terminator record" : "unexpected terminator")
            }

            if !index.hed.trailing.isEmpty {
                problems.append("\(index.hed.trailing.count) bytes after the terminator")
            }

            if index.hed.bankStarts != spec.bankStarts {
                problems.append("bank starts [\(index.hed.bankStarts.map(String.init).joined(separator: ", "))] "
                    + "instead of [\(spec.bankStarts.map(String.init).joined(separator: ", "))]")
            }

            if problems.isEmpty {
                pass(id + ".layout", spec.name + " layout",
                     "\(BuildCheck.formatName(spec.format)), gapless, ends at the .mrg size",
                     "\(BuildCheck.formatName(index.format)), \(index.count) entries")
            } else {
                let shown = problems.prefix(3).joined(separator: "; ")
                    + (problems.count > 3 ? "; and \(problems.count - 3) more" : "")
                fail(id + ".layout", spec.name + " layout", .layoutInvalid, "valid", "\(problems.count) problem(s)",
                     "\(spec.name) does not have the documented layout: \(shown).")
            }

            countCheck(id + ".count", spec.name + " entries", spec.entries, index.count, spec.name + " entry count")
        }

        // MARK: - standalone mrgd00 files (containers.md 8)

        func checkStandalone(_ spec: StandaloneSpec) throws {
            let id = "data." + spec.fileName
            let path = "image/" + spec.fileName
            if !files.exists(path) {
                fail(id + ".files", spec.fileName, .fileMissing, "present", "missing",
                     "Required file missing from image\\: \(spec.fileName). The folder is incomplete.")
                return
            }

            pass(id + ".files", spec.fileName + " present", "present", "present")
            do {
                let (sections, length) = try readSections(path)
                counts.setStandaloneSections(spec.fileName, sections.count)
                let end = sections.map(\.end).max() ?? 0
                let packed = end + Mzp.padAfter(end)
                if packed != length {
                    fail(id + ".layout", spec.fileName + " layout", .layoutInvalid, buildNumber(length), buildNumber(packed),
                         "\(spec.fileName): the sections end at \(buildNumber(packed)) (with padding) but the file has "
                            + "\(buildNumber(length)) bytes.")
                } else {
                    pass(id + ".layout", spec.fileName + " layout", "sections fill the file", "sections fill the file")
                }

                countCheck(id + ".sections", spec.fileName + " sections", spec.sections, sections.count,
                           spec.fileName + " section count")
            } catch {
                if BuildCheck.isIOError(error) { throw error }
                fail(id + ".layout", spec.fileName + " layout", .layoutInvalid, "valid mrgd00", "\(error)",
                     "\(spec.fileName) is not a valid mrgd00 container: \(error)")
            }
        }

        private func readSections(_ path: String) throws -> (sections: [MzpSection], length: Int) {
            let length = try files.length(of: path)
            let head8 = try files.readRange(path, offset: 0, count: min(8, length))
            let head = ByteSpan(head8)
            guard head.count >= 8, Mzp.isContainer(head) else {
                throw TsukiError.format("bad magic (expected mrgd00)")
            }

            let count = Int(head.u16(6))
            let tableEnd = 8 + 8 * count
            guard tableEnd <= length else {
                throw TsukiError.format("section table (\(count) records) exceeds the file size \(length)")
            }

            let table = ByteSpan(try files.readRange(path, offset: 0, count: tableEnd))
            return (try MzpContainer.readTable(table, totalLength: length), length)
        }

        // MARK: - scripts (allscr.mrg section 0)

        func checkScripts() throws {
            let id = "data.scripts"
            let path = "image/allscr.mrg"
            if !files.exists(path) { return }

            do {
                let (sections, _) = try readSections(path)
                guard !sections.isEmpty else {
                    throw TsukiError.format("allscr.mrg has no sections")
                }

                let section = sections[0]
                let names = try NamTable.parseNam32(
                    ByteSpan(try files.readRange(path, offset: section.offset, count: section.size)))
                counts.scripts = names.count
                countCheck(id, "scripts (names in allscr.mrg section 0)", AnalysedBuild.scripts, names.count, "script name count")
                if sections.count - 3 != names.count {
                    fail(id + ".aligned", "script sections match the names", .layoutInvalid,
                         buildNumber(names.count), buildNumber(sections.count - 3),
                         "allscr.mrg has \(sections.count) sections for \(names.count) script names; script k should be section k + 3.")
                } else {
                    pass(id + ".aligned", "script sections match the names", "sections - 3 = names", "sections - 3 = names")
                }
            } catch {
                if BuildCheck.isIOError(error) { throw error }
                fail(id, "scripts (names in allscr.mrg section 0)", .layoutInvalid, "549 NAM32 names", "\(error)",
                     "allscr.mrg section 0 is not the script name table: \(error)")
            }
        }

        // MARK: - script_text.mrg (text.md 2)

        func checkText() throws {
            let path = "image/script_text.mrg"
            if !files.exists(path) { return }

            do {
                let (sections, _) = try readSections(path)
                if sections.count != 2 * AnalysedBuild.textLanguages.count {
                    return // the section count check already failed
                }

                for k in 0..<AnalysedBuild.textLanguages.count {
                    let language = AnalysedBuild.textLanguages[k]
                    let id = "data.text." + language
                    let table = sections[2 * k]
                    let blob = sections[2 * k + 1]
                    let raw = ByteSpan(try files.readRange(path, offset: table.offset, count: table.size))
                    let entries = raw.count / 4
                    var end = -1
                    for i in 0..<entries where raw.u32be(i * 4) == 0xFFFF_FFFF {
                        end = i
                        break
                    }

                    if raw.count % 4 != 0 || end < 2 {
                        fail(id, "text lines " + language, .layoutInvalid, "offset table with an end mark", "no end mark",
                             "script_text.mrg section \(2 * k) is not a big-endian offset table with a 0xFFFFFFFF end mark.")
                        continue
                    }

                    let guard1 = raw.u32be((end - 2) * 4)
                    let guard2 = raw.u32be((end - 1) * 4)
                    if guard1 != UInt32(blob.size) || guard2 != UInt32(blob.size) {
                        fail(id, "text lines " + language, .layoutInvalid, buildNumber(blob.size),
                             "\(buildNumber(Int(guard1))), \(buildNumber(Int(guard2)))",
                             "script_text.mrg \(language): the offset table does not end with the blob size twice.")
                        continue
                    }

                    let lines = end - 2
                    counts.setTextLines(language, lines)
                    countCheck(id, "text lines " + language, AnalysedBuild.textLines, lines, "text line count (\(language))")
                }
            } catch {
                if BuildCheck.isIOError(error) { throw error }
                fail("data.text", "script_text.mrg tables", .layoutInvalid, "valid", "\(error)",
                     "script_text.mrg is not a valid container: \(error)")
            }
        }

        // MARK: - vse names (se_nam.mrg section 2)

        func checkVseNames() throws {
            let path = "image/se_nam.mrg"
            if !files.exists(path) { return }

            do {
                let (sections, _) = try readSections(path)
                if sections.count < 3 { return }

                let section = sections[2]
                let names = try NamTable.parseNam32(
                    ByteSpan(try files.readRange(path, offset: section.offset, count: section.size)))
                counts.vseNames = names.count
                countCheck("data.vse.names", "vse names (se_nam.mrg section 2)", AnalysedBuild.vseNames, names.count,
                           "vse name count")
            } catch {
                if BuildCheck.isIOError(error) { throw error }
                fail("data.vse.names", "vse names (se_nam.mrg section 2)", .layoutInvalid, "NAM32", "\(error)",
                     "se_nam.mrg section 2 is not a NAM32 table: \(error)")
            }
        }

        // MARK: - movies

        func checkMovies() {
            let movies = files.listFiles(in: "image/movie")
            let mp4 = movies.filter { $0.lowercased().hasSuffix(".mp4") }.count
            counts.movieFiles = mp4
            if mp4 == 0 && movies.isEmpty {
                fail("data.movies", "movie files (image/movie/*.mp4)", .fileMissing, buildNumber(AnalysedBuild.movieFiles), "0",
                     "The folder image\\movie is missing or empty; the movies cannot play.")
                return
            }

            countCheck("data.movies", "movie files (image/movie/*.mp4)", AnalysedBuild.movieFiles, mp4, "movie file count")
        }

        // MARK: - totals

        func checkTotals() {
            if counts.tripletEntries.count == AnalysedBuild.triplets.count {
                countCheck("data.triplets.total", "triplet entries over 12 archives",
                           AnalysedBuild.tripletEntryTotal, counts.tripletTotal, "triplet entry total")
            }

            if counts.standaloneSections.count == AnalysedBuild.standalone.count {
                countCheck("data.standalone.total", "standalone sections over 8 files",
                           AnalysedBuild.standaloneSectionTotal, counts.standaloneTotal, "standalone section total")
            }
        }
    }

    // MARK: - helpers

    /// C# enum name of the record layout (`Hed8`), which the messages print.
    private static func formatName(_ format: HedFormat) -> String {
        format == .hed8 ? "Hed8" : "Hed4"
    }

    private static func isIOError(_ error: Error) -> Bool {
        guard let tsuki = error as? TsukiError, case .io = tsuki else { return false }
        return true
    }

    private static func contains(_ data: ByteSpan, _ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, data.count >= needle.count else { return needle.isEmpty }
        for offset in 0...(data.count - needle.count) where data.slice(offset, needle.count).elementsEqual(needle) {
            return true
        }
        return false
    }
}
