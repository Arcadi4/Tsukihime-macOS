// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Ported from knife (https://github.com/AuroraWright/knife) by AuroraWright
import Foundation
import TsukiCore
import TsukiEngine

/// A CG of the gallery with the picture-seen bits that unlock it resolved once.
public struct GalleryCg: Sendable {
    public let group: Int
    public let index: Int
    public let row: GalleryCgRow
    public let category: Int
    public let directSeen: Int
    public let aliasSeen: [Int]
    public let languageStrip: Bool

    public var Group: Int { group }
    public var Index: Int { index }
    public var Row: GalleryCgRow { row }
    public var Category: Int { category }
    public var DirectSeen: Int { directSeen }
    public var AliasSeen: [Int] { aliasSeen }
    public var LanguageStrip: Bool { languageStrip }

    public init(group: Int, index: Int, row: GalleryCgRow, category: Int, directSeen: Int, aliasSeen: [Int], languageStrip: Bool) {
        self.group = group
        self.index = index
        self.row = row
        self.category = category
        self.directSeen = directSeen
        self.aliasSeen = aliasSeen
        self.languageStrip = languageStrip
    }
}

/// The unlock rules of the gallery, the music player, the movie list and the ending list.
public final class GalleryModel {
    /// names_sprites is the first 9,958 picture names: a CG whose picture is beyond them is gallery-only.
    public static let spriteNameCount: Int = 9958
    public static let SpriteNameCount: Int = spriteNameCount

    /// The scene whose completion (QA_25) unlocks every CG.
    public static let allCgScene: Int = 557
    public static let AllCgScene: Int = allCgScene

    /// The movie gallery items: the movie table index and the movie_seen bit that unlocks it (nil: always).
    public static let movies: [(movie: Int, bit: Int?)] = [(4, nil), (5, 0), (6, 1)]
    public static let Movies: [(movie: Int, bit: Int?)] = movies

    private static let lock = NSLock()
    private static var cache: [ObjectIdentifier: GalleryModel] = [:]

    /// The tables the model reads.
    public let tables: UiGalleryTables
    public var Tables: UiGalleryTables { tables }

    /// The CGs by group (458 groups, 1,972 CGs).
    public let groups: [[GalleryCg]]
    public var Groups: [[GalleryCg]] { groups }

    private init(tables: UiGalleryTables) {
        self.tables = tables
        var aliases: [String: GalleryAliasRow] = [:]
        for a in tables.cgAliases {
            aliases[a.key] = a
        }

        var strips = Set<String>()
        for name in tables.cgLanguageStrips {
            strips.insert(Self.stem(name).lowercased())
        }

        var groupsList: [[GalleryCg]] = []
        groupsList.reserveCapacity(tables.cgGroups.count)

        for g in 0..<tables.cgGroups.count {
            let group = tables.cgGroups[g]
            var list: [GalleryCg] = []
            list.reserveCapacity(group.entries.count)

            for k in 0..<group.entries.count {
                let row = group.entries[k]
                let direct = Self.seen(Self.spriteIndex(tables, row.name), tables)
                let alias: [Int] = aliases[row.name].map { Self.aliasPlan($0, tables) } ?? []
                let isStrip = strips.contains(Self.stem(row.name).lowercased())
                list.append(GalleryCg(group: g, index: k, row: row, category: group.category, directSeen: direct, aliasSeen: alias, languageStrip: isStrip))
            }
            groupsList.append(list)
        }

        self.groups = groupsList
    }

    /// The model of `tables` (built once per table set).
    public static func `for`(_ tables: UiGalleryTables) -> GalleryModel {
        lock.lock()
        defer { lock.unlock() }
        let id = ObjectIdentifier(tables)
        if let existing = cache[id] {
            return existing
        }
        let created = GalleryModel(tables: tables)
        cache[id] = created
        return created
    }

    public static func For(_ tables: UiGalleryTables) -> GalleryModel {
        Self.for(tables)
    }

    private static func stem(_ name: String) -> String {
        if let dot = name.firstIndex(of: ".") {
            return String(name[..<dot])
        }
        return name
    }

    private static func spriteIndex(_ tables: UiGalleryTables, _ name: String) -> Int {
        let i = tables.pictureIndex(name)
        return (i >= 0 && i < spriteNameCount) ? i : -1
    }

    private static func seen(_ pictureId: Int, _ tables: UiGalleryTables) -> Int {
        pictureId < 0 ? -1 : tables.pictureSeenIndex(pictureId)
    }

    private static func aliasPlan(_ alias: GalleryAliasRow, _ tables: UiGalleryTables) -> [Int] {
        var plan: [Int] = []
        for al in alias.aliases {
            let i = spriteIndex(tables, al)
            if i >= 0 || al.count < 6 {
                plan.append(seen(i, tables))
                break
            }

            for letter in "ALMS" {
                let prefix = al.prefix(4)
                let suffix = al.dropFirst(5)
                let candidate = "\(prefix)\(letter)\(suffix)"
                plan.append(seen(tables.pictureIndex(candidate), tables))
            }
        }

        return plan.filter { $0 >= 0 }
    }

