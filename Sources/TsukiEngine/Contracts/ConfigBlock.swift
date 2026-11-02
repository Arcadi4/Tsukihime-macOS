import Foundation
import TsukiCore

/// The configuration block at VA 0x66C578 (0x140 bytes), stored as system block +0x04
/// (adv_state.md 9.2; sound_runtime.md 2.4).
///
/// Ported from `Tsuki.Engine/Contracts/Generated/ConfigBlock.g.cs` (generator
/// `tools/setup/gen_state_blocks.py`; source `tsuki.misc_adv_system_state.CONFIG_FIELDS`, names
/// `CONFIG_NAMES`).
public final class ConfigBlock: StateBlock {
    /// Size of the block in bytes (0x140).
    public static let size = 0x140

    /// Number of entries of `characterVoiceVolume`.
    public static let characterVoiceVolumeCount = 19

    /// Creates a zeroed block.
    public init() {
        super.init(size: ConfigBlock.size)
    }

    /// Creates a view of the `size` bytes of `storage` at `offset` (shared, not copied).
    public init(storage: ByteStorage, offset: Int = 0) {
        super.init(storage: storage, offset: offset, length: ConfigBlock.size)
    }

    /// Every byte of the block in exactly one field, in offset order.
    public static let fields: [StateField] = [
        StateField(name: "display00", oracleName: "config+0x00", offset: 0x0000, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "display02", oracleName: "config+0x02", offset: 0x0002, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "liveValue04", oracleName: "config+0x04", offset: 0x0004, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "display06", oracleName: "config+0x06", offset: 0x0006, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "constants08", oracleName: "config+0x08", offset: 0x0008, size: 0x8, kind: .scalar, type: "u64"),
        StateField(name: "hud10", oracleName: "config+0x10", offset: 0x0010, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "hud12", oracleName: "config+0x12", offset: 0x0012, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "musicVolume", oracleName: "config+0x14", offset: 0x0014, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "playAllVoices", oracleName: "config+0x16", offset: 0x0016, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "sfxVolume", oracleName: "config+0x18", offset: 0x0018, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "systemSeVolume", oracleName: "config+0x1A", offset: 0x001A, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "word1C", oracleName: "config+0x1C", offset: 0x001C, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "word1E", oracleName: "config+0x1E", offset: 0x001E, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "unseenTextSpeed", oracleName: "config+0x20", offset: 0x0020, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "seenTextSpeed", oracleName: "config+0x22", offset: 0x0022, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "language", oracleName: "config+0x24", offset: 0x0024, size: 0x2, kind: .scalar, type: "i16"),
        StateField(name: "textDraw26", oracleName: "config+0x26", offset: 0x0026, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "text28", oracleName: "config+0x28", offset: 0x0028, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "textColourMode", oracleName: "config+0x2A", offset: 0x002A, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "audio2C", oracleName: "config+0x2C", offset: 0x002C, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "autoModeWait", oracleName: "config+0x2E", offset: 0x002E, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "fastForwardReadOnly", oracleName: "config+0x30", offset: 0x0030, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "sceneJumpButtons", oracleName: "config+0x32", offset: 0x0032, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "constant34", oracleName: "config+0x34", offset: 0x0034, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "voiceGate36", oracleName: "config+0x36", offset: 0x0036, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "unused38", oracleName: "config+0x38", offset: 0x0038, size: 0x4, kind: .unused, type: "bytes"),
        StateField(name: "voiceEnableBits", oracleName: "config+0x3C", offset: 0x003C, size: 0x4, kind: .scalar, type: "u32"),
        StateField(name: "autoSaveMask", oracleName: "config+0x40", offset: 0x0040, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "actionPreset", oracleName: "config+0x42", offset: 0x0042, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "choice44", oracleName: "config+0x44", offset: 0x0044, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "hud46", oracleName: "config+0x46", offset: 0x0046, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "unused48", oracleName: "config+0x48", offset: 0x0048, size: 0x2, kind: .unused, type: "bytes"),
        StateField(name: "hud4A", oracleName: "config+0x4A", offset: 0x004A, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "restoreLiveValueGate", oracleName: "config+0x4C", offset: 0x004C, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "interruptVoices", oracleName: "config+0x4E", offset: 0x004E, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "constant50", oracleName: "config+0x50", offset: 0x0050, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "unused52", oracleName: "config+0x52", offset: 0x0052, size: 0x2, kind: .unused, type: "bytes"),
        StateField(name: "musicVolumeCopy", oracleName: "config+0x54", offset: 0x0054, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "dialog56", oracleName: "config+0x56", offset: 0x0056, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "constant58", oracleName: "config+0x58", offset: 0x0058, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "bootRecords", oracleName: "config+0x5A", offset: 0x005A, size: 0x1C, kind: .bytes, type: "bytes"),
        StateField(name: "characterVoiceVolume", oracleName: "config+0x76", offset: 0x0076, size: 0x26, kind: .array, type: "u16", count: 19),
        StateField(name: "pageEndInstantUnseen", oracleName: "config+0x9C", offset: 0x009C, size: 0x1, kind: .scalar, type: "u8"),
        StateField(name: "pageEndInstantSeen", oracleName: "config+0x9D", offset: 0x009D, size: 0x1, kind: .scalar, type: "u8"),
        StateField(name: "autoModePageSpeed", oracleName: "config+0x9E", offset: 0x009E, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "autoSkipCleared", oracleName: "config+0xA0", offset: 0x00A0, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "skipConfirm", oracleName: "config+0xA2", offset: 0x00A2, size: 0x1, kind: .scalar, type: "u8"),
        StateField(name: "textAnimations", oracleName: "config+0xA3", offset: 0x00A3, size: 0x1, kind: .scalar, type: "u8"),
        StateField(name: "seenTextAnimations", oracleName: "config+0xA4", offset: 0x00A4, size: 0x1, kind: .scalar, type: "u8"),
        StateField(name: "constantA5", oracleName: "config+0xA5", offset: 0x00A5, size: 0x1, kind: .scalar, type: "u8"),
        StateField(name: "musicMute", oracleName: "config+0xA6", offset: 0x00A6, size: 0x1, kind: .scalar, type: "u8"),
        StateField(name: "sfxMute", oracleName: "config+0xA7", offset: 0x00A7, size: 0x1, kind: .scalar, type: "u8"),
        StateField(name: "systemSeMute", oracleName: "config+0xA8", offset: 0x00A8, size: 0x1, kind: .scalar, type: "u8"),
        StateField(name: "unusedA9", oracleName: "config+0xA9", offset: 0x00A9, size: 0x97, kind: .unused, type: "bytes"),
    ]

