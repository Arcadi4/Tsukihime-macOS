import Foundation
import TsukiCore

/// `Text_Layout` (eboot VA 0xC6C20): both passes for one text block, bit-exact in IEEE float32 in
/// the engine's operation order. Port of `tsuki.textbox.layout_box` (docs/formats/textbox.md 3-6),
/// which was verified record for record against the game's own function.
public enum TextLayout {
    /// '^' or an automatic wrap on this line index ends the text (VA 0xC7FCD, 0xC8BD0).
    public static let maxLineIndex = 31

    // Constants of the eboot (text VA = file offset - 0x2280). Values typed as the double the Python
    // oracle uses and narrowed to float32, exactly like numpy.float32(x).
    private static let sxDiv: Float = 0.33333334        // VA 0x2D2F94: sx, sy arguments are divided by 3
    private static let rubyDy: Float = -7.04            // VA 0x2D31A0
    private static let rubySx: Float = 0.1              // VA 0xC7C9A
    private static let rubySy: Float = 0.11
    private static let rubyW: Float = 0.1               // VA 0x2D2FD8: reading pen advance = w * 0.1
    private static let pInit: Float = -40.0             // VA 0x2D2F98: initial ruby overlap guard
    private static let kMinus160: Float = -160.0        // VA 0x2D2FB4: dash line_end margin
    private static let kEmpty: Float = 20.0             // VA 0x2D2FB0: height of an empty line = 20 * sy
    private static let kxBreak: Float = 69.0            // VA 0x2D2FA8: '@x' wrap sets the line height to 69 * sy
    private static let kx555: Float = 555.0             // VA 0x2D2FA4: English '@x' wrap threshold

    /// The scale table of `@h` / `@w` (VA 0x2D3730): ten float32 values, as the exact bit patterns
    /// of the eboot.
    public static let scaleTableBits: [UInt32] = [
        0x3EB00000, 0x3EBEAAAB, 0x3ECD5555, 0x3EDC0000, 0x3EEAAAAB,
        0x3EF95555, 0x3E6AAAAB, 0x3E840000, 0x3E92AAAA, 0x3EA15556,
    ]

    private static let scaleTable: [Float] = scaleTableBits.map { Float(bitPattern: $0) }

    /// The `@f` box widths (VA 0x2D3758).
    private static let fontMetricTable: [Int] = [480, 536, 524, 0]

    /// The `@c0..@c5` colour words (VA 0x2D34C0).
    private static let colorTable: [Int] = [0x632C, 0xF800, 0x345F, 0x1082, 0xAD55, 0x001F]

    /// The scale table of `@h` / `@w` as floats.
    public static var scales: [Float] { scaleTable }

    /// The `@f` box widths.
    public static var fontMetrics: [Int] { fontMetricTable }

    /// The `@c0..@c5` colour words.
    public static var colors: [Int] { colorTable }

    /// VA 0x538F0(block, width): the width the layout really uses. For blocks 4..8 and 79..89 (the
    /// message slots and the page history): 600 when the window index is 42; else 574 when the language is
    /// English and the width is 474; else the width unchanged.
    public static func mainBoxWidth(_ lang: Language, _ width: Int = 474, _ window: Int = 0, _ block: Int = 4) -> Int {
        if !((block >= 4 && block <= 8) || (block >= 79 && block <= 89)) {
            return width
        }

        if window == 42 {
            return 600
        }

        if lang == .en && width == 474 {
            return 574
        }

        return width
    }

