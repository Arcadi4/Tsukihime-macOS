import Foundation
import TsukiCore
import TsukiEngine

/// One entry of the SELF segment table (docs/formats/engine.md 1.2).
public struct SelfSegment: Equatable, Sendable {
    /// Position in the table.
    public let index: Int
    /// Bits 20..31 = ELF program header index, 0x800 = blocked, 0x8 = deflated, 0x2 = encrypted.
    public let flags: UInt64
    /// File offset of the stored bytes.
    public let offset: UInt64
    /// Stored size.
    public let compSize: UInt64
    /// Size after inflating.
    public let decSize: UInt64

    public init(index: Int, flags: UInt64, offset: UInt64, compSize: UInt64, decSize: UInt64) {
        self.index = index
        self.flags = flags
        self.offset = offset
        self.compSize = compSize
        self.decSize = decSize
    }

    /// The ELF program header this segment holds the bytes of.
    public var phdrId: Int { Int((flags >> 20) & 0xFFF) }

    /// True for a segment with data (flag 0x800).
    public var blocked: Bool { flags & 0x800 != 0 }

    /// True when the segment is deflated (flag 0x8).
    public var deflated: Bool { flags & 0x8 != 0 }

    /// True when the segment is encrypted (flag 0x2).
    public var encrypted: Bool { flags & 0x2 != 0 }
}

/// An ELF64 program header (docs/formats/engine.md 1.2).
public struct ProgramHeader: Equatable, Sendable {
    public let index: Int
    public let type: UInt32
    public let flags: UInt32
    public let offset: UInt64
    public let vAddr: UInt64
    public let pAddr: UInt64
    public let fileSize: UInt64
    public let memSize: UInt64
    public let align: UInt64

    public init(
        index: Int, type: UInt32, flags: UInt32, offset: UInt64, vAddr: UInt64,
        pAddr: UInt64, fileSize: UInt64, memSize: UInt64, align: UInt64
    ) {
        self.index = index
        self.type = type
        self.flags = flags
        self.offset = offset
        self.vAddr = vAddr
        self.pAddr = pAddr
        self.fileSize = fileSize
        self.memSize = memSize
        self.align = align
    }

    /// A header mark for an ELF without program headers; `index` is -1.
    public static let empty = ProgramHeader(
        index: -1, type: 0, flags: 0, offset: 0, vAddr: 0, pAddr: 0, fileSize: 0, memSize: 0, align: 0)

    /// The name of a known type (`LOAD`, `SCE_RELRO`, ...), else the hex value.
    public var typeName: String { SelfImage.programHeaderTypeName(type) }

    /// Permissions as `RWX` with `-` for a missing right.
    public var perms: String {
        (flags & 4 != 0 ? "R" : "-") + (flags & 2 != 0 ? "W" : "-") + (flags & 1 != 0 ? "X" : "-")
    }
}

/// One entry of the SCE dynamic table.
public struct DynamicEntry: Equatable, Sendable {
    /// The tag (`DT_*`), as an unsigned 64-bit value.
    public let tag: UInt64
    public let value: UInt64

    public init(tag: UInt64, value: UInt64) {
        self.tag = tag
        self.value = value
    }
}

/// An ELF64 symbol of the dynamic symbol table; imports are named `NID#library#module`.
public struct ElfSymbol: Equatable, Sendable {
    public let index: Int
    public let name: String
    public let info: UInt8
    public let other: UInt8
    public let shndx: UInt16
    public let value: UInt64
    public let size: UInt64

    public init(index: Int, name: String, info: UInt8, other: UInt8, shndx: UInt16, value: UInt64, size: UInt64) {
        self.index = index
        self.name = name
        self.info = info
        self.other = other
        self.shndx = shndx
        self.value = value
        self.size = size
    }

    /// The binding (high nibble of `st_info`).
    public var bind: Int { Int(info >> 4) }

    /// The symbol type (low nibble of `st_info`): 2 = function, 1 = object, 6 = TLS.
    public var type: Int { Int(info & 0xF) }
}

/// An `Elf64_Rela` entry.
public struct Relocation: Equatable, Sendable {
    /// The VA that is patched.
    public let offset: UInt64
    /// Symbol index (`r_info >> 32`).
    public let sym: Int32
    /// Relocation type (`r_info & 0xFFFFFFFF`).
    public let type: UInt32
    /// The addend.
    public let addend: Int64

    public init(offset: UInt64, sym: Int32, type: UInt32, addend: Int64) {
        self.offset = offset
        self.sym = sym
        self.type = type
        self.addend = addend
    }
}

