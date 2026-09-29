// Tessera — the on-screen grid overlay and the drag-to-zone gesture.
//
// The overlay is a borderless, click-through window per screen that draws the very same
// rects Geometry hands to the Accessibility layer, so what the user sees while dragging is
// pixel-identical to where the window lands.

import AppKit

// MARK: - Window and view

/// Never key, never main: the overlay must not steal focus from the window being dragged.
private final class OverlayPanel: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Draws one screen's grid in the window's local coordinates.
private final class OverlayGridView: NSView {
    var grid = GridSpec.default
    /// Global (Cocoa) rect the cells are laid out in; converted to local coords when drawing.
    var visibleArea = CGRect.zero
    var screenOrigin = CGPoint.zero
    var selection: CellRect?
    /// False for the short flash after a placement: only the chosen cell is painted.
    var drawsAllCells = true

    private func local(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -screenOrigin.x, dy: -screenOrigin.y)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Resolving the semantic colours here, inside draw, is what makes the overlay follow
        // light/dark: NSAppearance.current is the view's own appearance only at draw time.
        let spec = grid.clamped()
        if drawsAllCells {
            let fill = resolved(.windowBackgroundColor, alpha: 0.30)
            let stroke = resolved(.separatorColor, alpha: 0.85)
            for row in 0..<spec.rows {
                for col in 0..<spec.cols {
                    let rect = local(Geometry.frame(for: CellRect(col: col, row: row),
                                                    in: spec, on: visibleArea))
                    guard rect.intersects(dirtyRect) else { continue }
                    let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                            xRadius: 5, yRadius: 5)
                    fill.setFill()
                    path.fill()
                    stroke.setStroke()
                    path.lineWidth = 1
                    path.stroke()
                }
            }
        }

        guard let selection else { return }
        let accent = resolved(.controlAccentColor, alpha: 1)
        let rect = local(Geometry.frame(for: selection, in: spec, on: visibleArea))
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
        accent.withAlphaComponent(0.35).setFill()
        path.fill()
        accent.setStroke()
        path.lineWidth = 2
        path.stroke()
        drawLabel(for: selection, in: rect, accent: accent)
    }

    private func resolved(_ color: NSColor, alpha: CGFloat) -> NSColor {
        let rgb = color.usingColorSpace(.sRGB) ?? NSColor.gray
        return alpha < 1 ? rgb.withAlphaComponent(alpha) : rgb
    }

    private func drawLabel(for cell: CellRect, in rect: CGRect, accent: NSColor) {
        let zoneName = Store.shared.config.zones.first { $0.cell == cell }?.name
        let text = zoneName ?? "\(cell.w)×\(cell.h)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let padding = CGSize(width: 10, height: 5)
        let pill = CGRect(x: rect.midX - size.width / 2 - padding.width,
                          y: rect.midY - size.height / 2 - padding.height,
                          width: size.width + 2 * padding.width,
                          height: size.height + 2 * padding.height)
        guard pill.width <= rect.width, pill.height <= rect.height else { return }
        accent.withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        (text as NSString).draw(at: CGPoint(x: pill.minX + padding.width,
                                            y: pill.minY + padding.height),
                                withAttributes: attributes)
    }
}

// MARK: - Controller

final class OverlayController {
    static let shared = OverlayController()
    private init() {}

    private var gridPanels: [String: OverlayPanel] = [:]
    private var flashPanels: [String: OverlayPanel] = [:]
    private var visibleKey: String?

    // MARK: Flash

    /// A short, non-interactive confirmation of where a window just went.
    func flash(cell: CellRect, on screen: NSScreen) {
        let key = screen.tesseraKey
        let panel = flashPanels[key] ?? makePanel(drawsAllCells: false)
        flashPanels[key] = panel
        configure(panel, for: screen, selection: cell)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak panel] in
            guard let panel else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().alphaValue = 0
            } completionHandler: {
                panel.orderOut(nil)
            }
        }
    }

    // MARK: Grid

    func showGrid(on screen: NSScreen) {
        let key = screen.tesseraKey
        if let visibleKey, visibleKey != key { gridPanels[visibleKey]?.orderOut(nil) }
        let panel = gridPanels[key] ?? makePanel(drawsAllCells: true)
        gridPanels[key] = panel
        let previous = (panel.contentView as? OverlayGridView)?.selection
        configure(panel, for: screen, selection: previous)
        panel.orderFrontRegardless()
        visibleKey = key
    }

    func hideGrid() {
        for panel in gridPanels.values { panel.orderOut(nil) }
        for panel in gridPanels.values { (panel.contentView as? OverlayGridView)?.selection = nil }
        visibleKey = nil
    }

    func highlight(_ cell: CellRect?) {
        guard let visibleKey, let view = gridPanels[visibleKey]?.contentView as? OverlayGridView,
              view.selection != cell else { return }
        view.selection = cell
        view.needsDisplay = true
    }

    // MARK: Plumbing

    private func makePanel(drawsAllCells: Bool) -> OverlayPanel {
        let panel = OverlayPanel(contentRect: .zero, styleMask: [.borderless],
                                 backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let view = OverlayGridView(frame: .zero)
        view.drawsAllCells = drawsAllCells
        panel.contentView = view
        return panel
    }

    private func configure(_ panel: OverlayPanel, for screen: NSScreen, selection: CellRect?) {
        panel.setFrame(screen.frame, display: false)
        guard let view = panel.contentView as? OverlayGridView else { return }
        view.grid = Store.shared.config.grid(for: screen.tesseraKey)
        view.visibleArea = screen.visibleFrame
        view.screenOrigin = screen.frame.origin
        view.selection = selection
        view.needsDisplay = true
    }
}

