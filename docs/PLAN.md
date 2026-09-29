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

**Next action:** Gianluca prova popover, hotkey e disposizioni salvate a mano (il motore è verificato dal vivo sull'Acer: tutte le finestre atterrano al primo colpo).

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

### Round 3 — test dal vivo sull'hardware di Gianluca (2026-09-29)

Installata, autorizzata, e provata davvero su MacBook + Acer X34. Cosa ha insegnato il test,
che nessuna lettura del codice avrebbe trovato:

1. **La configurazione veniva buttata**: aggiungere un campo a `Config` rendeva illeggibile ogni
   file esistente (il decoder sintetizzato di Swift lancia sulla chiave mancante e i default della
   struct non si applicano). Il 3×2 dell'Acer era sul disco e l'app leggeva 12×8. Ora decodifica
   campo per campo, con test in entrambe le direzioni (file vecchio e file futuro).
2. **L'autorizzazione Accessibilità non sopravviveva al rebuild**: firma ad-hoc diversa a ogni
   build. Ora `build-app.sh` usa l'identità Apple Development se c'è (Team 853ZZ3CH23): verificato,
   il permesso resta dopo una reinstallazione.
3. **`--diagnose` da terminale è cieco**: gira in un processo senza permesso e vede zero finestre.
   Ora i comandi passano per l'istanza in esecuzione via `DistributedNotificationCenter`.
4. **Il pulsante zoom è veleno**: premerlo per de-massimizzare manda in fullscreen le app Electron
   e Catalyst (ci sono finite Teams e WhatsApp durante il test). Rimosso; le finestre massimizzate
   si sbloccano con uno "strattone" a dimensione piccola, e `--exit-fullscreen` ripara i danni.
5. **La verifica del piazzamento era sbagliata**: confrontava l'origine in coordinate Cocoa, che
   dipende dall'altezza scelta dall'app. Ora confronta l'angolo alto-sinistro in coordinate AX e
   accetta l'altro angolo per le app a dimensione imposta.
6. **Le app si riaggiustano dopo il ridimensionamento** (Terminale si aggancia ai caratteri,
   Chromium si riposiziona): servono due passaggi di assestamento. Con questi, sull'Acer 3×2 le
   quattro finestre arrivano tutte a destinazione.

Esito finale sull'Acer, strategia «Una per cella»: 3 finestre esatte, 1 con l'altezza imposta da
Terminale (700 invece di 693, una riga di caratteri). Limiti veri e documentati nel README:
dimensioni minime delle app, griglia dei caratteri di Terminale, finestre in fullscreen saltate.

### Round 4 — UI e UX al livello di Burny (2026-09-29)

Gianluca: «la UI e UX ancora non è a livello di Burny», e in particolare vedeva le impostazioni
in una finestra separata. Risposte sue alle domande: manca il colpo d'occhio, più una sensazione
generale di rifinitura; userà Tessera soprattutto dal popover e in automatico.

- **Un solo contenitore**: `PreferencesWindowController` eliminato. Le impostazioni sono pagine
  del popover (`PopoverPage { home, settings, zones }`) con header a chevron, come Burny.
- **Colpo d'occhio**: la miniatura della griglia non è più vuota, è la mappa di dove sono le
  finestre adesso (`AutoArrange.occupancy(on:)`): nome dell'app in ogni tessera, la finestra
  attiva in accento, tratteggiate quelle che una disposizione non può piazzare esatta
  (fullscreen, o dimensione minima più grande della cella). Sopra, la riga di stato
  «Acer X34 P · 3×2 · 4 finestre».
- **«Sistema tutto» è l'azione primaria**, un bottone vero col conteggio e il menu delle
  strategie accanto, perché è così che verrà usata.
- Popover 272 pt (era una finestra da 360×520 più un menu), scala tipografica di Burny.
- La UI si guarda prima di consegnarla: `./scripts/render-ui.sh` rende home, impostazioni e zone.

### Memoria — misurata, non stimata (2026-09-29)

`vmmap --summary` (physical footprint, quello che mostra Monitoraggio Attività), non RSS:
Tessera 28,8 MB contro i 27,9 MB di Burny, picco di avvio identico (92 MB, caricamento dei
framework). La parte scrivibile davvero dell'app è ~7 MB residenti: tutto il resto è AppKit e
Foundation nella dyld shared cache, condivise con ogni altra app.

Riscrivere in Rust o Go non sposterebbe niente (Go peggiorerebbe: runtime e GC in più, AppKit
comunque linkato). Provata e **scartata** l'ottimizzazione «butta la finestra Impostazioni alla
chiusura»: protocollo identico sulle due build, 29,4 MB contro 29,6 MB a 45 s dalla chiusura.
Chiudere una finestra libera già backing store e layer; l'albero di view che resta pesa rumore.
Resta il comando `--settings` (apre/chiude le Impostazioni da terminale), nato per quella misura.

**Deviazioni dal piano:** `masterStack` non era rappresentabile quando la pila supera le righe della
griglia; invece di stringere le finestre sotto la cella, ripiega sulla disposizione bilanciata.


### Round 3 — «si muovono mille volte invece che andare diretto»

Gianluca, dopo la prova dal vivo: «è proprio alla base il processo che è sbagliato: tu sai dove devi
andare, quante ce n'hai, come puoi fare e lì vai diretto» e «ti stai overcomplicando una cosa facilissima».
Aveva ragione due volte.

- **Tolto tutto l'impianto adattivo**: cache delle dimensioni minime imparate, assegnazione per
  domanda, `PlannedMove`, tassonomia dei rifiuti. Lo schermo è noto e le finestre si contano:
  le celle sono note, quindi una scrittura per finestra.
- **La causa vera delle finestre che non si ridimensionavano** non era l'app che rifiuta: era Tessera
  che leggeva e riscriveva più in fretta di quanto l'app risponda. Una app applica una scrittura AX
  sul proprio run loop; la lettura fatta subito dopo restituisce il frame di prima, e la terza
  scrittura di posizione — decisa su quella lettura vecchia — annullava il ridimensionamento ancora
  in volo. Misurato con una sonda: la stessa finestra che «rifiutava» 1136×1394 accetta ogni altezza
  richiesta se le si lascia 250 ms.
- Ora: posizione → dimensione, nessuna rilettura; 80 ms fra una finestra e l'altra (due finestre della
  stessa app passano per un solo processo, e a raffica tiene la prima e scarta le altre); una sola
  scrittura correttiva, e solo per chi è rimasto lontano dalla cella, giudicata sull'angolo AX.
- **Tolleranze oneste**: uno scarto fino a 20 px di dimensione è l'app che si aggancia alla propria
  griglia (Terminal alle righe di caratteri) e conta come «ok»; WhatsApp che pretende 800 px di
  larghezza in una cella da 493 resta segnalato come «l'app impone».

| Data | Compito | Commit | Verdetto | Note |
|---|---|---|---|---|
| 2026-09-29 | Semplificazione motore + griglia fissa/automatica per schermo | — | fatto | prova sull'Acer (3 Terminal, 3×1) e sull'interno (Chrome + WhatsApp, 3×2): tutte «ok» al primo colpo tranne la larghezza minima di WhatsApp; seconda passata identica alla prima (nessuno si muove più) |
