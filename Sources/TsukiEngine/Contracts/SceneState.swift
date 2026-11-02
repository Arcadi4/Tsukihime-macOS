import Foundation
import TsukiCore

/// The script-side layer state at VA 0x16500C0 (0x1A08 bytes): 51 per-layer arrays of 40 entries,
/// the scalar globals and 4 unaddressed gaps (layers.md 3, adv_state.md 2.6). A history record
/// holds it twice (+0x58 and the committed copy +0x1A60).
///
/// Ported from `Tsuki.Engine/Contracts/Generated/SceneState.g.cs` (generator
/// `tools/setup/gen_state_blocks.py`; source `tsuki.misc_adv_system_state.SCENE_STATE_FIELDS` +
/// `tsuki.misc_layer_state_and_motions.SCENE_ARRAYS`).
public final class SceneState: StateBlock {
    /// Size of the block in bytes (0x1A08).
    public static let size = 0x1A08

    /// Number of layers; every per-layer array has one entry per layer (layers.md 3).
    public static let layers = 40

    /// Values per entry of `crop`.
    public static let cropPerEntry = 4

    /// Values per entry of `shakeKind`.
    public static let shakeKindPerEntry = 2

    /// Values per entry of `shakeFade`.
    public static let shakeFadePerEntry = 2

    /// Values per entry of `shakeTime`.
    public static let shakeTimePerEntry = 2

    /// Values per entry of `shakePar`.
    public static let shakeParPerEntry = 12

    /// Creates a zeroed block.
    public init() {
        super.init(size: SceneState.size)
    }

    /// Creates a view of the `size` bytes of `storage` at `offset` (shared, not copied).
    public init(storage: ByteStorage, offset: Int = 0) {
        super.init(storage: storage, offset: offset, length: SceneState.size)
    }

