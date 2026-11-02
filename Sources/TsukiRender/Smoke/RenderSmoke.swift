import Foundation
import Metal
import TsukiCore

/// The result of drawing the smoke shader.
public struct SmokeRender: Equatable, Sendable {
    public let pixels: [UInt8]
    public let mismatches: Int
    public let log: String

    public init(pixels: [UInt8], mismatches: Int, log: String) {
        self.pixels = pixels
        self.mismatches = mismatches
        self.log = log
    }
}

/// Offscreen Metal test helper.
public enum RenderSmoke {
    public static let width = 8
    public static let height = 4
    public static let tintBlue: Float = 0.6

    public static let smokeMSL = """
    #include <metal_stdlib>
    using namespace metal;

    struct SmokeVertexOut {
        float4 position [[position]];
    };

    vertex SmokeVertexOut smoke_vertex(uint vid [[vertex_id]]) {
        SmokeVertexOut out;
        float2 p = float2(float((vid << 1) & 2), float(vid & 2));
        out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        return out;
    }

    fragment float4 smoke_fragment(SmokeVertexOut in [[stage_in]]) {
        float r = in.position.x / 8.0;
        float g = in.position.y / 4.0;
        return float4(r, g, 0.6, 1.0);
    }
    """

    /// Computes the expected RGBA8 target pixels.
    public static func expected() -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let r = toUnorm8((Double(x) + 0.5) / Double(width))
                let g = toUnorm8((Double(y) + 0.5) / Double(height))
                let b = toUnorm8(Double(tintBlue))
                let a: UInt8 = 255
                let offset = (y * width + x) * 4
                buf[offset] = r
                buf[offset + 1] = g
                buf[offset + 2] = b
                buf[offset + 3] = a
            }
        }
        return buf
    }

    /// Compiles and draws the smoke shader offscreen, reading back pixels to compare with expected.
    public static func render(device: MTLDevice) throws -> SmokeRender {
        guard let queue = device.makeCommandQueue() else {
            throw TsukiError.state("failed to make command queue")
        }

        let library = try device.makeLibrary(source: smokeMSL, options: nil)
        guard let vFunc = library.makeFunction(name: "smoke_vertex"),
              let fFunc = library.makeFunction(name: "smoke_fragment") else {
            throw TsukiError.state("failed to find smoke functions")
        }

        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.vertexFunction = vFunc
        pipelineDesc.fragmentFunction = fFunc
        pipelineDesc.colorAttachments[0].pixelFormat = .rgba8Unorm
        let pipeline = try device.makeRenderPipelineState(descriptor: pipelineDesc)

        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: texDesc) else {
            throw TsukiError.state("failed to make target texture")
        }

        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = texture
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        passDesc.colorAttachments[0].storeAction = .store

        guard let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: passDesc) else {
            throw TsukiError.state("failed to make encoder")
        }

        enc.setRenderPipelineState(pipeline)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()

        cmd.commit()
        cmd.waitUntilCompleted()

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { ptr in
            texture.getBytes(
                ptr.baseAddress!,
                bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0
            )
        }

        let exp = expected()
        var mismatches = 0
        for i in 0..<pixels.count {
            if pixels[i] != exp[i] {
                mismatches += 1
            }
        }

        return SmokeRender(pixels: pixels, mismatches: mismatches, log: "ok")
    }

    private static func toUnorm8(_ v: Double) -> UInt8 {
        UInt8(clamping: Int((max(0.0, min(1.0, v)) * 255.0).rounded()))
    }
}
