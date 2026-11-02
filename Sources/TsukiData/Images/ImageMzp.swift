import Foundation
import TsukiCore
import TsukiEngine

/// A reusable buffer for the MZX0 output of one tile. A decode worker keeps one and passes it to every
/// ``ImageMzp/decodeTile(_:scratch:rgba:simd:)`` call; it grows to the largest tile it has seen and is
/// not shared between threads.
public final class TileScratch {
    /// Contents are unspecified past the declared stream size.
    var buffer: [UInt8] = []

    public init() {}

    /// Grows the buffer to at least `size` bytes (contents unspecified).
    func reserve(_ size: Int) {
        if buffer.count < size {
            buffer = [UInt8](repeating: 0, count: max(size, 1 << 20))
        }
    }
}

/// An image MZP (docs/formats/images.md): an mrgd00 container whose section 0 is the ``ImageHeader``
/// and whose sections 1..N are the MZX0 streams of the tiles, row-major. Decodes tiles to
/// straight-alpha RGBA8 and builds the ``Picture`` of the data contract. A port of `tsuki.image`
/// (`decode_image`, `decode_tile`, `assemble`).
public struct ImageMzp {
    /// The container (a window onto the archive mapping; not copied).
    public let container: MzpContainer

    /// Section 0, parsed.
    public let header: ImageHeader

    private init(container: MzpContainer, header: ImageHeader) {
        self.container = container
        self.header = header
    }

    /// The container is an image MZP by the rule of `tsuki.sniff.classify_mzp`: not every section
    /// nested, section 0 starts with a self-consistent header, every other section is an MZX0
    /// stream, and the count is 1 + tiles.
    public static func isImage(_ container: MzpContainer) -> Bool {
        let n = container.count
        guard n > 0 else {
            return false
        }

        var allNested = true
        var i = 0
        while i < n && allNested {
            allNested = container.isNested(i)
            i += 1
        }

        if allNested {
            return false
        }

        let head = container.head(0, count: 16)
        guard head.count >= 16 else {
            return false
        }

        let w = Int(head.u16(0))
        let h = Int(head.u16(2))
        let tw = Int(head.u16(4))
        let th = Int(head.u16(6))
        let tx = Int(head.u16(8))
        let ty = Int(head.u16(10))
        guard w != 0, h != 0, tw != 0, th != 0, tx != 0, ty != 0,
              tx == (w + tw - 1) / tw, ty == (h + th - 1) / th
        else {
            return false
        }

        for i in 1..<n {
            if !container.head(i, count: 4).elementsEqual(mzxMagic) {
                return false
            }
        }

        return n == 1 + (tx * ty)
    }

    /// Parses the header of an image container.
    public static func open(_ container: MzpContainer) throws -> ImageMzp {
        guard container.count != 0 else {
            throw TsukiError.format("container has no sections")
        }

        let header = try ImageHeader.parse(container.section(0))
        guard container.count == 1 + header.tiles else {
            throw TsukiError.format("\(container.count) sections for \(header.tiles) tiles")
        }

        return ImageMzp(container: container, header: header)
    }

    /// Parses `data` as an mrgd00 image container.
    public static func open(_ data: ByteSpan) throws -> ImageMzp {
        try open(MzpContainer.parse(data))
    }

