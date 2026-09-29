# Security & privacy

Tessera moves other apps' windows. That is a powerful thing to let a program do, so this page says
exactly what it needs, what it does with it, and what it never does.

## Nothing leaves your Mac

Tessera makes **no network requests at all**: no update check, no crash reporting, no analytics, no
telemetry. There is no server, no account and nothing to sign in to. It reads no browser data, no
Keychain items, no credentials.

Everything it stores is one file you can read and edit:
`~/Library/Application Support/Tessera/config.json` — your grids, gaps, zones, saved layouts and
preferences. Next to it, `state.json` holds a handful of fields (version, pid, whether
Accessibility access is granted, a timestamp) so the command line can see what the running app is
doing, and `diagnose.txt` is the last reply the running app wrote for a command-line query. When
you turn on **Open at login**, Tessera registers itself with macOS's own `SMAppService`, the
documented login-item API — the same list you see in System Settings › General › Login Items.
Nothing else is written anywhere.

## Accessibility access: why, and what it allows

macOS keeps one app from touching another app's windows unless you allow it in
**System Settings › Privacy & Security › Accessibility**. Tessera asks for it because that
permission *is* the feature: without it, it cannot move or resize a single window.

What Tessera does with it:

| | |
|---|---|
| **Reads** | The list of on-screen windows on the current Desktop, and for each one its owning app, its title and its frame — the same things Mission Control shows you. |
| **Writes** | A window's position and size, one write per window, when you place it, arrange a screen, trigger a zone hotkey or restore a layout. |
| **Never** | Reads the contents of a window, its text fields, its documents or its clipboard. Accessibility can, in principle, read the text inside other apps; Tessera asks only for window geometry and asks for nothing else. |

Window titles are used to match a window to a saved layout and to label it on the popover's map.
They stay in memory and in `config.json` if you save a layout that matches on one; they are never
sent anywhere, because nothing is ever sent anywhere.

The permission is granted to a **signature**, not to a path. `scripts/build-app.sh` signs with your
Apple Development identity when you have one, so the grant survives a rebuild; with only an ad-hoc
signature, macOS sees a different app after each build and asks again. That is macOS working as
intended, not Tessera losing the permission.

## Global hotkeys

Zones and saved layouts can have a global hotkey. Tessera registers those specific combinations
with Carbon's `RegisterEventHotKey`, the documented API for exactly this. It does **not** install a
keyboard event tap and does not see any other key you press.

## You build it yourself

No prebuilt binaries are distributed. Both `./install.sh` and the Homebrew formula compile the
sources on your Mac with the Swift toolchain from the Xcode Command Line Tools. There are no
dependencies to audit beyond Apple's own frameworks, and the whole app is about 3,400 lines across
ten files in [`Sources/`](Sources/), so you can read all of it before you build it.

## Reporting a problem

Please open an issue at https://github.com/giacolaiacomo/tessera/issues. If you would rather not
discuss it in public first, say so in the issue without the details and we will find another way.
