import Foundation
import TsukiCore
import TsukiEngine

/// The markup tokenizer of the engine's layout pass 2 (VA 0xC76C0 ff., docs/formats/text.md 6),
/// plain-text rendering, the style state machine and the census.
///
/// It works on the UTF-8 *bytes* of a line, as the engine does: one-byte parameters, byte-counted
/// windows (`@s` 256, `@X(...)` 255). Text that a parameter splits inside a multi-byte character is
/// kept as the undecodable bytes (the Python reference keeps them as surrogate escapes); it never
/// happens in the retail data.
public enum Markup {
    fileprivate static let iconTags: [[UInt8]] = TextRules.iconNames.map { Array(("[\($0)]").utf8) }

    /// Splits a line into tokens following the engine's layout pass 2. Ruby `<base|ruby>` is parsed
    /// unless the language is English. With `script` the string is a `_ZM/_ZD/_MSAD` message
    /// argument: a `$` followed by six digits becomes a `RefToken`, and `@e` / `@n` end the message
    /// (later text is returned as one final text token after that code; the engine discards it).
    public static func tokenize(_ line: ByteSpan, _ language: Language, script: Bool = false) -> [MarkupToken] {
        MarkupScanner(line: line.toArray(), rubyOn: TextRules.rubyEnabled(language), script: script).run()
    }

    /// Tokenizes a string (its UTF-8 bytes).
    public static func tokenize(_ line: String, _ language: Language, script: Bool = false) -> [MarkupToken] {
        tokenize(ByteSpan(Array(line.utf8)), language, script: script)
    }

    /// All tokens, descending into ruby groups (the group first, then its parts).
    public static func flatten(_ tokens: [MarkupToken]) -> [MarkupToken] {
        var result: [MarkupToken] = []
        for token in tokens {
            result.append(token)
            if case .ruby(let ruby) = token {
                result.append(contentsOf: flatten(ruby.baseTokens))
                result.append(contentsOf: flatten(ruby.readingTokens))
            }
        }
        return result
    }

    /// Readable text as UTF-8 bytes: `^` becomes a line feed, codes are removed, ruby is rendered as
    /// asked, icons keep their `[name]` unless `icons` is false, and references keep their source.
    public static func plainText(_ tokens: [MarkupToken], ruby: RubyRendering = .drop,
                                 icons: Bool = true) -> [UInt8] {
        var parts: [UInt8] = []
        for token in tokens {
            switch token {
            case .text(let text):
                parts.append(contentsOf: text.text)
            case .ruby(let group):
                switch ruby {
                case .drop:
                    parts.append(contentsOf: group.base)
                case .paren:
                    parts.append(contentsOf: group.base)
                    parts.append(0x28)
                    parts.append(contentsOf: group.reading)
                    parts.append(0x29)
                case .markup:
                    parts.append(contentsOf: group.raw)
                }
            case .newline:
                parts.append(0x0A)
            case .icon(let icon):
                if icons { parts.append(contentsOf: icon.raw) }
            case .ref(let reference):
                parts.append(contentsOf: reference.raw)
            case .code:
                break
            }
        }
        return parts
    }

    /// Tokenizes `line` and renders it.
    public static func plainText(_ line: ByteSpan, _ language: Language, ruby: RubyRendering = .drop,
                                 icons: Bool = true) -> [UInt8] {
        plainText(tokenize(line, language), ruby: ruby, icons: icons)
    }

    /// The glyph flag word the layout writes for a style (VA 0xC790C..0xC7B39).
    public static func glyphFlags(_ style: MarkupStyle, ligaturePiece: Bool = false) -> Int {
        var flags = 1 | (style.style == 1 ? 4 : 0)
        switch style.style {
        case 2: flags |= 0x10_0000
        case 3: flags |= 0x20_0000
        case 4: flags |= 0x40_0000
        case 5: flags |= 0x60_0000
        default: break
        }
        if style.anim != 0 && !ligaturePiece { flags |= 8 }
        if style.flagB { flags |= 0x1_0000 }
        return flags
    }

    /// Applies the control codes and returns runs that carry their style. `seq` approximates the
    /// engine's per-glyph typewriter counter (starts at 1, +1 per code point; ruby glyphs are not
    /// counted; `@t` sets it to 0). Codes inside a ruby group take effect after the group's run.
    public static func toRuns(_ tokens: [MarkupToken], _ language: Language) -> [MarkupRun] {
        _ = TextRules.code(language)
        var machine = RunMachine(english: language == .en)
        for token in tokens {
            machine.add(token)
        }
        return machine.runs
    }

