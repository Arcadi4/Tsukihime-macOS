import Foundation
import TsukiEngine

/// What a click on a word of the button guide line does (package K12).
public enum GuideAction: Sendable {
    /// Nothing: the click is taken by the guide line (Move Cursor, Scroll).
    case none
    /// The Back word: cancel.
    case back
    /// The Confirm word: decide on the item under the cursor.
    case confirm
    /// The Delete Data word of the save list.
    case deleteData
    /// A word with the shoulder buttons: the left half of it is L1, the right half R1.
    case shoulders

    public static let None = GuideAction.none
    public static let Back = GuideAction.back
    public static let Confirm = GuideAction.confirm
    public static let DeleteData = GuideAction.deleteData
    public static let Shoulders = GuideAction.shoulders
}

/// A word of a guide line and its icons as the pointer can hit them: the word, what it does, where it is.
public struct GuideHit: Equatable, Sendable {
    public var word: Int
    public var action: GuideAction
    public var rect: RectF

    public var Word: Int { word }
    public var Action: GuideAction { action }
    public var Rect: RectF { rect }

    public init(word: Int, action: GuideAction, rect: RectF) {
        self.word = word
        self.action = action
        self.rect = rect
    }

    public init(_ word: Int, _ action: GuideAction, _ rect: RectF) {
        self.word = word
        self.action = action
        self.rect = rect
    }
}

/// Widgets the screens share: the button guide line, the scroll bar, the dialog window, digit strings.
public enum UiWidgets {
    private static let guideSeq: [[(kind: UInt8, cell: UInt8)]] = [
        [(1, 0), (0, 10), (1, 1), (0, 7), (1, 2), (0, 0), (1, 26), (0, 11)],
        [(1, 0), (0, 10), (1, 1), (0, 7), (1, 12), (0, 0), (1, 13), (0, 15), (1, 26), (0, 11)],
        [(1, 0), (0, 10), (1, 1), (0, 7), (1, 12), (0, 0), (1, 13), (0, 15), (1, 26), (0, 11)],
        [(1, 0), (0, 10), (1, 11), (0, 7), (1, 2), (0, 0)],
        [(1, 0), (0, 10), (1, 1), (0, 7), (1, 2), (0, 0)],
        [(1, 0), (0, 10), (1, 1), (0, 7), (1, 2), (0, 0)],
        [(1, 0), (0, 10), (1, 1), (0, 7), (1, 21), (0, 8), (1, 22), (0, 9), (1, 13), (0, 17), (0, 16), (1, 2), (0, 0), (1, 26), (0, 11)],
        [(1, 0), (0, 10), (1, 1), (0, 7), (1, 13), (0, 14), (0, 13), (1, 2), (0, 0), (1, 26), (0, 11)],
        [(1, 0), (0, 10), (1, 1), (0, 7), (1, 13), (0, 14), (0, 13), (1, 2)],
        [(1, 0), (0, 10), (1, 23), (0, 15), (1, 25), (0, 11), (1, 24), (0, 12)],
        [(1, 0), (0, 10), (1, 1), (0, 7), (1, 2), (0, 0)],
        [(1, 0), (0, 10), (1, 1), (0, 7), (1, 18), (0, 9), (1, 2), (0, 0), (1, 26), (0, 11)],
        // 12: story yes/no prompt
        [(1, 1), (0, 7), (1, 2), (0, 0)],
    ]

    /// The guide of the story's yes / no prompts: Confirm and Move Cursor.
    public static let guidePrompt = 12
    public static let GuidePrompt = guidePrompt

    /// The guide used by the save and load list.
    public static let guideList = 0
    public static let GuideList = guideList

    /// The guide of the config pages.
    public static let guideConfig = 2
    public static let GuideConfig = guideConfig

    /// The guide of the backlog.
    public static let guideBacklog = 3
    public static let GuideBacklog = guideBacklog

