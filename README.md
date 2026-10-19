# Ullage

Mac menü çubuğunda yapay zekâ araçlarının **5 saatlik ve haftalık limitini** ve **token kullanımını** gösteren küçük bir uygulama.
Claude, Codex ve Antigravity desteklenir (Gemini CLI kotası, hesabında Code Assist lisansı varsa).

- Menü çubuğunda `5s 77%  H 48%`: 5 saatlik ve haftalık kalan limit ayrı ayrı, göstergesini (yüzde, çubuk, halka, pil, segment) sen seçersin.
- Popover: sıfırlanma geri sayımı, tempo göstergesi ("Rahat / Dengeli / Hızlı"), son 7 günün token grafiği.
- Kullanım penceresi: GitHub tarzı etkinlik tablosu, seri sayacı, gün/hafta/ay grafikleri, sağlayıcıya ve modele göre dağılım.
- 9 tema, bildirimler, ayarlanabilir yenileme aralığı.
- Veri kalıcı: log dosyaları silinse bile geçmiş kendi veritabanında kalır.

Hiçbir veri bir sunucuya gönderilmez. Her şey kendi Mac'inde, kendi oturumlarınla okunur.

## Kurulum (macOS)

Gereksinim: macOS 14 veya üstü, Apple Silicon ya da Intel.

### 1. Uygulama olarak indir (en kolayı)

1. [Releases](https://github.com/Piercies3sc/ullage/releases/latest) sayfasından **`Ullage.zip`** dosyasını indir ve aç.
2. `Ullage.app`'i **Uygulamalar** klasörüne sürükle.
3. Uygulama imzasız olduğu için macOS ilk açılışta engelleyebilir. Uygulamaya **sağ tıkla → Aç → Aç** de (bir kez yeterli).
4. Menü çubuğunda belirir.

### 2. Terminalden tek satırla kur

```bash
curl -L https://github.com/Piercies3sc/ullage/releases/latest/download/Ullage.zip -o /tmp/Ullage.zip \
  && unzip -q -o /tmp/Ullage.zip -d /Applications \
  && xattr -cr /Applications/Ullage.app \
  && open /Applications/Ullage.app
```

Güncellemek için aynı komutu tekrar çalıştır. Kaldırmak için `/Applications/Ullage.app`'i sil.

### 3. Kaynaktan derle

```bash
git clone https://github.com/Piercies3sc/ullage.git
cd ullage/macos
./scripts/build_app.sh        # build/Ullage.app üretir
open build/Ullage.app
```

Xcode'un tamamı gerekmez, Command Line Tools (`xcode-select --install`) yeterlidir.

## Windows

Windows sürümü [`windows/`](windows) klasöründe geliştirilecek. Henüz hazır değil.

## Verileri nereden okur

| Sağlayıcı | Limit | Token |
|---|---|---|
| Claude | Anthropic kullanım uç noktası (Claude Code oturumunla; Keychain izni ister, "Her Zaman İzin Ver" de) | `~/.claude` kayıtları |
| Codex | `~/.codex` oturum kayıtları | aynı kayıtlar |
| Antigravity | IDE açıkken yerel dil sunucusu | yerel konuşma veritabanı (alan eşlemesi tahmini) |
| Gemini | Google Code Assist kota API'si (Gemini CLI oturumunla, lisans gerekir) | yok |

Ek gereksinimler:
- Codex kayıtları sıkıştırılmıştır: `brew install zstd`.
- Gemini oturumunu yenilemek için Gemini CLI kurulu olmalı: `npm i -g @google/gemini-cli`.

Veri alınamayan ya da tahmini olan her şey Ayarlar > Sağlayıcılar sayfasında açıkça "Kesin / Tahmini / Veri yok" etiketiyle gösterilir. Uydurma değer gösterilmez.

## Notlar

- Claude limit uç noktası resmi olmayan bir arayüzdür ve değişebilir.
- Sağlayıcı logoları [lobehub/lobe-icons](https://github.com/lobehub/lobe-icons) paketinden alınmıştır; marka hakları sahiplerine aittir.
- Bu proje Anthropic, OpenAI, Google ile bağlantılı değildir.

## Lisans

MIT
