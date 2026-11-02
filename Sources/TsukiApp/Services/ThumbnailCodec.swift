import Foundation
import TsukiEngine
import zlib

/// Encodes and decodes slot thumbnails.
public enum ThumbnailCodec {
    /// Width of a stored thumbnail.
    public static let width = 320

    /// Height of a stored thumbnail.
    public static let height = 180

    /// The format id this code writes.
    public static let format: UInt16 = 1

    /// Packs `rgba` (`width` x `height`, straight alpha) into a slot thumbnail.
    public static func encode(width: Int, height: Int, rgba: [UInt8]) -> SlotThumbnail {
        let needed = width * height * 4
        precondition(rgba.count >= needed, "pixel buffer too small")

        var head = [UInt8](repeating: 0, count: 4)
        let w16 = UInt16(width).littleEndian
        let h16 = UInt16(height).littleEndian
        withUnsafeBytes(of: w16) { head[0] = $0[0]; head[1] = $0[1] }
        withUnsafeBytes(of: h16) { head[2] = $0[0]; head[3] = $0[1] }

        var compressed = compressZlib(rgba, count: needed)
        var result = head
        result.append(contentsOf: compressed)
        return SlotThumbnail(format: format, data: result)
    }

    /// Unpacks a thumbnail; nil when format is not ours or data is damaged.
    public static func decode(_ thumbnail: SlotThumbnail?) -> (width: Int, height: Int, rgba: [UInt8])? {
        guard let t = thumbnail, t.format == format, t.data.count >= 8 else {
            return nil
        }

        let w = Int(UInt16(t.data[0]) | (UInt16(t.data[1]) << 8))
        let h = Int(UInt16(t.data[2]) | (UInt16(t.data[3]) << 8))
        if w <= 0 || h <= 0 || Int64(w) * Int64(h) > Int64(width * height) {
            return nil
        }

        let expectedSize = w * h * 4
        let payload = Array(t.data[4...])
        guard let rgba = decompressZlib(payload, expectedSize: expectedSize) else {
            return nil
        }

        return (w, h, rgba)
    }

    /// Box-filters an RGBA image down to `width` x `height`.
    public static func downscale(_ rgba: [UInt8], width srcWidth: Int, height srcHeight: Int) -> [UInt8] {
        var output = [UInt8](repeating: 0, count: width * height * 4)

        for y in 0..<height {
            let y0 = y * srcHeight / height
            let y1 = max(y0 + 1, (y + 1) * srcHeight / height)

            for x in 0..<width {
                let x0 = x * srcWidth / width
                let x1 = max(x0 + 1, (x + 1) * srcWidth / width)

                var r = 0, g = 0, b = 0, n = 0
                for sy in y0..<y1 {
                    let row = sy * srcWidth * 4
                    for sx in x0..<x1 {
                        let o = row + (sx * 4)
                        r += Int(rgba[o])
                        g += Int(rgba[o + 1])
                        b += Int(rgba[o + 2])
                        n += 1
                    }
                }

                let d = ((y * width) + x) * 4
                output[d] = UInt8(r / n)
                output[d + 1] = UInt8(g / n)
                output[d + 2] = UInt8(b / n)
                output[d + 3] = 255
            }
        }

        return output
    }

    private static func compressZlib(_ data: [UInt8], count: Int) -> [UInt8] {
        var stream = z_stream()
        guard deflateInit_(&stream, Z_DEFAULT_COMPRESSION, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            return []
        }
        defer { deflateEnd(&stream) }

        let bufferSize = max(16384, count + 64)
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var result = [UInt8]()
        data.withUnsafeBytes { inBytes in
            stream.next_in = UnsafeMutablePointer<UInt8>(mutating: inBytes.bindMemory(to: UInt8.self).baseAddress)
            stream.avail_in = uInt(count)

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

    private static func decompressZlib(_ data: [UInt8], expectedSize: Int) -> [UInt8]? {
        var stream = z_stream()
        guard inflateInit_(&stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            return nil
        }
        defer { inflateEnd(&stream) }

        var result = [UInt8](repeating: 0, count: expectedSize)
        var ret: Int32 = 0
        data.withUnsafeBytes { inBytes in
            stream.next_in = UnsafeMutablePointer<UInt8>(mutating: inBytes.bindMemory(to: UInt8.self).baseAddress)
            stream.avail_in = uInt(data.count)

            result.withUnsafeMutableBytes { outBytes in
                stream.next_out = outBytes.bindMemory(to: UInt8.self).baseAddress
                stream.avail_out = uInt(expectedSize)
                ret = inflate(&stream, Z_FINISH)
            }
        }
        return (ret == Z_STREAM_END || stream.avail_out == 0) ? result : nil
    }
}
