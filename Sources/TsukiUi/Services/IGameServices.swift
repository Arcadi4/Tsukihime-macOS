import Foundation
import TsukiCore
import TsukiEngine

/// The PS4 system sounds (`SystemSE_Play(id)`, docs/formats/sound_runtime.md 10.1): the ids the menus play.
public enum UiSound: Int, Sendable {
    /// Decide: confirm a choice, open a screen (id 0, moon_se00002).
    case decide = 0
    /// Done: a save or a delete finished, a dialog answered (id 1, moon_se00003).
    case done = 1
    /// Cursor move (id 2, moon_se00001; docs/formats/system_flow.md 4.4 "a change plays SE 2").
    case cursor = 2
    /// Open a dialog or the backlog (id 3, moon_se00007).
    case open = 3
    /// PRESS ANY BUTTON and NEW GAME (id 5, moon_se00011; system_flow.md 4.3, 4.4).
    case start = 5
    /// Buzzer: the action is not available (id 6, moon_se00003; system_flow.md 4.4).
    case buzzer = 6

    public static let Decide = UiSound.decide
    public static let Done = UiSound.done
    public static let Cursor = UiSound.cursor
    public static let Open = UiSound.open
    public static let Start = UiSound.start
    public static let Buzzer = UiSound.buzzer
}

/// The banner of the mode panel's feedback (DISP_PARTS child 10, four rows; knife `Banner`).
public enum BannerKind: Int, Sendable {
    /// Skip on.
    case skip = 0
    /// Quick save done.
    case quickSave = 1
    /// Auto save done.
    case autoSave = 2
    /// Auto mode on.
    case auto = 3

    public static let Skip = BannerKind.skip
    public static let QuickSave = BannerKind.quickSave
    public static let AutoSave = BannerKind.autoSave
    public static let Auto = BannerKind.auto
}

/// What the config screen changed, so the game applies it (volumes, language reload, voice gates).
public enum ConfigChange: Sendable {
    case volume
    case setting
    case language
    case reset

    public static let Volume = ConfigChange.volume
    public static let Setting = ConfigChange.setting
    public static let Language = ConfigChange.language
    public static let Reset = ConfigChange.reset
}

/// One save slot as the list shows it (docs/formats/adv_state.md 7).
public struct UiSlot: Equatable, Sendable {
    public var index: Int
    public var used: Bool
    public var date: Date
    public var phase: Int
    public var sceneTitle: Int
    public var notes: String

    public var Index: Int { index }
    public var Used: Bool { used }
    public var DateVal: Date { date }
    public var Phase: Int { phase }
    public var SceneTitle: Int { sceneTitle }
    public var Notes: String { notes }

    public init(index: Int, used: Bool, date: Date, phase: Int, sceneTitle: Int, notes: String) {
        self.index = index
        self.used = used
        self.date = date
        self.phase = phase
        self.sceneTitle = sceneTitle
        self.notes = notes
    }
}

/// A slot thumbnail: straight-alpha RGBA8 pixels, top-down.
public final class UiThumbnail: Sendable {
    public let width: Int
    public let height: Int
    public let version: Int
    public let rgba: [UInt8]

    public var Width: Int { width }
    public var Height: Int { height }
    public var Version: Int { version }
    public var Rgba: [UInt8] { rgba }

    public init(width: Int, height: Int, version: Int, rgba: [UInt8]) {
        self.width = width
        self.height = height
        self.version = version
        self.rgba = rgba
    }
}

/// One message of a backlog page.
public final class BacklogMessage: Sendable {
    public let text: [UInt8]
    public let blankBefore: Int
    public let voiceId: Int

    public var Text: [UInt8] { text }
    public var BlankBefore: Int { blankBefore }
    public var VoiceId: Int { voiceId }

    public init(text: [UInt8], blankBefore: Int = 0, voiceId: Int = -1) {
        self.text = text
        self.blankBefore = blankBefore
        self.voiceId = voiceId
    }
}

/// One page of the history the backlog shows (docs/formats/adv_state.md 5.4).
public final class BacklogPage: Sendable {
    public let messages: [BacklogMessage]
    public let jumpable: Bool

    public var Messages: [BacklogMessage] { messages }
    public var Jumpable: Bool { jumpable }

    public init(messages: [BacklogMessage], jumpable: Bool = true) {
        self.messages = messages
        self.jumpable = jumpable
    }
}

/// What the title needs to know about the player's progress (docs/formats/system_flow.md 1, 3.4, 4.2).
public struct UiTitleInfo: Equatable, Sendable {
    public var prologueSeen: Bool
    public var storyStarted: Bool
    public var titleStage: Int
    public var continueSlot: Int

