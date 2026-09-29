// Numeric checks for the pure geometry: no UI, no Accessibility, just the maths.
import AppKit

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { failures += 1; print("FAIL \(what)") }
}

let vf = CGRect(x: 0, y: 25, width: 3840, height: 2135)   // a 4K screen minus the menu bar
let grid = GridSpec(cols: 12, rows: 8, outerGap: 8, innerGap: 8)

// 1. The grid fills the visible frame exactly, inside the outer gap.
let topLeft = Geometry.frame(for: CellRect(col: 0, row: 0), in: grid, on: vf)
let bottomRight = Geometry.frame(for: CellRect(col: 11, row: 7), in: grid, on: vf)
check(abs(topLeft.minX - (vf.minX + 8)) < 1, "left edge: \(topLeft.minX)")
check(abs(topLeft.maxY - (vf.maxY - 8)) < 1, "top edge: \(topLeft.maxY)")
check(abs(bottomRight.maxX - (vf.maxX - 8)) < 1, "right edge: \(bottomRight.maxX)")
check(abs(bottomRight.minY - (vf.minY + 8)) < 1, "bottom edge: \(bottomRight.minY)")

// 2. Neighbours are exactly innerGap apart, and a span equals the union of its cells.
let a = Geometry.frame(for: CellRect(col: 3, row: 2), in: grid, on: vf)
let b = Geometry.frame(for: CellRect(col: 4, row: 2), in: grid, on: vf)
check(abs((b.minX - a.maxX) - 8) < 1, "inner gap: \(b.minX - a.maxX)")
let span = Geometry.frame(for: CellRect(col: 3, row: 2, w: 2, h: 1), in: grid, on: vf)
check(abs(span.minX - a.minX) < 1 && abs(span.maxX - b.maxX) < 1, "span == union: \(span) vs \(a)|\(b)")

// 3. Every cell's centre maps back to that cell, and a placed frame reads back as its own cell.
for r in 0..<grid.rows {
    for c in 0..<grid.cols {
        let cell = CellRect(col: c, row: r)
        let frame = Geometry.frame(for: cell, in: grid, on: vf)
        let hit = Geometry.cell(at: CGPoint(x: frame.midX, y: frame.midY), in: grid, on: vf)
        check(hit?.col == c && hit?.row == r, "cell(at:) \(c),\(r) -> \(String(describing: hit))")
        check(Geometry.nearestCell(for: frame, in: grid, on: vf) == cell, "nearestCell \(c),\(r)")
    }
}
// Multi-cell windows read back as the area they cover.
let big = CellRect(col: 2, row: 1, w: 5, h: 3)
check(Geometry.nearestCell(for: Geometry.frame(for: big, in: grid, on: vf), in: grid, on: vf) == big,
      "nearestCell on a span")

// 4. Every strategy partitions every grid: n tiles, no overlap, full coverage.
for grid in [GridSpec(cols: 12, rows: 8, outerGap: 8, innerGap: 8),
             GridSpec(cols: 2, rows: 2, outerGap: 0, innerGap: 0),
             GridSpec(cols: 3, rows: 2, outerGap: 12, innerGap: 4),
             GridSpec(cols: 16, rows: 9, outerGap: 2, innerGap: 2)] {
for strategy in ArrangeStrategy.allCases {
    for n in 1...24 {
        let cells = AutoArrange.partition(count: n, grid: grid, screenAspect: vf.width / vf.height,
                                          strategy: strategy)
        check(cells.count == n, "\(strategy) n=\(n): got \(cells.count) tiles")
        guard n <= grid.cols * grid.rows else { continue }
        var cover = Array(repeating: 0, count: grid.cols * grid.rows)
        for cell in cells {
            for r in cell.row...cell.maxRow {
                for c in cell.col...cell.maxCol { cover[r * grid.cols + c] += 1 }
            }
        }
        check(!cover.contains(where: { $0 > 1 }), "\(strategy) n=\(n): overlapping tiles")
        if strategy == .cells {
            // One cell each, in reading order: coverage is n cells, no more.
            check(cover.filter { $0 == 1 }.count == n, "\(strategy) n=\(n): \(cover.filter { $0 == 1 }.count) cells used")
        } else {
            check(!cover.contains(0), "\(strategy) n=\(n): uncovered cells")
        }
    }
}
}

