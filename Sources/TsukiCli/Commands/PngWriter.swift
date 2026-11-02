import Foundation
import zlib
import TsukiCore

public enum PngWriter {
    public static func write(_ path: String, width: Int, height: Int, rgba: [UInt8]) throws {
        try rgba.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            try write(path, width: width, height: height, rgba: base, count: rgba.count)
        }
    }

    public static func write(_ path: String, width: Int, height: Int, rgba: UnsafePointer<UInt8>, count: Int) throws {
        guard count >= width * height * 4 else {
            throw TsukiError.format("not enough pixels")
        }

        let stride = width * 4
        var raw = [UInt8](repeating: 0, count: height * (stride + 1))
        var offset = 0
        for y in 0..<height {
            raw[offset] = 0 // filter none
            offset += 1
            let srcOffset = y * stride
            raw.replaceSubrange(offset..<(offset + stride), with: UnsafeBufferPointer(start: rgba.advanced(by: srcOffset), count: stride))
            offset += stride
        }

        var destLen = uLongf(compressBound(uLong(raw.count)))
        var compressed = [UInt8](repeating: 0, count: Int(destLen))
        let res = compress(&compressed, &destLen, raw, uLong(raw.count))
        guard res == Z_OK else {
            throw TsukiError.format("zlib compression failed: \(res)")
        }

        var pngData = Data()
        pngData.append(contentsOf: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        var ihdr = [UInt8](repeating: 0, count: 13)
        writeBe(&ihdr, 0, UInt32(width))
        writeBe(&ihdr, 4, UInt32(height))
        ihdr[8] = 8 // bit depth
        ihdr[9] = 6 // color type RGBA
        chunk(&pngData, "IHDR", ihdr)
        chunk(&pngData, "IDAT", Array(compressed.prefix(Int(destLen))))
        chunk(&pngData, "IEND", [])

        try pngData.write(to: URL(fileURLWithPath: path))
    }

    private static func chunk(_ s: inout Data, _ type: String, _ data: [UInt8]) {
        var lenBytes = [UInt8](repeating: 0, count: 4)
        writeBe(&lenBytes, 0, UInt32(data.count))
        s.append(contentsOf: lenBytes)

        let typeBytes = Array(type.utf8)
        s.append(contentsOf: typeBytes)
        s.append(contentsOf: data)

        var crc = UInt32(crc32(0, nil, 0))
        crc = UInt32(crc32(uLong(crc), typeBytes, uInt(typeBytes.count)))
        if !data.isEmpty {
            crc = UInt32(crc32(uLong(crc), data, uInt(data.count)))
        }

        var crcBytes = [UInt8](repeating: 0, count: 4)
        writeBe(&crcBytes, 0, crc)
        s.append(contentsOf: crcBytes)
    }

    private static func writeBe(_ b: inout [UInt8], _ o: Int, _ v: UInt32) {
        b[o] = UInt8((v >> 24) & 0xFF)
        b[o + 1] = UInt8((v >> 16) & 0xFF)
        b[o + 2] = UInt8((v >> 8) & 0xFF)
        b[o + 3] = UInt8(v & 0xFF)
    }
}
