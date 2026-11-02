import Foundation
import Metal
import TsukiCore
import TsukiData
import TsukiEngine
import TsukiMedia
import TsukiPlatform
import TsukiRender
import TsukiUi

public final class DataParts: UiPictureSource {
    public let data: GameFolderSource

    public init(data: GameFolderSource) {
        self.data = data
    }

    public func parts(_ index: Int) -> Picture? {
        try? data.parts(index)
    }
}

public final class ScriptCache: FlowScripts {
    private let source: GameFolderSource
    private var images: [Int: ScriptImage] = [:]
    private var labelsMap: [Int: LabelTable] = [:]
    private let lock = NSLock()

    public init(_ source: GameFolderSource) {
        self.source = source
    }

    public func script(_ k: Int) -> ScriptImage {
        lock.lock()
        defer { lock.unlock() }
        if let s = images[k] { return s }
        let s = source.script(k)
        images[k] = s
        return s
    }

    public func labels(_ k: Int) -> LabelTable {
        lock.lock()
        defer { lock.unlock() }
        if let l = labelsMap[k] { return l }
        let l = (try? source.scripts.labelLookup(k)) ?? LabelTable(records: [])
        labelsMap[k] = l
        return l
    }
}

public enum GameApp {
    public static let exitAlreadyRunning = 3
    public static let exitAudioDead = 5

    public static func run(args: AppArgs) -> Int {
        let dataDir = StartupSettings.dataDirectory(args)
        let startup = StartupSettings.load(args)
        let early = AppIdentity.startupLanguage(args: args, settings: startup.data, store: nil)

        guard let instance = SingleInstance.tryAcquire(dataDirectory: dataDir) else {
            let msg = "\(AppIdentity.productName): the game is already running on the profile \(dataDir)\n"
            if let data = msg.data(using: .utf8) {
                FileHandle.standardError.write(data)
            }
            if !args.hidden {
                MessageBox.showError(title: AppIdentity.productName, message: PortText.get(.alreadyRunning, early))
            }
            return exitAlreadyRunning
        }
        _ = instance

        let gameFolder = args.gameDir ?? FileManager.default.currentDirectoryPath
        let source: GameFolderSource
        do {
            source = try GameFolderSource.open(gameFolder)
        } catch {
            print("Failed to open game folder \(gameFolder): \(error)")
            CrashLog.append(dataDirectory: dataDir, logFile: args.logFile, text: "GameFolderSource.open failed: \(error)")
            if !args.hidden {
                MessageBox.showError(title: AppIdentity.productName, message: "Could not open game folder: \(error.localizedDescription)")
            }
            return 1
        }
        defer { source.dispose() }

        let savePath = args.noSave ? nil : (dataDir as NSString).appendingPathComponent("save.dat")
        var usedBackup = false
        var store: SaveStore
        if let savePath = savePath, FileManager.default.fileExists(atPath: savePath) {
            do {
                store = try SaveFile.readWithFallback(path: savePath, usedBackup: &usedBackup) ?? SaveStore()
            } catch {
                store = SaveStore()
            }
        } else {
            store = SaveStore()
        }

        let windowOptions = startup.windowOptions(title: AppIdentity.windowTitle(source: source, language: early))
        let window: GameWindow
        do {
            window = try GameWindow.create(options: windowOptions)
        } catch {
            print("Failed to create window: \(error)")
            return 1
        }
        defer { window.close() }

        let placement = startup.placeWindow(window)
        if !args.hidden {
            window.show()
        }
        if args.fullscreen || (startup.data.fullscreen == true) {
            window.setFullscreen(true)
        }

        guard let mtlDevice = window.metalView.device else {
            return 1
        }
        let compositor: MetalCompositor
        do {
            compositor = try MetalCompositor(device: mtlDevice)
        } catch {
            print("Failed to create compositor: \(error)")
            return 1
        }

        let cache = TextureCache(device: mtlDevice)
        let executor = DisplayListExecutor(compositor: compositor, textures: cache)
        let displaySettings = DisplaySettings(
            window: AppDisplayWindow(window: window),
            config: store.systemData.block.config,
            commit: {
                if let savePath = savePath {
                    try? SaveFile.commit(path: savePath, store: store)
                }
            },
            settingsPath: startup.path,
            windowedSize: (placement.width, placement.height)
        )

        let mixer = AudioMixer()
        let commandPlayer = AudioCommandPlayer(data: source, mixer: mixer)
        var audioOutput: AudioOutput?
        if !args.mute && !args.hidden {
            audioOutput = try? AudioOutput.openDevice { buffer in
                mixer.render(interleaved: buffer)
            }
            try? audioOutput?.start()
        }
        defer { audioOutput?.dispose() }

        let movieHost = MovieHost(data: source)
        let scriptCache = ScriptCache(source)
        let partsData = DataParts(data: source)
        let engineServices = TsukiEngine.GameServices(data: source, scripts: scriptCache)
        engineServices.layouts = source.layouts
        engineServices.seLookup = { name, flags in
            (try? source.soundEffectNames.lookup(name, flags: flags))?.index
        }

        let appParts = AppServicesParts(
            data: source,
            hostFactory: { lang, profile in
                let opt = GameOptions()
                opt.language = lang
                return GameHost(services: engineServices, options: opt, profile: profile)
            },
            store: store,
            audio: commandPlayer,
            movies: movieHost,
            savePath: savePath,
            initialLanguage: early,
            settingsPath: startup.path,
            promptOverride: args.prompts
        )

        let services = AppServices(parts: appParts)
        services.display = displaySettings

        let portSettings = PortSettings(settingsPath: startup.path, data: startup.data)
        services.port = portSettings

        let ui = UiRoot(data: source, services: services, parts: partsData)
        let feeder = TextureFeeder(data: source, cache: cache)
        feeder.thumbnails = { slot in services.thumbnail(slot) }
        feeder.movieFrames = { slot in movieHost.currentFrame(slot: slot) }

        let runtime = AppRuntime(services: services, ui: ui, audio: commandPlayer, movies: movieHost)
        runtime.grab = {
            let (w, h) = (320, 180)
            let (fw, fh) = (compositor.frame.width, compositor.frame.height)
            var fullRgba = [UInt8](repeating: 0, count: fw * fh * 4)
            compositor.frame.texture.getBytes(&fullRgba, bytesPerRow: fw * 4, from: MTLRegionMake2D(0, 0, fw, fh), mipmapLevel: 0)
            let down = ThumbnailCodec.downscale(fullRgba, width: fw, height: fh)
            return (width: w, height: h, rgba: down)
        }

        let input = PcInput(window: window)
        let displayList = DisplayList()
        let loop = MainLoop(window: window)

        runtime.start()

        _ = loop.run(
            onStep: { tick in
                services.observeDevice(input.lastDevice)
                let inFrame = input.sample(frame: tick.frame)
                _ = runtime.step(raw: inFrame, nominalTimestamp: tick.nominalTimestamp, list: displayList)
                _ = feeder.ensureResident(list: displayList, budget: 0.004)
                _ = executor.execute(displayList)

                if let drawable = window.metalView.currentDrawable {
                    compositor.draw(into: drawable.texture)
                    if let cmdBuf = window.metalView.device?.makeCommandQueue()?.makeCommandBuffer() {
                        cmdBuf.present(drawable)
                        cmdBuf.commit()
                    }
                }

                if args.exitAfter > 0 && tick.frame >= args.exitAfter {
                    return false
                }
                return !runtime.exitRequested
            },
            onPresent: { _ in },
            maxSeconds: args.seconds
        )

        _ = services.commit()
        return 0
    }
}