    /// Counts every markup construct in `lines` (line id = position): key to (count, lines, first
    /// ids). Tokens inside ruby groups are counted too, with the key prefixed by `in ruby: `. Keys
    /// are decoded as UTF-8 (invalid bytes become U+FFFD); sort them for the reference's ordinal order.
    public static func census(_ lines: [ByteSpan], _ language: Language) -> [String: CensusEntry] {
        var stats: [String: CensusEntry] = [:]
        var id = 0
        for line in lines {
            visit(tokenize(line, language), id, "", &stats)
            id += 1
        }
        return stats
    }

    /// Number of Python `str` characters of UTF-8 bytes decoded with `surrogateescape`: one per scalar
    /// value, one per undecodable byte.
    public static func countCodePoints(_ utf8: ByteSpan) -> Int {
        var count = 0
        var i = 0
        while i < utf8.count {
            let length = scalarLength(utf8, i)
            i += length > 1 ? length : 1
            count += 1
        }
        return count
    }

    /// One census entry.
    public struct CensusEntry: Equatable {
        /// Occurrences.
        public var count = 0
        /// Lines that contain it.
        public var lines = 0
        /// The first five line ids.
        public var firstIds: [Int] = []
        var lastLine = -1

        public init() {}
    }

    private static func add(_ stats: inout [String: CensusEntry], _ key: String, _ id: Int) {
        var entry = stats[key] ?? CensusEntry()
        entry.count += 1
        if entry.lastLine != id {
            entry.lines += 1
            if entry.firstIds.count < 5 { entry.firstIds.append(id) }
            entry.lastLine = id
        }
        stats[key] = entry
    }

    private static func visit(_ tokens: [MarkupToken], _ id: Int, _ prefix: String,
                              _ stats: inout [String: CensusEntry]) {
        for token in tokens {
            switch token {
            case .ruby(let ruby):
                add(&stats, prefix + "ruby <base|ruby>", id)
                if !ruby.closed { add(&stats, prefix + "ruby group not closed", id) }
                visit(ruby.baseTokens, id, "in ruby: ", &stats)
                visit(ruby.readingTokens, id, "in ruby: ", &stats)
            case .newline:
                add(&stats, prefix + "^ (newline)", id)
            case .icon(let icon):
                add(&stats, prefix + "[\(icon.name)] (icon \(icon.index))", id)
            case .code(let code):
                let letter = String(decoding: code.code, as: UTF8.self)
                let arg = code.arg.map { String(decoding: $0, as: UTF8.self) } ?? ""
                let key = letter != ">" ? "@\(letter)\(arg)" : "> (stray, swallowed)"
                add(&stats, prefix + key, id)
            case .text(let text):
                for byte in text.text where isLiteral(byte) {
                    add(&stats, prefix + "literal '\(Character(UnicodeScalar(byte)))'", id)
                }
            case .ref:
                break
            }
        }
    }

    private static func isLiteral(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x3C, 0x3E, 0x7C, 0x5B, 0x5D, 0x40, 0x5E, 0x24, 0x25: return true
        default: return false
        }
    }

    /// The length of the valid UTF-8 scalar at `i`, or 1 when the bytes there are not a valid
    /// scalar (the reference counts each undecodable byte separately).
    private static func scalarLength(_ bytes: ByteSpan, _ i: Int) -> Int {
        let first = bytes[i]
        if first < 0x80 { return 1 }
        let n = bytes.count
        let continuation: (Int) -> Bool = { $0 < n && bytes[$0] & 0xC0 == 0x80 }

        if first & 0xE0 == 0xC0 {
            guard first >= 0xC2, continuation(i + 1) else { return 1 }
            return 2
        }
        if first & 0xF0 == 0xE0 {
            guard continuation(i + 1), continuation(i + 2) else { return 1 }
            let second = bytes[i + 1]
            if first == 0xE0 { guard second >= 0xA0 else { return 1 } }
            if first == 0xED { guard second <= 0x9F else { return 1 } }
            return 3
        }
        if first & 0xF8 == 0xF0 {
            guard first <= 0xF4, continuation(i + 1), continuation(i + 2), continuation(i + 3) else { return 1 }
            let second = bytes[i + 1]
            if first == 0xF0 { guard second >= 0x90 else { return 1 } }
            if first == 0xF4 { guard second <= 0x8F else { return 1 } }
            return 4
        }
        return 1
    }
}