    /// A copy of the block in a new array.
    public func clone() -> ConfigBlock {
        let c = ConfigBlock()
        c.copy(from: self)
        return c
    }

    /// The block as stored in the eboot data image at VA 0x66C578, i.e. the boot defaults
    /// (adv_state.md 9.2 "boot value"; equal to `tsuki.misc_adv_system_state.read_static_config`).
    public static func createBootDefaults() -> ConfigBlock {
        let c = ConfigBlock()
        c.display00 = 255
        c.display02 = 1
        c.display06 = 127
        c.constants08 = 71777214294589441
        c.hud10 = 255
        c.musicVolume = 40
        c.playAllVoices = 100
        c.sfxVolume = 40
        c.systemSeVolume = 10
        c.unseenTextSpeed = 35
        c.seenTextSpeed = 15
        c.language = -1
        c.textDraw26 = 1
        c.autoModeWait = 2200
        c.fastForwardReadOnly = 1
        c.sceneJumpButtons = 1
        c.constant34 = 1
        c.voiceGate36 = 1
        c.voiceEnableBits = 1_073_741_823
        c.autoSaveMask = 3
        c.interruptVoices = 1
        c.constant50 = 1
        c.musicVolumeCopy = 40
        for i in 0..<characterVoiceVolumeCount {
            c.setCharacterVoiceVolume(i, 50)
        }
        c.autoModePageSpeed = 3000
        c.constantA5 = 1

        return c
    }

    /// +0x0000 u16 config+0x00: display value (0xCD640 arg /4). Readers: 0x41890, 0x3EE10, 0xA0AD0,
    /// 0xA0B10, 0xA2630; no writer (the scan hits at 0x3C3F7 / 0x3F81C are nop instructions).
    /// Menu: -. Boot value 255.
    public var display00: UInt16 {
        get { readU16(0x0000) }
        set { writeU16(0x0000, newValue) }
    }

