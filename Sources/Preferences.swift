// Tessera — the settings window: grid, zones, automatic arrangement, general options.
//
// Editing model: the SwiftUI state below is a one-way mirror of the Store. Every control writes
// through `PrefsModel.update`, which calls `Store.shared.mutate` and then re-reads the config.
// This window deliberately does not listen to `Store.shared.onChange` (that handler is
// AppController's): observing it here would turn every keystroke into a write/refresh loop.
//
// The visual idiom — narrow column, cards with an uppercase caption, 12 pt labels with a 10.5 pt
// note underneath — is Burny's, and the shared pieces (`TesseraCard`, `SettingRow`) live here.

import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Shared style

/// A titled card: the one container both the popover and this window are built out of.
struct TesseraCard<Content: View>: View {
    var title: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            VStack(alignment: .leading, spacing: 8) { content }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.055)))
        }
    }
}

/// A label, an optional explanation under it, and the control on the right.
struct SettingRow<Control: View>: View {
    let label: String
    var note: String?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 12))
                if let note {
                    Text(note).font(.system(size: 10.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control
        }
    }
}

private struct MiniStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 22, alignment: .trailing)
            Stepper("", value: $value, in: range).labelsHidden().controlSize(.small)
        }
    }
}

private struct MiniSlider: View {
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>

    var body: some View {
        HStack(spacing: 6) {
            Slider(value: $value, in: range).controlSize(.small).frame(width: 104)
            Text("\(Int(value.rounded()))")
                .font(.system(size: 11, design: .rounded)).monospacedDigit()
                .foregroundStyle(.secondary).frame(width: 20, alignment: .trailing)
        }
    }
}

// MARK: - Window

final class PreferencesWindowController {
    static let shared = PreferencesWindowController()

    private let model = PrefsModel()
    private var window: NSWindow?

    private init() {}

