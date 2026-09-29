// Tessera — the preferences window: grid, zones, automatic arrangement, general options.
//
// Editing model: the SwiftUI state below is a one-way mirror of the Store. Every control writes
// through `PrefsModel.update`, which calls `Store.shared.mutate` and then re-reads the config.
// This window deliberately does not listen to `Store.shared.onChange` (that handler is
// AppController's): observing it here would turn every keystroke into a write/refresh loop.

import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Window

final class PreferencesWindowController {
    static let shared = PreferencesWindowController()

    private let model = PrefsModel()
    private var window: NSWindow?

    private init() {}

    func show() {
        model.reload()
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Preferenze di Tessera"
            window.isReleasedWhenClosed = false   // we reuse this very instance on every show()
            window.contentView = NSHostingView(rootView: PrefsRootView(model: model))
            window.center()
            self.window = window
        }
        // The app is an .accessory: without activating first, the window opens behind everything.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Model

struct PrefsScreenOption: Identifiable, Hashable {
    let id: String
    let title: String
}

final class PrefsModel: ObservableObject {
    @Published private(set) var config: Config
    @Published var screenKey: String
    @Published var screens: [PrefsScreenOption]
    @Published var previewWindowCount: Int = 3
    @Published var launchAtLogin: Bool
    @Published var accessibilityTrusted: Bool

    init() {
        config = Store.shared.config
        screens = PrefsModel.screenOptions()
        screenKey = (NSScreen.main ?? NSScreen.screens.first)?.tesseraKey ?? ""
        launchAtLogin = SMAppService.mainApp.status == .enabled
        accessibilityTrusted = AX.isTrusted
    }

    func reload() {
        config = Store.shared.config
        screens = PrefsModel.screenOptions()
        if !screens.contains(where: { $0.id == screenKey }) {
            screenKey = screens.first?.id ?? ""
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        accessibilityTrusted = AX.isTrusted
    }

    private static func screenOptions() -> [PrefsScreenOption] {
        NSScreen.screens.map { screen in
            let size = screen.frame.size
            let title = "\(screen.localizedName) — \(Int(size.width))×\(Int(size.height))"
            return PrefsScreenOption(id: screen.tesseraKey, title: title)
        }
    }

    // MARK: Derived

    var grid: GridSpec { config.grid(for: screenKey) }

    var visibleFrame: CGRect {
        NSScreen.screen(forKey: screenKey)?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1600, height: 1000)
    }

    var screenAspect: CGFloat {
        let frame = visibleFrame
        return frame.height > 0 ? frame.width / frame.height : 1.6
    }

    // MARK: Writing

    func update(_ body: (inout Config) -> Void) {
        Store.shared.mutate(body)
        config = Store.shared.config
    }

    func bind<T>(_ keyPath: WritableKeyPath<Config, T>) -> Binding<T> {
        Binding(get: { self.config[keyPath: keyPath] },
                set: { value in self.update { $0[keyPath: keyPath] = value } })
    }

    func bindGrid<T>(_ keyPath: WritableKeyPath<GridSpec, T>) -> Binding<T> {
        Binding(get: { self.grid[keyPath: keyPath] },
                set: { value in
                    let key = self.screenKey
                    self.update { config in
                        var grid = config.grid(for: key)
                        grid[keyPath: keyPath] = value
                        config.grids[key] = grid.clamped()
                    }
                })
    }

    func setGrid(cols: Int, rows: Int) {
        let key = screenKey
        update { config in
            var grid = config.grid(for: key)
            grid.cols = cols
            grid.rows = rows
            config.grids[key] = grid.clamped()
        }
    }

    func bindZone(_ zone: Zone) -> Binding<Zone> {
        Binding(get: { self.config.zones.first { $0.id == zone.id } ?? zone },
                set: { value in
                    self.update { config in
                        guard let index = config.zones.firstIndex(where: { $0.id == zone.id }) else { return }
                        config.zones[index] = value
                    }
                })
    }

    func addZone() {
        update { config in
            let cell = CellRect(col: 0, row: 0, w: 1, h: 1)
            config.zones.append(Zone(name: "Zona \(config.zones.count + 1)", cell: cell))
        }
    }

