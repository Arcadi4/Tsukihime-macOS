import Foundation
import TsukiCore
import TsukiEngine

/// One CG of the gallery (a 32-byte record of a group's NULL-terminated list).
public struct CgEntry: Equatable, Sendable {
    /// Group index (0..457).
    public let group: Int
    /// Position inside the group.
    public let index: Int
    /// The picture file name without the one-character prefix (`IMG1685.MZP`).
    public let name: String
    /// The prefix character (' ' or '-'); no code reads it.
    public let prefix: Character
    /// Index into the GALLERY_PARTS_CG_TH sheet (knife's thumbnail id).
    public let thumbnail: Int
    /// View offset x (knife's CG_ORIGINS; 19 entries are non-zero).
    public let x: Int
    /// View offset y.
    public let y: Int
    /// Picture width in the viewer.
    public let width: Int
    /// Picture height in the viewer.
    public let height: Int
    /// The +0x1C byte (meaning [H]; knife's "gallery-only" is a different quantity).
    public let flag: Int
    /// The group's unlock category (knife's group condition id).
    public let category: Int

    public init(
        group: Int, index: Int, name: String, prefix: Character, thumbnail: Int, x: Int, y: Int, width: Int, height: Int,
        flag: Int, category: Int
    ) {
        self.group = group
        self.index = index
        self.name = name
        self.prefix = prefix
        self.thumbnail = thumbnail
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.flag = flag
        self.category = category
    }
}

/// A gallery group: the entries that are shown as one tile.
public struct CgGroup: Equatable, Sendable {
    /// Group index.
    public let index: Int
    /// Unlock category 0..19.
    public let category: Int
    /// The CGs of the group.
    public let entries: [CgEntry]

    public init(index: Int, category: Int, entries: [CgEntry]) {
        self.index = index
        self.category = category
        self.entries = entries
    }
}

/// A CG unlocked by seeing another picture (`key` is shown when one of the aliases was seen).
public struct CgAlias: Equatable, Sendable {
    /// Table index.
    public let index: Int
    /// The CG's picture name.
    public let key: String
    /// The pictures that unlock it.
    public let aliases: [String]

    public init(index: Int, key: String, aliases: [String]) {
        self.index = index
        self.key = key
        self.aliases = aliases
    }
}

/// An entry of the picture seen-index map: image `name` is recorded under bit `seenIndex` (knife's SEEN_ALIAS).
public struct SeenMapEntry: Equatable, Sendable {
    /// Table index.
    public let index: Int
    /// Picture name.
    public let name: String
    /// The seen bit (2701 and up).
    public let seenIndex: Int

    public init(index: Int, name: String, seenIndex: Int) {
        self.index = index
        self.name = name
        self.seenIndex = seenIndex
    }
}

/// A track of the music room.
public struct MusicTrack: Equatable, Sendable {
    /// Position in the list.
    public let index: Int
    /// bgm.hed index; the unlock bit is 0xC80 + this.
    public let bgm: Int
    /// ui_text id of the title.
    public let titleUi: Int
    /// Credit ui_text id after "Vocals:", -1 none.
    public let vocalUi: Int
    /// Lyrics credit, -1 none.
    public let lyricsUi: Int
    /// Composer credit, -1 none.
    public let composerUi: Int
    /// Arranger credit, -1 none.
    public let arrangerUi: Int
    /// Length in ms (0 for some).
    public let lengthMs: Int
    /// Loop start sample (48 kHz).
    public let loopStart: Int
    /// Loop end sample (knife's end is this + 1).
    public let loopEnd: Int
    /// Other bgm indices that also unlock the track.
    public let variants: [Int]

    public init(
        index: Int, bgm: Int, titleUi: Int, vocalUi: Int, lyricsUi: Int, composerUi: Int, arrangerUi: Int, lengthMs: Int,
        loopStart: Int, loopEnd: Int, variants: [Int]
    ) {
        self.index = index
        self.bgm = bgm
        self.titleUi = titleUi
        self.vocalUi = vocalUi
        self.lyricsUi = lyricsUi
        self.composerUi = composerUi
        self.arrangerUi = arrangerUi
        self.lengthMs = lengthMs
        self.loopStart = loopStart
        self.loopEnd = loopEnd
        self.variants = variants
    }
}

