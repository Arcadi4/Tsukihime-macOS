import Foundation
import TsukiCore
import TsukiEngine

/// One size of an icon: straight RGBA, row-major, `size` squared.
public struct IconFrame: Equatable, Sendable {
    /// The side in pixels.
    public let size: Int

    /// The pixels, top-down, `size * size * 4` bytes.
    public let rgba: [UInt8]

    public init(size: Int, rgba: [UInt8]) {
        self.size = size
        self.rgba = rgba
    }
}

/// The square of the full-size picture an icon is sampled from: opaque RGBA (transparent pixels were
/// laid over the plate colour).
public struct FaceCrop: Equatable, Sendable {
    /// The side in pixels.
    public let side: Int

    /// The pixels, row-major.
    public let rgba: [UInt8]

    /// Where the eyes were found in the face layer (x, y, width, height), for the log and the tests.
    public let eyeBox: PixelRect

    /// The face layer the crop came from.
    public let source: String

    public init(side: Int, rgba: [UInt8], eyeBox: PixelRect, source: String) {
        self.side = side
        self.rgba = rgba
        self.eyeBox = eyeBox
        self.source = source
    }
}

/// Builds the face icon from the game data and encodes it as a Windows .ico file.
///
/// The picture: the face layer `ARU_A_00_00_N00.MZP` (Arcueid, the largest sprite class, pose 00,
/// costume 00, her neutral smile) drawn over its body `ARU_A_00_00_N00_B.MZP` as the engine does.
/// The crop is anchored on her eyes, the only saturated red in the face layer: the box of the red
/// pixels gives the eye line and the span of both eyes; the square is `wideScale` x that span and
/// puts the eye line at `eyeLine` of its height; 16..32 px take a tighter square so the face stays
/// readable. Each size is sampled from the full-size crop on its own (never a resized copy of
/// another size), masked to a rounded square and given a thin moon-blue rim.
public enum FaceIcon {
    /// The face layer the icon is cut from (the catalog record's `name1`; its body is `name0`).
    public static let faceLayer = "ARU_A_00_00_N00.MZP"

    /// The icon sizes, small to large.
    public static let sizes = [16, 24, 32, 48, 64, 128, 256]

    /// Sizes up to this one take the tighter crop.
    public static let tightUpTo = 32

    /// The square's side as a multiple of the eyes' span (both eyes, outer corner to outer corner).
    public static let wideScale = 1.85

    /// The tighter square of the small sizes.
    public static let tightScale = 1.45

    /// Where the eye line sits in the square (a share of the side from the top).
    public static let eyeLine = 0.40

    /// The corner radius of the rounded square, a share of the side.
    public static let cornerRadius = 0.20

    /// Bumped when the arithmetic changes, so a cached icon of an older build is rebuilt.
    public static let version = 1

    // the plate behind a transparent pixel and the rim: the night indigo and its moon-blue border
    private static let plateR: UInt8 = 0x0E
    private static let plateG: UInt8 = 0x15
    private static let plateB: UInt8 = 0x32
    private static let rimR: UInt8 = 0x8F
    private static let rimG: UInt8 = 0xA6
    private static let rimB: UInt8 = 0xFF

    private static let maskSamples = 4

    /// The rim's width in pixels at `size`.
    public static func rimWidth(_ size: Int) -> Double {
        size <= 32 ? 1.0 : size <= 64 ? 1.5 : size <= 128 ? 2.0 : 3.0
    }

    /// The side of the square at `size` given the eyes' span.
    public static func sideFor(eyeSpan: Int, size: Int) -> Int {
        Int((Double(eyeSpan) * (size <= tightUpTo ? tightScale : wideScale)).rounded(.toNearestOrEven))
    }

