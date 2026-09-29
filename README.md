# Tessera

Una piccola app nella barra dei menu di macOS per disporre le finestre su una **griglia che decidi tu**
— 12×8, 16×9, 3×2 — invece dei soliti quattro quadranti.

## Cosa fa

- **Automatico**: "Sistema tutto" spartisce la griglia fra le finestre aperte (bilanciata, colonne,
  righe, master + pila). Una griglia 3×2 vuol dire sei riquadri: sistema le sei finestre in primo
  piano e lascia le altre dove sono. Cambi la griglia e lo schermo si ridispone all'istante.
- **Hotkey**: assegni una combinazione a una zona (un rettangolo di celle) e la finestra attiva ci va.
- **Griglia nel menu**: clic sull'icona, clic sulla cella (o trascini su più celle).
- **Disposizioni salvate**: "Dev", "Call", "Ricerca" — tutte le finestre al loro posto in un colpo.
- **Auto-fit**: se vuoi, ogni finestra nuova finisce da sola nell'area libera più grande.

Gap esterni e interni configurabili, griglia diversa per ogni schermo. Tocca solo le finestre della
Scrivania in cui sei.

## Installazione

```sh
./install.sh
```

Poi autorizza Tessera in *Impostazioni di Sistema › Privacy e sicurezza › Accessibilità*: serve per
spostare le finestre delle altre app. Per disinstallare: `./uninstall.sh`.

## Sviluppo

```sh
./scripts/test.sh              # controlli numerici sulla geometria della griglia
./scripts/build-app.sh         # build/Tessera.app
./scripts/render-ui.sh         # popover e Impostazioni in PNG, senza lanciare l'app
~/Applications/Tessera.app/Contents/MacOS/Tessera --diagnose   # cosa vede e cosa farebbe, a secco
```

`--diagnose` non sposta niente: stampa schermi, griglie, finestre viste e la cella in cui finirebbe
ognuna. È il primo comando da lanciare quando una disposizione non è quella che ti aspettavi.

Requisiti: macOS 13+, strumenti da riga di comando di Xcode. Nessuna dipendenza esterna.
La configurazione sta in `~/Library/Application Support/Tessera/config.json`.
