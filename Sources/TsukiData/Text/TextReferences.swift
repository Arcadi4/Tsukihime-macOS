import Foundation
import TsukiCore
import TsukiEngine

/// A decoded script as text: its name (allscr section 0) and its statements as one string (UTF-8
/// decoded).
public struct ScriptSource: Equatable, Sendable {
    /// The script name.
    public let name: String
    /// The decoded script.
    public let text: String

    public init(name: String, text: String) {
        self.name = name
        self.text = text
    }
}

/// The four commands that carry message text (docs/formats/text.md 5.1).
public enum TextCommandOp: Sendable {
    /// `_ZM<5 hex>(message)`: shows a message.
    case zm
    /// `_ZD<5 hex>(message)`: a disabled message, never shown.
    case zd
    /// `_MSAD(message)`: adds text to the current message.
    case msad
    /// `_SELR(n,message[,locked])`: defines a choice.
    case selr
}

/// One text command of a script, found by a light scan of the statements (docs/formats/text.md 5).
public struct TextCommand: Equatable, Sendable {
    public let script: Int
    public let name: String
    public let pos: Int
    public let op: TextCommandOp
    public let label: String
    public let arg: String
    public let choice: Int?
    public let extra: [String]

    public init(script: Int, name: String, pos: Int, op: TextCommandOp, label: String, arg: String,
                choice: Int?, extra: [String]) {
        self.script = script
        self.name = name
        self.pos = pos
        self.op = op
        self.label = label
        self.arg = arg
        self.choice = choice
        self.extra = extra
    }

    /// The op as the reference writes it (`ZM`, `ZD`, `MSAD`, `SELR`).
    public var opName: String {
        switch op {
        case .zm: return "ZM"
        case .zd: return "ZD"
        case .msad: return "MSAD"
        case .selr: return "SELR"
        }
    }

    /// The part of the argument the engine keeps: `_ZM/_ZD/_MSAD` cut at the first `@e` / `@n` and at
    /// 0x300 bytes (copy loop at VA 0x92458..0x924B0); `_SELR` argument 1 as it is.
    public var message: String {
        if op == .selr { return arg }
        let cut = TextReferences.endIndex(arg)
        let message = cut.map { String(Array(arg)[0..<$0]) } ?? arg
        return TextReferences.truncateUtf8(message, TextRules.messageArgMax)
    }

    /// `e`, `n` or empty (the closing parenthesis); always empty for `_SELR`.
    public var endCode: String {
        guard op != .selr, let cut = TextReferences.endIndex(arg) else { return "" }
        let chars = Array(arg)
        return cut + 1 < chars.count ? String(chars[cut + 1]) : ""
    }

    /// The engine's end mode: 0 for `)`, 1 for `@n`, 2 for `@e`; nil for `_SELR`.
    public var endMode: Int? {
        guard op != .selr else { return nil }
        switch endCode {
        case "n": return 1
        case "e": return 2
        default: return 0
        }
    }

    /// False for `_ZD` (the marker dispatcher at VA 0x98479 never shows a disabled message).
    public var displayed: Bool { op != .zd }

    /// A `_SELR` whose third argument is 1: the choice the menu cursor skips (text.md 5.2; the
    /// meaning is a hypothesis).
    public var locked: Bool {
        op == .selr && extra.count > 0 && TextReferences.pyStrip(extra[0]) == "1"
    }

    /// The `$NNNNNN` ids in `message`.
    public var refs: [Int] { TextReferences.scanRefs(message) }

    /// The slot string the engine builds for menu position `slot` (`_SELR` only), as UTF-8.
    public func choiceSlot(_ slot: Int) throws -> [UInt8] {
        guard op == .selr else {
            throw TsukiError.state("not a _SELR command")
        }
        return TextRules.choiceSlotText(slot, message: ByteSpan(Array(message.utf8)))
    }
}

/// How the scripts reference `script_text` lines (docs/formats/text.md 5): the text commands, the
/// reference index, the message groups, the census and the classes of the unreferenced ids. The scan
/// is regex-level (statements split at `;`), exactly as the Python reference does it; the full
/// bytecode-level reading is the VM's.
public enum TextReferences {
    /// Lines that script 00_02 shows as pre-rendered images (allpac0 `IMGxxxx`) instead of text
    /// commands (text.md 5.7).
    public static let imageTextIds: [Int: String] = [
        12: "IMG2629", 13: "IMG2630", 14: "IMG2631", 15: "IMG2632", 16: "IMG2633",
        59: "IMG2634", 63: "IMG2635", 68: "IMG2636", 82: "IMG2459", 87: "IMG2460", 93: "IMG2461",
    ]

    /// The classes of an unreferenced id, in the order of the reference.
    public static let unreferencedClasses: [String] = [
        "choice-number", "image-text", "blank", "merged-fragment", "not-shown",
    ]

