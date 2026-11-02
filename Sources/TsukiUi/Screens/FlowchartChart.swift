// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Ported from knife (https://github.com/AuroraWright/knife) by AuroraWright: knife/src/flow.rs
import Foundation
import TsukiCore
import TsukiEngine

/// The sheets of the flowchart's chart (GALLERY_PARTS_FC children).
public enum ChartSheet: Int, Sendable {
    case bandMiddle = 0
    case bandUnder = 1
    case bandUpper = 2
    case lineGrey = 3
    case lineLit = 4
    case mosaic = 5
    case nodeFrame = 6
    case title = 7
}

/// A textured piece of the chart in content coordinates (y not yet scrolled).
public struct ChartSprite: Sendable {
    public let sheet: ChartSheet
    public let dst: RectF
    public let src: RectF
    public let prio: Int

    public var Sheet: ChartSheet { sheet }
    public var Dst: RectF { dst }
    public var Src: RectF { src }
    public var Prio: Int { prio }

    public init(sheet: ChartSheet, dst: RectF, src: RectF, prio: Int) {
        self.sheet = sheet
        self.dst = dst
        self.src = src
        self.prio = prio
    }
}

/// A node the cursor can select.
public struct ChartNode: Sendable {
    public let node: Int
    public let x: Float
    public let y: Float
    public let preview: Int
    public let titleUi: Int
    public let synopsisUi: Int

    public var Node: Int { node }
    public var X: Float { x }
    public var Y: Float { y }
    public var Preview: Int { preview }
    public var TitleUi: Int { titleUi }
    public var SynopsisUi: Int { synopsisUi }

    public init(node: Int, x: Float, y: Float, preview: Int, titleUi: Int, synopsisUi: Int) {
        self.node = node
        self.x = x
        self.y = y
        self.preview = preview
        self.titleUi = titleUi
        self.synopsisUi = synopsisUi
    }
}

/// A cursor cell: the record index inside its row and the shown row.
public struct ChartCell: Hashable, Sendable {
    public var col: Int
    public var row: Int

    public var Col: Int { get { col } set { col = newValue } }
    public var Row: Int { get { row } set { row = newValue } }

    public init(col: Int, row: Int) {
        self.col = col
        self.row = row
    }

    public init(_ col: Int, _ row: Int) {
        self.col = col
        self.row = row
    }
}

/// The record under a cursor cell.
public struct ChartRecord: Sendable {
    public let column: Int
    public let node: Int
    public let scriptScene: Int

    public var Column: Int { column }
    public var Node: Int { node }
    public var ScriptScene: Int { scriptScene }

    public init(column: Int, node: Int, scriptScene: Int) {
        self.column = column
        self.node = node
        self.scriptScene = scriptScene
    }
}

/// The flowchart's chart.
public final class FlowchartChart {
    public static let nodeW: Float = 104.0
    public static let NodeW: Float = nodeW
    public static let nodeH: Float = 64.0
    public static let NodeH: Float = nodeH
    public static let viewHeight: Float = 1022.0
    public static let ViewHeight: Float = viewHeight
    public static let mosaicCellW: Int = 81
    public static let MosaicCellW: Int = mosaicCellW
    public static let mosaicCellH: Int = 45
    public static let MosaicCellH: Int = mosaicCellH
    public static let mosaicColumns: Int = 20
    public static let MosaicColumns: Int = mosaicColumns

    private static let drawn: UInt32 = 1 << 31
    private static let lit: UInt32 = 1 << 30
    private static let edgeBase: Int = 564

    private let _grid: [GridRow]
    private let _progress: IUiProgress
    private let _gallery: Bool

    public let sprites: [ChartSprite]
    public var Sprites: [ChartSprite] { sprites }

    public let nodes: [ChartNode]
    public var Nodes: [ChartNode] { nodes }

    public let titles: [[ChartSprite]]
    public var Titles: [[ChartSprite]] { titles }

    public let limits: [Float]
    public var Limits: [Float] { limits }

    public let rowY: [Float]
    public var RowY: [Float] { rowY }

    public let scrollMax: Float
    public var ScrollMax: Float { scrollMax }

    public var rows: Int { _grid.count }
    public var Rows: Int { rows }