    /// +0x0002 u16 config+0x02: display value (0xCD640 arg). Readers: 0x41890, 0x45910, 0x53CF0,
    /// 0x57080. Menu: -. Boot value 1.
    public var display02: UInt16 {
        get { readU16(0x0002) }
        set { writeU16(0x0002, newValue) }
    }

    /// +0x0004 u16 config+0x04: live value 0..255 (stick A y in ADV: 0x61321..0x6137F,
    /// +-(|y| - 80) / 8 per frame). Readers: written by 0x60710 (0x6137F) and History_Restore
    /// 0x7CA2A (only when +0x4C != 0; dead 0x41DB0 / 0x41FC0 likewise); read by History_Push
    /// +0x363E, 0x41890 (0xCD650). Menu: -. Boot value 0.
    public var liveValue04: UInt16 {
        get { readU16(0x0004) }
        set { writeU16(0x0004, newValue) }
    }

    /// +0x0006 u16 config+0x06: display value (0xCD650 arg). Readers: 0x41890, 0x3EE10. Menu: -.
    /// Boot value 127.
    public var display06: UInt16 {
        get { readU16(0x0006) }
        set { writeU16(0x0006, newValue) }
    }

    /// +0x0008 u64 config+0x08: constants. Readers: no reader found. Menu: -.
    /// Boot value 71777214294589441.
    public var constants08: UInt64 {
        get { readU64(0x0008) }
        set { writeU64(0x0008, newValue) }
    }

    /// +0x0010 u16 config+0x10: HUD constant. Readers: 0x53200, 0x53CF0 (HUD). Menu: -. Boot value 255.
    public var hud10: UInt16 {
        get { readU16(0x0010) }
        set { writeU16(0x0010, newValue) }
    }

    /// +0x0012 u16 config+0x12: HUD constant. Readers: 0x53CF0. Menu: -. Boot value 0.
    public var hud12: UInt16 {
        get { readU16(0x0012) }
        set { writeU16(0x0012, newValue) }
    }

    /// +0x0014 u16 config+0x14: music volume 0..100 (%). Readers: 0x41890/0x3E9B0: runtime byte
    /// 0x17DA268+0xC = (1 - mute +0xA6) * value; UI 0x412F0. Menu: page 1 item 82 (Sound: Music
    /// value). Boot value 40.
    public var musicVolume: UInt16 {
        get { readU16(0x0014) }
        set { writeU16(0x0014, newValue) }
    }

    /// +0x0016 u16 config+0x16: Play All Voices: 100 = on, 0 = off. Readers: runtime 0x17DA268+0xD;
    /// voice code 0x41AB0, 0x7E790, 0x92380, 0x95E60, 0xA300, 0xAD80. Menu: page 1 item 92
    /// (== 1 -> 100 else 0). Boot value 100.
    public var playAllVoices: UInt16 {
        get { readU16(0x0016) }
        set { writeU16(0x0016, newValue) }
    }

    /// +0x0018 u16 config+0x18: SFX volume 0..100. Readers: runtime 0x17DA268+0xE =
    /// (1 - mute +0xA7) * value. Menu: page 1 item 87. Boot value 40.
    public var sfxVolume: UInt16 {
        get { readU16(0x0018) }
        set { writeU16(0x0018, newValue) }
    }

    /// +0x001A u16 config+0x1A: System Effects volume 0..100. Readers: runtime 0x17DA268+0xF =
    /// (1 - mute +0xA8) * value. Menu: page 1 item 91. Boot value 10.
    public var systemSeVolume: UInt16 {
        get { readU16(0x001A) }
        set { writeU16(0x001A, newValue) }
    }

    /// +0x001C u16 config+0x1C: constant (movie path). Readers: 0x68A70. Menu: -. Boot value 0.
    public var word1C: UInt16 {
        get { readU16(0x001C) }
        set { writeU16(0x001C, newValue) }
    }

    /// +0x001E u16 config+0x1E: constant (BGM start). Readers: 0x98C0, 0x9B40 (BGM). Menu: -.
    /// Boot value 0.
    public var word1E: UInt16 {
        get { readU16(0x001E) }
        set { writeU16(0x001E, newValue) }
    }

    /// +0x0020 u16 config+0x20: Unseen Text Display Speed (ms per character unit, max 250). Readers:
    /// reveal speed 0x56160 / 0x561D0 / 0xA2630 (textbox.md 8.1); UI preview 0x40C30. Menu: page 0
    /// item 55. Boot value 35.
    public var unseenTextSpeed: UInt16 {
        get { readU16(0x0020) }
        set { writeU16(0x0020, newValue) }
    }

