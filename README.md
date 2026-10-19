# Ullage

Mac menü çubuğunda yapay zekâ araçlarının **5 saatlik ve haftalık limitini** ve **token kullanımını** gösteren küçük bir uygulama.
Claude, Codex ve Antigravity desteklenir (Gemini CLI kotası, hesabında Code Assist lisansı varsa).

- Menü çubuğunda `5s 77%  H 48%`: 5 saatlik ve haftalık kalan limit ayrı ayrı, göstergesini (yüzde, çubuk, halka, pil, segment) sen seçersin.
- Popover: sıfırlanma geri sayımı, tempo göstergesi ("Rahat / Dengeli / Hızlı"), son 7 günün token grafiği.
- Kullanım penceresi: GitHub tarzı etkinlik tablosu, seri sayacı, gün/hafta/ay grafikleri, sağlayıcıya ve modele göre dağılım.
- 9 tema, bildirimler, ayarlanabilir yenileme aralığı.
- Veri kalıcı: log dosyaları silinse bile geçmiş kendi veritabanında kalır.

Hiçbir veri bir sunucuya gönderilmez. Her şey kendi Mac'inde, kendi oturumlarınla okunur.

## Kurulum

1. [Releases](../../releases) sayfasından `Ullage.zip` dosyasını indir ve aç.
2. `Ullage.app`'i Uygulamalar klasörüne taşı.
3. Uygulama imzasız olduğu için macOS ilk açılışta engelleyebilir. Şunlardan birini yap:
   - Uygulamaya **sağ tıkla → Aç → Aç**, ya da
   - Terminal'de: `xattr -cr /Applications/Ullage.app`
4. Menü çubuğunda belirir.

Gereksinim: macOS 14 veya üstü.

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

## Kaynaktan derleme

```bash
git clone <bu-depo>
cd <depo>
./scripts/build_app.sh        # build/Ullage.app üretir
```

Xcode'un tamamı gerekmez, Command Line Tools (`xcode-select --install`) yeterlidir.

## Notlar

- Claude limit uç noktası resmi olmayan bir arayüzdür ve değişebilir.
- Sağlayıcı logoları [lobehub/lobe-icons](https://github.com/lobehub/lobe-icons) paketinden alınmıştır; marka hakları sahiplerine aittir.
- Bu proje Anthropic, OpenAI, Google ile bağlantılı değildir.

## Lisans

MIT
