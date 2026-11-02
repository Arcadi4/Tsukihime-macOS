import Foundation

/// Where the story's two-button prompts (`_SELS`, `_SELA`) put their pieces, in the 640 x 448 units of the PS4's HUD canvas (package K13). Every number is an
/// operand of the eboot's draw functions 0xA7CD0 (mode 2) / 0xA8250 (mode 3) and of the input functions 0xA7AA0 / 0xA7FD0, read with `tools/eboot/disasm.py`
/// (docs/status/knife/K13.md); knife's `sub_85900` has the same values.
public enum PromptLayout {
    /// The x of button 0 (No), the left one (widget 0xD5; float 0x2169E0).
    public static let noX: Float = 241.0

    /// The x of button 1 (Yes), the right one (widget 0xD6; float 0x2169E8).
    public static let yesX: Float = 327.0

    /// The y of both buttons' top edge (float 0x2169E4).
    public static let buttonY: Float = 238.51852

    /// The dialog window's centre x (float 0x2169C8; one unit right of the screen centre, as the eboot has it).
    public static let windowCenterX: Float = 321.0

    /// The centre y of the window and of the backdrop (float 0x2169BC).
    public static let centerY: Float = 224.0

    /// The message block's left edge (float 0x2169D8); the block is 474 units wide and centres its lines.
    public static let messageX: Float = 83.333336

    /// The message block's top is `centerY + messageDy * scale` (float 0x2169CC).
    public static let messageDy: Float = -42.31111

    /// The layout width of the message (474, the `Text_Layout` width argument 0x1DA).
    public static let messageWidth: Int = 474

    /// The layout height of the message (220, argument 0xDC).
    public static let messageHeight: Int = 220

    /// Glyph scale x of the message, times the pop scale (float 0x2169D0).
    public static let messageSx: Double = 0.37

    /// Glyph scale y of the message, times the pop scale (float 0x2169D4; 0.37 x 448 / 360).
    public static let messageSy: Double = 0.46044448

    /// The per-frame step of the fade in and out (floats 0x216884 / 0x216888 / 0x216890 / 0x216894).
    public static let fadeStep: Float = 0.1

    /// The window's pop: it is 1 + 0.05 (1 - alpha) while opening (phase 0) and 1 - 0.05 (1 - alpha) while closing (phase 3), else 1 (floats 0x216954 / 0x216958).
    public static let pop: Float = 0.05

    // the hit box of a button widget (record 0x8731F0 + 0x30 k: shorts -10, -10, 60, 45 at +0x0C), added to the widget's truncated position; the pointer test of
    // 0xD05B0 takes the first widget whose box holds the pointer, ends included

    /// Hit box left edge relative to the button's x.
    public static let hitX0: Int = -10

    /// Hit box top edge relative to the button's y.
    public static let hitY0: Int = -10

    /// Hit box right edge (inclusive) relative to the button's x.
    public static let hitX1: Int = 60

    /// Hit box bottom edge (inclusive) relative to the button's y.
    public static let hitY1: Int = 45

    /// The button (0 No, 1 Yes) whose hit box holds the pointer unit (`ux`, `uy`), or -1.
    public static func buttonAt(_ ux: Int, _ uy: Int) -> Int {
        let y = Int(buttonY)
        if uy < y + hitX0 || uy > y + hitY1 {
            return -1
        }

        if ux >= Int(noX) + hitX0 && ux <= Int(noX) + hitX1 {
            return 0
        }

        if ux >= Int(yesX) + hitX0 && ux <= Int(yesX) + hitX1 {
            return 1
        }

        return -1
    }
}
