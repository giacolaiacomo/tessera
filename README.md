# Tessera

Una piccola app nella barra dei menu di macOS per disporre le finestre su una **griglia che decidi tu**
— 12×8, 16×9, 3×2 — invece dei soliti quattro quadranti.

## Cosa fa

- **Automatico**: "Sistema tutto" spartisce la griglia fra le finestre aperte (bilanciata, colonne,
  righe, master + pila). Una griglia 3×2 vuol dire sei riquadri: sistema le sei finestre in primo
  piano e lascia le altre dove sono. Cambi la griglia e lo schermo si ridispone all'istante.
- **Hotkey**: assegni una combinazione a una zona (un rettangolo di celle) e la finestra attiva ci va.
- **Griglia nel menu**: clic sull'icona e vedi dove sono le finestre adesso, ognuna col nome
  dell'app; clic su una cella (o trascinamento su più celle) per piazzare quella attiva.
  Le impostazioni sono una pagina dello stesso popover, non una finestra a parte.
- **Disposizioni salvate**: "Dev", "Call", "Ricerca" — tutte le finestre al loro posto in un colpo.
- **Auto-fit**: se vuoi, ogni finestra nuova finisce da sola nell'area libera più grande.

La griglia di ogni schermo può essere **fissa** — quella che scegli tu — oppure **automatica**:
la decide il numero di finestre aperte su quel monitor, così ci stanno tutte e si vedono tutte.
Su un 34" ultrawide quattro finestre diventano 2×2 e sei diventano 3×2; i margini che hai scelto
restano i tuoi, la modalità decide solo quante celle.

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

# Comandi dell'app installata (parlano con l'istanza in esecuzione, che ha il permesso):
T=~/Applications/Tessera.app/Contents/MacOS/Tessera
$T --diagnose                       # cosa vede e cosa farebbe, senza muovere nulla
$T --arrange cells --screen Acer    # dispone davvero, su uno schermo scelto, e riporta esito per finestra
$T --fit-grid --screen Acer         # sceglie la griglia dalle finestre aperte e le dispone tutte
$T --exit-fullscreen                # riporta le finestre fuori dal fullscreen (lì non sono disponibili)
```

`--diagnose` non sposta niente: stampa schermi, griglie, finestre viste e la cella in cui finirebbe
ognuna. È il primo comando da lanciare quando una disposizione non è quella che ti aspettavi.
`--arrange` riporta l'esito finestra per finestra, compreso il motivo di un rifiuto (codice AX,
attributi settabili, stato fullscreen).

### Cosa non si può ottenere da un'app

Alcune finestre non obbediscono, e non è un difetto di Tessera: le app a **dimensione minima**
(Chrome sotto i 500 pt, Attività di Sistema, Teams) restano più grandi della cella; **Terminale**
si aggancia alla griglia dei caratteri, quindi sbaglia di qualche pixel; le finestre in
**fullscreen** hanno una Scrivania tutta loro e vengono saltate — usa `--exit-fullscreen` o il
pulsante verde per riportarle indietro. Tessera fa due passaggi di assestamento, perché diverse
app (Terminale, Chromium) si riaggiustano dopo il ridimensionamento.

Requisiti: macOS 13+, strumenti da riga di comando di Xcode. Nessuna dipendenza esterna.
La configurazione sta in `~/Library/Application Support/Tessera/config.json`.
