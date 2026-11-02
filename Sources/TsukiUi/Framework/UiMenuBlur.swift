import Foundation
import TsukiCore
import TsukiEngine

/// Appends the blur of the scene drawn so far to a display list.
public enum UiMenuBlur {
    /// The capture surface that holds the unblurred scene.
    public static let sceneSurface = 12
    public static let SceneSurface = sceneSurface

    /// The capture surface that holds the horizontally blurred scene.
    public static let passSurface = 13
    public static let PassSurface = passSurface

    /// The offscreen target of the horizontal pass.
    public static let passTarget: UInt8 = 40
    public static let PassTarget: UInt8 = passTarget

    /// The standard deviation in pixels of the 1920 x 1080 frame.
    public static let sigma: Float = 4.4
    public static let Sigma = sigma

    /// The taps on each side of the centre.
    public static let taps = 13
    public static let Taps = taps

    /// Frames of the fade-in.
    public static let fadeFrames = 12
    public static let FadeFrames = fadeFrames

    /// Adds the four commands that blur what the list has drawn so far to the frame, at `alpha` (0..1) over the unblurred scene.
    public static func append(_ list: DisplayList, _ alpha: Float) {
        if alpha <= 0.0 {
            return
        }

        let w: Float = 1920.0
        let h: Float = 1080.0
        list.add(DrawCommand(kind: .capture, target: 0, texture: TextureRef.capture(sceneSurface)))
        list.add(pass(
            source: TextureRef.capture(sceneSurface),
            target: passTarget,
            alpha: 255,
            blend: 0,
            fx: QuadFx(pass: .blur, mask: 0, nearest: false, a0: 1.0 / w, a1: 0.0, a2: sigma, a3: Float(taps))
        ))
        list.add(DrawCommand(kind: .capture, target: passTarget, texture: TextureRef.capture(passSurface)))
        let a = UInt8(clamping: Int(floor(alpha * 255.0)).clamped(to: 1...255))
        list.add(pass(
            source: TextureRef.capture(passSurface),
            target: 0,
            alpha: a,
            blend: 1,
            fx: QuadFx(pass: .blur, mask: 0, nearest: false, a0: 0.0, a1: 1.0 / h, a2: sigma, a3: Float(taps))
        ))
    }
    public static func Append(_ list: DisplayList, _ alpha: Float) {
        append(list, alpha)
    }

    private static func pass(source: TextureRef, target: UInt8, alpha: UInt8, blend: UInt8, fx: QuadFx) -> DrawCommand {
        let rgba = 0xFFFFFF | (UInt32(alpha) << 24)
        return DrawCommand(
            kind: .texturedQuad,
            target: target,
            texture: source,
            v0: Vertex(x: 0, y: 0, u: 0, v: 0, rgba: rgba),
            v1: Vertex(x: 1920, y: 0, u: 1, v: 0, rgba: rgba),
            v2: Vertex(x: 0, y: 1080, u: 0, v: 1, rgba: rgba),
            v3: Vertex(x: 1920, y: 1080, u: 1, v: 1, rgba: rgba),
            effectWord: 0,
            blendState: blend,
            clip: nil,
            fx: fx
        )
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
