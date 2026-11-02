import Foundation
import TsukiCore

/// What the choice draw needs from the choice machine for one frame (system_flow.md 5.2, 5.3).
public struct ChoiceView: Sendable {
    /// Line pitch in canvas units.
    public static let linePitch: Double = 26.02

    /// 0 fade-in, 1 reveal, 2 select, 3 decided.
    public var phase: Int
    /// The cursor line (u16 0x17506A2), -1 none.
    public var cursor: Int
    /// The previous cursor line (0x17506A4), -1 none.
    public var previous: Int
    /// The choice alpha `a` (HUD alpha times 0x17506A8).
    public var alpha: Float
    /// The highlight `h` (0x17506B4), 0..1.
    public var highlight: Float
    /// The decide flash (0x17506AC), 1 to 0.
    public var flash: Float
    /// Left edge of the lines in canvas units (87, or 30 in English).
    public var x0: Double
    /// Top of the first line in canvas units.
    public var y0: Double
    /// Pixels per canvas unit in x (3).
    public var unitX: Double
    /// Pixels per canvas unit in y (the host's text scale; 1080 / 344.7 on the console).
    public var unitY: Double

    public init(phase: Int, cursor: Int, previous: Int, alpha: Float, highlight: Float, flash: Float, x0: Double, y0: Double, unitX: Double, unitY: Double) {
        self.phase = phase
        self.cursor = cursor
        self.previous = previous
        self.alpha = alpha
        self.highlight = highlight
        self.flash = flash
        self.x0 = x0
        self.y0 = y0
        self.unitX = unitX
        self.unitY = unitY
    }

    /// The top of line `k` (`y_k = y0 + 26.02 k`).
    public func lineY(_ k: Int) -> Double {
        y0 + (Self.linePitch * Double(k))
    }
}

/// One draw call of the choice screen as the PS4 function 0xA6E10 makes it (system_flow.md 5.3), in the units of its canvas (640 x 344.7): what
/// `tools/tsuki/misc_boot_title_choice_flow.choice_draw_list` lists. Recorded only when `GameHost.choiceTrace` is set (the tests).
public struct ChoiceDraw: Sendable {
    /// `"text"` (a block draw) or `"tex"` (a SELECT_PARTS picture).
    public var kind: String
    /// Text block id (0x14 + k, glow copies 0x64 + j / 0x6C + j) or texture slot (91 + SELECT_PARTS child).
    public var slot: Int
    /// Position x in canvas units (the centre for the ring, whose draw flag is 0x34).
    public var x: Double
    /// Position y in canvas units.
    public var y: Double
    /// The alpha of the draw.
    public var alpha: Double
    /// Texture draws: picture scale x in canvas units per texel (the engine's `SetScale`); 0 for text.
    public var scaleX: Double
    /// Texture draws: picture scale y; 0 for text.
    public var scaleY: Double
    /// Text draws: the draw flags (0x1020 | shadow bit); 0 for the glow copies and for pictures.
    public var flags: Int
    /// Text draws: the colour word the block was laid out with (0xFFFF, 0x77FF, 0xC7FF); 0 for pictures.
    public var colour: Int

    public init(kind: String, slot: Int, x: Double, y: Double, alpha: Double, scaleX: Double, scaleY: Double, flags: Int, colour: Int) {
        self.kind = kind
        self.slot = slot
        self.x = x
        self.y = y
        self.alpha = alpha
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.flags = flags
        self.colour = colour
    }
}

/// The decoration of the choice screen that the PS4 draws around the option texts (system_flow.md 5.3, VA 0xA6E10): the vignette that dims the scene and
/// the page text, the eight offset copies of the cursor line's text in cyan (the glow, cross-fading from the previous line), the underline and the lens
/// flare of the cursor line, and, once a line is decided, the ring, the blue bands and the lens flare of the flash. The sheet is SELECT_PARTS (children
/// 0..5 = textures 91..96), drawn 1 texel per pixel with the additive-alpha effect word 0xB (ps_add) except the vignette (word 0).
public final class ChoiceGlow {
    // the eight glow copies' offsets in canvas units (VA 0xA7209)
    private static let offsets: [(dx: Double, dy: Double)] = [
        (-0.9, 0), (0.9, 0), (0, -0.7), (0, 0.7),
        (-0.9, -0.7), (0.9, -0.7), (-0.9, 0.7), (0.9, 0.7)
    ]

