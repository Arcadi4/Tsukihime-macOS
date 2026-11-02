import Foundation
import TsukiCore
import TsukiData

public enum ReferenceKind: String, Sendable, CaseIterable {
    case image
    case voice
    case se
    case bgm
    case movie
    case scene
    case label
    case text
    case motion
    case rule
}

public struct CensusReference: Sendable {
    public let kind: ReferenceKind
    public let script: Int
    public let offset: Int
    public let command: String
    public let key: String
    public let result: String
    public let resolved: Bool

    public init(kind: ReferenceKind, script: Int, offset: Int, command: String, key: String, result: String, resolved: Bool) {
        self.kind = kind
        self.script = script
        self.offset = offset
        self.command = command
        self.key = key
        self.result = result
        self.resolved = resolved
    }

    public var line: String {
        "\(kind.rawValue)\t\(script)\t\(offset)\t\(command)\t\(key)\t\(result)"
    }
}

public struct CensusFinding: Sendable {
    public let check: String
    public let detail: String
    public let allowedBecause: String?

    public init(check: String, detail: String, allowedBecause: String?) {
        self.check = check
        self.detail = detail
        self.allowedBecause = allowedBecause
    }

    public var allowed: Bool { allowedBecause != nil }
}

public struct CensusKindTotals: Sendable {
    public let kind: ReferenceKind
    public let references: Int
    public let distinct: Int
    public let resolved: Int
    public let allowed: Int
    public let unexpected: Int

    public init(kind: ReferenceKind, references: Int, distinct: Int, resolved: Int, allowed: Int, unexpected: Int) {
        self.kind = kind
        self.references = references
        self.distinct = distinct
        self.resolved = resolved
        self.allowed = allowed
        self.unexpected = unexpected
    }
}

public struct CensusCheck: Sendable {
    public let name: String
    public let checked: Int
    public let failed: Int

    public init(name: String, checked: Int, failed: Int) {
        self.name = name
        self.checked = checked
        self.failed = failed
    }
}

public struct GlyphCensusLanguage: Sendable {
    public let language: String
    public let lines: Int
    public let distinctCharacters: Int
    public let occurrences: Int64
    public let missing: [(key: String, count: Int)]
    public let pagesUsed: Int
    public let outOfPage: Int

    public init(language: String, lines: Int, distinctCharacters: Int, occurrences: Int64, missing: [(key: String, count: Int)], pagesUsed: Int, outOfPage: Int) {
        self.language = language
        self.lines = lines
        self.distinctCharacters = distinctCharacters
        self.occurrences = occurrences
        self.missing = missing
        self.pagesUsed = pagesUsed
        self.outOfPage = outOfPage
    }
}

public final class CensusReport: Sendable {
    public let scripts: Int
    public let statements: Int
    public let references: [CensusReference]
    public let totals: [CensusKindTotals]
    public let findings: [CensusFinding]
    public let checks: [CensusCheck]
    public let glyphs: [GlyphCensusLanguage]
    public let elapsed: Double

    public init(
        scripts: Int,
        statements: Int,
        references: [CensusReference],
        totals: [CensusKindTotals],
        findings: [CensusFinding],
        checks: [CensusCheck],
        glyphs: [GlyphCensusLanguage],
        elapsed: Double
    ) {
        self.scripts = scripts
        self.statements = statements
        self.references = references
        self.totals = totals
        self.findings = findings
        self.checks = checks
        self.glyphs = glyphs
        self.elapsed = elapsed
    }

    public var failures: [CensusFinding] {
        findings.filter { !$0.allowed }
    }

    public var isClean: Bool {
        failures.isEmpty
    }
}

public struct CensusOptions: Sendable {
    public var parallelism: Int = ProcessInfo.processInfo.activeProcessorCount
    public var checkTargets: Bool = true
    public var checkGlyphs: Bool = true
    public var decodeAudioSample: Int = 48
    public var decodePictureSample: Int = 48

    public init(parallelism: Int = ProcessInfo.processInfo.activeProcessorCount, checkTargets: Bool = true, checkGlyphs: Bool = true, decodeAudioSample: Int = 48, decodePictureSample: Int = 48) {
        self.parallelism = parallelism
        self.checkTargets = checkTargets
        self.checkGlyphs = checkGlyphs
        self.decodeAudioSample = decodeAudioSample
        self.decodePictureSample = decodePictureSample
    }
}
