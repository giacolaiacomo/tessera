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
        case .balanced:    return tr("Balanced")
        case .cells:       return tr("One per cell")
        case .columns:     return tr("Columns")
        case .rows:        return tr("Rows")
        case .masterStack: return tr("Master + stack")
        }
    }

    var detail: String {
        switch self {
        case .balanced:    return tr("Fills the screen, splitting it into tiles as square as it can.")
        case .cells:       return tr("One window per grid cell, in reading order: on a 3×2 every window is a sixth of the screen, even when there are fewer than six.")
        case .columns:     return tr("One column each, as tall as the screen.")
        case .rows:        return tr("One row each, as wide as the screen.")
        case .masterStack: return tr("The front window large on the left, the rest stacked on the right.")
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

    /// Arranges the windows of one screen: work out every rectangle first, then set each
    /// window once.
    ///
    /// There is nothing to discover at run time. The screen size is known, the window count is
    /// known, so the grid and every target rectangle are known — the arrangement is a piece of
    /// arithmetic, not a negotiation. A window is written once and left alone; the read at the
    /// end is only for the report, and moves nothing.
    ///
    /// The grid is also a promise about sizes: a 3×2 means six tiles, not "as many slivers as
    /// there are windows", so only the frontmost `cols × rows` windows are tiled and the rest
    /// stay where they are.
    @discardableResult
    static func apply(_ windows: [ManagedWindow], on screen: NSScreen,
                      strategy: ArrangeStrategy) -> Int {
        let grid = refreshAutoGrid(on: screen)
        let visible = screen.visibleFrame
        let chosen = AX.sortedFrontToBack(windows).prefix(grid.cols * grid.rows)
        // Reading order, so each window ends up near where it already was.
        let ordered = chosen.sorted { a, b in
            let fa = a.frame ?? CGRect.zero, fb = b.frame ?? CGRect.zero
            return fa.minX == fb.minX ? fa.maxY > fb.maxY : fa.minX < fb.minX
        }
        let cells = partition(count: ordered.count, grid: grid,
                              screenAspect: visible.width / visible.height, strategy: strategy,
                              masterFraction: Store.shared.config.masterFraction)
        let moves = zip(ordered, cells).map { window, cell in
            (window: window, target: Geometry.frame(for: cell, in: grid, on: visible))
        }

        var errors: [String] = []
        for (window, target) in moves {
            // An app answers on its own run loop: two windows of the same app go through one
            // process, and fired back to back it keeps the first and drops the rest. A pause
            // too short to see is all it needs to keep up.
            let current = window.frame ?? CGRect.zero
            // A window filling the screen ignores a resize until it leaves that state.
            let fillsScreen = abs(current.width - visible.width) < 4
                && abs(current.height - visible.height) < 4
            let result = AX.writeFrame(window.element, to: target, shrinkFirst: fillsScreen)
            errors.append("pos \(result.position.rawValue)/size \(result.size.rawValue)"
                          + " asked \(Int(target.width))×\(Int(target.height))")
            usleep(80_000)
        }

        // Everyone has been told once. After a moment to answer, a single corrective write goes
        // only to the windows still far from their cell — a window keeping its own minimum size
        // is within tolerance and is left alone.
        usleep(250_000)
        func missedIts(_ target: CGRect, _ window: AXUIElement) -> Bool {
            guard let now = AX.frame(of: window) else { return false }
            // Judged on the AX corner: a window that snaps to its own row height keeps that
            // corner and only its bottom moves, so it is not chased for nothing.
            let here = AX.toAX(now), there = AX.toAX(target)
            return abs(here.minX - there.minX) > 4 || abs(here.minY - there.minY) > 4
                || abs(here.width - there.width) > 24 || abs(here.height - there.height) > 24
        }
        var corrected = false
        for (window, target) in moves where missedIts(target, window.element) {
            AX.writeFrame(window.element, to: target)
            usleep(80_000)
            corrected = true
        }
        if corrected { usleep(250_000) }

        lastOutcomes = zip(moves, errors).map { move, error in
            let outcome = AX.inspect(move.window.element, against: move.target)
            if case .didNotMove = outcome {
                return (move.window.appName + " [\(error)]", outcome)
            }
            return (move.window.appName, outcome)
        }
        return lastOutcomes.filter { $0.outcome.succeeded }.count
    }

    /// What happened to each window in the last arrangement, for `--arrange` to report.
    private(set) static var lastOutcomes: [(app: String, outcome: AX.PlacementOutcome)] = []

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

    // MARK: Choosing the grid for you

    /// The grid that shows `n` windows at once on this screen, all of them visible.
    ///
    /// Two things are traded off: tiles should be roughly `targetAspect` (a window is more
    /// usable wide than tall), and cells should not be left over. On a 34" ultrawide four
    /// windows come out 2×2, six come out 3×2; on the laptop four come out 2×2 as well.
    static func bestGrid(for n: Int, on screen: NSScreen, like existing: GridSpec,
                         targetAspect: CGFloat = 1.45) -> GridSpec {
        bestGrid(for: n, fitting: screen.visibleFrame, like: existing, targetAspect: targetAspect)
    }

    static func bestGrid(for n: Int, fitting frame: CGRect, like existing: GridSpec,
                         targetAspect: CGFloat = 1.45) -> GridSpec {
        guard n > 0, frame.height > 0 else { return existing }
        let aspect = frame.width / frame.height
        var best = (cols: 1, rows: n)
        var bestScore = CGFloat.greatestFiniteMagnitude
        for cols in 1...n {
            let rows = Int(ceil(Double(n) / Double(cols)))
            let spare = cols * rows - n
            // A couple of empty cells are tolerable if they buy a much better shape; a grid
            // that is mostly holes is not what "show me everything" means.
            guard spare <= max(1, n / 3) else { continue }
            let tileAspect = (aspect / CGFloat(cols)) * CGFloat(rows)
            let score = abs(log(tileAspect / targetAspect)) + CGFloat(spare) * 0.35
            if score < bestScore {
                bestScore = score
                best = (cols, rows)
            }
        }
        return GridSpec(cols: best.cols, rows: best.rows,
                        outerGap: existing.outerGap, innerGap: existing.innerGap)
    }

    /// Set while an automatic grid is being written, so the "re-tile when the grid changes"
    /// rule does not fire: opening the popover must never move someone's windows.
    private(set) static var isWritingAutoGrid = false

    /// Stores a computed grid without waking the "re-tile when the grid changes" rule.
    static func writeGrid(_ grid: GridSpec, for screenKey: String) {
        guard Store.shared.config.grid(for: screenKey) != grid else { return }
        isWritingAutoGrid = true
        Store.shared.mutate { $0.grids[screenKey] = grid }
        isWritingAutoGrid = false
    }

    /// Brings a screen's stored grid in line with how many windows are open, when that screen
    /// is in automatic mode. Returns the grid to use either way.
    ///
    /// Only an arrangement may call this. Recomputing it on every read — a popover opening, a
    /// diagnostic — made the grid shift under the windows that were already placed in it: you
    /// tile four windows into 2×2, close one, and the layout you were looking at is suddenly
    /// described by a 3×1 grid nobody applied.
    @discardableResult
    static func refreshAutoGrid(on screen: NSScreen) -> GridSpec {
        let key = screen.tesseraKey
        let config = Store.shared.config
        let current = config.grid(for: key)
        guard config.isAutoGrid(key) else { return current }
        let wanted = bestGrid(for: windows(on: screen).count, on: screen, like: current)
        writeGrid(wanted, for: key)
        return wanted
    }

    // MARK: What the screen looks like right now

    /// One entry per window on a screen, snapped to the cell it currently occupies — the data
    /// behind the popover's live map. `resistant` marks the windows an arrangement cannot place
    /// exactly (a full-screen window, or one whose minimum size is bigger than its cell).
    struct Occupant {
        let appName: String
        let cell: CellRect
        let isFocused: Bool
        let resistant: Bool
    }

    static func occupancy(on screen: NSScreen) -> [Occupant] {
        let grid = Store.shared.config.grid(for: screen.tesseraKey)
        let focused = AX.focusedWindow()
        let cellCount = grid.cols * grid.rows
        return AX.sortedFrontToBack(windows(on: screen)).enumerated().compactMap { index, window in
            guard let frame = window.frame else { return nil }
            let cell = Geometry.nearestCell(for: frame, in: grid, on: screen.visibleFrame)
            let cellSize = Geometry.frame(for: cell, in: grid, on: screen.visibleFrame)
            return Occupant(appName: window.appName,
                            cell: cell,
                            isFocused: focused.map { CFEqual($0.element, window.element) } ?? false,
                            // Bigger than the cell it sits in, or past what the grid can tile.
                            resistant: index >= cellCount
                                || frame.width > cellSize.width + 8
                                || frame.height > cellSize.height + 8)
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

