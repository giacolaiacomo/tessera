#!/bin/zsh
# Numeric checks for the grid maths (no UI, no Accessibility permission needed).
set -e
cd "$(dirname "$0")/.."
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
cp Tests/GeometryTests.swift "$WORK/main.swift"
swiftc Sources/Core.swift Sources/WindowsAX.swift Sources/AutoArrange.swift "$WORK/main.swift" \
  -module-cache-path "$WORK/modules" -o "$WORK/geotest"
"$WORK/geotest"
