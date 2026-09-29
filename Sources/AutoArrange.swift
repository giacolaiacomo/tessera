// Tessera — automatic placement: spread the open windows over the grid the user chose,
// and drop a new window into the largest hole left on that same grid.
//
// Every result is expressed in whole cells of the current GridSpec, so an automatic
// arrangement is indistinguishable from one the user snapped by hand: same gaps, same
// alignment, and any window can then be nudged without breaking the rest.

import AppKit

enum ArrangeStrategy: String, Codable, CaseIterable {
    case balanced      // as square as the screen allows
    case cells         // the grid taken literally: one cell per window, empty cells stay empty
    case columns       // one column each
    case rows          // one row each
    case masterStack   // first window large on the left, the rest stacked on the right

    var label: String {
        switch self {
        case .balanced:    return "Bilanciata"
        case .cells:       return "Una per cella"
        case .columns:     return "Colonne"
        case .rows:        return "Righe"
        case .masterStack: return "Master + pila"
        }
    }

    var detail: String {
        switch self {
        case .balanced:    return "Riempie lo schermo dividendolo in riquadri il più quadrati possibile."
        case .cells:       return "Una finestra per cella della griglia, nell'ordine di lettura: con 3×2 ogni finestra è un sesto di schermo, anche se le finestre sono meno di sei."
        case .columns:     return "Una colonna a testa, alte quanto lo schermo."
        case .rows:        return "Una riga a testa, larghe quanto lo schermo."
        case .masterStack: return "La finestra in primo piano grande a sinistra, le altre in pila a destra."
        }
    }
}

enum AutoArrange {

    // MARK: Partitioning the grid

    /// Splits `total` grid lines into `parts` contiguous runs, spreading the remainder over the
    /// first runs so no run is ever empty (callers must pass parts <= total).
    private static func split(_ total: Int, into parts: Int) -> [(start: Int, length: Int)] {
        let parts = max(1, min(parts, total))
        let base = total / parts, extra = total % parts
        var result: [(Int, Int)] = []
        var start = 0
        for i in 0..<parts {
            let length = base + (i < extra ? 1 : 0)
            result.append((start, length))
            start += length
        }
        return result
    }

    /// How many columns to use for `n` windows so that each tile stays close to `targetAspect`
    /// (width/height) on this screen.
    private static func columnCount(for n: Int, grid: GridSpec, aspect: CGFloat,
                                    targetAspect: CGFloat = 1.45) -> Int {
        var best = 1
        var bestError = CGFloat.greatestFiniteMagnitude
        for k in 1...max(1, min(n, grid.cols)) {
            let rowsUsed = Int(ceil(Double(n) / Double(k)))
            guard rowsUsed <= grid.rows else { continue }
            let tileAspect = (aspect / CGFloat(k)) * CGFloat(rowsUsed)
            let error = abs(log(tileAspect / targetAspect))
            if error < bestError { bestError = error; best = k }
        }
        return best
    }

    /// One cell rect per window, in order.
    ///
    /// The grid is the constraint, not a suggestion: with more windows than cells the extra
    /// windows share the last cell rather than being squeezed into sub-cell slivers.
    static func partition(count n: Int, grid: GridSpec, screenAspect aspect: CGFloat,
                          strategy: ArrangeStrategy, masterFraction: CGFloat = 0.6) -> [CellRect] {
        guard n > 0 else { return [] }
        let g = grid.clamped()
        let capacity = g.cols * g.rows
        // A lone window fills the screen — except under `.cells`, where the grid is taken at
        // face value and one window means one cell.
        if n == 1, strategy != .cells { return [CellRect(col: 0, row: 0, w: g.cols, h: g.rows)] }
        guard n <= capacity else {
            let head = partition(count: capacity, grid: g, screenAspect: aspect, strategy: strategy,
                                 masterFraction: masterFraction)
            return head + Array(repeating: head[capacity - 1], count: n - capacity)
        }

        switch strategy {
        case .cells:
            // The grid at face value: fill it in reading order and leave the rest empty.
            return (0..<n).map { CellRect(col: $0 % g.cols, row: $0 / g.cols) }

        case .columns:
            // One column each — unless there are more windows than columns, in which case a
            // single strip per window would be unusable and the balanced grid is the honest answer.
            guard n <= g.cols else {
                return partition(count: n, grid: g, screenAspect: aspect, strategy: .balanced,
                                 masterFraction: masterFraction)
            }
            return split(g.cols, into: n).map { CellRect(col: $0.start, row: 0, w: $0.length, h: g.rows) }

        case .rows:
            guard n <= g.rows else {
                return partition(count: n, grid: g, screenAspect: aspect, strategy: .balanced,
                                 masterFraction: masterFraction)
            }
            return split(g.rows, into: n).map { CellRect(col: 0, row: $0.start, w: g.cols, h: $0.length) }

        case .masterStack:
            let masterW = max(1, min(g.cols - 1, Int((CGFloat(g.cols) * masterFraction).rounded())))
            let stackCols = g.cols - masterW
            let master = CellRect(col: 0, row: 0, w: masterW, h: g.rows)
            if n - 1 <= g.rows {
                let stack = split(g.rows, into: n - 1).map {
                    CellRect(col: masterW, row: $0.start, w: stackCols, h: $0.length)
                }
                return [master] + stack
            }
            // The stack outgrew one column. Tile it over the remaining columns while the master
            // still fits; once even that is too tight, the whole screen goes balanced.
            guard n - 1 <= stackCols * g.rows else {
                return partition(count: n, grid: g, screenAspect: aspect, strategy: .balanced,
                                 masterFraction: masterFraction)
            }
            let stackGrid = GridSpec(cols: stackCols, rows: g.rows,
                                     outerGap: g.outerGap, innerGap: g.innerGap)
            let stack = partition(count: n - 1, grid: stackGrid,
                                  screenAspect: aspect * CGFloat(stackCols) / CGFloat(g.cols),
                                  strategy: .balanced, masterFraction: masterFraction)
            return [master] + stack.map {
                CellRect(col: $0.col + masterW, row: $0.row, w: $0.w, h: $0.h)
            }

        case .balanced:
            let k = columnCount(for: n, grid: g, aspect: aspect)
            let colRuns = split(g.cols, into: k)
            // Spread the windows over the columns, fuller columns first.
            let base = n / k, extra = n % k
            var result: [CellRect] = []
            for (i, run) in colRuns.enumerated() {
                let inThisColumn = base + (i < extra ? 1 : 0)
                guard inThisColumn > 0 else { continue }
                for rowRun in split(g.rows, into: inThisColumn) {
                    result.append(CellRect(col: run.start, row: rowRun.start,
                                           w: run.length, h: rowRun.length))
                }
            }
            return result
        }
    }

