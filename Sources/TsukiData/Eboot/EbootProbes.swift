import Foundation
import TsukiCore

/// The structural probes of RR 3.3 item 2 that the build check does not run itself: the SELF segment
/// table, the image catalog, the picture-name list, the movie table, the scene-id table and `ui_text`.
/// They are a self-test when the SHA-256 matches and a diagnosis when it does not, so a damaged or
/// foreign eboot.bin fails with a message instead of an exception.
public enum EbootProbes {
    /// Runs every probe on the bytes of eboot.bin. Never throws for malformed content.
    public static func run(_ eboot: ByteSpan) -> [CheckResult] {
        var results: [CheckResult] = []
        let reader: EbootReader
        do {
            reader = try EbootReader.parse(eboot)
        } catch {
            results.append(fail(
                "segments", "SELF segment table", "10 plain segments", "unreadable",
                "eboot.bin cannot be read as a PS4 SELF: \(describe(error))"))
            return results
        }

        probe(&results, "segments", "SELF segment table") { segments(reader.image) }
        probe(&results, "layout", "segment layout (text 0x2280, RELRO 0x32C210, data 0x365FA0)") {
            layout(reader.image)
        }
        probe(&results, "catalog", "image catalog: BLACK.mzp, BLUE.mzp, 14,744 records + 31 empty") {
            try catalog(reader, eboot)
        }
        probe(&results, "names", "picture-name list: BLACK first, 14,744 names + 1 empty, 0xFF") {
            try names(reader)
        }
        probe(&results, "movies", "movie table: titlebg1.mp4 first, 134 records, terminator -1") {
            try movies(reader)
        }
        probe(&results, "scenes", "scene-id table at text 0x216130 starts 110, 240, 260, 270") {
            try scenes(reader)
        }
        probe(&results, "uitext", "ui_text[ja][0] is \"NULL\"") { try uiTextFirst(reader) }
        probe(&results, "uitext.table", "ui_text: 5 x 1,499 pointers equal their relocations") {
            try uiTextAll(reader)
        }
        return results
    }

    private static func describe(_ error: Error) -> String {
        if let error = error as? TsukiError { return error.description }
        return String(describing: error)
    }

    private static func probe(
        _ results: inout [CheckResult], _ id: String, _ title: String,
        _ check: () throws -> (expected: String, actual: String, ok: Bool)
    ) {
        do {
            let outcome = try check()
            results.append(outcome.ok
                ? CheckResult(
                    id: "eboot.probe." + id, title: title, status: .pass, failure: .none,
                    expected: outcome.expected, actual: outcome.actual, message: "")
                : fail(
                    id, title, outcome.expected, outcome.actual,
                    "\(title): expected \(outcome.expected), found \(outcome.actual). The tables are not where the analysed build has them."))
        } catch {
            results.append(fail(id, title, "readable", "unreadable", "\(title): \(describe(error))"))
        }
    }

    private static func fail(
        _ id: String, _ title: String, _ expected: String, _ actual: String, _ message: String
    ) -> CheckResult {
        CheckResult(
            id: "eboot.probe." + id, title: title, status: .fail, failure: .ebootProbeFailed,
            expected: expected, actual: actual, message: message)
    }

