// Composes the README images from the popover screenshots that scripts/render-ui.sh produces.
//
//   swift scripts/compose-docs.swift <dark dir> <light dir> <out dir>
//
// Expects icon.png, statusicon.png, popover.png, settings.png, zones.png and frames/state-N.png
// in <dark dir>, and popover.png, settings.png, zones.png in <light dir>.
// Writes hero.png, screens.png and frames/f####.png (10 fps) to <out dir>.
//
// Everything that looks like the app here IS the app: the screenshots are real renders of the
// SwiftUI popover and the mark is drawn by Sources/Logo.swift. Only the canvas around them —
// background, menu bar strip, captions, cursor — is drawn by this file.

import AppKit

let args = CommandLine.arguments
let darkDir = URL(fileURLWithPath: args[1])
let lightDir = URL(fileURLWithPath: args[2])
let out = URL(fileURLWithPath: args[3])

func rgb(_ hex: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: a)
}

// Tessera's palette, taken from the mark in Sources/Logo.swift: a deep navy plate, a teal-to-blue
// mosaic and a warm core.
let plateDark = 0x070B16, plateMid = 0x101A2E, plateHi = 0x1B2743
let teal = 0x3FDCC6, blue = 0x4A7BFF, gold = 0xFFD36B

/// Loads a snapshot and gives it its point size. The renders are @2x.
func load(_ dir: URL, _ name: String, scale: CGFloat = 2) -> NSImage {
    let img = NSImage(contentsOf: dir.appendingPathComponent(name))!
    let rep = img.representations[0]
    img.size = NSSize(width: CGFloat(rep.pixelsWide) / scale, height: CGFloat(rep.pixelsHigh) / scale)
    return img
}

/// Draws into a bitmap with a top-left origin, like a screen.
func canvas(_ w: CGFloat, _ h: CGFloat, _ name: String, scale: CGFloat = 2, _ draw: (NSRect) -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w * scale), pixelsHigh: Int(h * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: w, height: h)
    NSGraphicsContext.saveGraphicsState()
    let cg = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    cg.translateBy(x: 0, y: h)
    cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    draw(NSRect(x: 0, y: 0, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}

func drawImage(_ img: NSImage, in r: NSRect, alpha: CGFloat = 1) {
    img.draw(in: r, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
}

func attributed(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor,
                lineGap: CGFloat = 0.25, centered: Bool = false) -> NSAttributedString {
    let para = NSMutableParagraphStyle()
    para.lineSpacing = size * lineGap
    if centered { para.alignment = .center }
    return NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                      .foregroundColor: color, .paragraphStyle: para])
}

@discardableResult
func text(_ s: String, at p: NSPoint, size: CGFloat, weight: NSFont.Weight = .regular,
          color: NSColor = .white, width: CGFloat = 1000, centered: Bool = false) -> CGFloat {
    let attr = attributed(s, size: size, weight: weight, color: color, centered: centered)
    let bounds = attr.boundingRect(with: NSSize(width: width, height: 4000), options: [.usesLineFragmentOrigin])
    attr.draw(with: NSRect(x: p.x, y: p.y, width: width, height: bounds.height), options: [.usesLineFragmentOrigin])
    return bounds.height
}

func textWidth(_ s: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
    NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).size().width
}

/// A popover-like panel: rounded corners, hairline border and a soft drop shadow.
func panel(_ img: NSImage, at origin: NSPoint, scale: CGFloat = 1, dark: Bool, alpha: CGFloat = 1) {
    let r = NSRect(origin: origin, size: NSSize(width: img.size.width * scale, height: img.size.height * scale))
    let shape = NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current?.cgContext.setAlpha(alpha)
    NSGraphicsContext.current?.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
    defer { NSGraphicsContext.current?.cgContext.endTransparencyLayer(); NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow()
    sh.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.62 : 0.20)
    sh.shadowBlurRadius = 42
    sh.shadowOffset = NSSize(width: 0, height: 18)
    sh.set()
    (dark ? rgb(0x1E1E1E) : rgb(0xECECEC)).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    drawImage(img, in: r)
    NSGraphicsContext.restoreGraphicsState()
    (dark ? NSColor.white.withAlphaComponent(0.13) : NSColor.black.withAlphaComponent(0.10)).setStroke()
    shape.lineWidth = 1
    shape.stroke()
}

