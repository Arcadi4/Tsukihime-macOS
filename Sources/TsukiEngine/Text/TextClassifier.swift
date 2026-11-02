import Foundation
import TsukiCore

/// Result of layout pass 1: the element count, the break classes and the English word lengths.
public struct ClassifyResult: Sendable, Equatable {
    /// Elements found (at most ``TextClassifier/elementBudget``).
    public let n: Int
    /// Break class of every element (byte array VA 0x178C100, 1200 entries).
    public let classes: [UInt8]
    /// English word-length table (u16 array VA 0x178C5B0): entry i-1 = length + 1 of the word that starts at element i.
    public let wordLen: [UInt16]

    public init(n: Int, classes: [UInt8], wordLen: [UInt16]) {
        self.n = n
        self.classes = classes
        self.wordLen = wordLen
    }
}

/// Layout pass 1 of `Text_Layout` (eboot VA 0xC6D80..0xC7375): one break class per element (glyph or
/// control) within a 1200-element budget, plus the English word-length table. Port of
/// `tsuki.textbox.classify` (docs/formats/textbox.md 5.1).
public enum TextClassifier {
    /// Pass 1 loop bound (VA 0xC6D95): 1200 elements.
    public static let elementBudget = 0x4B0

    /// Zero bytes appended after the text so look-ahead reads see the NUL terminator and more.
    static let padding = 300

    /// VA 0x11AB0: a "wide" character (break class 1, ruby unit 2).
    public static func isWide(_ key: UInt64) -> Bool {
        if key < 0x100 {
            return false
        }
        if key <= 0xFFFF {
            return key == 0xC2B1 || key == 0xC397 || key == 0xC3B7
        }
        if key <= 0xFFFFFF {
            return !(key >= 0xEFBDA1 && key <= 0xEFBE9F)
        }
        return true
    }

    /// VA 0x11B00 plus the length rule of pass 1: (key, bytes); an invalid lead gives (0, 1).
    static func decode(_ b: [UInt8], _ p: Int) -> (key: UInt64, length: Int) {
        let c = Int(b[p])
        if c < 0x80 {
            return (UInt64(c), 1)
        }
        if (c & 0xE0) == 0xC0 {
            return ((UInt64(c) << 8) | UInt64(b[p + 1]), 2)
        }
        if (c & 0xF0) == 0xE0 {
            return ((UInt64(c) << 16) | (UInt64(b[p + 1]) << 8) | UInt64(b[p + 2]), 3)
        }
        if (c & 0xF8) == 0xF0 {
            return ((UInt64(c) << 24) | (UInt64(b[p + 1]) << 16) | (UInt64(b[p + 2]) << 8) | UInt64(b[p + 3]), 4)
        }
        return (0, 1)
    }

    private static func bit(_ mask: UInt64, _ k: Int64) -> Bool {
        k >= 0 && k < 64 && ((mask >> Int(k)) & 1) == 1
    }

    /// Pass-1 class of a wide character (VA 0xC6EF3..0xC7051, 0xC70C9..0xC7211).
    static func wideClass(_ key: UInt64) -> Int {
        var k: Int64
        if key > 0xE38282 {
            k = Int64(key) - 0xE38283
            if k <= 0x26 && bit(0x5540000815, k) {
                return 0x0D // small kana
            }
            k = Int64(key) - 0xE38383
            if k >= 0 && k <= 0x39 && bit(0x30C081500000001, k) {
                return 0x0D
            }
            k = Int64(key) - 0xEFBC81
            if k >= 0 && k <= 0x1E {
                if bit(0x6002900, k) {
                    return 0x71
                }
                if bit(0x40000001, k) {
                    return 0x0D
                }
                if k == 7 {
                    return 0x0E
                }
            }
            return 1
        }

        k = Int64(key) - 0xE38081
        if k >= 0 && k <= 0x0E {
            if bit(0x5412, k) {
                return 0x71
            }
            if bit(0x2800, k) {
                return 0x0E
            }
            if k == 0 {
                return 0x0D
            }
        }

        k = Int64(key) - 0xE38181
        if k >= 0 && k <= 0x22 && bit(0x400000155, k) {
            return 0x0D
        }

        k = Int64(key) - 0xE28098
        if k >= 0 && k <= 0x0F {
            if k == 0 || k == 4 {
                return 0x0E
            }
            if k == 1 || k == 5 {
                return 0x71
            }
            if k == 15 {
                return 0x0D
            }
        }

        return 1
    }

    private static func afterDotOk(_ c: Int) -> Bool {
        c <= 0x2E && (c == 0x22 || c == 0x27 || c == 0x2E)
    }

    private static func tagLength(_ b: [UInt8], _ p: Int, _ tags: [[UInt8]]) -> Int {
        for t in tags {
            if p + t.count <= b.count && b[p..<(p + t.count)].elementsEqual(t) {
                return t.count
            }
        }
        return 0
    }

