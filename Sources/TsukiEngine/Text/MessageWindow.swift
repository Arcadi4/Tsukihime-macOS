import Foundation
import TsukiCore

/// Arguments the `_ZM` handler (VA 0x92380) and the HUD (VA 0x53CF0) pass for the ordinary ADV
/// message, and the text origin of its first message (docs/formats/textbox.md 5; tools/tsuki/textbox.py
/// `BoxParams`).
public struct BoxParams: Sendable, Equatable {
    /// Width argument (474; VA 0x538F0 turns it into 574 in English).
    public var width: Int
    /// Height limit (220).
    public var height: Int
    /// Extra advance per glyph.
    public var spacing: Int
    /// Extra space between lines (9).
    public var leading: Int
    /// Glyph scale x argument (0.74, times F31 / 24 when F31 > 0).
    public var sx: Double
    /// Glyph scale y argument.
    public var sy: Double
    /// First stack argument: the RGB565 colour word.
    public var color: Int
    /// Second stack argument: bit 20 = start in style 2 (bubble windows).
    public var flags: Int
    /// Text origin x in the 640 x 360 text space.
    public var x: Double
    /// Text origin y.
    public var y: Double
    /// F1105 (F1109 in English when > 0).
    public var window: Int

    public init(
        width: Int = 474,
        height: Int = 220,
        spacing: Int = 0,
        leading: Int = 9,
        sx: Double = 0.74,
        sy: Double = 0.74,
        color: Int = 0xFFFF,
        flags: Int = 0,
        x: Double = 87.0,
        y: Double = 49.0,
        window: Int = 0
    ) {
        self.width = width
        self.height = height
        self.spacing = spacing
        self.leading = leading
        self.sx = sx
        self.sy = sy
        self.color = color
        self.flags = flags
        self.x = x
        self.y = y
        self.window = window
    }

    /// The `TextLayout` arguments for a message block; `savedX` is the `@x` continue position
    /// (`MessageWindow.continueX` of the message before it on the page).
    public func toLayoutParams(block: Int = 4, savedX: Double = 0.0) -> LayoutParams {
        LayoutParams(
            width: width,
            height: height,
            spacing: spacing,
            leading: leading,
            color: color,
            flags: flags,
            sx: sx,
            sy: sy,
            block: block,
            window: window,
            savedX: savedX
        )
    }
}

/// Where a window picture is drawn (VA 0x540A5..0x54492).
public struct WindowDraw: Sendable, Equatable {
    /// F1105 (or F1109) value.
    public let index: Int
    /// Texture slot.
    public let slot: Int
    /// DISP_PARTS child that registration table VA 0x780C90 loads into the slot.
    public let dispChild: Int
    /// Top-left x on the 1920 x 1080 screen.
    public let xPx: Double
    /// Top-left y.
    public let yPx: Double
    /// Screen pixels per texel, x.
    public let scaleX: Double
    /// Screen pixels per texel, y.
    public let scaleY: Double
    /// Picture alpha.
    public let alpha: Double
    /// True for a speech-bubble picture (index 3..55).
    public let bubble: Bool

    public init(
        index: Int,
        slot: Int,
        dispChild: Int,
        xPx: Double,
        yPx: Double,
        scaleX: Double,
        scaleY: Double,
        alpha: Double,
        bubble: Bool
    ) {
        self.index = index
        self.slot = slot
        self.dispChild = dispChild
        self.xPx = xPx
        self.yPx = yPx
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.alpha = alpha
        self.bubble = bubble
    }
}

/// The outputs of the HUD's call of VA 0xCA690 (at VA 0x53FC4, docs/formats/textbox.md 7.1): the position after the last revealed glyph of
/// the current message in block units with the function's own x origin of 88, truncated to whole units, and whether the text is complete.
public struct ClickAnchor: Sendable, Equatable {
    /// `trunc(88 + dx + (x2 - x0) * sx + 3)` of the last revealed non-ruby glyph (the mirrored `@b` rule for those glyphs); 88 with no glyph.
    public let x: Int
    /// `trunc(y_line + dy)` of that glyph; 0 with no glyph.
    public let y: Int
    /// The last glyph record (ruby included) is revealed at alpha 1: `tail > ctr`, or `head - tail <= 0`.
    public let complete: Bool