    /// Lays out `text` (the message bytes without the terminating NUL).
    /// - Parameters:
    ///   - text: Message bytes with their markup.
    ///   - lang: Text language: English has no ruby and breaks at words.
    ///   - fonts: The glyph tables of the eboot.
    ///   - p: Call arguments; nil = the ordinary ADV message.
    public static func layout(_ text: ByteSpan, _ lang: Language, _ fonts: FontTables, _ p: LayoutParams? = nil) throws -> TextBlock {
        let params = p ?? LayoutParams()
        let langIndex = Int(lang.rawValue)
        let english = lang == .en
        let glyphs = fonts.for(lang)
        var b = Array(text)
        b.append(contentsOf: repeatElement(0, count: TextClassifier.padding))
        let pass1 = TextClassifier.classify(b, langIndex, params.flags, fonts.tags, english)
        let n = pass1.n
        let cls = pass1.classes
        let wl = pass1.wordLen
        let flags = params.flags
        let window = params.window
        var W = mainBoxWidth(lang, params.width, window, params.block)

        let sxa = Float(params.sx)
        let sya = Float(params.sy)
        let baseSx = sxDiv * sxa
        let baseSy = sxDiv * sya
        if n == 0 {
            // VA 0xC7375: no element -> return 0; the block is not (re)initialised and the end counter is not written.
            return TextBlock(
                n: 0,
                widthArg: params.width,
                height: params.height,
                flags: flags,
                spacing: params.spacing,
                leading: params.leading,
                boxWidth: W,
                sx: baseSx,
                sy: baseSy,
                nLines: 0,
                lastGlyphLine: 0,
                lineGlyphs: [UInt16](repeating: 0, count: TextBlock.lineSlots),
                lineWidth: [Float](repeating: 0, count: TextBlock.lineSlots),
                lineHeight: [Float](repeating: 0, count: TextBlock.lineSlots),
                records: [],
                classes: cls,
                wordLen: wl,
                endCtr: -1,
                yField: 0,
                empty: true
            )
        }

        let normalWindow = params.normalWindow ?? (window < 3)
        var curSx = baseSx
        var curSy = baseSy
        var style = (flags >> 19) & 2
        var anim = 0
        var flagB = false
        var literalCaret = false
        let spacingF = Float(params.spacing)
        let bit17 = (flags >> 17) & 1

        var recs = [GlyphRecord]()
        recs.reserveCapacity(n)
        var lineGlyphs = [UInt16](repeating: 0, count: TextBlock.lineSlots)
        var lineWidth = [Float](repeating: 0, count: TextBlock.lineSlots)
        var lineHeight = [Float](repeating: 0, count: TextBlock.lineSlots)
        var nlines = 0
        var lastGlyphLine = 0
        var yField = 0

        var ctr = 1
        var savedCtr = 0
        var ext = 0
        var colw = params.color & 0xFFFF
        var hangcap = 0
        var hang = 0
        var nowrap = 0
        var kind = 0
        var pen: Float = 0
        var maxh: Float = 0
        var line = 0
        var P: Float = pInit
        var off: Float = 0
        var rmin: Float = 0
        var rpen: Float = 0
        var rCtr = 0
        var rLine = 0
        var rLineNext = 0
        var bu = 0
        var ru = 0
        var justWrapped = 0
        var pos = 0
        var prevPos = -1
        var i = 0
        var stale: Glyph = Glyph(consumed: 0, tex: 0, x: 0, y: 0, w: 0, h: 0, adj: 0.0)
        var haveStale = false

        while i < n {
            let c = Int(b[pos])
            var q = pos + 1
            if c == 0x40 {
                // '@' (VA 0xC77D0)
                let op = Int(b[pos + 1])
                q = pos + 2
                switch op {
                case 0x54, 0x6B:
                    break
                case 0x31:
                    b[pos + 2] = 0x5E
                    literalCaret = true
                case 0x32:
                    b[pos + 2] = 0x29
                case 0x61:
                    q = pos + 3
                    if (flags & 0x40) == 0 {
                        anim = Int(b[pos + 2] - 0x30)
                    }
                case 0x62:
                    if (flags & 0x40) == 0 {
                        flagB = true
                    }
                case 0x63:
                    q = pos + 3
                    let v = Int(b[pos + 2] - 0x30) & 0xFF
                    if v == 0 {
                        colw = params.color & 0xFFFF
                        ext = 0
                    } else if v <= 5 {
                        colw = colorTable[v]
                    } else if v < 10 {
                        ext = v
                    }
                case 0x66:
                    q = pos + 3
                    let v = Int(b[pos + 2] - 0x30) & 0xFF
                    W = v < fontMetricTable.count ? fontMetricTable[v] : 0
                case 0x68, 0x77:
                    q = pos + 3
                    let v = Int(b[pos + 2] - 0x30) & 0xFF
                    let sc = v < scaleTable.count ? scaleTable[v] : 0
                    if op == 0x68 {
                        curSy = sya * sc
                    } else {
                        curSx = sxa * sc
                    }
                case 0x69:
                    if english {
                        switch style {
                        case 1: style = 4
                        case 2: style = 5
                        default: style = 3
                        }
                    } else {
                        style = 1
                    }
                case 0x67:
                    style = 1
                case 0x7A:
                    style = 2
                case 0x6C:
                    ctr = savedCtr
                case 0x75:
                    savedCtr = ctr
                case 0x74:
                    ctr = 0
                case 0x6F:
                    nowrap = 1
                case 0x70:
                    nowrap = 0
                case 0x72:
                    // VA 0xC87B9
                    anim = 0
                    flagB = false
                    ext = 0
                    curSx = baseSx
                    curSy = baseSy
                    style = (style == 4) ? 1 : (style == 5 ? 2 : 0)
                    colw = params.color & 0xFFFF
                case 0x73:
                    // VA 0xC8836
                    var sign = 1
                    var val: UInt32 = 0
                    var r = pos + 3
                    var ended = false
                    for _ in 0..<0x100 {
                        let d = b[r - 1]
                        if d == 0 || d == 0x29 || d == 0x2C {
                            ended = true
                            break
                        }
                        if d == 0x2D {
                            sign = -1
                        } else if d >= 0x30 && d <= 0x39 {
                            val = val &* 10 &+ UInt32(d - 0x30)
                        }
                        r += 1
                    }
                    q = ended ? r : pos + 0x102
                    let v = sign < 0 ? -Int(val) : Int(val)
                    let sc = Float(v) * 0.015625
                    curSx = sc
                    curSy = sc
                case 0x78:
                    // VA 0xC88E1
                    let d = b[pos + 2]
                    if d >= 0x30 && d <= 0x39 {
                        if (flags & 0x40) != 0 {
                            q = pos + 3
                            if b[pos + 3] >= 0x30 && b[pos + 3] <= 0x39 {
                                q = pos + 4
                                if b[pos + 4] >= 0x30 && b[pos + 4] <= 0x39 {
                                    q = pos + 5
                                }
                            }
                        } else {
                            var x1 = Float(d - 0x30)
                            q = pos + 3
                            if b[pos + 3] >= 0x30 && b[pos + 3] <= 0x39 {
                                x1 = x1 * 10.0 + Float(b[pos + 3] - 0x30)
                                q = pos + 4
                                if b[pos + 4] >= 0x30 && b[pos + 4] <= 0x39 {
                                    x1 = x1 * 10.0 + Float(b[pos + 4] - 0x30)
                                    q = pos + 5
                                }
                            }
                            pen = x1
                        }
                    } else if (flags & 0x40) == 0 {
                        let sxv = Float(params.savedX)
                        let limit = curSx * -64.0 + Float(W)
                        if sxv > limit || (english && sxv > kx555) {
                            // wrap onto a new line (VA 0xC896F)
                            lineHeight[line] = curSy * kxBreak
                            hang = 0
                            justWrapped = 1
                            nlines += 1
                            line += 1
                            pen = 0
                            maxh = 0
                        } else {
                            pen = sxv
                        }
                    }
                case 0x79:
                    // VA 0xC89E4
                    yField = 0
                    let d = b[pos + 2]
                    if d >= 0x30 && d <= 0x39 {
                        yField = Int(d - 0x30)
                        q = pos + 3
                        if b[pos + 3] >= 0x30 && b[pos + 3] <= 0x39 {
                            yField = yField * 10 + Int(b[pos + 3] - 0x30)
                            q = pos + 4
                            if b[pos + 4] >= 0x30 && b[pos + 4] <= 0x39 {
                                yField = yField * 10 + Int(b[pos + 4] - 0x30)
                                q = pos + 5
                            }
                        }
                    }
                default:
                    // VA 0xC8625: an unknown code skips a "(...)" group
                    if b[pos + 2] == 0x28 {
                        var r = pos + 4
                        for _ in 0..<0xFF {
                            let d = b[r - 1]
                            if d == 0 {
                                break
                            }
                            if d == 0x29 {
                                q = r
                                break
                            }
                            r += 1
                        }
                    }
                }

                prevPos = pos
                pos = q
                i += 1
                continue
            }

            if c == 0x5E && !literalCaret {
                // '^' (VA 0xC7F3D)
                if justWrapped != 0 {
                    justWrapped = 0
                    nowrap = 0
                } else {
                    let brk = (flags & 0x4000) == 0 && ((flags & 0x8000) == 0 || pen != 0)
                    if brk {
                        nlines += 1
                        if lineHeight[line] == 0 {
                            lineHeight[line] = curSy * kEmpty
                        }
                        if line > 30 {
                            break
                        }
                        line += 1
                        hang = 0
                        pen = 0
                        maxh = 0
                    }
                    off = 0
                    nowrap = 0
                    justWrapped = 0
                }

                prevPos = pos
                pos = q
                i += 1
                continue
            }

            if c == 0 {
                break
            }

            if c < 0x80 && c != 0x5E {
                if !english && c == 0x3C {
                    // '<' ruby start (VA 0xC7717)
                    rLineNext = line + 1
                    var k = 0
                    bu = 0
                    let baseOff = pos + 1
                    while true {
                        let d = b[baseOff + k]
                        if d <= 0x5C {
                            if d == 0 || d == 0x29 {
                                break
                            }
                        } else {
                            if d == 0x5D {
                                k += 1
                                bu = 2
                                continue
                            }
                            if d == 0x7C {
                                k += 1
                                break
                            }
                        }

                        let (key, _) = TextClassifier.decode(b, baseOff + k)
                        k += key < 0x100 ? 1 : key <= 0xFFFF ? 2 : key <= 0xFFFFFF ? 3 : 4
                        bu += (TextClassifier.isWide(key) ? 1 : 0) + 1
                    }

                    ru = 0
                    while true {
                        let d = b[baseOff + k]
                        if d == 0 || d == 0x29 || d == 0x3E {
                            break
                        }

                        let (key, _) = TextClassifier.decode(b, baseOff + k)
                        k += key < 0x100 ? 1 : key <= 0xFFFF ? 2 : key <= 0xFFFFFF ? 3 : 4
                        ru += (TextClassifier.isWide(key) ? 1 : 0) + 1
                    }

                    let S = curSx * 32.0 * Float(bu) + Float(ru) * Float(-3.392)
                    let half = S * 0.5
                    if P - half > 0 {
                        off = P
                        P -= S
                    } else {
                        off = half
                        P = -half
                    }

                    kind = 1
                    rmin = 0
                    rpen = pen
                    rCtr = ctr
                    rLine = line
                    prevPos = pos
                    pos = q
                    i += 1
                    continue
                }

                if c == 0x7C && kind > 0 {
                    // '|' (VA 0xC7EE7)
                    if kind == 1 {
                        kind = 2
                        if (flags & 0x2000) != 0 {
                            while true {
                                let d = b[q]
                                q += 1
                                if d == 0 || d == 0x3E {
                                    break
                                }
                            }
                            kind = 0
                        }
                    }

                    prevPos = pos
                    pos = q
                    i += 1
                    continue
                }

                if !english && c == 0x3E {
                    // '>' (VA 0xC82D2)
                    kind = 0
                    prevPos = pos
                    pos = q
                    i += 1
                    continue
                }
            }

            if c == 0x5E {
                literalCaret = false
            }

            // ---- glyph (VA 0xC7824) ----
            let wF = Float(W)
            var lineEnd = false
            if pen >= curSx * kMinus160 + wF {
                let m = cmod10(i + 1 < TextClassifier.elementBudget ? Int(cls[i + 1]) : 0)
                if m != 2 {
                    lineEnd = m != 3 && nowrap == 0 && kind < 2
                }
            }

            let lineStart = 0 >= pen
            let variant = LanguageGlyphs.dashVariantAt(ByteSpan(b), pos, prevPos, lineStart, lineEnd, flagB)
            let g: Glyph
            if variant >= 0 {
                g = glyphs.dashGlyph(variant, style, kind, Double(curSx))
            } else {
                let fetched = (try? glyphs.charGlyph(ByteSpan(b), pos, style, kind, Double(curSx)))
                    ?? Glyph(consumed: 0, tex: 0xFFFF, x: 0, y: 0, w: 0, h: 0, adj: 0.0)
                if fetched.consumed == 0 {
                    // invalid lead byte: the engine leaves its outputs untouched
                    let basis = haveStale ? stale : Glyph(consumed: 0, tex: 0xFFFF, x: 0, y: 0, w: LanguageGlyphs.cell, h: LanguageGlyphs.cell, adj: 0.0)
                    g = Glyph(consumed: 0, tex: basis.tex, x: basis.x, y: basis.y, w: basis.w, h: basis.h, adj: basis.adj)
                } else {
                    g = fetched
                }
            }

            stale = g
            haveStale = true
            let adj = Float(g.adj)
            var fl = 1 | (style == 1 ? 4 : 0) | styleFlags(style)
            if variant < 0 && anim != 0 {
                fl |= 8
            }
            if flagB {
                fl |= 0x10000
            }

            let w = g.w
            let h = g.h
            let x2 = (g.x + w - 1) & 0xFFFF
            let y2 = (g.y + h - 1) & 0xFFFF
            var nxtCls: Int
            var wrapI: Int
            if kind >= 2 {
                // ruby reading (VA 0xC7BA1)
                let rctr = bu / 3 + 1 + rCtr
                var x = rpen + off + adj
                let baseX: Float
                if x > wF + Float(-6.4) {
                    off = 0
                    rLine = rLineNext
                    x = rmin + 0 + adj
                    baseX = rmin
                    P = pInit
                } else {
                    baseX = rpen
                }

                recs.append(GlyphRecord(
                    index: i,
                    flags: fl | 2,
                    color: colw,
                    ext: ext,
                    line: rLine,
                    tex: g.tex & 0xFFFF,
                    x: g.x,
                    y: g.y,
                    x2: x2,
                    y2: y2,
                    ctr: rctr & 0xFFFF,
                    dx: x,
                    dy: rubyDy,
                    sx: rubySx,
                    sy: rubySy
                ))
                rpen = Float(w) * rubyW + adj + baseX
                nxtCls = i + 1 < TextClassifier.elementBudget ? Int(cls[i + 1]) : 0
                wrapI = i
            } else {
                if kind == 1 {
                    rmin = pen < rmin ? pen : rmin
                }

                let dx = pen + adj
                recs.append(GlyphRecord(
                    index: i,
                    flags: fl,
                    color: colw,
                    ext: ext,
                    line: line,
                    tex: g.tex & 0xFFFF,
                    x: g.x,
                    y: g.y,
                    x2: x2,
                    y2: y2,
                    ctr: ctr & 0xFFFF,
                    dx: dx,
                    dy: 0,
                    sx: curSx,
                    sy: curSy
                ))
                let adv = Float(w - 3) * curSx + spacingF
                pen = adv + dx + curSx * -3.0
                lineWidth[line] = pen
                let hh = Float(h - 4) * curSy
                if hh > maxh {
                    lineHeight[line] = hh
                    maxh = hh
                }

                ctr += 1
                lastGlyphLine = line
                lineGlyphs[line] = UInt16(truncatingIfNeeded: Int(lineGlyphs[line]) + 1)
                if kind == 0 {
                    P -= adv
                }

                nxtCls = i + 1 < TextClassifier.elementBudget ? Int(cls[i + 1]) : 0
                wrapI = i
                if kind == 1 {
                    // last base glyph followed by '|': look past the reading (VA 0xC7DF2..0xC7EDF)
                    let lead = Int(b[pos])
                    let nb = lead < 0x80 ? 1 : (lead & 0xE0) == 0xC0 ? 2 : (lead & 0xF0) == 0xE0 ? 3 : (lead & 0xF8) == 0xF0 ? 4 : 0
                    if b[pos + nb] == 0x7C && n - i >= 3 {
                        var k = pos + nb + 1
                        var cnt = 0
                        let limit = n - 2 - i
                        var found = false
                        while cnt != limit {
                            let d = Int(b[k])
                            if d < 0x80 {
                                if d == 0x3E {
                                    found = true
                                    break
                                }
                                k += 1
                            } else if (d & 0xE0) == 0xC0 {
                                k += 2
                            } else if (d & 0xF0) == 0xE0 {
                                k += 3
                            } else if (d & 0xF8) == 0xF0 {
                                k += 4
                            }
                            cnt += 1
                        }

                        if found {
                            wrapI = cnt + 2 + i
                            let idx = cnt + 3 + i
                            nxtCls = idx < TextClassifier.elementBudget ? Int(cls[idx]) : 0
                        }
                    }
                }
            }

            // ---- automatic wrap (VA 0xC7FFD..0xC8BD0) ----
            let consumed = g.consumed
            prevPos = pos
            pos += consumed
            i += 1
            let res = wrap(i - 1, wrapI, nxtCls, cls, wl, n, pen, wF, curSx, english, nowrap, kind, hang, hangcap, flags, bit17, normalWindow)
            hang = res.hang
            hangcap = res.hangCap
            justWrapped = res.justWrapped
            if res.break {
                nlines += 1
                if lineHeight[line] == 0 {
                    lineHeight[line] = curSy * kEmpty
                }
                line += 1
                hang = 0
                pen = 0
                maxh = 0
            }

            if line > maxLineIndex {
                break
            }
        }

        nlines += 1
        return TextBlock(
            n: n,
            widthArg: params.width,
            height: params.height,
            flags: flags,
            spacing: params.spacing,
            leading: params.leading,
            boxWidth: W,
            sx: baseSx,
            sy: baseSy,
            nLines: nlines,
            lastGlyphLine: lastGlyphLine,
            lineGlyphs: lineGlyphs,
            lineWidth: lineWidth,
            lineHeight: lineHeight,
            records: recs,
            classes: cls,
            wordLen: wl,
            endCtr: ctr,
            yField: yField,
            empty: false
        )
    }

