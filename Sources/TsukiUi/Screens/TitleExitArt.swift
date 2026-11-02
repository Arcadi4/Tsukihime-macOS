// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Ported from knife (https://github.com/AuroraWright/knife) by AuroraWright
import Foundation
import TsukiEngine

/// The ink columns of one letter in a cell, inclusive.
public struct LetterSpan: Equatable, Sendable {
    public var left: Int
    public var right: Int

    public var Left: Int { left }
    public var Right: Int { right }

    public init(left: Int, right: Int) {
        self.left = left
        self.right = right
    }

    public init(_ left: Int, _ right: Int) {
        self.left = left
        self.right = right
    }

    /// The number of columns.
    public var width: Int { right - left + 1 }
    public var Width: Int { width }
}

/// What `TitleExitArt.composeState` measured and did.
public struct ExitLayout: Equatable, Sendable {
    public var gap: Int
    public var centre: Float
    public var letters: [LetterSpan]
    public var rowTop: Int
    public var rowBottom: Int
    public var eSource: String
    public var iSource: String
    public var glowSum: Float

    public var Gap: Int { gap }
    public var Centre: Float { centre }
    public var Letters: [LetterSpan] { letters }
    public var RowTop: Int { rowTop }
    public var RowBottom: Int { rowBottom }
    public var ESource: String { eSource }
    public var ISource: String { iSource }
    public var GlowSum: Float { glowSum }

    public init(gap: Int, centre: Float, letters: [LetterSpan], rowTop: Int, rowBottom: Int, eSource: String, iSource: String, glowSum: Float) {
        self.gap = gap
        self.centre = centre
        self.letters = letters
        self.rowTop = rowTop
        self.rowBottom = rowBottom
        self.eSource = eSource
        self.iSource = iSource
        self.glowSum = glowSum
    }
}

/// The EXIT item of the title, built at run time from the player's own TITLE_PARTS art.
public enum TitleExitArt {
    public static let cellWidth: Int = 296
    public static let CellWidth: Int = cellWidth
    public static let cellHeight: Int = 72
    public static let CellHeight: Int = cellHeight
    public static let sheetWidth: Int = 968
    public static let SheetWidth: Int = sheetWidth
    public static let sheetHeight: Int = 472
    public static let SheetHeight: Int = sheetHeight
    public static let ink: Int = 128
    public static let Ink: Int = ink
    public static let glowReach: Int = 28
    public static let GlowReach: Int = glowReach
    public static let counterDip: Int = 5
    public static let CounterDip: Int = counterDip

    private static let minGap: Int = 6
    private static let maxGap: Int = 20
    private static let farApart: Float = 20.0
    private static let wordNewGame: Int = 0
    private static let wordLoadGame: Int = 1
    private static let wordConfig: Int = 2
    private static let wordGallery: Int = 3
    private static let wordContinue: Int = 4

    private static let cellTop: [Int] = [24, 112, 200, 288, 376]
    private static let letterCounts: [Int] = [7, 8, 6, 7, 8]
    private static let wordNames: [String] = ["NEW GAME", "LOAD GAME", "CONFIG", "GALLERY", "CONTINUE"]

    public static func compose(_ sheet: Picture) -> (normal: UiComposedPicture, cursor: UiComposedPicture)? {
        if sheet.width != sheetWidth || sheet.height != sheetHeight {
            return nil
        }

        let rgba = UiComposed.assemble(sheet)
        var layout0: ExitLayout?
        var layout1: ExitLayout?
        guard let normal = composeState(rgba, 0, layout: &layout0),
              let cursor = composeState(rgba, 1, layout: &layout1) else {
            return nil
        }

        return (UiComposedPicture(width: cellWidth, height: cellHeight, rgba: normal),
                UiComposedPicture(width: cellWidth, height: cellHeight, rgba: cursor))
    }

    public static func Compose(_ sheet: Picture) -> (normal: UiComposedPicture, cursor: UiComposedPicture)? {
        compose(sheet)
    }