    /// Decompresses and converts tile `t` to its stored RGBA8 tile (`header.tileRgbaBytes` bytes,
    /// border included). Flag-0 tiles can be decoded too; the engine never displays them.
    ///
    /// - Parameters:
    ///   - t: Tile number, row-major.
    ///   - scratch: Per-thread MZX0 output buffer.
    ///   - rgba: At least `header.tileRgbaBytes` bytes.
    ///   - simd: Vector width for RGB565+LO+A.
    public func decodeTile(
        _ t: Int, scratch: TileScratch, rgba: inout [UInt8], simd: SimdLevel = .auto
    ) throws {
        guard t >= 0, t < header.tiles else {
            throw TsukiError.bounds("tile \(t) is not 0..<\(header.tiles)")
        }

        let stream = container.section(1 + t)
        do {
            let declared = try Mzx.declaredSize(stream)
            guard declared >= header.tileBytes else {
                throw TsukiError.format(
                    "tile data is \(declared) bytes, \(header.format) needs \(header.tileBytes)")
            }

            // One MZX0 command writes at most 128 bytes from one input byte, so a stream cannot
            // declare more.
            guard declared <= (stream.count - Mzx.headerSize) * 128 else {
                throw TsukiError.format(
                    "MZX0 declared size \(declared) cannot come from a \(stream.count)-byte stream")
            }

            scratch.reserve(Mzx.bufferSize(declared))
            _ = try Mzx.decode(stream, into: &scratch.buffer)
            let raw = ByteSpan(scratch.buffer, offset: 0, count: declared)
            try TileConverter.convert(header, raw: raw, rgba: &rgba, simd: simd)
        } catch let error as TsukiError {
            if case let .format(message) = error, !message.hasPrefix("tile ") {
                throw TsukiError.format("tile \(t): \(message)")
            }
            throw error
        }
    }

    /// The picture of the data contract: every tile in row-major order as straight-alpha RGBA8
    /// (stored tile, border included), flag-0 tiles empty. Never builds the displayed bitmap
    /// (ARCHITECTURE 4.3, S4).
    ///
    /// - Parameters:
    ///   - maxDegreeOfParallelism: Tile decode workers; 1 decodes on the calling thread.
    ///   - simd: Vector width for RGB565+LO+A.
    public func toPicture(
        maxDegreeOfParallelism: Int = 1, simd: SimdLevel = .auto
    ) throws -> Picture {
        let h = header
        var tiles: [PictureTile] = []
        tiles.reserveCapacity(h.tiles)
        var live: [Int] = []
        live.reserveCapacity(h.tiles)
        for t in 0..<h.tiles {
            let window = h.tileWindow(t)
            let source = PixelRect(
                x: window.sx, y: window.sy, width: window.width, height: window.height)
            if h.isLive(t) {
                live.append(t)
            }

            tiles.append(
                PictureTile(
                    index: t, flags: .empty, storedWidth: h.tileWidth, storedHeight: h.tileHeight,
                    source: source, x: window.x, y: window.y, rgba: []))
        }

        if maxDegreeOfParallelism <= 1 || live.count <= 1 {
            let scratch = TileScratch()
            for t in live {
                tiles[t] = try pictureTile(t, scratch: scratch, simd: simd)
            }
        } else {
            let workers = max(1, min(live.count, maxDegreeOfParallelism))
            let perWorker = (live.count + workers - 1) / workers
            let chunks: [[Int]] = stride(from: 0, to: live.count, by: perWorker).map {
                Array(live[$0..<min($0 + perWorker, live.count)])
            }
            let decoded: [Result<[PictureTile], Error>] = parallelMap(
                chunks, parallelism: workers
            ) { chunk in
                do {
                    let scratch = TileScratch()
                    var out: [PictureTile] = []
                    out.reserveCapacity(chunk.count)
                    for t in chunk {
                        out.append(try self.pictureTile(t, scratch: scratch, simd: simd))
                    }
                    return .success(out)
                } catch {
                    return .failure(error)
                }
            }

            for result in decoded {
                switch result {
                case let .success(chunk):
                    for tile in chunk {
                        tiles[tile.index] = tile
                    }
                case let .failure(error):
                    throw error
                }
            }
        }

        return Picture(width: h.displayWidth, height: h.displayHeight, tiles: tiles)
    }