    // MARK: Applying

    /// Arranges the given windows on one screen. Returns how many actually moved.
    ///
    /// The grid is a promise about sizes: a 3×2 means six tiles, not "as many slivers as there
    /// are windows". So only the frontmost `cols × rows` windows are tiled and everything
    /// further back is left exactly where it is.
    @discardableResult
    static func apply(_ windows: [ManagedWindow], on screen: NSScreen,
                      strategy: ArrangeStrategy) -> Int {
        let grid = Store.shared.config.grid(for: screen.tesseraKey)
        let aspect = screen.visibleFrame.width / screen.visibleFrame.height
        let chosen = AX.sortedFrontToBack(windows).prefix(grid.cols * grid.rows)
        // Left-to-right, top-to-bottom: keep the arrangement close to where things already were,
        // so windows travel the shortest distance to their tile.
        let ordered = chosen.sorted { a, b in
            let fa = a.frame ?? .zero, fb = b.frame ?? .zero
            return fa.minX == fb.minX ? fa.maxY > fb.maxY : fa.minX < fb.minX
        }
        let cells = partition(count: ordered.count, grid: grid, screenAspect: aspect, strategy: strategy)
        var moved = 0
        for (window, cell) in zip(ordered, cells) where AX.place(window, in: cell, on: screen) {
            moved += 1
        }
        return moved
    }

    /// How many windows "arrange all" would move on this screen, and how many it would leave alone.
    static func plan(on screen: NSScreen) -> (tiled: Int, untouched: Int) {
        let grid = Store.shared.config.grid(for: screen.tesseraKey)
        let total = windows(on: screen).count
        let tiled = min(total, grid.cols * grid.rows)
        return (tiled, total - tiled)
    }

    /// Every placeable window currently on this screen and on this Space.
    static func windows(on screen: NSScreen) -> [ManagedWindow] {
        let key = screen.tesseraKey
        return AX.onCurrentSpace(AX.allWindows()).filter { window in
            guard let frame = window.frame, frame.width > 1, frame.height > 1 else { return false }
            // Compare by screen key, not object identity: NSScreen hands out fresh instances.
            return AX.screen(of: window).tesseraKey == key
        }
    }

    // MARK: Auto-fit a single window

    /// The largest free rectangle of cells on a screen, ignoring `excluding` (the window being
    /// placed). Nil when the grid is full.
    static func largestFreeCell(on screen: NSScreen, excluding: ManagedWindow? = nil) -> CellRect? {
        let grid = Store.shared.config.grid(for: screen.tesseraKey)
        var occupied = Array(repeating: Array(repeating: false, count: grid.cols), count: grid.rows)
        for window in windows(on: screen) {
            if let excluding, CFEqual(window.element, excluding.element) { continue }
            guard let frame = window.frame else { continue }
            let cell = Geometry.nearestCell(for: frame, in: grid, on: screen.visibleFrame)
            for r in cell.row...cell.maxRow where r < grid.rows {
                for c in cell.col...cell.maxCol where c < grid.cols { occupied[r][c] = true }
            }
        }
        return largestRect(free: occupied, cols: grid.cols, rows: grid.rows)
    }

    /// Maximal all-free rectangle, by the usual largest-rectangle-in-histogram scan.
    static func largestRect(free occupied: [[Bool]], cols: Int, rows: Int) -> CellRect? {
        var heights = Array(repeating: 0, count: cols)
        var best: CellRect?
        var bestArea = 0
        for r in 0..<rows {
            for c in 0..<cols { heights[c] = occupied[r][c] ? 0 : heights[c] + 1 }
            // Histogram scan with a stack of increasing bars.
            var stack: [(startCol: Int, height: Int)] = []
            for c in 0...cols {
                let height = c < cols ? heights[c] : 0
                var start = c
                while let top = stack.last, top.height >= height {
                    stack.removeLast()
                    let area = top.height * (c - top.startCol)
                    if area > bestArea {
                        bestArea = area
                        best = CellRect(col: top.startCol, row: r - top.height + 1,
                                        w: c - top.startCol, h: top.height)
                    }
                    start = top.startCol
                }
                if height > 0 { stack.append((start, height)) }
            }
        }
        return bestArea > 0 ? best : nil
    }

    /// Drops one window into the biggest hole on its screen. Used by "auto-fit" and, when the
    /// option is on, by the watcher that sees a new window appear.
    @discardableResult
    static func fit(_ window: ManagedWindow) -> Bool {
        let screen = AX.screen(of: window)
        guard let cell = largestFreeCell(on: screen, excluding: window) else { return false }
        return AX.place(window, in: cell, on: screen)
    }
}