    public var PrologueSeen: Bool { prologueSeen }
    public var StoryStarted: Bool { storyStarted }
    public var TitleStage: Int { titleStage }
    public var ContinueSlot: Int { continueSlot }

    public init(prologueSeen: Bool, storyStarted: Bool, titleStage: Int, continueSlot: Int) {
        self.prologueSeen = prologueSeen
        self.storyStarted = storyStarted
        self.titleStage = titleStage
        self.continueSlot = continueSlot
    }
}

/// The PC port's display settings (package K19).
public protocol UiDisplaySettings: AnyObject {
    var fullscreen: Bool { get set }
    var windowSize: (width: Int, height: Int) { get set }
    var sizeChoices: [(width: Int, height: Int)] { get }
}
public typealias IUiDisplaySettings = UiDisplaySettings

public extension UiDisplaySettings {
    var Fullscreen: Bool { get { fullscreen } set { fullscreen = newValue } }
    var WindowSize: (width: Int, height: Int) { get { windowSize } set { windowSize = newValue } }
    var SizeChoices: [(width: Int, height: Int)] { sizeChoices }
}

/// The PC port's own switches (package K21).
public protocol UiPortSettings: AnyObject {
    var muteInBackground: Bool { get set }
    var copyTextToClipboard: Bool { get set }
    var textHookerOutput: Bool { get set }
    var textWebSocket: Bool { get set }
    var screenshotNotice: Bool { get set }
}
public typealias IUiPortSettings = UiPortSettings

public extension UiPortSettings {
    var MuteInBackground: Bool { get { muteInBackground } set { muteInBackground = newValue } }
    var CopyTextToClipboard: Bool { get { copyTextToClipboard } set { copyTextToClipboard = newValue } }
    var TextHookerOutput: Bool { get { textHookerOutput } set { textHookerOutput = newValue } }
    var TextWebSocket: Bool { get { textWebSocket } set { textWebSocket = newValue } }
    var ScreenshotNotice: Bool { get { screenshotNotice } set { screenshotNotice = newValue } }
}

/// Time, sound, language, configuration and progress: what every screen reads from the game.
public protocol UiSystemServices: AnyObject {
    var display: UiDisplaySettings? { get }
    var port: UiPortSettings? { get }
    var language: Language { get }
    var config: ConfigBlock { get }
    func configChanged(_ change: ConfigChange)
    func commitSystemData()
    var decideIsCross: Bool { get }
    var promptSetting: PromptSetting { get set }
    var promptStyle: PromptStyle { get }
    func global(_ index: Int) -> Int
    func setGlobal(_ index: Int, _ value: Int)
    func sceneBit(_ bit: Int) -> Bool
    func playSystemSound(_ sound: UiSound)
    func playTestSe()
    func playTestVoice(_ row: Int) -> Bool
    func stopTests()
    func playBgm(_ track: Int)
    func fadeOutBgm(_ seconds: Float)
    func startTitleMovie(_ movieIndex: Int)
    func stopTitleMovie()
    var titleMovieSlot: Int { get }
    var introMovieSlot: Int { get }
    func seekTitleMovie(_ seconds: Double)
    var titleMovieTime: Double { get }
    func startIntroMovie(_ movieIndex: Int)
    var introMoviePlaying: Bool { get }
    func stopIntroMovie()
}
public typealias IUiSystemServices = UiSystemServices

public extension UiSystemServices {
    var display: UiDisplaySettings? { nil }
    var port: UiPortSettings? { nil }
    var promptSetting: PromptSetting { get { .playStation } set {} }
    var promptStyle: PromptStyle { .playStation }

    var Display: UiDisplaySettings? { display }
    var Port: UiPortSettings? { port }
    var LanguageVal: Language { language }
    var Config: ConfigBlock { config }
    var DecideIsCross: Bool { decideIsCross }
    var PromptSettingVal: PromptSetting { get { promptSetting } set { promptSetting = newValue } }
    var PromptStyleVal: PromptStyle { promptStyle }
    var TitleMovieSlot: Int { titleMovieSlot }
    var IntroMovieSlot: Int { introMovieSlot }
    var TitleMovieTime: Double { titleMovieTime }
    var IntroMoviePlaying: Bool { introMoviePlaying }

    func ConfigChanged(_ change: ConfigChange) { configChanged(change) }
    func CommitSystemData() { commitSystemData() }
    func Global(_ index: Int) -> Int { global(index) }
    func SetGlobal(_ index: Int, _ value: Int) { setGlobal(index, value) }
    func SceneBit(_ bit: Int) -> Bool { sceneBit(bit) }
    func PlaySystemSound(_ sound: UiSound) { playSystemSound(sound) }
    func PlayTestSe() { playTestSe() }
    func PlayTestVoice(_ row: Int) -> Bool { playTestVoice(row) }
    func StopTests() { stopTests() }
    func PlayBgm(_ track: Int) { playBgm(track) }
    func FadeOutBgm(_ seconds: Float) { fadeOutBgm(seconds) }
    func StartTitleMovie(_ movieIndex: Int) { startTitleMovie(movieIndex) }
    func StopTitleMovie() { stopTitleMovie() }
    func SeekTitleMovie(_ seconds: Double) { seekTitleMovie(seconds) }
    func StartIntroMovie(_ movieIndex: Int) { startIntroMovie(movieIndex) }
    func StopIntroMovie() { stopIntroMovie() }
}

