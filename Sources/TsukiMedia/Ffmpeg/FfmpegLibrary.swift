import Darwin
import Foundation
import TsukiCore

public struct DecoderInfo: Sendable, Equatable {
    public let name: String
    public let longName: String
    public let codecId: Int
    public let mediaType: String

    public init(name: String, longName: String, codecId: Int, mediaType: String) {
        self.name = name
        self.longName = longName
        self.codecId = codecId
        self.mediaType = mediaType
    }
}

public struct FfmpegVersion: Sendable, Equatable {
    public let build: String
    public let avcodec: String
    public let avutil: String
    public let license: String

    public init(build: String, avcodec: String, avutil: String, license: String) {
        self.build = build
        self.avcodec = avcodec
        self.avutil = avutil
        self.license = license
    }
}

public enum FfmpegError: Error, CustomStringConvertible {
    case missing(folder: String, missingFiles: [String])
    case alreadyLoaded(String)
    case notLoaded
    case loadFailed(String)
    case symbolNotFound(String)
    case codecNotFound(String)
    case nativeError(code: Int32, message: String)

    public var description: String {
        switch self {
        case let .missing(folder, missing):
            return "FFmpeg shared libraries missing from \(folder): \(missing.joined(separator: ", "))"
        case let .alreadyLoaded(path):
            return "FFmpeg is already loaded from \(path)"
        case .notLoaded:
            return "FfmpegLibrary.load has not been called"
        case let .loadFailed(msg):
            return "Failed to load FFmpeg: \(msg)"
        case let .symbolNotFound(sym):
            return "FFmpeg symbol not found: \(sym)"
        case let .codecNotFound(name):
            return "Decoder not found: \(name)"
        case let .nativeError(code, msg):
            return "FFmpeg error (\(code)): \(msg)"
        }
    }
}

/// Dynamically loaded FFmpeg functions.
public final class FfmpegBindings: @unchecked Sendable {
    public static let shared = FfmpegBindings()

    // Library handles
    public var avutilHandle: UnsafeMutableRawPointer?
    public var swresampleHandle: UnsafeMutableRawPointer?
    public var avcodecHandle: UnsafeMutableRawPointer?
    public var avformatHandle: UnsafeMutableRawPointer?

    // libavutil
    public var av_version_info: (@convention(c) () -> UnsafePointer<CChar>?)?
    public var avutil_version: (@convention(c) () -> UInt32)?
    public var av_mallocz: (@convention(c) (Int) -> UnsafeMutableRawPointer?)?
    public var av_free: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?
    public var av_log_set_level: (@convention(c) (Int32) -> Void)?
    public var av_channel_layout_default: (@convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32)?
    public var av_channel_layout_uninit: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?
    public var av_frame_alloc: (@convention(c) () -> UnsafeMutableRawPointer?)?
    public var av_frame_free: (@convention(c) (UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Void)?
    public var av_frame_unref: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?
    public var av_strerror: (@convention(c) (Int32, UnsafeMutablePointer<CChar>?, Int) -> Int32)?

    // libavcodec
    public var avcodec_version: (@convention(c) () -> UInt32)?
    public var avcodec_license: (@convention(c) () -> UnsafePointer<CChar>?)?
    public var avcodec_find_decoder_by_name: (@convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer?)?
    public var av_codec_is_decoder: (@convention(c) (UnsafeMutableRawPointer?) -> Int32)?
    public var av_get_media_type_string: (@convention(c) (Int32) -> UnsafePointer<CChar>?)?
    public var avcodec_alloc_context3: (@convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?)?
    public var avcodec_free_context: (@convention(c) (UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Void)?
    public var avcodec_open2: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32)?
    public var av_packet_alloc: (@convention(c) () -> UnsafeMutableRawPointer?)?
    public var av_packet_free: (@convention(c) (UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Void)?
    public var avcodec_send_packet: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Int32)?
    public var avcodec_receive_frame: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Int32)?
    public var avcodec_flush_buffers: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?

    // libswresample
    public var swresample_version: (@convention(c) () -> UInt32)?

    // libavformat
    public var avformat_version: (@convention(c) () -> UInt32)?

    private init() {}
}

/// Loads pinned FFmpeg native libraries and looks up decoders.
public enum FfmpegLibrary {
    public static let avcodecDll = "libavcodec.63.dylib"

    public static let requiredDlls: [String] = [
        "libavutil.61.dylib",
        "libswresample.7.dylib",
        "libavcodec.63.dylib",
        "libavformat.63.dylib"
    ]

    public static let fallbackDlls: [String] = [
        "libavutil.dylib",
        "libswresample.dylib",
        "libavcodec.dylib",
        "libavformat.dylib"
    ]

    public static let requiredDecoders: [String] = ["atrac9", "h264", "aac"]

    private static let lock = NSLock()
    private static var _root: String?

