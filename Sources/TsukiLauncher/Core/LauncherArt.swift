import Foundation
import AppKit
import CoreGraphics
import TsukiCore
import TsukiEngine
import TsukiData

/// Decodes title art pictures for the launcher banner.
public enum LauncherArt {
    public static let titleBackgroundChild = 9
    public static let titleLogoChild = 1
    public static let maxWidth = 1600

    public static func loadHero(gameFolder: String) -> (background: NSImage?, logo: NSImage?) {
        do {
            let source = try GameFolderSource.open(gameFolder)
            let bgPic = source.uiSheet(.titleParts, .ja, titleBackgroundChild)
            let logoPic = source.uiSheet(.titleParts, .ja, titleLogoChild)

            let bgImg = toImage(picture: bgPic)
            let rawLogo = toImage(picture: logoPic)
            let croppedLogo = rawLogo.flatMap { cropToContent(image: $0) }

            return (bgImg, croppedLogo ?? rawLogo)
        } catch {
            return (nil, nil)
        }
    }

    public static func toImage(picture: TsukiEngine.Picture) -> NSImage? {
        guard picture.width > 0 && picture.height > 0 else { return nil }
        guard let rgba = try? ImageMzp.assemble(picture) else { return nil }

        let width = picture.width
        let height = picture.height

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)

        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: 4 * width,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }

    /// Crops transparent borders around the logo.
    public static func cropToContent(image: NSImage) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0 && height > 0 else { return image }

        let bytesPerRow = 4 * width
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return image
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var maxX = 0
        var minY = height
        var maxY = 0
        var hasVisible = false

        for y in 0..<height {
            let rowOffset = y * bytesPerRow
            for x in 0..<width {
                let alpha = data[rowOffset + (x * 4) + 3]
                if alpha > 10 {
                    hasVisible = true
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }

        guard hasVisible && minX <= maxX && minY <= maxY else { return image }

        // CoreGraphics coordinates: y=0 is at bottom
        let cropRect = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )

        guard let croppedCg = cgImage.cropping(to: cropRect) else { return image }
        return NSImage(cgImage: croppedCg, size: NSSize(width: cropRect.width, height: cropRect.height))
    }
}