    /// Every byte of the block in exactly one field, in offset order.
    public static let fields: [StateField] = [
        StateField(name: "scenePic", oracleName: "scene_pic", offset: 0x0000, size: 0x2, kind: .scalar, type: "i16"),
        StateField(name: "colourMode", oracleName: "colour_mode", offset: 0x0002, size: 0x2, kind: .scalar, type: "i16"),
        StateField(name: "pic", oracleName: "pic", offset: 0x0004, size: 0x50, kind: .array, type: "i16", count: 40),
        StateField(name: "blend", oracleName: "blend", offset: 0x0054, size: 0x50, kind: .array, type: "i16", count: 40),
        StateField(name: "flags", oracleName: "flags", offset: 0x00A4, size: 0x28, kind: .array, type: "u8", count: 40),
        StateField(name: "fxMode", oracleName: "fx_mode", offset: 0x00CC, size: 0x28, kind: .array, type: "i8", count: 40),
        StateField(name: "fxA", oracleName: "fx_a", offset: 0x00F4, size: 0x50, kind: .array, type: "i16", count: 40),
        StateField(name: "fxB", oracleName: "fx_b", offset: 0x0144, size: 0x28, kind: .array, type: "i8", count: 40),
        StateField(name: "x", oracleName: "x", offset: 0x016C, size: 0x50, kind: .array, type: "i16", count: 40),
        StateField(name: "y", oracleName: "y", offset: 0x01BC, size: 0x50, kind: .array, type: "i16", count: 40),
        StateField(name: "alpha", oracleName: "alpha", offset: 0x020C, size: 0x50, kind: .array, type: "i16", count: 40),
        StateField(name: "state", oracleName: "state", offset: 0x025C, size: 0x28, kind: .array, type: "i8", count: 40),
        StateField(name: "u284", oracleName: "u284", offset: 0x0284, size: 0x28, kind: .array, type: "u8", count: 40),
        StateField(name: "u2ac", oracleName: "u2ac", offset: 0x02AC, size: 0x28, kind: .array, type: "u8", count: 40),
        StateField(name: "u2d4", oracleName: "u2d4", offset: 0x02D4, size: 0x28, kind: .array, type: "u8", count: 40),
        StateField(name: "z", oracleName: "z", offset: 0x02FC, size: 0x50, kind: .array, type: "i16", count: 40),
        StateField(name: "gap034C", oracleName: "gap_034c", offset: 0x034C, size: 0x4, kind: .unused, type: "bytes"),
        StateField(name: "rot", oracleName: "rot", offset: 0x0350, size: 0x140, kind: .array, type: "i64", count: 40),
        StateField(name: "scale", oracleName: "scale", offset: 0x0490, size: 0x50, kind: .array, type: "i16", count: 40),
        StateField(name: "anchorX", oracleName: "anchor_x", offset: 0x04E0, size: 0x50, kind: .array, type: "i16", count: 40),
        StateField(name: "anchorY", oracleName: "anchor_y", offset: 0x0530, size: 0x50, kind: .array, type: "i16", count: 40),
        StateField(name: "u580", oracleName: "u580", offset: 0x0580, size: 0x50, kind: .array, type: "i16", count: 40),
        StateField(name: "u5d0", oracleName: "u5d0", offset: 0x05D0, size: 0x50, kind: .array, type: "i16", count: 40),
        StateField(name: "u620", oracleName: "u620", offset: 0x0620, size: 0x50, kind: .array, type: "i16", count: 40),
        StateField(name: "u670", oracleName: "u670", offset: 0x0670, size: 0x50, kind: .array, type: "i16", count: 40),
        StateField(name: "u6c0", oracleName: "u6c0", offset: 0x06C0, size: 0x50, kind: .array, type: "i16", count: 40),
        StateField(name: "u710", oracleName: "u710", offset: 0x0710, size: 0x50, kind: .array, type: "i16", count: 40),
        StateField(name: "u760", oracleName: "u760", offset: 0x0760, size: 0x50, kind: .array, type: "i16", count: 40),
        StateField(name: "u7b0", oracleName: "u7b0", offset: 0x07B0, size: 0x50, kind: .array, type: "i16", count: 40),
        StateField(name: "u800", oracleName: "u800", offset: 0x0800, size: 0x50, kind: .array, type: "i16", count: 40),
        StateField(name: "u850", oracleName: "u850", offset: 0x0850, size: 0x50, kind: .array, type: "i16", count: 40),
        StateField(name: "zoomX", oracleName: "zoom_x", offset: 0x08A0, size: 0x50, kind: .array, type: "i16", count: 40),
        StateField(name: "zoomY", oracleName: "zoom_y", offset: 0x08F0, size: 0x50, kind: .array, type: "i16", count: 40),
        StateField(name: "zoomPivot", oracleName: "zoom_pivot", offset: 0x0940, size: 0x28, kind: .array, type: "i8", count: 40),
        StateField(name: "mask", oracleName: "mask", offset: 0x0968, size: 0x50, kind: .array, type: "i16", count: 40),
        StateField(name: "sttr", oracleName: "sttr", offset: 0x09B8, size: 0x50, kind: .array, type: "i16", count: 40),
        StateField(name: "parent", oracleName: "parent", offset: 0x0A08, size: 0xA0, kind: .array, type: "i32", count: 40),
        StateField(name: "soxyX", oracleName: "soxy_x", offset: 0x0AA8, size: 0x28, kind: .array, type: "i8", count: 40),
        StateField(name: "soxyY", oracleName: "soxy_y", offset: 0x0AD0, size: 0x28, kind: .array, type: "i8", count: 40),
        StateField(name: "crop", oracleName: "crop", offset: 0x0AF8, size: 0x140, kind: .array, type: "i16", count: 40, perEntry: 4),
        StateField(name: "a16", oracleName: "a16", offset: 0x0C38, size: 0x50, kind: .array, type: "u16", count: 40),
        StateField(name: "a17", oracleName: "a17", offset: 0x0C88, size: 0x28, kind: .array, type: "u8", count: 40),
        StateField(name: "angle", oracleName: "angle", offset: 0x0CB0, size: 0x50, kind: .array, type: "i16", count: 40),
        StateField(name: "motion", oracleName: "motion", offset: 0x0D00, size: 0x3C0, kind: .array, type: "bytes", count: 40),
        StateField(name: "shakeKind", oracleName: "shake_kind", offset: 0x10C0, size: 0x50, kind: .array, type: "u8", count: 40, perEntry: 2),
        StateField(name: "shakeFade", oracleName: "shake_fade", offset: 0x1110, size: 0xA0, kind: .array, type: "i16", count: 40, perEntry: 2),
        StateField(name: "shakeTime", oracleName: "shake_time", offset: 0x11B0, size: 0xA0, kind: .array, type: "i16", count: 40, perEntry: 2),
        StateField(name: "shakePar", oracleName: "shake_par", offset: 0x1250, size: 0x3C0, kind: .array, type: "i16", count: 40, perEntry: 12),
        StateField(name: "stra", oracleName: "stra", offset: 0x1610, size: 0x50, kind: .array, type: "i16", count: 40),
        StateField(name: "stns", oracleName: "stns", offset: 0x1660, size: 0x28, kind: .array, type: "u8", count: 40),
        StateField(name: "stnsB", oracleName: "stns_b", offset: 0x1688, size: 0x28, kind: .array, type: "u8", count: 40),
        StateField(name: "ext", oracleName: "ext", offset: 0x16B0, size: 0x2D0, kind: .array, type: "bytes", count: 40),
        StateField(name: "picTableIndex", oracleName: "pic_table_index", offset: 0x1980, size: 0x2, kind: .scalar, type: "i16"),
        StateField(name: "textWindowA", oracleName: "text_window_a", offset: 0x1982, size: 0x2, kind: .scalar, type: "i16"),
        StateField(name: "textWindowB", oracleName: "text_window_b", offset: 0x1984, size: 0x2, kind: .scalar, type: "i16"),
        StateField(name: "commit49620A", oracleName: "commit_49620_a", offset: 0x1986, size: 0x2, kind: .scalar, type: "i16"),
        StateField(name: "commit49620B", oracleName: "commit_49620_b", offset: 0x1988, size: 0x2, kind: .scalar, type: "i16"),
        StateField(name: "commit495F0A", oracleName: "commit_495f0_a", offset: 0x198A, size: 0x2, kind: .scalar, type: "i16"),
        StateField(name: "commit495F0B", oracleName: "commit_495f0_b", offset: 0x198C, size: 0x2, kind: .scalar, type: "i16"),
        StateField(name: "commit495F0C", oracleName: "commit_495f0_c", offset: 0x198E, size: 0x2, kind: .scalar, type: "i16"),
        StateField(name: "reset1990", oracleName: "reset_1990", offset: 0x1990, size: 0x8, kind: .scalar, type: "u64"),
        StateField(name: "reset1998", oracleName: "reset_1998", offset: 0x1998, size: 0x2, kind: .scalar, type: "u16"),
        StateField(name: "word199A", oracleName: "word_199a", offset: 0x199A, size: 0x2, kind: .scalar, type: "i16"),
        StateField(name: "word199C", oracleName: "word_199c", offset: 0x199C, size: 0x2, kind: .scalar, type: "i16"),
        StateField(name: "word199E", oracleName: "word_199e", offset: 0x199E, size: 0x2, kind: .scalar, type: "i16"),
        StateField(name: "byte19A0", oracleName: "byte_19a0", offset: 0x19A0, size: 0x1, kind: .scalar, type: "u8"),
        StateField(name: "byte19A1", oracleName: "byte_19a1", offset: 0x19A1, size: 0x1, kind: .scalar, type: "u8"),
        StateField(name: "effect19A2", oracleName: "effect_19a2", offset: 0x19A2, size: 0x1, kind: .scalar, type: "u8"),
        StateField(name: "f995Low", oracleName: "f995_low", offset: 0x19A3, size: 0x1, kind: .scalar, type: "u8"),
        StateField(name: "byte19A4", oracleName: "byte_19a4", offset: 0x19A4, size: 0x1, kind: .scalar, type: "u8"),
        StateField(name: "gap19A5", oracleName: "gap_19a5", offset: 0x19A5, size: 0x1, kind: .unused, type: "bytes"),
        StateField(name: "f967Base", oracleName: "f967_base", offset: 0x19A6, size: 0x2, kind: .scalar, type: "i16"),
        StateField(name: "byte19A8", oracleName: "byte_19a8", offset: 0x19A8, size: 0x1, kind: .scalar, type: "u8"),
        StateField(name: "byte19A9", oracleName: "byte_19a9", offset: 0x19A9, size: 0x1, kind: .scalar, type: "u8"),
        StateField(name: "byte19AA", oracleName: "byte_19aa", offset: 0x19AA, size: 0x1, kind: .scalar, type: "i8"),
        StateField(name: "u19ab", oracleName: "u19ab", offset: 0x19AB, size: 0x28, kind: .array, type: "u8", count: 40),
        StateField(name: "u19d3", oracleName: "u19d3", offset: 0x19D3, size: 0x28, kind: .array, type: "u8", count: 40),
        StateField(name: "gap19FB", oracleName: "gap_19fb", offset: 0x19FB, size: 0x1, kind: .unused, type: "bytes"),
        StateField(name: "screenEffect", oracleName: "screen_effect", offset: 0x19FC, size: 0x2, kind: .scalar, type: "i16"),
        StateField(name: "screenEffectP0", oracleName: "screen_effect_p0", offset: 0x19FE, size: 0x2, kind: .scalar, type: "i16"),
        StateField(name: "screenEffectP1", oracleName: "screen_effect_p1", offset: 0x1A00, size: 0x2, kind: .scalar, type: "i16"),
        StateField(name: "screenEffectP2", oracleName: "screen_effect_p2", offset: 0x1A02, size: 0x2, kind: .scalar, type: "i16"),
        StateField(name: "screenEffectP3", oracleName: "screen_effect_p3", offset: 0x1A04, size: 0x2, kind: .scalar, type: "i16"),
        StateField(name: "gap1A06", oracleName: "gap_1a06", offset: 0x1A06, size: 0x2, kind: .unused, type: "bytes"),
    ]

