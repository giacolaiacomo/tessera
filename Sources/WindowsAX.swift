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
    /// Order matters and one pass is not enough: an app that refuses a size until it has moved
    /// (or clamps to its own minimum) lands somewhere else, so we set size, then position, then
    /// re-apply whichever the app didn't honour.
    @discardableResult
    static func setFrame(_ window: AXUIElement, to rect: CGRect) -> Bool {
        let target = toAX(rect)
        for pass in 0..<2 {
            var size = CGSize(width: target.width, height: target.height)
            var origin = CGPoint(x: target.minX, y: target.minY)
            if pass == 0, let sizeValue = AXValueCreate(.cgSize, &size) {
                AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
            }
            if let originValue = AXValueCreate(.cgPoint, &origin) {
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, originValue)
            }
            if let sizeValue = AXValueCreate(.cgSize, &size) {
                AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
            }
            if let landed = frame(of: window),
               abs(landed.width - rect.width) < 2, abs(landed.height - rect.height) < 2,
               abs(landed.minX - rect.minX) < 2, abs(landed.minY - rect.minY) < 2 {
                return true
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
