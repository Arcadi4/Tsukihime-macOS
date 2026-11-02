import Foundation
import TsukiCore

/// Kind of a glyph quad the block draw emits.
public enum QuadKind: UInt8, Sendable {
    /// Drop shadow (draw flag 0x10): black, alpha 0.66 * a, one unit down and right.
    case shadow
    /// Outline copy of the glyph (atlas v + 512).
    case outline
    /// The glyph fill in the record colour.
    case fill
}

/// One quad of a drawn text block, in text-space units.
public struct Quad: Sendable, Equatable {
    /// Shadow, outline or fill.
    public let kind: QuadKind
    /// Texture slot (font page = slot - 0x21).
    public let tex: Int
    /// Atlas rectangle left (inclusive corners as in the record; the outline adds 512 to v).
    public let u0: Int
    /// Atlas rectangle top.
    public let v0: Int
    /// Atlas rectangle right.
    public let u1: Int
    /// Atlas rectangle bottom.
    public let v1: Int
    /// Left edge of the quad.
    public let x: Double
    /// Top edge of the quad.
    public let y: Double
    /// Text-space units per texel, x.
    public let sx: Double
    /// Text-space units per texel, y.
    public let sy: Double
    /// Red.
    public let r: Int
    /// Green.
    public let g: Int
    /// Blue.
    public let b: Int
    /// Alpha.
    public let alpha: Double
    /// Index into `TextBlock.records`.
    public let record: Int

    /// Font page (slot - 0x21).
    public var page: Int { tex - 0x21 }

    public init(
        kind: QuadKind,
        tex: Int,
        u0: Int,
        v0: Int,
        u1: Int,
        v1: Int,
        x: Double,
        y: Double,
        sx: Double,
        sy: Double,
        r: Int,
        g: Int,
        b: Int,
        alpha: Double,
        record: Int
    ) {
        self.kind = kind
        self.tex = tex
        self.u0 = u0
        self.v0 = v0
        self.u1 = u1
        self.v1 = v1
        self.x = x
        self.y = y
        self.sx = sx
        self.sy = sy
        self.r = r
        self.g = g
        self.b = b
        self.alpha = alpha
        self.record = record
    }
}

/// The block draw (eboot VA 0xC8F50): line offsets, the reveal window, redaction-bar substitution and the
/// outline / fill / drop-shadow quads of a laid-out block (docs/formats/textbox.md 7; tools/tsuki/textbox.py
/// `line_offsets`, `block_quads`).
public enum BlockDraw {
    /// Drop shadow (config +0x28 "text shadow").
    public static let shadow = 0x10

    /// Set by the HUD for every message block.
    public static let always = 0x20

    /// Line x = x + (width_arg - line_width) / 2.
    public static let center = 0x100

    /// Line x = x + width_arg - line_width.
    public static let right = 0x200

    /// y += (height - total) / 2.
    public static let vCenter = 0x400

    /// y += height - total.
    public static let bottom = 0x800

    /// Outline pass (also needs config +0x26 "text outline" != 0).
    public static let outline = 0x1000

    /// Head/tail value that shows a whole block (VA 0x1A7130).
    public static let revealAll: Double = 768.0

    /// The `@b` mirrored x origin, non-English / English (VA 0x2D3260).
    private static let mirrorX: [Float] = [463.0, 565.0]

    /// The `@b` mirrored x origin of `lang` (VA 0x2D3260 / 0x2D3270: 565 in English, 463 otherwise).
    public static func mirrorOrigin(_ lang: Language) -> Float {
        mirrorX[lang == .en ? 1 : 0]
    }

    /// Font page from texture slot (slot - 0x21).
    public static func pageOf(_ tex: Int) -> Int {
        tex - 0x21
    }

    /// Fill colour bytes 1..3 built from the record colour word (VA 0xC9C87..0xC9D06).
    public static func rgb565Bytes(_ c: Int) -> (r: Int, g: Int, b: Int) {
        ((c >> 8) & 0xF8, (c >> 3) & 0xF8, (c << 3) & 0xF8)
    }