func darkBackground(_ r: NSRect) {
    NSGradient(colors: [rgb(plateDark), rgb(plateMid), rgb(plateHi)])!.draw(in: r, angle: -60)
    NSGradient(colors: [rgb(blue, 0.38), rgb(blue, 0)])!
        .draw(fromCenter: NSPoint(x: r.width * 0.70, y: r.height * 0.52), radius: 0,
              toCenter: NSPoint(x: r.width * 0.70, y: r.height * 0.52), radius: r.width * 0.52, options: [])
    NSGradient(colors: [rgb(teal, 0.22), rgb(teal, 0)])!
        .draw(fromCenter: NSPoint(x: r.width * 0.04, y: r.height), radius: 0,
              toCenter: NSPoint(x: r.width * 0.04, y: r.height), radius: r.width * 0.45, options: [])
    NSGradient(colors: [rgb(gold, 0.10), rgb(gold, 0)])!
        .draw(fromCenter: NSPoint(x: r.width * 0.30, y: 0), radius: 0,
              toCenter: NSPoint(x: r.width * 0.30, y: 0), radius: r.width * 0.30, options: [])
}

func symbol(_ name: String, _ size: CGFloat) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: size, weight: .medium).applying(.init(paletteColors: [.white])))
}

let icon = load(darkDir, "icon.png", scale: 1)
let statusGlyph = load(darkDir, "statusicon.png", scale: 4)   // black template, tinted below

/// The status bar glyph in white: the template PNG is black on transparent, so it is drawn into
/// a transparency layer and painted over with `.sourceAtop`.
func drawStatusGlyph(in r: NSRect) {
    guard let cg = NSGraphicsContext.current?.cgContext else { return }
    cg.beginTransparencyLayer(auxiliaryInfo: nil)
    drawImage(statusGlyph, in: r)
    cg.setBlendMode(.sourceAtop)
    NSColor.white.setFill()
    r.fill()
    cg.setBlendMode(.normal)
    cg.endTransparencyLayer()
}

/// The menu bar strip with Tessera's item in it; returns the item's rect.
@discardableResult
func menuBar(_ r: NSRect, itemRight: CGFloat) -> NSRect {
    let barH: CGFloat = 28
    NSColor.black.withAlphaComponent(0.32).setFill()
    NSRect(x: 0, y: 0, width: r.width, height: barH).fill()
    var x = r.width - 16
    let clock = "Mon 29 Sep  09:41"
    x -= textWidth(clock, size: 13.5, weight: .medium)
    text(clock, at: NSPoint(x: x, y: 5.5), size: 13.5, weight: .medium)
    for s in ["switch.2", "magnifyingglass", "battery.75percent", "wifi"] {
        guard let img = symbol(s, 14) else { continue }
        x -= img.size.width + 18
        drawImage(img, in: NSRect(x: x, y: (barH - img.size.height) / 2, width: img.size.width, height: img.size.height))
    }
    // Tessera's item: the mosaic mark, nothing else — that is all the real status item shows.
    let itemW: CGFloat = 34
    let itemRect = NSRect(x: min(x - itemW - 14, itemRight - itemW), y: 3, width: itemW, height: barH - 6)
    NSColor.white.withAlphaComponent(0.20).setFill()
    NSBezierPath(roundedRect: itemRect, xRadius: 5, yRadius: 5).fill()
    drawStatusGlyph(in: NSRect(x: itemRect.midX - 8, y: itemRect.midY - 7, width: 16, height: 14))
    return itemRect
}

/// A row of factual tags, wrapped to `maxWidth`. Returns the y it ended at.
@discardableResult
func chips(_ labels: [String], at p: NSPoint, size: CGFloat = 15, maxWidth: CGFloat) -> CGFloat {
    var x = p.x, y = p.y
    let h = size * 2.1
    for label in labels {
        let w = textWidth(label, size: size, weight: .semibold) + size * 1.75
        if x > p.x && x + w > p.x + maxWidth { x = p.x; y += h + 10 }
        let c = NSRect(x: x, y: y, width: w, height: h)
        rgb(blue, 0.20).setFill()
        NSBezierPath(roundedRect: c, xRadius: h / 2, yRadius: h / 2).fill()
        rgb(teal, 0.45).setStroke()
        NSBezierPath(roundedRect: c.insetBy(dx: 0.5, dy: 0.5), xRadius: h / 2, yRadius: h / 2).stroke()
        text(label, at: NSPoint(x: x + size * 0.875, y: y + (h - size * 1.22) / 2), size: size,
             weight: .semibold, color: rgb(0xD8E6FF))
        x += w + 10
    }
    return y + h
}

// MARK: - hero.png

let heroPopover = load(darkDir, "popover.png")
let heroScale: CGFloat = 0.88   // 601 pt of popover has to fit under a 28 pt menu bar in 640