    public static func composeState(_ sheet: [UInt8], _ column: Int, layout: inout ExitLayout?) -> [UInt8]? {
        layout = nil
        guard let words = words(sheet, column) else {
            return nil
        }

        let cont = words[wordContinue]
        let gal = words[wordGallery]
        if gal.rowTop != cont.rowTop || gal.rowBottom != cont.rowBottom {
            return nil
        }

        var gaps: [Int] = []
        var centre: Float = 0
        for w in words {
            for i in 1..<w.letters.count {
                let g = w.letters[i].left - w.letters[i - 1].right - 1
                if g >= minGap && g <= maxGap {
                    gaps.append(g)
                }
            }
            if let first = w.letters.first, let last = w.letters.last {
                centre += Float(first.left + last.right) / 2.0
            }
        }

        if gaps.isEmpty {
            return nil
        }

        gaps.sort()
        let gap = gaps[gaps.count / 2]
        centre /= Float(words.count)

        let eCandidates = [(wordNewGame, 1), (wordLoadGame, 7), (wordContinue, 7)]
        let e = crispest(words, eCandidates, cont)
        let iSource = crispest(words, [(wordConfig, 4), (wordContinue, 4)], cont)
        let t = (wordContinue, 3)
        let y = (wordGallery, 6)
        let sources = [e, y, iSource, t]
        let yInk = gal.letters[6]
        let (yTop, yBottom) = gal.letterRows(yInk)
        if yTop + yBottom != cont.rowTop + cont.rowBottom {
            return nil
        }

        var total = 3 * gap
        for (w, l) in sources {
            total += words[w].letters[l].width
        }

        let left = Int(floor(centre - (Float(total) / 2.0) + 0.5))
        if left < 2 || left + total > cellWidth - 2 {
            return nil
        }

        var placed: [LetterSpan] = Array(repeating: LetterSpan(0, 0), count: 4)
        var x = left
        for k in 0..<4 {
            let w = words[sources[k].0].letters[sources[k].1].width
            placed[k] = LetterSpan(x, x + w - 1)
            x += w + gap
        }

        let glow = GlowModel.of(words)

        var cell = [UInt8](repeating: 0, count: cellWidth * cellHeight * 4)
        let rowTop = cont.rowTop
        let rowBottom = cont.rowBottom
        for k in 0..<4 {
            let src = words[sources[k].0]
            let span = src.letters[sources[k].1]
            copyBox(src.rgba, span, rowTop, rowBottom, &cell, placed[k].left)
        }

        mirrorLowerHalf(&cell, placed[1], rowTop, rowBottom, yTop + yBottom)
        let composed = WordCell(cell, placed, rowTop, rowBottom)
        glow.paint(composed)
        cell = composed.rgba

        layout = ExitLayout(
            gap: gap,
            centre: centre,
            letters: placed,
            rowTop: rowTop,
            rowBottom: rowBottom,
            eSource: "\(wordNames[e.0])[\(e.1)]",
            iSource: "\(wordNames[iSource.0])[\(iSource.1)]",
            glowSum: glow.sum
        )
        return cell
    }

    static func words(_ sheet: [UInt8], _ column: Int) -> [WordCell]? {
        if sheet.count < sheetWidth * sheetHeight * 4 || column < 0 || column > 2 {
            return nil
        }

        var words: [WordCell] = []
        words.reserveCapacity(cellTop.count)
        for k in 0..<cellTop.count {
            let w = WordCell.cut(sheet, 24 + (312 * column), cellTop[k])
            if w.letters.count != letterCounts[k] || w.rowTop < 1 || w.rowBottom >= cellHeight - 1 {
                return nil
            }
            words.append(w)
        }

        return words
    }

    public static func repaintGlow(_ sheet: [UInt8], _ column: Int, _ word: Int) -> [UInt8]? {
        guard let words = words(sheet, column), word >= 0, word < words.count else {
            return nil
        }

        let src = words[word]
        var cell = [UInt8](repeating: 0, count: cellWidth * cellHeight * 4)
        for span in src.letters {
            copyBox(src.rgba, span, src.rowTop, src.rowBottom, &cell, span.left)
        }

        let composed = WordCell(cell, src.letters, src.rowTop, src.rowBottom)
        GlowModel.of(words).paint(composed)
        return composed.rgba
    }

    public static func segment(_ cell: [UInt8], rowTop: inout Int, rowBottom: inout Int) -> [LetterSpan] {
        var colMax = [Int](repeating: 0, count: cellWidth)
        rowTop = -1
        rowBottom = -1
        for y in 0..<cellHeight {
            for x in 0..<cellWidth {
                let a = Int(cell[(((y * cellWidth) + x) * 4) + 3])
                if a > colMax[x] {
                    colMax[x] = a
                }
                if a >= ink {
                    if rowTop < 0 {
                        rowTop = y
                    }
                    rowBottom = y
                }
            }
        }

        var spans: [LetterSpan] = []
        var start = -1
        for x in 0...cellWidth {
            let isInk = x < cellWidth && colMax[x] >= ink
            if isInk && start < 0 {
                start = x
            } else if !isInk && start >= 0 {
                if !spans.isEmpty && start - spans[spans.count - 1].right - 1 <= counterDip {
                    spans[spans.count - 1] = LetterSpan(spans[spans.count - 1].left, x - 1)
                } else {
                    spans.append(LetterSpan(start, x - 1))
                }
                start = -1
            }
        }

        return spans
    }

