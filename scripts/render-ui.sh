#!/bin/zsh
# Renders the popover and the settings window to PNG without launching the app, so a UI change
# can be looked at before it ships. Output: build/ui/popover.png, settings.png, zones.png.
#
#   ./scripts/render-ui.sh [outdir] [light|dark] [docs] [frames]
#
# With no extra flags nothing changes: the same three PNGs as always. The flags are what
# scripts/docs-images.sh uses — see the header of Tests/RenderUI.swift.
set -e
cd "$(dirname "$0")/.."
OUT="${1:-build/ui}"
shift 2>/dev/null || true
mkdir -p "$OUT"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
cp Tests/RenderUI.swift "$WORK/main.swift"
# main.swift is excluded: it owns the real entry point, and RenderUI.swift stands in for it.
swiftc $(ls Sources/*.swift | grep -v 'main.swift') "$WORK/main.swift" \
  -module-cache-path "$WORK/modules" -o "$WORK/render"
"$WORK/render" "$OUT" "$@"