    func removeZone(_ zone: Zone) {
        update { config in config.zones.removeAll { $0.id == zone.id } }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = enabled
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Don't tell the user something we failed to do: show what the system really says.
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        let actual = launchAtLogin
        update { $0.launchAtLogin = actual }
    }
}

// MARK: - Grid preview

struct PrefsPreviewItem: Identifiable {
    let id = UUID()
    var cell: CellRect
    var label: String
}

/// The grid as it will land on the selected screen: same proportions, same gaps, scaled down.
struct PrefsGridPreview: View {
    var grid: GridSpec
    var aspect: CGFloat
    var items: [PrefsPreviewItem] = []

    var body: some View {
        Canvas { context, size in
            let box = PrefsGridPreview.box(aspect: aspect, in: size)
            let area = CGRect(origin: .zero, size: box.size)
            context.fill(Path(roundedRect: box, cornerRadius: 6),
                         with: .color(Color.primary.opacity(0.06)))
            drawCells(&context, grid: grid, area: area, box: box)
            drawItems(&context, grid: grid, area: area, box: box)
        }
        .frame(minWidth: 180, minHeight: 130)
    }

    private func drawCells(_ context: inout GraphicsContext, grid: GridSpec,
                           area: CGRect, box: CGRect) {
        let shading = GraphicsContext.Shading.color(Color.primary.opacity(0.14))
        for row in 0..<grid.rows {
            for col in 0..<grid.cols {
                let cell = CellRect(col: col, row: row, w: 1, h: 1)
                let rect = Geometry.frame(for: cell, in: grid, on: area)
                context.fill(Path(PrefsGridPreview.flip(rect, in: box)), with: shading)
            }
        }
    }

    private func drawItems(_ context: inout GraphicsContext, grid: GridSpec,
                           area: CGRect, box: CGRect) {
        let fill = GraphicsContext.Shading.color(Color.accentColor.opacity(0.55))
        let stroke = GraphicsContext.Shading.color(Color.accentColor)
        for item in items {
            let rect = Geometry.frame(for: item.cell, in: grid, on: area)
            let path = Path(PrefsGridPreview.flip(rect, in: box))
            context.fill(path, with: fill)
            context.stroke(path, with: stroke, lineWidth: 1)
            guard !item.label.isEmpty else { continue }
            let text = Text(item.label).font(.system(size: 9, weight: .semibold)).foregroundColor(.white)
            context.draw(text, in: PrefsGridPreview.flip(rect, in: box).insetBy(dx: 1, dy: 1))
        }
    }

    /// The largest rect with the screen's proportions that fits the canvas.
    private static func box(aspect: CGFloat, in size: CGSize) -> CGRect {
        let aspect = max(0.1, aspect)
        var width = size.width
        var height = width / aspect
        if height > size.height {
            height = size.height
            width = height * aspect
        }
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2,
                      width: width, height: height)
    }

    /// Cocoa rect (y up, origin at the box's bottom-left) to canvas rect (y down).
    private static func flip(_ rect: CGRect, in box: CGRect) -> CGRect {
        CGRect(x: box.minX + rect.minX, y: box.minY + (box.height - rect.maxY),
               width: max(1, rect.width), height: max(1, rect.height))
    }
}

// MARK: - Shared controls

struct PrefsScreenPicker: View {
    @ObservedObject var model: PrefsModel

    var body: some View {
        Picker("Schermo", selection: $model.screenKey) {
            ForEach(model.screens) { option in
                Text(option.title).tag(option.id)
            }
        }
        .pickerStyle(.menu)
    }
}

struct PrefsIntStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        Stepper(value: $value, in: range) {
            Text("\(label) \(value)")
                .font(.callout)
                .monospacedDigit()
        }
        .fixedSize()
    }
}

// MARK: - Root

struct PrefsRootView: View {
    @ObservedObject var model: PrefsModel