/// Saving and loading (docs/formats/adv_state.md 7).
public protocol UiSaveServices: AnyObject {
    var savingDisabled: Bool { get }
    var slots: [UiSlot] { get }
    func thumbnail(_ slot: Int) -> UiThumbnail?
    func save(_ slot: Int) -> Bool
    func load(_ slot: Int) -> Bool
    func delete(_ slot: Int) -> Bool
    func copy(_ slot: Int) -> Bool
    func quickSave() -> Bool
    func quickLoad() -> Bool
    var hasQuickSave: Bool { get }
}
public typealias IUiSaveServices = UiSaveServices

public extension UiSaveServices {
    var SavingDisabled: Bool { savingDisabled }
    var Slots: [UiSlot] { slots }
    var HasQuickSave: Bool { hasQuickSave }

    func Thumbnail(_ slot: Int) -> UiThumbnail? { thumbnail(slot) }
    func Save(_ slot: Int) -> Bool { save(slot) }
    func Load(_ slot: Int) -> Bool { load(slot) }
    func Delete(_ slot: Int) -> Bool { delete(slot) }
    func Copy(_ slot: Int) -> Bool { copy(slot) }
    func QuickSave() -> Bool { quickSave() }
    func QuickLoad() -> Bool { quickLoad() }
}

/// The running story: scene state the system menu and the mode panel read, and the actions they take.
public protocol UiStoryServices: AnyObject {
    var phase: Int { get }
    var sceneTitle: Int { get }
    var script: Int { get }
    var autoMode: Bool { get }
    var skipMode: Bool { get }
    var sceneJumpEnabled: Bool { get }
    var panelAllowed: Bool { get }
    func toggleAuto()
    func toggleSkip()
    func fastForward(_ held: Bool)
    func replayVoice()
    func nextScene()
    func previousScene()
    func rewind(_ held: Bool)
    func startScene(_ sceneId: Int)
    func resumeLoaded()
    func autoSaveForTitle() -> Bool
    func returnToTitle()
    var backlog: [BacklogPage] { get }
    func playBacklogVoice(_ voiceId: Int)
    func backlogJump(_ page: Int)
    func openFlowchart()
    func openGallery()
}
public typealias IUiStoryServices = UiStoryServices

public extension UiStoryServices {
    var Phase: Int { phase }
    var SceneTitle: Int { sceneTitle }
    var Script: Int { script }
    var AutoMode: Bool { autoMode }
    var SkipMode: Bool { skipMode }
    var SceneJumpEnabled: Bool { sceneJumpEnabled }
    var PanelAllowed: Bool { panelAllowed }
    var Backlog: [BacklogPage] { backlog }

    func ToggleAuto() { toggleAuto() }
    func ToggleSkip() { toggleSkip() }
    func FastForward(_ held: Bool) { fastForward(held) }
    func ReplayVoice() { replayVoice() }
    func NextScene() { nextScene() }
    func PreviousScene() { previousScene() }
    func Rewind(_ held: Bool) { rewind(held) }
    func StartScene(_ sceneId: Int) { startScene(sceneId) }
    func ResumeLoaded() { resumeLoaded() }
    func AutoSaveForTitle() -> Bool { autoSaveForTitle() }
    func ReturnToTitle() { returnToTitle() }
    func PlayBacklogVoice(_ voiceId: Int) { playBacklogVoice(voiceId) }
    func BacklogJump(_ page: Int) { backlogJump(page) }
    func OpenFlowchart() { openFlowchart() }
    func OpenGallery() { openGallery() }
}

/// Everything the menus talk to the game through (package K5a).
public protocol GameServices: UiSystemServices, UiSaveServices, UiStoryServices, UiGalleryServices {
    var storyPrompt: UiStoryPrompt? { get }
    var title: UiTitleInfo { get }
    func requestQuit()
}
public typealias IGameServices = GameServices

public extension GameServices {
    var storyPrompt: UiStoryPrompt? { nil }
    func requestQuit() {}

    var StoryPrompt: UiStoryPrompt? { storyPrompt }
    var Title: UiTitleInfo { title }
    func RequestQuit() { requestQuit() }

    func sceneSeen(_ n: Int) -> Bool {
        sceneBit(n)
    }
}
