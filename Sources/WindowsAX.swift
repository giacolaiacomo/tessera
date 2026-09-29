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

    /// True for ordinary, movable document windows — skips panels, sheets and popovers, and
    /// leaves full-screen windows alone: they own a Space, and dragging one out of it to make
    /// it a tile is never what someone meant.
    private static func isPlaceable(_ element: AXUIElement) -> Bool {
        let subrole = attribute(element, kAXSubroleAttribute as String, String.self)
        if let subrole, subrole != kAXStandardWindowSubrole as String { return false }
        if let minimized = attribute(element, kAXMinimizedAttribute as String, NSNumber.self),
           minimized.boolValue { return false }
        if let fullScreen = attribute(element, "AXFullScreen", NSNumber.self), fullScreen.boolValue {
            return false
        }
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
        if case .placed = place(window, at: rect) { return true }
        return false
    }

    /// Why a window did not end up exactly where it was asked to go. Kept in the open because
    /// "it moved but did not resize" is the failure people actually hit, and a silent Bool made
    /// it impossible to tell an app's minimum size from a refused request.
    enum PlacementOutcome {
        case placed
        /// In the right place, but the app chose its own size: a minimum, a fixed size, or a
        /// step (Terminal snaps to whole character rows).
        case resizedByApp(CGSize)
        case refused(position: AXError, size: AXError, landed: CGRect?, why: String)

        var succeeded: Bool {
            if case .refused = self { return false }
            return true
        }

        var describedInItalian: String {
            switch self {
            case .placed: return "ok"
            case .resizedByApp(let size):
                return "in posizione, ma l'app impone \(Int(size.width))×\(Int(size.height))"
            case .refused(let position, let size, let landed, let why):
                return "rifiutata (posizione \(position.rawValue), dimensione \(size.rawValue))"
                    + (landed.map { ", è rimasta \(Int($0.origin.x)),\(Int($0.origin.y)) \(Int($0.width))×\(Int($0.height))" } ?? "")
                    + " — \(why)"
            }
        }
    }

    static func place(_ window: AXUIElement, at rect: CGRect) -> PlacementOutcome {
        let target = toAX(rect)
        var origin = CGPoint(x: target.minX, y: target.minY)
        var size = CGSize(width: target.width, height: target.height)
        var positionError = AXError.success
        var sizeError = AXError.success

        func set(_ attribute: String, _ value: AXValue?) -> AXError {
            guard let value else { return .failure }
            return AXUIElementSetAttributeValue(window, attribute as CFString, value)
        }

        for pass in 0..<3 {
            positionError = set(kAXPositionAttribute as String, AXValueCreate(.cgPoint, &origin))
            sizeError = set(kAXSizeAttribute as String, AXValueCreate(.cgSize, &size))
            _ = set(kAXPositionAttribute as String, AXValueCreate(.cgPoint, &origin))
            // Electron and Catalyst windows apply a resize asynchronously: reading the frame
            // straight away reports the old one and makes a good placement look refused.
            if pass > 0 { usleep(120_000) }
            guard let landed = frame(of: window) else { break }
            // Compare the top-left corner in AX coordinates — the very thing that was set.
            // Checking the Cocoa origin instead would call a correct placement a failure
            // whenever the app picked its own height, since that origin is derived from it.
            let landedAX = toAX(landed)
            let placed = abs(landedAX.minX - target.minX) < 2 && abs(landedAX.minY - target.minY) < 2
            let sized = abs(landed.width - rect.width) < 2 && abs(landed.height - rect.height) < 2
            if placed && sized { return .placed }
            // An app that imposes its own size cannot honour both corners: accept either one.
            // iPhone Mirroring, for instance, grows upwards from the bottom-left it was given.
            var anchored = placed
                || (abs(landed.minX - rect.minX) < 2 && abs(landed.minY - rect.minY) < 2)
            // An app whose minimum size is bigger than the cell cannot sit in it, and macOS
            // shoves it back on screen so neither corner lines up. If it still covers the cell
            // it was sent to, it went where it was told — it just does not fit.
            if !anchored, landed.width > rect.width || landed.height > rect.height {
                let overlap = landed.intersection(rect)
                anchored = !overlap.isNull
                    && overlap.width * overlap.height > rect.width * rect.height * 0.5
            }
            // Give an app that is mid-animation one more pass before calling it a refusal.
            if anchored && pass > 0 { return .resizedByApp(landed.size) }
            // A maximised window accepts a position and quietly ignores a size. Shaking it to a
            // small size first breaks that state without touching the zoom button, which on
            // Electron and Catalyst apps means "full screen" and would make things worse.
            if !sized, let screen = NSScreen.screens.first(where: { $0.frame.intersects(landed) }),
               abs(landed.width - screen.visibleFrame.width) < 4,
               abs(landed.height - screen.visibleFrame.height) < 4 {
                var nudge = CGSize(width: 400, height: 300)
                _ = set(kAXSizeAttribute as String, AXValueCreate(.cgSize, &nudge))
                usleep(120_000)
            }
        }
        return .refused(position: positionError, size: sizeError, landed: frame(of: window),
                        why: describeResistance(window))
    }

    /// The handful of window properties that explain a refusal: whether the attributes are
    /// settable at all, whether the window is full screen, and whether it has a zoom button.
    private static func describeResistance(_ window: AXUIElement) -> String {
        var sizeSettable: DarwinBoolean = false
        var positionSettable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &sizeSettable)
        AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &positionSettable)
        let full = attribute(window, "AXFullScreen", NSNumber.self)?.boolValue
        var zoom: CFTypeRef?
        let hasZoom = AXUIElementCopyAttributeValue(window, kAXZoomButtonAttribute as CFString,
                                                    &zoom) == .success
        let subrole = attribute(window, kAXSubroleAttribute as String, String.self) ?? "?"
        return "size settabile \(sizeSettable.boolValue), position settabile \(positionSettable.boolValue)"
            + ", AXFullScreen \(full.map(String.init) ?? "assente"), zoom button \(hasZoom)"
            + ", subrole \(subrole)"
    }

    /// Windows that are in full screen, which `allWindows()` deliberately leaves out.
    static func fullScreenWindows() -> [ManagedWindow] {
        NSWorkspace.shared.runningApplications.flatMap { app -> [ManagedWindow] in
            guard let bundleID = app.bundleIdentifier, app.activationPolicy == .regular else { return [] }
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            guard let list = attribute(appElement, kAXWindowsAttribute as String, [AXUIElement].self)
            else { return [] }
            return list.filter {
                attribute($0, "AXFullScreen", NSNumber.self)?.boolValue == true
            }.map {
                ManagedWindow(element: $0, pid: app.processIdentifier, bundleID: bundleID,
                              appName: app.localizedName ?? bundleID, title: title(of: $0))
            }
        }
    }

    /// Brings a window back from full screen to an ordinary window on this Space.
    ///
    /// Note what this does NOT do: press the zoom button. On Electron and Catalyst apps that
    /// button means "full screen", so pressing it to un-maximise a window does the exact
    /// opposite — it swallows the window into a Space of its own.
    @discardableResult
    static func exitFullScreen(_ window: ManagedWindow) -> Bool {
        guard attribute(window.element, "AXFullScreen", NSNumber.self)?.boolValue == true
        else { return false }
        AXUIElementSetAttributeValue(window.element, "AXFullScreen" as CFString, kCFBooleanFalse)
        usleep(700_000)   // the Space animation takes about half a second
        return attribute(window.element, "AXFullScreen", NSNumber.self)?.boolValue == false
    }

    /// Places a window into a cell of the grid of the screen it should live on.
    @discardableResult
    static func place(_ window: ManagedWindow, in cell: CellRect, on screen: NSScreen) -> Bool {
        outcome(placing: window, in: cell, on: screen).succeeded
    }

    static func outcome(placing window: ManagedWindow, in cell: CellRect,
                        on screen: NSScreen) -> PlacementOutcome {
        let grid = Store.shared.config.grid(for: screen.tesseraKey)
        return place(window.element, at: Geometry.frame(for: cell, in: grid, on: screen.visibleFrame))
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