    var body: some View {
        TabView {
            PrefsGridTab(model: model).tabItem { Text("Griglia") }
            PrefsZonesTab(model: model).tabItem { Text("Zone") }
            PrefsAutoTab(model: model).tabItem { Text("Automatico") }
            PrefsGeneralTab(model: model).tabItem { Text("Generale") }
        }
        .padding(14)
        .frame(minWidth: 760, minHeight: 540)
    }
}

// MARK: - Tab 1: grid

struct PrefsGridTab: View {
    @ObservedObject var model: PrefsModel

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                PrefsScreenPicker(model: model)
                Text("La griglia è salvata per ogni schermo.")
                    .font(.caption).foregroundColor(.secondary)
                Divider()
                controls
                Divider()
                presets
                Spacer()
            }
            .frame(width: 320)

            VStack(alignment: .leading, spacing: 6) {
                Text("Anteprima").font(.headline)
                PrefsGridPreview(grid: model.grid, aspect: model.screenAspect)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            PrefsIntStepper(label: "Colonne:", value: model.bindGrid(\.cols), range: 1...32)
            PrefsIntStepper(label: "Righe:", value: model.bindGrid(\.rows), range: 1...32)
            PrefsGapSlider(label: "Margine esterno", value: model.bindGrid(\.outerGap))
            PrefsGapSlider(label: "Spazio fra le celle", value: model.bindGrid(\.innerGap))
        }
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preset").font(.headline)
            HStack(spacing: 8) {
                PrefsPresetButton(title: "2×2", cols: 2, rows: 2, model: model)
                PrefsPresetButton(title: "3×2", cols: 3, rows: 2, model: model)
                PrefsPresetButton(title: "12×8", cols: 12, rows: 8, model: model)
                PrefsPresetButton(title: "16×9", cols: 16, rows: 9, model: model)
            }
        }
    }
}

struct PrefsGapSlider: View {
    let label: String
    @Binding var value: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(label): \(Int(value.rounded())) pt").font(.callout)
            Slider(value: $value, in: 0...40)
        }
    }
}

struct PrefsPresetButton: View {
    let title: String
    let cols: Int
    let rows: Int
    @ObservedObject var model: PrefsModel

    var body: some View {
        Button(title) { model.setGrid(cols: cols, rows: rows) }
    }
}

// MARK: - Tab 2: zones

struct PrefsZonesTab: View {
    @ObservedObject var model: PrefsModel

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Zone").font(.headline)
                    Spacer()
                    Button("Aggiungi zona") { model.addZone() }
                }
                zoneList
            }
            .frame(minWidth: 380)

            VStack(alignment: .leading, spacing: 6) {
                Text("Anteprima").font(.headline)
                PrefsGridPreview(grid: model.grid, aspect: model.screenAspect, items: previewItems)
                PrefsScreenPicker(model: model)
            }
            .frame(width: 280)
        }
    }

    private var zoneList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if model.config.zones.isEmpty {
                    Text("Nessuna zona. Aggiungine una per assegnarle una scorciatoia.")
                        .font(.callout).foregroundColor(.secondary)
                }
                ForEach(model.config.zones) { zone in
                    PrefsZoneRow(zone: model.bindZone(zone),
                                 grid: model.grid,
                                 onDelete: { model.removeZone(zone) })
                }
            }
            .padding(.trailing, 6)
        }
    }

    private var previewItems: [PrefsPreviewItem] {
        model.config.zones.map { PrefsPreviewItem(cell: $0.cell, label: $0.name) }
    }
}

struct PrefsZoneRow: View {
    @Binding var zone: Zone
    let grid: GridSpec
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Nome", text: $zone.name).frame(width: 160)
                Spacer()
                Button("Elimina", action: onDelete)
            }
            HStack(spacing: 10) {
                PrefsIntStepper(label: "Col:", value: $zone.cell.col, range: 0...max(0, grid.cols - 1))
                PrefsIntStepper(label: "Riga:", value: $zone.cell.row, range: 0...max(0, grid.rows - 1))
            }
            HStack(spacing: 10) {
                PrefsIntStepper(label: "Largh.:", value: $zone.cell.w,
                                range: 1...max(1, grid.cols - zone.cell.col))
                PrefsIntStepper(label: "Alt.:", value: $zone.cell.h,
                                range: 1...max(1, grid.rows - zone.cell.row))
            }
            HStack(spacing: 8) {
                Text("Scorciatoia").font(.callout).foregroundColor(.secondary)
                HotkeyRecorder(keyCode: $zone.keyCode, modifiers: $zone.modifiers)
                    .frame(width: 150, height: 24)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }
}

