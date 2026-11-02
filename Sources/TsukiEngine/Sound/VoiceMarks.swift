import Foundation
import TsukiCore

/// The marks the PS4's `_VPLY` / `_VPL2` handler leaves in the G words (docs/formats/sound_runtime.md 3.6, adv_state.md 9.4; package K36):
/// they are what the Sound tab of the config reads to show one row per character heard, and what its test buttons play. All of them lie in
/// G[0..499], so they persist in the system block with the read text and the unlocks.
///
/// VA 0x99EF7..0x99F08 (the handler, after the group lookup): `G[73] |= (u16)(1 << character)`. VA 0x3D260 (our `VoiceGallery_Heard`,
/// called at 0x9A058 with the character and the entry of the statement): nothing for character 23 or a negative entry; else
/// `k = log2(mask[character < 24 ? character : 0])`, `G[31 + k] = (u16)entry`, `G[words[k]] |= 4` with the row words i32[19] at
/// text VA 0x1A6850. The handler returns before any of it in scan mode (byte 0x174DE48, VA 0x968B2).
public enum VoiceMarks {
    /// G[73]: bit c set once character c (0..15; the shift is truncated to 16 bits) spoke.
    public static let heardWord = 73

    /// G[31 + k]: the entry of the last voice of config slot k (what the row's test button plays, VA 0x401E0).
    public static let lastVoiceWord = 31

    /// The bit of a row word that shows the row (VA 0x3D2A6; read at 0x3E088).
    public static let rowShownBit: UInt16 = 4

    /// The bit of a row word that gives rows 15 and 16 their own face (VA 0x3E1C9).
    public static let rowFaceBit: UInt16 = 1

    /// The bit of a row word that gives the rows outside mask 0x430C9 their own name (VA 0x3E22E).
    public static let rowNameBit: UInt16 = 2

    /// Number of config voice rows (slots 0..18).
    public static let rowCount = SoundConfig.characterSlots

    /// What a `_VPLY` / `_VPL2` of `character` with `entry` writes (VA 0x99F08 and 0x3D260).
    /// `rowWords` is the eboot's row word table (nil: the row bit is not written, a test rig without the table).
    public static func note(_ vars: Vars, _ rowWords: [Int]?, _ character: Int, _ entry: Int) {
        // or word ptr [G73], dx with edx = 1 << cl: characters 16 and above leave the word alone
        let shift = character & 31
        let bit = UInt16(truncatingIfNeeded: 1 << shift)
        vars.setG(heardWord, vars.getG(heardWord) | bit)
        if character == VoiceGroups.extraCharacter || entry < 0 {
            return
        }

        let slot = VoiceGroups.slotOf(character)
        vars.setG(lastVoiceWord + slot, UInt16(truncatingIfNeeded: entry))
        if let rowWords = rowWords, slot >= 0 && slot < rowWords.count {
            let w = rowWords[slot]
            if w >= 0 && w < Vars.gCount {
                vars.setG(w, vars.getG(w) | rowShownBit)
            }
        }
    }

    /// True when the row word of slot `slot` has its shown bit (the row's character spoke).
    public static func isRowShown(_ vars: Vars, _ rowWords: [Int], _ slot: Int) -> Bool {
        guard slot >= 0 && slot < rowWords.count else { return false }
        let w = rowWords[slot]
        guard w >= 0 && w < Vars.gCount else { return false }
        return (vars.getG(w) & rowShownBit) != 0
    }

    /// True for a profile written before the marks were recorded (package K36): text was read (`readmax` has an entry) but no character
    /// ever got its heard bit. The first voiced line of the game (00_00, Shiki) sets G[73], so a profile that played anything with the marks
    /// in place never qualifies again.
    public static func needsRebuild(_ vars: Vars, _ system: SystemBlock) -> Bool {
        if vars.getG(heardWord) != 0 {
            return false
        }

        for b in 0..<SystemBlock.readmaxCount {
            if system.getReadmax(b) != 0 {
                return true
            }
        }

        return false
    }

    /// Rebuilds the marks of a profile that predates them from the read text: every `_VPLY` / `_VPL2` whose next marker counts as read
    /// (`SystemData.isRead`: the marker's line is at most the block's `readmax`, which the engine raises when the marker after it is
    /// reached) ran on the PS4 too, so its marks are written as the handler would have. The entry of G[31 + k] is the last one in script order
    /// (the PS4 keeps the last one heard in play order). Returns the number of voice statements credited.
    public static func rebuildFromReadText(data: GameData, system: SystemData, vars: Vars, rowWords: [Int]?) -> Int {
        var credited = 0
        var pending: [(character: Int, entry: Int)] = []

        for k in 0..<data.scriptCount {
            let image = data.script(k)
            let bytes = ByteSpan(image.bytes)
            pending.removeAll(keepingCapacity: true)
            var entry = -1 // 0x16541FC: -1 after a message consumed it

            for start in image.segmentStarts {
                guard let seg = try? ScriptSegmenter.read(bytes, start), seg.isCommand else {
                    continue
                }

                let first = bytes[seg.nameStart]
                if first == UInt8(ascii: "Z") {
                    guard let (block, sub) = ScriptSegmenter.readMarkerId(bytes, seg) else {
                        continue
                    }

                    if !pending.isEmpty {
                        if system.isRead(block, sub) {
                            for (c, e) in pending {
                                note(vars, rowWords, c, e)
                                credited += 1
                            }
                        }
                        pending.removeAll(keepingCapacity: true)
                    }

                    if seg.nameStart + 1 < bytes.count && bytes[seg.nameStart + 1] == UInt8(ascii: "M") {
                        entry = -1 // the message display takes the pending voice (VA 0x92380)
                    }

                    continue
                }

                if first != UInt8(ascii: "V") {
                    continue
                }

                guard let st = ScriptSegmenter.statement(k, bytes, seg) else {
                    continue
                }

                let name = st.name.description
                if name != "VPLY" && name != "VPL2" {
                    continue
                }

                let b = st.args
                let voice = SoundTags.argText(b, 0, 0)
                let character = VoiceGroups.characterOf(voice)
                if !voice.hasPrefix("_") {
                    let hex = SoundTags.argText(b, 0, 1).trimmingCharacters(in: .whitespacesAndNewlines)
                    entry = hex.isEmpty ? 0 : (Int(hex, radix: 16) ?? 0)
                }

                pending.append((character, entry))
                if name == "VPL2" {
                    entry = -1 // _VPL2 plays at once and clears the pending voice
                }
            }
        }

        return credited
    }
}