    /// +0x0022 u16 config+0x22: Seen Text Display Speed (max 250). Readers: reveal speed for read
    /// lines (textbox.md 8.1). Menu: page 0 item 59. Boot value 15.
    public var seenTextSpeed: UInt16 {
        get { readU16(0x0022) }
        set { writeU16(0x0022, newValue) }
    }

    /// +0x0024 i16 config+0x24: language (0 ja, 1 en, 2 zc, 3 zt, >= 4 system). Readers: Lang_Index
    /// 0x3ED90 and 13 other readers. Menu: page 0 items 75..78 (written by 0x406B0); SaveImage_LoadSystem
    /// 0x6FE94: < 0 (boot 0xFFFF) -> 0x407F0() (system language). Boot value 65535.
    public var language: Int16 {
        get { readI16(0x0024) }
        set { writeI16(0x0024, newValue) }
    }

    /// +0x0026 u16 config+0x26: text draw constant. Readers: 0x53CF0, 0x7C340, 0xC8F50 (block
    /// draw). Menu: -. Boot value 1.
    public var textDraw26: UInt16 {
        get { readU16(0x0026) }
        set { writeU16(0x0026, newValue) }
    }

    /// +0x0028 u16 config+0x28: text constant. Readers: 0x3A030, 0x3C360, 0x3C4B0, 0x53200,
    /// 0x53CF0, 0x7C340, 0xA6E10, 0xD0190. Menu: -. Boot value 0.
    public var text28: UInt16 {
        get { readU16(0x0028) }
        set { writeU16(0x0028, newValue) }
    }

    /// +0x002A u16 config+0x2A: text colour mode: 0 fixed, 1 read-text colour 0xDC6D, 2 per-speaker
    /// colour (0x86A8B0). Readers: History_Restore 0x7D977, 0x60710, Z handlers 0x92380.., 0x7B790.
    /// Menu: -. Boot value 0.
    public var textColourMode: UInt16 {
        get { readU16(0x002A) }
        set { writeU16(0x002A, newValue) }
    }

    /// +0x002C u16 config+0x2C: audio constant. Readers: 0x80180.., MPLY 0x87AF0, SEPL 0x893F0,
    /// 0x95130. Menu: -. Boot value 0.
    public var audio2C: UInt16 {
        get { readU16(0x002C) }
        set { writeU16(0x002C, newValue) }
    }

    /// +0x002E u16 config+0x2E: Auto-Mode Wait Time (ms, max 10000). Readers: auto mode (Adv_Update),
    /// UI 0x40C30. Menu: page 0 item 65. Boot value 2200.
    public var autoModeWait: UInt16 {
        get { readU16(0x002E) }
        set { writeU16(0x002E, newValue) }
    }

    /// +0x0030 u16 config+0x30: Fast-Forward: 1 = read text only, 0 = all text. Readers: 0x60710
    /// 0x612DF / 0x61B0D stop skipping at unread text (0x75C90); Adv_Update 0xA0E71;
    /// Script_Prefetch. Menu: page 0 item 70 (row 'Fast-Forward'). Boot value 1.
    public var fastForwardReadOnly: UInt16 {
        get { readU16(0x0030) }
        set { writeU16(0x0030, newValue) }
    }

    /// +0x0032 u16 config+0x32: scene-jump buttons enabled. Readers: 0x60710 0x6101D
    /// (next/previous scene). Menu: -. Boot value 1.
    public var sceneJumpButtons: UInt16 {
        get { readU16(0x0032) }
        set { writeU16(0x0032, newValue) }
    }

    /// +0x0034 u16 config+0x34: constant. Readers: 0x41890, 0x3EE10. Menu: -. Boot value 1.
    public var constant34: UInt16 {
        get { readU16(0x0034) }
        set { writeU16(0x0034, newValue) }
    }

    /// +0x0036 u16 config+0x36: constant (voice gate with +0x16). Readers: 0x41AB0: voice enabled =
    /// +0x16 != 0 && +0x36 != 0. Menu: -. Boot value 1.
    public var voiceGate36: UInt16 {
        get { readU16(0x0036) }
        set { writeU16(0x0036, newValue) }
    }

