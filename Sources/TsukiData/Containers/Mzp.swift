import Foundation
import TsukiCore
import TsukiEngine

/// Constants shared by HED records and mrgd00 section records.
public enum Mzp {
    /// The sector size of every archive.
    public static let sector = 0x800

    /// The six bytes at the start of an mrgd00 container.
    public static let magic: [UInt8] = Array("mrgd00".utf8)

    /// Exact byte size from the sector count and the low 16 bits:
    /// `size = (cap & ~0xFFFF) | lo`, minus 0x10000 when that exceeds `cap = sectors * 0x800`.
    public static func decodeSize(sectors: Int, low: Int) -> Int {
        let cap = sectors * sector
        var size = (cap & ~0xFFFF) | (low & 0xFFFF)
        if size > cap { size -= 0x10000 }
        return size
    }

    /// The 1...8 bytes of 0xFF the packer puts after a section ending at `end`.
    public static func padAfter(_ end: Int) -> Int {
        8 - (end % 8)
    }

    public static func isContainer(_ data: ByteSpan) -> Bool {
        data.count >= 8 && data.slice(0, 6).elementsEqual(magic)
    }
}

/// One section record of an mrgd00 container.
public struct MzpSection: Equatable {
    public let index: Int
    public let sectorOffset: Int
    public let byteOffsetWord: Int
    public let sizeSectors: Int
    public let sizeLow: Int
    /// Byte offset of the section data relative to the container start.
    public let offset: Int
    /// Exact byte size.
    public let size: Int

    public var inSectorOffset: Int { byteOffsetWord & 0x0FFF }
    public var end: Int { offset + size }
}

/// An mrgd00 container: a header, a section table, and section data. Sections are zero-copy views
/// of the container window.
public struct MzpContainer {
    public let data: ByteSpan
    public let dataStart: Int
    public let sections: [MzpSection]

    public var count: Int { sections.count }

    /// End of the last section's data relative to the container start.
    public var end: Int {
        sections.reduce(dataStart) { max($0, $1.end) }
    }

    /// Size including the trailing 0xFF pad; this is what a HED8 size field holds.
    public var packedSize: Int {
        let e = end
        return e + Mzp.padAfter(e)
    }

    public static func parse(_ data: ByteSpan) throws -> MzpContainer {
        guard data.count >= 8 else {
            throw TsukiError.format("container window of \(data.count) bytes is shorter than its header")
        }
        guard Mzp.isContainer(data) else {
            throw TsukiError.format("bad magic \(hex(data.slice(0, 6))) (expected mrgd00)")
        }
        let count = Int(data.u16(6))
        let dataStart = 8 + 8 * count
        guard dataStart <= data.count else {
            throw TsukiError.format("section table (\(count) records) exceeds container size \(data.count)")
        }
        return MzpContainer(data: data, dataStart: dataStart, sections: try readTable(data, totalLength: data.count))
    }

    /// Reads only the section table, for a reader that has the head of a large container.
    public static func readTable(_ head: ByteSpan, totalLength: Int) throws -> [MzpSection] {
        guard head.count >= 8, Mzp.isContainer(head) else {
            throw TsukiError.format("bad magic (expected mrgd00)")
        }
        let count = Int(head.u16(6))
        let dataStart = 8 + 8 * count
        guard head.count >= dataStart else {
            throw TsukiError.format("section table (\(count) records) is cut off at \(head.count) bytes")
        }
        guard dataStart <= totalLength else {
            throw TsukiError.format("section table (\(count) records) exceeds container size \(totalLength)")
        }

        var sections: [MzpSection] = []
        sections.reserveCapacity(count)
        for i in 0..<count {
            let record = head.slice(8 + 8 * i, 8)
            let sectorOffset = Int(record.u16(0))
            let byteOffset = Int(record.u16(2))
            let sizeSectors = Int(record.u16(4))
            let sizeLow = Int(record.u16(6))
            let offset = dataStart + sectorOffset * Mzp.sector + (byteOffset & 0x0FFF) + ((byteOffset & 0xF000) << 15)
            let size = Mzp.decodeSize(sectors: sizeSectors, low: sizeLow)
            guard offset + size <= totalLength else {
                throw TsukiError.format("section \(i) [0x\(String(offset, radix: 16))+0x\(String(size, radix: 16))] exceeds container size 0x\(String(totalLength, radix: 16))")
            }
            sections.append(MzpSection(index: i, sectorOffset: sectorOffset, byteOffsetWord: byteOffset,
                                       sizeSectors: sizeSectors, sizeLow: sizeLow, offset: offset, size: size))
        }
        return sections
    }

    public func section(_ index: Int) -> ByteSpan {
        let s = sections[index]
        return data.slice(s.offset, s.size)
    }

    public func isNested(_ index: Int) -> Bool {
        let s = sections[index]
        return s.size >= 8 && data.slice(s.offset, 6).elementsEqual(Mzp.magic)
    }

    public func child(_ index: Int) throws -> MzpContainer {
        try MzpContainer.parse(section(index))
    }

    public func head(_ index: Int, count: Int = 16) -> ByteSpan {
        let s = sections[index]
        return data.slice(s.offset, min(count, s.size))
    }

    /// Differences from the packing rule (empty for retail containers).
    public func validate(checkPadding: Bool = true) -> [String] {
        var issues: [String] = []
        var expected = dataStart
        var previousEnd = dataStart
        for s in sections {
            if s.inSectorOffset >= Mzp.sector {
                issues.append("section \(s.index): byte_offset 0x\(String(s.byteOffsetWord, radix: 16)) >= 0x800")
            }
            let touched = (s.inSectorOffset + s.size + Mzp.sector - 1) / Mzp.sector
            if s.sizeSectors != touched {
                issues.append("section \(s.index): size_sectors \(s.sizeSectors) != ceil((byte_offset+size)/0x800)")
            }
            if s.offset != expected {
                issues.append("section \(s.index): offset 0x\(String(s.offset, radix: 16)), expected 0x\(String(expected, radix: 16))")
            } else if checkPadding, s.index > 0 {
                let pad = data.slice(previousEnd, s.offset - previousEnd)
                if pad.contains(where: { $0 != 0xFF }) {
                    issues.append("section \(s.index): padding before it is not 0xFF")
                }
            }
            previousEnd = s.end
            expected = s.end + Mzp.padAfter(s.end)
        }

        if checkPadding, !sections.isEmpty {
            let e = end
            let tailLength = min(Mzp.padAfter(e), data.count - e)
            if tailLength > 0, data.slice(e, tailLength).contains(where: { $0 != 0xFF }) {
                issues.append("trailing pad not 0xFF")
            }
        }
        return issues
    }

    /// SHA-1 of the `offset:size;` pairs, used by the verification tools to compare section tables.
    public func sectionDigest() -> String {
        var text = ""
        for s in sections {
            if !text.isEmpty { text += ";" }
            text += "\(s.offset):\(s.size)"
        }
        return sha1Hex(Array(text.utf8))
    }
}

private func hex(_ span: ByteSpan) -> String {
    span.map { String(format: "%02x", $0) }.joined()
}
