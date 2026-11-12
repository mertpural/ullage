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
- **GitHub profil kartı** (isteğe bağlı): token kullanım ısı haritanı kendi profil reposuna bir resim olarak koyar ve günde bir güncel tutar. Ayarlar > Otomasyon'dan açılır.
- Hiçbir veri bir yere gönderilmez. Her şey kendi bilgisayarında, kendi hesabınla okunur. (Profil kartını açarsan yalnızca günlük toplam token'ın kendi GitHub reposuna gider.)

<p align="center"><img src="docs/profil-karti.svg" alt="Ullage GitHub profil kartı" width="100%"></p>

### Desteklenen araçlar

| Araç | Ne gösterir | Nasıl okunur |
|---|---|---|
| **Claude** (Claude Code ve Claude uygulaması) | Kalan 5 saatlik ve haftalık limit, token | `~/.claude` kayıtları, limit için Claude Code'un kendi oturumu |
| **Codex** | Kalan 5 saatlik ve haftalık limit, token | `~/.codex/sessions` kayıtları |
| **Antigravity** | Kalan limit (IDE açıkken), token | Uygulamanın kendi yerel sunucusu ve kayıtları |
| **Gemini** (Code Assist lisansı varsa) | Günlük kota | Gemini CLI girişi |
| **OpenCode** | Yalnızca token | `~/.local/share/opencode` kayıtları |
| **Kimi CLI** | Yalnızca token | `~/.kimi/sessions` kayıtları |
| **Cline / Roo Code** (VS Code, Cursor, Windsurf, VSCodium) | Yalnızca token | Eklentinin kendi görev klasörleri |

İlk dört araç her zaman listede durur. **OpenCode, Kimi ve Cline yalnızca bilgisayarında izi varsa görünür:** kayıt klasörü yoksa Ullage onları hiç göstermez, ayarlarda da çıkmaz. Kullanmaya başlayınca kendiliğinden **Sağlayıcılar** sayfasında belirir. Menü çubuğunda ve açılır pencerede görünmesi için oradan açman gerekir, kendiliğinden eklenmezler.

Bu üç araçta kalan limit okunmaz, çünkü genelde kendi API anahtarınla çalışırlar. Ullage yalnızca harcadığın token'ı sayar; kartlarda, kullanım sayfasında ve etkinlik tablosunda diğer araçlarla birlikte görünür. Kayıt biçimleri belgelerden alındı ve henüz gerçek kurulumlarla denenmedi; araç güncellenip biçimi değiştirirse ilgili kayıtlar sessizce atlanır, uygulama etkilenmez.

Diğer web siteleri (ChatGPT, Perplexity, Grok gibi) bilgisayarda kayıt bırakmadığı için desteklenmiyor.

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