    private init(
        sprites: [ChartSprite],
        nodes: [ChartNode],
        titles: [[ChartSprite]],
        limits: [Float],
        rowY: [Float],
        scrollMax: Float,
        grid: [GridRow],
        progress: IUiProgress,
        gallery: Bool
    ) {
        self.sprites = sprites
        self.nodes = nodes
        self.titles = titles
        self.limits = limits
        self.rowY = rowY
        self.scrollMax = scrollMax
        self._grid = grid
        self._progress = progress
        self._gallery = gallery
    }

    private final class Rec {
        let n: ChartNodeRow
        var flags: UInt32 = 0
        init(node: ChartNodeRow) {
            self.n = node
        }
    }

    private final class Row {
        let index: Int
        let phase: Int
        let recs: [Rec]
        init(index: Int, phase: Int, recs: [Rec]) {
            self.index = index
            self.phase = phase
            self.recs = recs
        }
    }

    private final class GridRow {
        let index: Int
        let phase: Int
        let cells: [(n: ChartNodeRow, node: Int)]
        init(index: Int, phase: Int, cells: [(n: ChartNodeRow, node: Int)]) {
            self.index = index
            self.phase = phase
            self.cells = cells
        }
    }

    private static func nodeAt(_ columns: [ChartColumnRow], _ c: Int, _ j: Int) -> (scene: Int, link: Int) {
        let col = columns[c]
        return j < col.nodes.count ? (col.nodes[j].scene, col.nodes[j].link) : (col.overrunScene, col.overrunLink)
    }

    public static func keptColumns(_ columns: [ChartColumnRow], _ progress: IUiProgress) -> [Int] {
        var kept: [Int] = []
        for c in 0..<columns.count {
            let col = columns[c]
            let count = col.nodes.count
            let rows = max(count, 1)
            var vis = 0
            var diff = 0
            for j in 0..<rows {
                let (a, link) = nodeAt(columns, c, j)
                if !((a > 0 && progress.sceneDone(a)) || (link > 0 && progress.edgeSeen(link))) {
                    continue
                }

                vis += 1
                if a > 0 {
                    diff += 1
                    continue
                }

                if a == 0 {
                    continue
                }

                if c == 0 || j > columns[c - 1].nodes.count {
                    diff += 1
                    continue
                }

                let pa = nodeAt(columns, c - 1, j).scene
                if progress.sceneDone(-a) {
                    if abs(pa) != abs(a) {
                        diff += 1
                        continue
                    }

                    if c > 0x113 {
                        continue
                    }

                    for k in (c + 1)..<columns.count {
                        if j > columns[k].nodes.count {
                            diff += 1
                            break
                        }

                        if columns[k].group > col.group {
                            break
                        }

                        let (ka, klink) = nodeAt(columns, k, j)
                        if ka != a || klink != link {
                            diff += 1
                            break
                        }
                    }
                } else if pa + a != 0 {
                    diff += 1
                }
            }

            if (vis >= 2 && diff != 0) || (vis == 1 && (diff == 1 || count == 1)) {
                kept.append(c)
            }
        }
        return kept
    }

    public static func KeptColumns(_ columns: [ChartColumnRow], _ progress: IUiProgress) -> [Int] {
        keptColumns(columns, progress)
    }

    private final class Builder {
        private let _fl: IUiProgress
        private let _lines: [SheetCell]
        private let _rows: [Row]

        var sprites: [ChartSprite] = []

        init(progress: IUiProgress, lines: [SheetCell], rows: [Row]) {
            self._fl = progress
            self._lines = lines
            self._rows = rows
        }

        private func completed(_ n: Int) -> Bool { n >= 1 && _fl.sceneDone(n) }
        private func read(_ n: Int) -> Bool { n >= 1 && _fl.sceneSeen(n) }
        private func route(_ n: Int) -> Bool { n >= 1 && _fl.routeScene(n) }
        private func edge(_ f: Int) -> Bool { f >= 1 && _fl.edgeSeen(f) }
        private func routeEdge(_ f: Int) -> Bool { f >= 1 && _fl.routeEdge(f) }

        private func push(_ sheet: ChartSheet, _ x: Float, _ y: Float, _ src: RectF, _ prio: Int) {
            sprites.append(ChartSprite(sheet: sheet, dst: RectF(x, y, src.w, src.h), src: src, prio: prio))
        }