// 4b. The roundtrip holds on other grids and other screen shapes too.
for grid in [GridSpec(cols: 3, rows: 2, outerGap: 12, innerGap: 4),
             GridSpec(cols: 16, rows: 9, outerGap: 0, innerGap: 0)] {
    for screen in [vf, CGRect(x: -1512, y: 300, width: 1512, height: 945)] {
        for r in 0..<grid.rows {
            for c in 0..<grid.cols {
                let cell = CellRect(col: c, row: r)
                let frame = Geometry.frame(for: cell, in: grid, on: screen)
                check(Geometry.nearestCell(for: frame, in: grid, on: screen) == cell,
                      "roundtrip \(grid.cols)x\(grid.rows) on \(screen.width)x\(screen.height) at \(c),\(r)")
                check(screen.insetBy(dx: -1, dy: -1).contains(frame), "tile inside screen \(frame)")
            }
        }
    }
}

// 5. Largest free rectangle finds the real hole.
var occupied = Array(repeating: Array(repeating: false, count: 6), count: 4)
for r in 0..<4 { for c in 0..<3 { occupied[r][c] = true } }   // left half taken
check(AutoArrange.largestRect(free: occupied, cols: 6, rows: 4) == CellRect(col: 3, row: 0, w: 3, h: 4),
      "largest free rect: \(String(describing: AutoArrange.largestRect(free: occupied, cols: 6, rows: 4)))")
for r in 0..<4 { for c in 0..<6 { occupied[r][c] = true } }
check(AutoArrange.largestRect(free: occupied, cols: 6, rows: 4) == nil, "full grid -> nil")

// 6. A config written by another version still loads: unknown keys are ignored and missing
//    ones fall back, because throwing here would silently reset someone's grids.
let legacyJSON = """
{
  "grids": { "display-2": { "cols": 3, "rows": 2, "outerGap": 8, "innerGap": 8 } },
  "zones": [], "layouts": [],
  "showOverlayOnDrag": true, "overlayModifierOnly": false,
  "launchAtLogin": false, "autoFitNewWindows": false,
  "defaultStrategy": "balanced", "masterFraction": 0.6
}
""".data(using: .utf8)!
if let config = try? JSONDecoder().decode(Config.self, from: legacyJSON) {
    check(config.grid(for: "display-2") == GridSpec(cols: 3, rows: 2, outerGap: 8, innerGap: 8),
          "legacy config keeps its grid: \(config.grid(for: "display-2"))")
    check(config.rearrangeOnGridChange, "missing field falls back to its default")
} else {
    check(false, "legacy config failed to decode")
}
// The other direction: a file from a future version, with a key this build knows nothing about.
let futureJSON = """
{ "grids": { "display-9": { "cols": 4, "rows": 3, "outerGap": 0, "innerGap": 0 } },
  "somethingNew": 42, "defaultStrategy": "cells" }
""".data(using: .utf8)!
if let config = try? JSONDecoder().decode(Config.self, from: futureJSON) {
    check(config.grid(for: "display-9").cols == 4, "future config keeps its grid")
    check(config.defaultStrategy == .cells, "future config keeps its strategy")
} else {
    check(false, "future config failed to decode")
}

// 7. The automatic grid: every window visible, tiles as close to 3:2 as the screen allows.
let ultrawide = CGRect(x: 0, y: 0, width: 3440, height: 1410)   // Acer X34
let laptop = CGRect(x: 0, y: 0, width: 1512, height: 892)
for (frame, name) in [(ultrawide, "ultrawide"), (laptop, "laptop")] {
    for n in 1...12 {
        let grid = AutoArrange.bestGrid(for: n, fitting: frame, like: .default)
        check(grid.cols * grid.rows >= n, "\(name) n=\(n): \(grid.cols)×\(grid.rows) does not fit")
        check(grid.cols * grid.rows - n <= max(1, n / 3),
              "\(name) n=\(n): \(grid.cols)×\(grid.rows) wastes too many cells")
        // Every window has to be visible: the partition must give n distinct tiles.
        let cells = AutoArrange.partition(count: n, grid: grid,
                                          screenAspect: frame.width / frame.height, strategy: .cells)
        check(Set(cells).count == n, "\(name) n=\(n): duplicate cells")
    }
}
check(AutoArrange.bestGrid(for: 4, fitting: ultrawide, like: .default) == GridSpec(cols: 2, rows: 2),
      "ultrawide with 4 windows: \(AutoArrange.bestGrid(for: 4, fitting: ultrawide, like: .default))")