/// A needed module (`DT_SCE_NEEDED_MODULE`).
public struct ModuleRef: Equatable, Sendable {
    public let id: Int
    public let name: String
    public let versionMajor: Int
    public let versionMinor: Int

    public init(id: Int, name: String, versionMajor: Int, versionMinor: Int) {
        self.id = id
        self.name = name
        self.versionMajor = versionMajor
        self.versionMinor = versionMinor
    }
}

/// An imported library (`DT_SCE_IMPORT_LIB` with its attribute).
public struct LibraryRef: Equatable, Sendable {
    public let id: Int
    public let name: String
    public let version: Int
    public let attr: UInt64?

    public init(id: Int, name: String, version: Int, attr: UInt64?) {
        self.id = id
        self.name = name
        self.version = version
        self.attr = attr
    }
}

/// One imported symbol with its GOT slot, as `eboot.selfelf.Import`.
public final class ImportedSymbol {
    /// Index into the dynamic symbol table.
    public let symIndex: Int
    /// The 11-character NID.
    public let nid: String
    /// Library name, or `lib#N` when its id is unknown.
    public let library: String
    /// Module name, or `mod#N` when its id is unknown.
    public let module: String
    /// Library id.
    public let libId: Int
    /// Module id.
    public let modId: Int
    /// Symbol type: 2 = function, 1 = object, 6 = TLS.
    public let symType: Int
    /// GOT slot VA (jump slot) or data slot (GLOB_DAT / 64).
    public let gotVa: UInt64
    /// Relocation type.
    public let relocType: UInt32
    /// The PLT stub VA in the text segment, filled by `findPlt`.
    public var pltVa: UInt64?

    public init(
        symIndex: Int, nid: String, library: String, module: String, libId: Int, modId: Int,
        symType: Int, gotVa: UInt64, relocType: UInt32, pltVa: UInt64? = nil
    ) {
        self.symIndex = symIndex
        self.nid = nid
        self.library = library
        self.module = module
        self.libId = libId
        self.modId = modId
        self.symType = symType
        self.gotVa = gotVa
        self.relocType = relocType
        self.pltVa = pltVa
    }
}

/// A loaded segment (`LOAD` or `SCE_RELRO`) with the SELF bytes that back it.
public struct LoadSegment {
    public let header: ProgramHeader
    /// SELF file offset of the first byte, or nil when no blocked SELF segment holds the bytes.
    public let fileOffset: Int?
    /// The `fileSize` bytes of the loaded segment, or nil when they are not in the file.
    public let bytes: ByteSpan?

    public init(header: ProgramHeader, fileOffset: Int?, bytes: ByteSpan?) {
        self.header = header
        self.fileOffset = fileOffset
        self.bytes = bytes
    }

    public var index: Int { header.index }
    public var vAddr: UInt64 { header.vAddr }
    public var fileSize: UInt64 { header.fileSize }
    public var memSize: UInt64 { header.memSize }
    public var flags: UInt32 { header.flags }
}

/// A SELF + ELF64 reader for the (fake-signed, plain) PS4 executable. A port of `tools/eboot/selfelf.py`
/// (docs/formats/engine.md 1-2). The class holds the whole file as given; it reads nothing else.
public final class SelfImage {
    /// The SELF magic at the start of the file.
    public static let magic: [UInt8] = [0x4F, 0x15, 0x3D, 0x1D]

    /// `R_X86_64_64`.
    public static let rX8664: UInt32 = 1
    /// `R_X86_64_GLOB_DAT`.
    public static let rX86GlobDat: UInt32 = 6
    /// `R_X86_64_JUMP_SLOT`.
    public static let rX86JumpSlot: UInt32 = 7
    /// `R_X86_64_RELATIVE`.
    public static let rX86Relative: UInt32 = 8

    private static let ptLoad: UInt32 = 1
    private static let ptDynamic: UInt32 = 2
    private static let ptSceDynlibData: UInt32 = 0x61000000
    private static let ptSceRelro: UInt32 = 0x61000010

    private static let dtSceStrtab: UInt64 = 0x61000035
    private static let dtSceSymtab: UInt64 = 0x61000039
    private static let dtSceSymtabSz: UInt64 = 0x6100003F
    private static let dtSceJmprel: UInt64 = 0x61000029
    private static let dtScePltrelSz: UInt64 = 0x6100002D
    private static let dtSceRela: UInt64 = 0x6100002F
    private static let dtSceRelaSz: UInt64 = 0x61000031
    private static let dtSceNeededModule: UInt64 = 0x6100000F
    private static let dtSceImportLib: UInt64 = 0x61000015
    private static let dtSceImportLibAttr: UInt64 = 0x61000019
    private static let dtSceModuleInfo: UInt64 = 0x6100000D