/// The tokenizer state of one line.
private final class MarkupScanner {
    private let b: [UInt8]
    private let n: Int
    private let rubyOn: Bool
    private let script: Bool
    private var out: [MarkupToken] = []
    private var buf: [UInt8] = []
    private var base: [MarkupToken] = []
    private var ruby: [MarkupToken] = []
    private var state = 0
    private var groupStart = 0

    init(line: [UInt8], rubyOn: Bool, script: Bool) {
        b = line
        n = line.count
        self.rubyOn = rubyOn
        self.script = script
    }

    func run() -> [MarkupToken] {
        var i = 0
        while i < n {
            let plainEnd = plainEnd(i)
            if plainEnd > i {
                buf.append(contentsOf: b[i..<plainEnd])
                i = plainEnd
                continue
            }

            let c = b[i]
            if c == 0 {
                break
            }

            if script && c == 0x24 && i + 7 <= n && allDigits(i + 1, 6) {
                var id = 0
                for k in 1...6 {
                    id = (id * 10) + Int(b[i + k]) - 0x30
                }
                emit(.ref(RefToken(lineId: id, raw: slice(i, i + 7))))
                i += 7
                continue
            }

            if c == 0x40 {
                if i + 1 >= n {
                    // Engine: '@' + NUL goes to the default handler, which skips 2 bytes and reads past
                    // the end; stop here.
                    emit(.code(CodeToken(code: [], arg: nil, raw: [0x40])))
                    break
                }
                if !scanCode(&i) {
                    break
                }
                continue
            }

            if c == 0x5E {
                emit(.newline)
                i += 1
                continue
            }

            if c == 0x5B {
                let icon = matchIcon(i)
                if icon >= 0 {
                    emit(.icon(IconToken(name: TextRules.iconNames[icon], index: icon,
                                         raw: Markup.iconTags[icon])))
                    i += Markup.iconTags[icon].count
                    continue
                }
            }

            if rubyOn && c == 0x3C {
                if state != 0 {
                    closeGroup(i, closed: false)
                } else {
                    flush()
                }
                state = 1
                groupStart = i
                i += 1
                continue
            }

            if rubyOn && c == 0x7C && state != 0 {
                if state == 1 {
                    flush()
                    state = 2
                }
                i += 1
                continue
            }

            if rubyOn && c == 0x3E {
                if state != 0 {
                    closeGroup(i + 1, closed: true)
                } else {
                    emit(.code(CodeToken(code: [0x3E], arg: nil, raw: [0x3E])))
                }
                i += 1
                continue
            }

            buf.append(c)
            i += 1
        }

        if state != 0 {
            closeGroup(n, closed: false)
        }
        flush()
        return out
    }

    /// Scans the `@` code at `i` (a following byte exists); false ends the scan (script mode `@e` / `@n`).
    private func scanCode(_ i: inout Int) -> Bool {
        let k = b[i + 1]
        var j = i + 2
        var arg: [UInt8]?

        switch k {
        case 0x61, 0x63, 0x66, 0x68, 0x77: // a c f h w
            arg = slice(j, j + 1)
            j += 1
        case 0x73: // s
            var kk = j
            while kk < n && kk - j < 256 && b[kk] != 0x2C && b[kk] != 0x29 && b[kk] != 0 {
                kk += 1
            }
            arg = slice(j, kk)
            j = kk < n && kk - j < 256 ? kk + 1 : kk
        case 0x78, 0x79: // x y
            var kk = j
            while kk < n && kk - j < 3 && b[kk] >= 0x30 && b[kk] <= 0x39 {
                kk += 1
            }
            let digits = slice(j, kk)
            arg = digits.isEmpty ? nil : digits
            j = kk
        case 0x31, 0x32: // 1 2
            emit(.code(CodeToken(code: [k], arg: nil, raw: slice(i, i + 2))))
            if j < n {
                targetAppend(.text(TextToken(text: [k == 0x31 ? 0x5E : 0x29], raw: slice(j, j + 1))))
            }
            i = j + 1
            return true
        case 0x62, 0x67, 0x69, 0x6B, 0x6C, 0x6F, 0x70, 0x72, 0x74, 0x75, 0x7A, 0x54:
            break // b g i k l o p r t u z T: no parameter
        default:
            if j < n && b[j] == 0x28 {
                var close = -1
                let limit = min(n, j + 1 + 255)
                if limit > j + 1 {
                    for p in (j + 1)..<limit {
                        if b[p] == 0 { break }
                        if b[p] == 0x29 { close = p; break }
                    }
                }
                if close != -1 {
                    arg = slice(j, close + 1)
                    j = close + 1
                }
            }
        }

        emit(.code(CodeToken(code: [k], arg: arg, raw: slice(i, j))))
        i = j
        if script && (k == 0x65 || k == 0x6E) { // e n
            if state != 0 {
                closeGroup(i, closed: false)
            }
            if i < n {
                out.append(.text(TextToken(slice(i, n))))
            }
            return false
        }
        return true
    }