canvas(1280, 640, "hero.png") { r in
    darkBackground(r)
    let popW = heroPopover.size.width * heroScale
    let popX = r.width - popW - 72
    let item = menuBar(r, itemRight: popX + popW / 2 + 17)
    panel(heroPopover, at: NSPoint(x: popX, y: 28 + 12), scale: heroScale, dark: true)
    // The thread from the status item down to the popover it opened.
    rgb(0xFFFFFF, 0.22).setStroke()
    let thread = NSBezierPath()
    thread.move(to: NSPoint(x: item.midX, y: item.maxY))
    thread.line(to: NSPoint(x: item.midX, y: 40))
    thread.lineWidth = 1
    thread.stroke()

    drawImage(icon, in: NSRect(x: 80, y: 88, width: 152, height: 152))
    text("Tessera", at: NSPoint(x: 96, y: 252), size: 84, weight: .heavy)
    text("Your windows, on a grid you choose.", at: NSPoint(x: 96, y: 376),
         size: 30, weight: .medium, color: NSColor.white.withAlphaComponent(0.82), width: 820)
    text("A menu bar app for macOS. A grid per screen, up to 32×32, and every window\nsnapped onto it in one click.",
         at: NSPoint(x: 96, y: 432), size: 19, weight: .regular,
         color: NSColor.white.withAlphaComponent(0.58), width: 800)
    chips(["A grid per screen · fixed or automatic", "Five arrangements", "No network, no telemetry"],
          at: NSPoint(x: 96, y: 516), maxWidth: 820)
}

// MARK: - screens.png

let shots: [(NSImage, String)] = [
    (load(lightDir, "popover.png"), "The screen map and the quick grids"),
    (load(lightDir, "settings.png"), "Settings are a page of the popover"),
    (load(lightDir, "zones.png"), "Zones, each with its own hotkey"),
]
let tallest = shots.map(\.0.size.height).max()!

canvas(1280, 56 + tallest + 84, "screens.png") { r in
    NSGradient(colors: [rgb(0xF4F8FF), rgb(0xE3ECFC)])!.draw(in: r, angle: -90)
    NSGradient(colors: [rgb(teal, 0.20), rgb(teal, 0)])!
        .draw(fromCenter: NSPoint(x: r.width * 0.22, y: r.height), radius: 0,
              toCenter: NSPoint(x: r.width * 0.22, y: r.height), radius: r.width * 0.45, options: [])
    NSGradient(colors: [rgb(blue, 0.16), rgb(blue, 0)])!
        .draw(fromCenter: NSPoint(x: r.width * 0.82, y: 0), radius: 0,
              toCenter: NSPoint(x: r.width * 0.82, y: 0), radius: r.width * 0.45, options: [])
    let gap: CGFloat = 56
    let total = shots.reduce(CGFloat(0)) { $0 + $1.0.size.width } + gap * CGFloat(shots.count - 1)
    var x = (r.width - total) / 2
    // Top-aligned, each caption under its own panel: the three pages are genuinely different
    // heights, and gluing the caption to the panel says so instead of hiding it.
    for (img, caption) in shots {
        panel(img, at: NSPoint(x: x, y: 56), dark: false)
        let attr = attributed(caption, size: 15.5, weight: .semibold, color: rgb(0x243C63), centered: true)
        attr.draw(with: NSRect(x: x - 20, y: 56 + img.size.height + 26, width: img.size.width + 40, height: 60),
                  options: [.usesLineFragmentOrigin])
        x += img.size.width + gap
    }
}

// MARK: - frames/ — picking a grid, and the windows following

let states = (0...2).map { load(darkDir, "frames/state-\($0).png") }
// Which preset chip is lit in each state: 4×1 is the fourth chip, 3×2 the fifth, Auto the first.
// GridChips lays out Auto + four presets as equal columns inside the card, so the centres are
// arithmetic: the card's inner width is 272 − 2×14 (popover padding) − 2×9 (card padding) = 226,
// five chips with 4 pt gaps → 42 pt each. Checked against the rendered PNGs.
let chipIndex = [3, 4, 0]
func chipCentre(_ index: Int) -> NSPoint { NSPoint(x: 44 + 46 * CGFloat(index), y: 83.5) }

let subtitles = [
    "4×1 — four columns across the ultrawide.",
    "3×2 — six cells, and four windows spread over them.",
    "Auto — the grid follows how many windows are open.",
]

let frameDir = out.appendingPathComponent("frames")
try? FileManager.default.createDirectory(at: frameDir, withIntermediateDirectories: true)

let W: CGFloat = 1000, H: CGFloat = 520
let cardScale: CGFloat = 1.4
let cardSize = NSSize(width: states[0].size.width * cardScale, height: states[0].size.height * cardScale)
let cardOrigin = NSPoint(x: W - cardSize.width - 60, y: 40)
func chipPoint(_ index: Int) -> NSPoint {
    let c = chipCentre(index)
    return NSPoint(x: cardOrigin.x + c.x * cardScale, y: cardOrigin.y + c.y * cardScale)
}
let idle = NSPoint(x: 470, y: 430)