/// An entry of the ending list (the 25 "Teach Me, Miss Ciel" scenarios).
public struct ExtraScenario: Equatable, Sendable {
    /// Table row.
    public let index: Int
    /// Scene id passed to the replay (1000..1024).
    public let scriptScene: Int
    /// The script's RDST id (533..557; knife's node bit).
    public let flowScene: Int
    /// scene_done(unlockA) or scene_done(unlockB) unlocks the entry.
    public let unlockA: Int
    /// Second unlock scene, -1 none.
    public let unlockB: Int
    /// Index into the help-message table.
    public let message: Int
    /// The ui_text id of the "Play ...?" prompt, -1 when out of range.
    public let messageUi: Int

    public init(
        index: Int, scriptScene: Int, flowScene: Int, unlockA: Int, unlockB: Int, message: Int, messageUi: Int
    ) {
        self.index = index
        self.scriptScene = scriptScene
        self.flowScene = flowScene
        self.unlockA = unlockA
        self.unlockB = unlockB
        self.message = message
        self.messageUi = messageUi
    }
}

/// The CG gallery, music room and ending list tables of the eboot (docs/formats/gallery.md 4-6; knife's `gallery_table.rs`, `gallery.rs`
/// and the `SEEN_ALIAS` of `save_tables.rs`). Port of the gallery half of `tsuki.misc_gallery_extras_flowchart.load`; the knife cross-check
/// of the research document (docs/research/knife_tables.md) found 1972 of 1972 entries, 105 of 105 aliases, 2144 of 2144 seen-map
/// entries and 95 of 95 tracks equal.
public struct GalleryTables: Sendable {
    /// RELRO VA of the 458 group records of 32 bytes.
    public static let groupVa: Int = 0x400830

    /// Number of groups.
    public static let groupCount: Int = 458

    /// RELRO VA of the 105 alias records of 0x28 bytes.
    public static let aliasVa: Int = 0x404170

    /// Number of aliases.
    public static let aliasCount: Int = 105

    /// RELRO VA of the 11 special (four-language-band) CG names.
    public static let specialVa: Int = 0x4051E0

    /// Number of special names.
    public static let specialCount: Int = 11

    /// Data VA of the 16-byte seen-map records (NULL-name terminated).
    public static let seenMapVa: Int = 0x86AA30

    /// Text VA of the 95 music records of 0x38 bytes.
    public static let musicVa: Int = 0x1A47D0

    /// Number of music tracks.
    public static let musicCount: Int = 95

    /// Text VA of the 25 ending-list records of 20 bytes.
    public static let extraVa: Int = 0x18F810

    /// Number of ending-list entries.
    public static let extraCount: Int = 25

    /// Text VA of the 55 help-message ids (the dialog table's tail, ending prompts).
    public static let helpMessageVa: Int = 0x2D2D40

    /// Number of help messages.
    public static let helpMessageCount: Int = 55

    /// Text VA of the 27 trophy scene records of 8 bytes.
    public static let trophySceneVa: Int = 0x221400

    /// Number of trophy scenes.
    public static let trophySceneCount: Int = 27

    /// Text VA of the jump table of the CG category switch (VA 0x1C460).
    public static let categoryJumpTableVa: Int = 0x188380

    /// The common join of the category switch.
    public static let categoryJoin: Int = 0x1C51B

    /// Number of unlock categories with a rule (1..19).
    public static let categoryCount: Int = 19

    /// The 458 groups.
    public let groups: [CgGroup]

    /// The 105 aliases.
    public let aliases: [CgAlias]

    /// The 11 CG names that stack one picture per language (knife's CG_LANGUAGE_STRIPS).
    public let special: [String]

    /// The seen-index map (2,144 entries).
    public let seenMap: [SeenMapEntry]

    /// The 95 music tracks.
    public let music: [MusicTrack]

    /// The 25 ending-list entries.
    public let extras: [ExtraScenario]