    private func slice(_ from: Int, _ to: Int) -> [UInt8] {
        let end = min(to, n)
        let start = min(from, end)
        return Array(b[start..<end])
    }

    private func allDigits(_ from: Int, _ count: Int) -> Bool {
        for k in 0..<count where b[from + k] < 0x30 || b[from + k] > 0x39 {
            return false
        }
        return true
    }

    private func plainEnd(_ from: Int) -> Int {
        var p = from
        while p < n && b[p] != 0 && b[p] != 0x24 && b[p] != 0x40 && b[p] != 0x5E && b[p] != 0x5B
            && b[p] != 0x3C && b[p] != 0x7C && b[p] != 0x3E {
            p += 1
        }
        return p
    }

    private func matchIcon(_ at: Int) -> Int {
        for (index, tag) in Markup.iconTags.enumerated() where at + tag.count <= n {
            if b[at..<(at + tag.count)].elementsEqual(tag) { return index }
        }
        return -1
    }

    private func targetAppend(_ token: MarkupToken) {
        switch state {
        case 0: out.append(token)
        case 1: base.append(token)
        default: ruby.append(token)
        }
    }

    private func flush() {
        guard !buf.isEmpty else { return }
        let text = buf
        buf.removeAll(keepingCapacity: true)
        switch state {
        case 0: mergeText(into: &out, text)
        case 1: mergeText(into: &base, text)
        default: mergeText(into: &ruby, text)
        }
    }

    private func mergeText(into tokens: inout [MarkupToken], _ text: [UInt8]) {
        if case .text(let previous)? = tokens.last {
            tokens.removeLast()
            tokens.append(.text(TextToken(text: previous.text + text, raw: previous.raw + text)))
        } else {
            tokens.append(.text(TextToken(text)))
        }
    }

    private func emit(_ token: MarkupToken) {
        flush()
        targetAppend(token)
    }

    private func closeGroup(_ end: Int, closed: Bool) {
        flush()
        out.append(.ruby(RubyToken(base: joinText(base), reading: joinText(ruby), raw: slice(groupStart, end),
                                   baseTokens: base, readingTokens: ruby, closed: closed)))
        base.removeAll(keepingCapacity: true)
        ruby.removeAll(keepingCapacity: true)
        state = 0
    }

    private func joinText(_ tokens: [MarkupToken]) -> [UInt8] {
        var joined: [UInt8] = []
        for token in tokens {
            if case .text(let text) = token {
                joined.append(contentsOf: text.text)
            }
        }
        return joined
    }
}

/// The style state machine of `toRuns`.
private struct RunMachine {
    private var style = MarkupStyle()
    private var seq = 1
    private var saved = 1
    private let english: Bool
    private(set) var runs: [MarkupRun] = []

    init(english: Bool) {
        self.english = english
    }

    mutating func add(_ token: MarkupToken) {
        switch token {
        case .text(let text):
            runs.append(MarkupRun(kind: "text", text: text.text, ruby: [], style: style, value: nil, seq: seq))
            seq += Markup.countCodePoints(ByteSpan(text.text))
        case .ruby(let ruby):
            runs.append(MarkupRun(kind: "ruby", text: ruby.base, ruby: ruby.reading, style: style, value: nil, seq: seq))
            // Python: len(t.base), where base joins the text of the tokens of the base part. Codes
            // do not advance the sequence; only the base's own text tokens do.
            for inner in ruby.baseTokens {
                if case .text(let text) = inner {
                    seq += Markup.countCodePoints(ByteSpan(text.text))
                }
            }
            for inner in Markup.flatten(ruby.baseTokens + ruby.readingTokens) {
                if case .code(let code) = inner {
                    apply(code)
                }
            }
        case .icon(let icon):
            runs.append(MarkupRun(kind: "icon", text: Array(icon.name.utf8), ruby: [], style: style,
                                  value: icon.index, seq: seq))
            seq += 1
        case .newline:
            runs.append(MarkupRun(kind: "newline", text: [], ruby: [], style: style, value: nil, seq: seq))
        case .ref(let reference):
            runs.append(MarkupRun(kind: "ref", text: reference.raw, ruby: [], style: style,
                                  value: reference.lineId, seq: seq))
        case .code(let code):
            apply(code)
        }
    }