// MARK: - Tab 3: automatic

struct PrefsAutoTab: View {
    @ObservedObject var model: PrefsModel

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                strategyPicker
                masterSlider
                Divider()
                autoFitToggle
                Spacer()
            }
            .frame(width: 340)

            VStack(alignment: .leading, spacing: 8) {
                Text("Anteprima della strategia").font(.headline)
                Stepper(value: $model.previewWindowCount, in: 1...12) {
                    Text("Finestre: \(model.previewWindowCount)").monospacedDigit()
                }
                .fixedSize()
                PrefsGridPreview(grid: model.grid, aspect: model.screenAspect, items: previewItems)
                PrefsScreenPicker(model: model)
            }
        }
    }

    private var strategyPicker: some View {
        Picker("Strategia predefinita", selection: model.bind(\.defaultStrategy)) {
            ForEach(ArrangeStrategy.allCases, id: \.self) { strategy in
                Text(strategy.label).tag(strategy)
            }
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private var masterSlider: some View {
        if model.config.defaultStrategy == .masterStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Larghezza del master: \(Int((model.config.masterFraction * 100).rounded()))%")
                    .font(.callout)
                Slider(value: model.bind(\.masterFraction), in: 0.3...0.8)
            }
        }
    }

    private var autoFitToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Sistema automaticamente le finestre nuove", isOn: model.bind(\.autoFitNewWindows))
            Text("Una finestra appena aperta viene messa nell'area libera più grande della griglia.")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private var previewItems: [PrefsPreviewItem] {
        let cells = AutoArrange.partition(count: model.previewWindowCount,
                                          grid: model.grid,
                                          screenAspect: model.screenAspect,
                                          strategy: model.config.defaultStrategy,
                                          masterFraction: model.config.masterFraction)
        return cells.enumerated().map { PrefsPreviewItem(cell: $0.element, label: "\($0.offset + 1)") }
    }
}

// MARK: - Tab 4: general

struct PrefsGeneralTab: View {
    @ObservedObject var model: PrefsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            overlayOptions
            Divider()
            Toggle("Apri al login", isOn: launchBinding)
            Divider()
            PrefsAccessibilityStatus(model: model)
            Spacer()
            footer
        }
    }

    private var launchBinding: Binding<Bool> {
        Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) })
    }

    private var overlayOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Mostra la griglia mentre trascino una finestra",
                   isOn: model.bind(\.showOverlayOnDrag))
            Toggle("Solo tenendo premuto ⌥", isOn: model.bind(\.overlayModifierOnly))
                .disabled(!model.config.showOverlayOnDrag)
                .padding(.leading, 18)
        }
    }

    private var footer: some View {
        HStack {
            Text("Tessera \(appVersion)").font(.caption).foregroundColor(.secondary)
            Spacer()
            Button("Mostra il file di configurazione nel Finder") {
                PrefsGeneralTab.revealConfig()
            }
        }
    }

    private static func revealConfig() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tessera", isDirectory: true)
        NSWorkspace.shared.activateFileViewerSelecting([directory.appendingPathComponent("config.json")])
    }
}

struct PrefsAccessibilityStatus: View {
    @ObservedObject var model: PrefsModel

    var body: some View {
        if model.accessibilityTrusted {
            Label("Accesso Accessibilità attivo", systemImage: "checkmark.circle")
                .foregroundColor(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label("Tessera non può spostare le finestre senza l'accesso Accessibilità.",
                      systemImage: "exclamationmark.triangle")
                Button("Apri Impostazioni") {
                    AX.openAccessibilitySettings()
                    model.accessibilityTrusted = AX.isTrusted
                }
            }
        }
    }
}
