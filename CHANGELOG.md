# Changelog

## Unreleased

- **Fixed, properly this time: "Arrange all" still needed two or three clicks.** The previous fix
  asked a window again when it had not landed — but skipped any window whose app Tessera had
  learned needs more room than the cell, and those were exactly the windows that needed asking
  again. Worse, that learned minimum was often an over-estimate, measured from a window caught
  halfway through a resize, so an app could disqualify itself from the retry on the strength of
  a number that was wrong. Mail came down roughly half the remaining distance per click: 246 px
  too wide, then 118, then 60.
  What ends the retry now is the window itself, not a stored number. Tessera asks again — up to
  three times, pausing first — and drops a window from the list the moment a round changes
  nothing about it, because an app refusing its cell refuses instantly. Measured on both screens
  from a scrambled start: one pass gives exactly what two passes give, five times out of five.
  Mail, which used to take three clicks, now lands exact on the first.

- **Fixed: "Arrange all" needed a second click to finish the job.** The first click put the
  windows in the right places at not-quite-the-right sizes; the second one got it right. Two
  separate causes, both now measured rather than guessed at.
  - An app that has to grow a window a long way stops short of the size it was given, and takes
    the rest only when asked again. Three Terminal windows dragged from 1900×1000 into the cells
    of a 3×1 came out about 60 px short every time.
  - **It will not hear the second request if it comes too soon.** Repeating the write straight
    away changed nothing at all — six writes in 200 ms left the windows exactly as wrong as one
    did. A pause of 120 ms before asking again is what the second click really was, and with it
    one click lands the windows within 4 px, which is Terminal's character grid and as close as
    anything gets.
  Tessera now asks again, up to twice, pausing first, and only of a window that has not landed
  and whose app is not already known to need more room than the cell has. A screen where
  everything lands first time pays nothing for any of this: still 71 ms. The same applies to a
  single placement, so dragging one window on the map finishes in one gesture too.

- **Fixed: the first "Arrange all" placed the windows but did not resize them, and it took a
  second one to get it right.** The cause is the oldest trap in this codebase, walked into from
  a new direction. Tessera writes a position and a size, waits, and then corrects any window
  that did not land — and the correction used to rewrite the *size it had just read*. When a
  window was read before its app had finished resizing, that read returned the old size, and
  writing it back cancelled the resize still in flight: the window ended up in exactly the right
  place at exactly the wrong size. Two things now make that impossible. Every correction after
  the first write is a **move and only a move** — Tessera never writes a size it read a moment
  earlier. And the wait no longer mistakes a window that has not started moving for one that has
  finished: it waits for each window that was actually asked for something to visibly answer,
  and for three consecutive quiet reads, because Chrome animates its resize and two reads 20 ms
  apart can both land in the same lull. Checked by arranging from a scrambled screen and
  comparing the result of one pass with the result of two: identical, three times over.
- A side effect of the same bug: the app minimums Tessera learns were being taught frames caught
  in mid-air. Chrome was recorded as needing 927×627 when it really stops at 500×434, and a
  wrong minimum makes the automatic grid too coarse.

- **An arrangement is about twenty times faster.** Measured on a 1512×892 laptop with six windows
  that all really move: **1584 ms before, 130 ms now**; on an ultrawide with four, 263 ms → 72 ms.
  Almost none of that was the windows. The writes themselves take 2–13 ms; the rest was Tessera
  sleeping — a flat 90 ms before it dared look at the result and a flat 150 ms at the end,
  whether or not anything had happened. Tessera now waits for the only thing that can actually
  be observed, the frames going still, and leaves the moment they do.
- **Fixed: apps with a minimum size were nudged for nothing.** The test for "this window has
  answered" asked whether it was sitting on its cell's corner, so an app that refused the size of
  its cell — Mail, Calendar, Xcode, System Settings — looked like a window that had never
  replied. Every arrangement waited out the full timeout for them and then wrote a second time to
  windows that had already said no. Five such pointless writes per arrangement on a normal
  laptop screen; now none.
- **Moving one window from the map no longer pauses.** A placement waited a tenth of a second
  before checking on the window and the map waited a further third of a second before redrawing,
  so a drag — and a swap, which is two placements — spent about half a second doing nothing
  visible. Both waits are now a look.
- `--arrange` reports where the milliseconds went and how far each window ended up from its
  cell, so "it lags" and "it is not precise" can be answered with a number instead of an
  impression.
- An Accessibility call cannot hang the app any more: a window server round trip to another app
  is synchronous and the default timeout is generous, so one busy app could freeze the menu bar
  for seconds. It gives up after 1.5 s and says so.

## 1.1.1 — 2026-09-29

- **Fixed: Tessera would not compile with Swift 6.4**, so `brew install` failed on an up-to-date
  Mac with the error `cannot assign to property: 'self' is immutable` in `MenuBar.swift`. The
  drag gesture kept its state in `@State` properties, which it assigned from inside the gesture's
  closures; Swift 6.2 accepts that, 6.4 refuses it. The gesture's state now lives in a small
  observable object, which is not a question either compiler has to answer.
- **While you drag a window over a cell that is already taken, you can see the swap before you
  let go**: the window that would move out is drawn, faded and named, in the cell you are
  emptying.

## 1.1.0 — 2026-09-29

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
- **Fixed: everything that acts on the front window went dead after the first use.** Opening the
  popover puts Tessera in front, so the second time it opened, "the front window" was Tessera's
  own — nothing. It now remembers the app that was in front before it, and falls back to that
  app's first placeable window when nothing holds focus. `--diagnose` prints what it sees as the
  front window.
- **The two commands under the arrange button say what they do**: "Snap the front window" (with
  the app's name and where it will go) and "Fit the grid to the windows". When the first one is
  unavailable it says why instead of being a grey line.
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
