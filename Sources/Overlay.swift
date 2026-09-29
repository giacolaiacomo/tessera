// Tessera — the brief highlight that confirms where a window just went.
//
// A borderless, click-through window per screen, drawing the very same rect Geometry hands to
// the Accessibility layer. It is the only on-screen chrome the app draws: there is no
// drag-to-zone overlay, which got in the way of every ordinary window move.

import AppKit

/// Never key, never main: the flash must not steal focus from the window that was just placed.
private final class OverlayPanel: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Draws one cell rect in the window's local coordinates.
private final class OverlayFlashView: NSView {
    var grid = GridSpec.default
    /// Global (Cocoa) rect the cells are laid out in; converted to local coords when drawing.
    var visibleArea = CGRect.zero
    var screenOrigin = CGPoint.zero
    var cell: CellRect?

    override func draw(_ dirtyRect: NSRect) {
        guard let cell else { return }
        // Semantic colours are resolved here, inside draw: NSAppearance.current is the view's
        // own appearance only at draw time, which is what makes this follow light and dark.
        let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
        let rect = Geometry.frame(for: cell, in: grid.clamped(), on: visibleArea)
            .offsetBy(dx: -screenOrigin.x, dy: -screenOrigin.y)
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
        accent.withAlphaComponent(0.28).setFill()
        path.fill()
        accent.setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}

final class OverlayController {
    static let shared = OverlayController()
    private init() {}

    private var panels: [String: OverlayPanel] = [:]

    /// A short, non-interactive confirmation of where a window just went.
    func flash(cell: CellRect, on screen: NSScreen) {
        let key = screen.tesseraKey
        let panel = panels[key] ?? makePanel()
        panels[key] = panel
        panel.setFrame(screen.frame, display: false)
        if let view = panel.contentView as? OverlayFlashView {
            view.grid = Store.shared.config.grid(for: key)
            view.visibleArea = screen.visibleFrame
            view.screenOrigin = screen.frame.origin
            view.cell = cell
            view.needsDisplay = true
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak panel] in
            guard let panel else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                panel.animator().alphaValue = 0
            } completionHandler: {
                panel.orderOut(nil)
            }
        }
    }

    private func makePanel() -> OverlayPanel {
        let panel = OverlayPanel(contentRect: .zero, styleMask: [.borderless],
                                 backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = OverlayFlashView(frame: .zero)
        return panel
    }
}
