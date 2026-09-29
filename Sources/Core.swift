// Tessera — grid model, geometry and persistence.
//
// Coordinate note: everything public here speaks Cocoa coordinates (origin bottom-left of the
// primary screen, y growing up), the same as NSScreen. The Accessibility API speaks top-left
// coordinates; WindowsAX.swift owns that conversion and nothing else should do it.

import AppKit

let appVersion = "1.0.0"   // scripts/build-app.sh reads this for Info.plist
let bundleID = "com.tessera.menubar"

// MARK: - Grid

/// A screen's grid: how many cells, and the breathing room around and between them.
struct GridSpec: Codable, Equatable {
    var cols: Int = 12
    var rows: Int = 8
    var outerGap: CGFloat = 8
    var innerGap: CGFloat = 8

    static let `default` = GridSpec()

    init(cols: Int = 12, rows: Int = 8, outerGap: CGFloat = 8, innerGap: CGFloat = 8) {
        self.cols = cols
        self.rows = rows
        self.outerGap = outerGap
        self.innerGap = innerGap
    }

    /// Same leniency as `Config`: a missing field falls back instead of losing the grid.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cols = (try? container.decodeIfPresent(Int.self, forKey: .cols)).flatMap { $0 } ?? 12
        rows = (try? container.decodeIfPresent(Int.self, forKey: .rows)).flatMap { $0 } ?? 8
        outerGap = (try? container.decodeIfPresent(CGFloat.self, forKey: .outerGap)).flatMap { $0 } ?? 8
        innerGap = (try? container.decodeIfPresent(CGFloat.self, forKey: .innerGap)).flatMap { $0 } ?? 8
    }

    func clamped() -> GridSpec {
        GridSpec(cols: max(1, min(cols, 32)), rows: max(1, min(rows, 32)),
                 outerGap: max(0, min(outerGap, 80)), innerGap: max(0, min(innerGap, 80)))
    }
}

/// A rectangle of cells. `col`/`row` are 0-based, row 0 is the TOP row (what people point at).
struct CellRect: Codable, Equatable, Hashable {
    var col: Int
    var row: Int
    var w: Int = 1
    var h: Int = 1

    var maxCol: Int { col + w - 1 }
    var maxRow: Int { row + h - 1 }

    /// The rect covering both corners of a drag.
    static func spanning(_ a: (col: Int, row: Int), _ b: (col: Int, row: Int)) -> CellRect {
        let c0 = min(a.col, b.col), r0 = min(a.row, b.row)
        return CellRect(col: c0, row: r0, w: abs(a.col - b.col) + 1, h: abs(a.row - b.row) + 1)
    }

    func clamped(to grid: GridSpec) -> CellRect {
        let c = max(0, min(col, grid.cols - 1))
        let r = max(0, min(row, grid.rows - 1))
        return CellRect(col: c, row: r,
                        w: max(1, min(w, grid.cols - c)), h: max(1, min(h, grid.rows - r)))
    }
}

enum Geometry {
    /// Screen rect (Cocoa coords) for a cell rect, honouring the gaps.
    static func frame(for cell: CellRect, in grid: GridSpec, on visibleFrame: CGRect) -> CGRect {
        let g = grid.clamped()
        let cell = cell.clamped(to: g)
        let cellW = (visibleFrame.width - 2 * g.outerGap - CGFloat(g.cols - 1) * g.innerGap) / CGFloat(g.cols)
        let cellH = (visibleFrame.height - 2 * g.outerGap - CGFloat(g.rows - 1) * g.innerGap) / CGFloat(g.rows)
        // Round the edges, not the sizes: rounding a width independently makes a 2-cell span
        // disagree with the two cells it covers by a pixel.
        let left = visibleFrame.minX + g.outerGap + CGFloat(cell.col) * (cellW + g.innerGap)
        let right = left + CGFloat(cell.w) * cellW + CGFloat(cell.w - 1) * g.innerGap
        let top = visibleFrame.maxY - g.outerGap - CGFloat(cell.row) * (cellH + g.innerGap)
        let bottom = top - (CGFloat(cell.h) * cellH + CGFloat(cell.h - 1) * g.innerGap)
        return CGRect(x: left.rounded(), y: bottom.rounded(),
                      width: right.rounded() - left.rounded(),
                      height: top.rounded() - bottom.rounded())
    }

    /// The cell under a point (Cocoa coords). Nil when the point is outside the screen.
    static func cell(at point: CGPoint, in grid: GridSpec, on visibleFrame: CGRect) -> (col: Int, row: Int)? {
        guard visibleFrame.contains(point) else { return nil }
        let g = grid.clamped()
        let colW = visibleFrame.width / CGFloat(g.cols)
        let rowH = visibleFrame.height / CGFloat(g.rows)
        let col = Int((point.x - visibleFrame.minX) / colW)
        let row = Int((visibleFrame.maxY - point.y) / rowH)   // row 0 is the top one
        return (max(0, min(col, g.cols - 1)), max(0, min(row, g.rows - 1)))
    }