        private func cell(_ i: Int) -> RectF {
            if i >= 0 && i < _lines.count {
                let c = _lines[i]
                return RectF(Float(c.x0), Float(c.y0), Float(c.width), Float(c.height))
            }
            return RectF(0, 0, 4, 4)
        }

        func band(_ top: Float, _ bottom: Float) -> Float {
            let h = bottom - top + 3.0
            sprites.append(ChartSprite(sheet: .bandMiddle, dst: RectF(0, top, 1440, h), src: RectF(0, 0, 1440, 1), prio: 460))
            return bottom + 10.0
        }

        func divider(_ y: Float) {
            push(.bandUnder, 0, y, RectF(0, 0, 1440, 5), 450)
            push(.bandUpper, 0, y + 8.0, RectF(0, 0, 1440, 5), 450)
        }

        private func recAt(_ k: Int, _ j: Int) -> Rec? {
            guard k >= 0 && k < _rows.count && j >= 0 && j < _rows[k].recs.count else { return nil }
            return _rows[k].recs[j]
        }

        private func greyOn(_ k: Int, _ j: Int) -> Bool {
            guard let r = recAt(k, j) else { return false }
            return (r.flags & FlowchartChart.drawn) != 0 || (r.n.scene >= 1 && completed(r.n.scene)) || edge(r.n.link)
        }

        private func litOn(_ k: Int, _ j: Int) -> Bool {
            guard let r = recAt(k, j) else { return false }
            return (r.flags & FlowchartChart.lit) != 0 || (r.n.scene >= 1 && route(r.n.scene)) || routeEdge(r.n.link)
        }

        private func upWith(_ k: Int, _ j: Int, _ f: (Int) -> Bool) -> Bool {
            guard k >= 1, let p = recAt(k - 1, j), p.n.scene != 0 else { return false }
            return f(abs(p.n.scene))
        }

        private func selfGrey(_ k: Int, _ j: Int) -> Bool {
            guard let r = recAt(k, j) else { return false }
            let n = r.n.scene
            if n == 0 {
                return false
            } else if n < 0 {
                return completed(-n) || (k + 1 == _rows.count)
            } else {
                return completed(n) || edge(r.n.link)
            }
        }

        private func selfLit(_ k: Int, _ j: Int) -> Bool {
            guard let r = recAt(k, j) else { return false }
            return r.n.scene != 0 && route(abs(r.n.scene))
        }

        private func shape(_ kind: Int, _ k: Int, _ j: Int, _ lit: Bool) -> Int {
            let on = { [weak self] (jj: Int) -> Bool in
                guard let self = self else { return false }
                return lit ? self.litOn(k, jj) : self.greyOn(k, jj)
            }
            let up = lit ? upWith(k, j, route) : upWith(k, j, completed)
            let me = lit ? selfLit(k, j) : selfGrey(k, j)
            let left = on(j - 1)
            let right = on(j + 1)
            switch kind {
            case 5:
                return !up ? 4 : (right ? (me ? 5 : 2) : (me ? 3 : 5))
            case 8:
                if !up {
                    return 7
                }
                return left ? (right ? 8 : 6) : (right ? 2 : 8)
            case 10:
                return !up ? 9 : (left ? (me ? 10 : 6) : (me ? 3 : 10))
            case 11:
                if !me {
                    return 7
                }
                return left ? (right ? 11 : 9) : (right ? 4 : 11)
            default:
                return kind
            }
        }

        private func line(_ k: Int, _ j: Int, _ first: Bool, _ lit: Bool, _ kind: Int, _ x: Float, _ y: Float) {
            let baseCell = 0
            let sheet: ChartSheet = lit ? .lineLit : .lineGrey
            let prio = lit ? 440 : 450
            let cellKind = (kind >= 0 && kind <= 25) ? kind : 12
            let c = cell(cellKind + baseCell)
            push(sheet, x, y, c, prio)
            let n = recAt(k, j)?.n.scene ?? 0
            if kind == 3 {
                if first {
                    push(sheet, x, y - 13.0, cell(baseCell), prio)
                }
            } else if kind <= 11 && ((0xE30 >> kind) & 1) != 0 && n < 0 {
                var c2 = read(-n)
                if lit && !c2 {
                    c2 = route(-n)
                }
                if c2 {
                    push(sheet, x, y + 14.0, cell(baseCell + 1), prio)
                }
            }
        }

