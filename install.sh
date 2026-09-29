#!/bin/zsh
# Build Tessera.app into ~/Applications and run it.
#
# Accessibility permission is tied to the binary's signature, so always install to
# ~/Applications and launch from there — running an ad-hoc rebuild from the Desktop
# makes macOS ask for the permission again every time.
set -e
cd "$(dirname "$0")"

APP="$HOME/Applications/Tessera.app"
pkill -x Tessera 2>/dev/null || true
echo "→ Building…"
./scripts/build-app.sh "$APP"
open "$APP"
echo "✓ Tessera installata in ~/Applications e avviata — guarda la barra dei menu."
echo "  Se è la prima volta, autorizzala in Impostazioni di Sistema › Privacy e sicurezza › Accessibilità."
