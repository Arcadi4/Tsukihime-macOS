import Foundation
import Metal
import TsukiCore

/// Resolves the textures a display list names.
public protocol ITextureSource: AnyObject {
    /// The Metal texture of `key` and its transition parameters, or nil when it is not resident.
    func tryGetTexture(_ key: TextureRef) -> (texture: MTLTexture, transition: TransitionParams?)?
}

/// What one `DisplayListExecutor.execute` did.
public struct ExecuteStats: Equatable, Sendable {
    public var commands: Int
    public var draws: Int
    public var culled: Int
    public var captures: Int
    public var missingTextures: Int
    public var blits: Int
    public var blitPixels: Int64

    public init(
        commands: Int = 0,
        draws: Int = 0,
        culled: Int = 0,
        captures: Int = 0,
        missingTextures: Int = 0,
        blits: Int = 0,
        blitPixels: Int64 = 0
    ) {
        self.commands = commands
        self.draws = draws
        self.culled = culled
        self.captures = captures
        self.missingTextures = missingTextures
        self.blits = blits
        self.blitPixels = blitPixels
    }
}

/// Executes `DisplayList`s on a `MetalCompositor`.
public final class DisplayListExecutor: @unchecked Sendable {
    public let compositor: MetalCompositor
    public let textures: ITextureSource

    public init(compositor: MetalCompositor, textures: ITextureSource) {
        self.compositor = compositor
        self.textures = textures
    }

    /// Runs every command of `list` in order.
    @discardableResult
    public func execute(_ list: DisplayList) -> ExecuteStats {
        compositor.beginFrame()
        var missing = 0

        for cmd in list.commands {
            switch cmd.kind {
            case .texturedQuad:
                guard let (tex, tp) = resolve(cmd.texture) else {
                    missing += 1
                    break
                }
                draw(cmd, texture: tex, transition: tp)

            case .fillQuad:
                draw(cmd, texture: nil, transition: nil)

            case .capture:
                compositor.capture(target: cmd.target, surface: Int(cmd.texture.a))

            case .clear:
                let fill = cmd.v0.rgba
                let r = UInt8(fill & 0xFF)
                let g = UInt8((fill >> 8) & 0xFF)
                let b = UInt8((fill >> 16) & 0xFF)
                let a = UInt8((fill >> 24) & 0xFF)
                compositor.clear(target: cmd.target, r: r, g: g, b: b, a: a)
            }
        }

        compositor.endFrame()
        let c = compositor.counters
        return ExecuteStats(
            commands: list.commands.count,
            draws: c.draws,
            culled: c.culled,
            captures: c.captures,
            missingTextures: missing,
            blits: c.blits,
            blitPixels: c.blitPixels
        )
    }

    private func resolve(_ key: TextureRef) -> (texture: MTLTexture, transition: TransitionParams?)? {
        if key.kind == .capture {
            let tex = compositor.captureSurface(Int(key.a)).texture
            return (texture: tex, transition: nil)
        }
        return textures.tryGetTexture(key)
    }

    private func draw(_ cmd: DrawCommand, texture: MTLTexture?, transition: TransitionParams?) {
        let quad = [cmd.v0, cmd.v1, cmd.v2, cmd.v3]
        compositor.drawQuad(
            target: cmd.target,
            texture: texture,
            quad: quad,
            word: Int(cmd.effectWord),
            blendState: Int(cmd.blendState),
            transition: transition,
            clip: cmd.clip,
            fx: cmd.fx
        )
    }
}
