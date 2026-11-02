import Foundation
import TsukiCore

/// The voice-group tables (docs/formats/sound_runtime.md 8; eboot table 0x215E90, mask table 0x86A850, verified for all 54
/// voice.nam groups): voice name prefix to character, character to config slot.
public enum VoiceGroups {
    /// Character 23: the groups of the extra material (M00..), which have no voice row in the config.
    public static let extraCharacter = 23

    private static let charOfGroup: [String: Int] = [
        "A00": 1, "A10": 2, "A11": 2, "A12": 2, "A20": 3, "A21": 3, "A22": 3, "A23": 3, "A24": 3,
        "B00": 4, "B10": 5, "B20": 6, "B30": 7, "B40": 8, "B50": 9, "B60": 10, "B70": 11,
        "B80": 12, "B90": 13, "C00": 14, "C10": 15, "C20": 16, "C30": 17, "C40": 18, "C50": 19,
        "C60": 20, "C70": 21, "C80": 0, "C90": 22,
        "M00": 23, "M01": 23, "M02": 23, "M03": 23, "M11": 23, "M12": 23,
    ]

    /// 0x86A850: the config enable mask of each character (u32[24]).
    public static let characterMask: [UInt32] = [
        0x40000, 0x1, 0x2, 0x4, 0x200, 0x10000, 0x10, 0x20, 0x8, 0x80, 0x1000, 0x8000,
        0x20000, 0x1, 0x400, 0x2000, 0x4000, 0x800, 0x40, 0x40000, 0x40000, 0x100, 0x40000, 0x40000,
    ]

    /// The character the `_VPLY` handler derives from a voice name (its first 3 characters; every group not listed gets 0).
    public static func characterOf(_ name: String) -> Int {
        let prefix = name.count >= 3 ? String(name.prefix(3)) : name
        return charOfGroup[prefix] ?? 0
    }

    /// The enable mask of `character` (characters outside 0..23 use character 0, VA 0x3D2D0).
    public static func maskOf(_ character: Int) -> UInt32 {
        characterMask[character >= 0 && character < 24 ? character : 0]
    }

    /// The config slot k of a character: bit k of config +0x3C, volume u16 at config +0x76 + 2k (VA 0x3D2D0).
    public static func slotOf(_ character: Int) -> Int {
        let mask = maskOf(character)
        return mask == 0 ? 0 : 31 - mask.leadingZeroBitCount
    }
}

/// The system sounds (docs/formats/sound_runtime.md 10.1; eboot tables 0x2D3770 and 0x6241F0): `SystemSE_Play(id)` plays a
/// pair of HE-VAG entries, one hard left and one hard right.
public enum SystemSounds {
    /// Number of system sound ids (28).
    public static let count = 28

    private static let idTable: [(bank: Int, index: Int)] = [
        (0, 0), (0, 1), (0, 2), (0, 4), (0, 5), (0, 6), (0, 1), (0, 3), (0, 7), (0, 8),
    ] + [(bank: Int, index: Int)](repeating: (0, 20), count: 18)

    private static let vagTable: [(left: Int, right: Int)] = [
        (3, 4), (5, 6), (1, 2), (7, 8), (9, 10), (11, 12), (13, 14), (15, 16), (17, 18),
    ] + [(left: Int, right: Int)](repeating: (0, -1), count: 27)

    /// The (left, right) `vag.mrg` entries of system sound `id` (VA 0xCC670): right is -1 for a mono sound and
    /// left <= 0 means nothing plays.
    public static func vags(_ id: Int) throws -> (left: Int, right: Int) {
        guard id >= 0 && id < idTable.count else {
            throw TsukiError.bounds("system sound ids are 0..\(idTable.count - 1)")
        }

        let (bank, index) = idTable[id]
        return vagTable[(bank * 128) + index]
    }

    /// The bank an `open_handle` of `stream` belongs to: SE channels use vse, voices use voice.
    static func bankOfStream(_ stream: Int) -> AudioBank {
        stream >= AudioStreams.firstSE ? .se : .voice
    }
}