    /// Python's `str.strip()`: removes the characters `str.isspace()` accepts (including
    /// U+001C..U+001F, U+0085, U+00A0 and the ideographic space), which differ from Swift's
    /// whitespace set.
    public static func pyStrip(_ s: String) -> String {
        let scalars = Array(s.unicodeScalars)
        var a = 0
        var b = scalars.count
        while a < b && isPySpace(scalars[a]) { a += 1 }
        while b > a && isPySpace(scalars[b - 1]) { b -= 1 }
        var view = String.UnicodeScalarView()
        for i in a..<b { view.append(scalars[i]) }
        return String(view)
    }

    /// True for the characters Python's `str.isspace()` accepts.
    public static func isPySpace(_ scalar: Unicode.Scalar) -> Bool {
        let c = scalar.value
        return (c >= 0x09 && c <= 0x0D) || (c >= 0x1C && c <= 0x20) || c == 0x85 || c == 0xA0
            || c == 0x1680 || (c >= 0x2000 && c <= 0x200A) || c == 0x2028 || c == 0x2029
            || c == 0x202F || c == 0x205F || c == 0x3000
    }

    /// The ids of every `$` followed by six decimal digits (Unicode digits count, as in Python's
    /// `\d`), scanning without overlap.
    public static func scanRefs(_ s: String) -> [Int] {
        let scalars = Array(s.unicodeScalars)
        var ids: [Int] = []
        var i = 0
        while i < scalars.count {
            if scalars[i] == "$", let id = tryRef(scalars, i) {
                ids.append(id)
                i += 7
            } else {
                i += 1
            }
        }
        return ids
    }

    /// Replaces every `$` + six digits with `$N` (the argument shape of the census).
    public static func replaceRefs(_ s: String) -> String {
        let scalars = Array(s.unicodeScalars)
        var view = String.UnicodeScalarView()
        var i = 0
        while i < scalars.count {
            if scalars[i] == "$", tryRef(scalars, i) != nil {
                view.append("$")
                view.append("N")
                i += 7
            } else {
                view.append(scalars[i])
                i += 1
            }
        }
        return String(view)
    }

    /// The longest prefix of `s` whose UTF-8 form fits in `maxBytes` (Python's
    /// `raw[:n].decode("utf-8", "ignore")` for a valid string).
    public static func truncateUtf8(_ s: String, _ maxBytes: Int) -> String {
        var bytes = 0
        var view = String.UnicodeScalarView()
        for scalar in s.unicodeScalars {
            let size = String(scalar).utf8.count
            if bytes + size > maxBytes {
                break
            }
            bytes += size
            view.append(scalar)
        }
        return String(view)
    }

    /// Decodes every script of an archive as strict UTF-8 text.
    public static func loadScripts(_ allscr: AllscrArchive) throws -> [ScriptSource] {
        var list: [ScriptSource] = []
        list.reserveCapacity(allscr.count)
        for k in 0..<allscr.count {
            list.append(ScriptSource(name: allscr.names[k], text: try TextTable.strictUTF8(allscr.scriptBytes(k))))
        }
        return list
    }

    /// Every text command of every script, in script and statement order.
    public static func iterTextCommands(_ scripts: [ScriptSource]) -> [TextCommand] {
        var list: [TextCommand] = []
        for (k, script) in scripts.enumerated() {
            let statements = split(script.text, on: ";")
            for (pos, statement) in statements.enumerated() {
                guard let parsed = tryParseCommand(pyStrip(statement)) else { continue }
                var choice: Int?
                var extra: [String] = []
                var arg = parsed.arg
                if parsed.op == .selr {
                    var parts = split(arg, on: ",")
                    if parts.count > 1 && parts[1].hasPrefix("`") {
                        parts[1] = parts[1].count > 5 ? String(parts[1].dropFirst(5)) : ""
                    }
                    let head = pyStrip(parts[0])
                    let digits = String(head.drop(while: { $0 == "-" }))
                    if !digits.isEmpty && digits.allSatisfy(isASCIIDigit) {
                        choice = Int(head)
                    }
                    arg = parts.count > 1 ? parts[1] : ""
                    extra = parts.count > 2 ? Array(parts[2...]) : []
                }
                list.append(TextCommand(script: k, name: script.name, pos: pos, op: parsed.op,
                                        label: parsed.label, arg: arg, choice: choice, extra: extra))
            }
        }
        return list
    }

    /// The commands that reference each id (ascending ids when the keys are sorted).
    public static func refIndex(_ commands: [TextCommand]) -> [Int: [TextCommand]] {
        var index: [Int: [TextCommand]] = [:]
        for command in commands {
            for reference in command.refs {
                index[reference, default: []].append(command)
            }
        }
        return index
    }

