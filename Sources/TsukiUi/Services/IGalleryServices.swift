import Foundation

/// The persistent progress the gallery, the music player and the flowchart read (docs/formats/gallery.md 2.1): the unlock bit sets of the system data and the
/// per-playthrough marks of the running story. Every query takes the game's own numbers and answers false outside its range.
public protocol UiProgress: AnyObject {
    /// scene_seen(n), n at most 0x23F (G[110..145]): the scene was started at least once.
    func sceneSeen(_ n: Int) -> Bool

    /// scene_done(n), n at most 0x23F (G[300..335]): the scene was finished.
    func sceneDone(_ n: Int) -> Bool

    /// edge_seen(id), 564 to 1267 (G[400..443]): the flowchart edge or choice was taken in any playthrough.
    func edgeSeen(_ id: Int) -> Bool

    /// movie_seen bit 0..15 (G[5]): 0 = the first opening watched, 1 = the second.
    func movieSeen(_ bit: Int) -> Bool

    /// picture_seen(seenIndex), 0..3199: the picture block of the system data.
    func pictureSeen(_ seenIndex: Int) -> Bool

    /// bgm_heard(track): the BGM block of the system data (bit 0xC80 + track).
    func bgmHeard(_ track: Int) -> Bool

    /// RTST(n): the node was entered in this playthrough (the per-save words F[201..272]).
    func routeScene(_ n: Int) -> Bool

    /// The edge was taken in this playthrough (F[600..687]).
    func routeEdge(_ id: Int) -> Bool
}
public typealias IUiProgress = UiProgress

public extension UiProgress {
    func SceneSeen(_ n: Int) -> Bool { sceneSeen(n) }
    func SceneDone(_ n: Int) -> Bool { sceneDone(n) }
    func EdgeSeen(_ id: Int) -> Bool { edgeSeen(id) }
    func MovieSeen(_ bit: Int) -> Bool { movieSeen(bit) }
    func PictureSeen(_ seenIndex: Int) -> Bool { pictureSeen(seenIndex) }
    func BgmHeard(_ track: Int) -> Bool { bgmHeard(track) }
    func RouteScene(_ n: Int) -> Bool { routeScene(n) }
    func RouteEdge(_ id: Int) -> Bool { routeEdge(id) }
}

/// What the gallery (CG viewer, music player, movies, endings) and the flowchart need from the game besides `UiProgress` (package K5b).
public protocol UiGalleryServices: UiProgress {
    /// F110: the node of the running story (the in-game chart opens on it), 0 when no node was entered.
    var currentNode: Int { get }

    /// The BGM track that plays now (bgm.hed index), or 0 when none does.
    var playingBgm: Int { get }

    /// Sets bgm_heard(track): the player marks the track of an entry that a variant or a special rule unlocked.
    func markBgmHeard(_ track: Int)

    /// Starts `track` from its beginning at once at `volume` (0..1) and replaces whatever plays.
    func playMusic(_ track: Int, volume: Float)

    /// Pauses or resumes the BGM.
    func pauseMusic(_ paused: Bool)

    /// Sets the BGM volume (0..1) over a tenth of a second.
    func setMusicVolume(_ volume: Float)

    /// Stops the BGM at once.
    func stopMusic()

    /// True while a gallery replay runs (F024 is set: the archive scene 3000 plays a scene of the gallery).
    var replayActive: Bool { get }

    /// Replays a scene from the gallery (docs/formats/gallery.md 3.2).
    func replayScene(_ scriptScene: Int, node: Int)

    /// The system menu's FlowChart during a replay picked in the gallery's flowchart was confirmed: ends the replay, the story returns to the gallery.
    func endReplay()

    /// The in-game flowchart's jump (docs/formats/gallery.md 5.5).
    func flowchartJump(column: Int, node: Int, scene: Int) -> Bool
    func flowchartJump(_ column: Int, _ node: Int, _ scene: Int) -> Bool
}
public typealias IUiGalleryServices = UiGalleryServices

public extension UiGalleryServices {
    var CurrentNode: Int { currentNode }
    var PlayingBgm: Int { playingBgm }
    var ReplayActive: Bool { replayActive }

    func MarkBgmHeard(_ track: Int) { markBgmHeard(track) }
    func PlayMusic(_ track: Int, _ volume: Float) { playMusic(track, volume: volume) }
    func PauseMusic(_ paused: Bool) { pauseMusic(paused) }
    func SetMusicVolume(_ volume: Float) { setMusicVolume(volume) }
    func StopMusic() { stopMusic() }
    func ReplayScene(_ scriptScene: Int, _ node: Int) { replayScene(scriptScene, node: node) }
    func replayScene(_ scriptScene: Int, _ node: Int) { replayScene(scriptScene, node: node) }
    func EndReplay() { endReplay() }
    func flowchartJump(_ column: Int, _ node: Int, _ scene: Int) -> Bool { flowchartJump(column: column, node: node, scene: scene) }
    func FlowchartJump(_ column: Int, _ node: Int, _ scene: Int) -> Bool { flowchartJump(column: column, node: node, scene: scene) }
}