    /// Convenience overload taking `[UInt8]`.
    public static func layout(_ text: [UInt8], _ lang: Language, _ fonts: FontTables, _ p: LayoutParams? = nil) throws -> TextBlock {
        try layout(ByteSpan(text), lang, fonts, p)
    }

    private static func styleFlags(_ style: Int) -> Int {
        switch style {
        case 2: return 0x100000
        case 3: return 0x200000
        case 4: return 0x400000
        case 5: return 0x600000
        default: return 0
        }
    }

    /// Signed C remainder of the (signed char) class value by 10.
    private static func cmod10(_ c: Int) -> Int {
        let s = c >= 128 ? c - 256 : c
        return s % 10
    }

    private struct WrapResult {
        let `break`: Bool
        let hang: Int
        let hangCap: Int
        let justWrapped: Int
    }

    /// Automatic wrap decision after a glyph (VA 0xC7FFD..0xC8BD0). `iElem` is the glyph's
    /// element index; `iLook` is r13, the start of the look-ahead (the '>' of a ruby
    /// group after its last base glyph, else `iElem`); `nxt` is the class
    /// of the element after `iLook`.
    private static func wrap(
        _ iElem: Int, _ iLook: Int, _ nxt: Int, _ cls: [UInt8], _ wl: [UInt16], _ n: Int,
        _ pen: Float, _ W: Float, _ sx: Float, _ english: Bool,
        _ nowrap: Int, _ kind: Int, _ hang: Int, _ hangcap: Int, _ flags: Int, _ bit17: Int, _ normalWindow: Bool
    ) -> WrapResult {
        let enabled = nowrap == 0 && kind < 2
        if !enabled {
            return WrapResult(break: false, hang: hang, hangCap: hangcap, justWrapped: 0)
        }

        var lim0: Float
        var lim1: Float
        if english {
            lim0 = sx * -64.0 + W
            lim1 = sx * -192.0 + lim0
            let wlen = iElem < TextClassifier.elementBudget ? Int(wl[iElem]) : 0
            if wlen != 0 {
                let x2 = Float(wlen + 1) * -32.0 * sx + W
                if x2 < lim0 {
                    lim1 = x2
                }
                lim0 = x2 < lim0 ? x2 : lim0
            }
        } else {
            lim0 = sx * -96.0 + W
            lim1 = lim0
        }

        let nxtS = nxt >= 128 ? nxt - 256 : nxt
        let lookX: Float
        if pen > lim1 {
            if pen > lim0 {
                // past the margin: kinsoku / word rules (VA 0xC80D8, 0xC8A94)
                var cap = 1
                var al = 1
                if (flags & 0x20000) != 0 {
                    al = bit17
                } else if english {
                    al = bit17
                } else {
                    let curc = iElem < TextClassifier.elementBudget ? Int(cls[iElem]) : 0
                    cap = 7
                    if !(curc == 0x71 || nxt == 0x71) {
                        if curc == 0x0E {
                            cap = 6
                        } else if curc == 0x0D {
                            cap = hangcap >= 7 ? 1 : 0
                        } else {
                            cap = (curc == 2 && nxt == 2) ? 7 : 1
                        }
                    }
                }

                let newHangCap = cap
                let mNext = cmod10(nxt)
                if mNext == 2 || mNext == 3 {
                    if al == 0 || cap > hang {
                        return englishLookahead(pen, hang + 1, newHangCap, iLook, nxt, cls, n, W, sx, english, normalWindow)
                    }
                    return WrapResult(break: true, hang: hang, hangCap: newHangCap, justWrapped: 1)
                }

                let cur = iElem < TextClassifier.elementBudget ? Int(cls[iElem]) : 0
                if cmod10(cur) != 4 {
                    return WrapResult(break: true, hang: hang, hangCap: newHangCap, justWrapped: 1)
                }

                if al != 0 && cap <= hang {
                    return WrapResult(break: true, hang: hang, hangCap: newHangCap, justWrapped: 1)
                }

                return englishLookahead(pen, hang + 1, newHangCap, iLook, nxt, cls, n, W, sx, english, normalWindow)
            }

            // English: lim1 < pen <= lim0 (VA 0xC82A7)
            if nxtS > 1 {
                if (nxtS - 4) % 10 == 0 && nxtS >= 4 {
                    if pen > sx * -128.0 + lim0 {
                        return WrapResult(break: true, hang: hang, hangCap: hangcap, justWrapped: 1)
                    }
                }
                lookX = pen
            } else {
                let step0 = nxtS == 0 ? sx * 32.0 + 3.0 : sx * 64.0
                var x4 = step0 + pen
                if iLook + 2 < n {
                    let step = sx * 32.0 + 3.0
                    var k = iLook + 2
                    for _ in 0..<(n - 2 - iLook) {
                        let d = k < TextClassifier.elementBudget ? Int(cls[k]) : 0
                        if cmod10(d) != 2 {
                            break
                        }
                        if x4 > lim0 {
                            return WrapResult(break: true, hang: hang, hangCap: hangcap, justWrapped: 1)
                        }
                        x4 = (d == 2 ? step : sx * 64.0) + x4
                        k += 1
                    }
                }
                lookX = x4
            }

            return englishLookahead(lookX, hang, hangcap, iLook, nxt, cls, n, W, sx, english, normalWindow)
        }

        return englishLookahead(pen, hang, hangcap, iLook, nxt, cls, n, W, sx, english, normalWindow)
    }