// MARK: - Drag to zone

/// Watches a window drag and turns the release point into a grid placement.
final class DragWatcher {
    static let shared = DragWatcher()
    private init() {}

    private var monitors: [Any] = []
    private var enabled = false

    private var window: ManagedWindow?
    private var lookedForWindow = false     // one hit test per gesture, not one per drag event
    private var startedInTitleBar = false
    private var lastWindowFrame: CGRect?
    private var confirmed = false           // the pointer really is dragging a window
    private var overlayVisible = false
    private var screenKey: String?
    private var anchor: (col: Int, row: Int)?
    private var selection: CellRect?

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        if on {
            let mask: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp, .flagsChanged]
            if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
                self?.handle(event)
            }) {
                monitors.append(global)
            }
            // Global monitors go quiet while Tessera itself is frontmost.
            if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
                self?.handle(event)
                return event
            }) {
                monitors.append(local)
            }
        } else {
            monitors.forEach(NSEvent.removeMonitor)
            monitors.removeAll()
            reset()
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDragged: dragged()
        case .leftMouseUp: released()
        case .flagsChanged: if confirmed { updateOverlay() }
        default: break
        }
    }

    private func dragged() {
        if window == nil && !lookedForWindow { begin() }
        guard window != nil else { return }
        if !confirmed { confirmIfMoved() }
        if confirmed { updateOverlay() }
    }

    private func begin() {
        lookedForWindow = true
        let point = NSEvent.mouseLocation
        guard let candidate = AX.window(at: point), candidate.bundleID != bundleID else { return }
        window = candidate
        lastWindowFrame = candidate.frame
        if let frame = candidate.frame {
            let titleBar = CGRect(x: frame.minX, y: frame.maxY - 28, width: frame.width, height: 28)
            startedInTitleBar = titleBar.contains(point)
        }
        confirmed = startedInTitleBar
    }

    /// Fallback for drags that start outside the title bar (tab bars, unified toolbars): if the
    /// window frame actually changed between two samples, it is being dragged.
    private func confirmIfMoved() {
        guard let window, let now = window.frame else { return }
        if let before = lastWindowFrame, before.origin != now.origin { confirmed = true }
        lastWindowFrame = now
    }

    private func updateOverlay() {
        guard !Store.shared.config.overlayModifierOnly
                || NSEvent.modifierFlags.contains(.option) else {
            hideOverlay()
            return
        }
        let screen = NSScreen.underMouse
        if screenKey != screen.tesseraKey {
            screenKey = screen.tesseraKey
            anchor = nil                       // a new screen means a new gesture
            selection = nil
        }
        if !overlayVisible {
            OverlayController.shared.showGrid(on: screen)
            overlayVisible = true
        }
        let grid = Store.shared.config.grid(for: screen.tesseraKey)
        guard let cell = Geometry.cell(at: NSEvent.mouseLocation, in: grid,
                                       on: screen.visibleFrame) else {
            selection = nil
            OverlayController.shared.highlight(nil)
            return
        }
        let start = anchor ?? cell
        anchor = start
        let rect = CellRect.spanning(start, cell).clamped(to: grid)
        selection = rect
        OverlayController.shared.highlight(rect)
    }

    private func hideOverlay() {
        guard overlayVisible else { return }
        OverlayController.shared.hideGrid()
        overlayVisible = false
        anchor = nil
        selection = nil
    }

    private func released() {
        defer { reset() }
        guard overlayVisible, let window, let selection,
              let key = screenKey, let screen = NSScreen.screen(forKey: key) else { return }
        OverlayController.shared.hideGrid()
        overlayVisible = false
        AX.place(window, in: selection, on: screen)
    }

    private func reset() {
        if overlayVisible {
            OverlayController.shared.hideGrid()
            overlayVisible = false
        }
        window = nil
        lookedForWindow = false
        lastWindowFrame = nil
        startedInTitleBar = false
        confirmed = false
        screenKey = nil
        anchor = nil
        selection = nil
    }
}
