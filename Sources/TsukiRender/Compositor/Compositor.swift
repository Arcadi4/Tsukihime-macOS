import Foundation
import Metal
import QuartzCore
import TsukiCore

/// One blend state as Metal blend factors and operations.
public struct MetalBlend: Equatable, Sendable {
    public let enabled: Bool
    public let sourceRGBBlendFactor: MTLBlendFactor
    public let destinationRGBBlendFactor: MTLBlendFactor
    public let rgbBlendOperation: MTLBlendOperation
    public let sourceAlphaBlendFactor: MTLBlendFactor
    public let destinationAlphaBlendFactor: MTLBlendFactor
    public let alphaBlendOperation: MTLBlendOperation

    public init(
        enabled: Bool,
        sourceRGBBlendFactor: MTLBlendFactor = .one,
        destinationRGBBlendFactor: MTLBlendFactor = .zero,
        rgbBlendOperation: MTLBlendOperation = .add,
        sourceAlphaBlendFactor: MTLBlendFactor = .one,
        destinationAlphaBlendFactor: MTLBlendFactor = .zero,
        alphaBlendOperation: MTLBlendOperation = .add
    ) {
        self.enabled = enabled
        self.sourceRGBBlendFactor = sourceRGBBlendFactor
        self.destinationRGBBlendFactor = destinationRGBBlendFactor
        self.rgbBlendOperation = rgbBlendOperation
        self.sourceAlphaBlendFactor = sourceAlphaBlendFactor
        self.destinationAlphaBlendFactor = destinationAlphaBlendFactor
        self.alphaBlendOperation = alphaBlendOperation
    }
}

/// The 14 fixed-function blend states of table 0x2D8030 as Metal blend descriptors.
public enum MetalBlendStates {
    public static let count = 14
    public static let maskMultiply = 0x80

    private static let maskMultiplyRecord = MetalBlend(
        enabled: true,
        sourceRGBBlendFactor: .zero,
        destinationRGBBlendFactor: .one,
        rgbBlendOperation: .add,
        sourceAlphaBlendFactor: .zero,
        destinationAlphaBlendFactor: .sourceAlpha,
        alphaBlendOperation: .add
    )

    private static let table: [MetalBlend] = buildTable()

    public static func get(_ state: Int) -> MetalBlend {
        if state == maskMultiply {
            return maskMultiplyRecord
        }
        if state < 0 || state >= count {
            return table[1]
        }
        return table[state]
    }

    private static func buildTable() -> [MetalBlend] {
        func on(
            _ cs: MTLBlendFactor, _ cd: MTLBlendFactor, _ cf: MTLBlendOperation,
            _ asrc: MTLBlendFactor, _ ad: MTLBlendFactor, _ af: MTLBlendOperation
        ) -> MetalBlend {
            MetalBlend(
                enabled: true,
                sourceRGBBlendFactor: cs, destinationRGBBlendFactor: cd, rgbBlendOperation: cf,
                sourceAlphaBlendFactor: asrc, destinationAlphaBlendFactor: ad, alphaBlendOperation: af
            )
        }

        return [
            // 0: replace
            MetalBlend(enabled: false, sourceRGBBlendFactor: .one, destinationRGBBlendFactor: .zero, rgbBlendOperation: .add, sourceAlphaBlendFactor: .one, destinationAlphaBlendFactor: .zero, alphaBlendOperation: .add),
            // 1: over
            on(.sourceAlpha, .oneMinusSourceAlpha, .add, .sourceAlpha, .oneMinusSourceAlpha, .add),
            // 2: additive
            on(.sourceAlpha, .one, .add, .sourceAlpha, .one, .add),
            // 3: erase
            on(.zero, .oneMinusSourceAlpha, .add, .sourceAlpha, .oneMinusSourceAlpha, .add),
            // 4: alpha := max(sa*1, da*0) = sa
            on(.zero, .one, .add, .one, .zero, .add),
            // 5: alpha := min(sa, da)
            on(.zero, .one, .add, .one, .one, .min),
            // 6: through dst alpha
            on(.destinationAlpha, .oneMinusDestinationAlpha, .add, .zero, .one, .add),
            // 7: add through dst alpha
            on(.destinationAlpha, .one, .add, .zero, .one, .add),
            // 8: subtract
            on(.sourceAlpha, .one, .subtract, .sourceAlpha, .one, .subtract),
            // 9: s * (1 - d)
            on(.oneMinusDestinationColor, .zero, .add, .zero, .one, .add),
            // 10: alpha := min(0, 0) = 0
            on(.zero, .one, .add, .zero, .zero, .add),
            // 11: alpha := max(sa, da)
            on(.zero, .one, .add, .one, .one, .max),
            // 12: alpha := sa * sa
            on(.zero, .one, .add, .sourceAlpha, .zero, .add),
            // 13:
            on(.destinationAlpha, .oneMinusDestinationAlpha, .add, .sourceAlpha, .oneMinusDestinationAlpha, .add),
        ]
    }
}

