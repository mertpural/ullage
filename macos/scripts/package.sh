#!/bin/bash
# build/Ullage.zip üretir. Genişletilmiş öznitelikler (._* dosyaları) zip'e girmez, aksi hâlde standart `unzip`
# açınca kod imzası bozulur ve uygulama açılmaz.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build_app.sh
ditto -c -k --norsrc --noextattr --keepParent build/Ullage.app build/Ullage.zip
echo "Hazır: build/Ullage.zip"

# Derleme klasöründe ikinci bir "Ullage.app" kalmasın (Spotlight'ta çift görünür): paketlendikten sonra .app uzantısı kaldırılır.
# Çalıştırdığın uygulama, build_app.sh'ın güncellediği kökteki build/Ullage.app'tir.
rm -rf build/Ullage-build
mv build/Ullage.app build/Ullage-build