    /// The box of the saturated red pixels of the face layer (her eyes), in displayed coordinates;
    /// nil when there are too few to be eyes.
    public static func findEyes(_ face: Picture) -> PixelRect? {
        var minX = Int.max
        var minY = Int.max
        var maxX = -1
        var maxY = -1
        var count = 0
        for tile in face.tiles {
            guard !tile.rgba.isEmpty else { continue }
            let sx = tile.source.x
            let sy = tile.source.y
            let width = tile.source.width
            let height = tile.source.height
            let tileWidth = tile.storedWidth
            for y in 0..<height {
                let row = (sy + y) * tileWidth + sx
                for x in 0..<width {
                    let i = (row + x) * 4
                    if isEyeRed(r: tile.rgba[i], g: tile.rgba[i + 1],
                                b: tile.rgba[i + 2], a: tile.rgba[i + 3]) {
                        let px = tile.x + x
                        let py = tile.y + y
                        minX = min(minX, px)
                        maxX = max(maxX, px)
                        minY = min(minY, py)
                        maxY = max(maxY, py)
                        count += 1
                    }
                }
            }
        }

        guard count >= 400, maxX >= minX else { return nil }
        let box = PixelRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        // two eyes side by side: wider than tall, and not a stray red elsewhere in the picture
        return box.width > box.height && box.width < face.width / 2 ? box : nil
    }

    /// Saturated red (her irises): opaque, red well above green and blue.
    public static func isEyeRed(r: UInt8, g: UInt8, b: UInt8, a: UInt8) -> Bool {
        let red = Int(r), green = Int(g), blue = Int(b)
        return Int(a) > 16 && red > 150 && green < 90 && blue < 90 && red - max(green, blue) > 90
    }

    /// One crop of `scale` x the eyes' span out of body + face, or nil when the eyes are not there.
    public static func crop(face: Picture, body: Picture, layerX: Int = 0, layerY: Int = 0,
                            scale: Double = FaceIcon.wideScale) -> FaceCrop? {
        crops(face: face, body: body, layerX: layerX, layerY: layerY, scales: [scale])?.first
    }

    /// Both crops (the wide one for 48 px and up, the tight one for 16..32) from one pass over the
    /// data; nil when the picture is not there.
    public static func crops(face: Picture, body: Picture, layerX: Int = 0,
                             layerY: Int = 0) -> (wide: FaceCrop, tight: FaceCrop)? {
        guard let both = crops(face: face, body: body, layerX: layerX, layerY: layerY,
                               scales: [wideScale, tightScale]), both.count == 2 else { return nil }
        return (both[0], both[1])
    }

    /// The image-catalog record of the face layer (`name1` is ``faceLayer``, case-insensitive, and the record is
    /// not a variant), or nil; the C# `FindRecord`.
    public static func findRecord(_ catalog: GameCatalog) -> CatalogEntry? {
        for entry in catalog.images.entries {
            if let face = entry.name1, sameName(face, faceLayer), !entry.isVariant {
                return entry
            }
        }
        return nil
    }

    /// Both crops from the images of the user's folder: the port of the C# `Crops(GameFolderSource)`. The face
    /// record is found in the catalog, then the face layer and its body are opened by name through the NAM search
    /// and cropped as ``crops(face:body:layerX:layerY:)`` does.
    ///
    /// - Throws: `TsukiError.io` when an archive file is missing or short; anything `files` throws.
    /// - Returns: nil when the catalog has no face record, a name is not in the NAM tables, or a container does not
    ///   parse (the failure the C# catches and reports as no icon).
    public static func crops(_ files: GameFiles, _ catalog: GameCatalog) throws
        -> (wide: FaceCrop, tight: FaceCrop)? {
        guard let both = try crops(files, catalog, scales: [wideScale, tightScale]),
              both.count == 2 else { return nil }
        return (both[0], both[1])
    }

    /// The crop of `scale` x the eyes' span from the images of the user's folder, or nil like
    /// ``crops(_:_:)``; the C# `Crop(GameFolderSource)`.
    public static func crop(_ files: GameFiles, _ catalog: GameCatalog,
                            scale: Double = FaceIcon.wideScale) throws -> FaceCrop? {
        try crops(files, catalog, scales: [scale])?.first
    }

