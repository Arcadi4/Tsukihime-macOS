import Foundation
import TsukiEngine

/// A picture the menus build at run time from the player's own sheets (package K33): straight-alpha RGBA8, top-down. It lives in memory only: it is the
/// player's art rearranged, so it is never written to disk and never part of the repository.
public final class UiComposedPicture: Sendable {
    public let width: Int
    public let height: Int
    public let rgba: [UInt8]

    public var Width: Int { width }
    public var Height: Int { height }
    public var Rgba: [UInt8] { rgba }

    public init(width: Int, height: Int, rgba: [UInt8]) {
        self.width = width
        self.height = height
        self.rgba = rgba
    }
}

/// The ids of the composed pictures (`TextureRef.forUiComposed`, `A`).
public enum UiComposedId {
    /// EXIT on the title in its normal look (white letters), a 296 x 72 cell like the other items (package K33).
    public static let titleExit = 0
    public static let TitleExit = titleExit

    /// EXIT on the title under the cursor (cyan letters).
    public static let titleExitCursor = 1
    public static let TitleExitCursor = titleExitCursor
}

/// Helpers for the composed pictures.
public enum UiComposed {
    /// The displayed picture as one RGBA image: each tile's `PictureTile.source` window is copied to its displayed position; empty tiles stay
    /// transparent (the same assembly the texture providers do for a whole-sheet quad).
    public static func assemble(_ picture: Picture) -> [UInt8] {
        var rgba = [UInt8](repeating: 0, count: picture.width * picture.height * 4)
        for t in picture.tiles {
            if t.flags == .empty || t.rgba.isEmpty {
                continue
            }

            let src = t.rgba
            let srcWidth = t.storedWidth
            let tSource = t.source
            for row in 0..<tSource.height {
                let dy = t.y + row
                if dy < 0 || dy >= picture.height {
                    continue
                }

                let w = min(tSource.width, picture.width - t.x)
                if w <= 0 {
                    continue
                }

                let srcOffset = ((tSource.y + row) * srcWidth + tSource.x) * 4
                let dstOffset = (dy * picture.width + t.x) * 4
                if srcOffset + w * 4 <= src.count && dstOffset + w * 4 <= rgba.count {
                    rgba.replaceSubrange(dstOffset..<(dstOffset + w * 4), with: src[srcOffset..<(srcOffset + w * 4)])
                }
            }
        }
        return rgba
    }
    public static func Assemble(_ picture: Picture) -> [UInt8] {
        assemble(picture)
    }
}