    /// The picture's tile layout without any decoded pixel (package K8): every tile has its flags,
    /// stored size and window, and an empty pixel array. For the callers that need geometry only
    /// (`SheetGeometry`): ``toPicture`` decodes every tile, which cost 20..100 ms for a sheet.
    public func toLayoutPicture() -> Picture {
        let h = header
        var tiles: [PictureTile] = []
        tiles.reserveCapacity(h.tiles)
        for t in 0..<h.tiles {
            let window = h.tileWindow(t)
            let flags: TileFlags = h.isLive(t) ? Self.flags(for: h.tileFlags[t]) : .empty
            tiles.append(
                PictureTile(
                    index: t, flags: flags, storedWidth: h.tileWidth, storedHeight: h.tileHeight,
                    source: PixelRect(
                        x: window.sx, y: window.sy, width: window.width, height: window.height),
                    x: window.x, y: window.y, rgba: []))
        }

        return Picture(width: h.displayWidth, height: h.displayHeight, tiles: tiles)
    }

    /// The displayed picture as straight-alpha RGBA8, `displayWidth x displayHeight` row-major,
    /// flag-0 tiles transparent: the value of `tsuki.image.decode_image(...).rgba`. For tests and
    /// tools; the runtime uploads tiles instead.
    public func decodeDisplayed(
        maxDegreeOfParallelism: Int = 1, simd: SimdLevel = .auto
    ) throws -> [UInt8] {
        try Self.assemble(
            toPicture(maxDegreeOfParallelism: maxDegreeOfParallelism, simd: simd))
    }

    /// Copies the displayed part of every tile of `picture` into one bitmap (images.md 2.2, 9).
    public static func assemble(_ picture: Picture) throws -> [UInt8] {
        guard picture.width >= 0, picture.height >= 0 else {
            throw TsukiError.format(
                "displayed picture of \(picture.width)x\(picture.height) has no bitmap")
        }

        let stride = 4 * picture.width
        var output = [UInt8](repeating: 0, count: stride * picture.height)
        for tile in picture.tiles {
            if tile.flags == .empty || tile.source.width <= 0 || tile.source.height <= 0 {
                continue
            }

            let rowBytes = 4 * tile.source.width
            for y in 0..<tile.source.height {
                let sourceOffset =
                    4 * (((tile.source.y + y) * tile.storedWidth) + tile.source.x)
                let destinationOffset = ((tile.y + y) * stride) + (4 * tile.x)
                guard sourceOffset >= 0, sourceOffset + rowBytes <= tile.rgba.count,
                      destinationOffset >= 0, destinationOffset + rowBytes <= output.count
                else {
                    throw TsukiError.bounds("tile \(tile.index) does not fit the picture bitmap")
                }

                output.withUnsafeMutableBytes { dst in
                    tile.rgba.withUnsafeBytes { src in
                        dst.baseAddress!.advanced(by: destinationOffset).copyMemory(
                            from: src.baseAddress!.advanced(by: sourceOffset), byteCount: rowBytes)
                    }
                }
            }
        }

        return output
    }

    private func pictureTile(
        _ t: Int, scratch: TileScratch, simd: SimdLevel
    ) throws -> PictureTile {
        let h = header
        let window = h.tileWindow(t)
        var rgba = [UInt8](repeating: 0, count: h.tileRgbaBytes)
        try decodeTile(t, scratch: scratch, rgba: &rgba, simd: simd)
        return PictureTile(
            index: t, flags: Self.flags(for: h.tileFlags[t]), storedWidth: h.tileWidth,
            storedHeight: h.tileHeight,
            source: PixelRect(
                x: window.sx, y: window.sy, width: window.width, height: window.height),
            x: window.x, y: window.y, rgba: rgba)
    }

    /// The packer writes 0, 1 and 2 only; any other nonzero byte means the tile is decoded and
    /// blended (only flag 0 changes what the engine does, images.md 2.3).
    private static func flags(for raw: UInt8) -> TileFlags {
        TileFlags(rawValue: raw) ?? .mayBeTransparent
    }

    private static let mzxMagic: [UInt8] = Array("MZX0".utf8)
}
