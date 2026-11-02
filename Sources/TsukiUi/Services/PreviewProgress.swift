import Foundation
import TsukiEngine

/// The unlock bits of a `PreviewServices` game: plain sets, with helpers that build a believable player from the eboot tables.
public final class PreviewProgress: UiProgress {
    /// scene_seen bits.
    public var seen: Set<Int> = []
    public var Seen: Set<Int> { get { seen } set { seen = newValue } }

    /// scene_done bits.
    public var done: Set<Int> = []
    public var Done: Set<Int> { get { done } set { done = newValue } }

    /// edge_seen ids (564..1267).
    public var edges: Set<Int> = []
    public var Edges: Set<Int> { get { edges } set { edges = newValue } }

    /// The nodes of this playthrough (RTST).
    public var route: Set<Int> = []
    public var Route: Set<Int> { get { route } set { route = newValue } }

    /// The edges of this playthrough.
    public var routeEdges: Set<Int> = []
    public var RouteEdges: Set<Int> { get { routeEdges } set { routeEdges = newValue } }

    /// movie_seen bits.
    public var movies: Set<Int> = []
    public var Movies: Set<Int> { get { movies } set { movies = newValue } }

    /// picture_seen bits (0..3199).
    public var pictures: Set<Int> = []
    public var Pictures: Set<Int> { get { pictures } set { pictures = newValue } }

    /// bgm_heard tracks.
    public var bgm: Set<Int> = []
    public var Bgm: Set<Int> { get { bgm } set { bgm = newValue } }

    public init() {}

    public func sceneSeen(_ n: Int) -> Bool { seen.contains(n) }
    public func sceneDone(_ n: Int) -> Bool { done.contains(n) }
    public func edgeSeen(_ id: Int) -> Bool { edges.contains(id) }
    public func movieSeen(_ bit: Int) -> Bool { movies.contains(bit) }
    public func pictureSeen(_ seenIndex: Int) -> Bool { pictures.contains(seenIndex) }
    public func bgmHeard(_ track: Int) -> Bool { bgm.contains(track) }
    public func routeScene(_ n: Int) -> Bool { route.contains(n) }
    public func routeEdge(_ id: Int) -> Bool { routeEdges.contains(id) }

    /// Forgets everything.
    public func clear() {
        seen.removeAll()
        done.removeAll()
        edges.removeAll()
        route.removeAll()
        routeEdges.removeAll()
        movies.removeAll()
        pictures.removeAll()
        bgm.removeAll()
    }
    public func Clear() { clear() }

    /// A player who has read the flowchart scenes 1 to `lastScene` in one playthrough.
    public func readTo(_ tables: UiGalleryTables, lastScene: Int, share: Float = 0.6) {
        clear()

        for n in (1...lastScene) {
            seen.insert(n)
            done.insert(n)
            route.insert(n)
        }
        for n in [485, 486] {
            seen.insert(n)
            done.insert(n)
            route.insert(n)
        }

        for _ in 0..<3 {
            for e in tables.chartEdges {
                let from = done.contains(e.from)
                let to = done.contains(e.to) || (e.to >= 497 && from)
                if from && to {
                    for id in e.globalIds {
                        edges.insert(id)
                    }
                    for id in e.playthroughIds {
                        routeEdges.insert(id)
                    }
                    if e.to >= 497 {
                        done.insert(e.to)
                        seen.insert(e.to)
                        route.insert(e.to)
                    }
                }
            }
        }

        movies.insert(0)
        movies.insert(1)

        let rng = UiRandom(seed: 11)
        let model = GalleryModel.for(tables)
        for group in model.groups {
            for cg in group {
                if model.categoryOpen(cg.category, self) && cg.directSeen >= 0 && rng.next() < share {
                    pictures.insert(cg.directSeen)
                }
            }
        }

        for i in 0..<tables.tracks.count {
            if rng.next() < share {
                bgm.insert(tables.tracks[i].bgm)
            }
        }
    }
    public func ReadTo(_ tables: UiGalleryTables, _ lastScene: Int, _ share: Float = 0.6) {
        readTo(tables, lastScene: lastScene, share: share)
    }

    /// A player who has finished everything.
    public func everything(_ tables: UiGalleryTables) {
        readTo(tables, lastScene: 560, share: 1.0)
        for n in 1...0x23F {
            seen.insert(n)
            done.insert(n)
        }
        for id in 564...1267 {
            edges.insert(id)
        }
    }
    public func Everything(_ tables: UiGalleryTables) {
        everything(tables)
    }
}
