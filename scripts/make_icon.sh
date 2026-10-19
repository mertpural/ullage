#!/bin/bash
# LogoMark'tan uygulama ikonunu (Resources/AppIcon.icns) üretir. Önce `scripts/build_app.sh` çalışmış olmalı.
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="build/Ullage.app/Contents/MacOS/AILimit"
AILIMIT_ICON="$PWD/Resources/icon_1024.png" "$BIN"

SET="build/AppIcon.iconset"
rm -rf "$SET"; mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/icon_1024.png --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/icon_1024.png --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "Hazır: Resources/AppIcon.icns"
