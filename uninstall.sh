#!/bin/zsh
set -e
pkill -x Tessera 2>/dev/null || true
rm -rf "$HOME/Applications/Tessera.app"
echo "✓ Tessera removed. Your configuration is still in ~/Library/Application Support/Tessera — delete it by hand if you want it gone."
