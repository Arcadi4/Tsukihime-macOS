import Foundation
import TsukiCore

/// The persistent config fields the sound code reads (config block at data VA 0x66C578; docs/formats/sound_runtime.md 2.4), with the
/// boot defaults of eboot VA 0x3EAC0. Port of `tsuki.misc_audio_runtime_semantics.Config`. The model reads these fields when it
/// needs them; `SoundModel.applyConfig` is `Sound_ApplyConfig` (VA 0x3E9B0) and copies them into the volume block.
public final class SoundConfig {
    /// Number of per-character voice volumes (config slots 0..18).
    public static let characterSlots = 19

    /// +0x14: BGM volume 0..100.
    public var bgm: Int = 40

    /// +0x16: voice master (menu item 0x5C: on = 100, off = 0).
    public var voice: Int = 100

    /// +0x18: SE volume.
    public var se: Int = 40

    /// +0x1A: system SE volume.
    public var sysSe: Int = 10

    /// +0x1C: 1 = lower the BGM while a voice plays (sound_runtime.md 9; config.md calls the field "constant (movie path)").
    public var duck: Int = 0

    /// +0x1E: 1 = the 5.1ch BGM set (entries n + 131, absent on the PS4 data).
    public var altBgm: Int = 0

    /// +0x2C: 1 = the SE notification hook runs after every started SE (`SoundModel.seStarted`).
    public var seCaption: Int = 0

    /// +0x30: voices also play in skip mode (read text only).
    public var skipVoice: Int = 1

    /// +0x36: second voice enable (0x41AB0); not written by the boot defaults routine, 1 in the saved config.
    public var voiceOn2: Int = 1

    /// +0x3C: bit k = the voice of config slot k is on.
    public var charEnable: UInt32 = 0x3FFFFFFF

    /// +0x4E: stop the voice when the text advances.
    public var stopOnAdvance: Int = 1

    /// +0x54: movie volume (a copy of +0x14).
    public var movie: Int = 40

    /// +0x76 + 2k: voice volume of config slot k (0..100).
    public var charVol: [Int] = [Int](repeating: 50, count: SoundConfig.characterSlots)

    /// +0xA6: mute BGM and movie.
    public var muteBgm: Int = 0

    /// +0xA7: mute SE.
    public var muteSe: Int = 0

    /// +0xA8: mute system SE.
    public var muteSys: Int = 0

    public init() {}

    /// Reads the sound fields of a config block (the persistent block of the engine).
    public static func fromBlock(_ block: ConfigBlock) -> SoundConfig {
        let c = SoundConfig()
        c.readFrom(block)
        return c
    }

    /// Copies the sound fields of `block`.
    public func readFrom(_ block: ConfigBlock) {
        bgm = Int(block.musicVolume)
        voice = Int(block.playAllVoices)
        se = Int(block.sfxVolume)
        sysSe = Int(block.systemSeVolume)
        duck = Int(block.word1C)
        altBgm = Int(block.word1E)
        seCaption = Int(block.audio2C)
        skipVoice = Int(block.fastForwardReadOnly)
        voiceOn2 = Int(block.voiceGate36)
        charEnable = block.voiceEnableBits
        stopOnAdvance = Int(block.interruptVoices)
        movie = Int(block.musicVolumeCopy)
        for i in 0..<SoundConfig.characterSlots {
            charVol[i] = Int(block.getCharacterVoiceVolume(i))
        }

        muteBgm = Int(block.musicMute)
        muteSe = Int(block.sfxMute)
        muteSys = Int(block.systemSeMute)
    }

    /// `Sound_ApplyConfig(full)` (VA 0x3E9B0): the bytes +0xB..+0xF of the volume block 0x17DA268 written into
    /// `volume` (a 16-byte array).
    public func fillVolumeBlock(_ volume: inout [UInt8]) {
        volume[0xC] = UInt8(truncatingIfNeeded: (1 - muteBgm) * bgm)
        volume[0xB] = UInt8(truncatingIfNeeded: (1 - muteBgm) * movie)
        volume[0xE] = UInt8(truncatingIfNeeded: (1 - muteSe) * se)
        volume[0xF] = UInt8(truncatingIfNeeded: (1 - muteSys) * sysSe)
        volume[0xD] = UInt8(truncatingIfNeeded: voice)
    }

    /// The voice gain of config slot `slot`: `char_vol[k] * voice / 100` (C division), or 0 when the slot's enable
    /// bit is clear (VA 0xB26D / 0x3EA4F / 0x928A2).
    public func charGain(_ slot: Int) -> Int {
        if (charEnable & (UInt32(1) << slot)) == 0 {
            return 0
        }

        return (SoundMath.i16(charVol[slot]) * SoundMath.i16(voice)) / 100
    }
}
