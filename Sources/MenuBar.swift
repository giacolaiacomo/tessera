// Tessera — the status item and its popover: the grid you can click, the zones, the automatic
// arrangements and the saved layouts.
//
// The popover is a SwiftUI view built when it opens and dropped when it closes: everything it
// shows depends on where the mouse is and on which window is in front at that instant, so there
// is nothing worth keeping alive in between.

import AppKit
import SwiftUI

// MARK: - What the popover shows

/// A snapshot of the state the popover draws, taken when it opens and whenever the config changes.
final class PopoverModel: ObservableObject {
    @Published fileprivate(set) var trusted = false
    @Published fileprivate(set) var appName: String?
    @Published fileprivate(set) var grid = GridSpec.default
    @Published fileprivate(set) var screenAspect: CGFloat = 1.6
    @Published fileprivate(set) var tiled = 0
    @Published fileprivate(set) var untouched = 0
    @Published fileprivate(set) var zones: [Zone] = []
    @Published fileprivate(set) var layouts: [Layout] = []
    @Published fileprivate(set) var strategy = ArrangeStrategy.balanced

    var canPlace: Bool { trusted && appName != nil }

    func reload(window: ManagedWindow?) {
        let config = Store.shared.config
        let screen = NSScreen.underMouse
        let frame = screen.visibleFrame
        trusted = AX.isTrusted
        appName = window?.appName
        grid = config.grid(for: screen.tesseraKey)
        screenAspect = frame.height > 0 ? frame.width / frame.height : 1.6
        let plan = trusted ? AutoArrange.plan(on: screen) : (tiled: 0, untouched: 0)
        tiled = plan.tiled
        untouched = plan.untouched
        zones = config.zones
        layouts = config.layouts
        strategy = config.defaultStrategy
    }
}

// MARK: - The clickable grid

/// A miniature of the screen's grid: click a cell or drag over several to pick an area.
/// Row 0 is the top row, exactly as in `CellRect`, which is also SwiftUI's y direction.
struct GridPicker: View {
    let grid: GridSpec
    let screenAspect: CGFloat
    var selected: CellRect?
    var enabled = true
    let onPick: (CellRect) -> Void

    @State private var anchor: CellRect?
    @State private var highlight: CellRect?

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in draw(in: context, size: size) }
                .contentShape(Rectangle())
                .gesture(drag(in: geometry.size))
        }
        .aspectRatio(screenAspect, contentMode: .fit)
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        let g = grid.clamped()
        let cellW = size.width / CGFloat(g.cols)
        let cellH = size.height / CGFloat(g.rows)
        let inset: CGFloat = cellW > 12 ? 1.5 : 0.75
        for row in 0..<g.rows {
            for col in 0..<g.cols {
                let rect = CGRect(x: CGFloat(col) * cellW, y: CGFloat(row) * cellH,
                                  width: cellW, height: cellH).insetBy(dx: inset, dy: inset)
                context.fill(Path(roundedRect: rect, cornerRadius: 2),
                             with: .color(.primary.opacity(0.12)))
            }
        }
        guard let shown = highlight ?? selected else { return }
        let cell = shown.clamped(to: g)
        let rect = CGRect(x: CGFloat(cell.col) * cellW, y: CGFloat(cell.row) * cellH,
                          width: CGFloat(cell.w) * cellW, height: CGFloat(cell.h) * cellH)
            .insetBy(dx: inset, dy: inset)
        context.fill(Path(roundedRect: rect, cornerRadius: 3),
                     with: .color(.accentColor.opacity(enabled ? 0.85 : 0.35)))
    }

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard enabled else { return }
                let current = cell(at: value.location, in: size)
                let start = anchor ?? CellRect(col: current.col, row: current.row)
                anchor = start
                highlight = CellRect.spanning((start.col, start.row), current).clamped(to: grid)
            }
            .onEnded { _ in
                defer { anchor = nil; highlight = nil }
                guard enabled, let picked = highlight else { return }
                onPick(picked)
            }
    }

    private func cell(at point: CGPoint, in size: CGSize) -> (col: Int, row: Int) {
        let g = grid.clamped()
        let col = Int(point.x / max(1, size.width / CGFloat(g.cols)))
        let row = Int(point.y / max(1, size.height / CGFloat(g.rows)))
        return (max(0, min(col, g.cols - 1)), max(0, min(row, g.rows - 1)))
    }
}

// MARK: - Rows

