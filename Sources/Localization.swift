// Tessera — localization, the same way Burny does it.
//
// The source is written in English: the literals in the code are the strings the app shows, so
// reading a view tells you exactly what appears on screen. A translation is one table keyed by
// the English text, and adding a language means adding a table — nothing else moves.
//
// `lang` is resolved once when the store loads and again whenever the setting changes, so a
// view built after that already draws in the chosen language.

import Foundation

var lang = "en"

/// "system" follows the Mac's preferred language, which for us is Italian or English.
func resolveLanguage(_ pref: String) -> String {
    pref != "system" ? pref : (Locale.preferredLanguages.first?.hasPrefix("it") == true ? "it" : "en")
}

let italian: [String: String] = [
    // Strategies
    "Balanced": "Bilanciata",
    "One per cell": "Una per cella",
    "Columns": "Colonne",
    "Rows": "Righe",
    "Master + stack": "Master + pila",
    "Fills the screen, splitting it into tiles as square as it can.":
        "Riempie lo schermo dividendolo in riquadri il più quadrati possibile.",
    "One window per grid cell, in reading order: on a 3×2 every window is a sixth of the screen, even when there are fewer than six.":
        "Una finestra per cella della griglia, nell'ordine di lettura: con 3×2 ogni finestra è un sesto di schermo, anche se le finestre sono meno di sei.",
    "One column each, as tall as the screen.": "Una colonna a testa, alte quanto lo schermo.",
    "One row each, as wide as the screen.": "Una riga a testa, larghe quanto lo schermo.",
    "The front window large on the left, the rest stacked on the right.":
        "La finestra in primo piano grande a sinistra, le altre in pila a destra.",

    // Placement outcomes
    "ok": "ok",
    "the app insists on %d×%d": "l'app impone %d×%d",
    "did not move": "non si è mossa",
    ", it is at %d,%d": ", è a %d,%d",

    // Popover
    "Settings": "Impostazioni",
    "Zones": "Zone",
    "Quit": "Esci",
    "Accessibility access is missing.": "Manca l'accesso Accessibilità.",
    "Open": "Apri",
    "Screen": "Schermo",
    "1 window": "1 finestra",
    "%d windows": "%d finestre",
    "1 dashed window won't fit exactly": "1 tratteggiata non si piazza esatta",
    "%d dashed windows won't fit exactly": "%d tratteggiate non si piazzano esatte",
    "Accessibility access is needed to see the windows.":
        "Serve l'accesso Accessibilità per vedere le finestre.",
    "1 window needs more room than a %d×%d cell.":
        "1 finestra ha bisogno di più spazio di una cella da %d×%d.",
    "%d windows need more room than a %d×%d cell.":
        "%d finestre hanno bisogno di più spazio di una cella da %d×%d.",
    "Auto picks cells they can use.": "Auto sceglie celle che possono usare.",
    "Drag a window to move it, hold ⌥ to give it more cells.":
        "Trascina una finestra per spostarla, tieni ⌥ per darle più celle.",
    "Click a cell to place %@.": "Clicca una cella per piazzare %@.",
    "Click or drag to place %@.": "Clic o trascina per piazzare %@.",
    "Bring a window to the front to place it.": "Porta davanti una finestra per poterla piazzare.",
    "Arrange all": "Sistema tutto",
    "Arrangement": "Composizione",
    "1 window in the grid": "1 finestra in griglia",
    "%d windows in the grid": "%d finestre in griglia",
    "1 stays where it is": "1 resta dov'è",
    "%d stay where they are": "%d restano dove sono",
    "Snap the front window": "Sistema la finestra davanti",
    "%@ into the biggest free space": "%@ nello spazio libero più grande",
    "Nothing is in front right now": "Adesso non c'è nessuna finestra davanti",
    "Fit the grid to the windows": "Adatta la griglia alle finestre",
    "Pick the grid from what is open, then arrange":
        "Sceglie la griglia da ciò che è aperto, poi dispone",
    "Layouts": "Disposizioni",
    "No saved layouts.": "Nessuna disposizione salvata.",
    "Save current layout…": "Salva disposizione attuale…",
    "Save the current layout": "Salva la disposizione attuale",
    "Name the windows as they sit right now.": "Dai un nome alla disposizione delle finestre di adesso.",
    "Save": "Salva",
    "Cancel": "Annulla",
    "Name": "Nome",
    "Layout %d": "Disposizione %d",

    // Settings
    "Areas with a shortcut": "Aree con scorciatoia",
    "none": "nessuna",
    "Grid": "Griglia",
    "Main screen": "Schermo principale",
    "Fixed": "Fissa",
    "Automatic": "Automatica",
    "The cells are the ones you pick, whatever is open.":
        "Le celle sono quelle che scegli tu, qualunque cosa sia aperta.",
    "The cells come from how many windows are on the screen.":
        "Le celle nascono da quante finestre ci sono sullo schermo.",
    "Now %d×%d, from %@.": "Ora %d×%d, da %@.",
    "1 open window": "1 finestra aperta",
    "%d open windows": "%d finestre aperte",
    "Outer edge": "Bordo esterno",
    "Between cells": "Fra le celle",
    "Arrange now": "Sistema adesso",
    "Arranges the windows on the screen under the pointer, right away.":
        "Dispone subito le finestre dello schermo sotto il puntatore.",
    "No zones yet. A zone is an area of the grid with a global shortcut: press ⌃⌥1 and the active window lands in it.":
        "Nessuna zona. Una zona è un'area della griglia con una scorciatoia globale: ⌃⌥1 e la finestra attiva ci finisce dentro.",
    "Add zone": "Aggiungi zona",
    "Delete the zone": "Elimina la zona",
    "Shortcut": "Scorciatoia",
    "Zone %d": "Zona %d",
    "Automatic arrangement": "Automatico",
    "Master width": "Larghezza del master",
    "Windows": "Finestre",
    "Arrange new windows": "Sistema le finestre nuove",
    "A window that has just opened lands in the biggest hole of the grid.":
        "Una finestra appena aperta finisce nel buco più grande della griglia.",
    "General": "Generale",
    "Open at login": "Apri al login",
    "Language": "Lingua",
    "System": "Sistema",
    "Re-arrange when the grid changes": "Ridisponi al cambio di griglia",
    "The screen's windows are arranged straight away.":
        "Le finestre dello schermo vengono sistemate all'istante.",
    "Configuration folder": "Cartella di configurazione",
    "Show": "Mostra",
    "Accessibility access is on": "Accesso Accessibilità attivo",
    "Without Accessibility access, Tessera cannot move windows.":
        "Senza l'accesso Accessibilità, Tessera non può spostare le finestre.",
    "Open System Settings": "Apri Impostazioni di Sistema",

    // Hotkeys
    "Space": "Spazio",
    "Press a combination…": "Premi una combinazione…",
    "No shortcut": "Nessuna scorciatoia",

    // Accessibility prompt
    "Tessera needs Accessibility access": "Tessera ha bisogno dell'accesso Accessibilità",
    "To move and resize the windows of other apps, Tessera has to be allowed in System Settings › Privacy & Security › Accessibility. It works the moment you tick the box: no restart needed.":
        "Per spostare e ridimensionare le finestre delle altre app, Tessera va autorizzata in Impostazioni di Sistema › Privacy e sicurezza › Accessibilità. Appena spunti la casella funziona: non serve riavviarla.",
    "Open Settings": "Apri Impostazioni",
    "Later": "Più tardi",

    // Command line
    "Screen %@: grid %d×%d from the open windows, 1 arranged.":
        "Schermo %@: griglia %d×%d dalle finestre aperte, sistemata 1.",
    "Screen %@: grid %d×%d from the open windows, %d arranged.":
        "Schermo %@: griglia %d×%d dalle finestre aperte, sistemate %d.",
    "1 window needed a second nudge.": "1 finestra ha avuto bisogno di una seconda spinta.",
    "%d windows needed a second nudge.": "%d finestre hanno avuto bisogno di una seconda spinta.",
    "Usage: --place col,row[,width,height] [--screen name]":
        "Uso: --place colonna,riga[,larghezza,altezza] [--screen nome]",
    "%@ placed in col %d row %d %d×%d.": "%@ piazzata in col %d riga %d %d×%d.",
    "No window is in front.": "Nessuna finestra in primo piano.",
    "Popover closed.": "Popover chiuso.",
    "Settings open in the popover.": "Impostazioni aperte nel popover.",
    "No window is in full screen.": "Nessuna finestra a tutto schermo.",
    "Brought back out of full screen: %@": "Riportate fuori dal fullscreen: %@",
    "Screen %@: 1 window arranged with the “%@” arrangement.":
        "Schermo %@: sistemata 1 finestra con la strategia «%@».",
    "Screen %@: %d windows arranged with the “%@” arrangement.":
        "Schermo %@: sistemate %d finestre con la strategia «%@».",
    "Tessera %@ — diagnostics (no window is moved)":
        "Tessera %@ — diagnostica (nessuna finestra viene spostata)",
    "Front window: %@": "Finestra davanti: %@",
    "Accessibility access: %@": "Accesso Accessibilità: %@",
    "on": "attivo",
    "NOT on — allow the app and try again": "NON attivo — autorizza l'app e riprova",
    "Default arrangement: %@": "Strategia predefinita: %@",
    "Screen %@ [%@]": "Schermo %@ [%@]",
    " (automatic: recomputed when you arrange, not now)":
        " (automatica: si ricalcola quando disponi, non adesso)",
    " (default, never changed for this screen)":
        " (predefinita, mai modificata per questo schermo)",
    " (fixed)": " (fissa)",
    "  grid: %d×%d, outer gap %d, inner gap %d":
        "  griglia: %d×%d, gap esterno %d, gap interno %d",
    "  windows on this Desktop: %d — would arrange %d, would leave %d":
        "  finestre su questa Scrivania: %d — ne sistemerebbe %d, ne lascia %d",
    "    %@ — %@ → cell col %d row %d %d×%d = %@":
        "    %@ — %@ → cella col %d riga %d %d×%d = %@",
    "Tessera is not running: open it and try again.":
        "Tessera non è in esecuzione: aprila e riprova.",
    "Tessera did not answer within 4 seconds.": "Tessera non ha risposto entro 4 secondi.",
    "Arrange which windows": "Quali finestre sistemare",
    "All": "Tutte",
    "Arrange %@": "Sistema %@",
    "All on this screen": "Tutte su questo schermo",
    "%d %@ windows · everything else stays put":
        "%d finestre di %@ · tutto il resto resta dov'è",
    " Only %@ — everything else was left where it was.":
        " Solo %@ — tutto il resto è rimasto dov'era.",
]

func tr(_ s: String) -> String { lang == "it" ? italian[s] ?? s : s }