    /// A copy of the block in a new array.
    public func clone() -> SceneState {
        let c = SceneState()
        c.copy(from: self)
        return c
    }

    /// Sets every per-layer field of `layer` to its value after `_STCC` / scene start (layers.md 3
    /// column "default"; `tsuki.misc_layer_state_and_motions.SceneState.reset_layer`).
    public func resetLayer(_ layer: Int) {
        Self.checkIndex(layer, SceneState.layers)
        setPic(layer, -1)
        setBlend(layer, 0)
        setFlags(layer, 0)
        setFxMode(layer, 0)
        setFxA(layer, 0)
        setFxB(layer, 0)
        setX(layer, 0)
        setY(layer, 0)
        setAlpha(layer, 255)
        setState(layer, 0)
        setU284(layer, 0)
        setU2AC(layer, 0)
        setU2D4(layer, 0)
        setZ(layer, 0)
        setRot(layer, 0)
        setScale(layer, 1000)
        setAnchorX(layer, 0)
        setAnchorY(layer, 0)
        setU580(layer, 0)
        setU5D0(layer, 0)
        setU620(layer, 0)
        setU670(layer, 0)
        setU6C0(layer, 0)
        setU710(layer, 0)
        setU760(layer, 0)
        setU7B0(layer, 0)
        setU800(layer, 0)
        setU850(layer, 0)
        setZoomX(layer, 1000)
        setZoomY(layer, 1000)
        setZoomPivot(layer, 0)
        setMask(layer, -1)
        setSttr(layer, -1)
        setParent(layer, -1)
        setSoxyX(layer, 0)
        setSoxyY(layer, 0)
        setCrop(layer, 0, 0)
        setCrop(layer, 1, 0)
        setCrop(layer, 2, 0)
        setCrop(layer, 3, 0)
        setA16(layer, 0)
        setA17(layer, 0)
        setAngle(layer, 0)
        motion(layer).clear()
        setShakeKind(layer, 0, 0)
        setShakeKind(layer, 1, 0)
        setShakeFade(layer, 0, 0)
        setShakeFade(layer, 1, 0)
        setShakeTime(layer, 0, 0)
        setShakeTime(layer, 1, 0)
        setShakePar(layer, 0, 0)
        setShakePar(layer, 1, 0)
        setShakePar(layer, 2, 0)
        setShakePar(layer, 3, 0)
        setShakePar(layer, 4, 0)
        setShakePar(layer, 5, 0)
        setShakePar(layer, 6, 0)
        setShakePar(layer, 7, 0)
        setShakePar(layer, 8, 0)
        setShakePar(layer, 9, 0)
        setShakePar(layer, 10, 0)
        setShakePar(layer, 11, 0)
        setStra(layer, 0)
        setStns(layer, 0)
        setStnsB(layer, 0)
        ext(layer).clear()
        setU19AB(layer, 0)
        setU19D3(layer, 0)
    }

    /// A new block with every layer reset (``resetLayer(_:)``) and the globals zero, like the
    /// oracle's `SceneState()`.
    public static func createDefault() -> SceneState {
        let s = SceneState()
        for layer in 0..<layers {
            s.resetLayer(layer)
        }
        return s
    }

    /// +0x0000 i16 scene_pic: i16 scene-level picture id (layer work: pic-seen bit + 0x49C20 at the
    /// commit); reset 0x789F0, 0x7E4E0 (restore re-sync), 0xA3810 (from 0x5B400).
    public var scenePic: Int16 {
        get { readI16(0x0000) }
        set { writeI16(0x0000, newValue) }
    }

    /// +0x0002 i16 colour_mode: i16 colour-mode word -> render 0xDE2658 (0x49C30 at the commit;
    /// 2 = grey, 3 = sepia, compositing.md 9); 0xA3810.
    public var colourMode: Int16 {
        get { readI16(0x0002) }
        set { writeI16(0x0002, newValue) }
    }

    /// +0x0004, i16 x 40, pic[layer]: STCH SCH2 STCC; committed to +0x18 i32 (0x49F60: -1 if >= 0x59D8).
    public func getPic(_ layer: Int) -> Int16 { readI16(0x0004 + 2 * Self.checkIndex(layer, SceneState.layers)) }

