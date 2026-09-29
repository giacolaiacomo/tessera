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
        check(!cover.contains(0), "\(strategy) n=\(n): uncovered cells")
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

print(failures == 0 ? "ALL GEOMETRY CHECKS PASSED" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
