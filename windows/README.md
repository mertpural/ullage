# Ullage — Windows

Windows sistem tepsisinde (saatin yanında) yapay zeka araçlarının **5 saatlik ve haftalık hakkını** gösteren sürüm.
Mac sürümüyle aynı: aynı veri, aynı temalar, aynı Kullanım sayfası.

## İndir

- **[Ullage-Setup.exe](https://github.com/mertpural/ullage/releases/latest/download/Ullage-Setup.exe)**: kurulum dosyası (çift tıkla, kurulur)
- **[Ullage-Portable.exe](https://github.com/mertpural/ullage/releases/latest/download/Ullage-Portable.exe)**: kurulum istemez, çift tıkla çalışır

> Uygulama imzasız olduğu için Windows "Bilgisayarınızı korudu" (SmartScreen) uyarısı çıkarabilir.
> **Ek bilgi → Yine de çalıştır** de, bir kere yeterli.

## Ne yapıyor?

- Tepsideki simge varsayılan olarak Ullage logosu. Simgeye basınca **Kullanım** penceresi açılır; hızlı görünüm sağ tık menüsünde. Limitleri her zaman görmek için Ayarlar > Görünüm'den **yüzen widget**'ı aç (küçük, şeffaf, her zaman üstte, sürüklenebilir, boyutu ayarlanır). Tepsiye `5s ve haftalık çubuklar` ya da `tek sayı` da koyabilirsin.
- Popover: Claude, Codex, Antigravity için 5 saatlik ve haftalık hak, sıfırlanma süresi, tempo göstergesi, son 7 günün token grafiği.
- Kullanım sayfası: GitHub tarzı etkinlik tablosu, seri sayacı, gün/hafta/ay grafikleri, "Cache dahil" seçimi (kalıcı).
- 9 tema, hakkın azalınca bildirim, ayarlanabilir yenileme süresi (15 saniyeden 15 dakikaya).
- Claude limiti için Claude Code komutu ya da (isteğe bağlı) Claude Code'un durum satırı kullanılır; terminal gerekmez.
- Hiçbir veri bir yere gönderilmez; her şey kendi bilgisayarında, kendi hesabınla okunur.

## Bilgileri nereden alıyor?

| Araç | Limit | Token |
|---|---|---|
| Claude | Anthropic'in kullanım bilgisi (Claude Code girişinle, `%USERPROFILE%\.claude\.credentials.json`) | `%USERPROFILE%\.claude\projects` |
| Codex | `%USERPROFILE%\.codex\sessions` | aynı yer |
| Antigravity | IDE açıkken yerel sunucusu | yerel konuşma kayıtları |

Gemini Windows sürümünde henüz yok.

## Durum

Bir Windows 11 bilgisayarında denendi (kurulum, tepsi, widget, limit ölçümü). Yine de farklı ekran ölçeklemeleri (%125, %150), açık renkli görev çubuğu ve tam ekran oyunlarda widget davranışı henüz denenmedi. Bir sorun görürsen [issue](https://github.com/mertpural/ullage/issues) aç.

**Limit görünmüyorsa:** terminalde `claude` yazıp `/login` ile giriş yap; Claude Desktop kullanıyorsan onda giriş yapılı olması yeter.

## Kendin derle

Node.js 22 veya üstü gerekir.

```bash
cd windows
npm install
npm start          # çalıştırır
npm test           # birim testleri
npm run dist       # dist/ klasörüne .exe üretir (Windows'ta)
```