    private static let idAlphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+-"

    private static let typeNames: [UInt32: String] = [
        0: "NULL", 1: "LOAD", 2: "DYNAMIC", 3: "INTERP", 4: "NOTE", 7: "TLS",
        0x60000000: "SCE_RELA", 0x61000000: "SCE_DYNLIBDATA", 0x61000001: "SCE_PROCPARAM",
        0x61000002: "SCE_MODULE_PARAM", 0x61000010: "SCE_RELRO",
        0x6FFFFF00: "SCE_COMMENT", 0x6FFFFF01: "SCE_LIBVERSION", 0x6474E550: "GNU_EH_FRAME",
    ]

    private static let dynamicNames: [UInt64: String] = [
        0: "NULL", 1: "NEEDED", 5: "STRTAB", 6: "SYMTAB", 7: "RELA", 8: "RELASZ", 9: "RELAENT",
        10: "STRSZ", 11: "SYMENT", 12: "INIT", 13: "FINI", 14: "SONAME", 15: "RPATH",
        16: "SYMBOLIC", 20: "PLTREL", 21: "DEBUG", 22: "TEXTREL", 24: "BIND_NOW",
        25: "INIT_ARRAY", 26: "FINI_ARRAY", 27: "INIT_ARRAYSZ", 28: "FINI_ARRAYSZ",
        30: "FLAGS", 32: "PREINIT_ARRAY", 33: "PREINIT_ARRAYSZ",
        0x61000005: "SCE_IDTABENTSZ", 0x61000007: "SCE_FINGERPRINT",
        0x61000009: "SCE_ORIGINAL_FILENAME", 0x6100000D: "SCE_MODULE_INFO",
        0x6100000F: "SCE_NEEDED_MODULE", 0x61000011: "SCE_MODULE_ATTR",
        0x61000013: "SCE_EXPORT_LIB", 0x61000015: "SCE_IMPORT_LIB",
        0x61000017: "SCE_EXPORT_LIB_ATTR", 0x61000019: "SCE_IMPORT_LIB_ATTR",
        0x6100001D: "SCE_STUB_MODULE_NAME", 0x6100001F: "SCE_STUB_MODULE_VERSION",
        0x61000021: "SCE_STUB_LIBRARY_NAME", 0x61000023: "SCE_STUB_LIBRARY_VERSION",
        0x61000025: "SCE_HASH", 0x61000027: "SCE_PLTGOT", 0x61000029: "SCE_JMPREL",
        0x6100002B: "SCE_PLTREL", 0x6100002D: "SCE_PLTRELSZ", 0x6100002F: "SCE_RELA",
        0x61000031: "SCE_RELASZ", 0x61000033: "SCE_RELAENT", 0x61000035: "SCE_STRTAB",
        0x61000037: "SCE_STRSZ", 0x61000039: "SCE_SYMTAB", 0x6100003B: "SCE_SYMENT",
        0x6100003D: "SCE_HASHSZ", 0x6100003F: "SCE_SYMTABSZ",
    ]

    /// The file bytes.
    public let data: ByteSpan

    /// The SELF segment table.
    public let selfSegments: [SelfSegment]

    /// File offset of the embedded ELF header (`0x20 + 0x20 * segments`; 0x160 in the retail file).
    public let elfOffset: Int

    /// The ELF entry point VA.
    public let entry: UInt64

    /// The ELF program headers.
    public let programHeaders: [ProgramHeader]

    /// The entries of PT_DYNAMIC up to and including the terminating tag 0.
    public private(set) var dynamicEntries: [DynamicEntry]

    /// The loaded segments (type LOAD and SCE_RELRO) in program-header order.
    public let loadSegments: [LoadSegment]

    /// The first LOAD segment with the execute flag (text and read-only data); the first LOAD, or an
    /// empty header, when the ELF has no executable segment.
    public let text: ProgramHeader

    /// The first LOAD segment with the write flag (data and bss); the first LOAD, or an empty header,
    /// when the ELF has no writable segment.
    public let dataSegment: ProgramHeader

    /// The SCE_RELRO segment, or nil.
    public let relro: ProgramHeader?

