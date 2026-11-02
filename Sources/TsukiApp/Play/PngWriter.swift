import Foundation
import zlib

/// A minimal PNG writer for screenshots (RGBA8, no filter, zlib).
public enum PngWriter {
    private static let table: [UInt32] = buildTable()

    public static func write(path: String, width: Int, height: Int, rgba: [UInt8]) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let rowBytes = width * 4
        var raw = [UInt8]()
        raw.reserveCapacity(height * (rowBytes + 1))
        for y in 0..<height {
            raw.append(0) // filter None
            let start = y * rowBytes
            raw.append(contentsOf: rgba[start..<(start + rowBytes)])
        }

        let compressed = compressZlib(raw)

        var fileData = [UInt8]()
        // PNG signature
        fileData.append(contentsOf: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        // IHDR
        var ihdr = [UInt8](repeating: 0, count: 13)
        let w32 = UInt32(width).bigEndian
        let h32 = UInt32(height).bigEndian
        withUnsafeBytes(of: w32) { ihdr[0] = $0[0]; ihdr[1] = $0[1]; ihdr[2] = $0[2]; ihdr[3] = $0[3] }
        withUnsafeBytes(of: h32) { ihdr[4] = $0[0]; ihdr[5] = $0[1]; ihdr[6] = $0[2]; ihdr[7] = $0[3] }
        ihdr[8] = 8  // bit depth
        ihdr[9] = 6  // RGBA
        ihdr[10] = 0 // deflate
        ihdr[11] = 0 // filter
        ihdr[12] = 0 // interlace
        appendChunk(to: &fileData, type: [UInt8]("IHDR".utf8), data: ihdr)

        // IDAT
        appendChunk(to: &fileData, type: [UInt8]("IDAT".utf8), data: compressed)

        // IEND
        appendChunk(to: &fileData, type: [UInt8]("IEND".utf8), data: [])

        try Data(fileData).write(to: URL(fileURLWithPath: path))
    }

    private static func appendChunk(to dest: inout [UInt8], type: [UInt8], data: [UInt8]) {
        let len32 = UInt32(data.count).bigEndian
        withUnsafeBytes(of: len32) { dest.append(contentsOf: $0) }
        dest.append(contentsOf: type)
        dest.append(contentsOf: data)

        var crc: UInt32 = 0xFFFFFFFF
        for b in type {
            crc = table[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8)
        }
        for b in data {
            crc = table[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8)
        }
        let finalCrc = (~crc).bigEndian
        withUnsafeBytes(of: finalCrc) { dest.append(contentsOf: $0) }
    }

    private static func compressZlib(_ data: [UInt8]) -> [UInt8] {
        var stream = z_stream()
        guard deflateInit_(&stream, Z_DEFAULT_COMPRESSION, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            return []
        }
        defer { deflateEnd(&stream) }

        let bufferSize = max(16384, data.count + 64)
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var result = [UInt8]()
        data.withUnsafeBytes { inBytes in
            stream.next_in = UnsafeMutablePointer<UInt8>(mutating: inBytes.bindMemory(to: UInt8.self).baseAddress)
            stream.avail_in = uInt(data.count)

            while true {
                stream.next_out = buffer
                stream.avail_out = uInt(bufferSize)

                let ret = deflate(&stream, stream.avail_in == 0 ? Z_FINISH : Z_NO_FLUSH)
                let produced = bufferSize - Int(stream.avail_out)
                if produced > 0 {
                    result.append(contentsOf: UnsafeBufferPointer(start: buffer, count: produced))
                }
                if ret == Z_STREAM_END || (stream.avail_in == 0 && stream.avail_out != 0) {
                    break
                }
            }
        }
        return result
    }

    private static func buildTable() -> [UInt32] {
        var t = [UInt32](repeating: 0, count: 256)
        for n in 0..<256 {
            var c = UInt32(n)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1
            }
            t[n] = c
        }
        return t
    }
}
