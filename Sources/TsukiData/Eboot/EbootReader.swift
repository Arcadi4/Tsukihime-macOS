import Foundation
import TsukiCore
import TsukiEngine

/// The addresses of the analysed eboot.bin (CUSA47999 v01.01) that the table readers use: text VA to file
/// offset is `VA + 0x2280`, RELRO `VA - 0x400000 + 0x32C210`, data `VA - 0x600000 + 0x365FA0`
/// (docs/formats/engine.md 1.2, RR 3.2). They are valid only after the build check accepted the file.
public enum EbootAddresses {
    /// File offset of text VA 0 (docs/formats/engine.md 1.2).
    public static let textFileOffset = 0x2280

    /// Size of the text segment in the file (also the first byte after it, as a VA).
    public static let textSize = 0x329DC8

    /// RELRO segment VA.
    public static let relroVa = 0x400000
    /// RELRO segment file offset.
    public static let relroFileOffset = 0x32C210
    /// RELRO segment size.
    public static let relroSize = 0x35ED0

    /// Data segment VA.
    public static let dataVa = 0x600000
    /// Data segment (file-backed part) file offset.
    public static let dataFileOffset = 0x365FA0
    /// Data segment (file-backed part) size.
    public static let dataSize = 0x7D66E0

    /// The image table, 0x48-byte records (docs/formats/images.md 8).
    public static let imageTable = 0x671900

    /// Size of an image table record.
    public static let imageRecordSize = 0x48

    /// Slots of the image table: the engine's bound `id <= 0x39B6`.
    public static let imageTableSlots = 0x39B6 + 1

    /// Used image table records in v01.01 (allpac2 entries minus DUMMY.MRG).
    public static let imageTableRecords = 14_744

    /// The picture-name list (32-byte records ending in CR LF, then 0xFF).
    public static let imageNames = 0x7F6800

    /// The old name list: the first 9,958 names of the list above (archives_ui_movies.md 2.4).
    public static let oldImageNames = 0x7A8B10

    /// Size of a name-list record.
    public static let nameRecordSize = 0x20

    /// The movie table, 0x30-byte records.
    public static let movieTable = 0xDC8C70

    /// Size of a movie record.
    public static let movieRecordSize = 0x30

    /// The terminator record of the movie table (id -1).
    public static let movieTerminator = 0xDCA590

    /// Five `char*` to the language suffixes `ja en zc zt ko`.
    public static let languageSuffixes = 0x42C030

    /// Four u32 movie ids of the prologue per language.
    public static let prologueTable = 0x200F70

    /// The scene-id table: 549 i16 (docs/formats/script.md 2.5).
    public static let sceneIds = 0x216130

    /// `char *ui_text[5][1499]` in RELRO.
    public static let uiText = 0x41D5F0

    /// The string "Hunex Consumer Library".
    public static let hunexString = 0x2DA510

    /// Size of a UI texture registration record.
    public static let uiRecordSize = 0x18

    /// The 21 UI texture registration tables: header-less arrays ended by a record with a negative
    /// texture slot.
    public static let uiTables: [Int] = [
        0x66AD10, 0x66BA80, 0x66BBC0, 0x66C9A0, 0x780C90, 0x781B70,
        0x782700, 0x784290, 0x785E20, 0x7879B0, 0x789540, 0x78B2C0,
        0x7A6090, 0x7A67F0, 0x7A6B20, 0x7A7680, 0x7A8300, 0x8730F0,
        0x8731A0, 0x873660, 0xDB9320,
    ]

    /// The five `ed1_parts` tables that no code references.
    public static let uiTablesUnreferenced: [Int] = [0x782700, 0x784290, 0x785E20, 0x7879B0, 0x789540]
}

/// Reads the file-backed bytes of eboot.bin by virtual address, through the program headers of a
/// `SelfImage`: a port of the read helpers of `tsuki.catalog_eboot.Eboot`. A read must lie inside one
/// loaded segment's file image (.bss and unmapped addresses are errors here, unlike `SelfImage.readVa`).
public final class EbootReader {
    /// The parsed SELF / ELF.
    public let image: SelfImage

    /// Where the tables are in this eboot: `EbootLayout.analysed` for the verified build, else what
    /// `EbootLocator` found by content. Every table reader takes its addresses and counts from here.
    public let layout: EbootLayout