    /// +0x003C u32 config+0x3C: per-character voice enable bits (bit i, 19 used). Readers: voice
    /// play 0xA300/0xAD80, 0x92380, 0x95E60, 0x9B760. Menu: page 1 items 98+5i (mute toggle == 1
    /// clears bit i). Boot value 1073741823.
    public var voiceEnableBits: UInt32 {
        get { readU32(0x003C) }
        set { writeU32(0x003C, newValue) }
    }

    /// +0x0040 u16 config+0x40: auto save mask: unused (its only reader 0x98BBF in _ATSV is
    /// unreachable; boot value 3). Readers: Script_Step 0x98BBF (dead branch: _ATSV(8) auto-saves
    /// without testing it). Menu: -. Boot value 3.
    public var autoSaveMask: UInt16 {
        get { readU16(0x0040) }
        set { writeU16(0x0040, newValue) }
    }

    /// +0x0042 u16 config+0x42: action preset (0..2, selects the action-mask table). Readers: 0x41890
    /// -> 0xCEEE0. Menu: -. Boot value 0.
    public var actionPreset: UInt16 {
        get { readU16(0x0042) }
        set { writeU16(0x0042, newValue) }
    }

    /// +0x0044 u16 config+0x44: choice-screen constant. Readers: 0xA6180, 0xA6940, 0xA6AD0.
    /// Menu: -. Boot value 0.
    public var choice44: UInt16 {
        get { readU16(0x0044) }
        set { writeU16(0x0044, newValue) }
    }

    /// +0x0046 u16 config+0x46: HUD constant. Readers: 0x53CF0. Menu: -. Boot value 0.
    public var hud46: UInt16 {
        get { readU16(0x0046) }
        set { writeU16(0x0046, newValue) }
    }

    /// +0x004A u16 config+0x4A: HUD constant. Readers: 0x45910, 0x45A30, 0x53CF0, 0x57080.
    /// Menu: -. Boot value 0.
    public var hud4A: UInt16 {
        get { readU16(0x004A) }
        set { writeU16(0x004A, newValue) }
    }

    /// +0x004C u16 config+0x4C: restore +0x04 from history (gate). Readers: History_Restore 0x7CA07,
    /// 0x41DB0, 0x41FC0. Menu: -. Boot value 0.
    public var restoreLiveValueGate: UInt16 {
        get { readU16(0x004C) }
        set { writeU16(0x004C, newValue) }
    }

    /// +0x004E u16 config+0x4E: Interrupt Voices on Advancing Text. Readers: Adv_Update 0xA1027,
    /// 0xA115B, 0xA1254 -> 0x8EA0 (stop voice). Menu: page 1 item 94. Boot value 1.
    public var interruptVoices: UInt16 {
        get { readU16(0x004E) }
        set { writeU16(0x004E, newValue) }
    }

    /// +0x0050 u16 config+0x50: constant. Readers: 0x56AB0. Menu: -. Boot value 1.
    public var constant50: UInt16 {
        get { readU16(0x0050) }
        set { writeU16(0x0050, newValue) }
    }

    /// +0x0054 u16 config+0x54: music volume copy (ducking base). Readers: runtime 0x17DA268+0xB =
    /// (1 - mute +0xA6) * value. Menu: copy of +0x14 (0x3E84E). Boot value 40.
    public var musicVolumeCopy: UInt16 {
        get { readU16(0x0054) }
        set { writeU16(0x0054, newValue) }
    }

    /// +0x0056 u16 config+0x56: dialog constant. Readers: 0x60710 (> 0: 0xA5DC0 dialog), 0xC6E0,
    /// 0xE8280. Menu: -. Boot value 0.
    public var dialog56: UInt16 {
        get { readU16(0x0056) }
        set { writeU16(0x0056, newValue) }
    }

    /// +0x0058 u16 config+0x58: constant. Readers: 0x57080, 0x5A5E0. Menu: -. Boot value 0.
    public var constant58: UInt16 {
        get { readU16(0x0058) }
        set { writeU16(0x0058, newValue) }
    }

    /// +0x005A, 0x1C bytes, config+0x5A: two 14-byte records copied from 0x164FCD8 / 0x164FCE8 by
    /// 0x419D0 at commit and back by 0x41890 at load (filled at boot by 0x75F10 from *0x86AA00 /
    /// *0x86AA08). Readers: 0x41890, 0x419D0. Menu: -. Boot value 0.
    public func bootRecords() -> ByteWindow { slice(0x005A, 0x1C) }

