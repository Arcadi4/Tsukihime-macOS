import Foundation
import Metal
import TsukiCore
import TsukiEngine
import TsukiData
import TsukiRender
import TsukiUi

public final class UiShotCommand: CliCommand {
    public var name: String { "ui-shot" }
    public var summary: String { "render a menu screen to a PNG through the GPU compositor; ui-shot <screen|--all> [--lang ja|en|zc|zt] [--prompts keyboard|playstation|xbox|auto] [--decide-cross] [--game DIR] [--out DIR] [--frames N]" }

    public init() {}

    public func run(_ args: [String], output: CliWriter, error: CliWriter) -> Int {
        var game: String? = nil
        var screen: String? = nil
        var outDir: String? = nil
        var lang = Language.en
        var frames = -1
        var all = false
        var prompts: PromptSetting? = nil
        var decideCross = false

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--prompts":
                if i + 1 < args.count {
                    i += 1
                    var parsed: PromptSetting = .auto
                    if !PromptStyles.tryParse(args[i], setting: &parsed) {
                        error.writeLine("ui-shot: --prompts takes keyboard, playstation, xbox or auto")
                        return ExitCode.usage
                    }
                    prompts = parsed
                }
            case "--game":
                if i + 1 < args.count {
                    i += 1
                    game = args[i]
                }
            case "--out":
                if i + 1 < args.count {
                    i += 1
                    outDir = args[i]
                }
            case "--frames":
                if i + 1 < args.count, let f = Int(args[i + 1]) {
                    i += 1
                    frames = f
                }
            case "--lang":
                if i + 1 < args.count {
                    i += 1
                    let l = args[i].lowercased()
                    switch l {
                    case "ja": lang = .ja
                    case "en": lang = .en
                    case "zc": lang = .zc
                    case "zt": lang = .zt
                    default:
                        error.writeLine("unknown language '\(l)'")
                        return ExitCode.usage
                    }
                }
            case "--all":
                all = true
            case "--decide-cross":
                decideCross = true
            default:
                if arg.hasPrefix("-") || screen != nil {
                    error.writeLine("ui-shot: unexpected argument '\(arg)'")
                    return ExitCode.usage
                }
                screen = arg
            }
            i += 1
        }

        if screen == nil && !all {
            error.writeLine("ui-shot: name a screen: " + UiPreview.screens.joined(separator: ", "))
            return ExitCode.usage
        }

        guard let folder = GameFolderLocator.resolve(game) else {
            error.writeLine("ui-shot: no game folder; pass --game <dir> or set TSUKI_GAME_DIR to the CUSA47999 folder")
            return ExitCode.usage
        }

        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: folder, isDirectory: &isDir) || !isDir.boolValue {
            error.writeLine("ui-shot: no game folder; pass --game <dir> or set TSUKI_GAME_DIR to the CUSA47999 folder")
            return ExitCode.usage
        }

        let out = outDir ?? (findRoot() as NSString).appendingPathComponent("scratch/K5a")
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

        let data: GameFolderSource
        do {
            data = try GameFolderSource.open(folder)
        } catch let err {
            error.writeLine("ui-shot: \(err)")
            return ExitCode.failed
        }

        guard let device = MTLCreateSystemDefaultDevice() else {
            error.writeLine("ui-shot: Metal is not supported on this device")
            return ExitCode.failed
        }

        let compositor: MetalCompositor
        do {
            compositor = try MetalCompositor(device: device, width: 1920, height: 1080)
        } catch let err {
            error.writeLine("ui-shot: cannot create Metal compositor: \(err)")
            return ExitCode.failed
        }

        let cache = TextureCache(device: device, capacityBytes: 2 << 30)
        let executor = DisplayListExecutor(compositor: compositor, textures: cache)
        let names = all ? UiPreview.screens : [screen!]

        for name in names {
            let start = Date()
            let services = PreviewServices(language: lang)
            if let p = prompts {
                services.promptSetting = p
            }
            services.decideIsCross = decideCross

            let parts = PartsPictureSource(data: data)
            let root = UiPreview.open(name, data: data, services: services, frames: frames, parts: parts)
            let list = DisplayList(capacity: 2048)
            list.reset(frame: 0)
            root.draw(list)
            list.seal()

            let uploader = UiTextureUploader(data: data, services: services, cache: cache, parts: parts, assets: root.context.assets)
            let uploaded = uploader.upload(list)
            compositor.clear(target: 0, r: 0, g: 0, b: 0, a: 255)
            let stats = executor.execute(list)
            var pixels = compositor.readTarget(0)
            var a = 3
            while a < pixels.count {
                pixels[a] = 255
                a += 4
            }

            let promptSuffix = prompts != nil ? "_" + PromptStyles.name(prompts!) : ""
            let file = (out as NSString).appendingPathComponent("ui_\(name)_\(lang.code)\(promptSuffix).png")
            try? PngWriter.write(file, width: 1920, height: 1080, rgba: pixels)

            let ms = Int(Date().timeIntervalSince(start) * 1000.0)
            let paddedName = name.padding(toLength: 18, withPad: " ", startingAt: 0)
            output.writeLine(String(format: "%@ %@: %5d commands, %5d quads, %d missing textures, %d textures, %d missing sheets, %d ms -> %@",
                                    paddedName, lang.code, list.commands.count, stats.draws, stats.missingTextures, uploaded, root.context.assets.missing.count, ms, file))
        }

        return ExitCode.ok
    }

    private func findRoot() -> String {
        let fm = FileManager.default
        var cur = URL(fileURLWithPath: fm.currentDirectoryPath)
        while cur.path != "/" {
            let slnx = cur.appendingPathComponent("src/Tsuki.slnx").path
            let pkg = cur.appendingPathComponent("Package.swift").path
            if fm.fileExists(atPath: slnx) || fm.fileExists(atPath: pkg) {
                return cur.path
            }
            cur = cur.deletingLastPathComponent()
        }
        return fm.currentDirectoryPath
    }
}

