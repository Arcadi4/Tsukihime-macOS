import Foundation
import TsukiCore
import TsukiEngine
import TsukiData

enum GlyphCensus {
    private static let firstSlot = FontArchive.firstSlot

    static func run(
        source: GameFolderSource, ids: [Int], findings: inout [CensusFinding]
    ) -> [GlyphCensusLanguage] {
        guard let tables = try? source.tables.fontTables else { return [] }
        var results: [GlyphCensusLanguage] = []
        for lang in TextRules.selectableLanguages {
            results.append(runLanguage(source: source, tables: tables, lang: lang, ids: ids, findings: &findings))
        }
        return results
    }

    private static func runLanguage(
        source: GameFolderSource, tables: FontTables, lang: Language, ids: [Int], findings: inout [CensusFinding]
    ) -> GlyphCensusLanguage {
        let code = TextRules.code(lang)
        guard let table = try? source.text.table(lang) else {
            return GlyphCensusLanguage(language: code, lines: 0, distinctCharacters: 0, occurrences: 0, missing: [], pagesUsed: 0, outOfPage: 0)
        }
        let narrow = tables.lookup("narrow")
        let wide = tables.lookup(code + "_wide")

        var seen = Set<Int>(ids)
        var queue = ids
        var head = 0
        var chars: [UInt64: Int] = [:]

        while head < queue.count {
            let id = queue[head]
            head += 1
            guard let lineBytes = try? table.lineBytes(id) else { continue }
            let tokens = Markup.flatten(Markup.tokenize(lineBytes, lang))
            for token in tokens {
                switch token {
                case .text(let t):
                    countChars(t.text, chars: &chars)
                case .ref(let r):
                    if r.lineId >= 0 && r.lineId < table.count && seen.insert(r.lineId).inserted {
                        queue.append(r.lineId)
                    }
                default:
                    break
                }
            }
        }

        let glyphs = tables.for(lang)
        guard let font = try? source.fontFile(lang) else {
            return GlyphCensusLanguage(language: code, lines: seen.count, distinctCharacters: chars.count, occurrences: 0, missing: [], pagesUsed: 0, outOfPage: 0)
        }

        var pageSize: [Int: (w: Int, h: Int)] = [:]
        var missing: [(key: String, count: Int)] = []
        var pages = Set<Int>()
        var rects = Set<String>()
        var outOfPage = 0

        for key in chars.keys.sorted() {
            let count = chars[key]!
            let lookup = key >= 0x10000 ? wide : narrow
            if lookup.get(key) < 0 {
                let hex = String(format: "%06x", key)
                missing.append((hex, count))
                continue
            }

            let utf8 = utf8Of(key)
            guard let g = try? glyphs.charGlyph(ByteSpan(utf8), 0, 0, 0, 1.0) else {
                continue
            }
            let page = g.tex - firstSlot
            if g.consumed != utf8.count || page < 0 || page >= FontArchive.pageCount {
                findings.append(CensusFinding(check: "glyph", detail: "\(code) U+\(String(key, radix: 16)): glyph slot 0x\(String(g.tex, radix: 16)) is not a page of ft_\(code).mrg", allowedBecause: nil))
                continue
            }

            pages.insert(page)
            let rectKey = "\(g.tex),\(g.x),\(g.y),\(g.w),\(g.h)"
            if !rects.insert(rectKey).inserted {
                continue
            }

            let size: (w: Int, h: Int)
            if let cached = pageSize[page] {
                size = cached
            } else {
                if let data = try? font.readPageData(page) {
                    size = (data.width, data.height)
                } else {
                    size = (0, 0)
                }
                pageSize[page] = size
            }

            if g.x < 0 || g.y < 0 || g.w < 0 || g.x + g.w > size.w || g.y + g.h > size.h {
                outOfPage += 1
                findings.append(CensusFinding(check: "glyph", detail: "\(code) U+\(String(key, radix: 16)): rectangle \(g.x),\(g.y) \(g.w)x\(g.h) is outside page \(page) (\(size.w)x\(size.h))", allowedBecause: nil))
            }
        }

        for (key, count) in missing {
            let reason = CensusAllowList.glyphFallbackReason(language: code, key: key, uses: count)
            findings.append(CensusFinding(
                check: "glyph", detail: "\(code): no glyph lookup entry for U+\(key) (\(count) uses)", allowedBecause: reason))
        }

        let totalOccurrences = chars.values.reduce(Int64(0)) { $0 + Int64($1) }
        return GlyphCensusLanguage(language: code, lines: seen.count, distinctCharacters: chars.count, occurrences: totalOccurrences, missing: missing, pagesUsed: pages.count, outOfPage: outOfPage)
    }

    private static func countChars(_ utf8: [UInt8], chars: inout [UInt64: Int]) {
        var i = 0
        while i < utf8.count {
            let b0 = utf8[i]
            let n: Int
            if b0 < 0x80 { n = 1 }
            else if b0 >= 0xC0 && b0 < 0xE0 { n = 2 }
            else if b0 >= 0xE0 && b0 < 0xF0 { n = 3 }
            else if b0 >= 0xF0 && b0 < 0xF8 { n = 4 }
            else { n = 1 }

            let actual = min(n, utf8.count - i)
            var key: UInt64 = 0
            for j in 0..<actual {
                key = (key << 8) | UInt64(utf8[i + j])
            }
            chars[key] = (chars[key] ?? 0) + 1
            i += actual
        }
    }

    private static func utf8Of(_ key: UInt64) -> [UInt8] {
        let n: Int
        if key < 0x100 { n = 1 }
        else if key < 0x10000 { n = 2 }
        else if key < 0x1000000 { n = 3 }
        else { n = 4 }

        var bytes = [UInt8](repeating: 0, count: n)
        var k = key
        for j in (0..<n).reversed() {
            bytes[j] = UInt8(k & 0xFF)
            k >>= 8
        }
        return bytes
    }
}
