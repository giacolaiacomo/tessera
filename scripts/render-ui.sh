#!/bin/zsh
# Renders the popover and the settings window to PNG without launching the app, so a UI change
# can be looked at before it ships. Output: build/ui/popover.png and build/ui/prefs.png.
set -e
cd "$(dirname "$0")/.."
OUT="${1:-build/ui}"
mkdir -p "$OUT"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
cp Tests/RenderUI.swift "$WORK/main.swift"
# main.swift is excluded: it owns the real entry point, and RenderUI.swift stands in for it.
swiftc $(ls Sources/*.swift | grep -v 'main.swift') "$WORK/main.swift" \
  -module-cache-path "$WORK/modules" -o "$WORK/render"
"$WORK/render" "$OUT"