    /// Per-line x and y origins of a block drawn at (`x`, `y`)
    /// (VA 0xC8FE8..0xC9401): `y_i = y + sum_{j<i}(leading + line_height_j)` in float32, x centred or
    /// right-aligned on the width argument by draw flags 0x100 / 0x200, and the block centred / bottom-aligned
    /// inside its height by 0x400 / 0x800. Returns the total height too.
    public static func lineOffsets(_ block: TextBlock, _ x: Float, _ y: Float, _ drawFlags: Int = always) -> (xs: [Float], ys: [Float], total: Float) {
        let nl = block.nLines
        let lead = Float(block.leading)
        var acc: Float = 0
        var ys = [Float](repeating: 0, count: nl)
        for i in 0..<nl {
            ys[i] = acc + y
            acc += lead + (i < TextBlock.lineSlots ? block.lineHeight[i] : 0)
        }

        let flags = drawFlags | block.flags
        var xs = [Float](repeating: x, count: nl)
        if (flags & center) != 0 {
            let wa = Float(block.widthArg)
            for i in 0..<nl {
                xs[i] = (wa - block.lineWidth[i]) * 0.5 + x
            }
        } else if (flags & right) != 0 {
            let x0 = Float(block.widthArg) + x
            for i in 0..<nl {
                xs[i] = x0 - block.lineWidth[i]
            }
        }

        if (flags & (vCenter | bottom)) != 0 {
            var off = Float(block.height) - acc
            if (flags & vCenter) != 0 {
                off *= 0.5
            }

            for i in 0..<nl {
                ys[i] = off + ys[i]
            }
        }

        return (xs, ys, acc)
    }

    /// Redaction-bar pictures (VA 0xC9401..0xC9732): (tex, u0, v0, u1, v1) for every record.
    private static func substituteBars(_ recs: [GlyphRecord], _ head: Float) -> [(tex: Int, u0: Int, v0: Int, u1: Int, v1: Int)] {
        var count = 0
        for r in recs {
            if r.tex >= 0x5F && Float(r.ctr) <= head {
                count += 1
            }
        }

        let n = min(count, 21)
        let baseK = n >= 2 ? (n - 2) * (n - 3) / 2 + 2 * n - 3 : 0
        var output = [(tex: Int, u0: Int, v0: Int, u1: Int, v1: Int)]()
        output.reserveCapacity(recs.count)
        var kI = 0
        for r in recs {
            var t = r.tex
            var u0 = r.x
            var v0 = r.y
            var u1 = r.x2
            var v1 = r.y2
            if r.tex >= 0x61 && r.y >= 0xDB {
                let c = kI % 14
                t = 0x61
                u0 = c * 68
                v0 = 0xDB
                u1 = c * 68 + 0x43
                v1 = 0x123
                kI = (kI + 1) % 21
            } else if r.tex >= 0x5F {
                let k = baseK + kI
                t = 0x5F + k / 98
                u0 = k % 14 * 68
                v0 = k % 98 / 14 * 73
                u1 = u0 + 0x43
                v1 = v0 + 0x48
                kI = (kI + 1) % 21
            }

            output.append((t, u0, v0, u1, v1))
        }

        return output
    }

