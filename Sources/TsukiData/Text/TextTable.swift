import Foundation
import TsukiCore
import TsukiEngine

/// One language of `script_text.mrg`: the offset table (big-endian u32; N string starts, then
/// `blob_size` twice) and the UTF-8 string blob in which every string ends with CR LF
/// (docs/formats/text.md 2).
///
/// Ids outside the table are rejected where the Python reference raises `IndexError` (the engine
/// reads past the table unchecked, text.md 4). Offsets that point outside the blob give the same
/// answers as Python slicing (clamped, possibly empty), so a damaged table never throws from a read.
public struct TextTable {
    /// The language of this table.
    public let language: Language

    private let offsetValues: [UInt32]
    private let blobSource: TextBlob

    /// Creates a table over an already parsed offset list and a blob.
    /// - Parameters:
    ///   - offsets: The N + 2 entries before the end mark(s): N string starts, then the blob size twice.
    public init(language: Language, offsets: [UInt32], blob: ByteSpan) throws {
        try self.init(language: language, offsets: offsets, blobSource: TextBlob(blob))
    }

    init(language: Language, offsets: [UInt32], blobSource: TextBlob) throws {
        guard offsets.count >= 2 else {
            throw TsukiError.format("offset table shorter than the two blob_size guard entries")
        }
        self.language = language
        self.offsetValues = offsets
        self.blobSource = blobSource
    }

    /// Number of string ids (the two trailing `blob_size` entries are guards).
    public var count: Int { offsetValues.count - 2 }

    /// The entries before the end mark: N string starts, then `blob_size` twice.
    public var offsets: [UInt32] { offsetValues }

    /// The string blob (loaded on first use when the table was opened from a file).
    public var blob: ByteSpan {
        get throws { try blobSource.value() }
    }

    /// Parses a big-endian offset table: the entries before the first 0xFFFFFFFF. Retail tables end
    /// with exactly one end mark, tables repacked by mangetsu with three; any number of end marks is
    /// accepted as long as only end marks follow the first one.
    /// - Parameters:
    ///   - data: The section bytes.
    ///   - strict: Demand the retail form (exactly one end mark).
    /// - Returns: The N + 2 entries and the number of end marks found.
    public static func parseOffsets(_ data: ByteSpan, strict: Bool) throws -> (offsets: [UInt32], endMarks: Int) {
        guard data.count % 4 == 0 else {
            throw TsukiError.format("offset table size \(data.count) is not a multiple of 4")
        }

        let n = data.count / 4
        var end = -1
        for i in 0..<n where data.u32be(4 * i) == TextRules.endMark {
            end = i
            break
        }
        guard end >= 0 else {
            throw TsukiError.format("offset table has no 0xFFFFFFFF end mark")
        }
        for i in end..<n where data.u32be(4 * i) != TextRules.endMark {
            throw TsukiError.format("non-end-mark entries after the 0xFFFFFFFF at index \(end)")
        }
        if strict && end != n - 1 {
            throw TsukiError.format("\(n - end) end marks; the retail layout has exactly one")
        }
        guard end >= 2 else {
            throw TsukiError.format("offset table shorter than the two blob_size guard entries")
        }

        var offsets = [UInt32](repeating: 0, count: end)
        for i in 0..<end {
            offsets[i] = data.u32be(4 * i)
        }
        return (offsets, n - end)
    }

    /// Exact bytes of string `id` including its trailing CR LF.
    public func raw(_ id: Int) throws -> ByteSpan {
        guard id >= 0 && id < count else {
            throw TsukiError.bounds("\(TextRules.code(language)): line id \(id) out of range 0..\(count - 1)")
        }
        return Self.pySlice(try blob, Int64(offsetValues[id]), Int64(offsetValues[id + 1]))
    }

    /// String `id` without its CR LF (a string that does not end with CR LF is returned whole).
    public func lineBytes(_ id: Int) throws -> ByteSpan {
        let bytes = try raw(id)
        if bytes.count >= 2 && bytes[bytes.count - 2] == 0x0D && bytes[bytes.count - 1] == 0x0A {
            return bytes.slice(0, bytes.count - 2)
        }
        return bytes
    }

    /// String `id` without its CR LF, decoded as strict UTF-8.
    public func line(_ id: Int) throws -> String {
        try Self.strictUTF8(lineBytes(id))
    }