    /// The guide of the save list: adds the north button, Delete Data.
    public static let guideSaveList = 11
    public static let GuideSaveList = guideSaveList

    /// Draws the button guide line.
    public static func guide(_ p: UiPainter, _ guideIndex: Int, dy: Float = 0.0, alpha: Float = 1.0, decideIsCross: Bool = false) {
        guard guideIndex >= 0 && guideIndex < guideSeq.count else {
            return
        }

        p.withAlpha(alpha) {
            let k = UiMetrics.unitY
            p.fill(RectF(0, (424.36 + dy) * k, UiMetrics.width, (449.0 - 424.36) * k), r: 0.0039, g: 0.2353, b: 0.3961, a: 0.5)
            let assets = p.assets
            let icons = assets.tables.guideIconCells
            let words = assets.tables.guideWordCells(assets.language)
            let style = p.promptStyle
            let seq = guideSeq[guideIndex]
            var x: Float = 55.0
            var word = -1
            var groupX = x
            var groupWord = -1
            var shoulders = false
            let barTop = (424.36 + dy) * k

            func flush(_ end: Float) {
                guard groupWord >= 0 && alpha >= 0.5 else {
                    return
                }
                let action: GuideAction
                if shoulders {
                    action = .shoulders
                } else {
                    switch groupWord {
                    case 0: action = .back
                    case 1, 11: action = .confirm
                    case 18: action = .deleteData
                    default: action = .none
                    }
                }
                p.addGuideHit(GuideHit(word: groupWord, action: action, rect: RectF(groupX - 6.0, barTop, end - groupX + 6.0, UiMetrics.height - barTop)))
            }

            var i = 0
            while i < seq.count {
                let (kind, cell) = seq[i]
                if kind == 1 {
                    flush(x)
                    groupWord = Int(cell)
                    groupX = x
                    shoulders = false
                } else if cell >= 13 && cell <= 17 {
                    shoulders = true
                }

                let c: SheetCell
                let sheet: UiSheet
                let bottom: Float
                let pad: Float

                if kind == 0 {
                    if Int(cell) >= icons.count {
                        i += 1
                        continue
                    }

                    if style != .playStation {
                        let next = (i + 1 < seq.count && seq[i + 1].kind == 0) ? Int(seq[i + 1].cell) : -1
                        var use = Int(cell)
                        if (cell == 14 && next == 13) || (cell == 17 && next == 16) {
                            use = 15
                            i += 1
                        }

                        let items = (style == .keyboard) ? PromptBindings.keyboard(use, word, menu: guideIndex != guidePrompt) : PromptBindings.xbox(use)
                        if !items.isEmpty {
                            x += UiPrompts.draw(p, items, x, ((445.0 + dy) * k) - 2.0, 1.0) + 10.0
                        }
                        i += 1
                        continue
                    }

                    let cellIdx = Int(cell)
                    let iconIndex: Int
                    if decideIsCross && (cellIdx == 7 || cellIdx == 10) {
                        iconIndex = 17 - cellIdx
                    } else {
                        iconIndex = cellIdx
                    }
                    c = icons[iconIndex]
                    sheet = UiSheets.guideIcons
                    bottom = 445.0
                    pad = 6.0
                } else {
                    let cellIdx = Int(cell)
                    if cellIdx >= words.count {
                        i += 1
                        continue
                    }
                    word = cellIdx
                    c = words[cellIdx]
                    sheet = UiSheets.guideWords
                    bottom = 444.0
                    pad = 4.0
                }

                let src = RectF.fromCorners(Float(c.x0), Float(c.y0), Float(c.x1), Float(c.y1))
                p.sprite(sheet, src, RectF(x, ((bottom + dy) * k) - src.h, src.w, src.h))
                x += src.w + pad + 4.0
                i += 1
            }

            flush(x)
        }
    }
    public static func guide(_ p: UiPainter, _ guideIndex: Int, _ dy: Float, _ alpha: Float, decideIsCross: Bool = false) {
        guide(p, guideIndex, dy: dy, alpha: alpha, decideIsCross: decideIsCross)
    }
    public static func Guide(_ p: UiPainter, _ guideIndex: Int, _ dy: Float = 0.0, _ alpha: Float = 1.0, _ decideIsCross: Bool = false) {
        guide(p, guideIndex, dy: dy, alpha: alpha, decideIsCross: decideIsCross)
    }
    public static func scrollBar(_ p: UiPainter, fraction: Float, travel: Float = 608.0, alpha: Float = 1.0, bar: UiScrollBar? = nil) {
        guard alpha > 0 else { return }
        p.withAlpha(alpha) {
            let y = UiScrollBar.thumbTop(fraction, travel: travel)
            let dst = RectF(1839, y, 32, 288)
            p.sprite(UiSheets.scrollSlider, RectF(48, 24, 32, 288), dst)
            guard let b = bar else { return }

            if b.pressed {
                p.sprite(UiSheets.scrollSlider, RectF(128, 24, 32, 288), dst)
            } else if b.hover {
                p.sprite(UiSheets.scrollSlider, RectF(128, 24, 32, 288), dst, alpha: 0.5)
            }
        }
    }
    public static func scrollBar(_ p: UiPainter, _ fraction: Float, _ travel: Float = 608.0, _ alpha: Float = 1.0, _ bar: UiScrollBar? = nil) {
        scrollBar(p, fraction: fraction, travel: travel, alpha: alpha, bar: bar)
    }
    public static func ScrollBar(_ p: UiPainter, _ fraction: Float, _ travel: Float = 608.0, _ alpha: Float = 1.0, _ bar: UiScrollBar? = nil) {
        scrollBar(p, fraction: fraction, travel: travel, alpha: alpha, bar: bar)
    }

