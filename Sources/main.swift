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
        arrange(NSScreen.underMouse, with: strategy)
    }

    @discardableResult
    func arrange(_ screen: NSScreen, with strategy: ArrangeStrategy) -> Int {
        AutoArrange.apply(AutoArrange.windows(on: screen), on: screen, strategy: strategy)
    }

    /// Picks the grid that shows everything open on this screen, applies it, and tiles one
    /// window per cell. The one-shot version of the automatic mode.
    @discardableResult
    func fitGridAndArrange(on screen: NSScreen) -> Int {
        let key = screen.tesseraKey
        let windows = AutoArrange.windows(on: screen)
        let grid = AutoArrange.bestGrid(for: windows.count, on: screen,
                                        like: store.config.grid(for: key))
        // Written as an automatic grid so this does not also trigger the "re-tile on grid
        // change" rule: the arrangement below is the one that should happen, once.
        AutoArrange.writeGrid(grid, for: key)
        return AutoArrange.apply(windows, on: screen, strategy: .cells)
    }

    /// Finds a screen by its key or by a piece of its name, for the command line.
    static func screen(matching text: String?) -> NSScreen {
        guard let text, !text.isEmpty else { return .underMouse }
        return NSScreen.screen(forKey: text)
            ?? NSScreen.screens.first { $0.localizedName.localizedCaseInsensitiveContains(text) }
            ?? .underMouse
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

    // MARK: Reacting to a new grid

    private var knownGrids: [String: GridSpec] = [:]

    /// Changing a grid is a request to see it: the screens whose grid just changed are re-tiled
    /// right away, otherwise the setting only takes effect on windows placed later.
    private func rearrangeScreensWhoseGridChanged() {
        let grids = store.config.grids
        defer { knownGrids = grids }
        guard store.config.rearrangeOnGridChange, !AutoArrange.isWritingAutoGrid else { return }
        for (key, grid) in grids where knownGrids[key] != grid {
            guard let screen = NSScreen.screen(forKey: key) else { continue }
            AutoArrange.apply(AutoArrange.windows(on: screen), on: screen,
                              strategy: store.config.defaultStrategy)
        }
    }

    // MARK: Permission

    private var trustWatcher: Timer?

    /// Polls until Accessibility access is granted, then wires everything up. Without this the
    /// app has to be restarted after ticking the box, which is a silly thing to ask.
    private func watchForTrust() {
        guard trustWatcher == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] timer in
            guard AX.isTrusted else { return }
            timer.invalidate()
            self?.trustWatcher = nil
            HotkeyManager.shared.reload()
            MenuBarController.shared.refresh()
            self?.writeState()
        }
        RunLoop.main.add(timer, forMode: .common)
        trustWatcher = timer
    }

    /// A tiny status file, so the app's real state can be read from a terminal (`--diagnose`
    /// runs as a different process and cannot answer for the running app).
    func writeState() {
        let state: [String: Any] = [
            "version": appVersion,
            "pid": ProcessInfo.processInfo.processIdentifier,
            "accessibilityTrusted": AX.isTrusted,
            "updated": ISO8601DateFormatter().string(from: Date()),
        ]
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tessera", isDirectory: true)
        guard let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted])
        else { return }
        try? data.write(to: dir.appendingPathComponent("state.json"), options: .atomic)
    }

    // MARK: Commands from the command line

    static let fitGridNotification = Notification.Name("sh.tessera.fitgrid")
    static let settingsNotification = Notification.Name("sh.tessera.settings")
    static let exitFullScreenNotification = Notification.Name("sh.tessera.exitfullscreen")
    static let diagnoseNotification = Notification.Name("sh.tessera.diagnose")
    static let arrangeNotification = Notification.Name("sh.tessera.arrange")
    static let placeNotification = Notification.Name("sh.tessera.place")

    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tessera", isDirectory: true)
    }

    private func listenForCommands() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: Self.diagnoseNotification, object: nil, queue: .main) { _ in
            try? diagnosticsText().write(to: Self.supportDirectory.appendingPathComponent("diagnose.txt"),
                                        atomically: true, encoding: .utf8)
        }
        center.addObserver(forName: Self.fitGridNotification, object: nil, queue: .main) { [weak self] note in
            let parts = (note.object as? String)?.components(separatedBy: ";") ?? []
            let screen = AppController.screen(matching: parts.count > 1 ? parts[1] : nil)
            let moved = self?.fitGridAndArrange(on: screen) ?? 0
            let grid = Store.shared.config.grid(for: screen.tesseraKey)
            let detail = AutoArrange.lastOutcomes
                .map { "  \($0.app): \($0.outcome.described)" }
                .joined(separator: "\n")
            let report = (moved == 1
                ? String(format: tr("Screen %@: grid %d×%d from the open windows, 1 arranged."),
                         screen.localizedName, grid.cols, grid.rows)
                : String(format: tr("Screen %@: grid %d×%d from the open windows, %d arranged."),
                         screen.localizedName, grid.cols, grid.rows, moved))
                + "\n" + detail + "\n"
            try? report.write(to: Self.supportDirectory.appendingPathComponent("diagnose.txt"),
                              atomically: true, encoding: .utf8)
        }
        center.addObserver(forName: Self.settingsNotification, object: nil, queue: .main) { _ in
            // Settings are a page of the popover now, so this toggles the popover on that page.
            let wasOpen = MenuBarController.shared.isPopoverShown
            MenuBarController.shared.togglePopover(page: .settings)
            let report = (wasOpen ? tr("Popover closed.") : tr("Settings open in the popover.")) + "\n"
            try? report.write(to: Self.supportDirectory.appendingPathComponent("diagnose.txt"),
                              atomically: true, encoding: .utf8)
        }
        center.addObserver(forName: Self.exitFullScreenNotification, object: nil, queue: .main) { _ in
            let windows = AX.fullScreenWindows()
            let restored = windows.filter(AX.exitFullScreen).map(\.appName)
            let report = (windows.isEmpty
                ? tr("No window is in full screen.")
                : String(format: tr("Brought back out of full screen: %@"),
                         restored.joined(separator: ", "))) + "\n"
            try? report.write(to: Self.supportDirectory.appendingPathComponent("diagnose.txt"),
                              atomically: true, encoding: .utf8)
        }
        center.addObserver(forName: Self.placeNotification, object: nil, queue: .main) { note in
            // "col,row,w,h;screen" — the front window into one rectangle of the grid.
            let parts = (note.object as? String)?.components(separatedBy: ";") ?? []
            let numbers = (parts.first ?? "").split(separator: ",").compactMap { Int($0) }
            let report: String
            if numbers.count < 2 {
                report = tr("Usage: --place col,row[,width,height] [--screen name]")
            } else if let window = AX.focusedWindow() {
                let cell = CellRect(col: numbers[0], row: numbers[1],
                                    w: numbers.count > 2 ? numbers[2] : 1,
                                    h: numbers.count > 3 ? numbers[3] : 1)
                let screen = parts.count > 1 && !parts[1].isEmpty
                    ? AppController.screen(matching: parts[1]) : AX.screen(of: window)
                let grid = Store.shared.config.grid(for: screen.tesseraKey)
                AX.place(window, in: cell.clamped(to: grid), on: screen)
                report = String(format: tr("%@ placed in col %d row %d %d×%d."),
                                window.appName, cell.col, cell.row, cell.w, cell.h)
            } else {
                report = tr("No window is in front.")
            }
            try? (report + "\n").write(to: Self.supportDirectory.appendingPathComponent("diagnose.txt"),
                                       atomically: true, encoding: .utf8)
        }
        center.addObserver(forName: Self.arrangeNotification, object: nil, queue: .main) { [weak self] note in
            // The command line packs "strategy;screen" into the one string a distributed
            // notification can carry.
            let parts = (note.object as? String)?.components(separatedBy: ";") ?? []
            let strategy = parts.first.flatMap(ArrangeStrategy.init(rawValue:))
                ?? self?.store.config.defaultStrategy ?? .balanced
            let screen = AppController.screen(matching: parts.count > 1 ? parts[1] : nil)
            let moved = self?.arrange(screen, with: strategy) ?? 0
            let detail = AutoArrange.lastOutcomes
                .map { "  \($0.app): \($0.outcome.described)" }
                .joined(separator: "\n")
                + (AutoArrange.lastCorrections == 0 ? "" : "\n  " + (AutoArrange.lastCorrections == 1
                    ? tr("1 window needed a second nudge.")
                    : String(format: tr("%d windows needed a second nudge."),
                             AutoArrange.lastCorrections)))
            let report = (moved == 1
                ? String(format: tr("Screen %@: 1 window arranged with the “%@” arrangement."),
                         screen.localizedName, strategy.label)
                : String(format: tr("Screen %@: %d windows arranged with the “%@” arrangement."),
                         screen.localizedName, moved, strategy.label))
                + "\n" + detail + "\n"
                + diagnosticsText()
            try? report.write(to: Self.supportDirectory.appendingPathComponent("diagnose.txt"),
                              atomically: true, encoding: .utf8)
        }
    }

    // MARK: Lifecycle

    func start() {
        MenuBarController.shared.install()
        HotkeyManager.shared.reload()
        NewWindowWatcher.shared.setEnabled(store.config.autoFitNewWindows)
        knownGrids = store.config.grids
        store.onChange = { [weak self] in
            guard let self else { return }
            HotkeyManager.shared.reload()
            NewWindowWatcher.shared.setEnabled(self.store.config.autoFitNewWindows)
            MenuBarController.shared.refresh()
            self.rearrangeScreensWhoseGridChanged()
        }
        writeState()
        listenForCommands()
        if !AX.isTrusted {
            promptForAccessibility()
            watchForTrust()
        }
    }

    private func promptForAccessibility() {
        AX.requestTrust()
        let alert = NSAlert()
        alert.messageText = tr("Tessera needs Accessibility access")
        alert.informativeText = tr("""
            To move and resize the windows of other apps, Tessera has to be allowed in System \
            Settings › Privacy & Security › Accessibility. It works the moment you tick the box: \
            no restart needed.
            """)
        alert.addButton(withTitle: tr("Open Settings"))
        alert.addButton(withTitle: tr("Later"))
        if alert.runModal() == .alertFirstButtonReturn { AX.openAccessibilitySettings() }
    }
}

