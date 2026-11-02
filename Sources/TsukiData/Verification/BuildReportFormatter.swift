import TsukiCore
import TsukiEngine
import Foundation

/// Turns a `BuildReport` into the text `tsuki verify` prints (and a message box could show).
public enum BuildReportFormatter {
    /// Formats the report. `verbose` lists every check; otherwise passing checks are summarised.
    public static func format(_ report: BuildReport, verbose: Bool = false) -> String {
        var text = ""
        text += "Tsuki build check (RR 3.3)\n"
        text += "folder: \(report.source)\n"
        if let info = report.info {
            text += "eboot.bin: \(buildNumber(info.ebootSize)) bytes, SHA-256 \(info.ebootSHA256)\n"
        }

        if let identity = report.identity {
            text += "build: \(identity.describe())\n"
            text += "languages: \(identity.describeLanguages())\n"
        }

        if let located = report.locations {
            text += "tables: \(located.summary())\n"
            if verbose {
                text += located.report()
            }
        }

        text += "\n"

        if verbose {
            for check in report.checks {
                appendLine(&text, check)
            }
        } else {
            appendGroup(&text, report, title: "eboot.bin", idPrefix: "eboot.")
            for spec in AnalysedBuild.triplets {
                let detail = report.counts.tripletEntries[spec.name].map { "\(buildNumber($0)) entries" } ?? "unreadable"
                appendGroup(&text, report, title: "\(spec.name) (\(spec.format.rawValue))",
                            idPrefix: "data.\(spec.name).", detail: detail)
            }

            for spec in AnalysedBuild.standalone {
                let detail = report.counts.standaloneSections[spec.fileName].map { "\(buildNumber($0)) sections" } ?? "unreadable"
                appendGroup(&text, report, title: spec.fileName,
                            idPrefix: "data.\(spec.fileName).", detail: detail)
            }

            appendGroup(&text, report, title: "scripts", idPrefix: "data.scripts",
                        detail: "\(buildNumber(report.counts.scripts)) scripts")
            for language in AnalysedBuild.textLanguages {
                let detail = report.counts.textLines[language].map { "\(buildNumber($0)) lines" } ?? "unreadable"
                appendGroup(&text, report, title: "text \(language)",
                            idPrefix: "data.text.\(language)", detail: detail)
            }

            appendGroup(&text, report, title: "vse names", idPrefix: "data.vse.names",
                        detail: "\(buildNumber(report.counts.vseNames)) names")
            appendGroup(&text, report, title: "movies", idPrefix: "data.movies",
                        detail: "\(buildNumber(report.counts.movieFiles)) files")
            appendGroup(&text, report, title: "totals", idPrefix: "data.triplets.total",
                        detail: "\(buildNumber(report.counts.tripletTotal)) entries, \(buildNumber(report.counts.standaloneTotal)) sections")
        }

        text += "\n"
        text += "Counts (FORMATS 2)\n"
        text += "  triplet archives   " + field(String(report.counts.tripletEntries.count), 6)
            + "   entries  " + field(buildNumber(report.counts.tripletTotal), 7)
            + "   (analysed build: 12 archives, \(buildNumber(AnalysedBuild.tripletEntryTotal)) entries)\n"
        text += "  standalone files   " + field(String(report.counts.standaloneSections.count), 6)
            + "   sections " + field(buildNumber(report.counts.standaloneTotal), 7)
            + "   (analysed build: 8 files, \(buildNumber(AnalysedBuild.standaloneSectionTotal)) sections)\n"
        text += "  scripts            " + field(buildNumber(report.counts.scripts), 6) + "\n"
        text += "  text lines         "
            + AnalysedBuild.textLanguages.map { report.counts.textLines[$0].map { buildNumber($0) } ?? "?" }.joined(separator: " + ")
            + "   (analysed build: 5 x \(buildNumber(AnalysedBuild.textLines)))\n"
        text += "  voices             " + field(buildNumber(report.counts.voices), 6) + "\n"
        text += "  movies             " + field(buildNumber(report.counts.movieFiles), 6) + "\n"
        text += "\n"

        if report.accepted {
            text += "RESULT: ACCEPTED - this is the verified build; every eboot address and archive count of the documents applies.\n"
        } else if report.usable {
            text += "RESULT: USABLE - not the verified build (\(report.identity?.describe() ?? "identity unknown")); "
                + "the tables were located by content and the data is complete. Notes:\n"
            for note in report.notes where !note.message.isEmpty {
                text += "  - \(note.message)\n"
            }
        } else {
            text += "RESULT: REJECTED (\(report.primaryFailure)) - \(report.failures.count) check(s) failed:\n"
            for failure in report.failures {
                text += "  - \(failure.message)\n"
            }
        }

        return text
    }

    private static func appendLine(_ text: inout String, _ check: CheckResult) {
        switch check.status {
        case .pass: text += "  ok    "
        case .note: text += "  note  "
        case .fail: text += "  FAIL  "
        }
        text += "\(check.title): \(check.actual)"
        if !check.passed {
            text += "   (expected \(check.expected))"
        }
        text += "\n"
    }

    private static func appendGroup(_ text: inout String, _ report: BuildReport, title: String,
                                    idPrefix: String, detail: String? = nil) {
        let checks = report.checks.filter { $0.id.hasPrefix(idPrefix) }
        if checks.isEmpty {
            text += "  skip  \(title)\n"
            return
        }

        let ok = checks.allSatisfy { $0.status == .pass }
        let failed = checks.contains { !$0.passed && $0.failure != .ebootSizeMismatch && $0.failure != .ebootHashMismatch }
        text += (ok ? "  ok    " : (failed ? "  FAIL  " : "  note  "))
        text += title
        if let detail {
            text += ": \(detail)"
        }
        text += "\n"
    }

    /// C#'s `,width` alignment: pads to the minimum width, never truncates.
    private static func field(_ value: String, _ width: Int) -> String {
        value.count >= width ? value : String(repeating: " ", count: width - value.count) + value
    }
}
