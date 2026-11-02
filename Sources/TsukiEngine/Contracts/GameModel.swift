import Foundation
import TsukiCore

/// Game language index as the engine stores it.
public enum Language: UInt8, CaseIterable, Sendable {
    case ja = 0
    case en = 1
    case zc = 2
    case zt = 3
    /// Placeholder data only; never selectable.
    case ko = 4

    /// Languages the launcher and config screen may offer.
    public static let selectable: [Language] = [.ja, .en, .zc, .zt]

    /// Two-letter code used for file names (`ft_ja.mrg`).
    public var code: String {
        switch self {
        case .ja: return "ja"
        case .en: return "en"
        case .zc: return "zc"
        case .zt: return "zt"
        case .ko: return "ko"
        }
    }

    public init?(code: String) {
        guard let match = Language.allCases.first(where: { $0.code == code.lowercased() }) else { return nil }
        self = match
    }
}

/// Identity of the user's copy.
public struct BuildInfo: Equatable, Sendable {
    public let source: String
    public let ebootSize: Int
    public let ebootSHA256: String

    public static let analysedEbootSize = 12_767_802
    public static let analysedEbootSHA256 = "c2843415fdfda5ebbc84f4d55c6cca044a7476436cf0cfdfccac83116beeb918"

    public init(source: String, ebootSize: Int, ebootSHA256: String) {
        self.source = source
        self.ebootSize = ebootSize
        self.ebootSHA256 = ebootSHA256
    }

    /// True when every eboot address in the format documents applies to this copy.
    public var isAnalysedBuild: Bool {
        ebootSize == Self.analysedEbootSize && ebootSHA256 == Self.analysedEbootSHA256
    }
}

/// One decoded script: the bytes the VM runs plus the start offset of every segment.
public struct ScriptImage: Sendable {
    public let index: Int
    public let bytes: [UInt8]
    public let segmentStarts: [Int]

    public init(index: Int, bytes: [UInt8], segmentStarts: [Int]) {
        self.index = index
        self.bytes = bytes
        self.segmentStarts = segmentStarts
    }

    public var span: ByteSpan { ByteSpan(bytes) }

    public func segmentEnd(_ i: Int) -> Int {
        i + 1 < segmentStarts.count ? segmentStarts[i + 1] : bytes.count
    }
}

/// A rectangle in pixels.
/// Tile flag byte of an image MZP.
public enum TileFlags: UInt8, Sendable {
    /// No texture is built and the tile is never displayed.
    case empty = 0
    /// May contain transparency; decoded and blended.
    case mayBeTransparent = 1
    /// Opaque hint; still blended with its alpha.
    case opaque = 2
}

/// One stored tile of a `Picture`.
public struct PictureTile: Sendable {
    public let index: Int
    public let flags: TileFlags
    public let storedWidth: Int
    public let storedHeight: Int
    /// The displayed part of the stored tile; the border around it is the filter apron.
    public let source: PixelRect
    /// Displayed position of `source` in the picture.
    public let x: Int
    public let y: Int
    /// Straight-alpha RGBA8 pixels of the whole stored tile, top-down; empty for empty tiles.
    public let rgba: [UInt8]

    public init(index: Int, flags: TileFlags, storedWidth: Int, storedHeight: Int,
                source: PixelRect, x: Int, y: Int, rgba: [UInt8]) {
        self.index = index
        self.flags = flags
        self.storedWidth = storedWidth
        self.storedHeight = storedHeight
        self.source = source
        self.x = x
        self.y = y
        self.rgba = rgba
    }
}

/// A decoded picture: straight-alpha RGBA8 tiles, row-major.
public struct Picture: Sendable {
    public let width: Int
    public let height: Int
    public let tiles: [PictureTile]

    public init(width: Int, height: Int, tiles: [PictureTile]) {
        self.width = width
        self.height = height
        self.tiles = tiles
    }
}

