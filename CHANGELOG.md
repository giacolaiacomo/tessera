# Changelog

## 1.0.0 — 2026-09-29

First public release.

- **A grid per screen**, fixed or automatic. Fixed means the grid you pick: the presets 2×1, 3×1,
  4×1, 3×2 and 4×2 are one click away in the popover, and the steppers go up to 32×32. Automatic
  derives the grid from how many windows are open on that screen, so they all fit and stay visible.
  Outer and inner gaps are configurable, per screen.
- **A live map of the screen** in the popover: the windows currently on it, drawn on the cells they
  occupy. Click a cell — or drag across several — to send the frontmost window there.
- **Arrange all**, with five arrangements: Balanced, One per cell, Columns, Rows, and
  Master + stack. Windows past the grid's capacity are left untouched.
- **Zones**: a named span of cells with a global hotkey that sends the active window into it.
- **Saved layouts**: capture where everything is right now, restore it later, with an optional
  hotkey.
- **Auto-fit new windows** (optional): a window that has just opened lands in the largest free area
  of the grid.
- Only the current Desktop/Space is touched, full-screen windows are skipped, and each window is
  placed with a single write, so there is no visible shuffling.
- **Command line**: `--diagnose` (prints screens, grids, the windows it sees and each one's target
  cell, without moving anything), `--arrange [strategy] [--screen name]`, `--fit-grid`,
  `--settings`, `--exit-fullscreen`, `--icon`.
- Settings live in the same popover as everything else, including Open at login and the language
  (System / English / Italiano).
- No network, no telemetry. Configuration is a single `~/Library/Application Support/Tessera/config.json`.
- Swift with AppKit and SwiftUI, no dependencies and no Xcode project. macOS 13+, about 29 MB of RAM.