        func grey(_ k: Int, _ j: Int, _ first: Bool, _ x: Float, _ y: Float) -> Bool {
            guard let r = recAt(k, j) else { return false }
            if (r.flags & FlowchartChart.drawn) == 0 && !edge(r.n.link) {
                return false
            }

            let n = r.n.scene
            var kind = r.n.connector
            if kind == 3 && n < 0 {
                guard k >= 1, let p = recAt(k - 1, j) else { return false }
                let ok = (p.flags & FlowchartChart.drawn) != 0 && (p.n.scene == 0 ? false : (p.n.scene < 0 ? read(-p.n.scene) : completed(p.n.scene)))
                if !ok {
                    return false
                }
            } else if kind == 5 || kind == 8 || kind == 10 || kind == 11 {
                kind = shape(kind, k, j, false)
            }

            if kind < 0 {
                return false
            }

            line(k, j, first, false, kind, x, y)
            return true
        }

        func litLine(_ k: Int, _ j: Int, _ first: Bool, _ x: Float, _ y: Float) -> Bool {
            guard let r = recAt(k, j) else { return false }
            if (r.flags & FlowchartChart.lit) == 0 && !routeEdge(r.n.link) {
                return false
            }

            let n = r.n.scene
            var kind = r.n.connector
            if kind == 3 && n < 0 {
                let ok = k >= 1 && recAt(k - 1, j).map { p in
                    (p.flags & FlowchartChart.lit) != 0 && abs(p.n.scene) >= 1 && route(abs(p.n.scene))
                } ?? false
                if !ok {
                    return true
                }
            } else if kind == 5 || kind == 8 || kind == 10 || kind == 11 {
                kind = shape(kind, k, j, true)
            }

            if kind >= 0 {
                line(k, j, first, true, kind, x, y)
            }
            return true
        }

        func node(_ k: Int, _ j: Int, _ gallery: Bool, _ x: Float, _ y: Float) -> Bool {
            let phase = _rows[k].phase
            let rec = _rows[k].recs[j]
            let n = rec.n.scene
            let edgeVal = rec.n.link
            let kind = rec.n.connector
            if n == 0 {
                return false
            }

            if n < 0 {
                if completed(-n) || !edge(edgeVal) || read(-n) || (!gallery && route(-n)) || kind == 3 {
                    return false
                }
            } else if !completed(n) && !edge(edgeVal) {
                return false
            }

            let thumb: Bool
            let select: Bool
            if gallery {
                let c = n >= 1 && completed(n)
                thumb = c
                select = c
            } else if n < 1 {
                thumb = false
                select = false
            } else {
                let rt = route(n)
                if rt {
                    rec.flags |= FlowchartChart.lit
                }
                thumb = completed(n)
                select = phase > 0 && rt
            }

            let t = rec.n.mosaic
            if thumb && t >= 0 {
                let src = RectF(
                    Float((mosaicCellW * (t % mosaicColumns)) + 1),
                    Float((mosaicCellH * (t / mosaicColumns)) + 1),
                    Float(mosaicCellW - 2),
                    Float(mosaicCellH - 2)
                )
                sprites.append(ChartSprite(sheet: .mosaic, dst: RectF(x + 1.0, y + 1.0, 102.0, 62.0), src: src, prio: 400))
            } else {
                push(.nodeFrame, x, y, RectF(0, 0, nodeW, nodeH), 400)
            }

            return select
        }

        static func visibleRows(_ columns: [ChartColumnRow], _ progress: IUiProgress) -> [Row] {
            var kept: [Row] = []
            for i in FlowchartChart.keptColumns(columns, progress) {
                kept.append(Row(index: i, phase: columns[i].group, recs: columns[i].nodes.map { Rec(node: $0) }))
            }
            return kept
        }
    }

