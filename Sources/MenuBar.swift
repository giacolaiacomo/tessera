// Tessera — the status item and the one panel the whole app lives in.
//
// There is no settings window: the popover has pages (home, settings, zones) and a chevron in
// the header to come back, so nothing ever opens behind the popover or outlives it. The SwiftUI
// tree is built when the popover opens and dropped when it closes: everything it shows depends
// on where the mouse is and on which window is in front at that instant.

import AppKit
import SwiftUI

// MARK: - Pages

enum PopoverPage {
    case home
    case settings
    case zones
}

// MARK: - What the popover shows

/// A snapshot of the state the popover draws, taken when it opens and whenever the config changes.
final class PopoverModel: ObservableObject {
    @Published var page = PopoverPage.home
    @Published fileprivate(set) var trusted = false
    @Published fileprivate(set) var appName: String?
    @Published fileprivate(set) var screenName = ""
    @Published fileprivate(set) var screenKey = ""
    @Published fileprivate(set) var grid = GridSpec.default
    @Published fileprivate(set) var autoGrid = false
    @Published fileprivate(set) var screenAspect: CGFloat = 1.6
    @Published fileprivate(set) var occupants: [AutoArrange.Occupant] = []
    @Published fileprivate(set) var tiled = 0
    @Published fileprivate(set) var untouched = 0
    @Published fileprivate(set) var zones: [Zone] = []
    @Published fileprivate(set) var layouts: [Layout] = []
    @Published fileprivate(set) var strategy = ArrangeStrategy.balanced

    /// How tall a settings page may grow before it scrolls. The render script raises it to
    /// capture a whole page in one image; nothing else touches it.
    var pageMaxHeight: CGFloat = 380

    var canPlace: Bool { trusted && appName != nil }
    var windowCount: Int { occupants.count }
    var resistant: Int { occupants.filter(\.resistant).count }

    func reload(window: ManagedWindow?) {
        let config = Store.shared.config
        let screen = NSScreen.underMouse
        let frame = screen.visibleFrame
        trusted = AX.isTrusted
        appName = window?.appName
        screenName = screen.localizedName
        screenKey = screen.tesseraKey
        autoGrid = config.isAutoGrid(screen.tesseraKey)
        // Read, never recompute: an automatic grid is settled when you arrange, not when you
        // look. Otherwise opening this popover redraws the map against a grid nobody applied.
        grid = config.grid(for: screen.tesseraKey)
        screenAspect = frame.height > 0 ? frame.width / frame.height : 1.6
        occupants = trusted ? AutoArrange.occupancy(on: screen) : []
        let plan = trusted ? AutoArrange.plan(on: screen) : (tiled: 0, untouched: 0)
        tiled = plan.tiled
        untouched = plan.untouched
        zones = config.zones
        layouts = config.layouts
        strategy = config.defaultStrategy
    }
}

extension PopoverModel {
    /// Made-up state for scripts/render-ui.sh, which runs without Accessibility access and so
    /// would otherwise only ever picture the empty, disabled popover.
    func loadDemo() {
        trusted = true
        appName = "Safari"
        screenName = "Acer X34 P"
        screenKey = "display-demo"
        grid = GridSpec(cols: 3, rows: 2)
        autoGrid = true
        screenAspect = 21.0 / 9.0
        // The renderer has no Accessibility access, so these stand-ins carry a window that
        // points at nothing: the map only ever draws their name and their cell.
        let nowhere = ManagedWindow(element: AXUIElementCreateSystemWide(), pid: 0,
                                    bundleID: "", appName: "", title: "")
        occupants = [
            AutoArrange.Occupant(window: nowhere, appName: "Safari", cell: CellRect(col: 0, row: 0), isFocused: true, resistant: false),
            AutoArrange.Occupant(window: nowhere, appName: "Xcode", cell: CellRect(col: 1, row: 0, w: 1, h: 2), isFocused: false, resistant: false),
            AutoArrange.Occupant(window: nowhere, appName: "Notes", cell: CellRect(col: 0, row: 1), isFocused: false, resistant: false),
            AutoArrange.Occupant(window: nowhere, appName: "Preview", cell: CellRect(col: 2, row: 0, w: 1, h: 2), isFocused: false, resistant: true),
        ]
        tiled = 4
        untouched = 1
        zones = [Zone(name: "Left", cell: CellRect(col: 0, row: 0, w: 1, h: 2), keyCode: 123, modifiers: 6400)]
        layouts = [Layout(name: "Dev", placements: [])]
    }
}