    /// The cell rect a window frame currently occupies — used when capturing a layout from
    /// the windows as they sit right now. Rounds to the nearest cell boundary.
    static func nearestCell(for frame: CGRect, in grid: GridSpec, on visibleFrame: CGRect) -> CellRect {
        let g = grid.clamped()
        let colW = visibleFrame.width / CGFloat(g.cols)
        let rowH = visibleFrame.height / CGFloat(g.rows)
        let c0 = Int(((frame.minX - visibleFrame.minX) / colW).rounded())
        let c1 = Int(((frame.maxX - visibleFrame.minX) / colW).rounded()) - 1
        let r0 = Int(((visibleFrame.maxY - frame.maxY) / rowH).rounded())
        let r1 = Int(((visibleFrame.maxY - frame.minY) / rowH).rounded()) - 1
        return CellRect(col: c0, row: r0, w: max(1, c1 - c0 + 1), h: max(1, r1 - r0 + 1)).clamped(to: g)
    }
}

// MARK: - Zones, layouts, config

/// A named zone with an optional global hotkey.
struct Zone: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var cell: CellRect
    var keyCode: UInt32?      // Carbon virtual key code
    var modifiers: UInt32?    // Carbon modifier mask
}

/// One window's place in a saved scene.
struct Placement: Codable, Equatable {
    var appBundleID: String
    var titleContains: String?   // disambiguates several windows of the same app
    var cell: CellRect
    var screenKey: String?       // nil = the screen the app is already on
}

/// A scene: "Dev", "Call", "Research" — applied in one go.
struct Layout: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var placements: [Placement]
    var keyCode: UInt32?
    var modifiers: UInt32?
}

struct Config: Codable {
    var grids: [String: GridSpec] = [:]     // screenKey -> grid
    var zones: [Zone] = []
    var layouts: [Layout] = []
    var launchAtLogin = false
    var rearrangeOnGridChange = true         // changing the grid re-tiles that screen at once
    var autoFitNewWindows = false            // a new window drops into the biggest free area
    /// Screens whose grid is not chosen by hand but derived from how many windows are open.
    var autoGrid: [String: Bool] = [:]
    var defaultStrategy: ArrangeStrategy = .balanced
    var masterFraction: CGFloat = 0.6        // width of the master tile in "master + stack"
    var language = "system"                  // system | en | it

    func grid(for screenKey: String) -> GridSpec {
        (grids[screenKey] ?? .default).clamped()
    }

    func isAutoGrid(_ screenKey: String) -> Bool { autoGrid[screenKey] ?? false }

    init() {}

    /// Decoded field by field, each falling back to its default.
    ///
    /// The synthesised decoder would throw on the first key a newer version added, and a throw
    /// here means the whole file is discarded — silently turning someone's grids back into the
    /// defaults. Adding a field must never cost a user their configuration.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) .flatMap { $0 } ?? fallback
        }
        grids = value(.grids, [:])
        zones = value(.zones, [])
        layouts = value(.layouts, [])
        launchAtLogin = value(.launchAtLogin, false)
        rearrangeOnGridChange = value(.rearrangeOnGridChange, true)
        autoFitNewWindows = value(.autoFitNewWindows, false)
        autoGrid = value(.autoGrid, [:])
        defaultStrategy = value(.defaultStrategy, .balanced)
        masterFraction = value(.masterFraction, 0.6)
        language = value(.language, "system")
    }
}

/// Reads and writes ~/Library/Application Support/Tessera/config.json.
final class Store {
    static let shared = Store()
    private(set) var config = Config()
    private let url: URL

    /// Bumped on every change so views can redraw.
    var onChange: (() -> Void)?

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tessera", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("config.json")
        load()
    }

    private func load() {
        // Whatever happens to the file, the language has to end up resolved: a defaulted config
        // still means "system", and the UI is built right after this returns.
        defer { lang = resolveLanguage(config.language) }
        guard let data = try? Data(contentsOf: url) else { return }
        do {
            config = try JSONDecoder().decode(Config.self, from: data)
        } catch {
            NSLog("Tessera: unreadable configuration (%@), starting from the defaults: %@",
                  url.path, String(describing: error))
        }
    }

    func mutate(_ body: (inout Config) -> Void) {
        body(&config)
        lang = resolveLanguage(config.language)
        save()
        onChange?()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - Screens

extension NSScreen {
    /// Stable-enough identity for a display across reconnects: the CG display ID when we can get
    /// it, otherwise the frame. Used as the key for per-screen grids.
    var tesseraKey: String {
        if let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return "display-\(number.uint32Value)"
        }
        return "frame-\(Int(frame.minX))x\(Int(frame.minY))-\(Int(frame.width))x\(Int(frame.height))"
    }

    static func screen(forKey key: String) -> NSScreen? {
        screens.first { $0.tesseraKey == key }
    }

    /// The screen under the mouse — where a drag or a hotkey should act.
    static var underMouse: NSScreen {
        let p = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(p) } ?? .main ?? screens[0]
    }
}