    /// The displayed messages as the engine's raw buffer sees them: a `_ZM` followed by the `_MSAD`
    /// commands that append to it (until the next `_ZM`/`_ZD` or the next script). `_SELR` does not
    /// touch the buffer; a `_ZD` starts no group.
    public static func messageGroups(_ commands: [TextCommand]) -> [[TextCommand]] {
        var groups: [[TextCommand]] = []
        var current: Int?
        for command in commands {
            switch command.op {
            case .selr:
                continue
            case .zd:
                current = nil
            case .zm:
                current = groups.count
                groups.append([command])
            case .msad:
                if let index = current, groups[index][0].script == command.script {
                    groups[index].append(command)
                } else {
                    current = groups.count
                    groups.append([command])
                }
            }
        }
        return groups
    }

    /// The ids referenced only by disabled `_ZD` messages (so never displayed), ascending.
    public static func zdOnlyIds(_ commands: [TextCommand]) -> [Int] {
        refIndex(commands)
            .filter { $0.value.allSatisfy { $0.op == .zd } }
            .keys
            .sorted()
    }

    /// Counts of ops, argument shapes and markup codes in the message arguments.
    public static func scriptCensus(_ commands: [TextCommand])
        -> (ops: [String: Int], shapes: [String: Int], codes: [String: Int]) {
        var ops: [String: Int] = [:]
        var shapes: [String: Int] = [:]
        var codes: [String: Int] = [:]

        func bump(_ table: inout [String: Int], _ key: String) {
            table[key, default: 0] += 1
        }

        for command in commands {
            bump(&ops, command.opName)
            let hasRefs = !command.refs.isEmpty
            if command.op == .selr {
                let tail = command.extra.map { "," + $0 }.joined()
                let body = hasRefs ? replaceRefs(command.arg) : "<label or inline text>"
                bump(&shapes, "SELR(<n>,\(body)\(tail))")
            } else if hasRefs {
                bump(&shapes, "\(command.opName)(\(replaceRefs(command.arg)))")
            } else {
                bump(&shapes, "\(command.opName)(<inline text>)")
            }

            for token in Markup.tokenize(ByteSpan(Array(command.arg.utf8)), .ja, script: command.op != .selr) {
                if case .code(let code) = token {
                    let letter = String(decoding: code.code, as: UTF8.self)
                    let arg = code.arg.map { String(decoding: $0, as: UTF8.self) } ?? ""
                    bump(&codes, "@" + letter + arg)
                }
            }
        }
        return (ops, shapes, codes)
    }

    /// A readable transcript of one script in one language: every text command, expanded. Choices are
    /// shown without the engine's number prefix (it depends on which `_SELR` commands the `_IF__`
    /// branches execute).
    public static func sceneTranscript(_ text: ScriptText, _ scripts: [ScriptSource], _ name: String,
                                       _ lang: Language) throws -> [String] {
        var rows: [String] = []
        for command in iterTextCommands(scripts.filter { $0.name == name }) {
            let expanded = try text.expandBytes(ByteSpan(Array(command.message.utf8)), lang)
            let decoded = Array(String(decoding: expanded, as: UTF8.self).utf8)
            let shown = String(decoding: Markup.plainText(ByteSpan(decoded), lang, ruby: .paren), as: UTF8.self)
                .replacingOccurrences(of: "\n", with: " / ")
            let prefix: String
            switch command.op {
            case .selr:
                prefix = "> choice \(command.choice.map { String($0) } ?? "None")\(command.locked ? " (locked)" : ""): "
            case .zm:
                prefix = ""
            case .zd:
                prefix = "[ZD] "
            case .msad:
                prefix = "+ "
            }
            let ids = command.refs.map(pad6).joined(separator: ",")
            rows.append("\(ids.isEmpty ? "------" : ids)\t\(prefix)\(shown)")
        }
        return rows
    }

    /// For every `_VPLY` / `_VPL2`, how many text commands follow it before the next voice command
    /// or the end of the script: count to number of voice commands, per op.
    public static func voiceTextCounts(_ scripts: [ScriptSource])
        -> (vply: [Int: Int], vpl2: [Int: Int]) {
        enum Table { case vply, vpl2 }

        var vply: [Int: Int] = [:]
        var vpl2: [Int: Int] = [:]

        func bump(_ table: Table, _ count: Int) {
            switch table {
            case .vply: vply[count, default: 0] += 1
            case .vpl2: vpl2[count, default: 0] += 1
            }
        }

        for script in scripts {
            var current: Table?
            var n = 0
            for statement in split(script.text, on: ";") {
                let command = pyStrip(statement)
                let voice: Table? = command.hasPrefix("_VPLY(") ? .vply
                    : command.hasPrefix("_VPL2(") ? .vpl2 : nil
                if let voice {
                    if let current { bump(current, n) }
                    current = voice
                    n = 0
                } else if tryParseCommand(command) != nil {
                    n += 1
                }
            }
            if let current { bump(current, n) }
        }
        return (vply, vpl2)
    }

