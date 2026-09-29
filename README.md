# Tessera

Una piccola app nella barra dei menu di macOS per disporre le finestre su una **griglia che decidi tu**
— 12×8, 16×9, 3×2 — invece dei soliti quattro quadranti.

## Cosa fa

- **Trascina e rilascia**: mentre sposti una finestra compare la griglia; rilasci su una cella, o
  "pennelli" più celle tenendo premuto, e la finestra ci si incastra.
- **Hotkey**: assegni una combinazione a una zona (un rettangolo di celle) e la finestra attiva ci va.
- **Griglia nel menu**: clic sull'icona, clic sulla cella.
- **Disposizioni salvate**: "Dev", "Call", "Ricerca" — tutte le finestre al loro posto in un colpo.
- **Automatico**: "Sistema tutto" spartisce la griglia fra le finestre aperte (bilanciata, colonne,
  righe, master + pila) e, se vuoi, ogni finestra nuova finisce da sola nell'area libera più grande.

Gap esterni e interni configurabili, griglia diversa per ogni schermo.

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
```

Requisiti: macOS 13+, strumenti da riga di comando di Xcode. Nessuna dipendenza esterna.
La configurazione sta in `~/Library/Application Support/Tessera/config.json`.
