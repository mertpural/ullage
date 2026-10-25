#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Hem Apple Silicon hem Intel Mac'lerde çalışsın diye universal derlenir; olmazsa yalnızca bu Mac'in mimarisi.
if swift build -c release --arch arm64 --arch x86_64 2>/dev/null; then
  BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/AILimit
else
  swift build -c release
  BIN=$(swift build -c release --show-bin-path)/AILimit
fi

APP_NAME="Ullage"
APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/AILimit"
mkdir -p "$APP/Contents/Resources"
cp -R Resources/Logos "$APP/Contents/Resources/Logos"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Ullage</string>
    <key>CFBundleDisplayName</key><string>Ullage</string>
    <key>CFBundleIdentifier</key><string>com.mertpural.ailimit</string>
    <key>CFBundleExecutable</key><string>AILimit</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.2.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

# Her derlemede aynı kimlikle imzalanır: macOS izinleri (Belgeler, bildirim vb.) uygulamanın kimliğine bağlar, kimlik
# her seferinde değişirse her yeni sürümde izinler yeniden sorulur. "Ullage Local Signing" yerel bir sertifikadır
# (anahtarlıkta yoksa geçici imzaya düşülür; o durumda izinler her derlemede yeniden sorulur).
SIGN_ID="-"
if security find-identity -p codesigning 2>/dev/null | grep -q "Ullage Local Signing"; then SIGN_ID="Ullage Local Signing"; fi
if ! codesign --force --sign "$SIGN_ID" "$APP" >/dev/null 2>&1; then
  echo "Uyarı: '$SIGN_ID' ile imzalanamadı, geçici imza kullanılıyor"
  codesign --force --sign - "$APP" >/dev/null 2>&1 || true
fi
echo "İmza: $SIGN_ID"
echo "Hazır: $APP"

# Kullanıcının açtığı uygulama /Applications içindedir (Belgeler gibi korumalı klasörlerde izin sorulur).
# Orada varsa yeni sürüm onun üzerine yazılır; böylece tek kopya kalır.
INSTALLED="/Applications/$APP_NAME.app"
if [ -d "$INSTALLED" ]; then
  ditto --norsrc --noextattr "$APP" "$INSTALLED"
  xattr -cr "$INSTALLED" 2>/dev/null || true   # Finder bilgisi imzayı bozar
  echo "Kurulu uygulama güncellendi: $INSTALLED"
  # Derleme çıktısı ikinci bir "Ullage.app" olarak kalmasın (Spotlight'ta çift görünür). Paketleme zip için ona ihtiyaç duyar.
  if [ -z "${ULLAGE_PACKAGING:-}" ]; then
    rm -rf build/stage
    mv "$APP" build/stage
  fi
fi
