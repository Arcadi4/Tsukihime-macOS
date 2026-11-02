import Foundation
import TsukiCore

public typealias IGameData = GameData
public typealias IFlowScripts = FlowScripts
public typealias IPictureLayoutSource = PictureLayoutSource

/// What the game interpreter needs from the outside world besides `GameData` (which already carries the picture catalog, the
/// motions, the glyph tables and the scene tables through `EbootTables`): the script label tables, the sound-effect name lookup
/// and the picture layout source of the stage. The composition root builds it over `GameFolderSource`.
public final class GameServices {
    /// The game data.
    public let data: any GameData

    /// The scripts and their label tables (the VM switches scripts through it).
    public let scripts: any FlowScripts

    /// The sound-effect lookup of `_SEPL` (name, flags) to the vse entry (`SeNames.lookup`); nil: every name is unknown.
    public var seLookup: ((String, Int) -> Int?)?

    /// The picture layout source of the stage draw; nil: the layers produce no quads (headless runs).
    public var layouts: (any PictureLayoutSource)?

    /// How many 60 Hz frames a sound stream plays: voices (`AudioBank.voice`) and effects. Headless runs have no mixer, so this
    /// stands in for `AudioCommandPlayer.isPlaying`; nil: a voice lasts `GameOptions.defaultVoiceFrames` frames.
    public var clipFrames: ((AudioBank, Int) -> Int)?

    /// Creates the services.
    /// - Parameters:
    ///   - data: The game data.
    ///   - scripts: The scripts and their label tables (the VM switches scripts through it).
    public init(data: any GameData, scripts: any FlowScripts) {
        self.data = data
        self.scripts = scripts
    }
}

/// Options of a game session.
public final class GameOptions {
    /// The game language (the config language is set from it at a new profile).
    public var language: Language = .en

    /// Frames a voice lasts when `GameServices.clipFrames` is nil.
    public var defaultVoiceFrames: Int = 120

    /// The movie clock: when true (headless runs and the explorer) a movie ends as soon as its start-up countdown is over; when false the
    /// host waits for the `MovieClock` the movie host reports each frame.
    public var virtualMovies: Bool = true

    /// When true, an unknown command is an error even outside TSUKI_DEV builds.
    public var strictCommands: Bool = false

    /// When true, unknown commands are counted (`GameHost.unknownCommands`) instead of throwing.
    public var recordUnknownCommands: Bool = false

    /// Seed of the stage's `rand()` (0: the engine's initial state 1).
    public var randomSeed: UInt32 = 0

    /// When true, sound commands are executed (the sound model runs); headless coverage runs can switch it off.
    public var sound: Bool = true

    public init() {}
}
