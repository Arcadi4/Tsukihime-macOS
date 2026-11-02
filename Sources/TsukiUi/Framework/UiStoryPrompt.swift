import Foundation
import TsukiEngine

/// Where the story's two-button prompts (`_SELS`, `_SELA`) put their pieces, in the 640 x 448 units of the PS4's HUD canvas.
public enum PromptLayout {
    public static let noX: Float = 241.0
    public static let yesX: Float = 327.0
    public static let buttonY: Float = 238.51852
    public static let windowCenterX: Float = 321.0
    public static let centerY: Float = 224.0
    public static let messageX: Float = 83.333336
    public static let messageDy: Float = -42.31111
    public static let messageWidth: Int = 474
    public static let messageHeight: Int = 220
    public static let messageSx: Double = 0.37
    public static let messageSy: Double = 0.46044448
    public static let fadeStep: Float = 0.1
    public static let pop: Float = 0.05
    public static let hitX0: Int = -10
    public static let hitY0: Int = -10
    public static let hitX1: Int = 60
    public static let hitY1: Int = 45

    public static let NoX = noX
    public static let YesX = yesX
    public static let ButtonY = buttonY
    public static let WindowCenterX = windowCenterX
    public static let CenterY = centerY
    public static let MessageX = messageX
    public static let MessageDy = messageDy
    public static let MessageWidth = messageWidth
    public static let MessageHeight = messageHeight
    public static let MessageSx = messageSx
    public static let MessageSy = messageSy
    public static let FadeStep = fadeStep
    public static let Pop = pop
    public static let HitX0 = hitX0
    public static let HitY0 = hitY0
    public static let HitX1 = hitX1
    public static let HitY1 = hitY1

    public static func buttonAt(_ ux: Int, _ uy: Int) -> Int {
        let y = Int(buttonY)
        if uy < y + hitY0 || uy > y + hitY1 {
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
    public static func ButtonAt(_ ux: Int, _ uy: Int) -> Int { buttonAt(ux, uy) }
}

/// The story's two-button prompt as the game host runs it (package K13).
public struct UiStoryPrompt: Sendable {
    public var messageId: Int
    public var cursor: Int
    public var alpha: Float
    public var scale: Float

    public var MessageId: Int { messageId }
    public var Cursor: Int { cursor }
    public var Alpha: Float { alpha }
    public var Scale: Float { scale }

    public init(messageId: Int, cursor: Int, alpha: Float, scale: Float = 1.0) {
        self.messageId = messageId
        self.cursor = cursor
        self.alpha = alpha
        self.scale = scale
    }
}

/// Draws `UiStoryPrompt` the way the eboot does.
public enum UiStoryPromptView {
    public static let guide: Int = UiWidgets.guidePrompt
    public static let Guide: Int = guide

    public static func draw(_ p: UiPainter, _ ctx: UiContext, _ prompt: UiStoryPrompt) {
        let a = min(max(prompt.alpha, 0.0), 1.0)
        if a <= 0.0 {
            return
        }

        let s = prompt.scale
        p.sprite(UiSheets.dialogBackdrop, UiMetrics.screen, alpha: a)
        let w = 824.0 * s
        let h = 416.0 * s
        p.sprite(
            UiSheets.dialogWindow,
            RectF(0, 0, 824, 416),
            RectF((PromptLayout.windowCenterX * UiMetrics.unitX) - (w / 2.0), (PromptLayout.centerY * UiMetrics.unitY) - (h / 2.0), w, h),
            alpha: a
        )

        let style = TextStyle(
            canvasW: 640,
            canvasH: 448,
            sx: PromptLayout.messageSx * Double(s),
            sy: PromptLayout.messageSy * Double(s),
            width: PromptLayout.messageWidth,
            height: PromptLayout.messageHeight,
            leading: 9,
            spacing: 0,
            colour: TextStyle.white,
            drawFlags: BlockDraw.outline | BlockDraw.center
        )
        ctx.text.draw(p, ctx.message(prompt.messageId), style, PromptLayout.messageX, PromptLayout.centerY + (PromptLayout.messageDy * s), a)

        for i in 0..<2 {
            let yes = (i == 1)
            let x = (yes ? PromptLayout.yesX : PromptLayout.noX) * UiMetrics.unitX
            UiDialogButtons.draw(p, ctx, yes: yes, selected: prompt.cursor == i, x: x, y: PromptLayout.buttonY * UiMetrics.unitY, alpha: a)
        }

        UiWidgets.guide(p, guide, dy: 0.0, alpha: a, decideIsCross: ctx.services.decideIsCross)
    }
    public static func Draw(_ p: UiPainter, _ ctx: UiContext, _ prompt: UiStoryPrompt) {
        draw(p, ctx, prompt)
    }
}
