# Changelog

## Unreleased

- **Tessera learns how small each app goes** and stops proposing cells they cannot use. A window
  that refuses its cell tells us its minimum for free; the automatic grid then picks fewer, bigger
  cells on a screen that cannot hold more, and leaves the windows that do not fit where they are.
  Measured on a 1512×892 laptop with six windows open: a 3×2 gave 493-wide cells that five of the
  six apps refused, and the result was a pile; automatic now answers 2×2 and tiles the three that
  fit, all of them exactly.
- **The map's dashed tiles now mean something precise**: this app will not take that cell. A
  window that merely happens to be large right now is not dashed, because it will shrink when
  asked.
- **`--diagnose` and the popover count what the arrangement will really do**, including the
  windows it will leave alone.
- **Quick grids in the popover**: Auto plus the presets that suit the shape of that screen, one
  click away, with the arrangement named in a picker instead of hidden behind an icon. Picking an
  arrangement makes it the default and applies it.
- **Move one window from the map**: drag its tile to another cell. That window moves, not the
  front one, and the popover stays open. Hold ⌥ while dragging to give it a rectangle of cells
  instead of keeping its size. Windows an app will not resize drag like any other — before, they
  could not be dragged at all, and the gesture silently moved the front window instead.
- **Dropping a window on an occupied cell swaps the two** instead of piling them up. Only when
  exactly one window is in the way and the dragged one keeps its shape; an ⌥-sweep leaves
  whatever it covers alone.
- **`--place col,row[,w,h]`**: the front window into one rectangle of the grid, from the command
  line.
- A single placement (map, zone hotkey, `--place`) also keeps a window that refuses to shrink
  inside the screen, instead of hanging it off the edge.
- **The pairing of windows to cells now minimises movement**: a window already on its cell stays
  there instead of swapping with a neighbour. `--diagnose` shows the same pairing an arrangement
  would use.
- **Arrangements are written back to back**, with no pause between windows: Tessera waits by
  looking, and only writes a second time to a window that neither moved nor resized. An app that
  refuses to shrink below its minimum is now slid back inside the screen instead of being left
  hanging off the edge.

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