    /// The 55 help-message ui_text ids (-1 none).
    public let helpMessages: [Int]

    /// The first field of the 27 trophy scene records.
    public let trophyScenes: [Int]

    /// For each CG category 1..19, the scene_seen ids of which any one unlocks it (read from the compiled switch at VA 0x1C460).
    public let categoryFlags: [Int: [Int]]

    public init(
        groups: [CgGroup], aliases: [CgAlias], special: [String], seenMap: [SeenMapEntry], music: [MusicTrack],
        extras: [ExtraScenario], helpMessages: [Int], trophyScenes: [Int], categoryFlags: [Int: [Int]]
    ) {
        self.groups = groups
        self.aliases = aliases
        self.special = special
        self.seenMap = seenMap
        self.music = music
        self.extras = extras
        self.helpMessages = helpMessages
        self.trophyScenes = trophyScenes
        self.categoryFlags = categoryFlags
    }

    /// All 1,972 CGs in group order.
    public var entries: [CgEntry] { groups.flatMap(\.entries) }

    /// Reads every gallery table.
    public static func read(_ reader: EbootReader) throws -> GalleryTables {
        let layout = reader.layout
        let groupCount = max(0, layout.galleryGroupCount)
        let aliasCount = max(0, layout.galleryAliasCount)
        let specialCount = max(0, layout.gallerySpecialCount)
        let musicCount = max(0, layout.musicCount)
        let extraCount = max(0, layout.extraCount)
        let trophyCount = max(0, layout.trophySceneCount)

        var groups: [CgGroup] = []
        groups.reserveCapacity(groupCount)
        for g in 0..<groupCount {
            let va = layout.galleryGroups + 32 * g
            let list = try pointer(reader, va)
            let category = Int(try reader.i32(va + 8))
            if try reader.read(va + 12, 20).contains(where: { $0 != 0 }) {
                throw TsukiError.format("CG group \(g): unexpected non-zero tail")
            }

            var entries: [CgEntry] = []
            var e = list
            while true {
                let namePtr = try pointer(reader, e)
                if namePtr == 0 {
                    break
                }

                let raw = reader.cString(namePtr, limit: 64)
                guard let prefix = raw.first else {
                    throw TsukiError.format("CG group \(g) entry \(entries.count): empty name")
                }

                entries.append(CgEntry(
                    group: g, index: entries.count, name: String(raw.dropFirst()), prefix: prefix,
                    thumbnail: Int(try reader.i32(e + 8)), x: Int(try reader.i32(e + 12)),
                    y: Int(try reader.i32(e + 16)), width: Int(try reader.i32(e + 20)),
                    height: Int(try reader.i32(e + 24)), flag: Int(try reader.i32(e + 28)), category: category))
                e += 32
            }

            groups.append(CgGroup(index: g, category: category, entries: entries))
        }

        var aliases: [CgAlias] = []
        aliases.reserveCapacity(aliasCount)
        for i in 0..<aliasCount {
            let va = layout.galleryAliases + 0x28 * i
            let key = reader.cString(try pointer(reader, va), limit: 64)
            var names: [String] = []
            for k in 1..<5 {
                let p = try pointer(reader, va + 8 * k)
                if p != 0 {
                    names.append(reader.cString(p, limit: 64))
                }
            }

            aliases.append(CgAlias(index: i, key: key, aliases: names))
        }

        var special: [String] = []
        special.reserveCapacity(specialCount)
        for i in 0..<specialCount {
            special.append(reader.cString(try pointer(reader, layout.gallerySpecial + 8 * i), limit: 64))
        }

        if try pointer(reader, layout.gallerySpecial + 8 * specialCount) != 0 {
            throw TsukiError.format("the special CG name list is longer than \(specialCount)")
        }

        var seen: [SeenMapEntry] = []
        var va = layout.seenMap
        while true {
            let p = try pointer(reader, va)
            if p == 0 {
                break
            }

            seen.append(SeenMapEntry(index: seen.count, name: reader.cString(p, limit: 64), seenIndex: Int(try reader.i32(va + 12))))
            va += 16
        }

        var music: [MusicTrack] = []
        music.reserveCapacity(musicCount)
        for i in 0..<musicCount {
            let recordVa = layout.music + 0x38 * i
            var f = [Int](repeating: 0, count: 14)
            for k in 0..<14 {
                f[k] = Int(try reader.i32(recordVa + 4 * k))
            }

            music.append(MusicTrack(
                index: i, bgm: f[0], titleUi: f[1], vocalUi: f[2], lyricsUi: f[3], composerUi: f[4], arrangerUi: f[5],
                lengthMs: f[6], loopStart: f[7], loopEnd: f[8], variants: f[9..<14].filter { $0 >= 0 }))
        }

        var help = [Int](repeating: 0, count: helpMessageCount)
        for i in 0..<help.count {
            help[i] = Int(try reader.i32(layout.dialogMessages + 4 * i))
        }

        var extras: [ExtraScenario] = []
        extras.reserveCapacity(extraCount)
        for i in 0..<extraCount {
            let recordVa = layout.extras + 20 * i
            let message = Int(try reader.i32(recordVa + 16))
            extras.append(ExtraScenario(
                index: i,
                scriptScene: Int(try reader.i32(recordVa)),
                flowScene: Int(try reader.i32(recordVa + 4)),
                unlockA: Int(try reader.i32(recordVa + 8)),
                unlockB: Int(try reader.i32(recordVa + 12)),
                message: message,
                messageUi: message >= 0 && message < helpMessageCount ? help[message] : -1))
        }

        var trophies = [Int](repeating: 0, count: trophyCount)
        for i in 0..<trophies.count {
            trophies[i] = Int(try reader.i32(layout.trophyScenes + 8 * i))
        }

        return GalleryTables(
            groups: groups, aliases: aliases, special: special, seenMap: seen, music: music, extras: extras,
            helpMessages: help, trophyScenes: trophies, categoryFlags: try readCategoryFlags(reader))
    }