    public init(x: Int, y: Int, complete: Bool) {
        self.x = x
        self.y = y
        self.complete = complete
    }
}

/// The ADV message window: parameters of the main text box, the window and bubble tables and how the
/// messages of one page are stacked (docs/formats/textbox.md 5, 8; tools/tsuki/textbox.py
/// `main_box_params`, `page_positions`, `window_for`, `bubble_text_origin`).
public enum MessageWindow {
    /// The x origin VA 0xCA690 lays its lines out from (float32 at VA 0x2D3048 and the eight copies at 0x2D3460).
    public static let anchorOriginX: Float = 88.0

    /// VA 0xCA690 as the HUD calls it (`block, 0x30, &x, &y, head, tail` at VA 0x53FC4): the line origins of `BlockDraw.lineOffsets`
    /// with x = 88 and y = 0 (the draw flags OR-ed with the block's), then one pass over the glyph records in order.
    public static func clickIconAnchor(
        _ block: TextBlock,
        head: Double,
        tail: Double,
        lang: Language,
        drawFlags: Int = 0x30
    ) -> ClickAnchor {
        var x = anchorOriginX
        var y: Float = 0
        var alpha: Float = 0
        if block.n > 0 && !block.records.isEmpty {
            let (xs, ys, _) = BlockDraw.lineOffsets(block, anchorOriginX, 0, drawFlags)
            let h = Float(head)
            let t = Float(tail)
            let span = h - t
            for r in block.records {
                if r.index == 0 && r.flags == 0 {
                    continue
                }

                let ctr = Float(r.ctr)
                if ctr > h {
                    alpha = 0
                    continue
                }

                alpha = (t > ctr || !(0 < span)) ? 1.0 : (h - ctr) / span
                if (r.flags & 2) != 0 {
                    continue
                }

                if xs.isEmpty {
                    continue
                }
                let line = min(max(r.line, 0), max(0, xs.count - 1))

                let w = Float(r.x2 - r.x)
                if (r.flags & 0x10000) != 0 {
                    let wq = (w == 0x43 && r.tex == 0x5E) ? (w - 5.0) : w
                    var gx = BlockDraw.mirrorOrigin(lang) - r.dx
                    gx -= wq * r.sx
                    gx += xs[line]
                    x = gx - 16.0
                } else {
                    let after = r.dx + xs[line]
                    let wsx = w * r.sx
                    x = (wsx + after) + 3.0
                }

                y = r.dy + ys[line]
            }
        }

        return ClickAnchor(x: Int(x), y: Int(y), complete: alpha == 1.0)
    }

    // Window table (VA 0x2006C0, 56 x {i32 slot, f32 x, f32 y} in a 1280 x 720 space).
    private static let windowTable: [(slot: Int, x: Int, y: Int)] = [
        (22, 0, 0), (23, 0, 0), (24, 0, 0), (25, 525, 414), (26, 525, 414), (27, 328, 393),
        (28, 328, 393), (29, 90, 388), (30, 90, 388), (31, 525, 44), (32, 525, 44), (33, 328, 34),
        (34, 328, 34), (35, 90, 13), (36, 90, 13), (37, 94, 414), (38, 94, 414), (39, 79, 393),
        (40, 79, 393), (41, 63, 388), (42, 63, 388), (43, 94, 44), (44, 94, 44), (45, 79, 34),
        (46, 79, 34), (47, 63, 13), (48, 63, 13), (49, 338, 229), (50, 338, 229), (51, 196, 210),
        (52, 196, 210), (53, 71, 198), (54, 71, 198), (27, 318, 393), (27, 318, 393), (29, 70, 388),
        (29, 90, 378), (29, 250, 378), (30, 300, 388), (33, 268, 34), (33, 98, 34), (34, 198, 34),
        (35, -5, 13), (35, 90, 13), (35, 105, 23), (36, 90, 13), (39, -101, 393), (41, 43, 388),
        (41, 63, 388), (45, 29, 34), (47, -47, 13), (47, -17, 13), (48, 18, 13), (53, 21, 198),
        (53, 61, 198), (54, 11, 198),
    ]