    /// +0x0076, u16 x 19, config+0x76[index]: per-character voice volume u16[19] (0..100). Readers:
    /// voice play 0xA300/0xAD80, 0x7E790, 0x3E9B0 test playback. Menu: page 1 items 100+5i
    /// (i < 19); defaults 16 x 50 (0x1A66A0) + 3 x 50. Boot value 50.
    public func getCharacterVoiceVolume(_ index: Int) -> UInt16 {
        readU16(0x0076 + 2 * Self.checkIndex(index, ConfigBlock.characterVoiceVolumeCount))
    }

    /// Sets config+0x76[index].
    public func setCharacterVoiceVolume(_ index: Int, _ value: UInt16) {
        writeU16(0x0076 + 2 * Self.checkIndex(index, ConfigBlock.characterVoiceVolumeCount), value)
    }

    /// +0x009C u8 config+0x9C: Display End of Page Instantly (unseen text). Readers: page option
    /// latch 0x56140 (textbox.md 8.3). Menu: page 0 item 54. Boot value 0.
    public var pageEndInstantUnseen: UInt8 {
        get { readU8(0x009C) }
        set { writeU8(0x009C, newValue) }
    }

    /// +0x009D u8 config+0x9D: Display End of Page Instantly (seen text). Readers: History_Restore
    /// 0x7D956, 0x92380. Menu: page 0 item 58. Boot value 0.
    public var pageEndInstantSeen: UInt8 {
        get { readU8(0x009D) }
        set { writeU8(0x009D, newValue) }
    }

    /// +0x009E u16 config+0x9E: Auto-Mode Advance Page Speed (ms, max 10000). Readers: auto mode,
    /// UI 0x40C30. Menu: page 0 item 62. Boot value 3000.
    public var autoModePageSpeed: UInt16 {
        get { readU16(0x009E) }
        set { writeU16(0x009E, newValue) }
    }

    /// +0x00A0 u16 config+0xA0: Auto Skip Cleared Scenes. Readers: 0x61F40. Menu: page 0 item 66.
    /// Boot value 0.
    public var autoSkipCleared: UInt16 {
        get { readU16(0x00A0) }
        set { writeU16(0x00A0, newValue) }
    }

    /// +0x00A2 u8 config+0xA2: Show Confirmation Message (auto skip). Readers: 0x60710 0x608F1.
    /// Menu: page 0 item 68. Boot value 0.
    public var skipConfirm: UInt8 {
        get { readU8(0x00A2) }
        set { writeU8(0x00A2, newValue) }
    }

    /// +0x00A3 u8 config+0xA3: Text Display Animations. Readers: block draw 0xC8F50. Menu: page 0
    /// item 72. Boot value 0.
    public var textAnimations: UInt8 {
        get { readU8(0x00A3) }
        set { writeU8(0x00A3, newValue) }
    }

    /// +0x00A4 u8 config+0xA4: Seen Text Display Animations. Readers: HUD 0x53CF0 (previous-message
    /// fade, textbox.md 5.8). Menu: page 0 item 74. Boot value 0.
    public var seenTextAnimations: UInt8 {
        get { readU8(0x00A4) }
        set { writeU8(0x00A4, newValue) }
    }

    /// +0x00A5 u8 config+0xA5: constant. Readers: FADS 0x81520, 0xC0330. Menu: -. Boot value 1.
    public var constantA5: UInt8 {
        get { readU8(0x00A5) }
        set { writeU8(0x00A5, newValue) }
    }

    /// +0x00A6 u8 config+0xA6: Music mute. Readers: volume formula above. Menu: page 1 item 81.
    /// Boot value 0.
    public var musicMute: UInt8 {
        get { readU8(0x00A6) }
        set { writeU8(0x00A6, newValue) }
    }

    /// +0x00A7 u8 config+0xA7: SFX mute. Readers: volume formula above. Menu: page 1 item 85.
    /// Boot value 0.
    public var sfxMute: UInt8 {
        get { readU8(0x00A7) }
        set { writeU8(0x00A7, newValue) }
    }

    /// +0x00A8 u8 config+0xA8: System Effects mute. Readers: volume formula above. Menu: page 1
    /// item 90. Boot value 0.
    public var systemSeMute: UInt8 {
        get { readU8(0x00A8) }
        set { writeU8(0x00A8, newValue) }
    }
}