final class UiTextureUploader {
    private struct SheetKey: Hashable {
        let set: UiSet
        let lang: Language
        let child: Int
    }

    private struct FontKey: Hashable {
        let lang: Language
        let page: Int
    }

    private struct PictureKey: Hashable {
        let archive: Int
        let entry: Int
    }

    private let data: GameFolderSource
    private let services: PreviewServices
    private let cache: TextureCache
    private let parts: PartsPictureSource
    private let assets: UiAssets

    private var sheets: [SheetKey: Picture] = [:]
    private var fonts: [FontKey: FontPage] = [:]
    private var pictures: [PictureKey: Picture?] = [:]

    init(data: GameFolderSource, services: PreviewServices, cache: TextureCache, parts: PartsPictureSource, assets: UiAssets) {
        self.data = data
        self.services = services
        self.cache = cache
        self.parts = parts
        self.assets = assets
    }

    func upload(_ list: DisplayList) -> Int {
        var n = 0
        for c in list.commands {
            if c.kind != .texturedQuad || cache.contains(c.texture) {
                continue
            }

            let t = c.texture
            switch t.kind {
            case .uiTile:
                guard let set = UiSet(rawValue: Int(t.a)), let lang = Language(rawValue: UInt8(t.b)) else {
                    continue
                }
                let key = SheetKey(set: set, lang: lang, child: Int(t.c))
                let pic: Picture
                if let cached = sheets[key] {
                    pic = cached
                } else {
                    pic = data.uiSheet(key.set, key.lang, key.child)
                    sheets[key] = pic
                }

                if let tile = pic.tiles.first(where: { $0.index == Int(t.d) }) {
                    cache.upload(key: t, width: tile.storedWidth, height: tile.storedHeight, rgba: tile.rgba)
                    n += 1
                }

            case .glyphPage:
                guard let lang = Language(rawValue: UInt8(t.a)) else { continue }
                let key = FontKey(lang: lang, page: Int(t.b))
                let page: FontPage
                if let cached = fonts[key] {
                    page = cached
                } else {
                    page = data.fontPage(key.lang, key.page)
                    fonts[key] = page
                }

                cache.upload(key: t, width: page.width, height: page.height, rgba: page.rgba)
                n += 1

            case .pictureTile:
                let key = PictureKey(archive: Int(t.a), entry: Int(t.b))
                let pic: Picture?
                if let cached = pictures[key] {
                    pic = cached
                } else {
                    pic = Int(t.a) == UiPictureArchive.parts ? parts.parts(Int(t.b)) : data.picture(Int(t.a), Int(t.b))
                    pictures[key] = pic
                }

                if let tile = pic?.tiles.first(where: { $0.index == Int(t.c) }) {
                    cache.upload(key: t, width: tile.storedWidth, height: tile.storedHeight, rgba: tile.rgba)
                    n += 1
                }

            case .thumbnail:
                if let thumb = services.thumbnail(Int(t.a)) {
                    cache.upload(key: t, width: thumb.width, height: thumb.height, rgba: thumb.rgba)
                    n += 1
                }

            case .uiComposed:
                if let lang = Language(rawValue: UInt8(t.b)),
                   let pic = assets.composed(Int(t.a), language: lang) {
                    cache.upload(key: t, width: pic.width, height: pic.height, rgba: pic.rgba)
                    n += 1
                }

            default:
                break
            }
        }
        return n
    }
}

final class PartsPictureSource: UiPictureSource {
    private let data: GameFolderSource

    init(data: GameFolderSource) {
        self.data = data
    }

    func parts(_ index: Int) -> Picture? {
        do {
            let archive = try data.archive("parts")
            guard index >= 0 && index < archive.index.count else { return nil }
            let container = try archive.container(index)
            return try ImageMzp.open(container).toPicture(maxDegreeOfParallelism: 1)
        } catch {
            return nil
        }
    }
}