    // MARK: - CG

    /// The category's gate: category 0 is always open, the others when any of their scenes was started.
    public func categoryOpen(_ category: Int, _ progress: IUiProgress) -> Bool {
        guard let scenes = tables.cgCategoryScenes[category] else {
            return true
        }
        return scenes.contains { progress.sceneSeen($0) }
    }
    public func CategoryOpen(_ category: Int, _ progress: IUiProgress) -> Bool {
        categoryOpen(category, progress)
    }

    /// The CG is unlocked (0x13630): its category is open and the picture or an alias was shown, or QA_25 was finished.
    public func isUnlocked(_ cg: GalleryCg, _ progress: IUiProgress) -> Bool {
        categoryOpen(cg.category, progress) &&
        (cg.aliasSeen.contains { progress.pictureSeen($0) } ||
         (cg.directSeen >= 0 && progress.pictureSeen(cg.directSeen)) ||
         progress.sceneDone(Self.allCgScene))
    }
    public func IsUnlocked(_ cg: GalleryCg, _ progress: IUiProgress) -> Bool {
        isUnlocked(cg, progress)
    }

    /// The unlocked entry indices of every group (an empty list for a locked group).
    public func unlocked(_ progress: IUiProgress) -> [[Int]] {
        var result: [[Int]] = []
        result.reserveCapacity(groups.count)
        for g in 0..<groups.count {
            let entryIndices = groups[g].filter { isUnlocked($0, progress) }.map { $0.index }
            result.append(entryIndices)
        }
        return result
    }
    public func Unlocked(_ progress: IUiProgress) -> [[Int]] {
        unlocked(progress)
    }

    // MARK: - Music

    /// The track is unlocked (0x2CBA0): its BGM or one of its variants was heard, or a special rule holds.
    public func trackUnlocked(_ index: Int, _ progress: IUiProgress) -> Bool {
        let t = tables.tracks[index]
        if progress.bgmHeard(t.bgm) || t.variants.contains(where: { progress.bgmHeard($0) }) {
            return true
        }

        switch t.bgm {
        case 80: return progress.movieSeen(0)
        case 82: return progress.sceneSeen(560)
        case 124: return progress.movieSeen(1)
        case 126: return progress.sceneSeen(562)
        default: return false
        }
    }
    public func TrackUnlocked(_ index: Int, _ progress: IUiProgress) -> Bool {
        trackUnlocked(index, progress)
    }

    /// The unlock state of every track.
    public func tracksUnlocked(_ progress: IUiProgress, mark: IUiGalleryServices? = nil) -> [Bool] {
        var ok = [Bool](repeating: false, count: tables.tracks.count)
        for i in 0..<ok.count {
            ok[i] = trackUnlocked(i, progress)
            if ok[i], let mark = mark, !progress.bgmHeard(tables.tracks[i].bgm) {
                mark.markBgmHeard(tables.tracks[i].bgm)
            }
        }
        return ok
    }
    public func TracksUnlocked(_ progress: IUiProgress, _ mark: IUiGalleryServices? = nil) -> [Bool] {
        tracksUnlocked(progress, mark: mark)
    }

    // MARK: - Movies

    /// Movie gallery item `item` can be played.
    public static func movieUnlocked(_ item: Int, _ progress: IUiProgress) -> Bool {
        guard item >= 0 && item < 3 else { return false }
        if let bit = movies[item].bit {
            return progress.movieSeen(bit)
        }
        return true
    }
    public static func MovieUnlocked(_ item: Int, _ progress: IUiProgress) -> Bool {
        movieUnlocked(item, progress)
    }

    // MARK: - Endings

    /// The number of ending list entries; the last one (QA_25) is the congratulation entry.
    public var endingCount: Int { tables.endings.count }
    public var EndingCount: Int { endingCount }

    /// Ending entry `index` is reached.
    public func endingUnlocked(_ index: Int, _ progress: IUiProgress) -> Bool {
        if index == endingCount - 1 {
            return allEndings(progress)
        }
        let e = tables.endings[index]
        return progress.sceneDone(e.unlockA) || (e.unlockB >= 0 && progress.sceneDone(e.unlockB))
    }
    public func EndingUnlocked(_ index: Int, _ progress: IUiProgress) -> Bool {
        endingUnlocked(index, progress)
    }

    /// Every ending but the last is reached.
    public func allEndings(_ progress: IUiProgress) -> Bool {
        for i in 0..<(endingCount - 1) {
            if !endingUnlocked(i, progress) {
                return false
            }
        }
        return true
    }
    public func AllEndings(_ progress: IUiProgress) -> Bool {
        allEndings(progress)
    }

    /// True when `node` is the flowchart node of an ending list scene (533..557).
    public func isEndingNode(_ node: Int) -> Bool {
        tables.endings.contains { $0.flowScene == node }
    }
    public func IsEndingNode(_ node: Int) -> Bool {
        isEndingNode(node)
    }
}
