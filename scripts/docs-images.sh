#!/bin/zsh
# Regenerates every image the README uses, from the real UI. One command, no manual step, and
# no Accessibility access: the popover is rendered off-screen by scripts/render-ui.sh with
# made-up but realistic state, so nothing of the machine it runs on ends up in the pictures.
#
#   ./scripts/docs-images.sh
#
# Writes docs/hero.jpg, docs/screens.jpg, docs/demo.gif, docs/social-preview.jpg, docs/icon.png.
set -e
cd "$(dirname "$0")/.."
command -v ffmpeg >/dev/null || { echo "ffmpeg not found — brew install ffmpeg"; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# A disposable home, so the renders read a seeded configuration and the real
# ~/Library/Application Support/Tessera/config.json is neither read nor written.
export CFFIXED_USER_HOME="$WORK/home"
mkdir -p "$CFFIXED_USER_HOME"

# height=455 is tuned so the settings page — which really does scroll at 380 pt — clips between
# two sections instead of through a sentence. Everything above the clip is the app as it ships.
./scripts/render-ui.sh "$WORK/dark"  dark  docs demo-config height=455 frames
./scripts/render-ui.sh "$WORK/light" light docs demo-config height=455

mkdir -p docs
cp "$WORK/dark/icon.png" docs/icon.png
sips -Z 256 docs/icon.png >/dev/null

swift scripts/compose-docs.swift "$WORK/dark" "$WORK/light" "$WORK"

# JPEG keeps the README light: the composed PNGs are several MB each.
sips -s format jpeg -s formatOptions 82 "$WORK/hero.png"    --out docs/hero.jpg    >/dev/null
sips -s format jpeg -s formatOptions 82 "$WORK/screens.png" --out docs/screens.jpg >/dev/null
# GitHub social preview: 1280×640, has to stay under 1 MB. hero.png is already that shape.
sips -z 640 1280 -s format jpeg -s formatOptions 88 "$WORK/hero.png" --out docs/social-preview.jpg >/dev/null

# One palette for the whole loop, or the gradient background crawls between frames.
ffmpeg -loglevel error -y -framerate 10 -i "$WORK/frames/f%04d.png" \
  -vf "scale=800:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" \
  docs/demo.gif

ls -lh docs/hero.jpg docs/screens.jpg docs/demo.gif docs/social-preview.jpg docs/icon.png
