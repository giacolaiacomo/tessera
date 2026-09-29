// Renders the popover's pages off-screen, so the layout can be inspected without launching
// the app. Output: popover.png (home), settings.png and zones.png.
//
//   render <outdir> [light|dark] [docs] [frames]
//
// With no flags this behaves exactly as it always has: the three PNGs, the system appearance,
// and a page height tall enough to capture a whole settings page in one image.
//   light|dark  pin the appearance (NSApp.appearance), instead of following the system
//   docs        leave pageMaxHeight at the app's real default, so the pages are the height a
//               user actually sees — what the README images should show
//   demo-config seed the configuration the settings and zones pages read, so the README images
//               show a configured app instead of an empty one. Refuses to run unless
//               CFFIXED_USER_HOME points somewhere disposable: it writes a real config.json,
//               and the person running the script must not lose theirs.
//   height=N    how tall a scrolling page may grow before it clips, overriding the two above
//   frames      also write icon.png, statusicon.png and frames/state-N.png: the states the
//               README animation steps through
import AppKit
import SwiftUI

// Stand-in for the one in main.swift, which cannot be compiled twice (top-level code).
final class AppController {
    static let shared = AppController()
    @discardableResult func placeFocused(in cell: CellRect) -> Bool { false }
    @discardableResult func fitFocused() -> Bool { false }
    @discardableResult func arrangeCurrentScreen(_ strategy: ArrangeStrategy) -> Int { 0 }
    @discardableResult func fitGridAndArrange(on screen: NSScreen) -> Int { 0 }
    @discardableResult func apply(_ layout: Layout) -> Int { 0 }
    func captureLayout(named name: String) -> Layout { Layout(name: name, placements: []) }
}

let outDir = CommandLine.arguments[1]
let flags = Set(CommandLine.arguments.dropFirst(2))

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
if flags.contains("dark") { app.appearance = NSAppearance(named: .darkAqua) }
if flags.contains("light") { app.appearance = NSAppearance(named: .aqua) }

func snapshot<V: View>(_ view: V, named name: String) {
    let host = NSHostingView(rootView: view)
    host.frame = CGRect(origin: .zero, size: host.fittingSize)
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
    host.cacheDisplay(in: host.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: name))
    print("\(name): \(Int(host.frame.width))×\(Int(host.frame.height)) pt")
}

if flags.contains("demo-config") {
    guard let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"], !home.isEmpty else {
        print("demo-config writes a config.json: set CFFIXED_USER_HOME to a scratch directory first")
        exit(1)
    }
    let key = NSScreen.underMouse.tesseraKey
    Store.shared.mutate { config in
        config.language = "en"          // the README images are in English, whatever the Mac speaks
        config.grids[key] = GridSpec(cols: 3, rows: 2, outerGap: 8, innerGap: 10)
        config.autoGrid[key] = false
        config.autoFitNewWindows = true
        config.defaultStrategy = .balanced
        config.zones = [
            Zone(name: "Left", cell: CellRect(col: 0, row: 0, w: 1, h: 2),
                 keyCode: 123, modifiers: 6400),      // ⌃⌥⌘←
            Zone(name: "Right column", cell: CellRect(col: 2, row: 0, w: 1, h: 2),
                 keyCode: 124, modifiers: 6400),      // ⌃⌥⌘→
        ]
        config.layouts = [
            Layout(name: "Writing", placements: []),
            Layout(name: "Review", placements: []),
        ]
    }
}

let popoverModel = PopoverModel()
popoverModel.reload(window: nil)
popoverModel.loadDemo()   // the renderer has no Accessibility access: picture a lived-in screen
// The README images want the popover at the height people really get; the inspection runs want
// the whole settings page in one shot, scrollbar and all.
let heightFlag = flags.first { $0.hasPrefix("height=") }.flatMap { CGFloat(Double($0.dropFirst(7)) ?? 0) }
popoverModel.pageMaxHeight = heightFlag ?? (flags.contains("docs") ? PopoverModel().pageMaxHeight : 4000)
let prefsModel = PrefsModel()
snapshot(TesseraPopover(model: popoverModel, prefs: prefsModel), named: outDir + "/popover.png")
popoverModel.page = .settings
snapshot(TesseraPopover(model: popoverModel, prefs: prefsModel), named: outDir + "/settings.png")
popoverModel.page = .zones
snapshot(TesseraPopover(model: popoverModel, prefs: prefsModel), named: outDir + "/zones.png")

// MARK: - Frames for the README animation

