// Renders the popover and the settings window off-screen, so the layout can be inspected
// without launching the app.
import AppKit
import SwiftUI

// Stand-in for the one in main.swift, which cannot be compiled twice (top-level code).
final class AppController {
    static let shared = AppController()
    @discardableResult func placeFocused(in cell: CellRect) -> Bool { false }
    @discardableResult func fitFocused() -> Bool { false }
    @discardableResult func arrangeCurrentScreen(_ strategy: ArrangeStrategy) -> Int { 0 }
    @discardableResult func apply(_ layout: Layout) -> Int { 0 }
    func captureLayout(named name: String) -> Layout { Layout(name: name, placements: []) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

func snapshot<V: View>(_ view: V, named name: String) {
    let host = NSHostingView(rootView: view)
    host.frame = CGRect(origin: .zero, size: host.fittingSize)
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
    host.cacheDisplay(in: host.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: name))
    print("\(name): \(Int(host.frame.width))×\(Int(host.frame.height)) pt")
}

let popoverModel = PopoverModel()
popoverModel.reload(window: nil)
snapshot(TesseraPopover(model: popoverModel), named: CommandLine.arguments[1] + "/popover.png")
snapshot(PrefsRootView(model: PrefsModel()), named: CommandLine.arguments[1] + "/prefs.png")