    private static func crispest(_ words: [WordCell], _ candidates: [(Int, Int)], _ reference: WordCell) -> (Int, Int) {
        var best = candidates.last!
        var bestScore = -1
        for (w, l) in candidates {
            let word = words[w]
            if word.rowTop != reference.rowTop || word.rowBottom != reference.rowBottom || l >= word.letters.count {
                continue
            }
            let score = word.crispness(word.letters[l])
            if score > bestScore {
                bestScore = score
                best = (w, l)
            }
        }
        return bestScore < 0 ? candidates.last! : best
    }

    private static func copyBox(_ src: [UInt8], _ span: LetterSpan, _ rowTop: Int, _ rowBottom: Int, _ dst: inout [UInt8], _ dstLeft: Int) {
        let width = span.width + 2
        for y in (rowTop - 1)...(rowBottom + 1) {
            let srcStart = (((y * cellWidth) + span.left - 1) * 4)
            let dstStart = (((y * cellWidth) + dstLeft - 1) * 4)
            dst.replaceSubrange(dstStart..<(dstStart + width * 4), with: src[srcStart..<(srcStart + width * 4)])
        }
    }

    private static func mirrorLowerHalf(_ cell: inout [UInt8], _ span: LetterSpan, _ rowTop: Int, _ rowBottom: Int, _ rowSum: Int) {
        let colSum = span.left + span.right
        var mirror = [UInt8](repeating: 0, count: (span.width + 2) * 4)
        for y in (rowTop - 1)...(rowBottom + 1) {
            let ySrc = rowSum - y
            if 2 * y < rowSum || ySrc < rowTop - 1 || ySrc > rowBottom + 1 {
                continue
            }

            for x in (span.left - 1)...(span.right + 1) {
                let xSrc = colSum - x
                let srcOff = (((ySrc * cellWidth) + xSrc) * 4)
                let mOff = (x - span.left + 1) * 4
                mirror[mOff] = cell[srcOff]
                mirror[mOff + 1] = cell[srcOff + 1]
                mirror[mOff + 2] = cell[srcOff + 2]
                mirror[mOff + 3] = cell[srcOff + 3]
            }

            for x in (span.left - 1)...(span.right + 1) {
                let o = ((y * cellWidth) + x) * 4
                let m = (x - span.left + 1) * 4
                if 2 * y != rowSum || mirror[m + 3] > cell[o + 3] {
                    cell[o] = mirror[m]
                    cell[o + 1] = mirror[m + 1]
                    cell[o + 2] = mirror[m + 2]
                    cell[o + 3] = mirror[m + 3]
                }
            }
        }
    }

    final class WordCell {
        var rgba: [UInt8]
        var letters: [LetterSpan]
        var rowTop: Int
        var rowBottom: Int

        init(_ rgba: [UInt8], _ letters: [LetterSpan], _ rowTop: Int, _ rowBottom: Int) {
            self.rgba = rgba
            self.letters = letters
            self.rowTop = rowTop
            self.rowBottom = rowBottom
        }

        static func cut(_ sheet: [UInt8], _ x0: Int, _ y0: Int) -> WordCell {
            var rgba = [UInt8](repeating: 0, count: cellWidth * cellHeight * 4)
            for y in 0..<cellHeight {
                let srcStart = (((y0 + y) * sheetWidth) + x0) * 4
                let dstStart = y * cellWidth * 4
                rgba.replaceSubrange(dstStart..<(dstStart + cellWidth * 4), with: sheet[srcStart..<(srcStart + cellWidth * 4)])
            }
            var top = 0
            var bottom = 0
            let letters = segment(rgba, rowTop: &top, rowBottom: &bottom)
            return WordCell(rgba, letters, top, bottom)
        }

        func crispness(_ span: LetterSpan) -> Int {
            var best = 0
            for x in span.left...span.right {
                var sum = 0
                for y in rowTop...rowBottom {
                    sum += Int(rgba[(((y * cellWidth) + x) * 4) + 3])
                }
                best = max(best, sum)
            }
            return best
        }