    public static func build(_ tables: UiGalleryTables, _ language: Language, _ progress: IUiProgress, _ gallery: Bool) -> FlowchartChart {
        let rows = Builder.visibleRows(tables.chartColumns, progress)
        let b = Builder(progress: progress, lines: tables.chartLineCells, rows: rows)
        var nodes: [ChartNode] = []
        var cellNodes: [[Int]] = rows.map { [Int](repeating: -1, count: $0.recs.count) }
        var titles: [[ChartSprite]] = []
        var limits: [Float] = []
        var rowY: [Float] = []
        var y: Float = 0
        var titleY: Float = 0
        var bandTop: Float = 0
        var phase: Int = 0
        var count: Int = 0
        var lastTitle: Int = -1
        let english = language == .en
        let titleCells = tables.chartTitleCells(language)
        let titleX: Float = english ? 2.0 : 208.0

        for k in 0..<rows.count {
            let first = rows[k].phase != phase
            if first {
                bandTop = b.band(bandTop, y + 8.0)
                b.divider(y + 8.0)
                limits.append(y + 16.0)
                y += 13.0
                phase = rows[k].phase
                titleY = y
                count = 0
                lastTitle = -1
            }

            let nodeY = y + 4.0
            rowY.append(nodeY)
            let slot = rows[k].phase
            while titles.count <= slot {
                titles.append([])
            }

            for j in 0..<rows[k].recs.count {
                let f = rows[k].recs[j].n
                let title = f.chapterLabel
                let edgeSeen = f.link >= 1 && progress.edgeSeen(f.link)
                if title >= 0 && count <= 2 && title > lastTitle && edgeSeen {
                    titles[slot].append(titleSprite(titleCells, titleX, titleY + 8.0, title))
                    titleY += 32.0
                    lastTitle = title
                    if title != 0 {
                        count += 1
                    } else {
                        titles[slot].append(titleSprite(titleCells, titleX, titleY + 8.0, prologueCell(titleCells)))
                        titleY += 32.0
                        count += 2
                    }
                }

                let x = (Float(j) * 96.0) + 438.0
                if b.node(k, j, gallery, x, nodeY) {
                    cellNodes[k][j] = nodes.count
                    nodes.append(ChartNode(node: f.scene, x: x, y: nodeY, preview: f.preview, titleUi: f.titleUi, synopsisUi: f.synopsisUi))
                }

                if b.grey(k, j, first, x, nodeY - 5.0) {
                    rows[k].recs[j].flags |= drawn
                }

                if !gallery && b.litLine(k, j, first, x, nodeY - 5.0) {
                    rows[k].recs[j].flags |= lit
                }
            }

            y += 56.0
        }

        let end = max(y, titleY) + 8.0
        _ = b.band(bandTop, end)
        b.sprites.append(ChartSprite(sheet: .bandUnder, dst: RectF(0, end, 1440, 5), src: RectF(0, 0, 1440, 5), prio: 450))

        let sortedSprites = b.sprites.enumerated()
            .sorted { a, b in
                if a.element.prio != b.element.prio {
                    return a.element.prio > b.element.prio
                }
                return a.offset < b.offset
            }
            .map { $0.element }

        var scrollMax = end + 56.0 + 4.0 - 1022.0
        if scrollMax - 28.0 <= 1022.0 {
            scrollMax -= 28.0
        }
        if !rows.isEmpty && rows[rows.count - 1].index == 276 {
            scrollMax -= 56.0
        }

        var grid: [GridRow] = []
        grid.reserveCapacity(rows.count)
        for k in 0..<rows.count {
            var cells: [(n: ChartNodeRow, node: Int)] = []
            cells.reserveCapacity(rows[k].recs.count)
            for j in 0..<rows[k].recs.count {
                cells.append((rows[k].recs[j].n, cellNodes[k][j]))
            }
            grid.append(GridRow(index: rows[k].index, phase: rows[k].phase, cells: cells))
        }

        return FlowchartChart(
            sprites: sortedSprites,
            nodes: nodes,
            titles: titles,
            limits: limits,
            rowY: rowY,
            scrollMax: max(scrollMax, 0.0),
            grid: grid,
            progress: progress,
            gallery: gallery
        )
    }

    public static func Build(_ tables: UiGalleryTables, _ language: Language, _ progress: IUiProgress, _ gallery: Bool) -> FlowchartChart {
        build(tables, language, progress, gallery)
    }

    private static func prologueCell(_ cells: [SheetCell]) -> Int {
        for i in stride(from: cells.count - 1, through: 0, by: -1) {
            if cells[i].width > 0 && cells[i].height > 0 {
                return i
            }
        }
        return 0
    }