    private init(
        data: ByteSpan, selfSegments: [SelfSegment], elfOffset: Int, entry: UInt64,
        programHeaders: [ProgramHeader], dynamicEntries: [DynamicEntry] = []
    ) {
        self.data = data
        self.selfSegments = selfSegments
        self.elfOffset = elfOffset
        self.entry = entry
        self.programHeaders = programHeaders
        self.dynamicEntries = dynamicEntries

        let loaded = programHeaders.filter { $0.type == Self.ptLoad || $0.type == Self.ptSceRelro }
        self.loadSegments = loaded.map { ph in
            let fo = Self.fileOffset(of: ph, in: selfSegments)
            var bytes: ByteSpan?
            if let fo, let size = Int(exactly: ph.fileSize), size >= 0, fo >= 0, fo <= data.count - size {
                bytes = data.slice(fo, size)
            }
            return LoadSegment(header: ph, fileOffset: fo, bytes: bytes)
        }
        self.text = programHeaders.first { $0.type == Self.ptLoad && $0.flags & 1 != 0 }
            ?? programHeaders.first { $0.type == Self.ptLoad }
            ?? programHeaders.first
            ?? .empty
        self.dataSegment = programHeaders.first { $0.type == Self.ptLoad && $0.flags & 2 != 0 }
            ?? programHeaders.first { $0.type == Self.ptLoad }
            ?? programHeaders.first
            ?? .empty
        self.relro = programHeaders.first { $0.type == Self.ptSceRelro }
    }

    /// The name of a program header type, or its hex value.
    public static func programHeaderTypeName(_ type: UInt32) -> String {
        typeNames[type] ?? "0x" + String(type, radix: 16)
    }

    /// The name of a dynamic tag, or its hex value.
    public static func dynamicTagName(_ tag: UInt64) -> String {
        dynamicNames[tag] ?? "0x" + String(tag, radix: 16)
    }

    /// Decodes the library or module id of an import name (base 64 digits, most significant first).
    public static func decodeId(_ s: String) throws -> Int {
        var value: Int64 = 0
        for ch in s {
            guard let index = idAlphabet.firstIndex(of: ch) else {
                throw TsukiError.format("bad id character '\(ch)' in \"\(s)\"")
            }
            let digit = Int64(idAlphabet.distance(from: idAlphabet.startIndex, to: index))
            let (scaled, scaleOverflow) = value.multipliedReportingOverflow(by: 64)
            let (next, addOverflow) = scaled.addingReportingOverflow(digit)
            guard !scaleOverflow, !addOverflow, next <= Int64(Int32.max) else {
                throw TsukiError.format("id \"\(s)\" does not fit 32 bits")
            }
            value = next
        }
        return Int(value)
    }

    /// Parses a SELF file: the segment table, the ELF header and program headers and the dynamic table.
    /// - Parameter data: The whole file; it must stay unchanged while the image is in use.
    /// - Throws: `TsukiError.format` when the file is not a plain SELF with an ELF64 image.
    public static func parse(_ data: ByteSpan) throws -> SelfImage {
        guard data.count >= 0x20, data.count >= 4, Array(data.slice(0, 4)) == magic else {
            let found = hexLower(data.slice(0, min(4, data.count)).toArray()).uppercased()
            throw TsukiError.format("not a SELF (magic \(found))")
        }

        let nseg = Int(data.u16(0x18))
        guard 0x20 + nseg * 0x20 <= data.count else {
            throw TsukiError.format("SELF segment table of \(nseg) entries runs past the end of the file")
        }

        var segments: [SelfSegment] = []
        segments.reserveCapacity(nseg)
        for i in 0..<nseg {
            let e = data.slice(0x20 + i * 0x20, 0x20)
            segments.append(SelfSegment(index: i, flags: e.u64(0), offset: e.u64(8), compSize: e.u64(16), decSize: e.u64(24)))
        }

        let elfOffset = 0x20 + nseg * 0x20
        let elfMagic: [UInt8] = [0x7F, 0x45, 0x4C, 0x46]
        guard elfOffset + 0x40 <= data.count, Array(data.slice(elfOffset, 4)) == elfMagic else {
            throw TsukiError.format("no ELF header at 0x\(String(elfOffset, radix: 16))")
        }

        let entry = data.u64(elfOffset + 0x18)
        let phoff = data.u64(elfOffset + 0x20)
        let phentsize = Int(data.u16(elfOffset + 0x36))
        let phnum = Int(data.u16(elfOffset + 0x38))
        guard phentsize >= 56 || phnum == 0 else {
            throw TsukiError.format("ELF program header size \(phentsize) is smaller than 56")
        }

        var headers: [ProgramHeader] = []
        headers.reserveCapacity(phnum)
        for i in 0..<phnum {
            let (base, baseOverflow) = UInt64(elfOffset).addingReportingOverflow(phoff)
            let (stepped, stepOverflow) = base.addingReportingOverflow(UInt64(i) * UInt64(phentsize))
            let (limit, limitOverflow) = stepped.addingReportingOverflow(56)
            guard !baseOverflow, !stepOverflow, !limitOverflow, limit <= UInt64(data.count), let at = Int(exactly: stepped) else {
                throw TsukiError.format("ELF program header \(i) runs past the end of the file")
            }
            let p = data.slice(at, 56)
            headers.append(ProgramHeader(
                index: i, type: p.u32(0), flags: p.u32(4), offset: p.u64(8), vAddr: p.u64(16),
                pAddr: p.u64(24), fileSize: p.u64(32), memSize: p.u64(40), align: p.u64(48)))
        }

        for segment in segments where segment.blocked && (segment.deflated || segment.encrypted) {
            throw TsukiError.format("segment \(segment.index) is compressed or encrypted; a decrypted SELF is required")
        }

        let image = SelfImage(
            data: data, selfSegments: segments, elfOffset: elfOffset, entry: entry, programHeaders: headers)
        image.dynamicEntries = try image.parseDynamic()
        return image
    }

