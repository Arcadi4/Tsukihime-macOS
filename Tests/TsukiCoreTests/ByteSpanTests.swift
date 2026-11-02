import XCTest
@testable import TsukiCore

final class ByteSpanTests: XCTestCase {
    func testLittleEndianReads() {
        let bytes: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
        let span = ByteSpan(bytes)
        XCTAssertEqual(span.u16(0), 0x0201)
        XCTAssertEqual(span.u32(0), 0x0403_0201)
        XCTAssertEqual(span.u64(0), 0x0807_0605_0403_0201)
        XCTAssertEqual(span.u32be(0), 0x0102_0304)
    }

    func testSlicesAreViews() {
        let bytes: [UInt8] = Array(0..<16)
        let span = ByteSpan(bytes).slice(4, 8)
        XCTAssertEqual(span.count, 8)
        XCTAssertEqual(span[0], 4)
        XCTAssertEqual(span[7], 11)
        XCTAssertEqual(span.slice(2, 2).toArray(), [6, 7])
    }

    func testWindowReflectsStorage() {
        let storage = ByteStorage(count: 8)
        let window = ByteWindow(storage: storage, offset: 2, length: 4)
        window.setU16(0, 0xBEEF)
        let span = window.span
        XCTAssertEqual(span.u16(0), 0xBEEF)
        window.setBit(3, true)
        XCTAssertTrue(window.getBit(3))
        XCTAssertEqual(span[0] & 0x08, 0x08)
    }

    func testWriterRoundTrip() {
        var writer = ByteWriter()
        writer.u8(0xAA)
        writer.u16(0x1234)
        writer.u32(0xDEAD_BEEF)
        writer.i32(-2)
        let span = ByteSpan(writer.bytes)
        XCTAssertEqual(span.u8(0), 0xAA)
        XCTAssertEqual(span.u16(1), 0x1234)
        XCTAssertEqual(span.u32(3), 0xDEAD_BEEF)
        XCTAssertEqual(span.i32(7), -2)
    }

    func testCursorBounds() throws {
        var cursor = ByteCursor(ByteSpan([1, 2, 3]))
        XCTAssertEqual(try cursor.u16(), 0x0201)
        XCTAssertThrowsError(try cursor.u32())
        XCTAssertEqual(try cursor.u8(), 3)
        XCTAssertTrue(cursor.isAtEnd)
    }

    func testMappedFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tsuki-core-mapped.bin")
        let bytes = (0..<4096).map { UInt8($0 & 0xFF) }
        try Data(bytes).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let file = try MappedFile(path: url.path)
        XCTAssertEqual(file.length, 4096)
        let view = try file.span(offset: 16, length: 4)
        XCTAssertEqual(view.toArray(), [16, 17, 18, 19])
        XCTAssertEqual(view.u32(0), 0x1312_1110)
        file.dispose()
    }
}
