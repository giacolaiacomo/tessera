# Tessera — piano

Menu bar app macOS che dispone le finestre su una griglia configurabile (non i soliti 4 quadranti).
Swift + AppKit/SwiftUI, nessuna dipendenza, build con `swiftc Sources/*.swift` (stesso stampo di Burny).

## Scelte

- **Griglia fissa configurabile per schermo** (`GridSpec`: colonne, righe, gap esterno e interno),
  salvata per display in `~/Library/Application Support/Tessera/config.json`. Una zona è un
  rettangolo di celle (`CellRect`), quindi qualunque area — 1 cella o 5×3 — è esprimibile.
- **Quattro modi di piazzare, una sola griglia**: overlay drag-to-zone, hotkey globali sulle zone,
  griglia cliccabile nel popover del menu bar, layout salvati applicati in blocco.
- **Automatico**: `AutoArrange` spartisce la griglia scelta fra le finestre aperte
  (bilanciata / colonne / righe / master+pila) e l'auto-fit mette una finestra nuova nel
  rettangolo libero più grande. Tutto in celle intere, così resta allineato a ciò che si fa a mano.
- Coordinate: tutto in coordinate Cocoa; solo `WindowsAX.swift` conosce il top-left dell'API AX.

## Moduli

| File | Contenuto |
|---|---|
| `Sources/Core.swift` | `GridSpec`, `CellRect`, `Geometry`, `Zone`, `Layout`, `Config`, `Store`, chiavi schermo |
| `Sources/WindowsAX.swift` | Accessibility: elenco finestre, finestra sotto il mouse, set frame con doppio passaggio |
| `Sources/AutoArrange.swift` | partizioni della griglia, rettangolo libero più grande, applicazione |
| `Sources/Overlay.swift` | overlay della griglia + `DragWatcher` (drag-to-zone) |
| `Sources/Hotkeys.swift` | hotkey globali Carbon, recorder per le Preferenze, watcher finestre nuove |
| `Sources/MenuBar.swift` | status item, griglia cliccabile, zone, "sistema tutto", layout |
| `Sources/Preferences.swift` | griglia per schermo, editor zone, automatico, generale |
| `Sources/main.swift` | `AppController` (API unica per UI/hotkey/overlay), icona, entry point |
| `Tests/GeometryTests.swift` | controlli numerici puri: `./scripts/test.sh` |

## Ledger

**Next action:** `./install.sh`, autorizzare in Accessibilità, e guardare drag-to-zone e «Sistema tutto» su schermo vero e guardare drag-to-zone e "sistema tutto" su dati reali (Gianluca).

| Data | Compito | Commit | Verdetto | Note |
|---|---|---|---|---|
| 2026-09-29 | Core + geometria + persistenza | — | fatto | `swiftc -typecheck` pulito |
| 2026-09-29 | Bridge Accessibility | — | fatto | doppio passaggio size→position→size per le app che clampano |
| 2026-09-29 | AutoArrange (4 strategie + auto-fit) | — | fatto | banco di prova: 4 griglie × 2 schermi × 4 strategie × 1–24 finestre, verde |
| 2026-09-29 | Banco di prova geometria | — | fatto | ha trovato 2 bug veri: arrotondamento per lato invece che per dimensione (span disallineato di 1 px) e strategie che restituivano meno tessere delle finestre |
| 2026-09-29 | MenuBar (lotto delegato) | — | fatto | finestra attiva catturata in `menuWillOpen`, non riletta a menu aperto |
| 2026-09-29 | Overlay + hotkey (lotto delegato) | — | fatto | review mia: aggiunto un solo hit test AX per gesto (era uno per evento di drag) |
| 2026-09-29 | Preferenze (lotto delegato) | — | fatto | review mia: `HotkeyRecorder` ri-collega i binding in `updateNSView`, non più solo alla creazione; `autoenablesItems = false` sul menu, altrimenti AppKit riabilitava le voci senza permesso Accessibilità |
| 2026-09-29 | Build `.app` + install.sh | — | fatto | ad-hoc sign; installare in `~/Applications` o macOS richiede di nuovo l'accesso Accessibilità |

**Deviazioni dal piano:** `masterStack` non era rappresentabile quando la pila supera le righe della
griglia; invece di stringere le finestre sotto la cella, ripiega sulla disposizione bilanciata.