    // MARK: - Mapping

    private static func fileOffset(of ph: ProgramHeader, in segments: [SelfSegment]) -> Int? {
        for segment in segments where segment.blocked && segment.phdrId == ph.index {
            return Int(exactly: segment.offset)
        }
        return nil
    }

    /// SELF file offset where the file bytes of `ph` start, or nil if no blocked segment holds them.
    public func phdrFileOffset(_ ph: ProgramHeader) -> Int? {
        Self.fileOffset(of: ph, in: selfSegments)
    }

    /// Maps an ELF file offset to a SELF file offset.
    public func elfToFile(_ elfOffset: UInt64) throws -> Int {
        for ph in programHeaders {
            let (end, overflow) = ph.offset.addingReportingOverflow(ph.fileSize)
            guard !overflow, ph.fileSize != 0, ph.offset <= elfOffset, elfOffset < end else { continue }
            guard let base = phdrFileOffset(ph) else { continue }
            guard let delta = Int(exactly: elfOffset - ph.offset) else {
                throw TsukiError.format("ELF offset 0x\(String(elfOffset, radix: 16)) is outside the file")
            }
            let (result, sumOverflow) = base.addingReportingOverflow(delta)
            guard !sumOverflow else {
                throw TsukiError.format("ELF offset 0x\(String(elfOffset, radix: 16)) is outside the file")
            }
            return result
        }
        throw TsukiError.format("ELF offset 0x\(String(elfOffset, radix: 16)) is not backed by a SELF segment")
    }

    /// The SELF file offset of a VA inside the file image of a loaded segment, or nil for a VA in .bss
    /// or outside every segment.
    public func vaToFile(_ va: Int) -> Int? {
        guard let address = UInt64(exactly: va) else { return nil }
        for segment in loadSegments {
            let ph = segment.header
            let (end, overflow) = ph.vAddr.addingReportingOverflow(ph.fileSize)
            if !overflow, ph.vAddr <= address, address < end {
                guard let base = segment.fileOffset, let delta = Int(exactly: address - ph.vAddr) else { return nil }
                return base + delta
            }
        }
        return nil
    }

    /// The loaded segment whose memory image (file part and bss) contains `va`, or nil.
    public func segmentOf(_ va: Int) -> ProgramHeader? {
        guard let address = UInt64(exactly: va) else { return nil }
        for segment in loadSegments {
            let ph = segment.header
            let (end, overflow) = ph.vAddr.addingReportingOverflow(ph.memSize)
            if !overflow, ph.vAddr <= address, address < end {
                return ph
            }
        }
        return nil
    }

    /// Reads `n` bytes at a VA; bytes in .bss (beyond the segment's file size) read as zero.
    public func readVa(_ va: Int, _ n: Int) throws -> [UInt8] {
        guard n >= 0 else { throw TsukiError.bounds("negative read of \(n) bytes at 0x\(String(va, radix: 16))") }
        guard let ph = segmentOf(va), let address = UInt64(exactly: va) else {
            throw TsukiError.format("VA 0x\(String(va, radix: 16)) not mapped")
        }

        var result = [UInt8](repeating: 0, count: n)
        let (fileEnd, overflow) = ph.vAddr.addingReportingOverflow(ph.fileSize)
        let available = overflow || address >= fileEnd ? 0 : Int(min(UInt64(n), fileEnd - address))
        if available > 0 {
            guard let fileOffset = vaToFile(va) else {
                throw TsukiError.format("VA 0x\(String(va, radix: 16)) has no file bytes")
            }
            guard fileOffset >= 0, fileOffset <= data.count - available else {
                throw TsukiError.format("range 0x\(String(fileOffset, radix: 16))+0x\(String(available, radix: 16)) is outside the file")
            }
            data.withUnsafeBytes { source in
                result.withUnsafeMutableBytes { destination in
                    destination.baseAddress!.copyMemory(
                        from: source.baseAddress!.advanced(by: fileOffset), byteCount: available)
                }
            }
        }
        return result
    }