/// One tappable line of the popover: a label, an optional shortcut pushed to the right.
struct PopoverRow: View {
    let title: String
    var trailing: String = ""
    var note: String?
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 12)).lineLimit(1)
                    Spacer(minLength: 6)
                    if !trailing.isEmpty {
                        Text(trailing).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                if let note {
                    Text(note).font(.system(size: 10.5)).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

// MARK: - The popover

struct TesseraPopover: View {
    @ObservedObject var model: PopoverModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !model.trusted { warning }
            gridSection
            arrangeSection
            if !model.zones.isEmpty { zonesSection }
            layoutsSection
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 272)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Tessera").font(.system(size: 13, weight: .bold))
            Spacer()
            Button { MenuBarController.shared.openPreferences() } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Impostazioni")
        }
    }

    private var warning: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Senza l'accesso Accessibilità le finestre non si muovono.")
                .font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Apri") { MenuBarController.shared.openAccessibility() }.controlSize(.small)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.orange.opacity(0.12)))
    }

    private var gridSection: some View {
        TesseraCard(title: "Griglia \(model.grid.cols)×\(model.grid.rows)") {
            Text(model.appName ?? "Nessuna finestra attiva")
                .font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            GridPicker(grid: model.grid, screenAspect: model.screenAspect, enabled: model.canPlace) { cell in
                MenuBarController.shared.place(in: cell)
            }
            .frame(height: 118)
            .frame(maxWidth: .infinity)
        }
    }

    private var arrangeSection: some View {
        TesseraCard(title: "Sistema") {
            PopoverRow(title: "Sistema tutto (\(windowCount(model.tiled)))",
                       note: untouchedNote, enabled: model.trusted) {
                MenuBarController.shared.arrange(with: model.strategy)
            }
            Menu("Sistema tutto con…") {
                ForEach(ArrangeStrategy.allCases, id: \.self) { strategy in
                    Button(strategy.label) { MenuBarController.shared.arrange(with: strategy) }
                }
            }
            .menuStyle(.borderlessButton)
            .font(.system(size: 12))
            .disabled(!model.trusted)
            PopoverRow(title: "Sistema la finestra attiva", enabled: model.canPlace) {
                MenuBarController.shared.fitFocused()
            }
        }
    }

    private var zonesSection: some View {
        TesseraCard(title: "Zone") {
            ForEach(model.zones) { zone in
                PopoverRow(title: zone.name,
                           trailing: hotkeyDescription(keyCode: zone.keyCode, modifiers: zone.modifiers),
                           enabled: model.canPlace) {
                    MenuBarController.shared.place(in: zone.cell)
                }
            }
        }
    }

    private var layoutsSection: some View {
        TesseraCard(title: "Disposizioni") {
            ForEach(model.layouts) { layout in
                PopoverRow(title: layout.name,
                           trailing: hotkeyDescription(keyCode: layout.keyCode, modifiers: layout.modifiers),
                           enabled: model.trusted) {
                    MenuBarController.shared.apply(layout)
                }
            }
            PopoverRow(title: "Salva disposizione attuale…", enabled: model.trusted) {
                MenuBarController.shared.saveLayout()
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Tessera \(appVersion)").font(.system(size: 10.5)).foregroundStyle(.tertiary)
            Spacer()
            Button("Esci") { NSApp.terminate(nil) }.buttonStyle(.borderless).font(.system(size: 11))
        }
    }

    private func windowCount(_ n: Int) -> String {
        n == 1 ? "1 finestra" : "\(n) finestre"
    }

    private var untouchedNote: String? {
        guard model.untouched > 0 else { return nil }
        return model.untouched == 1
            ? "1 finestra resta dov'è"
            : "\(model.untouched) finestre restano dove sono"
    }
}

// MARK: - The status item

final class MenuBarController: NSObject, NSPopoverDelegate {
    static let shared = MenuBarController()
    private override init() {}

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let model = PopoverModel()

    /// The window that was focused just before the popover took over. Read before showing it —
    /// afterwards the popover is frontmost and `AX.focusedWindow()` answers with the wrong thing.
    private var capturedWindow: ManagedWindow?

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Logo.statusItemIcon()
        item.button?.toolTip = "Tessera"
        item.button?.target = self
        item.button?.action = #selector(toggle)
        statusItem = item
        popover.behavior = .transient
        popover.delegate = self
    }

    /// Re-reads the config while the popover is open. Closed, it will read it again on the next open.
    func refresh() {
        guard popover.isShown else { return }
        model.reload(window: capturedWindow)
    }

    @objc private func toggle() {
        guard let button = statusItem?.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        capturedWindow = AX.isTrusted ? AX.focusedWindow() : nil
        model.reload(window: capturedWindow)
        let host = NSHostingController(rootView: TesseraPopover(model: model))
        host.sizingOptions = [.preferredContentSize]   // grow and shrink with the content
        popover.contentViewController = host
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
        capturedWindow = nil
    }

    private func close() {
        if popover.isShown { popover.performClose(nil) }
    }

    // MARK: Actions

    /// Places the captured window directly: going through `AppController.placeFocused` would
    /// re-read the frontmost app, which by now is this popover's own.
    func place(in cell: CellRect) {
        defer { close() }
        guard let window = capturedWindow else { return }
        let screen = AX.screen(of: window)
        OverlayController.shared.flash(cell: cell, on: screen)
        AX.place(window, in: cell, on: screen)
    }

    func fitFocused() {
        defer { close() }
        guard let window = capturedWindow else { return }
        AutoArrange.fit(window)
    }

    func arrange(with strategy: ArrangeStrategy) {
        close()
        AppController.shared.arrangeCurrentScreen(strategy)
    }

    func apply(_ layout: Layout) {
        close()
        AppController.shared.apply(layout)
    }

    func saveLayout() {
        // The snapshot has to be taken before the alert steals the front window.
        let layout = AppController.shared.captureLayout(named: "")
        close()
        let alert = NSAlert()
        alert.messageText = "Salva la disposizione attuale"
        alert.informativeText = "Dai un nome alla disposizione delle finestre di adesso."
        alert.addButton(withTitle: "Salva")
        alert.addButton(withTitle: "Annulla")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "Nome"
        field.stringValue = "Disposizione \(Store.shared.config.layouts.count + 1)"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Store.shared.mutate { $0.layouts.append(Layout(name: name, placements: layout.placements)) }
    }

    func openPreferences() {
        close()
        PreferencesWindowController.shared.show()
    }

    func openAccessibility() {
        close()
        AX.openAccessibilitySettings()
    }
}