    private static func titleSprite(_ cells: [SheetCell], _ x: Float, _ y: Float, _ title: Int) -> ChartSprite {
        let c = (title >= 0 && title < cells.count) ? cells[title] : SheetCell(x0: 0, y0: 0, x1: 0, y1: 0)
        let src = RectF(Float(c.x0), Float(c.y0), Float(c.width), Float(c.height))
        return ChartSprite(sheet: .title, dst: RectF(x, y, src.w, src.h), src: src, prio: 430)
    }

    // MARK: - Cursor

    private func countAt(_ k: Int) -> Int {
        (k >= 0 && k < _grid.count) ? _grid[k].cells.count : 0
    }

    private func cellAt(_ c: ChartCell) -> (n: ChartNodeRow, node: Int)? {
        guard c.row >= 0 && c.row < _grid.count && c.col >= 0 && c.col < _grid[c.row].cells.count else { return nil }
        return _grid[c.row].cells[c.col]
    }

    /// The record under a cell as the action on it sees it, or null.
    public func recordAt(_ c: ChartCell) -> ChartRecord? {
        guard let cell = cellAt(c) else { return nil }
        return ChartRecord(column: _grid[c.row].index, node: cell.n.scene, scriptScene: cell.n.scriptScene)
    }
    public func RecordAt(_ c: ChartCell) -> ChartRecord? { recordAt(c) }

    /// The selectable node of a cell, or -1.
    public func nodeAt(_ c: ChartCell) -> Int {
        cellAt(c)?.node ?? -1
    }
    public func NodeAt(_ c: ChartCell) -> Int { nodeAt(c) }

    /// The cell of selectable node `node` (an index into `nodes`), or null.
    public func cellOf(_ node: Int) -> ChartCell? {
        for k in 0..<_grid.count {
            for j in 0..<_grid[k].cells.count {
                if _grid[k].cells[j].node == node {
                    return ChartCell(j, k)
                }
            }
        }
        return nil
    }
    public func CellOf(_ node: Int) -> ChartCell? { cellOf(node) }

    private func hasSprite(_ c: ChartCell) -> Bool { nodeAt(c) >= 0 }
    private func done(_ n: Int) -> Bool { n >= 1 && _progress.sceneDone(n) }
    private func edgeOk(_ c: ChartCell) -> Bool {
        guard let r = cellAt(c) else { return false }
        return r.n.link >= 1 && _progress.edgeSeen(r.n.link)
    }

    public func openCursor(_ id: Int, follow: ((ChartCell) -> Void)? = nil) -> ChartCell {
        var cur = ChartCell(0, 0)
        if id >= 0 {
            for k in 0..<_grid.count {
                if let j = _grid[k].cells.firstIndex(where: { $0.n.scene == id }) {
                    cur = ChartCell(j, k)
                    follow?(cur)
                }
            }
        }
        return cur
    }
    public func OpenCursor(_ id: Int, _ follow: ((ChartCell) -> Void)? = nil) -> ChartCell {
        openCursor(id, follow: follow)
    }

    private func snap(_ cell: ChartCell, _ wide: Bool) -> Int? {
        let n = countAt(cell.row)
        let ok = { [weak self] (c: Int) -> Bool in
            guard let self = self else { return false }
            return c >= 0 && c < n && self.hasSprite(ChartCell(c, cell.row))
        }
        if ok(cell.col) {
            return cell.col
        }

        let (reach, lo, hi): (Int, Int, Int) = wide ? (8, 0, n) : (cell.col >= 4 ? (8, 4, n) : (3, 0, 4))
        for d in 1...reach {
            for c in [cell.col + d, cell.col - d] {
                if c >= lo && c < hi && ok(c) {
                    return c
                }
            }
        }
        return nil
    }

    private func okCell(_ c: ChartCell) -> Bool {
        c.row >= 0 && c.row < _grid.count && hasSprite(c)
    }

    public func moveLeft(_ cell: ChartCell) -> ChartCell? {
        let (j, k) = (cell.col, cell.row)
        for c in stride(from: j - 1, through: 0, by: -1) {
            if hasSprite(ChartCell(c, k)) {
                return ChartCell(c, k)
            }
        }

        let last = rows - 1
        if k < last {
            if j < 1 {
                return nil
            }
            for c in [j - 1, j - 2] {
                if c < 0 {
                    break
                }
                if okCell(ChartCell(c, k + 1)) {
                    return ChartCell(c, k + 1)
                }
                if k >= 1 && okCell(ChartCell(c, k - 1)) {
                    return ChartCell(c, k - 1)
                }
            }
            return nil
        }

        if k <= 0 {
            return nil
        }

        for c in [j - 1, j - 2] {
            if c >= 0 && okCell(ChartCell(c, k - 1)) {
                return ChartCell(c, k - 1)
            }
        }
        return nil
    }
    public func MoveLeft(_ cell: ChartCell) -> ChartCell? { moveLeft(cell) }