    /// Reads a little-endian u64 at a VA.
    public func u64(_ va: Int) throws -> UInt64 { ByteSpan(try readVa(va, 8)).u64(0) }

    /// Reads a little-endian u32 at a VA.
    public func u32(_ va: Int) throws -> UInt32 { ByteSpan(try readVa(va, 4)).u32(0) }

    /// The bytes of the NUL-terminated string at a VA (at most `limit` bytes, without the NUL); empty
    /// if the VA has no file bytes (.bss or unmapped).
    public func cString(_ va: Int, limit: Int = 4096) -> [UInt8] {
        guard let start = vaToFile(va), start >= 0, start <= data.count else { return [] }
        let count = max(0, min(limit, data.count - start))
        guard count > 0 else { return [] }
        let window = data.slice(start, count)
        var end = window.count
        for i in 0..<window.count where window[i] == 0 {
            end = i
            break
        }
        return window.slice(0, end).toArray()
    }

    /// The file bytes of a loaded segment.
    public func segmentBytes(_ ph: ProgramHeader) throws -> ByteSpan {
        guard let base = phdrFileOffset(ph) else {
            throw TsukiError.format("phdr \(ph.index) has no SELF data")
        }
        guard let size = Int(exactly: ph.fileSize), size >= 0, base >= 0, base <= data.count - size else {
            throw TsukiError.format("phdr \(ph.index) bytes are outside the file")
        }
        return data.slice(base, size)
    }

    // MARK: - Dynamic table

    /// Values of every dynamic entry with `tag`.
    public func dyn(_ tag: UInt64) -> [UInt64] {
        dynamicEntries.filter { $0.tag == tag }.map(\.value)
    }

    /// The value of the only dynamic entry with `tag`.
    public func dyn1(_ tag: UInt64) throws -> UInt64 {
        let values = dyn(tag)
        guard values.count == 1 else {
            throw TsukiError.format("dynamic tag \(Self.dynamicTagName(tag)): \(values.count) entries")
        }
        return values[0]
    }

    /// The SELF file offset of PT_SCE_DYNLIBDATA (strings, symbols, relocations).
    public func dynlibFile() throws -> Int {
        guard let ph = programHeaders.first(where: { $0.type == Self.ptSceDynlibData }) else {
            throw TsukiError.format("no SCE_DYNLIBDATA")
        }
        if let fileOffset = phdrFileOffset(ph) {
            return fileOffset
        }
        return try elfToFile(ph.offset)
    }

    /// A string of the dynamic string table, as ASCII (other bytes become U+FFFD).
    public func dynStr(_ offset: UInt64) throws -> String {
        let table = try dyn1(Self.dtSceStrtab)
        guard let base = Int(exactly: table), let at = Int(exactly: offset) else {
            throw TsukiError.format("dynamic string offset is outside the file")
        }
        let (offsetSum, offsetOverflow) = base.addingReportingOverflow(at)
        guard !offsetOverflow else { throw TsukiError.format("dynamic string offset is outside the file") }
        let (start, overflow) = (try dynlibFile()).addingReportingOverflow(offsetSum)
        guard !overflow, start >= 0, start <= data.count else {
            throw TsukiError.format("dynamic string at 0x\(String(offsetSum, radix: 16)) is outside the file")
        }
        let rest = data.suffix(from: start)
        var end = rest.count
        for i in 0..<rest.count where rest[i] == 0 {
            end = i
            break
        }
        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(end)
        for i in 0..<end {
            let byte = rest[i]
            scalars.append(byte < 0x80 ? UnicodeScalar(byte) : UnicodeScalar(UInt32(0xFFFD))!)
        }
        return String(scalars)
    }

    /// The needed modules by id (`DT_SCE_NEEDED_MODULE`), in table order.
    public func modules() throws -> [ModuleRef] {
        var byId: [Int: Int] = [:]
        var list: [ModuleRef] = []
        for value in dyn(Self.dtSceNeededModule) {
            let id = Int((value >> 48) & 0xFFFF)
            let module = ModuleRef(
                id: id, name: try dynStr(value & 0xFFFF_FFFF),
                versionMajor: Int((value >> 40) & 0xFF), versionMinor: Int((value >> 32) & 0xFF))
            if let at = byId[id] {
                list[at] = module
            } else {
                byId[id] = list.count
                list.append(module)
            }
        }
        return list
    }