    /// Sets pic[layer].
    public func setPic(_ layer: Int, _ value: Int16) { writeI16(0x0004 + 2 * Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x0054, i16 x 40, blend[layer]: STBR; committed to +0x1C (0x49F90).
    public func getBlend(_ layer: Int) -> Int16 { readI16(0x0054 + 2 * Self.checkIndex(layer, SceneState.layers)) }

    /// Sets blend[layer].
    public func setBlend(_ layer: Int, _ value: Int16) { writeI16(0x0054 + 2 * Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x00A4, u8 x 40, flags[layer]: STBR a3=1 -> |0x80, SACL -> 0x40; committed to +0x1E.
    public func getFlags(_ layer: Int) -> UInt8 { readU8(0x00A4 + Self.checkIndex(layer, SceneState.layers)) }

    /// Sets flags[layer].
    public func setFlags(_ layer: Int, _ value: UInt8) { writeU8(0x00A4 + Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x00CC, i8 x 40, fx_mode[layer]: STEC (and STCH from the global word 0x164B97C); committed
    /// to +0x1F (0x49FB0).
    public func getFxMode(_ layer: Int) -> Int8 { readI8(0x00CC + Self.checkIndex(layer, SceneState.layers)) }

    /// Sets fx_mode[layer].
    public func setFxMode(_ layer: Int, _ value: Int8) { writeI8(0x00CC + Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x00F4, i16 x 40, fx_a[layer]: SNX2; committed to +0x20 (0x49FB0).
    public func getFxA(_ layer: Int) -> Int16 { readI16(0x00F4 + 2 * Self.checkIndex(layer, SceneState.layers)) }

    /// Sets fx_a[layer].
    public func setFxA(_ layer: Int, _ value: Int16) { writeI16(0x00F4 + 2 * Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x0144, i8 x 40, fx_b[layer]: SNX3; committed to +0x22 (0x49FB0).
    public func getFxB(_ layer: Int) -> Int8 { readI8(0x0144 + Self.checkIndex(layer, SceneState.layers)) }

    /// Sets fx_b[layer].
    public func setFxB(_ layer: Int, _ value: Int8) { writeI8(0x0144 + Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x016C, i16 x 40, x[layer]: STCH SCH2 STCL; committed to +0x30 f32 (0x49FD0).
    public func getX(_ layer: Int) -> Int16 { readI16(0x016C + 2 * Self.checkIndex(layer, SceneState.layers)) }

    /// Sets x[layer].
    public func setX(_ layer: Int, _ value: Int16) { writeI16(0x016C + 2 * Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x01BC, i16 x 40, y[layer]: STCH SCH2 STCL; committed to +0x34 f32 (0x49FD0).
    public func getY(_ layer: Int) -> Int16 { readI16(0x01BC + 2 * Self.checkIndex(layer, SceneState.layers)) }

    /// Sets y[layer].
    public func setY(_ layer: Int, _ value: Int16) { writeI16(0x01BC + 2 * Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x020C, i16 x 40, alpha[layer]: STCH SCH2 STGS; committed to +0x2C f32 = alpha/255 (0x4A010).
    public func getAlpha(_ layer: Int) -> Int16 { readI16(0x020C + 2 * Self.checkIndex(layer, SceneState.layers)) }

    /// Sets alpha[layer].
    public func setAlpha(_ layer: Int, _ value: Int16) { writeI16(0x020C + 2 * Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x025C, i8 x 40, state[layer]: STCH SCH2 (0), engine; committed to +0x24 i32 (0x4A040).
    public func getState(_ layer: Int) -> Int8 { readI8(0x025C + Self.checkIndex(layer, SceneState.layers)) }

    /// Sets state[layer].
    public func setState(_ layer: Int, _ value: Int8) { writeI8(0x025C + Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x0284, u8 x 40, u284[layer]: copied by STCH src; committed to -.
    public func getU284(_ layer: Int) -> UInt8 { readU8(0x0284 + Self.checkIndex(layer, SceneState.layers)) }

    /// Sets u284[layer].
    public func setU284(_ layer: Int, _ value: UInt8) { writeU8(0x0284 + Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x02AC, u8 x 40, u2ac[layer]: copied by STCH src; committed to -.
    public func getU2AC(_ layer: Int) -> UInt8 { readU8(0x02AC + Self.checkIndex(layer, SceneState.layers)) }

    /// Sets u2ac[layer].
    public func setU2AC(_ layer: Int, _ value: UInt8) { writeU8(0x02AC + Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x02D4, u8 x 40, u2d4[layer]: copied by STCH src; committed to -.
    public func getU2D4(_ layer: Int) -> UInt8 { readU8(0x02D4 + Self.checkIndex(layer, SceneState.layers)) }

    /// Sets u2d4[layer].
    public func setU2D4(_ layer: Int, _ value: UInt8) { writeU8(0x02D4 + Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x02FC, i16 x 40, z[layer]: STCH SCH2 STCP; committed to draw order (0x4A180 sorts).
    public func getZ(_ layer: Int) -> Int16 { readI16(0x02FC + 2 * Self.checkIndex(layer, SceneState.layers)) }

    /// Sets z[layer].
    public func setZ(_ layer: Int, _ value: Int16) { writeI16(0x02FC + 2 * Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x0350, i64 x 40, rot[layer]: STRT STPV(a3) STCH(reset 0); committed to +0x58 i64 (0x4B270).
    public func getRot(_ layer: Int) -> Int64 { readI64(0x0350 + 8 * Self.checkIndex(layer, SceneState.layers)) }

    /// Sets rot[layer].
    public func setRot(_ layer: Int, _ value: Int64) { writeI64(0x0350 + 8 * Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x0490, i16 x 40, scale[layer]: STCH SCH2; committed to +0x70 (0x4B1A0).
    public func getScale(_ layer: Int) -> Int16 { readI16(0x0490 + 2 * Self.checkIndex(layer, SceneState.layers)) }

    /// Sets scale[layer].
    public func setScale(_ layer: Int, _ value: Int16) { writeI16(0x0490 + 2 * Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x04E0, i16 x 40, anchor_x[layer]: STCH SCH2 STPV; committed to +0x76 (0x4B1A0).
    public func getAnchorX(_ layer: Int) -> Int16 { readI16(0x04E0 + 2 * Self.checkIndex(layer, SceneState.layers)) }

    /// Sets anchor_x[layer].
    public func setAnchorX(_ layer: Int, _ value: Int16) { writeI16(0x04E0 + 2 * Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x0530, i16 x 40, anchor_y[layer]: STCH SCH2 STPV; committed to +0x78 (0x4B1A0).
    public func getAnchorY(_ layer: Int) -> Int16 { readI16(0x0530 + 2 * Self.checkIndex(layer, SceneState.layers)) }

    /// Sets anchor_y[layer].
    public func setAnchorY(_ layer: Int, _ value: Int16) { writeI16(0x0530 + 2 * Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x0580, i16 x 40, u580[layer]: copied by STCH src; committed to -.
    public func getU580(_ layer: Int) -> Int16 { readI16(0x0580 + 2 * Self.checkIndex(layer, SceneState.layers)) }

    /// Sets u580[layer].
    public func setU580(_ layer: Int, _ value: Int16) { writeI16(0x0580 + 2 * Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x05D0, i16 x 40, u5d0[layer]: copied by STCH src; committed to -.
    public func getU5D0(_ layer: Int) -> Int16 { readI16(0x05D0 + 2 * Self.checkIndex(layer, SceneState.layers)) }

    /// Sets u5d0[layer].
    public func setU5D0(_ layer: Int, _ value: Int16) { writeI16(0x05D0 + 2 * Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x0620, i16 x 40, u620[layer]: copied by STCH src; committed to -.
    public func getU620(_ layer: Int) -> Int16 { readI16(0x0620 + 2 * Self.checkIndex(layer, SceneState.layers)) }

    /// Sets u620[layer].
    public func setU620(_ layer: Int, _ value: Int16) { writeI16(0x0620 + 2 * Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x0670, i16 x 40, u670[layer]: copied by STCH src; committed to -.
    public func getU670(_ layer: Int) -> Int16 { readI16(0x0670 + 2 * Self.checkIndex(layer, SceneState.layers)) }

    /// Sets u670[layer].
    public func setU670(_ layer: Int, _ value: Int16) { writeI16(0x0670 + 2 * Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x06C0, i16 x 40, u6c0[layer]: copied by STCH src; committed to -.
    public func getU6C0(_ layer: Int) -> Int16 { readI16(0x06C0 + 2 * Self.checkIndex(layer, SceneState.layers)) }

    /// Sets u6c0[layer].
    public func setU6C0(_ layer: Int, _ value: Int16) { writeI16(0x06C0 + 2 * Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x0710, i16 x 40, u710[layer]: copied by STCH src; committed to -.
    public func getU710(_ layer: Int) -> Int16 { readI16(0x0710 + 2 * Self.checkIndex(layer, SceneState.layers)) }

    /// Sets u710[layer].
    public func setU710(_ layer: Int, _ value: Int16) { writeI16(0x0710 + 2 * Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x0760, i16 x 40, u760[layer]: copied by STCH src; committed to -.
    public func getU760(_ layer: Int) -> Int16 { readI16(0x0760 + 2 * Self.checkIndex(layer, SceneState.layers)) }

    /// Sets u760[layer].
    public func setU760(_ layer: Int, _ value: Int16) { writeI16(0x0760 + 2 * Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x07B0, i16 x 40, u7b0[layer]: copied by STCH src; committed to -.
    public func getU7B0(_ layer: Int) -> Int16 { readI16(0x07B0 + 2 * Self.checkIndex(layer, SceneState.layers)) }

    /// Sets u7b0[layer].
    public func setU7B0(_ layer: Int, _ value: Int16) { writeI16(0x07B0 + 2 * Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x0800, i16 x 40, u800[layer]: copied by STCH src; committed to -.
    public func getU800(_ layer: Int) -> Int16 { readI16(0x0800 + 2 * Self.checkIndex(layer, SceneState.layers)) }

    /// Sets u800[layer].
    public func setU800(_ layer: Int, _ value: Int16) { writeI16(0x0800 + 2 * Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x0850, i16 x 40, u850[layer]: copied by STCH src; committed to -.
    public func getU850(_ layer: Int) -> Int16 { readI16(0x0850 + 2 * Self.checkIndex(layer, SceneState.layers)) }

    /// Sets u850[layer].
    public func setU850(_ layer: Int, _ value: Int16) { writeI16(0x0850 + 2 * Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x08A0, i16 x 40, zoom_x[layer]: STZ4 a3; STCH SCH2 reset to 1000; committed to A +0xAA via 0x49930.
    public func getZoomX(_ layer: Int) -> Int16 { readI16(0x08A0 + 2 * Self.checkIndex(layer, SceneState.layers)) }

    /// Sets zoom_x[layer].
    public func setZoomX(_ layer: Int, _ value: Int16) { writeI16(0x08A0 + 2 * Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x08F0, i16 x 40, zoom_y[layer]: STZ4 a4; STCH SCH2 reset to 1000; committed to A +0xAC via 0x49930.
    public func getZoomY(_ layer: Int) -> Int16 { readI16(0x08F0 + 2 * Self.checkIndex(layer, SceneState.layers)) }

    /// Sets zoom_y[layer].
    public func setZoomY(_ layer: Int, _ value: Int16) { writeI16(0x08F0 + 2 * Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x0940, i8 x 40, zoom_pivot[layer]: STZ4 a7; STCH SCH2 reset to 0; committed to A +0xB0 via 0x49930.
    public func getZoomPivot(_ layer: Int) -> Int8 { readI8(0x0940 + Self.checkIndex(layer, SceneState.layers)) }

    /// Sets zoom_pivot[layer].
    public func setZoomPivot(_ layer: Int, _ value: Int8) { writeI8(0x0940 + Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x0968, i16 x 40, mask[layer]: STCH a11; committed to +0x120 i32.
    public func getMask(_ layer: Int) -> Int16 { readI16(0x0968 + 2 * Self.checkIndex(layer, SceneState.layers)) }

    /// Sets mask[layer].
    public func setMask(_ layer: Int, _ value: Int16) { writeI16(0x0968 + 2 * Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x09B8, i16 x 40, sttr[layer]: STTR; committed to +0x12C i32.
    public func getSttr(_ layer: Int) -> Int16 { readI16(0x09B8 + 2 * Self.checkIndex(layer, SceneState.layers)) }

    /// Sets sttr[layer].
    public func setSttr(_ layer: Int, _ value: Int16) { writeI16(0x09B8 + 2 * Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x0A08, i32 x 40, parent[layer]: SBAS; committed to +0x128 i32.
    public func getParent(_ layer: Int) -> Int32 { readI32(0x0A08 + 4 * Self.checkIndex(layer, SceneState.layers)) }

    /// Sets parent[layer].
    public func setParent(_ layer: Int, _ value: Int32) { writeI32(0x0A08 + 4 * Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x0AA8, i8 x 40, soxy_x[layer]: SOXY a1; committed to +0x130.
    public func getSoxyX(_ layer: Int) -> Int8 { readI8(0x0AA8 + Self.checkIndex(layer, SceneState.layers)) }

    /// Sets soxy_x[layer].
    public func setSoxyX(_ layer: Int, _ value: Int8) { writeI8(0x0AA8 + Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x0AD0, i8 x 40, soxy_y[layer]: SOXY a2; committed to +0x131.
    public func getSoxyY(_ layer: Int) -> Int8 { readI8(0x0AD0 + Self.checkIndex(layer, SceneState.layers)) }

    /// Sets soxy_y[layer].
    public func setSoxyY(_ layer: Int, _ value: Int8) { writeI8(0x0AD0 + Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x0AF8, 4 x i16 per entry x 40, crop[layer][index]: STCH a12..a15; committed to +0x132 4 x i16.
    public func getCrop(_ layer: Int, _ index: Int) -> Int16 {
        readI16(0x0AF8 + 8 * Self.checkIndex(layer, SceneState.layers) + 2 * Self.checkIndex(index, SceneState.cropPerEntry))
    }

    /// Sets crop[layer][index].
    public func setCrop(_ layer: Int, _ index: Int, _ value: Int16) {
        writeI16(0x0AF8 + 8 * Self.checkIndex(layer, SceneState.layers) + 2 * Self.checkIndex(index, SceneState.cropPerEntry), value)
    }

    /// +0x0C38, u16 x 40, a16[layer]: STCH a16; committed to +0x13A.
    public func getA16(_ layer: Int) -> UInt16 { readU16(0x0C38 + 2 * Self.checkIndex(layer, SceneState.layers)) }

    /// Sets a16[layer].
    public func setA16(_ layer: Int, _ value: UInt16) { writeU16(0x0C38 + 2 * Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x0C88, u8 x 40, a17[layer]: STCH a17; committed to +0x13C.
    public func getA17(_ layer: Int) -> UInt8 { readU8(0x0C88 + Self.checkIndex(layer, SceneState.layers)) }

    /// Sets a17[layer].
    public func setA17(_ layer: Int, _ value: UInt8) { writeU8(0x0C88 + Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x0CB0, i16 x 40, angle[layer]: STCH a19, STRR; committed to +0x15C.
    public func getAngle(_ layer: Int) -> Int16 { readI16(0x0CB0 + 2 * Self.checkIndex(layer, SceneState.layers)) }

    /// Sets angle[layer].
    public func setAngle(_ layer: Int, _ value: Int16) { writeI16(0x0CB0 + 2 * Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x0D00, 40 x 0x18 bytes, motion: entry layer. STMA SPMA; committed to +0x160 (0xBA8E0).
    public func motion(_ layer: Int) -> ByteWindow { slice(0x0D00 + 24 * Self.checkIndex(layer, SceneState.layers), 0x18) }

    /// +0x10C0, 2 x u8 per entry x 40, shake_kind[layer][index]: SQK2 (slot 0) SHK2/SSW2 (slot 1);
    /// committed to +0x178.
    public func getShakeKind(_ layer: Int, _ index: Int) -> UInt8 {
        readU8(0x10C0 + 2 * Self.checkIndex(layer, SceneState.layers) + Self.checkIndex(index, SceneState.shakeKindPerEntry))
    }

    /// Sets shake_kind[layer][index].
    public func setShakeKind(_ layer: Int, _ index: Int, _ value: UInt8) {
        writeU8(0x10C0 + 2 * Self.checkIndex(layer, SceneState.layers) + Self.checkIndex(index, SceneState.shakeKindPerEntry), value)
    }

    /// +0x1110, 2 x i16 per entry x 40, shake_fade[layer][index]: SQK2 SHK2 SSW2 a5; committed to +0x17A.
    public func getShakeFade(_ layer: Int, _ index: Int) -> Int16 {
        readI16(0x1110 + 4 * Self.checkIndex(layer, SceneState.layers) + 2 * Self.checkIndex(index, SceneState.shakeFadePerEntry))
    }

    /// Sets shake_fade[layer][index].
    public func setShakeFade(_ layer: Int, _ index: Int, _ value: Int16) {
        writeI16(0x1110 + 4 * Self.checkIndex(layer, SceneState.layers) + 2 * Self.checkIndex(index, SceneState.shakeFadePerEntry), value)
    }

    /// +0x11B0, 2 x i16 per entry x 40, shake_time[layer][index]: SQK2 SHK2 SSW2 a4; committed to +0x17E.
    public func getShakeTime(_ layer: Int, _ index: Int) -> Int16 {
        readI16(0x11B0 + 4 * Self.checkIndex(layer, SceneState.layers) + 2 * Self.checkIndex(index, SceneState.shakeTimePerEntry))
    }

    /// Sets shake_time[layer][index].
    public func setShakeTime(_ layer: Int, _ index: Int, _ value: Int16) {
        writeI16(0x11B0 + 4 * Self.checkIndex(layer, SceneState.layers) + 2 * Self.checkIndex(index, SceneState.shakeTimePerEntry), value)
    }

    /// +0x1250, 12 x i16 per entry x 40, shake_par[layer][index]: SQK2 SHK2 SSW2; committed to
    /// +0x182 / +0x18E.
    public func getShakePar(_ layer: Int, _ index: Int) -> Int16 {
        readI16(0x1250 + 24 * Self.checkIndex(layer, SceneState.layers) + 2 * Self.checkIndex(index, SceneState.shakeParPerEntry))
    }

    /// Sets shake_par[layer][index].
    public func setShakePar(_ layer: Int, _ index: Int, _ value: Int16) {
        writeI16(0x1250 + 24 * Self.checkIndex(layer, SceneState.layers) + 2 * Self.checkIndex(index, SceneState.shakeParPerEntry), value)
    }

    /// +0x1610, i16 x 40, stra[layer]: STRA; committed to +0x2C8.
    public func getStra(_ layer: Int) -> Int16 { readI16(0x1610 + 2 * Self.checkIndex(layer, SceneState.layers)) }

    /// Sets stra[layer].
    public func setStra(_ layer: Int, _ value: Int16) { writeI16(0x1610 + 2 * Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x1660, u8 x 40, stns[layer]: STNS; committed to +0x1D0.
    public func getStns(_ layer: Int) -> UInt8 { readU8(0x1660 + Self.checkIndex(layer, SceneState.layers)) }

    /// Sets stns[layer].
    public func setStns(_ layer: Int, _ value: UInt8) { writeU8(0x1660 + Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x1688, u8 x 40, stns_b[layer]: STNS; committed to +0x1D1.
    public func getStnsB(_ layer: Int) -> UInt8 { readU8(0x1688 + Self.checkIndex(layer, SceneState.layers)) }

    /// Sets stns_b[layer].
    public func setStnsB(_ layer: Int, _ value: UInt8) { writeU8(0x1688 + Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x16B0, 40 x 0x12 bytes, ext: entry layer. STCH STPV STEC; committed to +0x50 (off),
    /// +0x1F0 colour, +0x2A8.
    public func ext(_ layer: Int) -> ByteWindow { slice(0x16B0 + 18 * Self.checkIndex(layer, SceneState.layers), 0x12) }

    /// +0x1980 i16 pic_table_index: i16 index into the 12-byte table 0x873050 -> 0x493E0 at the
    /// commit (layer work); 0x68A70.
    public var picTableIndex: Int16 {
        get { readI16(0x1980) }
        set { writeI16(0x1980, newValue) }
    }

    /// +0x1982 i16 text_window_a: i16 copy of +0x1984 (kind-0 restore 0x7D860 / 0x7DBBE, 0x7E55A);
    /// _ZM 0x92840, _MSAD 0x92DE0; read by the HUD 0x53CF0.
    public var textWindowA: Int16 {
        get { readI16(0x1982) }
        set { writeI16(0x1982, newValue) }
    }

    /// +0x1984 i16 text_window_b: i16 = F931 when F931 >= 0 (kind-0 restore 0x7D736), 0x7E54A;
    /// read by _ZM / _MSAD / prefetch 0xA0740 [H: message-window style].
    public var textWindowB: Int16 {
        get { readI16(0x1984) }
        set { writeI16(0x1984, newValue) }
    }

    /// +0x1986 i16 commit_49620_a: i16 -> 0x49620 at the commit (layer work).
    public var commit49620A: Int16 {
        get { readI16(0x1986) }
        set { writeI16(0x1986, newValue) }
    }

    /// +0x1988 i16 commit_49620_b: i16 -> 0x49620 at the commit (layer work).
    public var commit49620B: Int16 {
        get { readI16(0x1988) }
        set { writeI16(0x1988, newValue) }
    }

    /// +0x198A i16 commit_495f0_a: i16 -> 0x495F0 at the commit (layer work).
    public var commit495F0A: Int16 {
        get { readI16(0x198A) }
        set { writeI16(0x198A, newValue) }
    }

    /// +0x198C i16 commit_495f0_b: i16 -> 0x495F0 at the commit.
    public var commit495F0B: Int16 {
        get { readI16(0x198C) }
        set { writeI16(0x198C, newValue) }
    }

    /// +0x198E i16 commit_495f0_c: i16 -> 0x495F0 at the commit.
    public var commit495F0C: Int16 {
        get { readI16(0x198E) }
        set { writeI16(0x198E, newValue) }
    }

    /// +0x1990 u64 reset_1990: u64, written only by the scene reset 0x789F0, never read.
    public var reset1990: UInt64 {
        get { readU64(0x1990) }
        set { writeU64(0x1990, newValue) }
    }

    /// +0x1998 u16 reset_1998: u16, written only by the scene reset 0x789F0, never read.
    public var reset1998: UInt16 {
        get { readU16(0x1998) }
        set { writeU16(0x1998, newValue) }
    }

    /// +0x199A i16 word_199a: i16 (dword store with +0x199C); scene reset, Slot_Load 0xA2EC3 = 0;
    /// read by the restore.
    public var word199A: Int16 {
        get { readI16(0x199A) }
        set { writeI16(0x199A, newValue) }
    }

    /// +0x199C i16 word_199c: i16 (see +0x199A).
    public var word199C: Int16 {
        get { readI16(0x199C) }
        set { writeI16(0x199C, newValue) }
    }

    /// +0x199E i16 word_199e: i16; scene reset, Slot_Load 0xA2ECD = 0; read by the restore.
    public var word199E: Int16 {
        get { readI16(0x199E) }
        set { writeI16(0x199E, newValue) }
    }

    /// +0x19A0 u8 byte_19a0: u8; no static writer (moved only by the block copies); read by the
    /// restore, 0x7E4E0.
    public var byte19A0: UInt8 {
        get { readU8(0x19A0) }
        set { writeU8(0x19A0, newValue) }
    }

    /// +0x19A1 u8 byte_19a1: u8 -> 0x426A0(byte, 0, 0) at the restore; reset; dead writers 0x7F510 / 0x7F680.
    public var byte19A1: UInt8 {
        get { readU8(0x19A1) }
        set { writeU8(0x19A1, newValue) }
    }

    /// +0x19A2 u8 effect_19a2: u8 screen effect (SNOW 0x81060, FLNT/FLOP/FLSP/FCLN/FCSP
    /// 0xB7720..0xB79C0) -> 0xA88B0(byte, 0) at the restore.
    public var effect19A2: UInt8 {
        get { readU8(0x19A2) }
        set { writeU8(0x19A2, newValue) }
    }

    /// +0x19A3 u8 f995_low: u8 = low byte of F995, written by every History_Push (0x7B2A2) before
    /// the copy.
    public var f995Low: UInt8 {
        get { readU8(0x19A3) }
        set { writeU8(0x19A3, newValue) }
    }

    /// +0x19A4 u8 byte_19a4: u8 -> 0x16541E4 at the restore; reset.
    public var byte19A4: UInt8 {
        get { readU8(0x19A4) }
        set { writeU8(0x19A4, newValue) }
    }

    /// +0x19A6 i16 f967_base: i16; F967 = this + 1 after a load (0x7E790) and the restore rule
    /// 0x7D513; reset.
    public var f967Base: Int16 {
        get { readI16(0x19A6) }
        set { writeI16(0x19A6, newValue) }
    }

    /// +0x19A8 u8 byte_19a8: u8; no static writer; read by 0x7E790 / 0x7EC30.
    public var byte19A8: UInt8 {
        get { readU8(0x19A8) }
        set { writeU8(0x19A8, newValue) }
    }

    /// +0x19A9 u8 byte_19a9: u8; no static writer; read by 0x7E790 / 0x7EC30.
    public var byte19A9: UInt8 {
        get { readU8(0x19A9) }
        set { writeU8(0x19A9, newValue) }
    }

    /// +0x19AA i8 byte_19aa: i8 -> 0x56CE0 at the commit (layer work); reset.
    public var byte19AA: Int8 {
        get { readI8(0x19AA) }
        set { writeI8(0x19AA, newValue) }
    }

    /// +0x19AB, u8 x 40, u19ab[layer]: copied by STCH src; committed to -.
    public func getU19AB(_ layer: Int) -> UInt8 { readU8(0x19AB + Self.checkIndex(layer, SceneState.layers)) }

    /// Sets u19ab[layer].
    public func setU19AB(_ layer: Int, _ value: UInt8) { writeU8(0x19AB + Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x19D3, u8 x 40, u19d3[layer]: copied by STCH src; committed to -.
    public func getU19D3(_ layer: Int) -> UInt8 { readU8(0x19D3 + Self.checkIndex(layer, SceneState.layers)) }

    /// Sets u19d3[layer].
    public func setU19D3(_ layer: Int, _ value: UInt8) { writeU8(0x19D3 + Self.checkIndex(layer, SceneState.layers), value) }

    /// +0x19FC i16 screen_effect: i16 screen-effect kind 0x1651ABC (SHAK 0x80180, SHAF 0x80AE0,
    /// 0x95130 helpers; SHAS sets 0 at 0x99817); restore: 1 -> 0x42DC0, 2 -> 0x43160, >= 3 ->
    /// 0x46270, else 0x433F0(-1).
    public var screenEffect: Int16 {
        get { readI16(0x19FC) }
        set { writeI16(0x19FC, newValue) }
    }

    /// +0x19FE i16 screen_effect_p0: i16 parameter of +0x19FC (same writers).
    public var screenEffectP0: Int16 {
        get { readI16(0x19FE) }
        set { writeI16(0x19FE, newValue) }
    }

    /// +0x1A00 i16 screen_effect_p1: i16 parameter of +0x19FC.
    public var screenEffectP1: Int16 {
        get { readI16(0x1A00) }
        set { writeI16(0x1A00, newValue) }
    }

    /// +0x1A02 i16 screen_effect_p2: i16 parameter of +0x19FC.
    public var screenEffectP2: Int16 {
        get { readI16(0x1A02) }
        set { writeI16(0x1A02, newValue) }
    }

    /// +0x1A04 i16 screen_effect_p3: i16 parameter of +0x19FC.
    public var screenEffectP3: Int16 {
        get { readI16(0x1A04) }
        set { writeI16(0x1A04, newValue) }
    }

    /// Motion entry +0x0, i16: motion id (+0; 0 = none).
    public func getMotionId(_ layer: Int) -> Int16 { readI16(0x0D00 + 24 * Self.checkIndex(layer, SceneState.layers) + 0x00) }

    /// Sets the Motion entry's MotionId.
    public func setMotionId(_ layer: Int, _ value: Int16) { writeI16(0x0D00 + 24 * Self.checkIndex(layer, SceneState.layers) + 0x00, value) }

    /// Motion entry +0x2, i16: speed divisor n of _STMA (+2).
    public func getMotionDivisor(_ layer: Int) -> Int16 { readI16(0x0D00 + 24 * Self.checkIndex(layer, SceneState.layers) + 0x02) }

    /// Sets the Motion entry's MotionDivisor.
    public func setMotionDivisor(_ layer: Int, _ value: Int16) { writeI16(0x0D00 + 24 * Self.checkIndex(layer, SceneState.layers) + 0x02, value) }

    /// Motion entry +0x8, i64: frame counter (+8; the scene copy holds the quantised count).
    public func getMotionFrames(_ layer: Int) -> Int64 { readI64(0x0D00 + 24 * Self.checkIndex(layer, SceneState.layers) + 0x08) }

    /// Sets the Motion entry's MotionFrames.
    public func setMotionFrames(_ layer: Int, _ value: Int64) { writeI64(0x0D00 + 24 * Self.checkIndex(layer, SceneState.layers) + 0x08, value) }

    /// Motion entry +0x10, u8: pause byte (+0x10).
    public func getMotionPause(_ layer: Int) -> UInt8 { readU8(0x0D00 + 24 * Self.checkIndex(layer, SceneState.layers) + 0x10) }

    /// Sets the Motion entry's MotionPause.
    public func setMotionPause(_ layer: Int, _ value: UInt8) { writeU8(0x0D00 + 24 * Self.checkIndex(layer, SceneState.layers) + 0x10, value) }

    /// Ext entry +0x2, i16: picture offset x = -anchor x (+2).
    public func getExtOffsetX(_ layer: Int) -> Int16 { readI16(0x16B0 + 18 * Self.checkIndex(layer, SceneState.layers) + 0x02) }

    /// Sets the Ext entry's ExtOffsetX.
    public func setExtOffsetX(_ layer: Int, _ value: Int16) { writeI16(0x16B0 + 18 * Self.checkIndex(layer, SceneState.layers) + 0x02, value) }

    /// Ext entry +0x4, i16: picture offset y = -anchor y (+4).
    public func getExtOffsetY(_ layer: Int) -> Int16 { readI16(0x16B0 + 18 * Self.checkIndex(layer, SceneState.layers) + 0x04) }

    /// Sets the Ext entry's ExtOffsetY.
    public func setExtOffsetY(_ layer: Int, _ value: Int16) { writeI16(0x16B0 + 18 * Self.checkIndex(layer, SceneState.layers) + 0x04, value) }

    /// Ext entry +0x6, u8: colour R of STEC mode 1 (+6; white after STCH / SCH2).
    public func getExtColourR(_ layer: Int) -> UInt8 { readU8(0x16B0 + 18 * Self.checkIndex(layer, SceneState.layers) + 0x06) }

    /// Sets the Ext entry's ExtColourR.
    public func setExtColourR(_ layer: Int, _ value: UInt8) { writeU8(0x16B0 + 18 * Self.checkIndex(layer, SceneState.layers) + 0x06, value) }

    /// Ext entry +0x7, u8: colour G (+7).
    public func getExtColourG(_ layer: Int) -> UInt8 { readU8(0x16B0 + 18 * Self.checkIndex(layer, SceneState.layers) + 0x07) }

    /// Sets the Ext entry's ExtColourG.
    public func setExtColourG(_ layer: Int, _ value: UInt8) { writeU8(0x16B0 + 18 * Self.checkIndex(layer, SceneState.layers) + 0x07, value) }

    /// Ext entry +0x8, u8: colour B (+8).
    public func getExtColourB(_ layer: Int) -> UInt8 { readU8(0x16B0 + 18 * Self.checkIndex(layer, SceneState.layers) + 0x08) }

    /// Sets the Ext entry's ExtColourB.
    public func setExtColourB(_ layer: Int, _ value: UInt8) { writeU8(0x16B0 + 18 * Self.checkIndex(layer, SceneState.layers) + 0x08, value) }
}
