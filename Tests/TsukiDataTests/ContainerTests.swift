import XCTest
@testable import TsukiCore
@testable import TsukiData

final class ContainerTests: XCTestCase {
    private func hed8(_ records: [(offset: Int, sectors: Int, size: Int)]) -> [UInt8] {
        var writer = ByteWriter()
        for r in records {
            let field = UInt32(r.offset & 0xFFFF) | UInt32((r.offset >> 16) & 0xF) << 28
            writer.u32(field)
            writer.u16(UInt16(r.sectors))
            writer.u16(UInt16(r.size))
        }
        return writer.bytes
    }

    func testHed8RoundTrip() throws {
        let bytes = hed8([(0, 2, 0x0FFF), (2, 1, 0x0800)])
        let table = try HedTable.parse(ByteSpan(bytes))
        XCTAssertEqual(table.format, .hed8)
        XCTAssertEqual(table.entries.count, 2)
        XCTAssertEqual(table.entries[0].offset, 0)
        XCTAssertEqual(table.entries[0].size, 0x0FFF)
        XCTAssertEqual(table.entries[1].offset, 0x1000)
        XCTAssertTrue(table.contiguous)
    }

    func testNam8Parsing() throws {
        var writer = ByteWriter()
        writer.raw(Array("ABC".utf8) + [0, 0, 0, 0, 0])
        writer.raw(Array("DUMMY".utf8) + [0, 0, 0])
        let table = try NamTable.parse(ByteSpan(writer.bytes))
        XCTAssertEqual(table.recordSize, 8)
        XCTAssertEqual(table.names, ["ABC", "DUMMY"])
    }

    func testMzpSections() throws {
        var writer = ByteWriter()
        writer.raw(Array("mrgd00".utf8))
        writer.u16(1)
        // one section: sector offset 0, byte offset 0, 1 sector, low size word 4
        writer.u16(0); writer.u16(0); writer.u16(1); writer.u16(4)
        writer.raw([1, 2, 3, 4])
        let container = try MzpContainer.parse(ByteSpan(writer.bytes))
        XCTAssertEqual(container.count, 1)
        XCTAssertEqual(container.section(0).toArray(), [1, 2, 3, 4])
    }

    func testMzxRoundTrip() throws {
        // Compress a short literal-only stream by hand: one literal command of 4 words, then a run.
        var stream = ByteWriter()
        stream.raw(Array("MZX0".utf8))
        stream.u32(10)
        stream.u8(3 << 2 | 3) // literal, 4 words
        stream.raw([1, 0, 2, 0, 3, 0, 4, 0])
        stream.u8(1 << 2 | 2) // ring word index 1 (the second literal word)
        let decoded = try Mzx.decompress(ByteSpan(stream.bytes))
        XCTAssertEqual(decoded.toArray(), [1, 0, 2, 0, 3, 0, 4, 0, 2, 0])
    }
}