    /// The class of every line id that no text command references: `choice-number` (43959..43968),
    /// `image-text`, `blank` (the ja line is a blank or `■`), `merged-fragment` (the ja text repeats
    /// the end of the previous line or the start of the next one) and `not-shown`.
    public static func classifyUnreferenced(_ text: ScriptText, _ commands: [TextCommand]) throws -> [Int: String] {
        let used = refIndex(commands)
        let ja = text.table(.ja)
        var result: [Int: String] = [:]
        for i in 0..<text.count {
            if used[i] != nil { continue }
            let s = stripIdeographic(try ja.line(i))
            let previous = i > 0 ? stripIdeographic(try ja.line(i - 1)) : ""
            let next = i + 1 < text.count ? stripIdeographic(try ja.line(i + 1)) : ""
            if i >= TextRules.choiceNumberOverflow {
                result[i] = "choice-number"
            } else if imageTextIds[i] != nil {
                result[i] = "image-text"
            } else if s.isEmpty || s == "■" {
                result[i] = "blank"
            } else if previous.hasSuffix(s) || next.hasPrefix(s) {
                result[i] = "merged-fragment"
            } else {
                result[i] = "not-shown"
            }
        }
        return result
    }

    /// The index of the first `@e` / `@n` in a `_ZM/_ZD/_MSAD` argument.
    static func endIndex(_ arg: String) -> Int? {
        let chars = Array(arg)
        for i in 0..<max(0, chars.count - 1) where chars[i] == "@" && (chars[i + 1] == "e" || chars[i + 1] == "n") {
            return i
        }
        return nil
    }

    private static func stripIdeographic(_ s: String) -> String {
        let chars = Array(s)
        var a = 0
        var b = chars.count
        while a < b && (chars[a] == " " || chars[a] == "\u{3000}") { a += 1 }
        while b > a && (chars[b - 1] == " " || chars[b - 1] == "\u{3000}") { b -= 1 }
        return String(chars[a..<b])
    }

    /// The six-digit display of a line id.
    private static func pad6(_ id: Int) -> String {
        let digits = String(id)
        return String(repeating: "0", count: max(0, 6 - digits.count)) + digits
    }

    private static func tryRef(_ scalars: [Unicode.Scalar], _ at: Int) -> Int? {
        guard at + 7 <= scalars.count else { return nil }
        var id = 0
        for k in 1...6 {
            let scalar = scalars[at + k]
            guard scalar.properties.generalCategory == .decimalNumber,
                  let value = scalar.properties.numericValue else { return nil }
            id = (id * 10) + Int(value)
        }
        return id
    }

    private static func isASCIIDigit(_ c: Character) -> Bool {
        c >= "0" && c <= "9"
    }

    private static func isHexDigit(_ c: Character) -> Bool {
        (c >= "0" && c <= "9") || (c >= "a" && c <= "f") || (c >= "A" && c <= "F")
    }

    /// Splits like Python's / C#'s `str.split(sep)`: empty pieces are kept, and the empty string
    /// gives one empty piece.
    private static func split(_ s: String, on separator: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        for c in s {
            if c == separator {
                parts.append(current)
                current = ""
            } else {
                current.append(c)
            }
        }
        parts.append(current)
        return parts
    }

    /// `^_(?:(ZM|ZD)([0-9a-fA-F]{5})|(MSAD)|(SELR))\((.*)\)\s*$` on an already stripped statement: the
    /// op, the five hex digits of a `_ZM/_ZD`, and everything between the first `(` and the final `)`.
    private static func tryParseCommand(_ stripped: String) -> (op: TextCommandOp, label: String, arg: String)? {
        guard stripped.count >= 6, stripped.first == "_" else { return nil }
        let chars = Array(stripped)
        let op: TextCommandOp
        let label: String
        let open: Int
        if stripped.hasPrefix("_ZM") || stripped.hasPrefix("_ZD") {
            guard chars.count >= 8, chars[3..<8].allSatisfy(isHexDigit) else { return nil }
            op = chars[2] == "M" ? .zm : .zd
            label = String(chars[3..<8])
            open = 8
        } else if stripped.hasPrefix("_MSAD") {
            op = .msad
            label = ""
            open = 5
        } else if stripped.hasPrefix("_SELR") {
            op = .selr
            label = ""
            open = 5
        } else {
            return nil
        }

        guard open < chars.count, chars[open] == "(", chars.count >= open + 2, chars.last == ")" else {
            return nil
        }
        let arg = String(chars[(open + 1)..<(chars.count - 1)])
        return (op, label, arg)
    }
}
