import Foundation
import TsukiCore
import TsukiEngine

/// The font-table probe of RR 3.3 item 2 (`EbootFontTables.verify()`, docs/formats/fonts.md 10.7): the code still loads every glyph
/// table from the expected address, the lookup arrays are sorted permutations, the tag names and wide-grid bases are the documented ones.
/// It is the eighth structural probe next to `EbootProbes` and is not run by `BuildCheck` yet.
public enum FontTableProbe {
    /// The id of the probe's `CheckResult`.
    public static let id = "eboot.probe.fonts"

    private static let title = "font tables: 16 lookup arrays (17,423 entries), 17 record arrays, tags, wide-grid bases"

    /// Runs the probe on the bytes of eboot.bin. Never throws for malformed content.
    public static func run(_ eboot: ByteSpan) -> CheckResult {
        do {
            let data = try EbootFontData.read(try EbootReader.parse(eboot))
            let issues = data.verify()
            let actual = issues.isEmpty
                ? "\(data.lookups.count) lookup arrays with \(grouped(data.lookupEntryCount)) entries"
                : "\(issues.count) problem(s)"
            if issues.isEmpty && data.lookupEntryCount == 17_423 {
                return CheckResult(id: id, title: title, status: .pass, failure: .none,
                                   expected: "no problems", actual: actual, message: "")
            }
            let detail = issues.isEmpty
                ? "the lookup arrays hold \(data.lookupEntryCount) entries, not 17,423"
                : issues.prefix(3).joined(separator: "; ")
            return fail(actual, detail)
        } catch {
            return fail("unreadable", "\(error)")
        }
    }

    private static func fail(_ actual: String, _ detail: String) -> CheckResult {
        CheckResult(id: id, title: title, status: .fail, failure: .ebootProbeFailed, expected: "no problems",
                    actual: actual, message: "\(title): \(detail). The font tables are not where the analysed build has them.")
    }

    /// `17,423`: the invariant thousands grouping of the probe's message.
    private static func grouped(_ value: Int) -> String {
        let digits = String(value)
        guard digits.count > 3 else { return digits }
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return out
    }
}
