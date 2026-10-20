#!/bin/bash
# build/Ullage.zip üretir. Genişletilmiş öznitelikler (._* dosyaları) zip'e girmez, aksi hâlde standart `unzip`
# açınca kod imzası bozulur ve uygulama açılmaz.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build_app.sh
ditto -c -k --norsrc --noextattr --keepParent build/Ullage.app build/release-mac.zip
echo "Hazır: build/release-mac.zip (GitHub'a yüklerken Ullage.zip adıyla kopyalanır)"

# Derleme klasöründe "Ullage" adlı ikinci bir şey kalmasın (Spotlight'ta çift görünür): paketlendikten sonra klasör "stage" olur.
# Çalıştırdığın uygulama, build_app.sh'ın güncellediği kökteki build/Ullage.app'tir.
rm -rf build/stage
mv build/Ullage.app build/stage
