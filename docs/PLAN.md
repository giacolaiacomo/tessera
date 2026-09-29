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

**Next action:** `./install.sh` e riprovare «Sistema tutto» con la griglia 3×2; se una disposizione non torna, `Tessera --diagnose` prima di qualsiasi ipotesi e guardare drag-to-zone e "sistema tutto" su dati reali (Gianluca).

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

| 2026-09-29 | Round 2 dopo la prova di Gianluca | 3214d68 + | fatto | motore, UI in stile Burny, logo; UI resa fuori schermo e guardata prima della consegna |

### Round 2 — cosa ha detto la prova su schermo vero

Bocciato: drag-to-zone («inguardabile, compare a ogni spostamento e mette 1×1»), UI troppo grande,
«Sistema tutto» che con 3×2 ridimensiona senza ridisporre.

- **Drag-to-zone rimosso del tutto** (scelta di Gianluca): via `DragWatcher` e l'overlay della
  griglia; di `Overlay.swift` resta solo il lampo di conferma dopo un piazzamento.
- **Causa del «ridimensiona ma non dispone»**, tre bug veri trovati rileggendo:
  1. le finestre oltre la capienza della griglia ricevevano tutte l'ultima cella, quindi si
     impilavano — ora si sistemano solo le prime `colonne × righe` in primo piano (z-order da
     `CGWindowListCopyWindowInfo`) e le altre restano intatte;
  2. `AutoArrange.windows(on:)` confrontava gli schermi con `===`, ma `NSScreen` non garantisce
     l'identità fra chiamate — ora confronta `tesseraKey`;
  3. `AX.setFrame` faceva dimensione → posizione, e ingrandire vicino a un bordo fa rispingere
     dentro la finestra da macOS, perdendo la posizione — ora posizione → dimensione → posizione,
     fino a tre passaggi, e accetta la dimensione minima imposta dall'app purché la posizione sia giusta.
- **Solo la Scrivania corrente**: le finestre su altri Spaces non vengono più toccate.
- **Cambiare griglia ridispone subito** lo schermo interessato (`rearrangeOnGridChange`, default on).
- **Nuova strategia «Una per cella»**: la griglia presa alla lettera (3×2 = sei riquadri anche con
  quattro finestre), perché «bilanciata» riempie sempre lo schermo e non era ciò che Gianluca si aspettava.
- **`--diagnose`**: stampa schermi, griglie, finestre viste e la cella di destinazione, senza muovere nulla.
- **UI rifatta in stile Burny**: popover SwiftUI da 272 pt (prima un NSMenu con una griglia da 264 pt)
  e Impostazioni da 360×520 pt (prima una finestra 780×560 con TabView), stessa scala tipografica di
  Burny (10 / 10.5 / 11 / 12 / 13) e le stesse card.
- **Logo** disegnato con la skill indicata da Gianluca (kaankiziltug/logo-design-skill): cinque tessere
  di dimensioni diverse che girano attorno a un nucleo caldo; `assets/` ha SVG, palette e anteprime,
  `Sources/Logo.swift` le ridisegna in AppKit (l'app non ha risorse esterne).
- **`./scripts/render-ui.sh`**: rende popover e Impostazioni in PNG senza lanciare l'app, per
  guardare una modifica di UI prima di spedirla.

**Deviazioni dal piano:** `masterStack` non era rappresentabile quando la pila supera le righe della
griglia; invece di stringere le finestre sotto la cella, ripiega sulla disposizione bilanciata.