    // Text anchor offsets (VA 0x200960, 56 x {f32 dx, f32 dy}).
    private static let textOffsets: [(dx: Double, dy: Double)] = [
        (0, 0), (0, 0), (0, 0), (97, 62.67), (97, 62.67), (99, 96), (99, 96), (99, 119.34),
        (99, 119.34), (97, 66.33), (97, 66.33), (99, 82.66), (99, 82.66), (99, 89), (99, 89),
        (78, 62.67), (78, 62.67), (89, 96), (89, 96), (112, 119.34), (112, 119.34), (78, 66.33),
        (78, 66.33), (89, 82.66), (89, 82.66), (112, 89), (112, 89), (97, 58.33), (97, 58.33),
        (99, 56), (99, 56), (99, 80.33), (99, 80.33), (69, 96), (79, 88), (80, 119.34), (99, 109.34),
        (90, 119.34), (99, 110), (64, 82.66), (60, 82.66), (85, 82.66), (45, 89), (65, 89),
        (95, 65), (99, 69), (85, 96), (98, 119.34), (103, 104), (89, 82.66), (103, 65), (93, 89),
        (103, 89), (70, 80.33), (82, 55), (70, 80.33),
    ]

    // Image size in the 640 x 448 window canvas for indices 33..55 (VA 0x200BB0 / 0x200C0C). Entries 2, 4 and 21
    // carry the exact float32 values of the eboot (the oracle's constants were corrected in this package).
    private static let windowSizes: [(w: Double, h: Double)] = [
        (716.8, 448.0), (716.8, 488.32), (684.800048828125, 448.0), (640.0, 488.32), (684.800048828125, 448.0),
        (640.0, 448.0), (710.4, 448.0), (896.0, 448.0), (729.6, 448.0), (729.6, 448.0),
        (646.4, 448.0), (640.0, 448.0), (640.0, 448.0), (646.4, 448.0), (704.0, 448.0),
        (640.0, 448.0), (832.0, 448.0), (716.8, 448.0), (716.8, 448.0), (710.4, 448.0),
        (710.4, 448.0), (678.3999633789062, 448.0), (710.4, 448.0),
    ]

    // F1106 -> VA 0x2005B0 and F1107 -> VA 0x200620.
    private static let xOffsets: [Double] = [
        0.0, 100.0, 120.0, 150.0, 20.0, 200.0, 250.0, 30.0, 40.0, 50.0, 500.0, 60.0, 70.0, 80.0,
        -100.0, -120.0, -150.0, -200.0, -250.0, -30.0, -300.0, -40.0, -50.0, -60.0, -70.0, -80.0, 400.0,
    ]

    private static let yOffsets: [Double] = [
        0.0, 10.0, 100.0, 15.0, 150.0, 20.0, 200.0, 220.0, 230.0, 240.0, 25.0, 250.0, 270.0,
        30.0, 300.0, 35.0, 50.0, 65.0, -10.0, -100.0, -15.0, -150.0, -170.0, -180.0, -190.0,
        -20.0, -200.0, -210.0, -220.0, -230.0, -30.0, -300.0, -40.0, -45.0, -50.0, -55.0, -60.0,
    ]

    /// Number of window table entries (F1105 values 0..55).
    public static var windowCount: Int { windowTable.count }

    /// Texture slot and 1280 x 720 position of a window index (VA 0x2006C0).
    public static func windowEntry(_ index: Int) -> (slot: Int, x: Int, y: Int) {
        windowTable[index]
    }

