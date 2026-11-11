# Ullage

Yapay zeka araçlarında **ne kadar hakkın kaldığını** Mac'in üst menü çubuğundan gösteren küçük bir uygulama.
5 saatlik ve haftalık limitini, harcadığın token'ı ve geçmiş kullanımını tek yerden görürsün.

## ⬇️ İndir

| | Dosya |
|---|---|
| **macOS** (Apple Silicon ve Intel) | [Ullage.zip](https://github.com/mertpural/ullage/releases/latest/download/Ullage.zip) |

Uygulama imzasız olduğu için ilk açılışta bir uyarı çıkar, bir kere onaylaman yeter (aşağıda).

## Ne yapıyor?

- Menü çubuğunda `5s 77%  H 48%` gibi görünür: 5 saatlik ve haftalık kalan hakkın ayrı ayrı. Gösterimi (yüzde, çubuk, halka, pil...) sen seçersin.
- Tıklayınca hakkın ne zaman yenileneceğini ve şu tempoyla gidersen yetip yetmeyeceğini gösterir ("Bu hızla biter: 19:40").
- **Kullanım** sayfası: GitHub'daki katkı tablosuna benzer etkinlik tablosu, seri sayacı, günlük/haftalık/aylık token grafikleri, en çok kullandığın projeler, API fiyatıyla tahmini maliyet.
- "Cache dahil" seçimi: açarsan her yerdeki toplamlar cache okumalarını da sayar.
- CSV olarak dışa aktarma ve paylaşabileceğin haftalık özet kartı (resim).
- 9 tema, hakkın azalınca bildirim, Pazartesi sabahı haftalık özet, Türkçe ve İngilizce arayüz.
- Hiçbir veri bir yere gönderilmez. Her şey kendi bilgisayarında, kendi hesabınla okunur.

Desteklenenler: **Claude, Codex, Antigravity** (Gemini de hesabında Code Assist lisansı varsa, şimdilik yalnızca Mac'te).

## Kurulum

### Mac (macOS 14 veya üstü)

1. Zip'i aç, `Ullage.app`'i **Uygulamalar** klasörüne sürükle.
2. Uygulamaya **sağ tıkla → Aç → Aç** de (imzasız olduğu için ilk seferde gerekir).
3. İlk açılışta macOS birkaç izin sorar. Hepsine "İzin Ver" de:
   - **Bildirimler** (hakkın azalınca haber vermesi için).
   - **Anahtar zinciri** (Claude Code girişini okumak için). Çıkarsa "Her Zaman İzin Ver".
   - **Belgeler klasörü** (Claude komutu çalışırken sorabilir).
4. Uygulama açılışta Sağlayıcılar sayfasındaki **Kurulum kontrolü**nü gösterir; neyin eksik olduğunu orada görürsün.

Terminalden tek satır:

```bash
curl -L https://github.com/mertpural/ullage/releases/latest/download/Ullage.zip -o /tmp/Ullage.zip \
  && unzip -q -o /tmp/Ullage.zip -d /Applications \
  && xattr -cr /Applications/Ullage.app \
  && open /Applications/Ullage.app
```

Kendin derlemek istersen (Xcode'un tamamı gerekmez, `xcode-select --install` yeter):

```bash
git clone https://github.com/mertpural/ullage.git
cd ullage/macos
./scripts/build_app.sh
```

## Limitler nereden geliyor?

| Araç | Limit | Token |
|---|---|---|
| Claude | Claude Code komutu ve Anthropic'in kullanım bilgisi (Claude Code ya da Claude uygulaması girişinle) | `~/.claude` klasörü |
| Codex | `~/.codex` klasörü | aynı yer |
| Antigravity | IDE açıkken yerel sunucusu | yerel konuşma kayıtları |
| Gemini | Google kota bilgisi (Gemini CLI girişinle, lisans gerekir) | yok |

**Claude'un limiti nasıl okunuyor?** Üç yoldan biri, sırayla denenir:
1. Claude Code'un durum satırı (Bildirim ve otomasyon'dan açarsan): her cevaptan sonra yerel dosyaya yazılır, ağ gerekmez.
2. Anthropic'in kullanım bilgisi: resmi olmayan bir adres, hız sınırına takılabilir.
3. Claude Code komutu: tek satırlık küçük bir Haiku isteği atıp limiti ölçer. Yalnızca yeni kullanım olunca ve en sık 5 dakikada bir yapılır. Terminal gerekmez.

Hiçbiri alınamazsa son bilinen değer "Tahmini" diye gösterilir. Olmayan veri uydurulmaz: Ayarlar > Sağlayıcılar sayfasında her veri "Kesin / Tahmini / Veri yok" diye yazılır.

## Limit görünmüyorsa

- **Claude:** Claude Code ya da Claude uygulamasında giriş yapılı olmalı. Terminalde `claude` yazıp `/login` diyebilirsin.
- **Codex:** Kayıtlar sıkıştırılmışsa `brew install zstd` gerekir (Mac).
- **Antigravity:** IDE açıkken okunur.
- **Gemini:** `npm i -g @google/gemini-cli` ile kurup bir kez giriş yap.
- Sağlayıcılar sayfasındaki **Kurulum kontrolü** bunların hangisinin eksik olduğunu gösterir.

## Notlar

- Claude'un limit bilgisi resmi olmayan yollardan alınıyor, ileride değişebilir.
- Tahmini maliyet üçüncü taraf fiyat listelerine dayanır, yaklaşıktır; abonelik ücretini göstermez.
- Logolar [lobe-icons](https://github.com/lobehub/lobe-icons) paketinden. Marka hakları sahiplerine ait.
- Bu proje Anthropic, OpenAI veya Google ile bağlantılı değil.

## Lisans

MIT
