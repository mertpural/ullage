# Ullage

Yapay zeka araçlarında **ne kadar hakkın kaldığını** Mac'in üst menü çubuğundan gösteren küçük bir uygulama.
5 saatlik ve haftalık limitini, harcadığın token'ı ve geçmiş kullanımını tek yerden görürsün.

## ⬇️ İndir

**[Ullage.zip'i indir (macOS)](https://github.com/mertpural/ullage/releases/latest/download/Ullage.zip)**

İndirince zip'i aç, `Ullage.app`'i Uygulamalar klasörüne at, bitti.

> İlk açılışta Mac "tanınmayan geliştirici" diyebilir. Uygulamaya **sağ tıkla → Aç → Aç** de, bir kere yeterli.

## Ne yapıyor?

- Menü çubuğunda `5s 77%  H 48%` gibi görünür: 5 saatlik ve haftalık kalan hakkın ayrı ayrı. Gösterimi (yüzde, çubuk, halka, pil...) sen seçersin.
- Tıklayınca hakkın ne zaman yenileneceğini ve şu tempoyla gidersen yetip yetmeyeceğini gösterir.
- Kullanım sayfasında GitHub'daki katkı tablosuna benzer bir etkinlik tablosu, seri sayacı ve günlük/haftalık/aylık token grafikleri var.
- 9 farklı tema, bildirimler (hakkın azalınca haber verir) ve ayarlanabilir yenileme süresi.
- Hiçbir veri bir yere gönderilmez. Her şey kendi bilgisayarında, kendi hesabınla okunur.

Desteklenenler: **Claude, Codex, Antigravity** (Gemini de hesabında Code Assist lisansı varsa).

## Kurulum

Gereksinim: macOS 14 veya üstü (Apple Silicon ve Intel ikisi de olur).

### Yol 1: Zip ile (en kolayı)
Yukarıdaki indir bağlantısına tıkla, zip'i aç, `Ullage.app`'i Uygulamalar'a taşı.

### Yol 2: Terminalden tek satır

```bash
curl -L https://github.com/mertpural/ullage/releases/latest/download/Ullage.zip -o /tmp/Ullage.zip \
  && unzip -q -o /tmp/Ullage.zip -d /Applications \
  && xattr -cr /Applications/Ullage.app \
  && open /Applications/Ullage.app
```

Güncellemek için aynı komutu tekrar çalıştır. Silmek için `/Applications/Ullage.app`'i çöpe at.

### Yol 3: Kendin derle

```bash
git clone https://github.com/mertpural/ullage.git
cd ullage/macos
./scripts/build_app.sh
open build/Ullage.app
```

Xcode'un tamamı gerekmez, `xcode-select --install` ile gelen komut satırı araçları yeter.

## Bilgileri nereden alıyor?

| Araç | Limit | Token |
|---|---|---|
| Claude | Anthropic'in kullanım bilgisi (Claude Code girişinle) | `~/.claude` klasörü |
| Codex | `~/.codex` klasörü | aynı yer |
| Antigravity | IDE açıkken yerel sunucusu | yerel konuşma kayıtları |
| Gemini | Google kota bilgisi (Gemini CLI girişinle, lisans gerekir) | yok |

Ek olarak:
- Claude için Mac'in anahtar zinciri izin ister, **"Her Zaman İzin Ver"** de.
- Codex kayıtlarını okumak için `brew install zstd` gerekir.
- Gemini için Gemini CLI kurulu ve girişli olmalı (`npm i -g @google/gemini-cli`).

Alınamayan ya da tahmini olan veriler Ayarlar > Sağlayıcılar sayfasında "Kesin / Tahmini / Veri yok" diye açıkça yazar. Olmayan veri uydurulmaz.

## Windows

Windows sürümü geliyor, çok yakında. Bkz. [`windows/`](windows).

## Notlar

- Claude'un limit bilgisi resmi olmayan bir yoldan alınıyor, ileride değişebilir.
- Logolar [lobe-icons](https://github.com/lobehub/lobe-icons) paketinden. Marka hakları sahiplerine ait.
- Bu proje Anthropic, OpenAI veya Google ile bağlantılı değil.

## Lisans

MIT