    public static var isLoaded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _root != nil
    }

    public static var rootPath: String {
        lock.lock()
        defer { lock.unlock() }
        guard let r = _root else {
            fatalError("FfmpegLibrary.load has not been called")
        }
        return r
    }

    @discardableResult
    public static func load(folder: String? = nil) throws -> FfmpegVersion {
        lock.lock()
        defer { lock.unlock() }

        if let existing = _root {
            if let req = folder {
                let full = (req as NSString).standardizingPath
                let current = (existing as NSString).standardizingPath
                if full != current {
                    throw FfmpegError.alreadyLoaded(existing)
                }
            }
            return try versionLocked()
        }

        let searchFolder = folder.map { ($0 as NSString).standardizingPath } ?? defaultFolder()
        guard let root = libraryFolder(searchFolder) else {
            throw FfmpegError.missing(folder: searchFolder, missingFiles: missingFiles(searchFolder))
        }

        try bindLibraries(in: root)
        _root = root
        return try versionLocked()
    }

    public static func version() throws -> FfmpegVersion {
        lock.lock()
        defer { lock.unlock() }
        guard _root != nil else { throw FfmpegError.notLoaded }
        return try versionLocked()
    }

    private static func versionLocked() throws -> FfmpegVersion {
        let b = FfmpegBindings.shared
        guard let buildFn = b.av_version_info,
              let codecVerFn = b.avcodec_version,
              let utilVerFn = b.avutil_version,
              let licenseFn = b.avcodec_license else {
            throw FfmpegError.notLoaded
        }

        let build = buildFn().map { String(cString: $0) } ?? ""
        let license = licenseFn().map { String(cString: $0) } ?? ""
        let codecVer = formatVersion(codecVerFn())
        let utilVer = formatVersion(utilVerFn())

        return FfmpegVersion(build: build, avcodec: codecVer, avutil: utilVer, license: license)
    }

    public static func findDecoder(_ name: String) throws -> DecoderInfo? {
        lock.lock()
        defer { lock.unlock() }
        guard _root != nil else { throw FfmpegError.notLoaded }
        let b = FfmpegBindings.shared
        guard let findFn = b.avcodec_find_decoder_by_name,
              let isDecFn = b.av_codec_is_decoder,
              let typeStrFn = b.av_get_media_type_string else {
            throw FfmpegError.notLoaded
        }

        guard let codec = name.withCString({ findFn($0) }) else {
            return nil
        }
        if isDecFn(codec) == 0 {
            return nil
        }

        // AVCodec struct: name (ptr), long_name (ptr), type (int32), id (int32)
        let namePtr = codec.load(as: UnsafePointer<CChar>?.self)
        let longNamePtr = codec.advanced(by: MemoryLayout<UnsafePointer<CChar>?>.size).load(as: UnsafePointer<CChar>?.self)
        let mediaTypeOffset = MemoryLayout<UnsafePointer<CChar>?>.size * 2
        let typeInt = codec.advanced(by: mediaTypeOffset).load(as: Int32.self)
        let idInt = codec.advanced(by: mediaTypeOffset + 4).load(as: Int32.self)

        let shortName = namePtr.map { String(cString: $0) } ?? name
        let longName = longNamePtr.map { String(cString: $0) } ?? shortName
        let mediaType = typeStrFn(typeInt).map { String(cString: $0) } ?? ""

        return DecoderInfo(name: shortName, longName: longName, codecId: Int(idInt), mediaType: mediaType)
    }

    public static func loadedModulePaths() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        var paths: [String] = []
        for image in NativeImages.enumerate() {
            if requiredDlls.contains(where: { matches(image, $0) }) || fallbackDlls.contains(where: { matches(image, $0) }) {
                paths.append(image)
            }
        }
        return paths.sorted()
    }

    private static func matches(_ path: String, _ required: String) -> Bool {
        let file = (path as NSString).lastPathComponent
        if file.caseInsensitiveCompare(required) == .orderedSame {
            return true
        }
        if required.hasSuffix(".dylib") {
            let stem = String(required.dropLast(6))
            return file.hasPrefix(stem + ".") && file.hasSuffix(".dylib")
        }
        return file.hasPrefix(required + ".")
    }

    private static func candidates(app: String) -> [String] {
        var dirs: [String] = [app]
        dirs.append(((app as NSString).deletingLastPathComponent as NSString).appendingPathComponent("Frameworks"))
        if let prefix = ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"], !prefix.isEmpty {
            dirs.append((prefix as NSString).appendingPathComponent("lib"))
        }
        dirs.append("/opt/homebrew/lib")
        dirs.append("/usr/local/lib")
        return dirs
    }

    private static func libraryFolder(_ folder: String) -> String? {
        let fm = FileManager.default
        let hasVersioned = requiredDlls.allSatisfy { fm.fileExists(atPath: ($0 as NSString).isAbsolutePath ? $0 : (folder as NSString).appendingPathComponent($0)) }
        if hasVersioned {
            return folder
        }
        let hasFallback = fallbackDlls.allSatisfy { fm.fileExists(atPath: (folder as NSString).appendingPathComponent($0)) }
        if hasFallback {
            return folder
        }
        return nil
    }

    private static func missingFiles(_ folder: String) -> [String] {
        let fm = FileManager.default
        var missing: [String] = []
        for dll in requiredDlls {
            let path = (folder as NSString).appendingPathComponent(dll)
            if !fm.fileExists(atPath: path) {
                missing.append(dll)
            }
        }
        return missing
    }

    private static func defaultFolder() -> String {
        let app = Bundle.main.bundlePath
        for cand in candidates(app: app) {
            if let f = libraryFolder(cand) {
                return f
            }
        }
        return "/opt/homebrew/lib"
    }

    private static func bindLibraries(in root: String) throws {
        let fm = FileManager.default
        func dylibPath(_ base: String, fallback: String) -> String {
            let p1 = (root as NSString).appendingPathComponent(base)
            if fm.fileExists(atPath: p1) { return p1 }
            let p2 = (root as NSString).appendingPathComponent(fallback)
            if fm.fileExists(atPath: p2) { return p2 }
            return p1
        }

        let utilPath = dylibPath("libavutil.61.dylib", fallback: "libavutil.dylib")
        let swrPath = dylibPath("libswresample.7.dylib", fallback: "libswresample.dylib")
        let codecPath = dylibPath("libavcodec.63.dylib", fallback: "libavcodec.dylib")
        let formatPath = dylibPath("libavformat.63.dylib", fallback: "libavformat.dylib")

        guard let util = dlopen(utilPath, RTLD_NOW | RTLD_GLOBAL) else {
            throw FfmpegError.loadFailed("dlopen(\(utilPath)) failed: \(String(cString: dlerror()))")
        }
        guard let swr = dlopen(swrPath, RTLD_NOW | RTLD_GLOBAL) else {
            throw FfmpegError.loadFailed("dlopen(\(swrPath)) failed: \(String(cString: dlerror()))")
        }
        guard let codec = dlopen(codecPath, RTLD_NOW | RTLD_GLOBAL) else {
            throw FfmpegError.loadFailed("dlopen(\(codecPath)) failed: \(String(cString: dlerror()))")
        }
        guard let format = dlopen(formatPath, RTLD_NOW | RTLD_GLOBAL) else {
            throw FfmpegError.loadFailed("dlopen(\(formatPath)) failed: \(String(cString: dlerror()))")
        }

        let b = FfmpegBindings.shared
        b.avutilHandle = util
        b.swresampleHandle = swr
        b.avcodecHandle = codec
        b.avformatHandle = format

        func sym<T>(_ handle: UnsafeMutableRawPointer, _ name: String) throws -> T {
            guard let ptr = dlsym(handle, name) else {
                throw FfmpegError.symbolNotFound(name)
            }
            return unsafeBitCast(ptr, to: T.self)
        }

        // util
        b.av_version_info = try sym(util, "av_version_info")
        b.avutil_version = try sym(util, "avutil_version")
        b.av_mallocz = try sym(util, "av_mallocz")
        b.av_free = try sym(util, "av_free")
        b.av_log_set_level = try sym(util, "av_log_set_level")
        b.av_channel_layout_default = try sym(util, "av_channel_layout_default")
        b.av_channel_layout_uninit = try? sym(util, "av_channel_layout_uninit")
        b.av_frame_alloc = try sym(util, "av_frame_alloc")
        b.av_frame_free = try sym(util, "av_frame_free")
        b.av_frame_unref = try sym(util, "av_frame_unref")
        b.av_strerror = try sym(util, "av_strerror")

        // codec
        b.avcodec_version = try sym(codec, "avcodec_version")
        b.avcodec_license = try sym(codec, "avcodec_license")
        b.avcodec_find_decoder_by_name = try sym(codec, "avcodec_find_decoder_by_name")
        b.av_codec_is_decoder = try sym(codec, "av_codec_is_decoder")
        b.av_get_media_type_string = try sym(codec, "av_get_media_type_string")
        b.avcodec_alloc_context3 = try sym(codec, "avcodec_alloc_context3")
        b.avcodec_free_context = try sym(codec, "avcodec_free_context")
        b.avcodec_open2 = try sym(codec, "avcodec_open2")
        b.av_packet_alloc = try sym(codec, "av_packet_alloc")
        b.av_packet_free = try sym(codec, "av_packet_free")
        b.avcodec_send_packet = try sym(codec, "avcodec_send_packet")
        b.avcodec_receive_frame = try sym(codec, "avcodec_receive_frame")
        b.avcodec_flush_buffers = try sym(codec, "avcodec_flush_buffers")

        // swresample
        b.swresample_version = try sym(swr, "swresample_version")

        // format
        b.avformat_version = try sym(format, "avformat_version")

        // AV_LOG_ERROR = 16
        b.av_log_set_level?(16)
    }

    private static func formatVersion(_ v: UInt32) -> String {
        "\(v >> 16).\((v >> 8) & 0xFF).\(v & 0xFF)"
    }
}
