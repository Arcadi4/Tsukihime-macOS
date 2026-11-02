import Foundation
import TsukiCore
import TsukiEngine

/// Which instruction set `TileConverter.rgb565LoAToRgba` uses (tests compare the three).
///
/// The C# reference has one loop per width; all of them produce the same bytes. The Swift port keeps a
/// single portable loop, so every level yields identical pixels.
public enum SimdLevel: Sendable {
    /// The widest vectors the machine accelerates.
    case auto

    /// One pixel at a time.
    case scalar

    /// 128-bit vectors, 8 pixels per step.
    case vector128

    /// 256-bit vectors, 16 pixels per step.
    case vector256
}

/// Decompressed tile bytes to straight-alpha RGBA8 (docs/formats/images.md 3-5): the output of the
/// engine's tile upload (VA 0xD6900, 0xD7040, 0xD5970) in the byte order R, G, B, A, which is also
/// `tsuki.image.decode_tile`.
public enum TileConverter {
    /// Converts one decompressed tile to RGBA8, `tileWidth x tileHeight x 4` bytes top-down, border
    /// included.
    ///
    /// - Parameters:
    ///   - header: The image header (format, tile size, palette).
    ///   - raw: The decompressed tile stream, at least `header.tileBytes` bytes.
    ///   - rgba: At least `header.tileRgbaBytes` bytes.
    ///   - simd: The vector width for RGB565+LO+A; `.auto` outside tests.
    public static func convert(
        _ header: ImageHeader, raw: ByteSpan, rgba: inout [UInt8], simd: SimdLevel = .auto
    ) throws {
        let n = header.tilePixels
        guard raw.count >= header.tileBytes else {
            throw TsukiError.format(
                "tile data is \(raw.count) bytes, \(header.format) needs \(header.tileBytes)")
        }

        guard rgba.count >= 4 * n else {
            throw TsukiError.bounds(
                "output of \(rgba.count) bytes is smaller than a \(header.tileWidth)x\(header.tileHeight) RGBA tile")
        }

        try rgba.withUnsafeMutableBytes { dst in
            switch header.format {
            case .hep8:
                try checkHep(header, raw)
                withUnsafeTemporaryAllocation(of: UInt32.self, capacity: 256) { palette in
                    hepPalette(raw.slice(ImageHeader.hepHeaderSize + n, 256 * 4), into: palette)
                    expand8(
                        raw.slice(ImageHeader.hepHeaderSize, n), palette: UnsafeBufferPointer(palette),
                        count: n, into: dst)
                }
            case .pal8:
                guard let palette = header.palette else {
                    throw TsukiError.format("pal8 tile has no header palette")
                }
                palette.withUnsafeBufferPointer { entries in
                    expand8(raw.slice(0, n), palette: entries, count: n, into: dst)
                }
            case .pal4:
                guard let palette = header.palette else {
                    throw TsukiError.format("pal4 tile has no header palette")
                }
                palette.withUnsafeBufferPointer { entries in
                    expand4(raw, palette: entries, count: n, into: dst)
                }
            case .rgb565LoA:
                rgb565LoAToRgba(raw.slice(0, 4 * n), into: dst, count: n, simd: simd)
            }
        }
    }

    /// RGB565 + low bits + alpha, three planes one after another (images.md 5): `n` u16 words, `n`
    /// low-bit bytes (`b:3 g:2 r:3`, LSB first), `n` alpha bytes. R = 5 high + 3 low bits,
    /// G = 6 high + 2 low bits, B = 5 high + 3 low bits.
    ///
    /// - Parameters:
    ///   - planes: The three planes, `4 n` bytes.
    ///   - rgba: `4 n` bytes, pixels as R, G, B, A.
    ///   - n: Pixel count.
    ///   - simd: Vector width.
    public static func rgb565LoAToRgba(
        _ planes: ByteSpan, rgba: inout [UInt8], count n: Int, simd: SimdLevel = .auto
    ) throws {
        guard n >= 0, planes.count / 4 >= n, rgba.count / 4 >= n else {
            throw TsukiError.bounds("buffers are smaller than 4 bytes per pixel")
        }

        rgba.withUnsafeMutableBytes { dst in
            rgb565LoAToRgba(planes.slice(0, 4 * n), into: dst, count: n, simd: simd)
        }
    }

