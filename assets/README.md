# Tessera logo

**Concept.** Five mosaic tesserae of five different sizes pinwheel around a small core and fill a square
exactly, with no leftover — a grid that is deliberately *not* uniform, which is the whole point of the app.
No arrows, no window chrome, no 2×2 quadrants.

**Construction grid.** A 100×100 square, top-left origin: `60×40` (top), `40×68` (right), `68×32` (bottom),
`32×60` (left), `28×28` (core at 32,40). The five areas sum to exactly 10000. Grout is a per-tile inset,
corner radius 4 units. App icon: inset 3, mark 58 % of the canvas inside an 80 % superellipse tile
(n = 5, the macOS Big Sur shape). Menu bar: inset 3.5, mark 14 pt in a 16×14 pt box.

**Palette (sRGB).** Tile `#1B2743` → `#0A1020` (top to bottom) · glow `#4A7BFF` at 30 % → 0 %
· tesserae `#3FDCC6` → `#4A7BFF` (one 45° sweep across the *whole* mosaic, so no two tiles match)
· core `#FFD36B` → `#FFB02E`.

**Don't.** Don't let the mosaic grow into the tile's safe margin (it stays inside the 80 % superellipse, with
air around it). Don't give each tessera its own gradient — one sweep across the set. Don't recolour the core:
the single warm tile is the only accent, and it carries the "one tile just landed" reading. Don't close the
grout: below 128 px the mark grows and the gaps open (`Sources/Logo.swift` does this automatically), and the
menu bar cut snaps to device pixels so the gaps never disappear at 1×. No text, ever.

`logo.svg` and `menubar.svg` are the masters; `Sources/Logo.swift` redraws them with NSBezierPath because the
app ships as a single binary. `preview/` holds renders straight out of that Swift code.
