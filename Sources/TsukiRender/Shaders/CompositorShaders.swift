import Foundation
import Metal
import simd

/// Uniform buffer layout matching the MSL struct CompositorUniforms.
public struct CompositorUniforms {
    public var viewport: SIMD4<Float>
    public var params: SIMD4<Float>
    public var fx: SIMD4<Float>
    public var blur: SIMD4<Float>
    public var hazeA: SIMD4<Float>
    public var hazeB: SIMD4<Float>

    public init(
        viewport: SIMD4<Float> = .zero,
        params: SIMD4<Float> = .zero,
        fx: SIMD4<Float> = .zero,
        blur: SIMD4<Float> = .zero,
        hazeA: SIMD4<Float> = .zero,
        hazeB: SIMD4<Float> = .zero
    ) {
        self.viewport = viewport
        self.params = params
        self.fx = fx
        self.blur = blur
        self.hazeA = hazeA
        self.hazeB = hazeB
    }
}

/// Metal Shading Language source and pipeline helpers.
public enum CompositorShaders {
    /// PS #2, basic 2DTex: S * C (pictures, captures).
    public static let modeBasic = 0

    /// PS #3, basic 2D: the vertex colour (untextured fills).
    public static let modeSolid = 100

    /// PS #0, transition 2DTex: the rule mask of a texture that carries transition parameters.
    public static let modeTransition = 101

    /// Every fragment-shader mode the compositor uses: basic, solid, transition and the 24 blend modes (27 programs).
    public static let allModes: [Int] = buildModes()

    /// True for the 24 blend shaders, which read the backdrop D.
    public static func readsBackdrop(_ mode: Int) -> Bool {
        mode >= 1 && mode <= 25 && mode != 3
    }

    private static func buildModes() -> [Int] {
        var modes = [modeBasic, modeSolid, modeTransition]
        for m in 1...25 where m != 3 {
            modes.append(m)
        }
        return modes
    }

    /// The unified MSL shader source code.
    public static let mslSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct CompositorUniforms {
        float4 viewport;   // x = width, y = height
        float4 params;     // blend: (1 - strength, strength, P2, 0); transition: (lo, hi, inv, 0)
        float4 fx;         // (haze enabled, mask enabled, blur enabled, 0)
        float4 blur;       // (du, dv, sigma, n)
        float4 hazeA;      // x: (amplitude, waves, phase, v offset)
        float4 hazeB;      // y: (amplitude, waves, phase, v scale)
    };