check(AutoArrange.bestGrid(for: 6, fitting: ultrawide, like: .default) == GridSpec(cols: 3, rows: 2),
      "ultrawide with 6 windows: \(AutoArrange.bestGrid(for: 6, fitting: ultrawide, like: .default))")
check(AutoArrange.bestGrid(for: 2, fitting: laptop, like: .default) == GridSpec(cols: 2, rows: 1),
      "laptop with 2 windows: \(AutoArrange.bestGrid(for: 2, fitting: laptop, like: .default))")
// The gaps the user chose are kept; only the cell count is decided for them.
let spaced = GridSpec(cols: 12, rows: 8, outerGap: 20, innerGap: 4)
let derived = AutoArrange.bestGrid(for: 5, fitting: ultrawide, like: spaced)
check(derived.outerGap == 20 && derived.innerGap == 4, "hand-picked gaps must be kept")

// MARK: - Pairing windows with cells

// Windows already sitting on their cells must not be shuffled: the pairing is the identity,
// whatever order they arrive in.
do {
    let grid = GridSpec(cols: 3, rows: 2)
    let cells = (0..<6).map { CellRect(col: $0 % 3, row: $0 / 3) }
    let targets = cells.map { Geometry.frame(for: $0, in: grid, on: ultrawide) }
    let shuffled = [4, 0, 5, 2, 1, 3]
    let current = shuffled.map { targets[$0] }
    let pairing = AutoArrange.pairing(current: current, targets: targets)
    check(pairing == shuffled, "windows already on a cell must stay: got \(pairing)")
}

// Whatever the starting positions, the pairing never travels further than reading order does.
do {
    let grid = GridSpec(cols: 4, rows: 2)
    let targets = (0..<8).map {
        Geometry.frame(for: CellRect(col: $0 % 4, row: $0 / 4), in: grid, on: ultrawide)
    }
    var seed: UInt64 = 12345
    func random(_ limit: CGFloat) -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(seed >> 33) / CGFloat(UInt32.max) * limit
    }
    func travel(_ pairing: [Int], _ current: [CGRect]) -> CGFloat {
        zip(current.indices, pairing).reduce(0) { total, pair in
            let a = current[pair.0], b = targets[pair.1]
            return total + hypot(a.midX - b.midX, a.midY - b.midY)
        }
    }
    for _ in 0..<200 {
        let current = (0..<8).map { _ in
            CGRect(x: ultrawide.minX + random(ultrawide.width - 400),
                   y: ultrawide.minY + random(ultrawide.height - 300),
                   width: 400, height: 300)
        }
        let pairing = AutoArrange.pairing(current: current, targets: targets)
        check(Set(pairing).count == 8, "every cell used exactly once: \(pairing)")
        check(travel(pairing, current) <= travel(Array(0..<8), current) + 0.001,
              "the pairing must not travel further than reading order")
    }
}

// MARK: - Cells that get in the way

// What counts as "already occupied" when a window is dropped on the map.
do {
    let tall = CellRect(col: 2, row: 0, w: 1, h: 2)
    check(tall.intersects(CellRect(col: 2, row: 1)), "a tall column contains the cell below it")
    check(CellRect(col: 2, row: 1).intersects(tall), "intersection is symmetric")
    check(!tall.intersects(CellRect(col: 1, row: 0)), "the next column over is not in the way")
    check(!tall.intersects(CellRect(col: 2, row: 2)), "the row under a 2-high column is free")
    check(CellRect(col: 0, row: 0, w: 3, h: 2).intersects(CellRect(col: 1, row: 1)),
          "a wide rectangle covers what is inside it")
    check(CellRect(col: 0, row: 0).intersects(CellRect(col: 0, row: 0)), "a cell is in its own way")
}

print(failures == 0 ? "ALL GEOMETRY CHECKS PASSED" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
