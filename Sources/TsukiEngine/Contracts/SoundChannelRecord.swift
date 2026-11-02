import Foundation
import TsukiCore

/// One sound channel record (0x34 bytes): BGM slots, voice streams and script SE channels
/// (sound_runtime.md 2.2).
///
/// Ported from `Tsuki.Engine/Contracts/Generated/SoundChannelRecord.g.cs` (generator
/// `tools/setup/gen_state_blocks.py`; source `tsuki.misc_audio_runtime_semantics.Rec`).
public final class SoundChannelRecord: StateBlock {
    /// Size of the block in bytes (0x34).
    public static let size = 0x34

    /// Data VA of the two BGM records (streams 0, 1; sound_runtime.md 2.1).
    public static let bgmRecordsVa: Int64 = 0xDD86A0

    /// Data VA of the four voice records (streams 2..5).
    public static let voiceRecordsVa: Int64 = 0xDD8B20

    /// Data VA of the twenty script SE records (streams 6..25, channel c = stream - 6).
    public static let seRecordsVa: Int64 = 0xDD8710

    /// Creates a zeroed block.
    public init() {
        super.init(size: SoundChannelRecord.size)
    }

    /// Creates a view of the `size` bytes of `storage` at `offset` (shared, not copied).
    public init(storage: ByteStorage, offset: Int = 0) {
        super.init(storage: storage, offset: offset, length: SoundChannelRecord.size)
    }

    /// Every byte of the block in exactly one field, in offset order.
    public static let fields: [StateField] = [
        StateField(name: "state", oracleName: "state", offset: 0x0000, size: 0x4, kind: .scalar, type: "u32"),
        StateField(name: "volumeClass", oracleName: "kind", offset: 0x0004, size: 0x4, kind: .scalar, type: "u32"),
        StateField(name: "started", oracleName: "w8", offset: 0x0008, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "entry", oracleName: "idx", offset: 0x000A, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "volume", oracleName: "vol", offset: 0x000C, size: 0x4, kind: .scalar, type: "f32"),
        StateField(name: "volumeTarget", oracleName: "vol_to", offset: 0x0010, size: 0x4, kind: .scalar, type: "f32"),
        StateField(name: "volumeStep", oracleName: "vol_rate", offset: 0x0014, size: 0x4, kind: .scalar, type: "f32"),
        StateField(name: "pan", oracleName: "pan", offset: 0x0018, size: 0x4, kind: .scalar, type: "f32"),
        StateField(name: "panTarget", oracleName: "pan_to", offset: 0x001C, size: 0x4, kind: .scalar, type: "f32"),
        StateField(name: "panStep", oracleName: "pan_rate", offset: 0x0020, size: 0x4, kind: .scalar, type: "f32"),
        StateField(name: "ramp3", oracleName: "p3", offset: 0x0024, size: 0x4, kind: .scalar, type: "f32"),
        StateField(name: "ramp3Target", oracleName: "p3_to", offset: 0x0028, size: 0x4, kind: .scalar, type: "f32"),
        StateField(name: "ramp3Step", oracleName: "p3_rate", offset: 0x002C, size: 0x4, kind: .scalar, type: "f32"),
        StateField(name: "character", oracleName: "char", offset: 0x0030, size: 0x1, kind: .scalar, type: "u8"),
        StateField(name: "padding31", oracleName: "pad", offset: 0x0031, size: 0x3, kind: .unused, type: "bytes"),
    ]

    /// A copy of the block in a new array.
    public func clone() -> SoundChannelRecord {
        let c = SoundChannelRecord()
        c.copy(from: self)
        return c
    }

    /// +0x0000 u32 state: 0 idle, 1 playing, 2 fading out (stop when the volume reaches 0).
    public var state: UInt32 {
        get { readU32(0x0000) }
        set { writeU32(0x0000, newValue) }
    }

    /// +0x0004 u32 kind: volume class ("kind"): 1 = SE (volume byte +0xE), 3 = system (+0xF), else
    /// voice (+0xD).
    public var volumeClass: UInt32 {
        get { readU32(0x0004) }
        set { writeU32(0x0004, newValue) }
    }

    /// +0x0008 u16 w8: 1 = a stream was started (the frame update skips the record when 0).
    public var started: UInt16 {
        get { readU16(0x0008) }
        set { writeU16(0x0008, newValue) }
    }

    /// +0x000A u16 idx: bgm.hed / vse.hed entry.
    public var entry: UInt16 {
        get { readU16(0x000A) }
        set { writeU16(0x000A, newValue) }
    }

    /// +0x000C f32 vol: current volume, 0..100 (the script's percentage).
    public var volume: Float {
        get { readF32(0x000C) }
        set { writeF32(0x000C, newValue) }
    }

    /// +0x0010 f32 vol_to: target volume.
    public var volumeTarget: Float {
        get { readF32(0x0010) }
        set { writeF32(0x0010, newValue) }
    }

    /// +0x0014 f32 vol_rate: ramp step per frame (<= 0 is replaced by 0.2).
    public var volumeStep: Float {
        get { readF32(0x0014) }
        set { writeF32(0x0014, newValue) }
    }

    /// +0x0018 f32 pan: current pan, -1000..1000 (stream pan = value * 0.001).
    public var pan: Float {
        get { readF32(0x0018) }
        set { writeF32(0x0018, newValue) }
    }

    /// +0x001C f32 pan_to: pan target.
    public var panTarget: Float {
        get { readF32(0x001C) }
        set { writeF32(0x001C, newValue) }
    }

    /// +0x0020 f32 pan_rate: pan step per frame (0 = no sweep).
    public var panStep: Float {
        get { readF32(0x0020) }
        set { writeF32(0x0020, newValue) }
    }

    /// +0x0024 f32 p3: third ramp, current (set only by the unused _SEP3; never sent to the stream).
    public var ramp3: Float {
        get { readF32(0x0024) }
        set { writeF32(0x0024, newValue) }
    }

    /// +0x0028 f32 p3_to: third ramp, target.
    public var ramp3Target: Float {
        get { readF32(0x0028) }
        set { writeF32(0x0028, newValue) }
    }

    /// +0x002C f32 p3_rate: third ramp, step.
    public var ramp3Step: Float {
        get { readF32(0x002C) }
        set { writeF32(0x002C, newValue) }
    }

    /// +0x0030 u8 char: character 1..19 (`070) for a voice-like SE, else 0.
    public var character: UInt8 {
        get { readU8(0x0030) }
        set { writeU8(0x0030, newValue) }
    }
}