    /// What the engine's copy routine (VA 0x75F80) produces for `id`: nothing for a negative id;
    /// nothing when the entry is shorter than 3 bytes (the guard entries `count` and `count + 1`
    /// included), else `min(n, 0x301) - 2` bytes (text.md 4). Ids past the table throw.
    public func engineLine(_ id: Int) throws -> ByteSpan {
        if id < 0 || id == offsetValues.count - 1 {
            return ByteSpan()
        }
        guard id < offsetValues.count else {
            throw TsukiError.bounds("\(TextRules.code(language)): id \(id) beyond the table")
        }

        let n = Int64(offsetValues[id + 1]) - Int64(offsetValues[id])
        guard n >= 3 else { return ByteSpan() }
        let start = Int64(offsetValues[id])
        return Self.pySlice(try blob, start, start + min(n, 0x301) - 2)
    }

    /// Deviations from the retail layout, one message each (empty for the retail data).
    public func validate() throws -> [String] {
        var issues: [String] = []
        let lang = TextRules.code(language)
        let offs = offsetValues
        let blob = try blob
        let size = Int64(blob.count)

        if offs.count < 2 || Int64(offs[offs.count - 1]) != size || Int64(offs[offs.count - 2]) != size {
            issues.append("\(lang): table does not end with blob_size twice (last=(\(offs[offs.count - 2]), \(offs[offs.count - 1])), blob=\(size))")
        }

        for i in 0..<(offs.count - 1) where offs[i + 1] < offs[i] {
            issues.append("\(lang): offsets decrease at \(i)")
            break
        }

        if !offs.isEmpty && offs[0] != 0 {
            issues.append("\(lang): first offset \(offs[0]) != 0")
        }

        var badEnd: [Int] = []
        for i in 0..<count {
            let a = Int64(offs[i])
            let b = Int64(offs[i + 1])
            let tail = Self.pySlice(blob, b - 2, b)
            if b - a < 2 || tail.count != 2 || tail[0] != 0x0D || tail[1] != 0x0A {
                badEnd.append(i)
            }
        }
        if !badEnd.isEmpty {
            issues.append("\(lang): \(badEnd.count) strings without CRLF, first [\(badEnd.prefix(5).map(String.init).joined(separator: ", "))]")
        }

        if Self.countByte(blob, 0x0D) != count || Self.countByte(blob, 0x0A) != count {
            var inner: [Int] = []
            for i in 0..<count {
                let line = try lineBytes(i)
                if line.contains(where: { $0 == 0x0D || $0 == 0x0A }) {
                    inner.append(i)
                }
            }
            issues.append("\(lang): \(inner.count) strings contain CR/LF before the end, first [\(inner.prefix(5).map(String.init).joined(separator: ", "))]")
        }

        if String(bytes: blob, encoding: .utf8) == nil {
            issues.append("\(lang): blob is not UTF-8")
        }

        if size != 0 && Int64(offs[count]) != size {
            issues.append("\(lang): last string does not end at the blob end")
        }

        return issues
    }

    static func strictUTF8(_ bytes: ByteSpan) throws -> String {
        guard let text = String(bytes: bytes, encoding: .utf8) else {
            throw TsukiError.format("line is not valid UTF-8")
        }
        return text
    }

    /// Python slicing `blob[a:b]` for non-negative bounds: clamped to the data, empty when `b <= a`.
    static func pySlice(_ data: ByteSpan, _ a: Int64, _ b: Int64) -> ByteSpan {
        let length = Int64(data.count)
        let start = max(0, min(a, length))
        let end = max(0, min(b, length))
        guard end > start else { return ByteSpan() }
        return data.slice(Int(start), Int(end - start))
    }

    private static func countByte(_ data: ByteSpan, _ value: UInt8) -> Int {
        data.reduce(0) { $0 + ($1 == value ? 1 : 0) }
    }
}

/// The lazily read blob of a `TextTable`. The factory may throw, so `LazyValue` cannot carry it.
final class TextBlob {
    private let lock = NSLock()
    private var cached: ByteSpan?
    private var factory: (() throws -> ByteSpan)?

    init(_ span: ByteSpan) {
        cached = span
    }

    init(_ factory: @escaping () throws -> ByteSpan) {
        self.factory = factory
    }

    func value() throws -> ByteSpan {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let made = try factory!()
        cached = made
        factory = nil
        return made
    }
}
