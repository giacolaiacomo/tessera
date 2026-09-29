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

    /// Every read and write below is a synchronous round trip to another app, and the default
    /// timeout is generous enough that one busy app can hold the whole arrangement — and, since
    /// this runs on the main thread, the menu bar with it — for seconds. Tessera would rather
    /// report a window it could not reach in time than stop being an app. Set on the system-wide
    /// element, this is the default for every element we touch.
    static let messagingTimeout: Void = {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.5)
    }()

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
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return focusedWindow(of: app)
    }

    /// The window this app is working in. Asked of a named app rather than of "whatever is in
    /// front", because Tessera itself is in front the moment its popover opens — and then
    /// "the front window" would be its own, which is nothing.
    static func focusedWindow(of app: NSRunningApplication) -> ManagedWindow? {
        guard let bundleID = app.bundleIdentifier else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        func wrap(_ window: AXUIElement) -> ManagedWindow {
            ManagedWindow(element: window, pid: app.processIdentifier, bundleID: bundleID,
                          appName: app.localizedName ?? bundleID, title: title(of: window))
        }
        if let window = attribute(appElement, kAXFocusedWindowAttribute as String, AXUIElement?.self) ?? nil,
           isPlaceable(window) {
            return wrap(window)
        }
        // No focused window is not the same as no window: an app can be in front with its
        // menu bar and a document window that simply does not hold focus.
        let windows = attribute(appElement, kAXWindowsAttribute as String, [AXUIElement].self) ?? []
        return windows.first(where: isPlaceable).map(wrap)
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

    /// Windows in front-to-back order, as CoreGraphics sees them. The Accessibility API exposes
    /// no z-order, so each window is matched against the on-screen list by pid and frame.
    static func sortedFrontToBack(_ windows: [ManagedWindow]) -> [ManagedWindow] {
        let entries = onScreenEntries()
        func depth(of window: ManagedWindow) -> Int {
            guard let frame = window.frame else { return entries.count }
            let axFrame = toAX(frame)
            let index = entries.firstIndex {
                $0.pid == window.pid
                    && abs($0.bounds.minX - axFrame.minX) < 3 && abs($0.bounds.minY - axFrame.minY) < 3
            }
            return index ?? entries.count   // anything unmatched sinks to the back
        }
        return windows.map { (window: $0, depth: depth(of: $0)) }
            .sorted { $0.depth < $1.depth }
            .map(\.window)
    }

    /// How a window answered. Apps with a minimum or a step size (Terminal snaps to whole
    /// character rows) cannot land exactly, and that is their business, not a failure to chase.
    enum PlacementOutcome {
        case placed
        case ownSize(CGSize)
        case didNotMove(CGRect?)

        var succeeded: Bool {
            if case .didNotMove = self { return false }
            return true
        }

        var described: String {
            switch self {
            case .placed:
                return tr("ok")
            case .ownSize(let size):
                return String(format: tr("the app insists on %d×%d"),
                              Int(size.width), Int(size.height))
            case .didNotMove(let landed):
                return tr("did not move") + (landed.map {
                    String(format: tr(", it is at %d,%d"), Int($0.minX), Int($0.minY))
                } ?? "")
            }
        }
    }

    /// Sets a window's frame: move, resize, move. No reads, no retries.
    ///
    /// The order is the whole trick. Resize first and the window grows where there is no room,
    /// so macOS pushes it back on screen and the new size is lost — which looks exactly like an
    /// app refusing to be resized. Move it to the free spot first, then it can grow into it:
    /// an AX resize keeps the top-left corner, so the move stays good.
    ///
    /// `shrinkFirst` is for a window that currently fills the screen: it ignores a resize until
    /// it leaves that state, and the caller knows that from the frame it already has.
    @discardableResult
    static func writeFrame(_ window: AXUIElement, to rect: CGRect,
                           shrinkFirst: Bool = false) -> (position: AXError, size: AXError) {
        let target = toAX(rect)
        var origin = CGPoint(x: target.minX, y: target.minY)
        var size = CGSize(width: target.width, height: target.height)

        func write(_ attribute: CFString, _ value: AXValue?) -> AXError {
            guard let value else { return .failure }
            return AXUIElementSetAttributeValue(window, attribute, value)
        }

        if shrinkFirst {
            var small = CGSize(width: min(size.width, 600), height: min(size.height, 400))
            _ = write(kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &small))
        }
        let positionError = write(kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &origin))
        let sizeError = write(kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size))
        // Nothing is read back here. An app answers a write on its own run loop, so a read taken
        // straight after returns the frame from before it — and a third write decided on that
        // stale answer cancels the resize still in flight. The caller waits, then looks.
        return (positionError, sizeError)
    }

    /// Reads where a window ended up. Touches nothing.
    static func inspect(_ window: AXUIElement, against rect: CGRect) -> PlacementOutcome {
        guard let landed = frame(of: window) else { return .didNotMove(nil) }
        let target = toAX(rect)
        let landedAX = toAX(landed)
        let corner = abs(landedAX.minX - target.minX) < 2 && abs(landedAX.minY - target.minY) < 2
        // A window that snaps to its own grid (Terminal to character rows) lands a few pixels
        // off and still fills its cell: that is placed, not an app imposing a size.
        let sized = abs(landed.width - rect.width) < 20 && abs(landed.height - rect.height) < 20
        if corner && sized { return .placed }
        // An app that keeps its own size cannot honour both corners, and macOS pushes an
        // oversized window back on screen: it counts as placed if it covers its cell.
        let overlap = landed.intersection(rect)
        let covers = !overlap.isNull && overlap.width * overlap.height > rect.width * rect.height * 0.5
        return corner || covers ? .ownSize(landed.size) : .didNotMove(landed)
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
        let grid = Store.shared.config.grid(for: screen.tesseraKey)
        let target = Geometry.frame(for: cell, in: grid, on: screen.visibleFrame)
        let current = window.frame ?? .zero
        let fillsScreen = abs(current.width - screen.visibleFrame.width) < 4
            && abs(current.height - screen.visibleFrame.height) < 4
        writeFrame(window.element, to: target, shrinkFirst: fillsScreen)
        var now = frameOnceStill(of: window.element, wasAt: current)

        // Asked again if it did not arrive, with a pause first. An app growing a window by a
        // lot stops short of the size it was given and takes the rest only when asked a second
        // time, and it will not hear that second request if it comes too soon — which is why
        // one drag, or one "Arrange all", used to need a second one to finish the job. Nothing
        // is repeated to a window that landed, or to an app already known to need more room
        // than the cell has.
        for _ in 0..<2 {
            guard let here = now, !landed(here, on: target),
                  AutoArrange.fits(window, in: target.size) else { break }
            usleep(120_000)
            writeFrame(window.element, to: target)
            now = frameOnceStill(of: window.element, wasAt: here)
        }

        keepOnScreen(window.element, hungFrom: target, within: screen.visibleFrame, settledAt: now)
        return true
    }

    /// Whether a frame is on its target, to the tolerance an app's own rounding needs — Terminal
    /// snaps to whole character rows and lands a few pixels short of any cell.
    static func landed(_ frame: CGRect, on target: CGRect) -> Bool {
        let here = toAX(frame), there = toAX(target)
        return abs(here.minX - there.minX) <= 4 && abs(here.minY - there.minY) <= 4
            && abs(here.width - there.width) <= 24 && abs(here.height - there.height) <= 24
    }

    /// Moves a window without saying anything about its size. Every correction Tessera makes
    /// after the first write is a move, never a resize: writing a size read a moment earlier is
    /// how you cancel a resize that is still in flight, and then the windows come out neatly
    /// arranged at the wrong sizes.
    @discardableResult
    static func writePosition(_ window: AXUIElement, to topLeft: CGPoint) -> AXError {
        var origin = topLeft
        guard let value = AXValueCreate(.cgPoint, &origin) else { return .failure }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    /// Two frames that are the same to the nearest pixel.
    static func same(_ a: CGRect?, _ b: CGRect?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return abs(a.minX - b.minX) < 1 && abs(a.minY - b.minY) < 1
            && abs(a.width - b.width) < 1 && abs(a.height - b.height) < 1
    }

    /// A window's frame, once it has stopped moving. An app applies a write on its own run loop,
    /// so the answer is never ready at once — but a fixed pause pays the slowest app's price on
    /// every placement, and that flat tenth of a second was most of what a drag on the map felt
    /// like. This looks instead, every 12 ms, and leaves as soon as the frame has both changed
    /// and stopped changing. A frame that never changes is the other real case — the window was
    /// already where it was asked to go — so after a short grace that counts as an answer too.
    static func frameOnceStill(of window: AXUIElement, wasAt before: CGRect?) -> CGRect? {
        var previous = before
        var polls = 0
        var quiet = 0
        let giveUp = DispatchTime.now().uptimeNanoseconds + 400_000_000
        while DispatchTime.now().uptimeNanoseconds < giveUp {
            usleep(20_000)
            polls += 1
            let now = frame(of: window)
            // Three quiet reads, not one: an app like Chrome animates its resize, and two reads
            // can fall in the same lull and be mistaken for a window that has finished moving.
            quiet = same(now, previous) ? quiet + 1 : 0
            previous = now
            if quiet >= 3 && (!same(now, before) || polls >= 5) { return now }
        }
        return previous
    }

    /// An app with a minimum size larger than the cell keeps its size — its right — but hung
    /// from the cell's top-left corner it then sticks out past the edge of the screen, which is
    /// no use to anybody. Same size, same corner, slid back inside.
    static func keepOnScreen(_ window: AXUIElement, hungFrom target: CGRect,
                             within visible: CGRect, settledAt now: CGRect?) {
        guard let now else { return }
        guard now.minX < visible.minX - 1 || now.minY < visible.minY - 1
                || now.maxX > visible.maxX + 1 || now.maxY > visible.maxY + 1 else { return }
        var rect = CGRect(x: target.minX, y: target.maxY - now.height,
                          width: now.width, height: now.height)
        rect.origin.x = min(max(rect.minX, visible.minX), max(visible.minX, visible.maxX - rect.width))
        rect.origin.y = min(max(rect.minY, visible.minY), max(visible.minY, visible.maxY - rect.height))
        writePosition(window, to: toAX(rect).origin)
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
