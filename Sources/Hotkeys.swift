// Tessera — global hotkeys (Carbon), the recorder view used by Preferences, and the watcher
// that fits brand-new windows into the grid.

import AppKit
import Carbon.HIToolbox
import SwiftUI

// MARK: - Registration

final class HotkeyManager {
    static let shared = HotkeyManager()
    private init() {}

    private var actions: [UInt32: () -> Void] = [:]
    private var registered: [EventHotKeyRef] = []
    private var nextID: UInt32 = 1
    private var handler: EventHandlerRef?

    /// Drops every registration and rebuilds it from the config. Safe to call on every change.
    func reload() {
        unregisterAll()
        installHandlerIfNeeded()
        for zone in Store.shared.config.zones {
            let cell = zone.cell
            register(keyCode: zone.keyCode, modifiers: zone.modifiers, label: zone.name) {
                AppController.shared.placeFocused(in: cell)
            }
        }
        for layout in Store.shared.config.layouts {
            register(keyCode: layout.keyCode, modifiers: layout.modifiers, label: layout.name) {
                AppController.shared.apply(layout)
            }
        }
    }

    private func unregisterAll() {
        for hotkey in registered { UnregisterEventHotKey(hotkey) }
        registered.removeAll()
        actions.removeAll()
        nextID = 1
    }

    private func register(keyCode: UInt32?, modifiers: UInt32?, label: String,
                          action: @escaping () -> Void) {
        guard let keyCode, let modifiers, modifiers != 0 else { return }
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x74_65_73_73), id: id)   // 'tess'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("Tessera: hotkey %@ per «%@» non registrata (status %d)",
                  hotkeyDescription(keyCode: keyCode, modifiers: modifiers), label, Int(status))
            return
        }
        registered.append(ref)
        actions[id] = action
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        // The Carbon callback is a C function pointer, so it carries no Swift context: it must
        // route back through the singleton instead of a captured self.
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return OSStatus(eventNotHandledErr) }
            HotkeyManager.shared.fire(id: hotKeyID.id)
            return noErr
        }, 1, &spec, nil, &handler)
    }

    private func fire(id: UInt32) {
        guard let action = actions[id] else { return }
        if Thread.isMainThread { action() } else { DispatchQueue.main.async(execute: action) }
    }
}

// MARK: - Human-readable shortcuts

/// "⌃⌥1" for a key code plus Carbon modifier mask; empty when nothing is assigned.
func hotkeyDescription(keyCode: UInt32?, modifiers: UInt32?) -> String {
    guard let keyCode, let modifiers else { return "" }
    var text = ""
    if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
    if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
    if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
    if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
    return text + HotkeyKeyNames.name(for: keyCode)
}

private enum HotkeyKeyNames {
    private static let table: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
        34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0",
        24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\", 43: ",", 44: "/", 47: ".",
        50: "`",
        36: "↩", 48: "⇥", 49: "Spazio", 51: "⌫", 53: "⎋", 76: "⌤", 117: "⌦",
        115: "↖", 116: "⇞", 119: "↘", 121: "⇟", 114: "?⃝",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    static func name(for keyCode: UInt32) -> String {
        table[keyCode] ?? "#\(keyCode)"
    }
}

// MARK: - Recorder

/// A click-to-arm field that captures the next combination pressed. Esc cancels, ⌫ clears.
struct HotkeyRecorder: NSViewRepresentable {
    @Binding var keyCode: UInt32?
    @Binding var modifiers: UInt32?

    func makeNSView(context: Context) -> HotkeyRecorderView {
        HotkeyRecorderView()
    }

    func updateNSView(_ view: HotkeyRecorderView, context: Context) {
        // Re-bind on every update: the closure made at creation time would keep writing through
        // the bindings of a struct value that SwiftUI has long since replaced.
        view.onCapture = { code, mask in
            keyCode = code
            modifiers = mask
        }
        view.title = hotkeyDescription(keyCode: keyCode, modifiers: modifiers)
        view.needsDisplay = true
    }
}

/// The AppKit side of `HotkeyRecorder`; public only because NSViewRepresentable needs the type.
final class HotkeyRecorderView: NSView {
    var onCapture: ((UInt32?, UInt32?) -> Void)?
    var title = ""
    private var armed = false {
        didSet { needsDisplay = true }
    }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 120, height: 24) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        armed = true
    }

    override func resignFirstResponder() -> Bool {
        armed = false
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // While armed we must win over menu shortcuts, otherwise ⌘-combinations never arrive.
        guard armed else { return false }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard armed else {
            super.keyDown(with: event)
            return
        }
        switch Int(event.keyCode) {
        case kVK_Escape:
            armed = false
        case kVK_Delete, kVK_ForwardDelete:
            armed = false
            onCapture?(nil, nil)
        default:
            let mask = HotkeyRecorderView.carbonModifiers(event.modifierFlags)
            guard mask != 0 else { return }   // a bare key would hijack typing everywhere
            armed = false
            onCapture?(UInt32(event.keyCode), mask)
        }
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        return mask
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        (armed ? NSColor.controlAccentColor.withAlphaComponent(0.15)
               : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (armed ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = armed ? 2 : 1
        path.stroke()

        let text: String
        if armed {
            text = "Premi una combinazione…"
        } else {
            text = title.isEmpty ? "Nessuna scorciatoia" : title
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: title.isEmpty ? .regular : .medium),
            .foregroundColor: title.isEmpty && !armed ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: CGPoint(x: rect.midX - size.width / 2,
                                            y: rect.midY - size.height / 2),
                                withAttributes: attributes)
    }
}

// MARK: - New windows

/// Polls the window list and auto-fits anything that just appeared.
///
/// Polling beats one AXObserver per application: no per-app registration to keep in sync when
/// apps launch and quit, and nothing to leak when one of them misbehaves.
final class NewWindowWatcher {
    static let shared = NewWindowWatcher()
    private init() {}

    private var timer: Timer?
    private var seen: Set<HotkeyElementKey> = []
    private var primed = false

    func setEnabled(_ on: Bool) {
        timer?.invalidate()
        timer = nil
        seen.removeAll()
        primed = false
        guard on else { return }
        let timer = Timer(timeInterval: 1.2, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(timer, forMode: .common)   // keep firing during menu and drag tracking
        self.timer = timer
        sample()
    }

    private func sample() {
        guard AX.isTrusted else { return }
        let windows = AX.allWindows().filter { $0.bundleID != bundleID }
        var current: Set<HotkeyElementKey> = []
        var fresh: [ManagedWindow] = []
        for window in windows {
            let key = HotkeyElementKey(window.element)
            current.insert(key)
            if !seen.contains(key) { fresh.append(window) }
        }
        seen = current
        guard primed else {
            primed = true       // the first pass is just the windows that were already open
            return
        }
        for window in fresh { AutoArrange.fit(window) }
    }
}

/// Identity of an AXUIElement, so a window can be recognised across samples.
private struct HotkeyElementKey: Hashable {
    private let element: AXUIElement

    init(_ element: AXUIElement) { self.element = element }

    static func == (lhs: HotkeyElementKey, rhs: HotkeyElementKey) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }
}