    /// Arguments of the `_ZM` layout call (VA 0x9280B) and the HUD origin of the first message.
    /// `window` = F1105 (F1109 overrides it in English when > 0); 0..2 = the ordinary
    /// full-screen page, 3..55 = a speech bubble (style 2 via flag bit 20).
    public static func mainBoxParams(
        _ lang: Language,
        window: Int = 0,
        read: Bool = false,
        readColorMode: Int = 0,
        f31: Int = 0,
        f32: Int = 0
    ) -> BoxParams {
        let normal = window < 3
        let sx = f31 <= 0 ? 0.74 : Double(Float(f31) / 24.0 * Float(0.74))
        let sy = f32 <= 0 ? 0.74 : Double(Float(f32) / 24.0 * Float(0.74))
        var color = 0xFFFF
        if readColorMode == 1 && read {
            color = normal ? 0xDC6D : 0xFFFF
        }

        let flags = normal ? 0 : (1 << 20)
        var (x, y) = lang == .en ? (30.0, 35.0) : (87.0, 49.0)
        if !normal {
            (x, y) = bubbleTextOrigin(window)
        }

        return BoxParams(
            width: 474,
            height: 220,
            spacing: 0,
            leading: 9,
            sx: sx,
            sy: sy,
            color: color,
            flags: flags,
            x: x,
            y: y,
            window: window
        )
    }

    /// DISP_PARTS child that registration table VA 0x780C90 loads into texture `slot`.
    public static func dispChildForSlot(_ slot: Int) throws -> Int {
        if slot >= 22 && slot <= 24 {
            return 11 + (slot - 22)
        }
        if slot >= 25 && slot <= 55 {
            return slot - 3
        }
        throw TsukiError.bounds("slot \(slot) is not a message-window slot")
    }

    /// The window picture drawn by the HUD (VA 0x540A5..0x54492; F822 == 1, F1104 == 0): index 0..2 is the
    /// full-screen 1920 x 1080 overlay with alpha opacity / 255 * fade, index 3..55 a speech bubble with alpha
    /// 0.784314 * fade. Nil for an index past 55.
    public static func windowFor(
        _ index: Int,
        opacity: Int = 255,
        fade: Double = 1.0,
        xoffIdx: Int = 0,
        yoffIdx: Int = 0
    ) -> WindowDraw? {
        if index < 0 || index > 0x37 {
            return nil
        }

        let (slot, tx, ty) = windowTable[index]
        let xo = (xoffIdx >= 0 && xoffIdx <= 0x1A) ? xOffsets[xoffIdx] : 0.0
        let yo = (yoffIdx >= 0 && yoffIdx <= 0x24) ? yOffsets[yoffIdx] : 0.0
        let bubble = index >= 3
        let (cw, ch) = (index >= 0x21 && index <= 0x37) ? windowSizes[index - 0x21] : (640.0, 448.0)
        let xCanvas = (Double(tx) + xo) * 640.0 / 1280.0
        let yCanvas = (Double(ty) + yo) * 448.0 / 720.0
        let a = (bubble ? 0.784314 : Double(opacity) / 255.0) * fade
        guard let child = try? dispChildForSlot(slot) else {
            return nil
        }
        return WindowDraw(
            index: index,
            slot: slot,
            dispChild: child,
            xPx: xCanvas * 3.0,
            yPx: yCanvas * 1080.0 / 448.0,
            scaleX: cw / 640.0,
            scaleY: ch / 448.0,
            alpha: a,
            bubble: bubble
        )
    }

    /// Text origin of speech bubble `index` in the 640 x 360 text space (VA 0x546CF..0x558B8).
    public static func bubbleTextOrigin(_ index: Int, xoffIdx: Int = 0, yoffIdx: Int = 0) -> (x: Double, y: Double) {
        let (_, tx, ty) = windowTable[index]
        let (dx, dy) = textOffsets[index]
        let xo = (xoffIdx >= 0 && xoffIdx <= 0x1A) ? xOffsets[xoffIdx] : 0.0
        let yo = (yoffIdx >= 0 && yoffIdx <= 0x24) ? yOffsets[yoffIdx] * 0.9578 : 0.0
        let x = Double(Float((Double(tx) + dx + xo) * 640.0 / 1280.0))
        let y = Double(Float((Double(ty) + dy + yo) * 360.0 / 720.0))
        return (x, y)
    }

    /// The width the HUD adds to the end x of a message to get the position an `@x` message continues at (float32 at VA 0x1A713C and 0x20B25C: one full-width glyph advance).
    public static let continueGap: Float = 16.52666664123535

