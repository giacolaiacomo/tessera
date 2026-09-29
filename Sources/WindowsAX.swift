// Tessera — the Accessibility bridge: find windows, read and set their frames.
//
// This is the only file that knows about top-left AX coordinates. Everything it hands out
// or accepts is in Cocoa coordinates (bottom-left origin), like NSScreen.

import AppKit
import ApplicationServices

struct ManagedWindow {
    let element: AXUIElement
    let pid: pid_t
    let bundleID: String
    let appName: String
    let title: String

    var frame: CGRect? { AX.frame(of: element) }
}

enum AX {

    // MARK: Permission

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt once; returns the state as of right now.
    @discardableResult
    static func requestTrust() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: Coordinate conversion

    /// Height of the display whose origin is (0,0): the anchor AX measures from.
    private static var primaryHeight: CGFloat {
        (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens[0]).frame.height
    }

    static func toAX(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func fromAX(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.minY - rect.height,
               width: rect.width, height: rect.height)
    }

    // MARK: Reading

    private static func attribute<T>(_ element: AXUIElement, _ name: String, _ type: T.Type) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private static func axValue(_ element: AXUIElement, _ name: String, _ type: AXValueType) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let v = value, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(v as! AXValue, type, &point) else { return nil }
        return point
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let origin = axValue(element, kAXPositionAttribute as String, .cgPoint),
              let size = axValue(element, kAXSizeAttribute as String, .cgSize) else { return nil }
        return fromAX(CGRect(x: origin.x, y: origin.y, width: size.x, height: size.y))
    }

    static func title(of element: AXUIElement) -> String {
        attribute(element, kAXTitleAttribute as String, String.self) ?? ""
    }

    /// True for ordinary, movable document windows — skips panels, sheets and popovers.
    private static func isPlaceable(_ element: AXUIElement) -> Bool {
        let subrole = attribute(element, kAXSubroleAttribute as String, String.self)
        if let subrole, subrole != kAXStandardWindowSubrole as String { return false }
        if let minimized = attribute(element, kAXMinimizedAttribute as String, NSNumber.self),
           minimized.boolValue { return false }
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &settable)
        return settable.boolValue
    }

    private static func windows(ofApp app: NSRunningApplication) -> [ManagedWindow] {
        guard let bundleID = app.bundleIdentifier, app.activationPolicy == .regular else { return [] }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let list = attribute(appElement, kAXWindowsAttribute as String, [AXUIElement].self) else { return [] }
        return list.filter(isPlaceable).map {
            ManagedWindow(element: $0, pid: app.processIdentifier, bundleID: bundleID,
                          appName: app.localizedName ?? bundleID, title: title(of: $0))
        }
    }

    /// Every placeable window of every ordinary running app.
    static func allWindows() -> [ManagedWindow] {
        NSWorkspace.shared.runningApplications.flatMap(windows(ofApp:))
    }

    /// The focused window of the frontmost app — the target of a hotkey or a menu-bar click.
    static func focusedWindow() -> ManagedWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier
        else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let window = attribute(appElement, kAXFocusedWindowAttribute as String, AXUIElement?.self) ?? nil
        else { return nil }
        return ManagedWindow(element: window, pid: app.processIdentifier, bundleID: bundleID,
                             appName: app.localizedName ?? bundleID, title: title(of: window))
    }

    /// The window under a screen point (Cocoa coords), topmost first — what a drag is carrying.
    static func window(at point: CGPoint) -> ManagedWindow? {
        let axPoint = CGPoint(x: point.x, y: primaryHeight - point.y)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(),
                                               Float(axPoint.x), Float(axPoint.y), &element) == .success,
              var current = element else { return nil }
        // Walk up to the window that owns whatever control sits under the cursor.
        for _ in 0..<12 {
            if attribute(current, kAXRoleAttribute as String, String.self) == kAXWindowRole as String {
                var pid: pid_t = 0
                AXUIElementGetPid(current, &pid)
                let app = NSRunningApplication(processIdentifier: pid)
                return ManagedWindow(element: current, pid: pid,
                                     bundleID: app?.bundleIdentifier ?? "",
                                     appName: app?.localizedName ?? "", title: title(of: current))
            }
            guard let parent = attribute(current, kAXParentAttribute as String, AXUIElement?.self) ?? nil
            else { return nil }
            current = parent
        }
        return nil
    }

    // MARK: Writing

    /// Moves and resizes a window to a Cocoa-coordinate rect.
    ///
    /// Position, size, position — and up to three times. One pass is not enough because the two
    /// attributes fight each other: growing a window near an edge makes macOS shove it back on
    /// screen (so the position set before the size is lost), while shrinking it first can make an
    /// app clamp to its own minimum. Setting position last is what actually gets the window where
    /// it was asked to go; the extra passes converge on apps that resize in steps.
    @discardableResult
    static func setFrame(_ window: AXUIElement, to rect: CGRect) -> Bool {
        let target = toAX(rect)
        var origin = CGPoint(x: target.minX, y: target.minY)
        var size = CGSize(width: target.width, height: target.height)

        func set(_ attribute: String, _ value: AXValue?) {
            guard let value else { return }
            AXUIElementSetAttributeValue(window, attribute as CFString, value)
        }

        for _ in 0..<3 {
            set(kAXPositionAttribute as String, AXValueCreate(.cgPoint, &origin))
            set(kAXSizeAttribute as String, AXValueCreate(.cgSize, &size))
            set(kAXPositionAttribute as String, AXValueCreate(.cgPoint, &origin))
            guard let landed = frame(of: window) else { return false }
            // An app with a minimum size will never match exactly: accept the position and let
            // the size be whatever the app insists on, rather than looping forever.
            let placed = abs(landed.minX - rect.minX) < 2 && abs(landed.minY - rect.minY) < 2
            let sized = abs(landed.width - rect.width) < 2 && abs(landed.height - rect.height) < 2
            if placed && sized { return true }
            if placed && landed.width >= rect.width - 2 && landed.height >= rect.height - 2 {
                return true   // clamped to its own minimum, but in the right place
            }
        }
        return false
    }

    /// Places a window into a cell of the grid of the screen it should live on.
    @discardableResult
    static func place(_ window: ManagedWindow, in cell: CellRect, on screen: NSScreen) -> Bool {
        let grid = Store.shared.config.grid(for: screen.tesseraKey)
        return setFrame(window.element, to: Geometry.frame(for: cell, in: grid, on: screen.visibleFrame))
    }

    /// The on-screen window list: pid and frame of everything visible on the current Space,
    /// frontmost first. Only pid and bounds are read, which need no Screen Recording permission
    /// — window titles would.
    private static func onScreenEntries() -> [(pid: pid_t, bounds: CGRect)] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                              kCGNullWindowID) as? [[String: Any]] ?? []
        return info.compactMap { entry in
            guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let dict = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary)
            else { return nil }
            return (pid, bounds)
        }
    }

    /// Drops the windows that are not on the current Space, so arranging one desktop never
    /// shuffles the windows sitting on another.
    static func onCurrentSpace(_ windows: [ManagedWindow]) -> [ManagedWindow] {
        // Presence is judged per app, not per window: a window's AX frame and its CG bounds can
        // disagree by a pixel mid-animation, and dropping a real window is worse than keeping one.
        let pids = Set(onScreenEntries().map(\.pid))
        return windows.filter { pids.contains($0.pid) }
    }

    /// Windows in front-to-back order, as CoreGraphics sees them.
    ///
    /// The Accessibility API exposes no z-order, so we match each window against the on-screen
    /// window list by pid and frame.
    static func sortedFrontToBack(_ windows: [ManagedWindow]) -> [ManagedWindow] {
        // Index 0 is the frontmost window; anything we cannot match sinks to the back.
        let entries = onScreenEntries()
        func depth(of window: ManagedWindow) -> Int {
            guard let frame = window.frame else { return entries.count }
            let axFrame = toAX(frame)
            let index = entries.firstIndex {
                $0.pid == window.pid
                    && abs($0.bounds.minX - axFrame.minX) < 3 && abs($0.bounds.minY - axFrame.minY) < 3
            }
            return index ?? entries.count
        }
        return windows.map { (window: $0, depth: depth(of: $0)) }
            .sorted { $0.depth < $1.depth }
            .map(\.window)
    }

    /// The screen a window mostly sits on.
    static func screen(of window: ManagedWindow) -> NSScreen {
        guard let frame = window.frame else { return .underMouse }
        return NSScreen.screens.max { a, b in
            a.frame.intersection(frame).area < b.frame.intersection(frame).area
        } ?? .underMouse
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