    /// One crop per scale from the images of the user's folder, the pictures opened once, with the
    /// record's layer position; the C# `Crops(GameFolderSource, scales)`.
    public static func crops(_ files: GameFiles, _ catalog: GameCatalog,
                             scales: [Double]) throws -> [FaceCrop]? {
        guard let record = findRecord(catalog) else { return nil }
        guard let face = try picture(files, catalog, faceLayer),
              let body = try picture(files, catalog, record.name0)
        else {
            return nil
        }
        return crops(face: face, body: body, layerX: record.layerX, layerY: record.layerY,
                     scales: scales)
    }

    /// One picture of an image archive by file name, or nil when the name or a container is not there.
    private static func picture(_ files: GameFiles, _ catalog: GameCatalog, _ name: String) throws
        -> Picture? {
        guard let id = try? catalog.nameIndex.find(name) else { return nil }
        let base = "image/" + id.archive.archiveName
        let index = try ArchiveIndex.load(files, base: base)
        guard id.index < index.count else { return nil }
        let archive = Archive.open(index: index, file: try files.mapped(base + ".mrg"))
        guard let container = try? archive.container(id.index), ImageMzp.isImage(container) else {
            return nil
        }
        return try? ImageMzp.open(container).toPicture()
    }

    /// Compares two ASCII names like the C#'s `StringComparison.OrdinalIgnoreCase`: A..Z fold only.
    private static func sameName(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8)
        let b = Array(rhs.utf8)
        guard a.count == b.count else { return false }
        for i in 0..<a.count {
            var x = a[i], y = b[i]
            if x >= 0x61 && x <= 0x7A { x -= 0x20 }
            if y >= 0x61 && y <= 0x7A { y -= 0x20 }
            if x != y { return false }
        }
        return true
    }

    /// One crop per scale, the eyes found once; nil when they are missing.
    public static func crops(face: Picture, body: Picture, layerX: Int = 0, layerY: Int = 0,
                             scales: [Double]) -> [FaceCrop]? {
        guard let box = findEyes(face) else { return nil }
        var crops: [FaceCrop] = []
        crops.reserveCapacity(scales.count)
        for scale in scales {
            let side = Int((Double(box.width) * scale).rounded(.toNearestOrEven))
            guard side >= 1 else { return nil }
            var x0 = Int((Double(box.x) + Double(box.width) / 2.0 - Double(side) / 2.0)
                .rounded(.toNearestOrEven))
            var y0 = Int((Double(box.y) + Double(box.height) / 2.0 - eyeLine * Double(side))
                .rounded(.toNearestOrEven))
            x0 = clamp(x0, 0, max(0, body.width - side))
            y0 = clamp(y0, 0, max(0, body.height - side))

            var canvas = [UInt8](repeating: 0, count: side * side * 4)
            for i in stride(from: 0, to: canvas.count, by: 4) {
                canvas[i] = plateR
                canvas[i + 1] = plateG
                canvas[i + 2] = plateB
                canvas[i + 3] = 255
            }

            blitUnder(body, canvas: &canvas, side: side, cx0: x0, cy0: y0, offsetX: 0, offsetY: 0)
            blitUnder(face, canvas: &canvas, side: side, cx0: x0, cy0: y0,
                      offsetX: layerX, offsetY: layerY)
            crops.append(FaceCrop(side: side, rgba: canvas, eyeBox: box, source: faceLayer))
        }
        return crops
    }

    /// Every size of the icon from the two crops.
    public static func renderAll(wide: FaceCrop, tight: FaceCrop) -> [IconFrame] {
        sizes.map { size in
            IconFrame(size: size, rgba: render(size <= tightUpTo ? tight : wide, size: size))
        }
    }

    /// One size of the icon from a crop: the square sampled down (supersampled bilinear, so every
    /// output pixel averages the source under it), masked to a rounded square with anti-aliased
    /// edges, the rim of `rimWidth` pixels in moon-blue inside the edge, transparent corners.
    public static func render(_ crop: FaceCrop, size: Int) -> [UInt8] {
        precondition(size >= 1, "an icon size is at least 1 pixel")
        var output = [UInt8](repeating: 0, count: size * size * 4)
        let side = crop.side
        let src = crop.rgba
        let step = Double(side) / Double(size)
        let samples = clamp(Int((2.0 * step).rounded(.up)), 2, 32)
        let radius = cornerRadius * Double(size)
        let rim = rimWidth(size)
        for y in 0..<size {
            for x in 0..<size {
                // the picture: the average of samples x samples bilinear reads spread over the
                // source square under this pixel
                var r = 0.0, g = 0.0, b = 0.0
                for sy in 0..<samples {
                    let fy = (Double(y) + (Double(sy) + 0.5) / Double(samples)) * step - 0.5
                    for sx in 0..<samples {
                        let fx = (Double(x) + (Double(sx) + 0.5) / Double(samples)) * step - 0.5
                        let pixel = bilinear(src, side: side, fx: fx, fy: fy)
                        r += pixel.r
                        g += pixel.g
                        b += pixel.b
                    }
                }

                let n = Double(samples * samples)
                r /= n
                g /= n
                b /= n

                // the mask: how much of this pixel lies inside the rounded square, and how much of
                // that inside the rim band
                var outer = 0
                var inner = 0
                for sy in 0..<maskSamples {
                    let py = Double(y) + (Double(sy) + 0.5) / Double(maskSamples)
                    for sx in 0..<maskSamples {
                        let px = Double(x) + (Double(sx) + 0.5) / Double(maskSamples)
                        let distance = roundedBoxDistance(px: px, py: py, size: size, radius: radius)
                        if distance <= 0 {
                            outer += 1
                            if distance <= -rim { inner += 1 }
                        }
                    }
                }

                let o = (y * size + x) * 4
                if outer == 0 { continue }

                let rimShare = Double(outer - inner) / Double(outer)
                output[o] = channel(r * (1 - rimShare) + Double(rimR) * rimShare)
                output[o + 1] = channel(g * (1 - rimShare) + Double(rimG) * rimShare)
                output[o + 2] = channel(b * (1 - rimShare) + Double(rimB) * rimShare)
                let maskArea = maskSamples * maskSamples
                output[o + 3] = UInt8((255.0 * Double(outer) / Double(maskArea)).rounded(.toNearestOrEven))
            }
        }
        return output
    }

    // ---- the .ico file -------------------------------------------------------------------------

    /// The frames as a Windows icon file: every size a 32-bit BMP entry (BITMAPINFOHEADER, BGRA rows
    /// bottom-up, an all-zero AND mask), the 256 px one included (its directory entry says 0 x 0, the
    /// Vista form).
    public static func encodeIco(_ frames: [IconFrame]) -> [UInt8] {
        precondition(!frames.isEmpty, "an icon file needs at least one frame")
        var writer = ByteWriter(reserving: 6 + 16 * frames.count)
        writer.u16(0)
        writer.u16(1)
        writer.u16(UInt16(frames.count))
        var offset = 6 + 16 * frames.count
        var images: [[UInt8]] = []
        images.reserveCapacity(frames.count)
        for frame in frames {
            let image = bmpEntry(frame)
            images.append(image)
            let dimension = UInt8(frame.size >= 256 ? 0 : frame.size)
            writer.u8(dimension)
            writer.u8(dimension)
            writer.u8(0)                                    // colour count
            writer.u8(0)                                    // reserved
            writer.u16(1)                                   // planes
            writer.u16(32)                                  // bits per pixel
            writer.u32(UInt32(image.count))
            writer.u32(UInt32(offset))
            offset += image.count
        }
        for image in images { writer.raw(image) }
        return writer.bytes
    }

    /// The 32-bit BMP entries of an icon file as RGBA frames (PNG entries and other depths are
    /// skipped); empty when the bytes are not an icon file.
    public static func decodeIco(_ ico: ByteSpan) -> [IconFrame] {
        var frames: [IconFrame] = []
        guard ico.count >= 6, ico.u16(0) == 0, ico.u16(2) == 1 else { return frames }
        let count = Int(ico.u16(4))
        for i in 0..<count {
            let at = 6 + 16 * i
            if at + 16 > ico.count { break }
            let length = Int(Int32(bitPattern: ico.u32(at + 8)))
            let offset = Int(Int32(bitPattern: ico.u32(at + 12)))
            if offset < 0 || length < 40 || offset + length > ico.count { continue }
            let image = ico.slice(offset, length)
            guard image.u32(0) == 40 else { continue }      // a PNG entry, or a header this reader does not know
            let width = Int(image.i32(4))
            let height = Int(image.i32(8)) / 2
            let bits = Int(image.u16(14))
            guard width > 0, height > 0, width == height, bits == 32,
                  40 + width * height * 4 <= image.count else { continue }

            var rgba = [UInt8](repeating: 0, count: width * height * 4)
            for y in 0..<height {
                let row = image.slice(40 + (height - 1 - y) * width * 4, width * 4)
                for x in 0..<width {
                    let s = x * 4
                    let d = (y * width + x) * 4
                    rgba[d] = row[s + 2]
                    rgba[d + 1] = row[s + 1]
                    rgba[d + 2] = row[s]
                    rgba[d + 3] = row[s + 3]
                }
            }
            frames.append(IconFrame(size: width, rgba: rgba))
        }
        return frames
    }

    /// Signed distance from (px, py) to the edge of the rounded square of `size` (negative inside).
    public static func roundedBoxDistance(px: Double, py: Double, size: Int, radius: Double) -> Double {
        let half = Double(size) / 2.0
        let qx = abs(px - half) - (half - radius)
        let qy = abs(py - half) - (half - radius)
        let outside = ((max(qx, 0) * max(qx, 0)) + (max(qy, 0) * max(qy, 0))).squareRoot()
        return outside + min(max(qx, qy), 0) - radius
    }

    // ---- internals -----------------------------------------------------------------------------

    private static func channel(_ value: Double) -> UInt8 {
        UInt8(clamp(Int(value.rounded(.toNearestOrEven)), 0, 255))
    }

    /// Straight-alpha "over" of the tiles of a layer that touch the square onto the opaque canvas.
    private static func blitUnder(_ picture: Picture, canvas: inout [UInt8], side: Int,
                                  cx0: Int, cy0: Int, offsetX: Int, offsetY: Int) {
        for tile in picture.tiles {
            let rgba = tile.rgba
            guard !rgba.isEmpty else { continue }
            let sx = tile.source.x
            let sy = tile.source.y
            let width = tile.source.width
            let height = tile.source.height
            let left = max(tile.x + offsetX, cx0)
            let top = max(tile.y + offsetY, cy0)
            let right = min(tile.x + offsetX + width, cx0 + side)
            let bottom = min(tile.y + offsetY + height, cy0 + side)
            if right <= left || bottom <= top { continue }

            let tileWidth = tile.storedWidth
            for y in top..<bottom {
                let srcRow = (sy + (y - tile.y - offsetY)) * tileWidth + sx + (left - tile.x - offsetX)
                let dstRow = (y - cy0) * side + (left - cx0)
                for x in 0..<(right - left) {
                    let s = (srcRow + x) * 4
                    let d = (dstRow + x) * 4
                    let alpha = Int(rgba[s + 3])
                    if alpha == 0 { continue }
                    canvas[d] = UInt8((Int(rgba[s]) * alpha + Int(canvas[d]) * (255 - alpha) + 127) / 255)
                    canvas[d + 1] = UInt8((Int(rgba[s + 1]) * alpha + Int(canvas[d + 1]) * (255 - alpha) + 127) / 255)
                    canvas[d + 2] = UInt8((Int(rgba[s + 2]) * alpha + Int(canvas[d + 2]) * (255 - alpha) + 127) / 255)
                }
            }
        }
    }

    private static func bilinear(_ src: [UInt8], side: Int, fx: Double, fy: Double)
        -> (r: Double, g: Double, b: Double) {
        let x = clamp(fx, 0, Double(side - 1))
        let y = clamp(fy, 0, Double(side - 1))
        let x0 = Int(x)
        let y0 = Int(y)
        let x1 = min(x0 + 1, side - 1)
        let y1 = min(y0 + 1, side - 1)
        let tx = x - Double(x0)
        let ty = y - Double(y0)
        let i00 = (y0 * side + x0) * 4
        let i10 = (y0 * side + x1) * 4
        let i01 = (y1 * side + x0) * 4
        let i11 = (y1 * side + x1) * 4
        let w00 = (1 - tx) * (1 - ty)
        let w10 = tx * (1 - ty)
        let w01 = (1 - tx) * ty
        let w11 = tx * ty
        return (
            Double(src[i00]) * w00 + Double(src[i10]) * w10 + Double(src[i01]) * w01 + Double(src[i11]) * w11,
            Double(src[i00 + 1]) * w00 + Double(src[i10 + 1]) * w10 + Double(src[i01 + 1]) * w01 + Double(src[i11 + 1]) * w11,
            Double(src[i00 + 2]) * w00 + Double(src[i10 + 2]) * w10 + Double(src[i01 + 2]) * w01 + Double(src[i11 + 2]) * w11
        )
    }

    private static func bmpEntry(_ frame: IconFrame) -> [UInt8] {
        let size = frame.size
        let maskRow = ((size + 31) / 32) * 4
        var image = [UInt8](repeating: 0, count: 40 + size * size * 4 + maskRow * size)
        putU32(&image, 0, 40)
        putI32(&image, 4, size)
        putI32(&image, 8, size * 2)                         // the XOR and the AND bitmaps together
        putU16(&image, 12, 1)
        putU16(&image, 14, 32)
        putU32(&image, 20, UInt32(size * size * 4))
        for y in 0..<size {
            let srcRow = (size - 1 - y) * size * 4          // bottom-up
            let dstRow = 40 + y * size * 4
            for x in 0..<size {
                let s = srcRow + x * 4
                let d = dstRow + x * 4
                image[d] = frame.rgba[s + 2]
                image[d + 1] = frame.rgba[s + 1]
                image[d + 2] = frame.rgba[s]
                image[d + 3] = frame.rgba[s + 3]
            }
        }
        return image                                          // the AND mask stays zero: alpha decides
    }
}

