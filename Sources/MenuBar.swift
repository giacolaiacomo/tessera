// Tessera — the status item and its menu: the grid you can click, the zones, the automatic
// arrangements and the saved layouts.
//
// The menu is rebuilt in `menuWillOpen` because everything it shows depends on where the mouse
// is and on which window is in front at that instant.

import AppKit

// MARK: - The clickable grid

/// A miniature of the screen's grid. Click a cell or drag over several to pick an area.
/// Flipped coordinates, so row 0 is the top row exactly as in `CellRect`.
final class MenuBarGridView: NSView {
    private let grid: GridSpec
    private let screenAspect: CGFloat
    private let headerText: String
    private let placementEnabled: Bool

    /// Called on mouse-up with the picked area.
    var onPick: ((CellRect) -> Void)?

    private var anchor: (col: Int, row: Int)?
    private var highlight: CellRect?
    private var trackingArea: NSTrackingArea?

    private let padding: CGFloat = 12
    private let headerHeight: CGFloat = 18
    private static let gridWidth: CGFloat = 240

    init(grid: GridSpec, screen: NSScreen, headerText: String, placementEnabled: Bool) {
        self.grid = grid.clamped()
        let frame = screen.visibleFrame
        self.screenAspect = frame.width > 0 ? frame.height / frame.width : 0.6
        self.headerText = headerText
        self.placementEnabled = placementEnabled
        let gridHeight = (Self.gridWidth * self.screenAspect).rounded()
        super.init(frame: NSRect(x: 0, y: 0,
                                 width: Self.gridWidth + 2 * padding,
                                 height: gridHeight + headerHeight + 2 * padding))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override var isFlipped: Bool { true }

    private var gridRect: CGRect {
        CGRect(x: padding, y: padding + headerHeight,
               width: bounds.width - 2 * padding,
               height: bounds.height - headerHeight - 2 * padding)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let header = NSAttributedString(string: headerText, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        header.draw(in: CGRect(x: padding, y: padding - 2,
                               width: bounds.width - 2 * padding, height: headerHeight))

        let area = gridRect
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: area, xRadius: 4, yRadius: 4).fill()

        let cellW = area.width / CGFloat(grid.cols)
        let cellH = area.height / CGFloat(grid.rows)
        let inset: CGFloat = 1

        NSColor.tertiaryLabelColor.setFill()
        for row in 0..<grid.rows {
            for col in 0..<grid.cols {
                let cell = CGRect(x: area.minX + CGFloat(col) * cellW,
                                  y: area.minY + CGFloat(row) * cellH,
                                  width: cellW, height: cellH).insetBy(dx: inset, dy: inset)
                NSBezierPath(roundedRect: cell, xRadius: 2, yRadius: 2).fill()
            }
        }

        if let highlight {
            let rect = CGRect(x: area.minX + CGFloat(highlight.col) * cellW,
                              y: area.minY + CGFloat(highlight.row) * cellH,
                              width: CGFloat(highlight.w) * cellW,
                              height: CGFloat(highlight.h) * cellH).insetBy(dx: inset, dy: inset)
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
        }

        NSColor.separatorColor.setStroke()
        let border = NSBezierPath(roundedRect: area.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        border.lineWidth = 1
        border.stroke()
    }

    // MARK: Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited,
                                            .enabledDuringMouseDrag],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    private func cell(at point: CGPoint) -> (col: Int, row: Int)? {
        let area = gridRect
        guard area.contains(point) else { return nil }
        let col = Int((point.x - area.minX) / (area.width / CGFloat(grid.cols)))
        let row = Int((point.y - area.minY) / (area.height / CGFloat(grid.rows)))
        return (max(0, min(col, grid.cols - 1)), max(0, min(row, grid.rows - 1)))
    }

    private func update(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let current = cell(at: point) else {
            if anchor == nil { setHighlight(nil) }
            return
        }
        setHighlight(CellRect.spanning(anchor ?? current, current).clamped(to: grid))
    }

    private func setHighlight(_ rect: CellRect?) {
        guard highlight != rect else { return }
        highlight = rect
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) { update(with: event) }
    override func mouseMoved(with event: NSEvent) { update(with: event) }
    override func mouseDragged(with event: NSEvent) { update(with: event) }

    override func mouseExited(with event: NSEvent) {
        if anchor == nil { setHighlight(nil) }
    }

    override func mouseDown(with event: NSEvent) {
        guard placementEnabled else { return }
        anchor = cell(at: convert(event.locationInWindow, from: nil))
        update(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer { anchor = nil }
        guard placementEnabled, anchor != nil, let picked = highlight else { return }
        onPick?(picked)
    }
}

// MARK: - The status item

final class MenuBarController: NSObject, NSMenuDelegate {
    static let shared = MenuBarController()
    private override init() {}

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

    /// The window that was focused just before the menu took over. Read in `menuWillOpen`, i.e.
    /// before our own menu becomes frontmost, and used directly for every placement action:
    /// going through `AppController.placeFocused` would re-read the frontmost app and could well
    /// hit a different window by the time the user clicks.
    private var capturedWindow: ManagedWindow?

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.statusIcon()
        item.button?.toolTip = "Tessera"
        menu.delegate = self
        menu.autoenablesItems = false   // we decide: without this AppKit re-enables the placement
                                        // items even when Accessibility access is missing
        item.menu = menu
        statusItem = item
        rebuild()
    }

    /// Rebuilds the configuration-dependent parts. Safe before `install()`.
    func refresh() {
        guard statusItem != nil else { return }
        rebuild()
    }

    // MARK: Icon

    private static func statusIcon() -> NSImage {
        let size = NSSize(width: 16, height: 14)
        let image = NSImage(size: size)
        image.lockFocus()
        // Same glyph as drawIcon() in main.swift: one tall tile, three stacked ones.
        let gap: CGFloat = 1.5
        let area = CGRect(x: 1, y: 1, width: size.width - 2, height: size.height - 2)
        let halfW = (area.width - gap) / 2
        let thirdH = (area.height - 2 * gap) / 3
        let tiles = [
            CGRect(x: area.minX, y: area.minY, width: halfW, height: area.height),
            CGRect(x: area.minX + halfW + gap, y: area.minY + 2 * (thirdH + gap), width: halfW, height: thirdH),
            CGRect(x: area.minX + halfW + gap, y: area.minY + thirdH + gap, width: halfW, height: thirdH),
            CGRect(x: area.minX + halfW + gap, y: area.minY, width: halfW, height: thirdH),
        ]
        NSColor.black.setFill()
        for tile in tiles {
            NSBezierPath(roundedRect: tile, xRadius: 1, yRadius: 1).fill()
        }
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    // MARK: Building the menu

    func menuWillOpen(_ menu: NSMenu) {
        capturedWindow = AX.isTrusted ? AX.focusedWindow() : nil
        rebuild()
    }

    func menuDidClose(_ menu: NSMenu) {
        capturedWindow = nil
    }

    private func rebuild() {
        let config = Store.shared.config
        let trusted = AX.isTrusted
        menu.removeAllItems()

        if !trusted {
            let warning = NSMenuItem(title: "Attiva l'accesso Accessibilità…",
                                     action: #selector(openAccessibility), keyEquivalent: "")
            warning.target = self
            menu.addItem(warning)
            menu.addItem(.separator())
        }

        addGridItem(trusted: trusted)
        addZones(config.zones, trusted: trusted)
        addArrange(config.defaultStrategy, trusted: trusted)
        addLayouts(config.layouts, trusted: trusted)

        menu.addItem(.separator())
        let preferences = NSMenuItem(title: "Preferenze…", action: #selector(openPreferences),
                                     keyEquivalent: ",")
        preferences.target = self
        menu.addItem(preferences)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Esci", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
    }

    private func addGridItem(trusted: Bool) {
        let screen = NSScreen.underMouse
        let header = capturedWindow?.appName ?? "Nessuna finestra attiva"
        let view = MenuBarGridView(grid: Store.shared.config.grid(for: screen.tesseraKey),
                                   screen: screen,
                                   headerText: header,
                                   placementEnabled: trusted && capturedWindow != nil)
        view.onPick = { [weak self] cell in
            self?.place(in: cell)
            self?.menu.cancelTracking()
        }
        let item = NSMenuItem()
        item.view = view
        item.isEnabled = trusted
        menu.addItem(item)
    }

    private func addZones(_ zones: [Zone], trusted: Bool) {
        guard !zones.isEmpty else { return }
        menu.addItem(.separator())
        menu.addItem(Self.sectionHeader("Zone"))
        for (index, zone) in zones.enumerated() {
            let item = NSMenuItem(title: zone.name, action: #selector(placeInZone(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = index
            item.isEnabled = trusted
            item.attributedTitle = Self.title(zone.name,
                                              trailing: hotkeyDescription(keyCode: zone.keyCode,
                                                                          modifiers: zone.modifiers))
            menu.addItem(item)
        }
    }

    private func addArrange(_ defaultStrategy: ArrangeStrategy, trusted: Bool) {
        menu.addItem(.separator())
        menu.addItem(Self.sectionHeader("Sistema"))

        let arrange = NSMenuItem(title: "Sistema tutto", action: #selector(arrangeDefault),
                                 keyEquivalent: "")
        arrange.target = self
        arrange.isEnabled = trusted
        menu.addItem(arrange)

        let strategies = NSMenuItem(title: "Sistema tutto con…", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for strategy in ArrangeStrategy.allCases {
            let item = NSMenuItem(title: strategy.label, action: #selector(arrangeWith(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = strategy.rawValue
            item.isEnabled = trusted
            item.state = strategy == defaultStrategy ? .on : .off
            submenu.addItem(item)
        }
        strategies.submenu = submenu
        strategies.isEnabled = trusted
        menu.addItem(strategies)

        let fit = NSMenuItem(title: "Sistema la finestra attiva nel buco più grande",
                             action: #selector(fitFocused), keyEquivalent: "")
        fit.target = self
        fit.isEnabled = trusted
        menu.addItem(fit)
    }

    private func addLayouts(_ layouts: [Layout], trusted: Bool) {
        menu.addItem(.separator())
        menu.addItem(Self.sectionHeader("Disposizioni"))
        for (index, layout) in layouts.enumerated() {
            let item = NSMenuItem(title: layout.name, action: #selector(applyLayout(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = index
            item.isEnabled = trusted
            item.attributedTitle = Self.title(layout.name,
                                              trailing: hotkeyDescription(keyCode: layout.keyCode,
                                                                          modifiers: layout.modifiers))
            menu.addItem(item)
        }
        let save = NSMenuItem(title: "Salva disposizione attuale…", action: #selector(saveLayout),
                              keyEquivalent: "")
        save.target = self
        save.isEnabled = trusted
        menu.addItem(save)
    }

    private static func sectionHeader(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        return item
    }

    /// A title with the hotkey pushed to the right edge of the menu.
    private static func title(_ text: String, trailing: String) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        guard !trailing.isEmpty else {
            return NSAttributedString(string: text, attributes: [.font: font])
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 220)]
        let result = NSMutableAttributedString(string: text + "\t", attributes: [
            .font: font, .paragraphStyle: paragraph,
        ])
        result.append(NSAttributedString(string: trailing, attributes: [
            .font: font,
            .paragraphStyle: paragraph,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        return result
    }

    // MARK: Actions

    private func place(in cell: CellRect) {
        guard let window = capturedWindow else { return }
        AX.place(window, in: cell, on: AX.screen(of: window))
    }

    @objc private func placeInZone(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int,
              index < Store.shared.config.zones.count else { return }
        place(in: Store.shared.config.zones[index].cell)
    }

    @objc private func arrangeDefault() {
        AppController.shared.arrangeCurrentScreen(Store.shared.config.defaultStrategy)
    }

    @objc private func arrangeWith(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let strategy = ArrangeStrategy(rawValue: raw) else { return }
        AppController.shared.arrangeCurrentScreen(strategy)
    }

    @objc private func fitFocused() {
        guard let window = capturedWindow else { return }
        AutoArrange.fit(window)
    }

    @objc private func applyLayout(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int,
              index < Store.shared.config.layouts.count else { return }
        AppController.shared.apply(Store.shared.config.layouts[index])
    }

    @objc private func saveLayout() {
        // The snapshot has to be taken before the alert steals the front window.
        let layout = AppController.shared.captureLayout(named: "")
        let alert = NSAlert()
        alert.messageText = "Salva la disposizione attuale"
        alert.informativeText = "Dai un nome alla disposizione delle finestre di adesso."
        alert.addButton(withTitle: "Salva")
        alert.addButton(withTitle: "Annulla")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Nome"
        field.stringValue = "Disposizione \(Store.shared.config.layouts.count + 1)"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)   // the only moment this accessory app takes focus
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Store.shared.mutate { $0.layouts.append(Layout(name: name, placements: layout.placements)) }
    }

    @objc private func openPreferences() {
        PreferencesWindowController.shared.show()
    }

    @objc private func openAccessibility() {
        AX.openAccessibilitySettings()
    }
}