    /// The position the next message of the page continues at after `block`, for its `@x` (global VA 0x178BE20): the HUD's history loop (VA 0x55A02..0x55A3F) and
    /// the `_ZM` handler through 0x7C340 (VA 0x7C66C..0x7C683) call 0xCAD10, whose first output is the x of the last used glyph record (left-aligned text: the record's x in
    /// the block), and set the global to `16.5267 + x`. The first message of a page leaves it at 0 (the HUD clears it at the start of every frame, VA 0x53D32).
    public static func continueX(_ block: TextBlock) -> Float {
        var x: Float = 0
        for r in block.records {
            if r.index == 0 && r.flags == 0 {
                continue
            }
            x = r.dx
        }
        return continueGap + x
    }

    /// Second output of VA 0xCAD10 as the HUD uses it: `int(y of the last line in the block)`.
    public static func lastLineOffset(_ block: TextBlock) -> Int {
        if block.nLines <= 1 {
            return 0
        }
        var acc: Float = 0
        let leading = Float(block.leading)
        for i in 0..<(block.nLines - 1) {
            acc += leading + block.lineHeight[i]
        }
        return Int(acc)
    }

    /// The y offset of the last line the block draw has revealed at `head` (the second output of the HUD's 0xCA690 call at VA
    /// 0x53FC4): like `lastLineOffset`, but only up to the line of the last glyph whose counter is not above the head.
    public static func revealedLastLineOffset(_ block: TextBlock, head: Double) -> Int {
        var line = 0
        let h = Float(head)
        for r in block.records {
            if (r.flags & 1) != 0 && Float(r.ctr) <= h {
                line = max(line, r.line)
            }
        }
        line = min(line, block.nLines - 1)
        var acc: Float = 0
        let leading = Float(block.leading)
        for i in 0..<line {
            acc += leading + block.lineHeight[i]
        }
        return Int(acc)
    }

    /// Origins of the messages of one full-screen page (HUD VA 0x54733..0x54C2F, 0x558BD..0x55A6B). Message j
    /// (0-based) is drawn at `y_j = y0 + sum_{i<j}(last_line_offset_i + 12 * s_i + 14) + sum_{i<=j} C_i * (12 * s_i + 14)`,
    /// where C_i = `blankBefore[i]` (script variable C847 as seen by message i; values at or above
    /// 0x21 mean C - 64, clamped to y >= 49.82 / 35.41) and s_i = `scaleY[i]` (C836 / 24, default 1).
    public static func pagePositions(
        _ blocks: [TextBlock],
        _ lang: Language,
        blankBefore: [Int]? = nil,
        scaleY: [Double]? = nil,
        origin: (x: Double, y: Double)? = nil
    ) -> [(x: Double, y: Double)] {
        let (x0, y0) = origin ?? (lang == .en ? (30.0, 35.0) : (87.0, 49.0))
        var result = [(x: Double, y: Double)]()
        result.reserveCapacity(blocks.count)
        var y = Float(y0)
        for j in 0..<blocks.count {
            let s = Float((scaleY != nil && j < scaleY!.count) ? scaleY![j] : 1.0)
            let step = s * 12.0 + 14.0
            let c = (blankBefore != nil && j < blankBefore!.count) ? blankBefore![j] : 0
            if c > 0 {
                if c >= 0x21 {
                    y = Float(c - 64) * step + y
                    let floor: Float = lang == .en ? 35.411766 : 49.823528
                    y = y >= floor ? y : floor
                } else {
                    y = Float(c) * step + y
                }
            }

            result.append((x0, Double(y)))
            y = Float(lastLineOffset(blocks[j])) + s * 12.0 + 14.0 + y
        }

        return result
    }

    /// Layout parameters for the speaker nameplate (VA 0x926B1).
    public static func namePlateParams(window: Int = 0) -> LayoutParams {
        LayoutParams(
            width: 150,
            height: 20,
            spacing: 2,
            leading: 0,
            color: 0xF6FD,
            flags: window < 3 ? 0 : (1 << 20),
            sx: 0.5,
            sy: 0.5,
            block: 14,
            window: window
        )
    }

    /// How far the current message moves down for the nameplate: the plate's last-line offset plus 14 (VA 0x54880).
    public static func namePlateShift(_ block: TextBlock) -> Double {
        Double(lastLineOffset(block) + 14)
    }
}