/// The popover's grid card on its own, rebuilt from the app's own views — `TesseraCard`,
/// `GridChips`, `GridPicker` — because `PopoverModel`'s state is `fileprivate(set)` and the
/// animation needs a different grid in every frame. Nothing here is drawn by hand: the chips
/// come from `GridChips` (which decides its own presets and which one is selected) and the map
/// from `GridPicker`, fed the cells `AutoArrange.partition` returns.
struct DemoGridCard: View {
    let screenName: String
    let grid: GridSpec
    let auto: Bool
    let aspect: CGFloat
    let occupants: [AutoArrange.Occupant]
    let focusedApp: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Tessera").font(.system(size: 14, weight: .bold))
                Spacer()
                Button {} label: { Image(systemName: "gearshape") }.buttonStyle(.borderless)
            }
            TesseraCard {
                HStack(spacing: 5) {
                    Text(screenName).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(grid.cols)×\(grid.rows)")
                        .font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Color.accentColor)
                    if auto {
                        Text("auto").font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.16)))
                            .foregroundStyle(Color.accentColor)
                    }
                    Spacer(minLength: 4)
                    Text("\(occupants.count) windows")
                        .font(.system(size: 11, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                GridChips(grid: grid, auto: auto, aspect: aspect, enabled: true) { _ in }
                GridPicker(grid: grid, screenAspect: aspect, occupants: occupants, enabled: true) { _ in }
                    .frame(height: 96)
                    .frame(maxWidth: .infinity)
                Text("Click or drag to place \(focusedApp).")
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 272)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Writes an NSImage as a PNG at its natural pixel size.
func writePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

if flags.contains("frames") {
    writePNG(Logo.appIcon(size: 1024), to: outDir + "/icon.png")

    // The menu bar glyph, rasterised at 4× and left as a black-on-transparent template: the
    // composer fills it with whatever the menu bar strip needs.
    let bar = Logo.statusItemIcon()
    let scale = 4
    if let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                  pixelsWide: Int(bar.size.width) * scale,
                                  pixelsHigh: Int(bar.size.height) * scale,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
        rep.size = bar.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        bar.draw(in: NSRect(origin: .zero, size: bar.size))
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: outDir + "/statusicon.png"))
    }

    // The four windows of the demo screen, in the order the engine would tile them.
    let apps = ["Safari", "Xcode", "Notes", "Preview"]
    let aspect: CGFloat = 21.0 / 9.0
    let screenName = "Acer X34 P"
    // An ultrawide 21:9 screen, the one `loadDemo` pictures.
    let visible = CGRect(x: 0, y: 0, width: 2100, height: 900)
    let autoGrid = AutoArrange.bestGrid(for: apps.count, fitting: visible, like: GridSpec(cols: 3, rows: 2))

    /// One animation state. The occupants are whatever `AutoArrange.partition` returns for this
    /// grid — the cells the real engine would place these four windows in, not a drawing of them.
    func state(_ grid: GridSpec, auto: Bool) -> DemoGridCard {
        let capacity = grid.clamped().cols * grid.clamped().rows
        if apps.count > capacity {
            // `AutoArrange.apply` only tiles the first cols×rows windows, so a state that
            // overflows the grid would show a layout the engine never produces.
            print("!! \(grid.cols)×\(grid.rows) holds \(capacity) windows, not \(apps.count)")
        }
        let cells = AutoArrange.partition(count: apps.count, grid: grid, screenAspect: aspect,
                                          strategy: .balanced, masterFraction: 0.6)
        // The renderer has no Accessibility access: these windows point at nothing, and the
        // map only ever draws their name and their cell.
        let nowhere = ManagedWindow(element: AXUIElementCreateSystemWide(), pid: 0,
                                    bundleID: "", appName: "", title: "")
        let occupants = zip(apps, cells).enumerated().map { index, pair in
            AutoArrange.Occupant(window: nowhere, appName: pair.0, cell: pair.1,
                                 isFocused: index == 0, resistant: false)
        }
        print("state \(grid.cols)×\(grid.rows)\(auto ? " auto" : ""): "
              + cells.map { "(\($0.col),\($0.row) \($0.w)×\($0.h))" }.joined(separator: " "))
        return DemoGridCard(screenName: screenName, grid: grid, auto: auto, aspect: aspect,
                            occupants: occupants, focusedApp: apps[0])
    }

    let states = [state(GridSpec(cols: 4, rows: 1), auto: false),
                  state(GridSpec(cols: 3, rows: 2), auto: false),
                  state(autoGrid, auto: true)]
    try? FileManager.default.createDirectory(atPath: outDir + "/frames", withIntermediateDirectories: true)
    for (index, view) in states.enumerated() {
        snapshot(view, named: outDir + "/frames/state-\(index).png")
    }
}