    /// The absolute pointer stored at `slot` (image base 0); 0 is NULL.
    static func pointer(_ reader: EbootReader, _ slot: Int) throws -> Int {
        let raw = try reader.u64(slot)
        let address = Int(bitPattern: UInt(truncatingIfNeeded: raw))
        if raw != 0, reader.fileOffset(address) == nil {
            throw TsukiError.format("slot 0x\(String(slot, radix: 16)): pointer 0x\(String(raw, radix: 16)) is not file-backed")
        }

        return address
    }

    /// Category 1..19 to its scene_seen ids from the switch at 0x1C460: each case loads `mov edi, imm32` once, or twice with an early-out
    /// `call 0xB81A0; test al, al; jne` between (category 15 = 0x113 or 0x114). Scanned byte by byte over those few instruction forms.
    private static func readCategoryFlags(_ reader: EbootReader) throws -> [Int: [Int]] {
        let layout = reader.layout
        var result: [Int: [Int]] = [:]
        guard layout.categoryCount >= 1 else { return result }
        for c in 1...layout.categoryCount {
            let target = Int(try reader.i32(layout.categoryJumpTable + 4 * (c - 1)))
            var at = (layout.categoryJumpTable + target) & 0xFFFF_FFFF
            var flags: [Int] = []
            scan: while at < layout.categoryJoin {
                let b = try reader.read(at, 8)
                switch b.u8(0) {
                case 0xBF:
                    flags.append(Int(b.i32(1)))
                    at += 5
                case 0xE8:
                    if Int(b.i32(1)) + at + 5 != 0xB81A0 {
                        throw TsukiError.format("category \(c): unexpected call at 0x\(String(at, radix: 16))")
                    }

                    at += 5
                case 0x84 where b.u8(1) == 0xC0:
                    at += 2
                case 0x0F where b.u8(1) == 0x85:
                    at += 6
                case 0xE9, 0xEB:
                    break scan
                default:
                    throw TsukiError.format(
                        "category \(c): unexpected opcode \(String(format: "%02X", b.u8(0))) at 0x\(String(at, radix: 16))")
                }
            }

            if flags.isEmpty {
                throw TsukiError.format("category \(c): no flag found")
            }

            result[c] = flags
        }

        return result
    }
}
