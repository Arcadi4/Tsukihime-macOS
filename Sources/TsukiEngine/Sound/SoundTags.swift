import Foundation
import TsukiCore

/// The keyword tag scan of the audio handlers (docs/formats/sound_runtime.md 3.1; eboot VA 0x87276..0x87308) and the argument
/// helpers they share. Port of `parse_tags`, `find_tag`, `_arg_text` and `_count_args`. All functions work on the
/// raw statement bytes: `sep` is the index of the separator byte after the four name bytes (`Statement.args[0]`).
public final class SoundTags {
    /// The tag of the fade time in milliseconds (``001`).
    public static let fade = 1

    /// The fade-out time of the old track (``011`).
    public static let wait = 11

    /// The volume (``017`).
    public static let volume = 17

    /// The pan (``018`).
    public static let pan = 18

    /// The loop argument (``049`).
    public static let loop = 49

    /// The delay of a deferred command (``068`).
    public static let delay = 68

    /// The start sample (``069`).
    public static let start = 69

    /// The character of a voice-like SE (``070`).
    public static let character = 70

    /// Tag byte per argument position 0..63 (0xFF = untagged).
    public private(set) var tags: [UInt8] = [UInt8](repeating: 0xFF, count: 64)

    /// 1 + the position of the last tagged argument (0 if none); the handlers search positions 0..N-1 only.
    public private(set) var count: Int = 0

    public init() {}

    private static func at(_ buf: ByteSpan, _ i: Int) -> UInt8 {
        i >= 0 && i < buf.count ? buf[i] : 0
    }

    /// The engine tag scan: an argument whose first byte is a backtick gets the tag byte
    /// `((d1 * 10 + d2) * 10 + d3) mod 256` of its three digit characters, any other argument 0xFF.
    public static func parse(_ buf: ByteSpan, _ sep: Int) -> SoundTags {
        let t = SoundTags()
        var ntags = 0
        var p = sep + 1
        for i in 0..<64 {
            t.tags[i] = 0xFF
            if p >= 0 && p < buf.count && buf[p] == 0x60 {
                let b0 = Int(at(buf, p + 1))
                let b1 = Int(at(buf, p + 2))
                let b2 = Int(at(buf, p + 3))
                var v = (((b0 * 10) & 0xFF) + b1) & 0xFF
                v = (((v * 10) & 0xFF) + b2 + 0x30) & 0xFF
                t.tags[i] = UInt8(v)
                p += 5
                ntags = i + 1
            }

            let start = p
            var q = p + 1
            var end = false
            var broke = false
            for _ in 0..<500 {
                let c = at(buf, q - 1)
                if c == 0x29 || c == 0x3B {
                    end = true
                    broke = true
                    break
                }

                if c == 0x2C {
                    broke = true
                    break
                }

                q += 1
            }

            if !broke {
                q = start + 500
            }

            if end {
                break
            }

            p = q
        }

        t.count = ntags
        return t
    }

    public static func parse(_ buf: [UInt8], _ sep: Int) -> SoundTags {
        parse(ByteSpan(buf), sep)
    }

    /// The position of the first argument tagged `tag` among the first `count`, or -1.
    public func find(_ tag: Int) -> Int {
        for j in 0..<count {
            if tags[j] == UInt8(tag) {
                return j
            }
        }

        return -1
    }

    /// Argument `index` copied the way the SE and voice handlers copy a name: skip a 5-byte backtick tag, stop at
    /// NUL ) , ;.
    public static func argText(_ b: ByteSpan, _ sep: Int, _ index: Int) -> String {
        var p = sep + 1
        for _ in 0..<index {
            var found = false
            for k in 0..<500 {
                let c = at(b, p + k)
                if c == 0x29 || c == 0x3B {
                    return ""
                }

                if c == 0x2C {
                    p += k + 1
                    found = true
                    break
                }
            }

            if !found {
                p += 500
            }
        }

        if p >= 0 && p < b.count && b[p] == 0x60 {
            p += 5
        }

        var scalars: [UnicodeScalar] = []
        while p >= 0 && p < b.count {
            let c = b[p]
            if c == 0 || c == 0x29 || c == 0x2C || c == 0x3B {
                break
            }
            scalars.append(UnicodeScalar(c))
            p += 1
        }

        return String(String.UnicodeScalarView(scalars))
    }

    public static func argText(_ b: [UInt8], _ sep: Int, _ index: Int) -> String {
        argText(ByteSpan(b), sep, index)
    }

    /// VA 0x99F12..0x99F5A: 1 + the number of commas before ) or ; (at most 0x1F3 bytes).
    public static func countArgs(_ b: ByteSpan, _ sep: Int) -> Int {
        var n = 1
        var k = sep + 1
        while k < b.count && k - sep < 0x1F9 {
            let c = b[k]
            if c == 0x29 || c == 0x3B {
                break
            }

            if c == 0x2C {
                n += 1
            }

            k += 1
        }

        return n
    }

    public static func countArgs(_ b: [UInt8], _ sep: Int) -> Int {
        countArgs(ByteSpan(b), sep)
    }

    /// The inline integer reader (VA 0x76690 / 0x76780) at argument `index`.
    public static func int(_ b: ByteSpan, _ sep: Int, _ index: Int, bits: Int = 16) -> Int {
        InlineReader.readInt(b, sep + 1, index, bits: bits)
    }

    public static func int(_ b: [UInt8], _ sep: Int, _ index: Int, bits: Int = 16) -> Int {
        InlineReader.readInt(ByteSpan(b), sep + 1, index, bits: bits)
    }

    /// The inline "present" test at argument `index`.
    public static func present(_ b: ByteSpan, _ sep: Int, _ index: Int) -> Bool {
        InlineReader.isPresent(b, sep + 1, index)
    }

    public static func present(_ b: [UInt8], _ sep: Int, _ index: Int) -> Bool {
        InlineReader.isPresent(ByteSpan(b), sep + 1, index)
    }
}
