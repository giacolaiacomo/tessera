// Tessera — the settings, as pages of the menu bar popover: grid, zones, automatic
// arrangement, general options. There is no settings window.
//
// Editing model: the SwiftUI state below is a one-way mirror of the Store. Every control writes
// through `PrefsModel.update`, which calls `Store.shared.mutate` and then re-reads the config.
// These pages deliberately do not listen to `Store.shared.onChange` (that handler is
// AppController's): observing it here would turn every keystroke into a write/refresh loop.
//
// The visual idiom — narrow column, cards with an uppercase caption, 12 pt labels with a 10.5 pt
// note underneath — is Burny's, and the shared pieces (`TesseraCard`, `SettingRow`) live here.

import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Shared style

/// A titled card: the one container every page is built out of.
struct TesseraCard<Content: View>: View {
    var title: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            VStack(alignment: .leading, spacing: 7) { content }
                .padding(9)
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
    enum Unit { case points, percent }

    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    var unit = Unit.points

    var body: some View {
        HStack(spacing: 6) {
            Slider(value: $value, in: range).controlSize(.small).frame(width: 84)
            Text(unit == .percent ? "\(Int((value * 100).rounded()))%" : "\(Int(value.rounded()))")
                .font(.system(size: 11, design: .rounded)).monospacedDigit()
                .foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
        }
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
    /// How many windows the selected screen holds — what an automatic grid is derived from.
    @Published private(set) var windowsOnScreen = 0

    init() {
        config = Store.shared.config
        screens = PrefsModel.screenOptions()
        screenKey = NSScreen.underMouse.tesseraKey   // the screen the popover is talking about
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
        countWindows()
        refreshAutoGrid()
    }

    /// The grid an automatic screen would get for the windows open right now — shown as a
    /// preview only. Nothing is written: the grid settles when you arrange, not when you look
    /// at this panel, or the layout would shift under windows already placed in it.
    var previewedAutoGrid: GridSpec? {
        guard config.isAutoGrid(screenKey), let screen = NSScreen.screen(forKey: screenKey)
        else { return nil }
        return AutoArrange.bestGrid(for: windowsOnScreen, on: screen, like: grid)
    }

    func refreshAutoGrid() {
        countWindows()
    }

    private func countWindows() {
        guard AX.isTrusted, let screen = NSScreen.screen(forKey: screenKey) else {
            windowsOnScreen = 0
            return
        }
        windowsOnScreen = AutoArrange.windows(on: screen).count
    }

    var isAutoGrid: Bool { config.isAutoGrid(screenKey) }

    func selectScreen(_ key: String) {
        screenKey = key
        countWindows()
        refreshAutoGrid()
    }

    func bindAutoGrid() -> Binding<Bool> {
        Binding(get: { self.isAutoGrid },
                set: { value in
                    let key = self.screenKey
                    self.update { $0.autoGrid[key] = value }
                    self.countWindows()
                    self.refreshAutoGrid()
                })
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
            config.zones.append(Zone(name: String(format: tr("Zone %d"), config.zones.count + 1),
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


// MARK: - Settings page

/// The settings as one narrow column inside the popover: sections stacked, the zones editor on
/// a page of its own because it is the only part that does not fit next to the rest.
struct SettingsPage: View {
    @ObservedObject var model: PrefsModel
    @ObservedObject var popover: PopoverModel
    var maxHeight: CGFloat = 380

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                PrefsGridSection(model: model)
                zonesLink
                PrefsAutoSection(model: model)
                PrefsGeneralSection(model: model)
            }
            .padding(.trailing, 2)   // room for the scroller
        }
        .frame(maxHeight: maxHeight)
    }

    private var zonesLink: some View {
        TesseraCard(title: tr("Zones")) {
            PopoverRow(title: tr("Areas with a shortcut"),
                       trailing: model.config.zones.isEmpty ? tr("none") : "\(model.config.zones.count)",
                       chevron: true) {
                popover.page = .zones
            }
        }
    }
}

// MARK: - Grid

struct PrefsGridSection: View {
    @ObservedObject var model: PrefsModel

    private let presets: [(cols: Int, rows: Int)] = [(2, 2), (3, 2), (12, 8), (16, 9)]

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("", selection: model.bindAutoGrid()) {
                Text(tr("Fixed")).tag(false)
                Text(tr("Automatic")).tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().controlSize(.small)
            Text(modeNote)
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modeNote: String {
        guard model.isAutoGrid else {
            return tr("The cells are the ones you pick, whatever is open.")
        }
        let grid = model.grid
        let windows = model.windowsOnScreen
        guard windows > 0 else { return tr("The cells come from how many windows are on the screen.") }
        let counted = windows == 1
            ? tr("1 open window")
            : String(format: tr("%d open windows"), windows)
        return String(format: tr("Now %d×%d, from %@."), grid.cols, grid.rows, counted)
    }

    var body: some View {
        TesseraCard(title: tr("Grid")) {
            if model.screens.count > 1 {
                Picker("", selection: Binding(get: { model.screenKey },
                                              set: { model.selectScreen($0) })) {
                    ForEach(model.screens) { Text($0.title).tag($0.id) }
                }
                .labelsHidden().controlSize(.small)
            } else {
                Text(model.screens.first?.title ?? tr("Main screen"))
                    .font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            modePicker
            // In automatic mode the cell count is the engine's to decide: the controls stay
            // visible, and dimmed, so it is clear what the mode took over.
            Group {
                SettingRow(label: tr("Columns")) {
                    MiniStepper(value: model.bindGrid(\.cols), range: 1...32)
                }
                SettingRow(label: tr("Rows")) {
                    MiniStepper(value: model.bindGrid(\.rows), range: 1...32)
                }
                HStack(spacing: 5) {
                    ForEach(presets, id: \.cols) { preset in
                        Button("\(preset.cols)×\(preset.rows)") {
                            model.setGrid(cols: preset.cols, rows: preset.rows)
                        }
                        .controlSize(.small)
                    }
                }
            }
            .disabled(model.isAutoGrid)
            .opacity(model.isAutoGrid ? 0.45 : 1)
            Divider()
            SettingRow(label: tr("Outer edge")) {
                MiniSlider(value: model.bindGrid(\.outerGap), range: 0...40)
            }
            SettingRow(label: tr("Between cells")) {
                MiniSlider(value: model.bindGrid(\.innerGap), range: 0...40)
            }
            Divider()
            PrefsGridPreview(grid: model.grid, screenAspect: model.screenAspect, tiles: [], height: 74)
            HStack {
                Button(tr("Arrange now")) {
                    AppController.shared.arrangeCurrentScreen(Store.shared.config.defaultStrategy)
                }
                .controlSize(.small)
                Spacer()
            }
            Text(tr("Arranges the windows on the screen under the pointer, right away."))
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Zones page

struct ZonesPage: View {
    @ObservedObject var model: PrefsModel
    var maxHeight: CGFloat = 380

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if model.config.zones.isEmpty {
                    TesseraCard {
                        Text(tr("No zones yet. A zone is an area of the grid with a global shortcut: press ⌃⌥1 and the active window lands in it."))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                ForEach(model.config.zones) { zone in
                    TesseraCard {
                        PrefsZoneRow(model: model, zone: model.bindZone(zone)) { model.removeZone(zone) }
                    }
                }
                HStack {
                    Button(tr("Add zone")) { model.addZone() }.controlSize(.small)
                    Spacer()
                }
            }
            .padding(.trailing, 2)
        }
        .frame(maxHeight: maxHeight)
    }
}

struct PrefsZoneRow: View {
    @ObservedObject var model: PrefsModel
    @Binding var zone: Zone
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                TextField(tr("Name"), text: $zone.name)
                    .textFieldStyle(.roundedBorder).controlSize(.small)
                Button { onDelete() } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help(tr("Delete the zone"))
            }
            HStack(spacing: 6) {
                Text(tr("Shortcut")).font(.system(size: 10.5)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                HotkeyRecorder(keyCode: $zone.keyCode, modifiers: $zone.modifiers)
                    .frame(width: 118, height: 22)
            }
            GridPicker(grid: model.grid, screenAspect: model.screenAspect, selected: zone.cell) { cell in
                zone.cell = cell
            }
            .frame(height: 72)
        }
    }
}

// MARK: - Automatic

struct PrefsAutoSection: View {
    @ObservedObject var model: PrefsModel

    var body: some View {
        TesseraCard(title: tr("Automatic arrangement")) {
            Picker("", selection: model.bind(\.defaultStrategy)) {
                ForEach(ArrangeStrategy.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .labelsHidden().controlSize(.small)
            Text(model.config.defaultStrategy.detail)
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.config.defaultStrategy == .masterStack {
                SettingRow(label: tr("Master width")) {
                    MiniSlider(value: model.bind(\.masterFraction), range: 0.3...0.8, unit: .percent)
                }
            }
            SettingRow(label: tr("Windows")) {
                MiniStepper(value: $model.previewWindowCount, range: 1...16)
            }
            PrefsGridPreview(grid: model.grid, screenAspect: model.screenAspect, tiles: tiles, height: 86)
            Divider()
            SettingRow(label: tr("Arrange new windows"),
                       note: tr("A window that has just opened lands in the biggest hole of the grid.")) {
                Toggle("", isOn: model.bind(\.autoFitNewWindows))
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden()
            }
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

struct PrefsGeneralSection: View {
    @ObservedObject var model: PrefsModel

    var body: some View {
        TesseraCard(title: tr("General")) {
            SettingRow(label: tr("Open at login")) {
                Toggle("", isOn: Binding(get: { model.launchAtLogin },
                                         set: { model.setLaunchAtLogin($0) }))
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden()
            }
            SettingRow(label: tr("Language")) {
                Picker("", selection: model.bind(\.language)) {
                    Text(tr("System")).tag("system")
                    Text("English").tag("en")
                    Text("Italiano").tag("it")
                }
                .labelsHidden().fixedSize().controlSize(.small)
            }
            Divider()
            SettingRow(label: tr("Re-arrange when the grid changes"),
                       note: tr("The screen's windows are arranged straight away.")) {
                Toggle("", isOn: model.bind(\.rearrangeOnGridChange))
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden()
            }
            Divider()
            PrefsAccessibilityStatus(model: model)
            Divider()
            SettingRow(label: tr("Configuration folder")) {
                Button(tr("Show")) { PrefsGeneralSection.revealConfig() }.controlSize(.small)
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
            Label(tr("Accessibility access is on"), systemImage: "checkmark.circle")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text(tr("Without Accessibility access, Tessera cannot move windows."))
                    .font(.system(size: 11)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button(tr("Open System Settings")) {
                    AX.openAccessibilitySettings()
                    model.accessibilityTrusted = AX.isTrusted
                }
                .controlSize(.small)
            }
        }
    }
}