    func show() {
        model.reload()
        if window == nil {
            let hosting = NSHostingController(rootView: PrefsRootView(model: model))
            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable]
            window.title = "Impostazioni di Tessera"
            window.isReleasedWhenClosed = false   // we reuse this very instance on every show()
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
    @Published var previewWindowCount = 4
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
            return PrefsScreenOption(id: screen.tesseraKey,
                                     title: "\(screen.localizedName) — \(Int(size.width))×\(Int(size.height))")
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
            config.zones.append(Zone(name: "Zona \(config.zones.count + 1)",
                                     cell: CellRect(col: 0, row: 0, w: 1, h: 1)))
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

// MARK: - Preview of a set of cells

struct PrefsPreviewTile: Identifiable {
    let id: Int
    let cell: CellRect
    let label: String
}

/// The grid as it will look, with the tiles that would be used numbered.
struct PrefsGridPreview: View {
    let grid: GridSpec
    let screenAspect: CGFloat
    let tiles: [PrefsPreviewTile]
    var height: CGFloat = 104

    var body: some View {
        Canvas { context, size in draw(in: context, size: size) }
            .aspectRatio(screenAspect, contentMode: .fit)
            .frame(height: height)
            .frame(maxWidth: .infinity)
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        let g = grid.clamped()
        let area = CGRect(origin: .zero, size: size)
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
        for tile in tiles {
            let cell = tile.cell.clamped(to: g)
            // Same maths as the real placement, so the preview cannot drift from it.
            let rect = Geometry.frame(for: cell, in: GridSpec(cols: g.cols, rows: g.rows,
                                                              outerGap: 0, innerGap: 0),
                                      on: area)
            let flipped = CGRect(x: rect.minX, y: size.height - rect.maxY,
                                 width: rect.width, height: rect.height)
                .insetBy(dx: inset, dy: inset)
            context.fill(Path(roundedRect: flipped, cornerRadius: 3),
                         with: .color(.accentColor.opacity(0.8)))
            guard flipped.width > 14, flipped.height > 12, !tile.label.isEmpty else { continue }
            let text = Text(tile.label).font(.system(size: 9, weight: .semibold)).foregroundColor(.white)
            context.draw(text, at: CGPoint(x: flipped.midX, y: flipped.midY))
        }
    }
}

// MARK: - Root

private enum PrefsTab: String, CaseIterable, Identifiable {
    case grid, zones, auto, general
    var id: String { rawValue }
    var label: String {
        switch self {
        case .grid: return "Griglia"
        case .zones: return "Zone"
        case .auto: return "Automatico"
        case .general: return "Generale"
        }
    }
}

struct PrefsRootView: View {
    @ObservedObject var model: PrefsModel
    @State private var tab = PrefsTab.grid

    var body: some View {
        VStack(spacing: 10) {
            Picker("", selection: $tab) {
                ForEach(PrefsTab.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch tab {
                    case .grid: PrefsGridTab(model: model)
                    case .zones: PrefsZonesTab(model: model)
                    case .auto: PrefsAutoTab(model: model)
                    case .general: PrefsGeneralTab(model: model)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)
            }
        }
        .padding(14)
        .frame(width: 360, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Grid

struct PrefsGridTab: View {
    @ObservedObject var model: PrefsModel

    private let presets: [(cols: Int, rows: Int)] = [(2, 2), (3, 2), (12, 8), (16, 9)]

    var body: some View {
        TesseraCard(title: "Schermo") {
            if model.screens.count > 1 {
                Picker("", selection: $model.screenKey) {
                    ForEach(model.screens) { Text($0.title).tag($0.id) }
                }
                .labelsHidden()
            } else {
                Text(model.screens.first?.title ?? "Schermo principale")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        TesseraCard(title: "Celle") {
            SettingRow(label: "Colonne") {
                MiniStepper(value: model.bindGrid(\.cols), range: 1...32)
            }
            SettingRow(label: "Righe") {
                MiniStepper(value: model.bindGrid(\.rows), range: 1...32)
            }
            Divider()
            SettingRow(label: "Margine esterno") {
                MiniSlider(value: model.bindGrid(\.outerGap), range: 0...40)
            }
            SettingRow(label: "Spazio fra le celle") {
                MiniSlider(value: model.bindGrid(\.innerGap), range: 0...40)
            }
            Divider()
            HStack(spacing: 6) {
                ForEach(presets, id: \.cols) { preset in
                    Button("\(preset.cols)×\(preset.rows)") {
                        model.setGrid(cols: preset.cols, rows: preset.rows)
                    }
                    .controlSize(.small)
                }
            }
        }
        TesseraCard(title: "Anteprima") {
            PrefsGridPreview(grid: model.grid, screenAspect: model.screenAspect, tiles: [])
            Button("Sistema adesso") {
                AppController.shared.arrangeCurrentScreen(Store.shared.config.defaultStrategy)
            }
            .controlSize(.small)
            Text("Dispone subito le finestre dello schermo sotto il puntatore con la strategia predefinita.")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Zones

struct PrefsZonesTab: View {
    @ObservedObject var model: PrefsModel

    var body: some View {
        TesseraCard(title: "Zone") {
            if model.config.zones.isEmpty {
                Text("Nessuna zona. Una zona è un'area della griglia con una scorciatoia globale.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(model.config.zones) { zone in
                PrefsZoneRow(model: model, zone: model.bindZone(zone)) { model.removeZone(zone) }
                if zone.id != model.config.zones.last?.id { Divider() }
            }
            Button("Aggiungi zona") { model.addZone() }.controlSize(.small)
        }
    }
}

struct PrefsZoneRow: View {
    @ObservedObject var model: PrefsModel
    @Binding var zone: Zone
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField("Nome", text: $zone.name)
                    .textFieldStyle(.roundedBorder).controlSize(.small).frame(width: 120)
                Spacer(minLength: 4)
                HotkeyRecorder(keyCode: $zone.keyCode, modifiers: $zone.modifiers)
                    .frame(width: 96, height: 22)
                Button { onDelete() } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("Elimina la zona")
            }
            GridPicker(grid: model.grid, screenAspect: model.screenAspect, selected: zone.cell) { cell in
                zone.cell = cell
            }
            .frame(height: 76)
        }
    }
}

// MARK: - Automatic

struct PrefsAutoTab: View {
    @ObservedObject var model: PrefsModel

    var body: some View {
        TesseraCard(title: "Strategia predefinita") {
            Picker("", selection: model.bind(\.defaultStrategy)) {
                ForEach(ArrangeStrategy.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            Text(model.config.defaultStrategy.detail)
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.config.defaultStrategy == .masterStack {
                SettingRow(label: "Larghezza del master") {
                    HStack(spacing: 6) {
                        Slider(value: model.bind(\.masterFraction), in: 0.3...0.8)
                            .controlSize(.small).frame(width: 104)
                        Text("\(Int((model.config.masterFraction * 100).rounded()))%")
                            .font(.system(size: 11, design: .rounded)).monospacedDigit()
                            .foregroundStyle(.secondary).frame(width: 32, alignment: .trailing)
                    }
                }
            }
        }
        TesseraCard(title: "Finestre nuove") {
            SettingRow(label: "Sistemale da sole",
                       note: "Una finestra appena aperta finisce nel buco più grande della griglia.") {
                Toggle("", isOn: model.bind(\.autoFitNewWindows))
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden()
            }
        }
        TesseraCard(title: "Anteprima") {
            SettingRow(label: "Finestre") {
                MiniStepper(value: $model.previewWindowCount, range: 1...16)
            }
            PrefsGridPreview(grid: model.grid, screenAspect: model.screenAspect, tiles: tiles)
        }
    }

    private var tiles: [PrefsPreviewTile] {
        let cells = AutoArrange.partition(count: model.previewWindowCount,
                                          grid: model.grid,
                                          screenAspect: model.screenAspect,
                                          strategy: model.config.defaultStrategy,
                                          masterFraction: model.config.masterFraction)
        return cells.enumerated().map { PrefsPreviewTile(id: $0.offset, cell: $0.element,
                                                         label: "\($0.offset + 1)") }
    }
}

// MARK: - General

struct PrefsGeneralTab: View {
    @ObservedObject var model: PrefsModel

    var body: some View {
        TesseraCard(title: "Generale") {
            SettingRow(label: "Apri al login") {
                Toggle("", isOn: Binding(get: { model.launchAtLogin },
                                         set: { model.setLaunchAtLogin($0) }))
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden()
            }
            Divider()
            SettingRow(label: "Ridisponi subito quando cambio la griglia",
                       note: "Le finestre dello schermo vengono sistemate all'istante, senza aspettare la prossima mossa.") {
                Toggle("", isOn: model.bind(\.rearrangeOnGridChange))
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden()
            }
        }
        TesseraCard(title: "Accessibilità") { PrefsAccessibilityStatus(model: model) }
        TesseraCard {
            HStack {
                Text("Tessera \(appVersion)").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                Spacer()
                Button("Mostra configurazione") { PrefsGeneralTab.revealConfig() }.controlSize(.small)
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
            Label("Accesso attivo", systemImage: "checkmark.circle")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Senza l'accesso Accessibilità, Tessera non può spostare le finestre.")
                    .font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                Button("Apri Impostazioni di Sistema") {
                    AX.openAccessibilitySettings()
                    model.accessibilityTrusted = AX.isTrusted
                }
                .controlSize(.small)
            }
        }
    }
}
