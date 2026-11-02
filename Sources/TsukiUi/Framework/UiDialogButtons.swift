import Foundation
import TsukiEngine

/// Draws one dialog button cell the way the sheet's cell looks, translated where the sheet is not.
public enum UiDialogButtons {
    /// The width of a button cell on the sheet and on the screen.
    public static let cellWidth: Float = 216.0
    public static let CellWidth: Float = cellWidth

    /// The height of a button cell.
    public static let cellHeight: Float = 56.0
    public static let CellHeight: Float = cellHeight

    /// The row of the 1 px cursor underline in a cursor cell.
    public static let underlineRow: Float = 42.0
    public static let UnderlineRow: Float = underlineRow

    /// Where the translated word's line box starts in the cell.
    public static let letterTop: Float = 10.0
    public static let LetterTop: Float = letterTop

    /// The height of the sheet's letters.
    public static let letterHeight: Float = 28.0
    public static let LetterHeight: Float = letterHeight

    private static let white: (r: Int, g: Int, b: Int) = (255, 255, 255)
    private static let whiteGlow: (r: Int, g: Int, b: Int) = (192, 238, 254)
    private static let cyan: (r: Int, g: Int, b: Int) = (0, 255, 240)
    private static let cyanGlow: (r: Int, g: Int, b: Int) = (2, 221, 255)

    /// True when the UI language's sheet carries the words in that language.
    public static func sheetIsLocalized(_ language: Language) -> Bool {
        language != .ja
    }
    public static func SheetIsLocalized(_ language: Language) -> Bool {
        sheetIsLocalized(language)
    }

    /// The word drawn instead of the sheet's letters, or nil when the sheet is used.
    public static func label(_ language: Language, yes: Bool) -> String? {
        sheetIsLocalized(language) ? nil : PortText.get(yes ? .dialogYes : .dialogNo, language)
    }
    public static func Label(_ language: Language, _ yes: Bool) -> String? {
        label(language, yes: yes)
    }

    /// The source cell of a button on the sheet.
    public static func sourceCell(yes: Bool, selected: Bool) -> RectF {
        let cy: Float = yes ? 0.0 : 67.0
        return selected ? RectF(0, cy + 135.0, cellWidth, cellHeight) : RectF(224, cy, cellWidth, cellHeight)
    }
    public static func SourceCell(_ yes: Bool, _ selected: Bool) -> RectF {
        sourceCell(yes: yes, selected: selected)
    }

    /// Draws the button whose cell's top-left is (x, y) in canvas pixels.
    public static func draw(_ p: UiPainter, _ ctx: UiContext, yes: Bool, selected: Bool, x: Float, y: Float, alpha: Float = 1.0) {
        let src = sourceCell(yes: yes, selected: selected)
        guard let lbl = label(ctx.language, yes: yes) else {
            p.sprite(UiSheets.dialogButtons, src, RectF(x, y, cellWidth, cellHeight), alpha: alpha)
            return
        }

        if selected {
            let line = RectF(src.x, src.y + underlineRow, cellWidth, cellHeight - underlineRow)
            p.sprite(UiSheets.dialogButtons, line, RectF(x, y + underlineRow, cellWidth, cellHeight - underlineRow), alpha: alpha)
        }

        ctx.text.drawGlowLabel(
            p, lbl, labelStyle(ctx.language), x + (cellWidth / 2.0), y + letterTop,
            selected ? cyan : white, selected ? cyanGlow : whiteGlow, alpha, selected ? 0.014 : 0.02
        )
    }
    public static func Draw(_ p: UiPainter, _ ctx: UiContext, _ yes: Bool, _ selected: Bool, _ x: Float, _ y: Float, _ alpha: Float = 1.0) {
        draw(p, ctx, yes: yes, selected: selected, x: x, y: y, alpha: alpha)
    }

    /// The glyph scale of the translated word.
    public static let labelScale: Double = 0.54
    public static let LabelScale: Double = labelScale

    /// The glyph style of the translated word.
    public static func labelStyle(_ language: Language) -> TextStyle {
        var style = TextStyle.menu(labelScale)
        style.width = 600
        style.height = 100
        style.spacing = 0
        style.leading = 0
        return style
    }
    public static func LabelStyle(_ language: Language) -> TextStyle {
        labelStyle(language)
    }
}
