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
    /// Which window goes into which cell.
    ///
    /// The cells are settled and so is the set of windows: all that is left to choose is the
    /// pairing, and the one that moves the windows least is the one that looks like the screen
    /// tidying itself instead of reshuffling. Reading order is only where the search starts;
    /// from there, swapping any two windows is tried until no swap shortens the total travel.
    /// Distances are measured between centres, so a window already sitting on its cell stays.
    static func pairing(current: [CGRect], targets: [CGRect]) -> [Int] {
        precondition(current.count == targets.count)
        var assignment = Array(current.indices)

        func travel(_ window: Int, _ target: Int) -> CGFloat {
            let a = CGPoint(x: current[window].midX, y: current[window].midY)
            let b = CGPoint(x: targets[target].midX, y: targets[target].midY)
            return hypot(a.x - b.x, a.y - b.y)
        }

        var improved = true
        while improved {
            improved = false
            for i in assignment.indices {
                for j in assignment.indices where j > i {
                    let now = travel(i, assignment[i]) + travel(j, assignment[j])
                    let swapped = travel(i, assignment[j]) + travel(j, assignment[i])
                    // A strict improvement only: equal costs keep reading order, which is the
                    // predictable answer when two windows are the same distance from two cells.
                    if swapped < now - 0.5 {
                        assignment.swapAt(i, j)
                        improved = true
                    }
                }
            }
        }
        return assignment
    }

    // MARK: What an app will accept

    /// Whether this app is known not to fit a cell of this size. An app never seen refusing
    /// anything is assumed to fit: that is how it gets the chance to prove otherwise.
    static func fits(_ window: ManagedWindow, in cell: CGSize) -> Bool {
        guard let minimum = Store.shared.config.minimum(forBundle: window.bundleID) else { return true }
        return minimum.width <= cell.width + 2 && minimum.height <= cell.height + 2
    }

    /// Records what the last arrangement taught us. A window that kept its own size was asked
    /// for something smaller and refused: the size it kept is an upper bound on its minimum,
    /// so the smallest refusal ever seen is the best estimate we have.
    private static func learn(from outcomes: [(window: ManagedWindow, outcome: AX.PlacementOutcome)]) {
        var learned: [String: [Double]] = [:]
        for (window, outcome) in outcomes {
            guard case .ownSize(let size) = outcome, !window.bundleID.isEmpty else { continue }
            let known = Store.shared.config.minimum(forBundle: window.bundleID)
            let width = min(Double(size.width), Double(known?.width ?? .greatestFiniteMagnitude))
            let height = min(Double(size.height), Double(known?.height ?? .greatestFiniteMagnitude))
            if known == nil || width < Double(known!.width) - 1 || height < Double(known!.height) - 1 {
                learned[window.bundleID] = [width, height]
            }
        }
        guard !learned.isEmpty else { return }
        Store.shared.mutate { config in
            for (bundle, size) in learned { config.minimums[bundle] = size }
        }
    }

    /// The size of one cell of a grid on a screen.
    static func cellSize(of grid: GridSpec, on frame: CGRect) -> CGSize {
        Geometry.frame(for: CellRect(col: 0, row: 0), in: grid, on: frame).size
    }

    /// The moves an arrangement would make: which window into which cell, and the rectangle
    /// that cell is. `apply` and `--diagnose` both go through here, so what the diagnostics
    /// print is what would really happen — including the pairing.
    static func moves(for windows: [ManagedWindow], on screen: NSScreen, grid: GridSpec,
                      strategy: ArrangeStrategy)
        -> [(window: ManagedWindow, cell: CellRect, target: CGRect)] {
        let visible = screen.visibleFrame
        // On an automatic screen the grid is Tessera's own choice, so it must not put a window
        // in a cell the app will refuse: the ones that cannot fit are left where they are and
        // counted as untouched. A grid the user set by hand is obeyed as it is.
        let candidates = Store.shared.config.isAutoGrid(screen.tesseraKey)
            ? windows.filter { fits($0, in: cellSize(of: grid, on: visible)) }
            : windows
        let chosen = AX.sortedFrontToBack(candidates).prefix(grid.cols * grid.rows)
        // Reading order first, so the pairing starts from the predictable answer.
        let ordered = chosen.sorted { a, b in
            let fa = a.frame ?? CGRect.zero, fb = b.frame ?? CGRect.zero
            return fa.minX == fb.minX ? fa.maxY > fb.maxY : fa.minX < fb.minX
        }
        let cells = partition(count: ordered.count, grid: grid,
                              screenAspect: visible.width / visible.height, strategy: strategy,
                              masterFraction: Store.shared.config.masterFraction)
        let targets = cells.map { Geometry.frame(for: $0, in: grid, on: visible) }
        let frames = ordered.map { $0.frame ?? CGRect.zero }
        return pairing(current: frames, targets: targets).enumerated().map { index, target in
            (window: ordered[index], cell: cells[target], target: targets[target])
        }
    }

    /// There is nothing to discover at run time. The screen size is known, the window count is
    /// known, so the grid and every target rectangle are known — the arrangement is a piece of
    /// arithmetic, not a negotiation. A window is written once and left alone; the read at the
    /// end is only for the report, and moves nothing.
    ///
    /// Every window is written back to back, without pausing between them: an app applies the
    /// write on its own run loop and answers in its own time, and nothing here reads until they
    /// have all been told. The one thing that must not happen is reading too early and
    /// correcting on a stale answer — that is what used to cancel a resize in flight.
    ///
    /// The grid is also a promise about sizes: a 3×2 means six tiles, not "as many slivers as
    /// there are windows", so only the frontmost `cols × rows` windows are tiled and the rest
    /// stay where they are.
    @discardableResult
    static func apply(_ windows: [ManagedWindow], on screen: NSScreen,
                      strategy: ArrangeStrategy) -> Int {
        let clock = Clock()
        let grid = refreshAutoGrid(on: screen)
        let visible = screen.visibleFrame
        let moves = moves(for: windows, on: screen, grid: grid, strategy: strategy)
        clock.mark("plan")

        var errors: [String] = []
        var before: [CGRect] = []
        lastCorrections = 0
        for (window, _, target) in moves {
            let current = window.frame ?? CGRect.zero
            before.append(current)
            // A window filling the screen ignores a resize until it leaves that state.
            let fillsScreen = abs(current.width - visible.width) < 4
                && abs(current.height - visible.height) < 4
            let result = AX.writeFrame(window.element, to: target, shrinkFirst: fillsScreen)
            errors.append("pos \(result.position.rawValue)/size \(result.size.rawValue)"
                          + " asked \(Int(target.width))×\(Int(target.height))")
        }
        clock.mark("write")

        func landed(_ index: Int) -> Bool {
            guard let now = AX.frame(of: moves[index].window.element) else { return true }
            let here = AX.toAX(now), there = AX.toAX(moves[index].target)
            return abs(here.minX - there.minX) <= 4 && abs(here.minY - there.minY) <= 4
                && abs(here.width - there.width) <= 24 && abs(here.height - there.height) <= 24
        }

        // Everyone has been told once. Now wait for the answers — an app applies the write on
        // its own run loop and takes its own time, and reading before it has is what used to
        // make Tessera "correct" a move that was still in flight.
        //
        // What is waited for is the one thing that can actually be observed: the frames have
        // stopped changing. Two identical reads in a row and the screen is done moving. Every
        // cleverer test tried here was a guess about what an app meant — "is it on its corner?"
        // read an app with a minimum size as a window that never answered, and "did anything
        // change?" read a window that was already in its final place as a dropped write. Both
        // guesses cost the full timeout and then a pointless second write. Stillness is not a
        // guess.
        // Which windows were actually asked for something. A window already sitting on its cell
        // was not, and waiting for it to change is waiting for something that will never happen
        // — that distinction is the whole reason this is not just "wait until nothing moves".
        let asked = moves.indices.filter { !AX.same(before[$0], moves[$0].target) }
        var rounds = 0
        var quiet = 0
        var previous: [CGRect?] = before.map { $0 }
        let giveUp = DispatchTime.now().uptimeNanoseconds + 600_000_000
        while DispatchTime.now().uptimeNanoseconds < giveUp {
            usleep(20_000)
            rounds += 1
            let now = moves.map { AX.frame(of: $0.window.element) }
            let still = zip(now, previous).allSatisfy(AX.same)
            // Stillness alone is not an answer: a window that has not started moving yet is
            // just as still as one that has finished. Every window that was asked for something
            // has to have visibly answered first — otherwise the correction below reads a frame
            // from before the resize and puts the window in the right place at the old size,
            // which is exactly what "it arranged them but did not resize them" looks like.
            let answered = asked.allSatisfy { index in
                guard let current = now[index] else { return true }
                if !AX.same(current, before[index]) { return true }
                // Nothing has changed — which is also an answer when the window is already on
                // its cell's corner and only its size is wrong. That is an app refusing a size,
                // and an app refuses instantly; there is nothing in flight to wait for. Only a
                // window that is neither where it was asked to be nor moving has said nothing.
                let here = AX.toAX(current), there = AX.toAX(moves[index].target)
                return abs(here.minX - there.minX) <= 4 && abs(here.minY - there.minY) <= 4
            }
            previous = now
            // One quiet read is not enough. Chrome does not resize in one go, it animates, and
            // two reads 20 ms apart can both land in the same lull — which is how an
            // arrangement came out positioned but not resized, and how Tessera then "learned"
            // a minimum size for Chrome that was really just a frame caught in mid-air. Three
            // consecutive quiet reads, 60 ms of nothing happening, is an answer.
            quiet = still ? quiet + 1 : 0
            if quiet >= 3 && answered { break }
        }
        clock.mark("settle ×\(rounds)")


        // A window that has not landed and whose app is not known to refuse a cell this size did
        // not get the whole message: a position took and a size did not, or the app was busy
        // with the window before it — several windows of one app go through one process, and it
        // does not always keep up. The cure is to repeat the request, in full, exactly as it was
        // made. Repeating the *target* is safe. What is never safe, and was the last bug here,
        // is writing back a size read off the window a moment earlier: that one cancels a
        // resize still in flight.
        // Asked once more, and then once more again if it is still not there. Terminal growing
        // from small to large overshoots the height it was given by about sixty pixels and then
        // takes the right one when asked a second time from where it now is, which is precisely
        // why clicking "Arrange all" twice used to work. Two extra rounds is what that second
        // click was, done here. Nothing is asked of a window already on its cell, or of an app
        // known to need more room than the cell has, so a screen that lands first time pays
        // nothing for this.
        for _ in 0..<2 {
            let missing = moves.indices.filter {
                !landed($0) && fits(moves[$0].window, in: moves[$0].target.size)
            }
            guard !missing.isEmpty else { break }
            usleep(120_000)
            for index in missing {
                AX.writeFrame(moves[index].window.element, to: moves[index].target)
                lastCorrections += 1
            }
            waitForStillness(moves.map { $0.window.element }, upTo: 400)
        }
        clock.mark("repeat ×\(lastCorrections)")

        // One corrective pass, and it is the same one for both things that can have gone wrong:
        // a write the app dropped, and an app that refused the size of its cell and is now
        // hanging off the edge of the screen. Either way the answer is the same — keep whatever
        // size the window has settled on, put its top-left on the cell's corner, and slide it
        // back inside the visible area. Writing a position a window already holds costs nothing
        // and moves nothing, so this does not need to know which case it is looking at.
        var slid = false
        for index in moves.indices {
            guard let now = AX.frame(of: moves[index].window.element), !landed(index) else { continue }
            let target = moves[index].target
            var rect = CGRect(x: target.minX, y: target.maxY - now.height,
                              width: now.width, height: now.height)
            rect.origin.x = min(max(rect.minX, visible.minX),
                                max(visible.minX, visible.maxX - rect.width))
            rect.origin.y = min(max(rect.minY, visible.minY),
                                max(visible.minY, visible.maxY - rect.height))
            guard abs(rect.minX - now.minX) > 2 || abs(rect.minY - now.minY) > 2 else { continue }
            AX.writePosition(moves[index].window.element, to: AX.toAX(rect).origin)
            lastCorrections += 1
            slid = true
        }
        // Only a window that was actually slid needs time to answer before the report reads it,
        // and it is asked by looking, like everything else here. This used to be a flat tenth of
        // a second paid on every arrangement, including the ones where nothing moved at all.
        if slid { waitForStillness(moves.map { $0.window.element }, upTo: 200) }
        clock.mark("slide")

        lastOutcomes = zip(moves, errors).map { move, error in
            let outcome = AX.inspect(move.window.element, against: move.target)
            if case .didNotMove = outcome {
                return (move.window.appName + " [\(error)]", outcome)
            }
            return (move.window.appName, outcome)
        }
        learn(from: zip(moves, lastOutcomes).map { (window: $0.window, outcome: $1.outcome) })
        clock.mark("report")
        lastTiming = clock.report(offBy: moves.indices.map { index in
            guard let now = AX.frame(of: moves[index].window.element) else { return .zero }
            let here = AX.toAX(now), there = AX.toAX(moves[index].target)
            return CGRect(x: here.minX - there.minX, y: here.minY - there.minY,
                          width: here.width - there.width, height: here.height - there.height)
        })
        return lastOutcomes.filter { $0.outcome.succeeded }.count
    }

    /// Waits until a set of windows has stopped changing shape, or until the budget runs out.
    /// Three quiet reads, because an app that animates a resize pauses between steps and two
    /// reads can fall in the same pause.
    private static func waitForStillness(_ windows: [AXUIElement], upTo milliseconds: UInt64) {
        var previous = windows.map { AX.frame(of: $0) }
        var quiet = 0
        let until = DispatchTime.now().uptimeNanoseconds + milliseconds * 1_000_000
        while DispatchTime.now().uptimeNanoseconds < until {
            usleep(20_000)
            let now = windows.map { AX.frame(of: $0) }
            quiet = zip(now, previous).allSatisfy(AX.same) ? quiet + 1 : 0
            previous = now
            if quiet >= 3 { return }
        }
    }

    /// Where the milliseconds of the last arrangement went, and how far off its target each
    /// window ended up. "It lags" and "it is not precise" are not things anyone can fix; a line
    /// saying the waiting cost 240 ms of the 260, and that Terminal landed 3 px short, is.
    private(set) static var lastTiming = ""

    /// A stopwatch with named laps. Nothing here touches a window.
    final class Clock {
        private let start = DispatchTime.now()
        private var last = DispatchTime.now()
        private var laps: [(name: String, ms: Double)] = []

        func mark(_ name: String) {
            let now = DispatchTime.now()
            laps.append((name, Double(now.uptimeNanoseconds - last.uptimeNanoseconds) / 1e6))
            last = now
        }

        func report(offBy: [CGRect]) -> String {
            let total = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e6
            let breakdown = laps.map { "\($0.name) \(Int($0.ms.rounded()))" }.joined(separator: ", ")
            let drift = offBy.map { rect -> String in
                let values = [rect.minX, rect.minY, rect.width, rect.height]
                return values.allSatisfy { abs($0) < 0.5 }
                    ? "exact"
                    : "\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))×\(Int(rect.height))"
            }.joined(separator: " | ")
            return "  timing: \(Int(total.rounded())) ms — \(breakdown)\n  off target: \(drift)"
        }
    }

    /// What happened to each window in the last arrangement, for `--arrange` to report.
    /// How many windows needed the one corrective write on the last arrangement. Zero means
    /// every window landed on the first try.
    private(set) static var lastCorrections = 0

    private(set) static var lastOutcomes: [(app: String, outcome: AX.PlacementOutcome)] = []

    /// How many windows "arrange all" would move on this screen, and how many it would leave alone.
    static func plan(on screen: NSScreen) -> (tiled: Int, untouched: Int) {
        let grid = Store.shared.config.grid(for: screen.tesseraKey)
        let open = windows(on: screen)
        // Through the same planner the arrangement uses, or the count promises one thing and
        // the arrangement does another.
        let tiled = moves(for: open, on: screen, grid: grid,
                          strategy: Store.shared.config.defaultStrategy).count
        return (tiled, open.count - tiled)
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
                         targetAspect: CGFloat = 1.45, needs: [CGSize?] = []) -> GridSpec {
        bestGrid(for: n, fitting: screen.visibleFrame, like: existing,
                 targetAspect: targetAspect, needs: needs)
    }

    static func bestGrid(for n: Int, fitting frame: CGRect, like existing: GridSpec,
                         targetAspect: CGFloat = 1.45, needs: [CGSize?] = []) -> GridSpec {
        guard n > 0, frame.height > 0 else { return existing }
        let aspect = frame.width / frame.height

        /// How many of these windows could actually use a cell this size. An app nothing is
        /// known about counts as fitting: it has never refused anything.
        func usable(_ cell: CGSize) -> Int {
            guard !needs.isEmpty else { return n }
            return needs.filter { $0 == nil || ($0!.width <= cell.width + 2 && $0!.height <= cell.height + 2) }.count
        }

        var best = (cols: 1, rows: n)
        var bestShown = -1
        var bestScore = CGFloat.greatestFiniteMagnitude
        for cols in 1...max(n, 1) {
            for rows in 1...max(n, 1) {
                let cells = cols * rows
                // Cells nobody asked for: a couple are worth a better shape, a grid that is
                // mostly holes is not what "show me everything" means.
                let spare = max(0, cells - n)
                guard spare <= max(1, n / 3) else { continue }
                let candidate = GridSpec(cols: cols, rows: rows,
                                         outerGap: existing.outerGap, innerGap: existing.innerGap)
                let cell = cellSize(of: candidate, on: frame)
                guard cell.width > 1, cell.height > 1 else { continue }
                // Windows that would actually be visible in this grid. Fewer cells than there
                // are windows is allowed — on a small screen with demanding apps it is the
                // honest answer, and the windows left over stay where they are.
                let shown = min(usable(cell), cells)
                let tileAspect = (aspect / CGFloat(cols)) * CGFloat(rows)
                let score = abs(log(tileAspect / targetAspect)) + CGFloat(spare) * 0.35
                if shown > bestShown || (shown == bestShown && score < bestScore) {
                    bestShown = shown
                    bestScore = score
                    best = (cols, rows)
                }
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
        // What the apps on this screen are known to need, so the grid never proposes cells
        // they will refuse: on a laptop screen with demanding apps that means fewer, bigger
        // cells, and the windows that do not fit are left alone rather than piled up.
        let open = windows(on: screen)
        let needs = open.map { Store.shared.config.minimum(forBundle: $0.bundleID) }
        let wanted = bestGrid(for: open.count, on: screen, like: current, needs: needs)
        writeGrid(wanted, for: key)
        return wanted
    }

    // MARK: What the screen looks like right now

    /// One entry per window on a screen, snapped to the cell it currently occupies — the data
    /// behind the popover's live map. `resistant` marks the windows an arrangement cannot place
    /// exactly (a full-screen window, or one whose minimum size is bigger than its cell).
    struct Occupant {
        /// The window itself, so the map can move this one and not the front one.
        let window: ManagedWindow
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
            return Occupant(window: window,
                            appName: window.appName,
                            cell: cell,
                            isFocused: focused.map { CFEqual($0.element, window.element) } ?? false,
                            // Dashed means "this one will not take that cell": an app known not
                            // to go that small, or a window past what the grid can tile. Being
                            // large right now is not the same thing — most windows shrink when
                            // asked, and marking those would cry wolf.
                            resistant: index >= cellCount || !fits(window, in: cellSize.size))
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