    /// The quads VA 0xC8F50 emits for a laid-out block drawn at (`x`, `y`) in
    /// text-space units. `head` / `tail` are the reveal positions (VA 0x1653E80 /
    /// 0x1653E84): a glyph whose counter is above head is not drawn, below tail fully, otherwise with alpha
    /// (head - ctr) / (head - tail). Order per glyph: drop shadow (draw flag 0x10), outline (draw flag 0x1000 and
    /// `outlineOption`), fill. The engine stops at the first glyph whose y is below y + height.
    public static func blockQuads(
        _ block: TextBlock,
        _ x: Float,
        _ y: Float,
        drawFlags: Int = outline | always,
        alpha: Double = 1.0,
        head: Double = revealAll,
        tail: Double = revealAll,
        textFade: Double = 1.0,
        outlineOption: Bool = true,
        instantOption: Bool = false,
        lang: Language = .ja,
        outlineRgb: (r: Int, g: Int, b: Int)? = nil
    ) -> [Quad] {
        let flags = drawFlags | block.flags
        let (xs, ys, _) = lineOffsets(block, x, y, flags)
        let hF = Float(head)
        let tF = Float(tail)
        let subs = substituteBars(block.records, hF)
        var output = [Quad]()
        output.reserveCapacity(block.records.count * 2)
        let wantOutline = (flags & outline) != 0 && outlineOption
        let (outR, outG, outB) = outlineRgb ?? (0, 0, 0)
        for ri in 0..<block.records.count {
            let r = block.records[ri]
            let (tex, u0, v0, u1, v1) = subs[ri]
            if v0 > 0x1FF {
                continue
            }

            let c = Float(r.ctr)
            if c > hF {
                continue
            }

            var aR: Float
            if tF > c {
                aR = 1.0
            } else if !(hF - tF > 0.0) {
                aR = 1.0
            } else {
                aR = (hF - c) / (hF - tF)
            }

            if instantOption && aR > 0.0 {
                aR = 1.0
            }

            if r.line < 0 || r.line >= ys.count {
                continue
            }

            let line = r.line
            var gx: Float
            if (r.flags & 0x10000) != 0 {
                // '@b': mirrored placement (VA 0xC9A9D)
                var wq = Float(u1 - u0)
                if u1 - u0 == 0x43 && tex == 0x5E {
                    wq += -5.0
                }

                gx = mirrorX[lang == .en ? 1 : 0] - r.dx - wq * r.sx
                gx += xs[line]
            } else {
                gx = xs[line] + r.dx
            }

            let gy = r.dy + ys[line]
            if gy > Float(block.height) + y {
                break
            }

            let fa = Double(aR * Float(alpha))
            if (flags & shadow) != 0 {
                output.append(Quad(
                    kind: .shadow,
                    tex: tex,
                    u0: u0,
                    v0: v0,
                    u1: u1,
                    v1: v1,
                    x: Double(gx) + 1.0,
                    y: Double(gy) + 1.0,
                    sx: Double(r.sx),
                    sy: Double(r.sy),
                    r: 0,
                    g: 0,
                    b: 0,
                    alpha: fa * 0.66,
                    record: ri
                ))
            }

            if wantOutline {
                let oa = 2.0 * max(0.0, textFade - 0.5) * Double(aR) * alpha * alpha
                output.append(Quad(
                    kind: .outline,
                    tex: tex,
                    u0: u0,
                    v0: v0 + 0x200,
                    u1: u1,
                    v1: v1 + 0x200,
                    x: Double(gx),
                    y: Double(gy),
                    sx: Double(r.sx),
                    sy: Double(r.sy),
                    r: outR,
                    g: outG,
                    b: outB,
                    alpha: oa,
                    record: ri
                ))
            }

            let (cr, cg, cb) = rgb565Bytes(r.color)
            output.append(Quad(
                kind: .fill,
                tex: tex,
                u0: u0,
                v0: v0,
                u1: u1,
                v1: v1,
                x: Double(gx),
                y: Double(gy),
                sx: Double(r.sx),
                sy: Double(r.sy),
                r: cr,
                g: cg,
                b: cb,
                alpha: fa,
                record: ri
            ))
        }

        return output
    }

    /// Appends the glyph quads of a laid-out block to a `DisplayList`.
    public static func addBlock(
        to list: DisplayList,
        block: TextBlock,
        x: Double,
        y: Double,
        alpha: Double = 1.0,
        head: Double = revealAll,
        tail: Double = revealAll,
        scaleY: Double = 1.0,
        offsetXPx: Double = 0.0,
        offsetYPx: Double = 0.0,
        textScale: Double = 3.0,
        textFade: Double = 1.0,
        outlineOption: Bool = true,
        instantOption: Bool = false,
        lang: Language = .ja,
        drawFlags: Int? = nil
    ) {
        let flags = drawFlags ?? (always | outline)
        let quads = blockQuads(
            block,
            Float(x),
            Float(y),
            drawFlags: flags,
            alpha: alpha,
            head: head,
            tail: tail,
            textFade: textFade,
            outlineOption: outlineOption,
            instantOption: instantOption,
            lang: lang
        )
        for q in quads {
            let page = q.page
            let pw = page == 0 ? 256.0 : 1024.0
            let w = Double(q.u1 - q.u0 + 1) * q.sx * textScale
            let h = Double(q.v1 - q.v0 + 1) * q.sy * scaleY
            let x0 = q.x * textScale + offsetXPx
            let y0 = q.y * scaleY + offsetYPx
            let u0 = Float(Double(q.u0) / pw)
            let v0 = Float(Double(q.v0) / pw)
            let u1 = Float(Double(q.u1 + 1) / pw)
            let v1 = Float(Double(q.v1 + 1) / pw)
            let clampedAlpha = UInt8(clamping: Int((q.alpha * 255.0).rounded()))
            let rgba = packRGBA8(UInt8(q.r), UInt8(q.g), UInt8(q.b), clampedAlpha)
            let cmd = DrawCommand(
                kind: .texturedQuad,
                target: 0,
                texture: TextureRef.glyphPage(language: Int(lang.rawValue), page: page),
                v0: Vertex(x: Float(x0), y: Float(y0), u: u0, v: v0, rgba: rgba),
                v1: Vertex(x: Float(x0 + w), y: Float(y0), u: u1, v: v0, rgba: rgba),
                v2: Vertex(x: Float(x0), y: Float(y0 + h), u: u0, v: v1, rgba: rgba),
                v3: Vertex(x: Float(x0 + w), y: Float(y0 + h), u: u1, v: v1, rgba: rgba)
            )
            list.add(cmd)
        }
    }
}