/// The cached icon in the profile folder: `icons/tsukihime.ico` and, beside it, `tsukihime.src`
/// saying which game folder and which build of the arithmetic made it. A current file is used as it
/// is, a missing or stale one is rebuilt from the game data (the game folder changed, or
/// `FaceIcon.version` did).
public enum FaceIconCache {
    /// The folder under the profile folder.
    public static let folderName = "icons"

    /// The icon file.
    public static let fileName = "tsukihime.ico"

    /// The stamp file beside it.
    public static let stampName = "tsukihime.src"

    /// An icon file larger than this is not read (the seven frames of `FaceIcon.sizes` are 364 KiB).
    public static let maxIconBytes = 4 << 20

    /// The icon file of `dataDirectory` (whether or not it exists).
    public static func iconPath(_ dataDirectory: String) -> String {
        (dataDirectory as NSString).appendingPathComponent(folderName + "/" + fileName)
    }

    /// The stamp file of `dataDirectory`.
    public static func stampPath(_ dataDirectory: String) -> String {
        (dataDirectory as NSString).appendingPathComponent(folderName + "/" + stampName)
    }

    /// What the stamp says for `gameFolder` with this build (the full path of the folder: it is a
    /// file of the player's own profile, never shared).
    public static func stamp(_ gameFolder: String) -> String {
        let full: String
        if gameFolder.hasPrefix("/") {
            full = URL(fileURLWithPath: gameFolder).standardizedFileURL.path
        } else {
            full = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(gameFolder).standardizedFileURL.path
        }
        var trimmed = full
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        return "v\(FaceIcon.version)|\(FaceIcon.faceLayer)|\(trimmed)"
    }

