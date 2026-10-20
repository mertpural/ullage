# Ullage — Windows

Windows sistem tepsisinde (saatin yanında) yapay zeka araçlarının **5 saatlik ve haftalık hakkını** gösteren sürüm.
Mac sürümüyle aynı: aynı veri, aynı temalar, aynı Kullanım sayfası.

## İndir

- **[Ullage-Setup.exe](https://github.com/mertpural/ullage/releases/latest/download/Ullage-Setup.exe)**: kurulum dosyası (çift tıkla, kurulur)
- **[Ullage-Portable.exe](https://github.com/mertpural/ullage/releases/latest/download/Ullage-Portable.exe)**: kurulum istemez, çift tıkla çalışır

> Uygulama imzasız olduğu için Windows "Bilgisayarınızı korudu" (SmartScreen) uyarısı çıkarabilir.
> **Ek bilgi → Yine de çalıştır** de, bir kere yeterli.

## Ne yapıyor?

- Tepsideki simgede en düşük kalan hakkın yüzdesi görünür. Rengi durumu gösterir (yeşil, turuncu, kırmızı).
- Simgeye tıklayınca popover açılır: Claude, Codex, Antigravity için 5 saatlik ve haftalık hak, sıfırlanma süresi, tempo göstergesi, son 7 günün token grafiği.
- Simgeye sağ tık → **Kullanım**: GitHub tarzı etkinlik tablosu, seri sayacı, gün/hafta/ay grafikleri.
- 9 tema, hakkın azalınca bildirim, ayarlanabilir yenileme süresi (15 saniyeden 15 dakikaya).
- Hiçbir veri bir yere gönderilmez; her şey kendi bilgisayarında, kendi hesabınla okunur.

## Bilgileri nereden alıyor?

| Araç | Limit | Token |
|---|---|---|
| Claude | Anthropic'in kullanım bilgisi (Claude Code girişinle, `%USERPROFILE%\.claude\.credentials.json`) | `%USERPROFILE%\.claude\projects` |
| Codex | `%USERPROFILE%\.codex\sessions` | aynı yer |
| Antigravity | IDE açıkken yerel sunucusu | yerel konuşma kayıtları |

Gemini Windows sürümünde henüz yok.

## Durum

Windows sürümünün ilk hali. Veri okuma mantığı macOS sürümüyle aynı sonuçları veriyor (birebir karşılaştırıldı),
ama Windows'ta henüz gerçek bir bilgisayarda denenmedi. Bir sorun görürsen [issue](https://github.com/mertpural/ullage/issues) aç.

## Kendin derle

Node.js 22 veya üstü gerekir.

```bash
cd windows
npm install
npm start          # çalıştırır
npm test           # birim testleri
npm run dist       # dist/ klasörüne .exe üretir (Windows'ta)
```