    private static func rgb565LoAToRgba(
        _ planes: ByteSpan, into dst: UnsafeMutableRawBufferPointer, count n: Int, simd: SimdLevel
    ) {
        planes.withUnsafeBytes { raw in
            let source = raw.baseAddress!.assumingMemoryBound(to: UInt8.self)
            let output = dst.baseAddress!.assumingMemoryBound(to: UInt8.self)
            for i in 0..<n {
                let word = UInt32(source[2 * i]) | UInt32(source[(2 * i) + 1]) << 8
                let low = UInt32(source[(2 * n) + i])
                let alpha = source[(3 * n) + i]
                let r = ((word >> 11) << 3) | (low >> 5)
                let g = (((word >> 5) & 0x3F) << 2) | ((low >> 3) & 3)
                let b = ((word & 0x1F) << 3) | (low & 7)
                let o = 4 * i
                output[o] = UInt8(truncatingIfNeeded: r)
                output[o + 1] = UInt8(truncatingIfNeeded: g)
                output[o + 2] = UInt8(truncatingIfNeeded: b)
                output[o + 3] = alpha
            }
        }
    }

    /// The HEP block must agree with the image header (images.md 4.1): magic, total size = the stream
    /// size, and the tile size.
    private static func checkHep(_ header: ImageHeader, _ raw: ByteSpan) throws {
        let magic = raw.slice(0, 4)
        let total = raw.u32(4)
        let width = raw.u32(0x14)
        let height = raw.u32(0x18)
        // The Python reference compares total_size with the decompressed length, so a longer stream is
        // rejected too.
        guard magic.elementsEqual(hepMagic), total == UInt32(raw.count),
              width == UInt32(header.tileWidth), height == UInt32(header.tileHeight)
        else {
            throw TsukiError.format(
                "HEP header mismatch: \(hexLower(magic)) total \(total) of \(raw.count), "
                    + "\(width)x\(height) in a \(header.tileWidth)x\(header.tileHeight) tile")
        }
    }

    /// HEP palette (images.md 4.2): 256 RGBA entries in plain order, alpha `a` to `2 * min(a, 0x7F)`
    /// (engine VA 0xD70CE).
    private static func hepPalette(_ raw: ByteSpan, into palette: UnsafeMutableBufferPointer<UInt32>) {
        for i in 0..<256 {
            let value = raw.u32(4 * i)
            let alpha = min(value >> 24, 0x7F) * 2
            palette[i] = (value & 0x00FF_FFFF) | (alpha << 24)
        }
    }

    private static func expand8(
        _ indices: ByteSpan, palette: UnsafeBufferPointer<UInt32>, count n: Int,
        into dst: UnsafeMutableRawBufferPointer
    ) {
        let output = dst.baseAddress!.assumingMemoryBound(to: UInt8.self)
        indices.withUnsafeBytes { raw in
            let source = raw.baseAddress!.assumingMemoryBound(to: UInt8.self)
            for i in 0..<n {
                let word = palette[Int(source[i])]
                let o = 4 * i
                output[o] = UInt8(truncatingIfNeeded: word)
                output[o + 1] = UInt8(truncatingIfNeeded: word >> 8)
                output[o + 2] = UInt8(truncatingIfNeeded: word >> 16)
                output[o + 3] = UInt8(truncatingIfNeeded: word >> 24)
            }
        }
    }

    /// PAL4 (images.md 3.2, engine VA 0xD7040): the tile is one linear stream of `n / 2` bytes; byte i
    /// gives texel 2i (low nibble) and texel 2i + 1 (high nibble) whatever the row width. For an odd
    /// texel count the last texel is index 0.
    private static func expand4(
        _ src: ByteSpan, palette: UnsafeBufferPointer<UInt32>, count n: Int,
        into dst: UnsafeMutableRawBufferPointer
    ) {
        let output = dst.baseAddress!.assumingMemoryBound(to: UInt8.self)

        func write(_ word: UInt32, at index: Int) {
            let o = 4 * index
            output[o] = UInt8(truncatingIfNeeded: word)
            output[o + 1] = UInt8(truncatingIfNeeded: word >> 8)
            output[o + 2] = UInt8(truncatingIfNeeded: word >> 16)
            output[o + 3] = UInt8(truncatingIfNeeded: word >> 24)
        }

        let m = n / 2
        src.withUnsafeBytes { raw in
            let source = raw.baseAddress!.assumingMemoryBound(to: UInt8.self)
            for i in 0..<m {
                let byte = source[i]
                write(palette[Int(byte & 0x0F)], at: 2 * i)
                write(palette[Int(byte >> 4)], at: (2 * i) + 1)
            }
        }

        if (n & 1) != 0 {
            write(palette[0], at: n - 1)
        }
    }

    private static let hepMagic: [UInt8] = Array("HEP\0".utf8)
}