    /// Pass 1 (VA 0xC6D80..0xC7375) with the standard `[tag]` names.
    /// - Parameters:
    ///   - text: The message bytes without the terminating NUL.
    ///   - lang: Text language (English: no ruby, English word table).
    ///   - flags: Caller flags (0x2000 skips ruby readings).
    public static func classify(_ text: ByteSpan, _ lang: Language, _ flags: Int = 0) -> ClassifyResult {
        var padded = Array(text)
        padded.append(contentsOf: repeatElement(0, count: padding))
        return classify(padded, Int(lang.rawValue), flags, FontTables.standardTagBytes, lang == .en)
    }

    /// Pass 1 over byte array.
    public static func classify(_ text: [UInt8], _ lang: Language, _ flags: Int = 0) -> ClassifyResult {
        var padded = text
        padded.append(contentsOf: repeatElement(0, count: padding))
        return classify(padded, Int(lang.rawValue), flags, FontTables.standardTagBytes, lang == .en)
    }

    /// Pass 1 over a buffer that already carries at least ``padding`` zero bytes after the text.
    static func classify(_ b: [UInt8], _ lang: Int, _ flags: Int, _ tags: [[UInt8]], _ english: Bool) -> ClassifyResult {
        var cls = [UInt8](repeating: 0, count: elementBudget)
        var wl = [UInt16](repeating: 0, count: elementBudget)
        var p = 0
        var i = 0
        var budget = elementBudget
        var prev = 0
        var ruby = 0
        while true {
            let c = Int(b[p])
            if c == 0 {
                break
            }

            var q = p + 1
            var cur = c
            if c >= 0x80 {
                let (key, ln) = decode(b, p)
                q = p + ln
                if isWide(key) {
                    cls[i] = UInt8(wideClass(key))
                } else if !(prev <= 0x2E && (prev == 0x20 || prev == 0x2C || prev == 0x2E)) {
                    cls[i] = 2
                    if key != 0xC2B7 && i != 0 {
                        let a = Int(cls[i - 1])
                        if (a | 2) == 3 || a >= 5 {
                            cls[i] = 0
                        }
                    }
                }
            } else if lang != 1 && c == 0x3C {
                ruby = 1
            } else if c == 0x7C && ruby > 0 {
                if ruby == 1 {
                    ruby = 2
                }
                if (flags & 0x2000) != 0 {
                    while true {
                        cur = Int(b[q])
                        q += 1
                        if cur == 0 || cur == 0x3E {
                            break
                        }
                    }
                    ruby = 0
                }
            } else if lang != 1 && c == 0x3E {
                ruby = 0
            } else if c == 0x40 {
                let d = Int(b[p + 1])
                let e = Int64(d - 0x61)
                if e >= 0 && e <= 0x16 && (bit(0x4000A4, e) || e == 0) {
                    q = p + 3
                } else if (d & 0xFE) == 0x78 {
                    if !(b[p + 2] >= 0x30 && b[p + 2] <= 0x39) {
                        q = p + 2
                    } else if !(b[p + 3] >= 0x30 && b[p + 3] <= 0x39) {
                        q = p + 3
                    } else {
                        q = (b[p + 4] >= 0x30 && b[p + 4] <= 0x39) ? p + 5 : p + 4
                    }
                } else if b[p + 2] == 0x28 {
                    q = p + 2
                    var r = p + 4
                    for _ in 0..<0xFF {
                        let d2 = b[r - 1]
                        if d2 == 0 {
                            break
                        }
                        if d2 == 0x29 {
                            q = r
                            break
                        }
                        r += 1
                    }
                } else {
                    q = p + 2
                }
            } else if c == 0x5E {
                // '^': a plain element
            } else if c == 0x5B {
                let tl = tagLength(b, p, tags)
                if tl != 0 {
                    q = p + tl
                    cls[i] = 1
                }
            } else {
                let wordStart = prev == 0x20 || (prev == 0x2C && c != 0x20) || (prev == 0x2E && !afterDotOk(c))
                if wordStart {
                    if english && i != 0 {
                        wl[i - 1] = 1
                        var k = 0
                        var sc = c
                        while true {
                            let d = Int(b[q + k])
                            if d == 0 || d == 0x5E || sc == 0x20 {
                                break
                            }
                            if sc == 0x2C && d != 0x20 {
                                break
                            }
                            if sc == 0x2E && !afterDotOk(d) {
                                break
                            }
                            wl[i - 1] = UInt16(k + 2)
                            k += 1
                            if budget == k {
                                break
                            }
                            sc = d
                        }
                    }
                } else if (c & 0xFD) == 0x2C {
                    cls[i] = 3
                } else if (prev == 0x21 || prev == 0x2E || prev == 0x3F) && (c == 0x27 || c == 0x22) {
                    cls[i] = 3
                } else {
                    cls[i] = 2
                }
            }

            i += 1
            budget -= 1
            prev = cur
            p = q
            if i == elementBudget {
                break
            }
        }

        return ClassifyResult(n: i, classes: cls, wordLen: wl)
    }
}