    /// The dialog window centred on the screen and scaled by `scale` about the centre.
    public static func dialogWindow(_ p: UiPainter, alpha: Float, scale: Float) {
        let w = 824.0 * scale
        let h = 416.0 * scale
        p.sprite(UiSheets.dialogWindow, RectF(0, 0, 824, 416), RectF((UiMetrics.width - w) / 2.0, (UiMetrics.height - h) / 2.0, w, h), alpha: alpha)
    }
    public static func DialogWindow(_ p: UiPainter, _ alpha: Float, _ scale: Float) {
        dialogWindow(p, alpha: alpha, scale: scale)
    }

    /// Draws a number with its last digit's left edge at `x`, digits 24 px apart going left.
    public static func number(_ p: UiPainter, digits: UiSheet, n: Int, x: Float, y: Float, cell0: Float = 2.0, pitch: Float = 32.0, cellY: Float = 0.0, step: Float = 24.0) {
        var num = max(n, 0)
        var curX = x
        repeat {
            let d = num % 10
            p.sprite(digits, RectF(cell0 + (pitch * Float(d)), cellY, 24, 32), RectF(curX, y, 24, 32))
            num /= 10
            curX -= step
        } while num > 0
    }
    public static func number(_ p: UiPainter, _ digits: UiSheet, _ n: Int, _ x: Float, _ y: Float, cell0: Float = 2.0, pitch: Float = 32.0, cellY: Float = 0.0, step: Float = 24.0) {
        number(p, digits: digits, n: n, x: x, y: y, cell0: cell0, pitch: pitch, cellY: cellY, step: step)
    }
    public static func Number(_ p: UiPainter, _ digits: UiSheet, _ n: Int, _ x: Float, _ y: Float, _ cell0: Float = 2.0, _ pitch: Float = 32.0, _ cellY: Float = 0.0, _ step: Float = 24.0) {
        number(p, digits: digits, n: n, x: x, y: y, cell0: cell0, pitch: pitch, cellY: cellY, step: step)
    }
}