    struct VertexIn {
        float2 pos [[attribute(0)]];
        float2 uv [[attribute(1)]];
        float4 color [[attribute(2)]];
    };

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
        float4 color;
    };

    vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                                constant CompositorUniforms &uniforms [[buffer(1)]])
    {
        VertexOut out;
        out.uv = in.uv;
        out.color = in.color;
        float ndcX = in.pos.x * (2.0 / uniforms.viewport.x) - 1.0;
        float ndcY = 1.0 - in.pos.y * (2.0 / uniforms.viewport.y);
        out.position = float4(ndcX, ndcY, 0.0, 1.0);
        return out;
    }

    inline float4 exportMrt0(float4 x)
    {
        uint4 u = as_type<uint4>(x);
        bool4 isNan = (u & 0x7FFFFFFFu) > 0x7F800000u;
        x = clamp(select(x, float4(0.0), isNan), 0.0, 1.0);
        uint4 normalBits = as_type<uint4>(x) & 0xFFFFE000u;
        float4 normal = as_type<float4>(normalBits);
        float4 subnormal = floor(x * 16777216.0) * (1.0 / 16777216.0);
        return select(normal, subnormal, x < float4(6.103515625e-05));
    }

    inline float2 hazeUv(float2 uv, float4 fx, float4 hazeA, float4 hazeB)
    {
        if (fx.x < 0.5) {
            return uv;
        }
        const float tau = 6.2831853;
        float s = hazeA.w + hazeB.w * uv.y;
        float dx = sin(tau * (fract(s * hazeA.y) + fract(hazeA.z))) * hazeA.x;
        float dy = cos(tau * (fract(s * hazeB.y) + fract(hazeB.z))) * hazeB.x;
        return uv + float2(dx, dy);
    }

    inline float4 blurTaps(float2 uv, texture2d<float> tex, sampler s, float4 blur)
    {
        float sigma = max(blur.z, 0.01);
        int n = int(blur.w + 0.5);
        float4 acc = float4(0.0);
        float sum = 0.0;
        for (int k = -n; k <= n; k++) {
            float x = float(k);
            float w = exp(-x * x / (2.0 * sigma * sigma));
            acc += tex.sample(s, uv + blur.xy * x) * w;
            sum += w;
        }
        return acc / sum;
    }

    fragment float4 fragment_main(VertexOut in [[stage_in]],
                                  constant CompositorUniforms &uniforms [[buffer(1)]],
                                  texture2d<float> u_tex [[texture(0)]],
                                  texture2d<float> u_backdrop [[texture(1)]],
                                  texture2d<float> u_mask [[texture(2)]],
                                  sampler u_sampler [[sampler(0)]])
    {
        float4 C = in.color;
        if (uniforms.fx.y > 0.5) {
            uint2 coord = uint2(in.position.xy);
            C.a *= u_mask.read(coord).a;
        }

        float2 uv = hazeUv(in.uv, uniforms.fx, uniforms.hazeA, uniforms.hazeB);
        float4 r;

    #if MODE == 0
        r = (uniforms.fx.z > 0.5 ? blurTaps(uv, u_tex, u_sampler, uniforms.blur) : u_tex.sample(u_sampler, uv)) * C;
    #elif MODE == 100
        r = C;
    #elif MODE == 101
        float m = u_tex.sample(u_sampler, uv).r;
        float t = clamp((m - uniforms.params.x) * (1.0 / (uniforms.params.y - uniforms.params.x)), 0.0, 1.0);
        float f = clamp(abs(uniforms.params.z - t * t * (3.0 - 2.0 * t)), 0.0, 1.0);
        r = C * f;
    #else
        float4 S = u_tex.sample(u_sampler, uv);
        uint2 coord = uint2(in.position.xy);
        float4 D = u_backdrop.read(coord);
        float3 s = S.rgb;
        float3 d = D.rgb;
        float ca = C.a;
        float sa = S.a;
        float p1 = uniforms.params.y;
        float p2 = uniforms.params.z;
        float dodgeBlack = as_type<float>(0x3C40C0C1u);
        float3 rgb;

    #if MODE == 1          // add
        rgb = min(float3(1.0), d + ca * s);
    #elif MODE == 2        // addalpha
        rgb = min(float3(1.0), ca * s + d * (1.0 - ca * sa));
    #elif MODE == 4        // darken
        rgb = d + ca * (min(d, s) - d);
    #elif MODE == 5 || MODE == 17   // dodge / ps_dodge5 (PsColorDodge5)
    #if MODE == 5
        float k = ca * max(p2, sa);
    #else
        float k = ca * sa;
    #endif
        float3 den = 1.0 - s * k;
        float3 q = select(d * (1.0 / den), float3(1.0), den <= 0.0);
        rgb = select(min(q, float3(1.0)), float3(0.0), d < dodgeBlack);
    #elif MODE == 6        // lighten
        rgb = d + ca * (max(d, s) - d);
    #elif MODE == 7        // multiplicative
        float k = ca * max(p2, sa);
        rgb = d + k * (s * d - d);
    #elif MODE == 8        // opaque
        rgb = d + ca * (s - d);
    #elif MODE == 9        // screen
        float k = ca * max(p2, sa);
        rgb = 1.0 - (1.0 - d) * (1.0 - s * k);
    #elif MODE == 10       // sub (subtracts the inverse of S)
        rgb = max(float3(0.0), d + ca * (s - 1.0));
    #elif MODE == 11       // ps_add (vertex colour rgb, not alpha)
        rgb = min(float3(1.0), d + C.rgb * s);
    #elif MODE == 12       // ps_burn: s = 0 gives -inf or NaN, both 0 after v_max
        rgb = select(max(float3(0.0), (1.0 / s) * (d - 1.0) + 1.0), float3(0.0), s <= 0.0);
    #elif MODE == 13       // ps_darken
        rgb = min(d, s);
    #elif MODE == 14       // ps_diff
        rgb = abs(d - s);
    #elif MODE == 15       // ps_diff5
        rgb = abs(d - s * (ca * sa));
    #elif MODE == 16       // ps_dodge: s = 1 gives +inf or NaN, both 1 after v_min
        rgb = select(min(float3(1.0), d * (1.0 / (1.0 - s))), float3(1.0), s >= 1.0);
    #elif MODE == 18       // ps_exclusion
        rgb = s + d - 2.0 * d * s;
    #elif MODE == 19       // ps_hardlight on X = C.rgb * S
        float3 x = C.rgb * s;
        rgb = select(2.0 * x * d, 1.0 - 2.0 * (1.0 - d) * (1.0 - x), x >= 0.5);
    #elif MODE == 20       // ps_lighten
        rgb = max(d, s);
    #elif MODE == 21       // ps_multi
        rgb = d * s;
    #elif MODE == 22       // ps_overlay
        rgb = select(2.0 * d * s, 1.0 - 2.0 * (1.0 - d) * (1.0 - s), d >= 0.5);
    #elif MODE == 23       // ps_screen
        rgb = s + d - d * s;
    #elif MODE == 24       // ps_softlight: |d| ^ e, e = s >= 0.5 ? 1 / (2 s) : 2 (1 - s)
        float3 e = select(2.0 * (1.0 - s), 1.0 / (2.0 * s), s >= 0.5);
        float3 ad = abs(d);
        rgb = select(exp2(log2(max(ad, float3(1e-30))) * e), float3(0.0), ad <= 0.0);
    #elif MODE == 25       // ps_sub (linear burn)
        rgb = max(float3(0.0), d + s - 1.0);
    #else
    #error unknown blend mode
    #endif

    #if MODE == 1 || MODE == 2 || (MODE >= 4 && MODE <= 10) || MODE == 15 || MODE == 17
        float a = 1.0 + p1 * (D.a - 1.0);           // "nexl" family
    #else
        float kk = ca * sa;
        float a = kk + p1 * (D.a - kk);              // "PS" family
    #endif
        r = float4(rgb, a);
    #endif

        return exportMrt0(r);
    }
    """

    /// Creates the standard vertex descriptor for quads.
    public static func makeVertexDescriptor() -> MTLVertexDescriptor {
        let desc = MTLVertexDescriptor()
        // Attribute 0: position (float2)
        desc.attributes[0].format = .float2
        desc.attributes[0].offset = 0
        desc.attributes[0].bufferIndex = 0

        // Attribute 1: uv (float2)
        desc.attributes[1].format = .float2
        desc.attributes[1].offset = 8
        desc.attributes[1].bufferIndex = 0

        // Attribute 2: color (uchar4Normalized)
        desc.attributes[2].format = .uchar4Normalized
        desc.attributes[2].offset = 16
        desc.attributes[2].bufferIndex = 0

        desc.layouts[0].stride = 20
        desc.layouts[0].stepFunction = .perVertex
        return desc
    }
}
