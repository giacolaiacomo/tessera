#!/bin/zsh
set -e
pkill -x Tessera 2>/dev/null || true
rm -rf "$HOME/Applications/Tessera.app"
echo "✓ Tessera rimossa. La configurazione resta in ~/Library/Application Support/Tessera (cancellala a mano se vuoi)."
