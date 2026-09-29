// Tessera — a small macOS menu bar app that tiles windows on a grid you choose.
//
// Four ways to place a window, all on the same grid: drag onto the overlay, a global hotkey,
// the grid in the menu bar popover, or a saved layout applied in one go — plus automatic
// arrangement of everything that is already open.
//
// Modules: Core (grid + config) · WindowsAX (Accessibility) · AutoArrange (automatic placement)
//          Overlay (drag-to-zone) · Hotkeys (global keys) · MenuBar (status item) · Preferences

import AppKit

/// The one object the UI, the hotkeys and the overlay all call into.
final class AppController {
    static let shared = AppController()
    private init() {}

    var store: Store { .shared }

    // MARK: Placing

    /// Places the focused window of the frontmost app. The screen is the one that window is on.
    @discardableResult
    func placeFocused(in cell: CellRect) -> Bool {
        guard let window = AX.focusedWindow() else { return false }
        let screen = AX.screen(of: window)
        OverlayController.shared.flash(cell: cell, on: screen)
        return AX.place(window, in: cell, on: screen)
    }

    /// Drops the focused window into the largest free area of its screen's grid.
    @discardableResult
    func fitFocused() -> Bool {
        guard let window = AX.focusedWindow() else { return false }
        return AutoArrange.fit(window)
    }

    /// Arranges every window on the screen under the mouse.
    @discardableResult
    func arrangeCurrentScreen(_ strategy: ArrangeStrategy) -> Int {
        let screen = NSScreen.underMouse
        return AutoArrange.apply(AutoArrange.windows(on: screen), on: screen, strategy: strategy)
    }

    // MARK: Layouts

    /// Applies a saved scene: every placement whose app is running and whose window matches.
    @discardableResult
    func apply(_ layout: Layout) -> Int {
        var windows = AX.allWindows()
        var applied = 0
        for placement in layout.placements {
            let index = windows.firstIndex { window in
                window.bundleID == placement.appBundleID
                    && (placement.titleContains.map { window.title.localizedCaseInsensitiveContains($0) } ?? true)
            }
            guard let index else { continue }
            let window = windows.remove(at: index)   // one window per placement
            let screen = placement.screenKey.flatMap(NSScreen.screen(forKey:)) ?? AX.screen(of: window)
            if AX.place(window, in: placement.cell, on: screen) { applied += 1 }
        }
        return applied
    }

    /// Snapshots the windows as they sit right now into a reusable scene.
    func captureLayout(named name: String) -> Layout {
        let placements: [Placement] = AX.allWindows().compactMap { window in
            guard let frame = window.frame, !window.bundleID.isEmpty else { return nil }
            let screen = AX.screen(of: window)
            let grid = store.config.grid(for: screen.tesseraKey)
            return Placement(appBundleID: window.bundleID,
                             titleContains: nil,
                             cell: Geometry.nearestCell(for: frame, in: grid, on: screen.visibleFrame),
                             screenKey: screen.tesseraKey)
        }
        return Layout(name: name, placements: placements)
    }

    // MARK: Lifecycle

    func start() {
        MenuBarController.shared.install()
        HotkeyManager.shared.reload()
        DragWatcher.shared.setEnabled(store.config.showOverlayOnDrag)
        NewWindowWatcher.shared.setEnabled(store.config.autoFitNewWindows)
        store.onChange = { [weak self] in
            guard let self else { return }
            HotkeyManager.shared.reload()
            DragWatcher.shared.setEnabled(self.store.config.showOverlayOnDrag)
            NewWindowWatcher.shared.setEnabled(self.store.config.autoFitNewWindows)
            MenuBarController.shared.refresh()
        }
        if !AX.isTrusted { promptForAccessibility() }
    }

    private func promptForAccessibility() {
        AX.requestTrust()
        let alert = NSAlert()
        alert.messageText = "Tessera ha bisogno dell'accesso Accessibilità"
        alert.informativeText = """
            Per spostare e ridimensionare le finestre delle altre app, Tessera va autorizzata in \
            Impostazioni di Sistema › Privacy e sicurezza › Accessibilità. Dopo averla attivata, \
            riavvia Tessera.
            """
        alert.addButton(withTitle: "Apri Impostazioni")
        alert.addButton(withTitle: "Più tardi")
        if alert.runModal() == .alertFirstButtonReturn { AX.openAccessibilitySettings() }
    }
}

// MARK: - Icon generation (scripts/build-app.sh calls the app with --icon)

func drawIcon(to path: String, size: Int) {
    let side = CGFloat(size)
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()
    let inset = side * 0.08
    let rect = CGRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset)
    NSColor(calibratedRed: 0.15, green: 0.17, blue: 0.22, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect, xRadius: side * 0.22, yRadius: side * 0.22).fill()

    // A 2×2-with-a-split mosaic: the point of the app in one glyph.
    let pad = side * 0.20, gap = side * 0.045
    let area = CGRect(x: pad, y: pad, width: side - 2 * pad, height: side - 2 * pad)
    let halfW = (area.width - gap) / 2
    let halfH = (area.height - gap) / 2
    let thirdH = (area.height - 2 * gap) / 3
    let tiles = [
        CGRect(x: area.minX, y: area.minY, width: halfW, height: area.height),
        CGRect(x: area.minX + halfW + gap, y: area.minY + 2 * (thirdH + gap), width: halfW, height: thirdH),
        CGRect(x: area.minX + halfW + gap, y: area.minY + thirdH + gap, width: halfW, height: thirdH),
        CGRect(x: area.minX + halfW + gap, y: area.minY, width: halfW, height: thirdH),
    ]
    _ = halfH
    NSColor.white.setFill()
    for tile in tiles {
        NSBezierPath(roundedRect: tile, xRadius: side * 0.05, yRadius: side * 0.05).fill()
    }
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

// MARK: - Entry point

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppController.shared.start()
    }
}

let arguments = CommandLine.arguments
if let index = arguments.firstIndex(of: "--icon"), arguments.count > index + 2 {
    drawIcon(to: arguments[index + 1], size: Int(arguments[index + 2]) ?? 512)
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