    /// True when the cached icon exists and was made from `gameFolder` by this build.
    public static func isCurrent(_ dataDirectory: String, gameFolder: String) -> Bool {
        let icon = iconPath(dataDirectory)
        let stampFile = stampPath(dataDirectory)
        let manager = FileManager.default
        guard manager.fileExists(atPath: icon), manager.fileExists(atPath: stampFile),
              let attributes = try? manager.attributesOfItem(atPath: icon),
              let length = attributes[.size] as? NSNumber, length.intValue != 0,
              let data = try? Data(contentsOf: URL(fileURLWithPath: stampFile)) else { return false }
        let text = String(decoding: data, as: UTF8.self)
        let firstLine = text.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        return firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(stamp(gameFolder)) == .orderedSame
    }

    /// The path of a current icon for `gameFolder`, building it when it is missing or stale. `open`
    /// is called only then and returns the decoded face and body pictures with the face layer's
    /// position. Nil when the pictures or the eyes are missing or the file could not be written
    /// (`log` says why).
    public static func ensure(
        _ dataDirectory: String,
        gameFolder: String,
        open: () throws -> (face: Picture, body: Picture, layerX: Int, layerY: Int),
        log: ((String) -> Void)? = nil
    ) -> String? {
        let icon = iconPath(dataDirectory)
        if isCurrent(dataDirectory, gameFolder: gameFolder) { return icon }

        let started = Date()
        do {
            let pictures = try open()
            guard let crops = FaceIcon.crops(face: pictures.face, body: pictures.body,
                                             layerX: pictures.layerX, layerY: pictures.layerY) else {
                log?("face icon: \(FaceIcon.faceLayer) (or its eyes) not found in \(gameFolder); the crescent stays")
                return nil
            }

            let frames = FaceIcon.renderAll(wide: crops.wide, tight: crops.tight)
            let folder = (icon as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            let temp = icon + ".tmp"
            try Data(FaceIcon.encodeIco(frames)).write(to: URL(fileURLWithPath: temp))
            if FileManager.default.fileExists(atPath: icon) {
                _ = try FileManager.default.replaceItemAt(URL(fileURLWithPath: icon),
                                                          withItemAt: URL(fileURLWithPath: temp))
            } else {
                try FileManager.default.moveItem(atPath: temp, toPath: icon)
            }
            try Data((stamp(gameFolder) + "\n").utf8).write(to: URL(fileURLWithPath: stampPath(dataDirectory)))

            let milliseconds = Int(Date().timeIntervalSince(started) * 1000)
            let box = crops.wide.eyeBox
            log?("face icon: built from \(crops.wide.source) (eyes at \(box.x),\(box.y) \(box.width) x \(box.height); "
                + "squares \(crops.wide.side) and \(crops.tight.side) px) into \(icon) in \(milliseconds) ms")
            return icon
        } catch {
            log?("face icon: not built (\(type(of: error)): \(error)); the crescent stays")
            return nil
        }
    }

    /// The frame of `size` in the cached file, or the largest one, or nil when the file is missing,
    /// too large or not an icon.
    public static func readFrame(_ iconPath: String, size: Int) -> IconFrame? {
        let manager = FileManager.default
        guard let attributes = try? manager.attributesOfItem(atPath: iconPath),
              let length = attributes[.size] as? NSNumber,
              length.intValue <= maxIconBytes,
              let data = try? Data(contentsOf: URL(fileURLWithPath: iconPath)) else { return nil }
        let frames = FaceIcon.decodeIco(ByteSpan([UInt8](data)))
        return frames.first { $0.size == size } ?? frames.max { $0.size < $1.size }
    }
}

// ---- little-endian writes ----------------------------------------------------------------------

private func putU16(_ bytes: inout [UInt8], _ offset: Int, _ value: Int) {
    bytes[offset] = UInt8(truncatingIfNeeded: value)
    bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
}

private func putU32(_ bytes: inout [UInt8], _ offset: Int, _ value: UInt32) {
    bytes[offset] = UInt8(truncatingIfNeeded: value)
    bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
    bytes[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
    bytes[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
}

private func putI32(_ bytes: inout [UInt8], _ offset: Int, _ value: Int) {
    putU32(&bytes, offset, UInt32(bitPattern: Int32(truncatingIfNeeded: value)))
}