    public func moveRight(_ cell: ChartCell) -> ChartCell? {
        let (j, k) = (cell.col, cell.row)
        let n = countAt(k)
        if j + 1 < n {
            for c in (j + 1)..<n {
                if hasSprite(ChartCell(c, k)) {
                    return ChartCell(c, k)
                }
            }
        }

        let last = rows - 1
        if k < last {
            for (c, maxCol) in [(j + 1, 7), (j + 2, 6)] {
                if j > maxCol {
                    return nil
                }
                if okCell(ChartCell(c, k + 1)) {
                    return ChartCell(c, k + 1)
                }
                if k >= 1 && okCell(ChartCell(c, k - 1)) {
                    return ChartCell(c, k - 1)
                }
            }
            return nil
        }

        if k <= 0 {
            return nil
        }

        for (c, maxCol) in [(j + 1, 7), (j + 2, 6)] {
            if j <= maxCol && okCell(ChartCell(c, k - 1)) {
                return ChartCell(c, k - 1)
            }
        }
        return nil
    }
    public func MoveRight(_ cell: ChartCell) -> ChartCell? { moveRight(cell) }

    private func routeStep(_ k: Int, _ dy: Int) -> ChartCell? {
        var r = k
        while true {
            r += dy
            if r < 0 || r >= rows || (dy < 0 && _grid[r].phase == 0) {
                return nil
            }
            if let j = _grid[r].cells.firstIndex(where: { $0.n.scene >= 1 && _progress.routeScene($0.n.scene) && $0.node >= 0 }) {
                return ChartCell(j, r)
            }
            if (dy < 0 && r < 1) || (dy > 0 && r >= rows - 1) {
                return nil
            }
        }
    }

    public func moveUp(_ cell: ChartCell) -> ChartCell? {
        let (j, k) = (cell.col, cell.row)
        if k < 1 {
            return nil
        }
        if !_gallery {
            return routeStep(k, -1)
        }

        var col = j
        var row = k
        while true {
            if let c = traceUp(col, row) {
                return c
            }
            row -= 1
            if let s = snap(ChartCell(col, row), false) {
                return ChartCell(s, row)
            }
            if row <= 0 {
                return nil
            }
            col = j
        }
    }
    public func MoveUp(_ cell: ChartCell) -> ChartCell? { moveUp(cell) }

    public func moveDown(_ cell: ChartCell) -> ChartCell? {
        let (j, k) = (cell.col, cell.row)
        let last = rows - 1
        if !_gallery {
            return k >= last ? nil : routeStep(k, 1)
        }

        var row = k
        while row < last {
            row += 1
            if let c = traceDown(j, row) {
                return c
            }
            if let s = snap(ChartCell(j, row), false) {
                return ChartCell(s, row)
            }
        }

        row = k
        while row < last {
            row += 1
            if let s = snap(ChartCell(j, row), true) {
                return ChartCell(s, row)
            }
        }
        return nil
    }
    public func MoveDown(_ cell: ChartCell) -> ChartCell? { moveDown(cell) }

    private func traceUp(_ j: Int, _ k: Int) -> ChartCell? {
        var cJ = j
        var cK = k
        while true {
            if cK < 0 || cJ < 0 || cJ >= countAt(cK) || !edgeOk(ChartCell(cJ, cK)) {
                return nil
            }
            if cK >= 1 && cJ < countAt(cK - 1), let above = cellAt(ChartCell(cJ, cK - 1)), done(above.n.scene) {
                return ChartCell(cJ, cK - 1)
            }
            guard let curr = cellAt(ChartCell(cJ, cK)) else { return nil }
            switch curr.n.connector {
            case 2, 5, 8:
                if let r1 = traceUp(cJ + 1, cK) {
                    return r1
                }
                cK -= 1
            case 3:
                cK -= 1
            case 4, 7:
                cJ += 1
            case 6:
                return traceUp(cJ, cK - 1) ?? traceUpLeft(cJ - 1, cK)
            case 9:
                return traceUpLeft(cJ - 1, cK)
            case 10:
                if let r2 = traceUpLeft(cJ - 1, cK) {
                    return r2
                }
                cK -= 1
            case 11:
                return traceUp(cJ + 1, cK) ?? traceUpLeft(cJ - 1, cK)
            default:
                return nil
            }
        }
    }