// MARK: - The clickable grid

/// A live miniature of the screen: the windows that are on it now, drawn on the grid they sit
/// on, and a click or a drag to send the active one anywhere.
/// Row 0 is the top row, exactly as in `CellRect`, which is also SwiftUI's y direction.
struct GridPicker: View {
    let grid: GridSpec
    let screenAspect: CGFloat
    var occupants: [AutoArrange.Occupant] = []
    var selected: CellRect?
    var enabled = true
    /// Whether a plain click can place the front window. Dragging a window on the map works
    /// even when it cannot: that gesture is about the window under the finger.
    var canPick = true
    let onPick: (CellRect) -> Void
    var onMove: ((AutoArrange.Occupant, CellRect) -> Void)?

    /// A window picked up from the map: which one, and where inside it the drag started, so it
    /// follows the pointer by the corner you grabbed rather than jumping under it.
    private struct WindowDrag {
        let index: Int
        let colOffset: Int
        let rowOffset: Int
    }

    @State private var anchor: CellRect?
    @State private var highlight: CellRect?
    @State private var windowDrag: WindowDrag?
    @State private var travelled = false

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
                             with: .color(.primary.opacity(0.10)))
            }
        }
        // Back to front, so the active window ends up on top of whatever it overlaps.
        for occupant in occupants.reversed() {
            draw(occupant, in: context, cellW: cellW, cellH: cellH, inset: inset)
        }
        guard let shown = highlight ?? selected else { return }
        let cell = shown.clamped(to: g)
        let rect = CGRect(x: CGFloat(cell.col) * cellW, y: CGFloat(cell.row) * cellH,
                          width: CGFloat(cell.w) * cellW, height: CGFloat(cell.h) * cellH)
            .insetBy(dx: inset, dy: inset)
        context.fill(Path(roundedRect: rect, cornerRadius: 3),
                     with: .color(.accentColor.opacity(enabled ? 0.85 : 0.35)))
    }

    /// One window's tile: the active one in the accent colour, the ones a layout cannot place
    /// exactly (full screen, or a minimum size larger than the cell) hollow and dashed.
    private func draw(_ occupant: AutoArrange.Occupant, in context: GraphicsContext,
                      cellW: CGFloat, cellH: CGFloat, inset: CGFloat) {
        let cell = occupant.cell.clamped(to: grid.clamped())
        let rect = CGRect(x: CGFloat(cell.col) * cellW, y: CGFloat(cell.row) * cellH,
                          width: CGFloat(cell.w) * cellW, height: CGFloat(cell.h) * cellH)
            .insetBy(dx: inset, dy: inset)
        guard rect.width > 3, rect.height > 3 else { return }
        let shape = Path(roundedRect: rect, cornerRadius: 3)
        if occupant.resistant {
            context.fill(shape, with: .color(.primary.opacity(0.06)))
            context.stroke(shape, with: .color(.primary.opacity(0.4)),
                           style: StrokeStyle(lineWidth: 1, dash: [2.5, 2]))
        } else if occupant.isFocused {
            context.fill(shape, with: .color(.accentColor.opacity(0.85)))
        } else {
            context.fill(shape, with: .color(.primary.opacity(0.28)))
        }
        guard rect.height > 11 else { return }
        let initial = String(occupant.appName.prefix(1))
        let fits = rect.width > CGFloat(occupant.appName.count) * 5.4 + 6
        let label = fits ? occupant.appName : initial
        guard rect.width > 9 else { return }
        let color: Color = occupant.isFocused ? .white : .primary.opacity(0.75)
        context.draw(Text(label).font(.system(size: 9, weight: .medium)).foregroundColor(color),
                     at: CGPoint(x: rect.midX, y: rect.midY))
    }

    /// One gesture, two meanings, decided on the first event and never mid-drag:
    /// starting on a window drags *that* window, starting on free space sweeps a rectangle of
    /// cells for the front window. A press that never moves keeps the old meaning either way.
    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard enabled else { return }
                let current = cell(at: value.location, in: size)
                let g = grid.clamped()
                if anchor == nil && windowDrag == nil {
                    let held = occupants.firstIndex {
                        !$0.resistant && $0.cell.clamped(to: g).contains(col: current.col, row: current.row)
                    }
                    if let held, onMove != nil {
                        let cell = occupants[held].cell.clamped(to: g)
                        windowDrag = WindowDrag(index: held,
                                                colOffset: current.col - cell.col,
                                                rowOffset: current.row - cell.row)
                    } else {
                        anchor = CellRect(col: current.col, row: current.row)
                    }
                }
                if abs(value.translation.width) + abs(value.translation.height) > 4 {
                    travelled = true
                }
                if let drag = windowDrag {
                    let cell = occupants[drag.index].cell.clamped(to: g)
                    let col = min(max(0, current.col - drag.colOffset), max(0, g.cols - cell.w))
                    let row = min(max(0, current.row - drag.rowOffset), max(0, g.rows - cell.h))
                    highlight = CellRect(col: col, row: row, w: cell.w, h: cell.h)
                } else if let start = anchor {
                    highlight = CellRect.spanning((start.col, start.row), current).clamped(to: grid)
                }
            }
            .onEnded { _ in
                let picked = highlight
                let drag = windowDrag
                let moved = travelled
                anchor = nil; highlight = nil; windowDrag = nil; travelled = false
                guard enabled, let picked else { return }
                if let drag, moved {
                    let occupant = occupants[drag.index]
                    guard picked != occupant.cell.clamped(to: grid.clamped()) else { return }
                    onMove?(occupant, picked)
                } else if canPick {
                    onPick(picked)
                }
            }
    }

    private func cell(at point: CGPoint, in size: CGSize) -> (col: Int, row: Int) {
        let g = grid.clamped()
        let col = Int(point.x / max(1, size.width / CGFloat(g.cols)))
        let row = Int(point.y / max(1, size.height / CGFloat(g.rows)))
        return (max(0, min(col, g.cols - 1)), max(0, min(row, g.rows - 1)))
    }
}

