#!/bin/bash
# Güncelleme bilgi dosyasını (site/latest.json) üretir. Uygulama bu dosyaya günde bir kez bakar.
# Kullanım: macos/scripts/make_update.sh <zip> "<sürüm notu>"
# Zip, siteye (site/downloads/Ullage.zip) konduktan sonra çalıştırılır; sürüm ve SHA-256 zip'ten okunur.
set -euo pipefail
cd "$(dirname "$0")/../.."
ZIP="${1:?zip yolu gerekli}"
NOTES="${2:-}"
BASE="${ULLAGE_SITE_URL:-https://ullage-app.netlify.app}"
VER=$(unzip -p "$ZIP" Ullage.app/Contents/Info.plist | plutil -extract CFBundleShortVersionString raw -o - -)
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
python3 - "$VER" "$BASE/downloads/Ullage.zip" "$SHA" "$NOTES" > site/latest.json <<'PY'
import json,sys
print(json.dumps({"version":sys.argv[1],"url":sys.argv[2],"sha256":sys.argv[3],"notes":sys.argv[4]},ensure_ascii=False,indent=2))
PY
cp site/latest.json site-lite/latest.json 2>/dev/null || true
echo "site/latest.json: sürüm $VER, sha256 ${SHA:0:12}…"