// MARK: - Icon generation (scripts/build-app.sh calls the app with --icon)

func writeIcon(to path: String, size: Int) {
    let image = Logo.appIcon(size: CGFloat(size))
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

// MARK: - Diagnostics (Tessera.app/Contents/MacOS/Tessera --diagnose)

/// What Tessera sees and what "arrange all" would do, without moving a single window.
///
/// Only the running app can answer this: Accessibility is granted to the app, and a second copy
/// of the binary started from a terminal is a different process that sees no windows at all.
/// So the command-line `--diagnose` asks the running app and prints its reply.
func diagnosticsText() -> String {
    let config = Store.shared.config
    var out = ""
    func print(_ line: String) { out += line + "\n" }
    print(String(format: tr("Tessera %@ — diagnostics (no window is moved)"), appVersion))
    print(String(format: tr("Accessibility access: %@"),
                 AX.isTrusted ? tr("on") : tr("NOT on — allow the app and try again")))
    print(String(format: tr("Default arrangement: %@"), config.defaultStrategy.label))
    // What the popover would act on. Tessera is in front while its own popover is open, so
    // this is the app that was in front before it, not whatever the system says right now.
    print(String(format: tr("Front window: %@"),
                 MenuBarController.shared.captureFrontWindow()
                    .map { "\($0.appName) — \($0.title)" } ?? tr("none")) + "\n")

    for screen in NSScreen.screens {
        let key = screen.tesseraKey
        let grid = config.grid(for: key)
        let windows = AutoArrange.windows(on: screen)
        let plan = AutoArrange.plan(on: screen)
        print(String(format: tr("Screen %@ [%@]"), screen.localizedName, key))
        print("  visibleFrame: \(short(screen.visibleFrame))")
        let origin = config.isAutoGrid(key)
            ? tr(" (automatic: recomputed when you arrange, not now)")
            : (config.grids[key] == nil
               ? tr(" (default, never changed for this screen)")
               : tr(" (fixed)"))
        print(String(format: tr("  grid: %d×%d, outer gap %d, inner gap %d"),
                     grid.cols, grid.rows, Int(grid.outerGap), Int(grid.innerGap))
              + origin)
        print(String(format: tr("  windows on this Desktop: %d — would arrange %d, would leave %d"),
                     windows.count, plan.tiled, plan.untouched))

        // The same pairing the arrangement would use, so this prints what would really happen.
        for move in AutoArrange.moves(for: windows, on: screen, grid: grid,
                                      strategy: config.defaultStrategy) {
            print(String(format: tr("    %@ — %@ → cell col %d row %d %d×%d = %@"),
                         move.window.appName, short(move.window.frame ?? .zero),
                         move.cell.col, move.cell.row, move.cell.w, move.cell.h,
                         short(move.target)))
        }
        print("")
    }
    return out
}

private func short(_ rect: CGRect) -> String {
    "\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))×\(Int(rect.height))"
}

// MARK: - Entry point

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppController.shared.start()
    }
}

