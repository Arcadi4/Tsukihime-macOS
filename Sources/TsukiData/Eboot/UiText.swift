import TsukiCore
import TsukiEngine
import Foundation

/// One entry of the UI string table.
public struct UiString: Equatable, Sendable {
    /// Language code: `ja en zc zt ko`.
    public let lang: String
    /// String id; 0 is a placeholder.
    public let id: Int
    /// VA of the NUL-terminated UTF-8 string.
    public let va: Int
    /// The decoded string; `^` is the line-break marker of the text renderer.
    public let text: String

    public init(lang: String, id: Int, va: Int, text: String) {
        self.lang = lang
        self.id = id
        self.va = va
        self.text = text
    }
}

/// The system / menu string table of eboot.bin: `ui_text[5][1499]` at RELRO VA 0x41D5F0 (RR 3.2,
/// engine.md 9). Language index 0 ja, 1 en, 2 zc, 3 zt, 4 ko; ids 1..1498 are strings and id 0 is a
/// placeholder (`NULL`) in every language.
public struct UiTextTable: Sendable {
    /// Entries per language (0x5DB); valid ids are 1..1498.
    public static let count: Int = 1499

    /// The language codes in table order.
    public static let languages: [String] = ["ja", "en", "zc", "zt", "ko"]

    /// The 1,499 entries of every language, indexed by id.
    public let rows: [[UiString]]

    public init(rows: [[UiString]]) {
        self.rows = rows
    }

    /// The 1,499 entries of one language, indexed by id.
    public func rows(_ language: Int) -> [UiString] {
        rows[language]
    }

    /// Reads all 5 x 1,499 entries. Every pointer must equal the addend of its
    /// R_X86_64_RELATIVE relocation, and every string must be valid UTF-8.
    public static func read(_ reader: EbootReader) throws -> UiTextTable {
        let image = reader.image
        let tableVa = reader.layout.uiText
        let count = reader.layout.uiTextCount

        var relocations: [UInt64: Int64] = [:]
        for relocation in image.rela() where relocation.type == SelfImage.rX86Relative {
            relocations[relocation.offset] = relocation.addend
        }

        let langCount = languages.count
        let raw = ByteSpan(try image.readVa(tableVa, 8 * count * langCount))
        var rows: [[UiString]] = []
        rows.reserveCapacity(langCount)
        for li in 0..<langCount {
            var list: [UiString] = []
            list.reserveCapacity(count)
            for i in 0..<count {
                let index = li * count + i
                let slot = UInt64(tableVa + 8 * index)
                let pointer = raw.u64(8 * index)
                guard let addend = relocations[slot], UInt64(bitPattern: addend) == pointer else {
                    let relocation = relocations[slot].map { String($0) } ?? "None"
                    throw TsukiError.format(
                        "ui_text[\(languages[li])][\(i)] at 0x\(String(slot, radix: 16)): "
                            + "file value 0x\(String(pointer, radix: 16)), relocation \(relocation)")
                }

                let va = Int(truncatingIfNeeded: pointer)
                let bytes = image.cString(va, limit: 4096)
                guard let text = String(bytes: bytes, encoding: .utf8) else {
                    throw TsukiError.format(
                        "ui_text[\(languages[li])][\(i)] at 0x\(String(va, radix: 16)): not UTF-8")
                }

                list.append(UiString(lang: languages[li], id: i, va: va, text: text))
            }

            rows.append(list)
        }

        return UiTextTable(rows: rows)
    }

    /// `UiText_Get(id)` (text VA 0xC29B0): `nil` unless `1 <= id <= 0x5DA` and
    /// `language * 0x5DB + id <= 0x1D47` (an unsigned compare, so a negative language gives nil too).
    public func get(_ language: Int, _ id: Int) -> String? {
        guard id >= 1 && id <= 0x5DA else { return nil }
        let index = language * 0x5DB + id
        guard index >= 0 && index <= 0x1D47 else { return nil }
        guard language >= 0 && language < rows.count, id < rows[language].count else { return nil }
        return rows[language][id].text
    }

    /// Escapes a string for the TSV export of `python -m eboot.uitext`: backslash, TAB, LF and CR
    /// (none of the last three occur in v01.01).
    public static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    /// The file `ui_text_<lang>.tsv` of the Python tool: a header, then `id` TAB hex VA TAB text per
    /// line, LF endings.
    public func tsv(_ language: Int) -> String {
        var out = "id\tva\ttext\n"
        for entry in rows[language] {
            out += "\(entry.id)\t\(Self.hex8(entry.va))\t\(Self.escape(entry.text))\n"
        }
        return out
    }

    /// Lower-case hexadecimal, at least eight digits (`ToString("x8")`).
    private static func hex8(_ value: Int) -> String {
        let digits = String(value, radix: 16)
        return digits.count >= 8 ? digits : String(repeating: "0", count: 8 - digits.count) + digits
    }
}