/// How much of the target is copied into the backdrop before a backdrop-reading quad.
public enum BackdropBlit: Sendable {
    case bounds
    case full
}

/// Texture filter for the source texture of textured quads.
public enum SamplingFilter: Sendable {
    case linear
    case nearest
}

/// Per-frame counters of the compositor.
public final class CompositorCounters: @unchecked Sendable {
    public var draws: Int = 0
    public var culled: Int = 0
    public var offscreen: Int = 0
    public var captures: Int = 0
    public var blits: Int = 0
    public var blitPixels: Int64 = 0

    public func reset() {
        draws = 0
        culled = 0
        offscreen = 0
        captures = 0
        blits = 0
        blitPixels = 0
    }
}

/// An RGBA8 texture with its size.
public final class RenderTarget: @unchecked Sendable {
    public let texture: MTLTexture
    public let width: Int
    public let height: Int

    public init(texture: MTLTexture, width: Int, height: Int) {
        self.texture = texture
        self.width = width
        self.height = height
    }

    /// Reads back RGBA8 pixels from the texture (top row first).
    public func readPixels() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { ptr in
            texture.getBytes(
                ptr.baseAddress!,
                bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0
            )
        }
        return bytes
    }
}

/// Metal vertex structure layout.
public struct MetalVertex {
    public var x: Float
    public var y: Float
    public var u: Float
    public var v: Float
    public var rgba: UInt32

    public init(_ v: Vertex) {
        self.x = v.x
        self.y = v.y
        self.u = v.u
        self.v = v.v
        self.rgba = v.rgba
    }

    public init(x: Float, y: Float, u: Float, v: Float, rgba: UInt32) {
        self.x = x
        self.y = y
        self.u = u
        self.v = v
        self.rgba = rgba
    }
}

/// Draws quads into RGBA8 Metal textures the way the PS4 display-list executor does.
public final class MetalCompositor: @unchecked Sendable {
    public static let captureSurfaceCount = 16
    private static let vboVertices = 16384

    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public let width: Int
    public let height: Int

    public var blit: BackdropBlit = .bounds
    public var filter: SamplingFilter = .linear
    public let counters = CompositorCounters()

    private var targets: [UInt8: RenderTarget] = [:]
    private var captures: [RenderTarget?] = Array(repeating: nil, count: captureSurfaceCount)
    private var backdropTarget: RenderTarget!

    private let vertexDescriptor: MTLVertexDescriptor
    private var vertexBuffer: MTLBuffer!
    private var vertexCursor = 0

    private var samplerLinear: MTLSamplerState!
    private var samplerNearest: MTLSamplerState!
    private var dummyWhiteTexture: MTLTexture!

    // Pipeline cache: (mode, blendState) -> MTLRenderPipelineState
    private struct PipelineKey: Hashable {
        let mode: Int
        let blendState: Int
    }
    private var pipelineCache: [PipelineKey: MTLRenderPipelineState] = [:]
    private var compiledFunctions: [Int: (vertex: MTLFunction, fragment: MTLFunction)] = [:]

    // Active command buffer and encoder state
    private var currentCommandBuffer: MTLCommandBuffer?
    private var currentRenderEncoder: MTLRenderCommandEncoder?
    private var currentRenderTargetId: UInt8?