let arguments = CommandLine.arguments
if let index = arguments.firstIndex(of: "--icon"), arguments.count > index + 2 {
    writeIcon(to: arguments[index + 1], size: Int(arguments[index + 2]) ?? 512)
    exit(0)
}

// The command-line paths print translated text as well, so the stored preference has to be
// read before the first print: touching the store is what resolves `lang`.
_ = Store.shared.config

/// Asks the running app to run a command and prints the reply it writes out.
func askRunningApp(_ name: Notification.Name, strategy: String?) -> Bool {
    let reply = AppController.supportDirectory.appendingPathComponent("diagnose.txt")
    try? FileManager.default.removeItem(at: reply)
    guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
        print(tr("Tessera is not running: open it and try again."))
        return false
    }
    DistributedNotificationCenter.default().postNotificationName(name, object: strategy,
                                                                 userInfo: nil, deliverImmediately: true)
    for _ in 0..<40 {
        if let text = try? String(contentsOf: reply, encoding: .utf8) {
            print(text)
            return true
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    print(tr("Tessera did not answer within 4 seconds."))
    return false
}

if let index = arguments.firstIndex(of: "--place"), arguments.count > index + 1 {
    let screenIndex = arguments.firstIndex(of: "--screen")
    let screen = screenIndex.flatMap { arguments.count > $0 + 1 ? arguments[$0 + 1] : nil } ?? ""
    _ = askRunningApp(AppController.placeNotification, strategy: "\(arguments[index + 1]);\(screen)")
    exit(0)
}

if arguments.contains("--diagnose") {
    // With the permission in hand (rare from a terminal) answer directly; otherwise ask the app.
    if AX.isTrusted { print(diagnosticsText()) } else { _ = askRunningApp(AppController.diagnoseNotification, strategy: nil) }
    exit(0)
}

if let index = arguments.firstIndex(of: "--fit-grid") {
    _ = index
    let screenIndex = arguments.firstIndex(of: "--screen")
    let screen = screenIndex.flatMap { arguments.count > $0 + 1 ? arguments[$0 + 1] : nil } ?? ""
    _ = askRunningApp(AppController.fitGridNotification, strategy: ";\(screen)")
    exit(0)
}

if arguments.contains("--settings") {
    _ = askRunningApp(AppController.settingsNotification, strategy: nil)
    exit(0)
}

if arguments.contains("--exit-fullscreen") {
    _ = askRunningApp(AppController.exitFullScreenNotification, strategy: nil)
    exit(0)
}

if let index = arguments.firstIndex(of: "--arrange") {
    let strategy = arguments.count > index + 1 && !arguments[index + 1].hasPrefix("--")
        ? arguments[index + 1] : ""
    let screenIndex = arguments.firstIndex(of: "--screen")
    let screen = screenIndex.flatMap { arguments.count > $0 + 1 ? arguments[$0 + 1] : nil } ?? ""
    _ = askRunningApp(AppController.arrangeNotification, strategy: "\(strategy);\(screen)")
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