    /// The imported libraries by id (`DT_SCE_IMPORT_LIB` with `DT_SCE_IMPORT_LIB_ATTR`), in table order.
    public func libraries() throws -> [LibraryRef] {
        var byId: [Int: Int] = [:]
        var list: [LibraryRef] = []
        for value in dyn(Self.dtSceImportLib) {
            let id = Int((value >> 48) & 0xFFFF)
            let library = LibraryRef(id: id, name: try dynStr(value & 0xFFFF_FFFF), version: Int((value >> 32) & 0xFFFF), attr: nil)
            if let at = byId[id] {
                list[at] = library
            } else {
                byId[id] = list.count
                list.append(library)
            }
        }
        for value in dyn(Self.dtSceImportLibAttr) {
            let id = Int((value >> 48) & 0xFFFF)
            if let at = byId[id] {
                list[at] = LibraryRef(id: list[at].id, name: list[at].name, version: list[at].version, attr: value & 0xFFFF_FFFF_FFFF)
            }
        }
        return list
    }

    /// The module name and the version word (`DT_SCE_MODULE_INFO`).
    public func moduleInfo() throws -> (name: String, version: UInt64) {
        let value = try dyn1(Self.dtSceModuleInfo)
        return (try dynStr(value & 0xFFFF_FFFF), value >> 32)
    }

    /// The dynamic symbol table.
    public func symbols() throws -> [ElfSymbol] {
        let symbolTable = try dyn1(Self.dtSceSymtab)
        let bytes = try dyn1(Self.dtSceSymtabSz)
        guard let tableOffset = Int(exactly: symbolTable), let count = Int(exactly: bytes / 24),
              let length = Int(exactly: UInt64(count) * 24) else {
            throw TsukiError.format("symbol table of \(bytes) bytes is too large")
        }
        let (baseOffset, offsetOverflow) = (try dynlibFile()).addingReportingOverflow(tableOffset)
        guard !offsetOverflow else { throw TsukiError.format("symbol table is outside the file") }
        let table = try slice(baseOffset, length)
        var list: [ElfSymbol] = []
        list.reserveCapacity(count)
        for i in 0..<count {
            let e = table.slice(i * 24, 24)
            list.append(ElfSymbol(
                index: i, name: try dynStr(UInt64(e.u32(0))), info: e.u8(4), other: e.u8(5),
                shndx: e.u16(6), value: e.u64(8), size: e.u64(16)))
        }
        return list
    }

    /// The PLT relocations (`DT_SCE_JMPREL`).
    public func jmpRel() throws -> [Relocation] { try relas(Self.dtSceJmprel, Self.dtScePltrelSz) }

    /// The relocations of `DT_SCE_RELA` (39,836 in the retail file). Empty when the dynamic table is
    /// unreadable, the shape UiText and the locator need.
    public func rela() -> [Relocation] { (try? relas(Self.dtSceRela, Self.dtSceRelaSz)) ?? [] }

    /// All imported symbols with their GOT slot: first the PLT relocations (functions), then the symbol
    /// relocations of `DT_SCE_RELA` (data imports).
    public func imports() throws -> [ImportedSymbol] {
        let symbols = try symbols()
        var librariesById: [Int: LibraryRef] = [:]
        for library in try libraries() { librariesById[library.id] = library }
        var modulesById: [Int: ModuleRef] = [:]
        for module in try modules() { modulesById[module.id] = module }

        var seen: Set<SeenImport> = []
        var list: [ImportedSymbol] = []
        let relocations = try jmpRel() + (rela().filter { $0.sym != 0 })
        for relocation in relocations {
            let index = Int(relocation.sym)
            guard index >= 0, index < symbols.count else {
                throw TsukiError.format("relocation references symbol \(index) of \(symbols.count)")
            }
            let symbol = symbols[index]
            if !symbol.name.contains("#") || symbol.shndx != 0 {
                continue
            }
            let parts = symbol.name.components(separatedBy: "#")
            guard parts.count == 3 else {
                throw TsukiError.format("import symbol name \"\(symbol.name)\" is not NID#library#module")
            }
            let libraryId = try Self.decodeId(parts[1])
            let moduleId = try Self.decodeId(parts[2])
            guard seen.insert(SeenImport(sym: relocation.sym, offset: relocation.offset)).inserted else {
                continue
            }
            list.append(ImportedSymbol(
                symIndex: index,
                nid: parts[0],
                library: librariesById[libraryId]?.name ?? "lib#\(libraryId)",
                module: modulesById[moduleId]?.name ?? "mod#\(moduleId)",
                libId: libraryId,
                modId: moduleId,
                symType: symbol.type,
                gotVa: relocation.offset,
                relocType: relocation.type))
        }
        return list
    }

