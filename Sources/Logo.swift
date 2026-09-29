import AppKit

/// Tessera's mark: five mosaic tesserae of different sizes pinwheeling around a small core,
/// together filling a square exactly — a grid that is deliberately not uniform.
/// `assets/logo.svg` and `assets/menubar.svg` are the design masters; this file redraws them
/// in code because the app ships as a single binary with no resources.
enum Logo {

    /// Full-colour app icon at any size, for the .icns generated at build time.
    static func appIcon(size: CGFloat) -> NSImage {
        let px = max(1, Int(size.rounded()))
        let image = NSImage(size: NSSize(width: size, height: size))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return image }
        rep.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        drawAppIcon(side: size)
        NSGraphicsContext.restoreGraphicsState()
        image.addRepresentation(rep)
        return image
    }

    /// Monochrome template image for the status bar (about 16×14 pt).
    static func statusItemIcon() -> NSImage {
        let box = NSSize(width: 16, height: 14)
        // Drawn through a handler so AppKit re-rasterises it at whatever backing scale the bar uses.
        let image = NSImage(size: box, flipped: false) { _ in
            let side: CGFloat = 14   // full bar height; 1 pt of air left and right
            let scale = max(1, NSGraphicsContext.current?.cgContext.ctm.a ?? 1)
            let origin = NSPoint(x: (((box.width - side) / 2) * scale).rounded(.down) / scale,
                                 y: (((box.height - side) / 2) * scale).rounded(.down) / scale)
            NSColor.black.setFill()
            mosaic(origin: origin, side: side, inset: 3.5, radius: 3.5, snap: scale).fill()
            return true
        }
        image.isTemplate = true   // lets macOS invert it for light/dark menu bars
        return image
    }

    // MARK: Geometry

    /// The five tesserae on a 100×100 grid, bottom-left origin. They tile the square with no leftover:
    /// 60×40, 40×68, 68×32, 32×60 around a 28×28 core.
    private static let cells: [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)] = [
        (0, 60, 60, 40),    // top
        (60, 32, 40, 68),   // right
        (32, 0, 68, 32),    // bottom
        (0, 0, 32, 60),     // left
    ]
    private static let core: (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) = (32, 32, 28, 28)

    /// `inset` is the grout half-gap and `radius` the tile corner, both in grid units.
    /// `snap` is the device pixels per point (0 = off): edges land on the pixel grid so the grout
    /// stays crisp. `inward` shrinks each tessera to the grid instead of rounding to the nearest
    /// pixel, which is what keeps the gaps from closing at 1× in the menu bar.
    private static func tile(_ c: (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat),
                             origin: NSPoint, side: CGFloat, inset: CGFloat, radius: CGFloat,
                             snap: CGFloat = 0, inward: Bool = false) -> NSBezierPath {
        let u = side / 100
        var r = NSRect(x: origin.x + (c.x + inset) * u, y: origin.y + (c.y + inset) * u,
                       width: (c.w - 2 * inset) * u, height: (c.h - 2 * inset) * u)
        if snap > 0 {
            func grid(_ v: CGFloat, _ round: (CGFloat) -> CGFloat) -> CGFloat { round(v * snap) / snap }
            let x0 = grid(r.minX, inward ? ceil : { $0.rounded() }), y0 = grid(r.minY, inward ? ceil : { $0.rounded() })
            let x1 = grid(r.maxX, inward ? floor : { $0.rounded() }), y1 = grid(r.maxY, inward ? floor : { $0.rounded() })
            r = NSRect(x: x0, y: y0, width: max(1 / snap, x1 - x0), height: max(1 / snap, y1 - y0))
        }
        let rad = min(radius * u, min(r.width, r.height) / 2)
        return NSBezierPath(roundedRect: r, xRadius: rad, yRadius: rad)
    }

    /// All five tesserae as one path, for the flat monochrome cut.
    private static func mosaic(origin: NSPoint, side: CGFloat, inset: CGFloat, radius: CGFloat, snap: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        for c in cells + [core] {
            path.append(tile(c, origin: origin, side: side, inset: inset, radius: radius, snap: snap, inward: true))
        }
        return path
    }

    /// Apple-style rounded tile: a true superellipse, not a circular-cornered rect.
    private static func superellipse(center: NSPoint, radius: CGFloat, n: CGFloat = 5, steps: Int = 192) -> NSBezierPath {
        let path = NSBezierPath()
        for i in 0..<steps {
            let t = 2 * CGFloat.pi * CGFloat(i) / CGFloat(steps)
            let c = cos(t), s = sin(t)
            let p = NSPoint(x: center.x + radius * copysign(pow(abs(c), 2 / n), c),
                            y: center.y + radius * copysign(pow(abs(s), 2 / n), s))
            if i == 0 { path.move(to: p) } else { path.line(to: p) }
        }
        path.close()
        return path
    }

    // MARK: Colour

    private static func rgb(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: alpha)
    }

    private static func drawAppIcon(side s: CGFloat) {
        let tileSide = s * 0.80                       // Apple icon grid: the art sits inside an 80 % tile
        let center = NSPoint(x: s / 2, y: s / 2)
        let plate = superellipse(center: center, radius: tileSide / 2)
        NSGradient(starting: rgb(0x1B2743), ending: rgb(0x0A1020))?.draw(in: plate, angle: -90)

        NSGraphicsContext.saveGraphicsState()
        plate.addClip()
        NSGradient(colors: [rgb(0x4A7BFF, 0.30), rgb(0x4A7BFF, 0)])?
            .draw(fromCenter: center, radius: 0, toCenter: center, radius: tileSide * 0.62, options: [])
        NSGraphicsContext.restoreGraphicsState()

        // Small-size cut: below 128 px the mark grows and the grout opens, or the tesserae merge.
        let t = min(max((s - 32) / 96, 0), 1)
        let markSide = s * (0.66 + (0.58 - 0.66) * t)
        let inset = 4.4 + (3.0 - 4.4) * t
        let origin = NSPoint(x: ((s - markSide) / 2).rounded(), y: ((s - markSide) / 2).rounded())
        let stones = NSBezierPath()
        for c in cells { stones.append(tile(c, origin: origin, side: markSide, inset: inset, radius: 4, snap: 1)) }
        // One gradient across the whole mosaic, so no two tesserae are the same tone.
        NSGradient(starting: rgb(0x3FDCC6), ending: rgb(0x4A7BFF))?.draw(in: stones, angle: -45)
        NSGradient(starting: rgb(0xFFD36B), ending: rgb(0xFFB02E))?
            .draw(in: tile(core, origin: origin, side: markSide, inset: inset, radius: 4, snap: 1), angle: -90)
    }
}