    private static let addWord: Int16 = 0xB
    private static let selectedScaleY: Double = 0.31917 // the TexDraw scale of the SELECT_PARTS pieces: one texel per pixel in y
    private let sheetSize: (Int) -> (width: Int, height: Int)
    private var _pulse: Float = 1.0
    private var _pulseStep: Float = -0.0111

    /// Receives every decoration draw in the engine's own units (the tests compare it with the oracle's draw list); nil in play.
    public var trace: ((ChoiceDraw) -> Void)? = nil

    /// The flare pulse (0x17506B8), bouncing between 0.333 and 1.
    public var pulse: Float { _pulse }

    public init(sheetSize: @escaping (Int) -> (width: Int, height: Int)) {
        self.sheetSize = sheetSize
    }

    /// The glow colour word of the cursor line: cyan while selecting, pale after the decision (system_flow.md 5.3).
    public static func glowColour(_ phase: Int) -> Int {
        phase == 3 ? 0xC7FF : 0x77FF
    }

    /// A new choice: the pulse restarts.
    public func reset() {
        _pulse = 1.0
        _pulseStep = -0.0111
    }

    /// A cursor change sets the pulse to 1 and its step to -0.0111 (VA 0xA6885).
    public func onCursorChange() {
        reset()
    }

    /// Every frame of the choice mode: the pulse bounces between 0.333 and 1 at 0.0111 per frame (VA 0xA61BB).
    public func tick(_ frames: Int) {
        for _ in 0..<max(1, frames) {
            _pulse += _pulseStep
            if _pulse <= 0.333 {
                _pulse = 0.333
                _pulseStep = 0.0111
            } else if _pulse >= 1.0 {
                _pulse = 1.0
                _pulseStep = -0.0111
            }
        }
    }

    /// The vignette (texture 96, child 5) over the whole frame, before the lines: it dims the scene and the page text.
    public func drawVignette(_ list: DisplayList, view: ChoiceView) {
        let (w, h) = sheetSize(5)
        add(to: list, view: view, child: 5, x0: 0, y0: 0, x1: Double(w), y1: Double(h), alpha: view.alpha, word: 0, canvasUnitY: 1080.0 / 448.0)
    }

    /// What belongs to line `k` after its text: the eight glow copies when it is the cursor or the previous line, and the underline and
    /// the flare when it is the cursor.
    public func drawLine(
        _ list: DisplayList,
        view: ChoiceView,
        k: Int,
        glowText: (Int, Int) -> TextBlock?,
        drawText: (TextBlock, Double, Double, Double) -> Void
    ) {
        let y = view.lineY(k)
        if k == view.cursor || k == view.previous {
            let g = (k == view.previous ? 1.0 - view.highlight : view.highlight) * view.alpha * 192.0 / 255.0
            if g > 0.0, let block = glowText(k, Self.glowColour(view.phase)) {
                let baseBlock = k == view.previous ? 0x6C : 0x64
                for j in 0..<Self.offsets.count {
                    let (dx, dy) = Self.offsets[j]
                    trace?(ChoiceDraw(
                        kind: "text",
                        slot: baseBlock + j,
                        x: view.x0 + dx,
                        y: y + dy,
                        alpha: Double(g / 8.0),
                        scaleX: 0,
                        scaleY: 0,
                        flags: 0,
                        colour: Self.glowColour(view.phase)
                    ))
                    drawText(block, view.x0 + dx, y + dy, Double(g / 8.0))
                }
            }
        }

        if k != view.cursor {
            return
        }

        // the underline grows with the highlight; the flare pulses (both drawn even when h = 0)
        let (uw, uh) = sheetSize(2)
        let scaleX = ((0.9 * Double(view.highlight)) + 0.1) / 3.0
        let ux = (view.x0 - 16.3333) * view.unitX
        let uy = (y + 8.93667) * view.unitY
        add(to: list, view: view, child: 2, x0: ux, y0: uy, x1: ux + (Double(uw) * scaleX * view.unitX), y1: uy + (Double(uh) * Self.selectedScaleY * view.unitY), alpha: view.alpha, word: Int(Self.addWord))

        let (fw, fh) = sheetSize(4)
        let fx = (view.x0 - 153.333) * view.unitX
        let fy = (y - 23.6183) * view.unitY
        add(to: list, view: view, child: 4, x0: fx, y0: fy, x1: fx + (Double(fw) * view.unitX / 3.0), y1: fy + (Double(fh) * Self.selectedScaleY * view.unitY), alpha: view.alpha * _pulse, word: Int(Self.addWord))
    }