    /// Finds the PLT stubs (`FF 25 disp32`, `jmp [rip+disp]`) whose target is the GOT slot of a
    /// jump-slot import and stores their VA in `pltVa`; returns how many were found.
    @discardableResult
    public func findPlt(_ imports: [ImportedSymbol]) throws -> Int {
        let text = self.text
        let code = try segmentBytes(text)
        var byGot: [UInt64: ImportedSymbol] = [:]
        for symbol in imports where symbol.relocType == Self.rX86JumpSlot {
            byGot[symbol.gotVa] = symbol
        }

        let pattern: [UInt8] = [0xFF, 0x25]
        var found = 0
        var position = Self.indexOf(pattern, in: code, from: 0)
        while position >= 0 {
            if position + 6 <= code.count {
                let displacement = code.i32(position + 2)
                let target = text.vAddr &+ UInt64(position) &+ 6 &+ UInt64(bitPattern: Int64(displacement))
                if let symbol = byGot[target], symbol.pltVa == nil {
                    symbol.pltVa = text.vAddr &+ UInt64(position)
                    found += 1
                }
            }
            let next = Self.indexOf(pattern, in: code, from: position + 1)
            position = next
        }
        return found
    }

    // MARK: - Internals

    private struct SeenImport: Hashable {
        let sym: Int32
        let offset: UInt64
    }

    private func slice(_ offset: Int, _ length: Int) throws -> ByteSpan {
        guard offset >= 0, length >= 0, offset <= data.count, length <= data.count - offset else {
            throw TsukiError.format(
                "range 0x\(String(offset, radix: 16))+0x\(String(length, radix: 16)) is outside the file (size 0x\(String(data.count, radix: 16)))")
        }
        return data.slice(offset, length)
    }

    private func parseDynamic() throws -> [DynamicEntry] {
        guard let ph = programHeaders.first(where: { $0.type == Self.ptDynamic }) else { return [] }
        let fo = try elfToFile(ph.offset)
        var list: [DynamicEntry] = []
        var i: UInt64 = 0
        while i < ph.fileSize / 16 {
            let (step, stepOverflow) = i.multipliedReportingOverflow(by: 16)
            guard !stepOverflow, let delta = Int(exactly: step) else {
                throw TsukiError.format("dynamic entry \(i) is outside the file")
            }
            let (at, overflow) = fo.addingReportingOverflow(delta)
            guard !overflow else { throw TsukiError.format("dynamic entry \(i) is outside the file") }
            let e = try slice(at, 16)
            let tag = e.u64(0)
            list.append(DynamicEntry(tag: tag, value: e.u64(8)))
            if tag == 0 { break }
            i += 1
        }
        return list
    }

    private func relas(_ offsetTag: UInt64, _ sizeTag: UInt64) throws -> [Relocation] {
        let tableOffset = try dyn1(offsetTag)
        let size = try dyn1(sizeTag)
        guard let offset = Int(exactly: tableOffset), let count = Int(exactly: size / 24),
              let length = Int(exactly: UInt64(count) * 24) else {
            throw TsukiError.format("relocation table of \(size) bytes is too large")
        }
        let (baseOffset, offsetOverflow) = (try dynlibFile()).addingReportingOverflow(offset)
        guard !offsetOverflow else { throw TsukiError.format("relocation table is outside the file") }
        let table = try slice(baseOffset, length)
        var list: [Relocation] = []
        list.reserveCapacity(count)
        for i in 0..<count {
            let e = table.slice(i * 24, 24)
            let info = e.u64(8)
            list.append(Relocation(
                offset: e.u64(0),
                sym: Int32(bitPattern: UInt32(truncatingIfNeeded: info >> 32)),
                type: UInt32(truncatingIfNeeded: info),
                addend: e.i64(16)))
        }
        return list
    }

    private static func indexOf(_ needle: [UInt8], in hay: ByteSpan, from start: Int) -> Int {
        guard !needle.isEmpty, start >= 0, hay.count >= needle.count, start <= hay.count - needle.count else { return -1 }
        var i = start
        while i <= hay.count - needle.count {
            var k = 0
            while k < needle.count, hay[i + k] == needle[k] { k += 1 }
            if k == needle.count { return i }
            i += 1
        }
        return -1
    }
}