    private static func n(_ value: Int) -> String {
        let digits = String(value)
        var text = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { text.append(",") }
            text.append(ch)
        }
        return text
    }

    private static func hex(_ value: Int) -> String {
        value < 0 ? "-1" : "0x" + String(value, radix: 16).uppercased()
    }

    private static func segments(_ selfImage: SelfImage) -> (expected: String, actual: String, ok: Bool) {
        let count = selfImage.selfSegments.count
        let plain = selfImage.selfSegments.allSatisfy { !($0.deflated || $0.encrypted) }
        return (
            "10 segments, all plain",
            "\(count) segments, \(plain ? "all plain" : "some deflated or encrypted")",
            count == 10 && plain)
    }

    private static func layout(_ selfImage: SelfImage) -> (expected: String, actual: String, ok: Bool) {
        let text = selfImage.text
        let relro = selfImage.relro
        let data = selfImage.dataSegment

        func describe(_ header: ProgramHeader?) -> String {
            guard let header else { return "missing" }
            let file = selfImage.phdrFileOffset(header).map(hex) ?? "-1"
            return "VA \(hex(Int(exactly: header.vAddr) ?? 0)) file \(file) size \(hex(Int(exactly: header.fileSize) ?? 0))"
        }

        let expected = "text VA 0x0 file 0x\(String(EbootAddresses.textFileOffset, radix: 16).uppercased()) "
            + "size 0x\(String(EbootAddresses.textSize, radix: 16).uppercased()); "
            + "RELRO VA 0x\(String(EbootAddresses.relroVa, radix: 16).uppercased()) "
            + "file 0x\(String(EbootAddresses.relroFileOffset, radix: 16).uppercased()) "
            + "size 0x\(String(EbootAddresses.relroSize, radix: 16).uppercased()); "
            + "data VA 0x\(String(EbootAddresses.dataVa, radix: 16).uppercased()) "
            + "file 0x\(String(EbootAddresses.dataFileOffset, radix: 16).uppercased()) "
            + "size 0x\(String(EbootAddresses.dataSize, radix: 16).uppercased())"
        let actual = "text \(describe(text)); RELRO \(describe(relro)); data \(describe(data))"
        let ok = text.vAddr == 0
            && selfImage.phdrFileOffset(text) == EbootAddresses.textFileOffset
            && text.fileSize == UInt64(EbootAddresses.textSize)
            && relro != nil && relro?.vAddr == UInt64(EbootAddresses.relroVa)
            && relro.flatMap { selfImage.phdrFileOffset($0) } == EbootAddresses.relroFileOffset
            && relro?.fileSize == UInt64(EbootAddresses.relroSize)
            && data.vAddr == UInt64(EbootAddresses.dataVa)
            && selfImage.phdrFileOffset(data) == EbootAddresses.dataFileOffset
            && data.fileSize == UInt64(EbootAddresses.dataSize)
        return (expected, actual, ok)
    }

    private static func catalog(_ reader: EbootReader, _ file: ByteSpan) throws -> (expected: String, actual: String, ok: Bool) {
        let catalog = try ImageCatalog.read(reader)
        guard catalog.count >= 2 else {
            throw TsukiError.format("the image catalog has \(catalog.count) records")
        }
        let (offset, used, empty) = try ImageCatalog.locate(file)
        let first = "\(catalog[0].name0), \(catalog[1].name0)"
        let namesOk = catalog[0].name0.caseInsensitiveCompare("BLACK.mzp") == .orderedSame
            && catalog[1].name0.caseInsensitiveCompare("BLUE.mzp") == .orderedSame
        let ok = namesOk && catalog.count == EbootAddresses.imageTableRecords && catalog.emptySlots == 31
            && offset == catalog.fileOffset && used == catalog.count && empty == catalog.emptySlots
        return (
            "BLACK.mzp, BLUE.mzp; 14,744 records + 31 empty; found by content at the same place",
            "\(first); \(n(catalog.count)) records + \(catalog.emptySlots) empty; by content: 0x\(String(offset, radix: 16).uppercased()), \(n(used)) + \(empty)",
            ok)
    }

    private static func names(_ reader: EbootReader) throws -> (expected: String, actual: String, ok: Bool) {
        let names = try PictureNameLists.read(reader)
        let end = try reader.read(EbootAddresses.imageNames + EbootAddresses.nameRecordSize * names.count, 1)[0]
        let lastName = names.last ?? ""
        let ok = names.count == PictureNameLists.records && names.first == "BLACK" && lastName.isEmpty && end == 0xFF
        return (
            "BLACK first, 14,745 records (14,744 names + 1 empty), then 0xFF",
            "\(names.first ?? "") first, \(n(names.count)) records, last \(lastName.isEmpty ? "empty" : "\"" + lastName + "\""), then 0x\(String(end, radix: 16).uppercased())",
            ok)
    }

    private static func movies(_ reader: EbootReader) throws -> (expected: String, actual: String, ok: Bool) {
        let movies = try MovieTable.read(reader)
        let terminator = try reader.i32(EbootAddresses.movieTerminator)
        guard let first = movies.first else {
            throw TsukiError.format("the movie table is empty")
        }
        let ok = movies.count == 134 && first.movieId == 0
            && first.path == "/app0/image/movie/titlebg1.mp4" && terminator == -1
        return (
            "134 records, record 0 id 0 /app0/image/movie/titlebg1.mp4, terminator -1 at 0xDCA590",
            "\(n(movies.count)) records, record 0 id \(first.movieId) \(first.path), terminator \(terminator)",
            ok)
    }

    private static func scenes(_ reader: EbootReader) throws -> (expected: String, actual: String, ok: Bool) {
        let ids = [
            try reader.i16(EbootAddresses.sceneIds),
            try reader.i16(EbootAddresses.sceneIds + 2),
            try reader.i16(EbootAddresses.sceneIds + 4),
            try reader.i16(EbootAddresses.sceneIds + 6),
        ]
        let expected: [Int16] = [110, 240, 260, 270]
        return (
            "110, 240, 260, 270",
            ids.map(String.init).joined(separator: ", "),
            ids == expected)
    }

    private static func uiTextFirst(_ reader: EbootReader) throws -> (expected: String, actual: String, ok: Bool) {
        let pointer = try reader.u64(EbootAddresses.uiText)
        let text = reader.cString(Int(truncatingIfNeeded: pointer), limit: 16)
        return ("\"NULL\"", "\"" + text + "\"", text == "NULL")
    }

    private static func uiTextAll(_ reader: EbootReader) throws -> (expected: String, actual: String, ok: Bool) {
        let table = try UiTextTable.read(reader)
        let count = UiTextTable.languages.count * UiTextTable.count
        var read = 0
        for language in 0..<UiTextTable.languages.count {
            read += table.rows(language).count
        }
        return ("\(n(count)) entries", "\(n(read)) entries", read == count)
    }
}
