import Foundation
import TsukiCore
import TsukiEngine

/// `script_text.mrg`: an mrgd00 container with 10 sections, an offset table and a string blob for
/// each of ja, en, zc, zt and ko (docs/formats/text.md 2). The five offset tables (176 KB each) are
/// read when the file is opened and checked to agree on the line count; a language's blob (0.2 ..
/// 3.4 MB) is read on first use, so a running game holds only the current language pair.
public final class ScriptText {
    /// The archive this type opens by default.
    public static let defaultPath = "image/script_text.mrg"

    private let tables: [TextTable]
    private let containerIssues: () throws -> [String]

    /// Lines per language (43,969 in the retail data); all five languages have the same number.
    public let count: Int

    /// Number of 0xFFFFFFFF end marks of each language's offset table (1 in the retail data), by
    /// language index.
    public let endMarks: [Int]

    private init(tables: [TextTable], endMarks: [Int], containerIssues: @escaping () throws -> [String]) {
        self.tables = tables
        self.endMarks = endMarks
        self.containerIssues = containerIssues
        self.count = tables[0].count
    }

    /// Opens `image/script_text.mrg` of a game folder view and reads the five offset tables.
    public static func open(_ files: GameFiles, path: String = defaultPath) throws -> ScriptText {
        let length = try files.length(of: path)
        let top = try files.readRange(path, offset: 0, count: min(length, 8))
        let head = ByteSpan(top)
        guard Mzp.isContainer(head) else {
            throw TsukiError.format("\(path): not an mrgd00 container")
        }

        let tableBytes = 8 + (8 * Int(head.u16(6)))
        let table = try files.readRange(path, offset: 0, count: min(length, tableBytes))
        let sections = try MzpContainer.readTable(ByteSpan(table), totalLength: length)
        try checkSectionCount(sections.count)
        return try create(
            readSection: { i in try files.readRange(path, offset: sections[i].offset, count: sections[i].size) },
            blob: { i in ByteSpan(try files.readRange(path, offset: sections[i].offset, count: sections[i].size)) },
            containerIssues: { try MzpContainer.parse(try files.readAll(path)).validate() }
        )
    }

    /// Opens a container that is already in memory.
    public static func fromMemory(_ file: ByteSpan) throws -> ScriptText {
        let container = try MzpContainer.parse(file)
        try checkSectionCount(container.count)
        return try create(
            readSection: { container.section($0).toArray() },
            blob: { container.section($0) },
            containerIssues: { container.validate() }
        )
    }

    /// The table of one language.
    public func table(_ language: Language) -> TextTable {
        tables[Int(language.rawValue)]
    }

    /// The raw line, CR LF included (text.md 2).
    public func raw(_ language: Language, _ id: Int) throws -> ByteSpan {
        try table(language).raw(id)
    }

    /// The line without its CR LF, markup intact, `$` references not expanded.
    public func lineBytes(_ language: Language, _ id: Int) throws -> ByteSpan {
        try table(language).lineBytes(id)
    }

    /// The line as the engine's copy routine yields it (VA 0x75F80).
    public func engineLine(_ language: Language, _ id: Int) throws -> ByteSpan {
        try table(language).engineLine(id)
    }

    /// The line without its CR LF as a string (strict UTF-8).
    public func line(_ language: Language, _ id: Int) throws -> String {
        try table(language).line(id)
    }

    /// Engine-exact `$NNNNNN` expansion (VA 0x76040) of a message in `language`; see
    /// `TextExpansion.expand(_:table:srcLen:expand:)`.
    public func expandBytes(_ message: ByteSpan, _ language: Language, srcLen: Int? = nil) throws -> [UInt8] {
        try TextExpansion.expand(message, table: table(language), srcLen: srcLen)
    }

    /// Every deviation from the retail layout, container and tables (empty for the retail file).
    /// Reads the whole file once more, and every blob.
    public func validate() throws -> [String] {
        var issues = try containerIssues()
        for table in tables {
            issues.append(contentsOf: try table.validate())
        }
        for i in 0..<endMarks.count where endMarks[i] != 1 {
            let language = Language(rawValue: UInt8(i))!
            issues.append("\(TextRules.code(language)): \(endMarks[i]) 0xFFFFFFFF end marks (retail has 1)")
        }
        return issues
    }

    private static func checkSectionCount(_ count: Int) throws {
        guard count == TextRules.sectionCount else {
            throw TsukiError.format("expected \(TextRules.sectionCount) sections, found \(count)")
        }
    }

    private static func create(
        readSection: (Int) throws -> [UInt8],
        blob: @escaping (Int) throws -> ByteSpan,
        containerIssues: @escaping () throws -> [String]
    ) throws -> ScriptText {
        var tables: [TextTable] = []
        var endMarks: [Int] = []
        tables.reserveCapacity(5)
        endMarks.reserveCapacity(5)
        for k in 0..<5 {
            let parsed = try TextTable.parseOffsets(ByteSpan(try readSection(2 * k)), strict: false)
            endMarks.append(parsed.endMarks)
            let language = Language(rawValue: UInt8(k))!
            tables.append(try TextTable(language: language, offsets: parsed.offsets,
                                        blobSource: TextBlob { try blob((2 * k) + 1) }))
        }

        let count = tables[0].count
        for k in 1..<5 where tables[k].count != count {
            let counts = tables.enumerated()
                .map { "\(TextRules.code(Language(rawValue: UInt8($0.offset))!)): \($0.element.count)" }
                .joined(separator: ", ")
            throw TsukiError.format("languages have different line counts: \(counts)")
        }

        return ScriptText(tables: tables, endMarks: endMarks, containerIssues: containerIssues)
    }
}