    /// First VA after the text segment: pointers to names must be below it.
    public var textEnd: Int

    /// The loaded segments as (first VA, VA after the file image, file offset of the first byte), in
    /// program-header order.
    public var segments: [(start: Int, end: Int, fileOffset: Int)]

    /// Creates a reader over a parsed image with the addresses of the verified build.
    public convenience init(_ image: SelfImage) {
        self.init(image, layout: .analysed)
    }

    /// Creates a reader over a parsed image whose tables are where `layout` says.
    public init(_ image: SelfImage, layout: EbootLayout) {
        self.image = image
        self.layout = layout

        var list: [(start: Int, end: Int, fileOffset: Int)] = []
        for segment in image.loadSegments {
            let ph = segment.header
            guard ph.fileSize != 0, let fileOffset = segment.fileOffset else { continue }
            let (endAddress, overflow) = ph.vAddr.addingReportingOverflow(ph.fileSize)
            guard !overflow, let start = Int(exactly: ph.vAddr), let end = Int(exactly: endAddress) else { continue }
            list.append((start: start, end: end, fileOffset: fileOffset))
        }
        self.segments = list

        let text = image.text
        let (endAddress, overflow) = text.vAddr.addingReportingOverflow(text.fileSize)
        self.textEnd = overflow ? 0 : (Int(exactly: endAddress) ?? 0)
    }

    /// Parses `data` and wraps it with the verified build's addresses.
    public static func parse(_ data: ByteSpan) throws -> EbootReader {
        EbootReader(try SelfImage.parse(data), layout: .analysed)
    }

    /// The same image with another `layout`.
    public func withLayout(_ layout: EbootLayout) -> EbootReader {
        EbootReader(image, layout: layout)
    }

    /// True when `p` points into the text segment (`0 < p < textEnd`).
    public func isTextPointer(_ p: Int) -> Bool { p > 0 && p < textEnd }

    /// The file offset of a VA, or nil when it is not file-backed.
    public func fileOffset(_ va: Int) -> Int? {
        for (start, end, fileOffset) in segments where va >= start && va < end {
            return fileOffset + (va - start)
        }
        return nil
    }

    /// The `n` bytes at a VA.
    /// - Throws: `TsukiError.format` when the range is not inside one segment's file image.
    public func read(_ va: Int, _ n: Int) throws -> ByteSpan {
        guard n >= 0 else {
            throw TsukiError.format("VA 0x\(String(va, radix: 16)) (+\(n)) is not file-backed")
        }
        for (start, end, fileOffset) in segments where va >= start && va < end {
            guard n <= end - va else { break }
            let offset = fileOffset + (va - start)
            guard offset >= 0, offset <= image.data.count - n else {
                throw TsukiError.format("VA 0x\(String(va, radix: 16)) (+\(n)) is not file-backed")
            }
            return image.data.slice(offset, n)
        }
        throw TsukiError.format("VA 0x\(String(va, radix: 16)) (+\(n)) is not file-backed")
    }

    /// A little-endian u32.
    public func u32(_ va: Int) throws -> UInt32 { try read(va, 4).u32(0) }

    /// A little-endian i32.
    public func i32(_ va: Int) throws -> Int32 { try read(va, 4).i32(0) }

    /// A little-endian u64.
    public func u64(_ va: Int) throws -> UInt64 { try read(va, 8).u64(0) }

    /// A little-endian i16.
    public func i16(_ va: Int) throws -> Int16 { try read(va, 2).i16(0) }

    /// The NUL-terminated string at a VA, at most `limit` bytes, each byte as one character (Latin-1,
    /// like the Python tools). Empty when the VA is not file-backed.
    public func cString(_ va: Int, limit: Int = 256) -> String {
        guard limit > 0 else { return "" }
        var n = limit
        for (start, end, _) in segments where va >= start && va < end {
            n = min(limit, end - va)
            break
        }
        guard let window = try? read(va, n) else { return "" }
        var end = window.count
        for i in 0..<window.count where window[i] == 0 {
            end = i
            break
        }
        return Self.latin1(window.slice(0, end))
    }

    /// Each byte as one character.
    public static func latin1(_ bytes: ByteSpan) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(bytes.count)
        for byte in bytes { scalars.append(UnicodeScalar(byte)) }
        return String(scalars)
    }
}