// MARK: - Quick grid

/// The grid presets worth having on a screen of this shape, plus the automatic one.
/// Picking one writes it for the screen under the mouse; with "re-arrange when the grid changes"
/// on (the default) the windows follow at once, with the popover still open.
struct GridChips: View {
    let grid: GridSpec
    let auto: Bool
    let aspect: CGFloat
    var enabled = true
    let onPick: (GridSpec?) -> Void

    /// A wide screen wants columns, a tall one wants rows: offering 1×2 on an ultrawide would
    /// be a preset nobody can use.
    private var presets: [(cols: Int, rows: Int)] {
        let shape: [(Int, Int)]
        if aspect >= 2.1 {
            shape = [(2, 1), (3, 1), (4, 1), (3, 2)]
        } else if aspect >= 1.2 {
            shape = [(2, 1), (2, 2), (3, 2), (4, 2)]
        } else {
            shape = [(1, 2), (2, 2), (2, 3)]
        }
        // A grid set by hand from the steppers stays visible and selected among the presets.
        if !auto && !shape.contains(where: { $0.0 == grid.cols && $0.1 == grid.rows }) {
            return shape + [(grid.cols, grid.rows)]
        }
        return shape
    }

    var body: some View {
        HStack(spacing: 4) {
            chip(label: "Auto", selected: auto) { onPick(nil) }
            ForEach(presets.indices, id: \.self) { index in
                let preset = presets[index]
                chip(label: "\(preset.cols)×\(preset.rows)",
                     selected: !auto && grid.cols == preset.cols && grid.rows == preset.rows) {
                    onPick(GridSpec(cols: preset.cols, rows: preset.rows,
                                    outerGap: grid.outerGap, innerGap: grid.innerGap))
                }
            }
        }
        .opacity(enabled ? 1 : 0.4)
    }

    private func chip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.75))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3.5)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Color.accentColor : Color.primary.opacity(0.07)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Rows