var frameNo = 0

func drawFrame(cursor: NSPoint, click: CGFloat, from: Int, to: Int, mix: CGFloat) {
    canvas(W, H, String(format: "frames/f%04d.png", frameNo), scale: 1) { r in
        darkBackground(r)
        menuBar(r, itemRight: cardOrigin.x + cardSize.width / 2 + 17)
        if mix < 0.99 { panel(states[from], at: cardOrigin, scale: cardScale, dark: true, alpha: 1 - mix) }
        if mix > 0.01 { panel(states[to], at: cardOrigin, scale: cardScale, dark: true, alpha: mix) }

        drawImage(icon, in: NSRect(x: 52, y: 62, width: 92, height: 92))
        text("Pick a grid.\nThe windows follow.", at: NSPoint(x: 56, y: 178), size: 38, weight: .heavy, width: 460)
        // One line at a time: two sentences crossfading on top of each other is unreadable.
        // The old one fades out, the new one fades in.
        let line = mix < 0.5 ? from : to
        let lineAlpha = mix < 0.5 ? 1 - mix * 2 : mix * 2 - 1
        text(subtitles[line], at: NSPoint(x: 56, y: 312), size: 19, weight: .medium,
             color: NSColor.white.withAlphaComponent(0.78 * lineAlpha), width: 430)
        chips(["No network, no telemetry"], at: NSPoint(x: 56, y: H - 92), size: 14, maxWidth: 430)

        if click > 0 {
            let rad = 9 + 20 * click
            rgb(0xFFFFFF, 0.5 * (1 - click)).setFill()
            NSBezierPath(ovalIn: NSRect(x: cursor.x - rad, y: cursor.y - rad, width: rad * 2, height: rad * 2)).fill()
        }
        // The macOS arrow, drawn by hand (NSCursor's image does not render outside a running app).
        let arrow = NSBezierPath()
        for (i, (dx, dy)) in [(0.0, 0.0), (0, 17), (4, 13.2), (6.8, 19.6), (9.6, 18.4), (6.9, 12.2), (12, 12.2)].enumerated() {
            let p = NSPoint(x: cursor.x + dx * 1.25, y: cursor.y + dy * 1.25)
            i == 0 ? arrow.move(to: p) : arrow.line(to: p)
        }
        arrow.close()
        arrow.lineJoinStyle = .round
        NSGraphicsContext.saveGraphicsState()
        let sh = NSShadow()
        sh.shadowColor = NSColor.black.withAlphaComponent(0.45)
        sh.shadowBlurRadius = 3
        sh.shadowOffset = NSSize(width: 0, height: 1)
        sh.set()
        NSColor.black.setFill()
        arrow.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.setStroke()
        arrow.lineWidth = 1.6
        arrow.stroke()
    }
    frameNo += 1
}

func ease(_ t: CGFloat) -> CGFloat { t * t * (3 - 2 * t) }

func hold(_ n: Int, at cursor: NSPoint, state: Int) {
    for _ in 0..<n { drawFrame(cursor: cursor, click: 0, from: state, to: state, mix: 0) }
}
func move(from a: NSPoint, to b: NSPoint, frames n: Int, state: Int) {
    for i in 1...n {
        let t = ease(CGFloat(i) / CGFloat(n))
        drawFrame(cursor: NSPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t),
                  click: 0, from: state, to: state, mix: 0)
    }
}
/// A click on a preset chip: the ripple and the crossfade to the state it produces.
func click(at p: NSPoint, from: Int, to: Int, fade: Int, then holdFrames: Int) {
    for i in 1...fade {
        let t = CGFloat(i) / CGFloat(fade)
        drawFrame(cursor: p, click: min(1, t * 1.4), from: from, to: to, mix: ease(t))
    }
    hold(holdFrames, at: p, state: to)
}

// 10 fps. Starts on 4×1, clicks 3×2, clicks Auto, clicks back to 4×1, and returns to rest.
hold(7, at: idle, state: 0)
move(from: idle, to: chipPoint(chipIndex[1]), frames: 7, state: 0)
click(at: chipPoint(chipIndex[1]), from: 0, to: 1, fade: 4, then: 15)
move(from: chipPoint(chipIndex[1]), to: chipPoint(chipIndex[2]), frames: 6, state: 1)
click(at: chipPoint(chipIndex[2]), from: 1, to: 2, fade: 4, then: 15)
move(from: chipPoint(chipIndex[2]), to: chipPoint(chipIndex[0]), frames: 6, state: 2)
click(at: chipPoint(chipIndex[0]), from: 2, to: 0, fade: 4, then: 8)
move(from: chipPoint(chipIndex[0]), to: idle, frames: 6, state: 0)

print("✓ hero.png, screens.png and \(frameNo) frames → \(out.path)")
