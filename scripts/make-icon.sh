#!/bin/bash
# Render the Voice Dictator app icon and assemble Resources/AppIcon.icns.
# Draws a 1024 master (scripts/make-icon.swift), downscales to every iconset
# size with sips, then packs them with iconutil. Run this once; install.sh picks
# up the resulting .icns. Re-run after changing the icon design.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p Resources
WORK="$(mktemp -d)"
MASTER="$WORK/AppIcon-1024.png"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

echo "Rendering 1024 master…"
swift scripts/make-icon.swift "$MASTER"

echo "Generating iconset sizes…"
# name                 size
gen() { sips -z "$2" "$2" "$MASTER" --out "$ICONSET/$1" >/dev/null; }
gen icon_16x16.png        16
gen icon_16x16@2x.png     32
gen icon_32x32.png        32
gen icon_32x32@2x.png     64
gen icon_128x128.png      128
gen icon_128x128@2x.png   256
gen icon_256x256.png      256
gen icon_256x256@2x.png   512
gen icon_512x512.png      512
cp "$MASTER" "$ICONSET/icon_512x512@2x.png"   # 1024

echo "Packing .icns…"
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
