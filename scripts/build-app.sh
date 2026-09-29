#!/bin/zsh
# Build Tessera.app at the given path (default: ./build/Tessera.app).
set -e
cd "$(dirname "$0")/.."
command -v swiftc >/dev/null || { echo "swiftc not found — run: xcode-select --install"; exit 1; }

APP="${1:-build/Tessera.app}"
VERSION=$(grep -m1 '^let appVersion' Sources/Core.swift | cut -d'"' -f2)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -Osize Sources/*.swift -module-cache-path "$WORK/modules" -o "$APP/Contents/MacOS/Tessera"
strip -x "$APP/Contents/MacOS/Tessera"

# App icon, drawn by the app itself
mkdir -p "$WORK/AppIcon.iconset"
for s in 16 32 128 256 512; do
  "$APP/Contents/MacOS/Tessera" --icon "$WORK/AppIcon.iconset/icon_${s}x${s}.png" $s
  "$APP/Contents/MacOS/Tessera" --icon "$WORK/AppIcon.iconset/icon_${s}x${s}@2x.png" $((s * 2))
done
iconutil -c icns "$WORK/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Tessera</string>
  <key>CFBundleIdentifier</key><string>com.tessera.menubar</string>
  <key>CFBundleExecutable</key><string>Tessera</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PL
# Sign with a stable identity when one exists. This is what makes the Accessibility permission
# survive a rebuild: macOS keys the grant to the signature, and an ad-hoc one changes every time
# the binary does, so the app silently stops being the app that was authorised.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -m1 "Apple Development" | sed -E 's/.*\) ([0-9A-F]+) ".*/\1/')
if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" "$APP" >/dev/null 2>&1 \
    && echo "  firmata con l'identità Apple Development $IDENTITY" \
    || { codesign --force --sign - "$APP" 2>/dev/null; echo "  firma stabile fallita, ad-hoc"; }
else
  codesign --force --sign - "$APP" 2>/dev/null || true   # ad-hoc: local use only
  echo "  firmata ad-hoc: l'autorizzazione Accessibilità andrà ridata dopo ogni build"
fi
echo "✓ $APP ($VERSION)"