/// One glyph page of `ft_<lang>.mrg`: 1024 x 1024, fill images above, dilated outlines 512 px lower.
public struct FontPage: Sendable {
    public let language: Language
    public let page: Int
    public let width: Int
    public let height: Int
    /// Straight-alpha RGBA8 pixels, top-down.
    public let rgba: [UInt8]

    public init(language: Language, page: Int, width: Int, height: Int, rgba: [UInt8]) {
        self.language = language
        self.page = page
        self.width = width
        self.height = height
        self.rgba = rgba
    }
}

/// Audio banks of the game folder.
public enum AudioBank: UInt8, Sendable, CaseIterable {
    case bgm = 0
    case se = 1
    case voice = 2
    case voice2 = 3
    case vag = 4
}

/// A loop in playable sample frames, end inclusive.
public struct AudioLoop: Equatable, Sendable {
    public let start: Int
    public let end: Int
    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }

    public var length: Int { end - start + 1 }
}

/// Decoded audio: interleaved float32 PCM at 48 kHz, cut to the playable range. Samples are never
/// clipped.
public struct AudioClip: Sendable {
    public let bank: AudioBank
    public let index: Int
    public let channels: Int
    public let sampleRate: Int
    public let samples: [Float]
    public let loop: AudioLoop?

    public init(bank: AudioBank, index: Int, channels: Int, sampleRate: Int, samples: [Float], loop: AudioLoop?) {
        self.bank = bank
        self.index = index
        self.channels = channels
        self.sampleRate = sampleRate
        self.samples = samples
        self.loop = loop
    }

    public var frameCount: Int { channels == 0 ? 0 : samples.count / channels }
}

/// Decodes one audio entry's payload to PCM. Implemented by TsukiMedia; the data layer only parses
/// containers and headers.
public protocol AudioDecoder: AnyObject {
    func decode(bank: AudioBank, index: Int, payload: ByteSpan) throws -> AudioClip
}

/// UI sheet sets of allpac3 by their eboot names.
public enum UiSet: Int, CaseIterable, Sendable {
    case confParts = 0
    case dispParts
    case menuParts
    case modePnlParts
    case saveParts
    case titleParts
    case selectParts
    case selectTxtParts
    case borderParts
    case effectParts
    case noiseParts
    case galleryPartsCommon
    case galleryPartsCg
    case galleryPartsCgTh
    case galleryPartsMusic
    case galleryPartsFc
    case galleryPartsFcTh
    case galleryPartsMovie
    case galleryPartsEnding

    /// The eboot base name in upper case (`CONF_PARTS`).
    public var archiveName: String {
        switch self {
        case .confParts: return "CONF_PARTS"
        case .dispParts: return "DISP_PARTS"
        case .menuParts: return "MENU_PARTS"
        case .modePnlParts: return "MODEPNL_PARTS"
        case .saveParts: return "SAVE_PARTS"
        case .titleParts: return "TITLE_PARTS"
        case .selectParts: return "SELECT_PARTS"
        case .selectTxtParts: return "SELECTTXT_PARTS"
        case .borderParts: return "BORDER_PARTS"
        case .effectParts: return "EFFECT_PARTS"
        case .noiseParts: return "NOISE_PARTS"
        case .galleryPartsCommon: return "GALLERY_PARTS_COMMON"
        case .galleryPartsCg: return "GALLERY_PARTS_CG"
        case .galleryPartsCgTh: return "GALLERY_PARTS_CG_TH"
        case .galleryPartsMusic: return "GALLERY_PARTS_MUSIC"
        case .galleryPartsFc: return "GALLERY_PARTS_FC"
        case .galleryPartsFcTh: return "GALLERY_PARTS_FC_TH"
        case .galleryPartsMovie: return "GALLERY_PARTS_MOVIE"
        case .galleryPartsEnding: return "GALLERY_PARTS_ENDING"
        }
    }

    /// True when the set exists per language (`_JA`, `_EN`, ... suffix on the archive name).
    public var isLocalized: Bool {
        switch self {
        case .selectParts, .borderParts, .effectParts, .noiseParts: return false
        default: return true
        }
    }
}