        func letterRows(_ span: LetterSpan) -> (top: Int, bottom: Int) {
            var top = -1
            var bottom = -1
            for y in rowTop...rowBottom {
                for x in span.left...span.right {
                    if rgba[(((y * cellWidth) + x) * 4) + 3] >= ink {
                        if top < 0 {
                            top = y
                        }
                        bottom = y
                        break
                    }
                }
            }
            return (top, bottom)
        }

        func inBox(_ x: Int, _ y: Int) -> Bool {
            if y < rowTop - 1 || y > rowBottom + 1 {
                return false
            }
            for s in letters {
                if x >= s.left - 1 && x <= s.right + 1 {
                    return true
                }
            }
            return false
        }

        func fields() -> [LetterField] {
            letters.map { LetterField.of(rgba, $0, rowTop - 1, rowBottom + 1) }
        }
    }

    final class LetterField {
        var dist2: [Int] = [Int](repeating: Int.max, count: cellWidth * cellHeight)
        var dx: [Int8] = [Int8](repeating: 0, count: cellWidth * cellHeight)
        var dy: [Int8] = [Int8](repeating: 0, count: cellWidth * cellHeight)

        static func of(_ rgba: [UInt8], _ span: LetterSpan, _ rowFrom: Int, _ rowTo: Int) -> LetterField {
            let f = LetterField()
            for py in rowFrom...rowTo {
                for px in span.left...span.right {
                    if rgba[(((py * cellWidth) + px) * 4) + 3] < ink {
                        continue
                    }
                    let y0 = max(0, py - glowReach)
                    let y1 = min(cellHeight - 1, py + glowReach)
                    let x0 = max(0, px - glowReach)
                    let x1 = min(cellWidth - 1, px + glowReach)
                    for y in y0...y1 {
                        let dy = y - py
                        let row = y * cellWidth
                        for x in x0...x1 {
                            let dx = x - px
                            let dd = (dx * dx) + (dy * dy)
                            let idx = row + x
                            if dd < f.dist2[idx] {
                                f.dist2[idx] = dd
                                f.dx[idx] = Int8(dx)
                                f.dy[idx] = Int8(dy)
                            }
                        }
                    }
                }
            }
            return f
        }
    }

    final class GlowModel {
        private static let side: Int = glowReach + 1
        private var _alpha = [Double](repeating: 0, count: side * side)
        private var _r = [Double](repeating: 0, count: side * side)
        private var _g = [Double](repeating: 0, count: side * side)
        private var _b = [Double](repeating: 0, count: side * side)
        private var _count = [Int](repeating: 0, count: side * side)
        private var _alphaAt = [Float](repeating: 0, count: side * side)
        private var _rAt = [Float](repeating: 0, count: side * side)
        private var _gAt = [Float](repeating: 0, count: side * side)
        private var _bAt = [Float](repeating: 0, count: side * side)
        private var _pairs: [(dx1: Int8, dy1: Int8, dx2: Int8, dy2: Int8, alpha: UInt8)] = []

        private(set) var sum: Float = 0

        static func of(_ words: [WordCell]) -> GlowModel {
            let model = GlowModel()
            for w in words {
                model.accumulate(w)
            }
            model.finish()
            return model
        }

        func alphaAt(_ dx: Int, _ dy: Int) -> Float {
            if abs(dx) > glowReach || abs(dy) > glowReach {
                return 0
            }
            return _alphaAt[Self.index(dx, dy)]
        }

        private static func index(_ dx: Int, _ dy: Int) -> Int {
            (abs(dx) * side) + abs(dy)
        }

        private func accumulate(_ word: WordCell) {
            let fields = word.fields()
            for y in 0..<cellHeight {
                for x in 0..<cellWidth {
                    if word.inBox(x, y) {
                        continue
                    }
                    let idx = (y * cellWidth) + x
                    var d1 = Int.max, d2 = Int.max
                    var dx1 = 0, dy1 = 0, dx2 = 0, dy2 = 0
                    Self.nearest(fields, idx, &d1, &d2, &dx1, &dy1, &dx2, &dy2)
                    if d1 == Int.max || d1 > glowReach * glowReach {
                        continue
                    }

                    let o = idx * 4
                    let a = word.rgba[o + 3]
                    if d2 == Int.max || Float(d2) >= farApart * farApart {
                        let k = Self.index(dx1, dy1)
                        _alpha[k] += Double(a)
                        _r[k] += Double(word.rgba[o]) * Double(a)
                        _g[k] += Double(word.rgba[o + 1]) * Double(a)
                        _b[k] += Double(word.rgba[o + 2]) * Double(a)
                        _count[k] += 1
                    } else {
                        _pairs.append((Int8(dx1), Int8(dy1), Int8(dx2), Int8(dy2), a))
                    }
                }
            }
        }