    /// VA 0xC817F: in the normal (full-screen) window, English text past 3/4 of the box breaks before a
    /// word whose estimated width would end beyond W + 2 * (32 * sx + 3).
    private static func englishLookahead(
        _ x: Float, _ hang: Int, _ hangcap: Int, _ iCur: Int, _ nxt: Int,
        _ cls: [UInt8], _ n: Int, _ W: Float, _ sx: Float, _ english: Bool, _ normalWindow: Bool
    ) -> WrapResult {
        if !normalWindow {
            return WrapResult(break: false, hang: hang, hangCap: hangcap, justWrapped: 0)
        }
        if !(x > W * 3.0 * 0.25) {
            return WrapResult(break: false, hang: hang, hangCap: hangcap, justWrapped: 0)
        }
        if !english {
            return WrapResult(break: false, hang: hang, hangCap: hangcap, justWrapped: 0)
        }
        if nxt != 0 {
            return WrapResult(break: false, hang: hang, hangCap: hangcap, justWrapped: 0)
        }
        if iCur + 2 >= n {
            return WrapResult(break: false, hang: hang, hangCap: hangcap, justWrapped: 0)
        }

        let s32 = sx * 32.0
        var acc = s32 + x + 3.0
        let step = s32 + 3.0
        let lim = step + step + W
        var k = iCur + 2
        for _ in 0..<(n - 2 - iCur) {
            let d = k < TextClassifier.elementBudget ? Int(cls[k]) : 0
            if d == 1 || (d != 0 && d > 5) {
                acc = sx * 64.0 + acc
            } else if d == 0 {
                return WrapResult(break: false, hang: hang, hangCap: hangcap, justWrapped: 0)
            } else {
                acc = step + acc
            }

            if acc > lim {
                return WrapResult(break: true, hang: hang, hangCap: hangcap, justWrapped: 1)
            }

            k += 1
        }

        return WrapResult(break: false, hang: hang, hangCap: hangcap, justWrapped: 0)
    }
}