    private func traceUpLeft(_ j: Int, _ k: Int) -> ChartCell? {
        var cJ = j
        while true {
            if cJ < 0 || cJ >= countAt(k) || !edgeOk(ChartCell(cJ, k)) {
                return nil
            }
            if k > 0 && cJ < countAt(k - 1), let above = cellAt(ChartCell(cJ, k - 1)), done(above.n.scene) {
                return ChartCell(cJ, k - 1)
            }
            guard let curr = cellAt(ChartCell(cJ, k)) else { return nil }
            switch curr.n.connector {
            case 2, 3, 5:
                return traceUp(cJ, k - 1)
            case 7, 11:
                cJ -= 1
            case 8:
                return traceUpLeft(cJ - 1, k) ?? traceUp(cJ, k - 1)
            default:
                return nil
            }
        }
    }

    private func traceDown(_ j: Int, _ k: Int) -> ChartCell? {
        var cJ = j
        var cK = k
        while true {
            if cK >= rows || cJ < 0 || cJ >= countAt(cK) {
                return nil
            }
            guard let cell = cellAt(ChartCell(cJ, cK)) else { return nil }
            let id = cell.n.scene
            if done(id) {
                return ChartCell(cJ, cK)
            }
            if !edgeOk(ChartCell(cJ, cK)) {
                return nil
            }
            switch cell.n.connector {
            case 2, 7:
                cJ += 1
            case 3, 9:
                cK += 1
            case 4:
                if id < 0 && done(-id) {
                    cJ += 1
                } else {
                    cK += 1
                }
            case 5, 11:
                if let r = traceDown(cJ + 1, cK) {
                    return r
                }
                cK += 1
            case 6, 8:
                return traceDownLeft(cJ - 1, cK)
            case 10:
                if id < 0 && done(-id) {
                    cK += 1
                } else {
                    return traceDownLeft(cJ - 1, cK)
                }
            default:
                return nil
            }
        }
    }

    private func traceDownLeft(_ j: Int, _ k: Int) -> ChartCell? {
        var cJ = j
        var cK = k
        while true {
            if cJ < 0 || cK >= rows {
                return nil
            }
            guard let cell = cellAt(ChartCell(cJ, cK)) else { return nil }
            let id = cell.n.scene
            if done(id) {
                return ChartCell(cJ, cK)
            }
            if !edgeOk(ChartCell(cJ, cK)) {
                return nil
            }
            switch cell.n.connector {
            case 11:
                if let r = traceDownLeft(cJ - 1, cK) {
                    return r
                }
                if id >= 0 || !done(-id) {
                    return traceDown(cJ, cK + 1)
                }
                cK += 1
            case 3, 4, 5:
                return traceDown(cJ, cK + 1)
            case 7, 8:
                cJ -= 1
            default:
                return nil
            }
        }
    }

    public func keepInView(_ cell: ChartCell, y: (Int) -> Float) -> ChartCell? {
        let last = rows - 1
        var col = cell.col
        var row = cell.row

        func settle(_ c: inout Int, _ r: Int, _ below: Bool) -> Bool {
            guard let s = snap(ChartCell(c, r), false) ?? snap(ChartCell(c, r), true) else {
                return false
            }
            c = s
            let node = nodeAt(ChartCell(s, r))
            return node >= 0 && (below ? y(node) < 994.0 : y(node) >= 4.0)
        }

        if row < last {
            while !settle(&col, row, false) {
                row += 1
                if row >= last {
                    break
                }
            }
        }

        if row >= 1 {
            while !settle(&col, row, true) {
                row -= 1
                if row <= 0 {
                    break
                }
            }
        }

        return row != cell.row ? ChartCell(col, row) : nil
    }
    public func KeepInView(_ cell: ChartCell, _ y: (Int) -> Float) -> ChartCell? {
        keepInView(cell, y: y)
    }
}
