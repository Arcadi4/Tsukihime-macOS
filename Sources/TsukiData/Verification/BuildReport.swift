import Foundation
import TsukiCore
import TsukiEngine

/// Outcome of one check.
public enum CheckStatus: Sendable {
    /// The check passed.
    case pass
    /// The check failed; the copy is not the analysed build.
    case fail
    /// Not the verified build's value, but nothing is wrong with it (another build's eboot or data
    /// counts); the copy stays usable.
    case note
}

/// Why a check failed. Every kind has its own message, so a wrong eboot differs from a missing
/// archive.
public enum BuildFailure: Int, Sendable, Comparable, CustomStringConvertible {
    /// The check passed.
    case none = 0
    /// eboot.bin is not in the folder.
    case ebootMissing = 1
    /// eboot.bin has another size than the analysed build.
    case ebootSizeMismatch = 2
    /// eboot.bin has another SHA-256 than the analysed build (RR 3.3 item 1).
    case ebootHashMismatch = 3
    /// A structural probe of RR 3.3 item 2 failed.
    case ebootProbeFailed = 4
    /// A data file the runtime needs is missing (RR 3.1).
    case fileMissing = 5
    /// A data file is there but breaks its documented layout.
    case layoutInvalid = 6
    /// An entry, section, line or file count differs from FORMATS section 2 (RR 3.3 item 3).
    case countMismatch = 7

    public static func < (left: BuildFailure, right: BuildFailure) -> Bool {
        left.rawValue < right.rawValue
    }

    /// The C# enum name, which the text report prints.
    public var description: String {
        switch self {
        case .none: return "None"
        case .ebootMissing: return "EbootMissing"
        case .ebootSizeMismatch: return "EbootSizeMismatch"
        case .ebootHashMismatch: return "EbootHashMismatch"
        case .ebootProbeFailed: return "EbootProbeFailed"
        case .fileMissing: return "FileMissing"
        case .layoutInvalid: return "LayoutInvalid"
        case .countMismatch: return "CountMismatch"
        }
    }
}

/// One line of a `BuildReport`.
public struct CheckResult: Sendable {
    /// Stable identifier such as `eboot.sha256` or `data.allpac0.count`.
    public let id: String
    /// What was checked.
    public let title: String
    /// Pass, note or fail.
    public let status: CheckStatus
    /// The failure kind, `.none` on a pass.
    public let failure: BuildFailure
    /// The documented value.
    public let expected: String
    /// The value found.
    public let actual: String
    /// A sentence for the person who sees the failure; empty on a pass.
    public let message: String

    public init(id: String, title: String, status: CheckStatus, failure: BuildFailure,
                expected: String, actual: String, message: String) {
        self.id = id
        self.title = title
        self.status = status
        self.failure = failure
        self.expected = expected
        self.actual = actual
        self.message = message
    }

    /// True when the check did not fail (a note counts as passed).
    public var passed: Bool { status != .fail }
}

/// The counts the build check read (FORMATS section 2). A count is 0 when its file could not be read.
public final class BuildCounts {
    /// Entries per triplet archive, by archive name.
    public private(set) var tripletEntries: [String: Int] = [:]
    /// Sections per standalone file, by file name.
    public private(set) var standaloneSections: [String: Int] = [:]
    /// Scripts: names in allscr.mrg section 0.
    public var scripts = 0
    /// Text lines per language of script_text.mrg, in the order ja, en, zc, zt, ko.
    public private(set) var textLines: [String: Int] = [:]
    /// Names in se_nam.mrg section 2.
    public var vseNames = 0
    /// Movie files (`*.mp4`) in `image/movie`.
    public var movieFiles = 0

    public init() {}

    /// Entries over all triplet archives read.
    public var tripletTotal: Int { tripletEntries.values.reduce(0, +) }
    /// Sections over all standalone files read.
    public var standaloneTotal: Int { standaloneSections.values.reduce(0, +) }
    /// Entries of voice.hed.
    public var voices: Int { tripletEntries["voice"] ?? 0 }

    public func setTripletEntries(_ name: String, _ count: Int) { tripletEntries[name] = count }

    public func setStandaloneSections(_ name: String, _ count: Int) { standaloneSections[name] = count }

    public func setTextLines(_ language: String, _ count: Int) { textLines[language] = count }
}

/// The result of the build check (RR 3.3, ARCHITECTURE 4.1).
public struct BuildReport {
    /// What the dump is: nil when eboot.bin could not be read.
    public let identity: BuildIdentity?
    /// Where the eboot's tables were found by content; nil for the verified build or when eboot.bin
    /// could not be read.
    public let locations: LocateResult?
    /// The folder, or a description of the view that was checked.
    public let source: String
    /// Size and SHA-256 of eboot.bin, or nil when it could not be read.
    public let info: BuildInfo?
    /// Every check that ran, in order.
    public let checks: [CheckResult]
    /// The counts that were read.
    public let counts: BuildCounts

    public init(source: String, info: BuildInfo?, checks: [CheckResult], counts: BuildCounts,
                identity: BuildIdentity? = nil, locations: LocateResult? = nil) {
        self.source = source
        self.info = info
        self.checks = checks
        self.counts = counts
        self.identity = identity
        self.locations = locations
    }

    /// True when the game can be played from this copy: every check passed except, at most, the
    /// identity of the eboot (its size and hash are not the verified build's), and the tables were
    /// located by content. `accepted` stays the strict word: the verified build, complete.
    public var usable: Bool {
        info != nil && failures.allSatisfy { $0.failure == .ebootSizeMismatch || $0.failure == .ebootHashMismatch }
    }

    /// True when every check passed outright: the folder is the verified build, complete, and every
    /// address in the documents applies.
    public var accepted: Bool { checks.allSatisfy { $0.status == .pass } }

    /// The checks that are notes (another build's values).
    public var notes: [CheckResult] { checks.filter { $0.status == .note } }

    /// The checks that failed.
    public var failures: [CheckResult] { checks.filter { !$0.passed } }

    /// The first failure kind in the order eboot, files, layout, counts; `.none` when accepted.
    public var primaryFailure: BuildFailure { failures.map(\.failure).min() ?? .none }
}

/// Invariant thousands grouping, the way the check and its report print counts.
func buildNumber(_ value: Int) -> String {
    let negative = value < 0
    let digits = Array(String(value.magnitude))
    var text = ""
    text.reserveCapacity(digits.count + digits.count / 3 + 1)
    for (offset, digit) in digits.enumerated() {
        if offset > 0 && (digits.count - offset) % 3 == 0 { text.append(",") }
        text.append(digit)
    }
    return negative ? "-" + text : text
}