    public init(device: MTLDevice, width: Int = 1920, height: Int = 1080) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            throw TsukiError.state("failed to create Metal command queue")
        }
        self.commandQueue = queue
        self.width = width
        self.height = height
        self.vertexDescriptor = CompositorShaders.makeVertexDescriptor()

        let vboSize = Self.vboVertices * MemoryLayout<MetalVertex>.stride
        guard let buf = device.makeBuffer(length: vboSize, options: .storageModeShared) else {
            throw TsukiError.state("failed to allocate Metal vertex buffer")
        }
        self.vertexBuffer = buf

        setupSamplers()
        setupDummyTexture()

        self.backdropTarget = createTarget(w: width, h: height)
        self.targets[0] = createTarget(w: width, h: height)
    }

    public var frame: RenderTarget {
        target(0)
    }

    public var backdrop: RenderTarget {
        backdropTarget
    }

    public func target(_ id: UInt8) -> RenderTarget {
        if let t = targets[id] {
            return t
        }
        let t = createTarget(w: width, h: height)
        targets[id] = t
        clearTarget(t, r: 0, g: 0, b: 0, a: 0)
        return t
    }

    public func captureSurface(_ surface: Int) -> RenderTarget {
        precondition(surface >= 0 && surface < Self.captureSurfaceCount)
        if let t = captures[surface] {
            return t
        }
        let t = createTarget(w: width, h: height)
        captures[surface] = t
        clearTarget(t, r: 0, g: 0, b: 0, a: 0)
        return t
    }

    public func beginFrame() {
        endCurrentEncoding()
        counters.reset()
        vertexCursor = 0
        currentCommandBuffer = commandQueue.makeCommandBuffer()
    }

    public func clear(target id: UInt8, r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let t = target(id)
        clearTarget(t, r: Float(r) / 255.0, g: Float(g) / 255.0, b: Float(b) / 255.0, a: Float(a) / 255.0)
    }

    public func drawQuad(
        target id: UInt8,
        texture: MTLTexture?,
        quad: [Vertex],
        word: Int,
        blendState: Int,
        transition: TransitionParams? = nil,
        clip: PixelRect? = nil,
        fx: QuadFx = QuadFx()
    ) {
        precondition(quad.count == 4, "a quad must have 4 vertices")

        if (quad[0].rgba >> 24) == 0 && (quad[1].rgba >> 24) == 0 && (quad[2].rgba >> 24) == 0 && (quad[3].rgba >> 24) == 0 {
            counters.culled += 1
            return
        }

        if fx.mask != 0 && fx.mask == id {
            return
        }

        var transition = transition
        if fx.pass == .rule {
            transition = TransitionParams(lo: fx.a0, hi: fx.a1, invert: fx.a2)
        }

        let rt = target(id)
        let e = DrawEffect.decode(word)
        let mode = DrawEffect.selectShader(textured: texture != nil, shaderMode: e.shaderMode, hasTransitionParams: transition != nil)

        let minX = min(min(quad[0].x, quad[1].x), min(quad[2].x, quad[3].x))
        let maxX = max(max(quad[0].x, quad[1].x), max(quad[2].x, quad[3].x))
        let minY = min(min(quad[0].y, quad[1].y), min(quad[2].y, quad[3].y))
        let maxY = max(max(quad[0].y, quad[1].y), max(quad[2].y, quad[3].y))

        var x0 = max(0, min(rt.width, Int(floor(minX))))
        var x1 = max(0, min(rt.width, Int(ceil(maxX))))
        var y0 = max(0, min(rt.height, Int(floor(minY))))
        var y1 = max(0, min(rt.height, Int(ceil(maxY))))

        if let c = clip {
            x0 = max(x0, c.x)
            y0 = max(y0, c.y)
            x1 = min(x1, c.x + c.width)
            y1 = min(y1, c.y + c.height)
        }

        if x1 <= x0 || y1 <= y0 {
            counters.offscreen += 1
            return
        }

        if CompositorShaders.readsBackdrop(mode) {
            copyBackdrop(rt, x0: x0, y0: y0, x1: x1, y1: y1)
        }

        if vertexCursor + 4 > Self.vboVertices {
            vertexCursor = 0
        }

        let cyclic = (cross(quad[0], quad[1], quad[2]) >= 0) == (cross(quad[0], quad[2], quad[3]) >= 0)
        let v0 = MetalVertex(quad[0])
        let v1 = MetalVertex(quad[1])
        let v2 = MetalVertex(cyclic ? quad[3] : quad[2])
        let v3 = MetalVertex(cyclic ? quad[2] : quad[3])

        let ptr = vertexBuffer.contents().assumingMemoryBound(to: MetalVertex.self)
        ptr[vertexCursor] = v0
        ptr[vertexCursor + 1] = v1
        ptr[vertexCursor + 2] = v2
        ptr[vertexCursor + 3] = v3

        guard let pipeline = getPipelineState(mode: mode, blendState: blendState) else {
            return
        }

        let encoder = ensureRenderEncoder(for: id)
        encoder.setRenderPipelineState(pipeline)

        let vertexOffset = vertexCursor * MemoryLayout<MetalVertex>.stride
        encoder.setVertexBuffer(vertexBuffer, offset: vertexOffset, index: 0)

        var uniforms = CompositorUniforms(
            viewport: SIMD4<Float>(Float(rt.width), Float(rt.height), 0, 0),
            params: (mode == CompositorShaders.modeTransition)
                ? SIMD4<Float>(transition?.lo ?? 0, transition?.hi ?? 1, transition?.invert ?? 0, 0)
                : SIMD4<Float>(1.0 - e.strength, e.strength, DrawEffect.p2For(mode: e.shaderMode, blendState: blendState), 0),
            fx: SIMD4<Float>(fx.pass == .haze ? 1 : 0, fx.mask != 0 ? 1 : 0, fx.pass == .blur ? 1 : 0, 0),
            blur: SIMD4<Float>(fx.a0, fx.a1, fx.a2, fx.a3),
            hazeA: SIMD4<Float>(fx.a0, fx.a1, fx.a2, fx.a3),
            hazeB: SIMD4<Float>(fx.b0, fx.b1, fx.b2, fx.b3)
        )
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<CompositorUniforms>.size, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<CompositorUniforms>.size, index: 1)

        let sourceTex = texture ?? dummyWhiteTexture
        encoder.setFragmentTexture(sourceTex, index: 0)
        encoder.setFragmentTexture(backdropTarget.texture, index: 1)

        let maskTex = fx.mask != 0 ? target(fx.mask).texture : dummyWhiteTexture
        encoder.setFragmentTexture(maskTex, index: 2)

        let sampler = (filter == .nearest || fx.nearest) ? samplerNearest : samplerLinear
        encoder.setFragmentSamplerState(sampler, index: 0)

        if let c = clip {
            let scX = max(0, min(rt.width - 1, c.x))
            let scY = max(0, min(rt.height - 1, c.y))
            let scW = max(1, min(rt.width - scX, c.width))
            let scH = max(1, min(rt.height - scY, c.height))
            encoder.setScissorRect(MTLScissorRect(x: scX, y: scY, width: scW, height: scH))
        } else {
            encoder.setScissorRect(MTLScissorRect(x: 0, y: 0, width: rt.width, height: rt.height))
        }

        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        vertexCursor += 4
        counters.draws += 1
    }

    public func capture(target id: UInt8, surface: Int) {
        endCurrentEncoding()
        let src = target(id)
        let dst = captureSurface(surface)

        ensureCommandBuffer()
        guard let blit = currentCommandBuffer?.makeBlitCommandEncoder() else {
            return
        }
        blit.copy(
            from: src.texture, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: src.width, height: src.height, depth: 1),
            to: dst.texture, destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blit.endEncoding()
        counters.captures += 1
    }

    public func endFrame() {
        endCurrentEncoding()
        currentCommandBuffer?.commit()
        currentCommandBuffer?.waitUntilCompleted()
        currentCommandBuffer = nil
    }

    /// Renders the current frame into `destination` texture with 16:9 letterboxing.
    public func draw(into destination: MTLTexture) {
        endCurrentEncoding()
        ensureCommandBuffer()

        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = destination
        desc.colorAttachments[0].loadAction = .clear
        desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        desc.colorAttachments[0].storeAction = .store

        guard let encoder = currentCommandBuffer?.makeRenderCommandEncoder(descriptor: desc) else {
            return
        }

        let dstW = Float(destination.width)
        let dstH = Float(destination.height)
        let s = min(dstW / Float(width), dstH / Float(height))
        let w = Float(width) * s
        let h = Float(height) * s
        let x = (dstW - w) / 2.0
        let y = (dstH - h) / 2.0

        let quad = [
            Vertex(x: x, y: y, u: 0, v: 0, rgba: 0xFFFFFFFF),
            Vertex(x: x + w, y: y, u: 1, v: 0, rgba: 0xFFFFFFFF),
            Vertex(x: x, y: y + h, u: 0, v: 1, rgba: 0xFFFFFFFF),
            Vertex(x: x + w, y: y + h, u: 1, v: 1, rgba: 0xFFFFFFFF),
        ]

        if let pipeline = getPipelineState(mode: CompositorShaders.modeBasic, blendState: 0) {
            encoder.setRenderPipelineState(pipeline)
            var verts = quad.map { MetalVertex($0) }
            encoder.setVertexBytes(&verts, length: MemoryLayout<MetalVertex>.stride * 4, index: 0)

            var uniforms = CompositorUniforms(viewport: SIMD4<Float>(dstW, dstH, 0, 0))
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<CompositorUniforms>.size, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<CompositorUniforms>.size, index: 1)

            encoder.setFragmentTexture(frame.texture, index: 0)
            encoder.setFragmentTexture(backdropTarget.texture, index: 1)
            encoder.setFragmentTexture(dummyWhiteTexture, index: 2)
            encoder.setFragmentSamplerState(samplerLinear, index: 0)

            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        encoder.endEncoding()
    }

    /// Presents the current frame to a CAMetalDrawable.
    public func present(to drawable: CAMetalDrawable) {
        draw(into: drawable.texture)
        currentCommandBuffer?.present(drawable)
    }

    /// Reads back the frame or a target as RGBA8 bytes.
    public func readTarget(_ id: UInt8 = 0) -> [UInt8] {
        endFrame()
        return target(id).readPixels()
    }

    // MARK: - Internal Helpers

    private func cross(_ o: Vertex, _ a: Vertex, _ b: Vertex) -> Float {
        ((a.x - o.x) * (b.y - o.y)) - ((a.y - o.y) * (b.x - o.x))
    }

    private func copyBackdrop(_ rt: RenderTarget, x0: Int, y0: Int, x1: Int, y1: Int) {
        endCurrentEncoding()
        var bx0 = x0
        var by0 = y0
        var bx1 = x1
        var by1 = y1
        if blit == .full {
            bx0 = 0
            by0 = 0
            bx1 = rt.width
            by1 = rt.height
        }

        ensureCommandBuffer()
        guard let blitEncoder = currentCommandBuffer?.makeBlitCommandEncoder() else {
            return
        }

        blitEncoder.copy(
            from: rt.texture, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: bx0, y: by0, z: 0),
            sourceSize: MTLSize(width: bx1 - bx0, height: by1 - by0, depth: 1),
            to: backdropTarget.texture, destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: bx0, y: by0, z: 0)
        )
        blitEncoder.endEncoding()

        counters.blits += 1
        counters.blitPixels += Int64((bx1 - bx0) * (by1 - by0))
    }

    private func clearTarget(_ t: RenderTarget, r: Float, g: Float, b: Float, a: Float) {
        endCurrentEncoding()
        ensureCommandBuffer()
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = t.texture
        desc.colorAttachments[0].loadAction = .clear
        desc.colorAttachments[0].clearColor = MTLClearColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
        desc.colorAttachments[0].storeAction = .store
        let enc = currentCommandBuffer?.makeRenderCommandEncoder(descriptor: desc)
        enc?.endEncoding()
    }

    private func ensureCommandBuffer() {
        if currentCommandBuffer == nil {
            currentCommandBuffer = commandQueue.makeCommandBuffer()
        }
    }

    private func ensureRenderEncoder(for targetId: UInt8) -> MTLRenderCommandEncoder {
        if let enc = currentRenderEncoder, currentRenderTargetId == targetId {
            return enc
        }
        endCurrentEncoding()
        ensureCommandBuffer()

        let rt = target(targetId)
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = rt.texture
        desc.colorAttachments[0].loadAction = .load
        desc.colorAttachments[0].storeAction = .store

        let enc = currentCommandBuffer!.makeRenderCommandEncoder(descriptor: desc)!
        currentRenderEncoder = enc
        currentRenderTargetId = targetId
        return enc
    }

    private func endCurrentEncoding() {
        if let enc = currentRenderEncoder {
            enc.endEncoding()
            currentRenderEncoder = nil
            currentRenderTargetId = nil
        }
    }

    private func createTarget(w: Int, h: Int) -> RenderTarget {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: w,
            height: h,
            mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead, .shaderWrite]
        desc.storageMode = .shared
        let tex = device.makeTexture(descriptor: desc)!
        return RenderTarget(texture: tex, width: w, height: h)
    }

    private func setupSamplers() {
        let linearDesc = MTLSamplerDescriptor()
        linearDesc.minFilter = .linear
        linearDesc.magFilter = .linear
        linearDesc.sAddressMode = .clampToEdge
        linearDesc.tAddressMode = .clampToEdge
        self.samplerLinear = device.makeSamplerState(descriptor: linearDesc)

        let nearestDesc = MTLSamplerDescriptor()
        nearestDesc.minFilter = .nearest
        nearestDesc.magFilter = .nearest
        nearestDesc.sAddressMode = .clampToEdge
        nearestDesc.tAddressMode = .clampToEdge
        self.samplerNearest = device.makeSamplerState(descriptor: nearestDesc)
    }

    private func setupDummyTexture() {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        desc.usage = .shaderRead
        desc.storageMode = .shared
        let tex = device.makeTexture(descriptor: desc)!
        var white: UInt32 = 0xFFFFFFFF
        tex.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &white, bytesPerRow: 4)
        self.dummyWhiteTexture = tex
    }

    private func getPipelineState(mode: Int, blendState: Int) -> MTLRenderPipelineState? {
        let key = PipelineKey(mode: mode, blendState: blendState)
        if let cached = pipelineCache[key] {
            return cached
        }

        // Compile functions for mode if needed
        let functions: (vertex: MTLFunction, fragment: MTLFunction)
        if let f = compiledFunctions[mode] {
            functions = f
        } else {
            let source = "#define MODE \(mode)\n" + CompositorShaders.mslSource
            guard let library = try? device.makeLibrary(source: source, options: nil),
                  let vFunc = library.makeFunction(name: "vertex_main"),
                  let fFunc = library.makeFunction(name: "fragment_main") else {
                return nil
            }
            functions = (vertex: vFunc, fragment: fFunc)
            compiledFunctions[mode] = functions
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = functions.vertex
        desc.fragmentFunction = functions.fragment
        desc.vertexDescriptor = vertexDescriptor
        desc.colorAttachments[0].pixelFormat = .rgba8Unorm

        let blend = MetalBlendStates.get(blendState)
        if blend.enabled {
            desc.colorAttachments[0].isBlendingEnabled = true
            desc.colorAttachments[0].sourceRGBBlendFactor = blend.sourceRGBBlendFactor
            desc.colorAttachments[0].destinationRGBBlendFactor = blend.destinationRGBBlendFactor
            desc.colorAttachments[0].rgbBlendOperation = blend.rgbBlendOperation
            desc.colorAttachments[0].sourceAlphaBlendFactor = blend.sourceAlphaBlendFactor
            desc.colorAttachments[0].destinationAlphaBlendFactor = blend.destinationAlphaBlendFactor
            desc.colorAttachments[0].alphaBlendOperation = blend.alphaBlendOperation
        } else {
            desc.colorAttachments[0].isBlendingEnabled = false
        }

        guard let state = try? device.makeRenderPipelineState(descriptor: desc) else {
            return nil
        }
        pipelineCache[key] = state
        return state
    }
}
