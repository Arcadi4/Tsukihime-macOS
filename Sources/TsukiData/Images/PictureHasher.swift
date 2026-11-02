import CommonCrypto
import Foundation
import TsukiCore
import TsukiEngine

/// SHA-1 of the displayed picture (`displayWidth x displayHeight` straight-alpha RGBA8, row-major,
/// flag-0 tiles transparent), the value the Python oracle records for every picture
/// (`hashlib.sha1(decode_image(...).rgba)`).
///
/// The bitmap is never built: tiles are decoded one tile row at a time, copied into a band of rows
/// and hashed, so a 343 MB picture needs about 25 MB. One hasher per thread; it keeps its buffers
/// between pictures.
public final class PictureHasher {
    private var context = CC_SHA1_CTX()
    private let scratch = TileScratch()
    private var tile: [UInt8] = []
    private var band: [UInt8] = []

    /// Number of tiles decoded since creation.
    public private(set) var tilesDecoded = 0

    /// Bytes of displayed RGBA hashed since creation.
    public private(set) var bytesHashed = 0

    public init() {
        CC_SHA1_Init(&context)
    }

    /// The SHA-1 of the displayed picture of `image` as 20 bytes.
    public func hash(_ image: ImageMzp, simd: SimdLevel = .auto) throws -> [UInt8] {
        let h = image.header
        let outWidth = h.displayWidth
        let outHeight = h.displayHeight
        let innerWidth = h.innerWidth
        let innerHeight = h.innerHeight
        let border = h.border
        guard outWidth > 0, outHeight > 0, innerWidth > 0, innerHeight > 0 else {
            throw TsukiError.format(
                "picture \(outWidth)x\(outHeight) with \(innerWidth)x\(innerHeight) displayed tile pixels has no hashable area")
        }

        let rowBytes = 4 * outWidth
        let bandBytes = rowBytes * min(innerHeight, outHeight)
        if band.count < bandBytes {
            band = [UInt8](repeating: 0, count: bandBytes)
        }

        if tile.count < h.tileRgbaBytes {
            tile = [UInt8](repeating: 0, count: h.tileRgbaBytes)
        }

        // Every displayed pixel is covered by a tile unless the header is odd (a border with a width
        // below 8): then clear the band.
        let bands = (outHeight + innerHeight - 1) / innerHeight
        let coverageGaps = h.tilesX * innerWidth < outWidth || bands > h.tilesY
        CC_SHA1_Init(&context)
        for by in 0..<bands {
            let y0 = by * innerHeight
            let rows = min(innerHeight, outHeight - y0)
            let bandLength = rowBytes * rows
            if coverageGaps {
                band.withUnsafeMutableBytes { raw in
                    _ = memset(raw.baseAddress!, 0, bandLength)
                }
            }

            if by < h.tilesY {
                for tx in 0..<h.tilesX {
                    let x0 = tx * innerWidth
                    if x0 >= outWidth {
                        break
                    }

                    let copyWidth = min(innerWidth, outWidth - x0)
                    let t = (by * h.tilesX) + tx
                    if !h.isLive(t) {
                        if !coverageGaps {
                            band.withUnsafeMutableBytes { raw in
                                for y in 0..<rows {
                                    _ = memset(
                                        raw.baseAddress!.advanced(by: (y * rowBytes) + (4 * x0)),
                                        0, 4 * copyWidth)
                                }
                            }
                        }
                        continue
                    }

                    try image.decodeTile(t, scratch: scratch, rgba: &tile, simd: simd)
                    tilesDecoded += 1
                    band.withUnsafeMutableBytes { dst in
                        tile.withUnsafeBytes { src in
                            for y in 0..<rows {
                                dst.baseAddress!.advanced(by: (y * rowBytes) + (4 * x0)).copyMemory(
                                    from: src.baseAddress!.advanced(
                                        by: 4 * (((y + border) * h.tileWidth) + border)),
                                    byteCount: 4 * copyWidth)
                            }
                        }
                    }
                }
            }

            band.withUnsafeBytes { raw in
                append(raw.baseAddress!, count: bandLength)
            }
            bytesHashed += bandLength
        }

        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        CC_SHA1_Final(&digest, &context)
        return digest
    }

    /// The SHA-1 as 40 lower-case hex digits.
    public func hashHex(_ image: ImageMzp, simd: SimdLevel = .auto) throws -> String {
        hexLower(try hash(image, simd: simd))
    }

    /// The SHA-1 of the displayed picture of the image container `container`.
    public func hashHex(container: MzpContainer, simd: SimdLevel = .auto) throws -> String {
        hexLower(try hash(ImageMzp.open(container), simd: simd))
    }

    private func append(_ bytes: UnsafeRawPointer, count: Int) {
        var offset = 0
        while offset < count {
            let chunk = min(count - offset, 1 << 30)
            _ = CC_SHA1_Update(&context, bytes.advanced(by: offset), CC_LONG(chunk))
            offset += chunk
        }
    }
}