/// One tappable line: a label, an optional value or shortcut on the right, a note underneath.
struct PopoverRow: View {
    let title: String
    var trailing: String = ""
    var note: String?
    var chevron = false
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
                    if chevron {
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
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

/// The title line inside a card: a name, an optional badge, an optional trailing note.
struct CardHeader: View {
    let title: String
    var badge: String?
    var trailing: String?

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold))
            if let badge {
                Text(badge).font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(Capsule().fill(Color.accentColor.opacity(0.16)))
                    .foregroundStyle(Color.accentColor)
            }
            Spacer(minLength: 6)
            if let trailing {
                Text(trailing).font(.system(size: 10.5)).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
    }
}

// MARK: - The popover

struct TesseraPopover: View {
    @ObservedObject var model: PopoverModel
    @ObservedObject var prefs: PrefsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            switch model.page {
            case .home: home
            case .settings: SettingsPage(model: prefs, popover: model, maxHeight: model.pageMaxHeight)
            case .zones: ZonesPage(model: prefs, maxHeight: model.pageMaxHeight)
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 272)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Header and footer

    private var title: String {
        switch model.page {
        case .home: return "Tessera"
        case .settings: return tr("Settings")
        case .zones: return tr("Zones")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if model.page != .home {
                Button { model.page = model.page == .zones ? .settings : .home } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
            }
            Text(title).font(.system(size: 14, weight: .bold))
            Spacer()
            if model.page == .home {
                Button { model.page = .settings } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless)
                    .help(tr("Settings"))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: "square.grid.2x2").font(.system(size: 9))
            Text("Tessera \(appVersion)").font(.system(size: 10.5))
            Spacer()
            Button(tr("Quit")) { NSApp.terminate(nil) }.buttonStyle(.borderless).font(.system(size: 11))
        }
        .foregroundStyle(.tertiary)
    }

    // MARK: Home

    private var home: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.trusted { warning }
            gridCard
            arrangeCard
            if !model.zones.isEmpty { zonesCard }
            layoutsCard
        }
    }

    private var warning: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(tr("Accessibility access is missing."))
                .font(.system(size: 11.5, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(tr("Open")) { MenuBarController.shared.openAccessibility() }.controlSize(.small)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.orange.opacity(0.12)))
    }

    private var gridCard: some View {
        TesseraCard {
            HStack(spacing: 5) {
                Text(model.screenName.isEmpty ? tr("Screen") : model.screenName)
                    .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text("·").foregroundStyle(.tertiary)
                Text("\(model.grid.cols)×\(model.grid.rows)")
                    .font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Color.accentColor)
                if model.autoGrid {
                    Text("auto").font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor.opacity(0.16)))
                        .foregroundStyle(Color.accentColor)
                }
                Spacer(minLength: 4)
                Text(windowCount(model.windowCount))
                    .font(.system(size: 11, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if let line = statusNote {
                Text(line).font(.system(size: 10.5)).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            GridChips(grid: model.grid, auto: model.autoGrid, aspect: model.screenAspect,
                      enabled: model.trusted) { spec in
                MenuBarController.shared.setGrid(spec)
            }
            GridPicker(grid: model.grid, screenAspect: model.screenAspect,
                       occupants: model.occupants, enabled: model.trusted,
                       canPick: model.canPlace,
                       onPick: { cell in MenuBarController.shared.place(in: cell) },
                       onMove: { occupant, cell in
                           MenuBarController.shared.move(occupant, to: cell)
                       })
            .frame(height: 96)
            .frame(maxWidth: .infinity)
            Text(mapNote)
                .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The windows that will not end up exactly where a layout puts them, said once, quietly.
    /// What stays out of the grid for lack of cells belongs to the arrange button, not here.
    private var statusNote: String? {
        guard model.resistant > 0 else { return nil }
        return model.resistant == 1
            ? tr("1 dashed window won't fit exactly")
            : String(format: tr("%d dashed windows won't fit exactly"), model.resistant)
    }

    private var mapNote: String {
        if !model.trusted { return tr("Accessibility access is needed to see the windows.") }
        guard !model.occupants.isEmpty else {
            return model.canPlace
                ? String(format: tr("Click or drag to place %@."), model.appName ?? "")
                : tr("Bring a window to the front to place it.")
        }
        return model.canPlace
            ? String(format: tr("Drag a window to move it. Click a cell to place %@."),
                     model.appName ?? "")
            : tr("Drag a window to move it.")
    }

    private var arrangeCard: some View {
        TesseraCard {
            HStack(spacing: 6) {
                Button { MenuBarController.shared.arrange(with: model.strategy) } label: {
                    Text(tr("Arrange all")).font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!model.trusted)
            }
            strategyMenu
            Text(arrangeNote)
                .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            PopoverRow(title: tr("Fit the active window"), enabled: model.canPlace) {
                MenuBarController.shared.fitFocused()
            }
            PopoverRow(title: tr("Fit grid to windows"), enabled: model.trusted) {
                MenuBarController.shared.fitGridToWindows()
            }
        }
    }

    /// The composition, named and one click away: picking one makes it the default and
    /// arranges with it, so the choice is seen instead of living in the settings.
    private var strategyMenu: some View {
        HStack(spacing: 6) {
            Text(tr("Arrangement")).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Picker("", selection: Binding(get: { model.strategy },
                                          set: { MenuBarController.shared.setStrategy($0) })) {
                ForEach(ArrangeStrategy.allCases, id: \.self) { strategy in
                    Text(strategy.label).tag(strategy)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()
            .disabled(!model.trusted)
        }
    }

    private var arrangeNote: String {
        let head = model.tiled == 1
            ? tr("1 window in the grid")
            : String(format: tr("%d windows in the grid"), model.tiled)
        guard model.untouched > 0 else { return head }
        let tail = model.untouched == 1
            ? tr("1 stays where it is")
            : String(format: tr("%d stay where they are"), model.untouched)
        return head + " · " + tail
    }

    private var zonesCard: some View {
        TesseraCard {
            CardHeader(title: tr("Zones"))
            ForEach(model.zones) { zone in
                PopoverRow(title: zone.name,
                           trailing: hotkeyDescription(keyCode: zone.keyCode, modifiers: zone.modifiers),
                           enabled: model.canPlace) {
                    MenuBarController.shared.place(in: zone.cell)
                }
            }
        }
    }

    private var layoutsCard: some View {
        TesseraCard {
            CardHeader(title: tr("Layouts"))
            if model.layouts.isEmpty {
                Text(tr("No saved layouts."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(model.layouts) { layout in
                PopoverRow(title: layout.name,
                           trailing: hotkeyDescription(keyCode: layout.keyCode, modifiers: layout.modifiers),
                           enabled: model.trusted) {
                    MenuBarController.shared.apply(layout)
                }
            }
            Button(tr("Save current layout…")) { MenuBarController.shared.saveLayout() }
                .controlSize(.small)
                .disabled(!model.trusted)
        }
    }

    private func windowCount(_ n: Int) -> String {
        n == 1 ? tr("1 window") : String(format: tr("%d windows"), n)
    }
}

// MARK: - The status item

final class MenuBarController: NSObject, NSPopoverDelegate {
    static let shared = MenuBarController()
    private override init() {}

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let model = PopoverModel()
    private let prefs = PrefsModel()

    /// The window that was focused just before the popover took over. Read before showing it —
    /// afterwards the popover is frontmost and `AX.focusedWindow()` answers with the wrong thing.
    private var capturedWindow: ManagedWindow?

    var isPopoverShown: Bool { popover.isShown }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Logo.statusItemIcon()
        item.button?.toolTip = "Tessera"
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        statusItem = item
        popover.behavior = .transient
        popover.delegate = self
    }

    /// Re-reads the config while the popover is open. Closed, it will read it again on the next open.
    func refresh() {
        guard popover.isShown else { return }
        model.reload(window: capturedWindow)
        prefs.reload()
    }

    @objc private func statusItemClicked() {
        togglePopover(page: .home)
    }

    /// Shows the popover on `page`, or closes it when that page is already the one on screen.
    func togglePopover(page: PopoverPage) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            if model.page == page { closePopover() } else { model.page = page }
            return
        }
        capturedWindow = AX.isTrusted ? AX.focusedWindow() : nil
        model.reload(window: capturedWindow)
        prefs.reload()
        model.page = page
        let host = NSHostingController(rootView: TesseraPopover(model: model, prefs: prefs))
        host.sizingOptions = [.preferredContentSize]   // grow and shrink with the content
        popover.contentViewController = host
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func closePopover() {
        if popover.isShown { popover.performClose(nil) }
    }

    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
        capturedWindow = nil
        model.page = .home
    }

    // MARK: Actions

    /// Places the captured window directly: going through `AppController.placeFocused` would
    /// re-read the frontmost app, which by now is this popover's own.
    func place(in cell: CellRect) {
        defer { closePopover() }
        guard let window = capturedWindow else { return }
        let screen = AX.screen(of: window)
        OverlayController.shared.flash(cell: cell, on: screen)
        AX.place(window, in: cell, on: screen)
        giveFocusBack(to: window)
    }

    /// Moves one window straight from the map. It is about that window, not the front one, and
    /// you will often move another right after, so the popover stays open. The map is redrawn a
    /// beat later: an app answers a write on its own run loop, and reading at once would draw
    /// the window where it no longer is.
    func move(_ occupant: AutoArrange.Occupant, to cell: CellRect) {
        let screen = AX.screen(of: occupant.window)
        OverlayController.shared.flash(cell: cell, on: screen)
        AX.place(occupant.window, in: cell, on: screen)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.popover.isShown else { return }
            self.model.reload(window: self.capturedWindow)
        }
    }

    func fitFocused() {
        defer { closePopover() }
        guard let window = capturedWindow else { return }
        AutoArrange.fit(window)
        giveFocusBack(to: window)
    }

    /// Opening the popover had to activate Tessera; hand the keyboard back to the app whose
    /// window was just moved, or the user ends up typing into nothing.
    private func giveFocusBack(to window: ManagedWindow) {
        NSRunningApplication(processIdentifier: window.pid)?.activate()
    }

    /// One-off: recompute the grid from how many windows are open, then tile them into it.
    func fitGridToWindows() {
        closePopover()
        AppController.shared.fitGridAndArrange(on: NSScreen.underMouse)
    }

    /// Quick grid change from the home page. `nil` means automatic: the grid is then taken
    /// from how many windows are open, which only makes sense together with the arranging,
    /// so that one tiles at once. A fixed grid is only written — `rearrangeOnGridChange`
    /// decides whether the windows follow, exactly as it does from the settings page.
    /// The popover stays open either way: this is a knob you turn while looking at the map.
    func setGrid(_ spec: GridSpec?) {
        let key = model.screenKey
        guard let screen = NSScreen.screen(forKey: key) else { return }
        if let spec {
            Store.shared.mutate { config in
                config.autoGrid[key] = false
                config.grids[key] = spec.clamped()
            }
        } else {
            Store.shared.mutate { $0.autoGrid[key] = true }
            AppController.shared.fitGridAndArrange(on: screen)
        }
        model.reload(window: capturedWindow)
        prefs.reload()
    }

    /// Picking a composition makes it the default and applies it right away.
    func setStrategy(_ strategy: ArrangeStrategy) {
        Store.shared.mutate { $0.defaultStrategy = strategy }
        arrange(with: strategy)
    }

    func arrange(with strategy: ArrangeStrategy) {
        closePopover()
        AppController.shared.arrangeCurrentScreen(strategy)
    }

    func apply(_ layout: Layout) {
        closePopover()
        AppController.shared.apply(layout)
    }

    func saveLayout() {
        // The snapshot has to be taken before the alert steals the front window.
        let layout = AppController.shared.captureLayout(named: "")
        closePopover()
        let alert = NSAlert()
        alert.messageText = tr("Save the current layout")
        alert.informativeText = tr("Name the windows as they sit right now.")
        alert.addButton(withTitle: tr("Save"))
        alert.addButton(withTitle: tr("Cancel"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = tr("Name")
        field.stringValue = String(format: tr("Layout %d"), Store.shared.config.layouts.count + 1)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Store.shared.mutate { $0.layouts.append(Layout(name: name, placements: layout.placements)) }
    }

    func openAccessibility() {
        closePopover()
        AX.openAccessibilitySettings()
    }
}