        private func finish() {
            let side = Self.side
            var ringAlpha = [Double](repeating: 0, count: side + 1)
            var ringR = [Double](repeating: 0, count: side + 1)
            var ringG = [Double](repeating: 0, count: side + 1)
            var ringB = [Double](repeating: 0, count: side + 1)
            var ringCount = [Int](repeating: 0, count: side + 1)

            for dx in 0...glowReach {
                for dy in 0...glowReach {
                    let k = Self.index(dx, dy)
                    let ring = min(side, Int(round(sqrt(Double((dx * dx) + (dy * dy))))))
                    ringAlpha[ring] += _alpha[k]
                    ringR[ring] += _r[k]
                    ringG[ring] += _g[k]
                    ringB[ring] += _b[k]
                    ringCount[ring] += _count[k]
                }
            }

            for dx in 0...glowReach {
                for dy in 0...glowReach {
                    let k = Self.index(dx, dy)
                    let ring = min(side, Int(round(sqrt(Double((dx * dx) + (dy * dy))))))
                    let own = _count[k] > 0
                    let a = own ? _alpha[k] : ringAlpha[ring]
                    let n = own ? _count[k] : ringCount[ring]
                    if n == 0 || a <= 0 {
                        continue
                    }

                    _alphaAt[k] = Float(a / Double(n))
                    _rAt[k] = Float((own ? _r[k] : ringR[ring]) / a)
                    _gAt[k] = Float((own ? _g[k] : ringG[ring]) / a)
                    _bAt[k] = Float((own ? _b[k] : ringB[ring]) / a)
                }
            }

            var num: Double = 0
            var den: Double = 0
            for pair in _pairs {
                let a1 = alphaAt(Int(pair.dx1), Int(pair.dy1))
                let a2 = alphaAt(Int(pair.dx2), Int(pair.dy2))
                let lo = min(a1, a2)
                let hi = max(a1, a2)
                num += Double(lo) * (Double(pair.alpha) - Double(hi))
                den += Double(lo) * Double(lo)
            }

            sum = den > 0 ? Float(min(max(num / den, 0.0), 1.5)) : 0
            _pairs.removeAll()
        }

        func paint(_ word: WordCell) {
            let fields = word.fields()
            for y in 0..<cellHeight {
                for x in 0..<cellWidth {
                    if word.inBox(x, y) {
                        continue
                    }
                    let idx = (y * cellWidth) + x
                    var d1 = Int.max, d2 = Int.max
                    var dx1 = 0, dy1 = 0, dx2 = 0, dy2 = 0
                    Self.nearest(fields, idx, &d1, &d2, &dx1, &dy1, &dx2, &dy2)
                    if d1 == Int.max {
                        continue
                    }

                    let a1 = alphaAt(dx1, dy1)
                    let a2 = d2 == Int.max ? 0 : alphaAt(dx2, dy2)
                    let a = max(a1, a2) + (sum * min(a1, a2))
                    if a < 0.5 {
                        continue
                    }

                    let k = a1 >= a2 ? Self.index(dx1, dy1) : Self.index(dx2, dy2)
                    let o = idx * 4
                    word.rgba[o] = Self.roundByte(_rAt[k])
                    word.rgba[o + 1] = Self.roundByte(_gAt[k])
                    word.rgba[o + 2] = Self.roundByte(_bAt[k])
                    word.rgba[o + 3] = Self.roundByte(a)
                }
            }
        }

        private static func nearest(_ fields: [LetterField], _ idx: Int, _ d1: inout Int, _ d2: inout Int, _ dx1: inout Int, _ dy1: inout Int, _ dx2: inout Int, _ dy2: inout Int) {
            d1 = Int.max
            d2 = Int.max
            dx1 = 0
            dy1 = 0
            dx2 = 0
            dy2 = 0
            for f in fields {
                let d = f.dist2[idx]
                if d < d1 {
                    d2 = d1
                    dx2 = dx1
                    dy2 = dy1
                    d1 = d
                    dx1 = Int(f.dx[idx])
                    dy1 = Int(f.dy[idx])
                } else if d < d2 {
                    d2 = d
                    dx2 = Int(f.dx[idx])
                    dy2 = Int(f.dy[idx])
                }
            }
        }

        private static func roundByte(_ v: Float) -> UInt8 {
            UInt8(clamping: Int(round(v)))
        }
    }
}