    /// After the lines of a decided choice: the ring that grows and turns, the blue bands and the lens flare.
    public func drawDecided(_ list: DisplayList, view: ChoiceView) {
        guard view.phase == 3, view.cursor >= 0 else {
            return
        }

        let s = sin(Double(view.flash) * (-Double.pi / 2.0)) + 1.0
        let scale = (1.4 * s) + 0.1
        let cx = 86.0 * view.unitX
        let cy = (view.y0 + 18.8308 + (ChoiceView.linePitch * Double(view.cursor))) * view.unitY
        let (rw, rh) = sheetSize(3)
        let hw = Double(rw) * scale / 3.0 * view.unitX / 2.0
        let hh = Double(rh) * scale * (344.7 / 1080.0) * view.unitY / 2.0
        let angle = Double(Int(s * 65535.0)) * (2.0 * Double.pi / 65536.0)
        let c = cos(angle), sn = sin(angle)
        let rgba = Self.pack(view.alpha)
        trace?(ChoiceDraw(kind: "tex", slot: 91 + 3, x: cx / view.unitX, y: cy / view.unitY, alpha: Double(view.alpha), scaleX: scale / 3.0, scaleY: scale * (344.7 / 1080.0), flags: 0, colour: 0))

        func corner(_ dx: Double, _ dy: Double, _ u: Float, _ t: Float) -> Vertex {
            Vertex(x: Float(cx + (dx * c) - (dy * sn)), y: Float(cy + (dx * sn) + (dy * c)), u: u, v: t, rgba: rgba)
        }

        list.add(DrawCommand(
            kind: .texturedQuad,
            texture: Self.sheet(3),
            v0: corner(-hw, -hh, 0, 0),
            v1: corner(hw, -hh, 1, 0),
            v2: corner(-hw, hh, 0, 1),
            v3: corner(hw, hh, 1, 1),
            effectWord: Self.addWord,
            blendState: 1
        ))

        let (bw, bh) = sheetSize(0)
        add(to: list, view: view, child: 0, x0: 0, y0: 0, x1: Double(bw) * view.unitX / 3.0, y1: Double(bh) * Self.selectedScaleY * view.unitY, alpha: view.alpha, word: Int(Self.addWord))

        let (lw, lh) = sheetSize(1)
        let lx = 5.0 * view.unitX
        let ly = (view.y0 - 290.761 + (ChoiceView.linePitch * Double(view.cursor))) * view.unitY
        add(to: list, view: view, child: 1, x0: lx, y0: ly, x1: lx + (Double(lw) * view.unitX / 3.0), y1: ly + (Double(lh) * Self.selectedScaleY * view.unitY), alpha: view.alpha, word: Int(Self.addWord))
    }

    private static func sheet(_ child: Int) -> TextureRef {
        TextureRef.uiTile(set: UiSet.selectParts.rawValue, language: Int(Language.ja.rawValue), child: child, tile: -1)
    }

    private static func pack(_ alpha: Float) -> UInt32 {
        let a = UInt8(clamping: Int(round(alpha * 255.0)))
        return 0x00FFFFFF | (UInt32(a) << 24)
    }

    private func add(
        to list: DisplayList,
        view: ChoiceView,
        child: Int,
        x0: Double,
        y0: Double,
        x1: Double,
        y1: Double,
        alpha: Float,
        word: Int,
        canvasUnitY: Double? = nil
    ) {
        if let trace = trace {
            let (tw, th) = sheetSize(child)
            let unitY = canvasUnitY ?? view.unitY
            trace(ChoiceDraw(
                kind: "tex",
                slot: 91 + child,
                x: x0 / view.unitX,
                y: y0 / unitY,
                alpha: Double(alpha),
                scaleX: (x1 - x0) / (Double(max(tw, 1)) * view.unitX),
                scaleY: (y1 - y0) / (Double(max(th, 1)) * unitY),
                flags: 0,
                colour: 0
            ))
        }

        let rgba = Self.pack(alpha)
        list.add(DrawCommand(
            kind: .texturedQuad,
            texture: Self.sheet(child),
            v0: Vertex(x: Float(x0), y: Float(y0), u: 0, v: 0, rgba: rgba),
            v1: Vertex(x: Float(x1), y: Float(y0), u: 1, v: 0, rgba: rgba),
            v2: Vertex(x: Float(x0), y: Float(y1), u: 0, v: 1, rgba: rgba),
            v3: Vertex(x: Float(x1), y: Float(y1), u: 1, v: 1, rgba: rgba),
            effectWord: Int16(truncatingIfNeeded: word),
            blendState: UInt8(truncatingIfNeeded: DrawEffectTables.blendStateOf(word))
        ))
    }
}