    private mutating func apply(_ token: CodeToken) {
        // The code as Python sees it: a one-byte ASCII code is that letter, the empty code (a lone
        // '@') is "", and a lone high byte matches nothing. Python's `c in "xy"` is true for "".
        let code: String
        if token.code.isEmpty {
            code = ""
        } else if token.code.count == 1 && token.code[0] < 0x80 {
            code = String(UnicodeScalar(token.code[0]))
        } else {
            code = "(non-ascii)"
        }
        let digit: Int? = {
            guard let arg = token.arg, arg.count == 1, arg[0] < 0x80 else { return nil }
            return Int(arg[0]) - 0x30
        }()

        if code == "c", let value = digit {
            let d = value & 0xFF
            if d == 0 {
                style.color = nil
                style.colorExt = 0
            } else if d <= 5 {
                style.color = TextRules.colorRgb565[d]
            } else if d <= 9 {
                style.colorExt = d
            }
        } else if code == "g" {
            style.style = 1
        } else if code == "z" {
            style.style = 2
        } else if code == "i" {
            style.style = english
                ? (style.style == 1 ? 4 : style.style == 2 ? 5 : 3)
                : 1
        } else if code == "b" {
            style.flagB = true
        } else if code == "a", let d = digit {
            style.anim = d
        } else if code == "r" {
            style.style = style.style == 4 ? 1 : style.style == 5 ? 2 : 0
            style.color = nil
            style.colorExt = 0
            style.flagB = false
            style.anim = 0
            style.scaleW = nil
            style.scaleH = nil
        } else if code == "o" {
            style.noWrap = true
        } else if code == "p" {
            style.noWrap = false
        } else if code == "h", let d = digit, d >= 0, d < TextRules.scaleTable.count {
            style.scaleH = TextRules.scaleTable[d]
        } else if code == "w", let d = digit, d >= 0, d < TextRules.scaleTable.count {
            style.scaleW = TextRules.scaleTable[d]
        } else if code == "f", let d = digit {
            style.fontMetric = d
        } else if code == "s", let arg = token.arg {
            let value = Self.parseScale(arg)
            style.scaleW = value
            style.scaleH = value
        } else if code == "t" {
            seq = 0
            runs.append(MarkupRun(kind: "seq", text: [0x74], ruby: [], style: style, value: 0, seq: seq))
        } else if code == "u" {
            saved = seq
            runs.append(MarkupRun(kind: "seq", text: [0x75], ruby: [], style: style, value: seq, seq: seq))
        } else if code == "l" {
            seq = saved
            runs.append(MarkupRun(kind: "seq", text: [0x6C], ruby: [], style: style, value: seq, seq: seq))
        } else if code == "k" {
            runs.append(MarkupRun(kind: "wait", text: [0x6B], ruby: [], style: style, value: nil, seq: seq))
        } else if code == "x" || code == "y" || code.isEmpty {
            let value = token.arg.flatMap { $0.isEmpty ? nil : Int(String(decoding: $0, as: UTF8.self)) }
            runs.append(MarkupRun(kind: "pos", text: Array(code.utf8), ruby: [], style: style,
                                  value: value, seq: seq))
        }
    }

    /// `@s`: the digits of the parameter (all other bytes are skipped) over 64, negated when it holds
    /// a minus sign.
    private static func parseScale(_ arg: [UInt8]) -> Double {
        var digits = ""
        var negative = false
        for byte in arg {
            if byte >= 0x30 && byte <= 0x39 {
                digits.append(Character(UnicodeScalar(byte)))
            } else if byte == 0x2D {
                negative = true
            }
        }
        let magnitude = digits.isEmpty ? 0.0 : (Double(digits) ?? 0.0)
        let signed = negative && magnitude != 0.0 ? -magnitude : magnitude
        return signed / 64.0
    }
}
