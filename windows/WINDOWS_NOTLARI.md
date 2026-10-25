# Windows notları

Bu dosya Windows sürümünde ne yapıldığını, ne çalışırken görüldüğünü ve nelerin henüz denenmediğini tutar.
Mac tarafına (`macos/`) dokunulmadı. GitHub'a hiçbir şey gönderilmedi, commit'ler yereldir.

## Yapılanlar
- Claude giriş durumu dört ayrı durum olarak tanınıyor: dosya yok, giriş yok (yalnızca MCP), süresi dolmuş, tamam. Popover'da her biri için açık mesaj, "Komutu kopyala" ve "Girişi kontrol et" düğmeleri var.
- Claude kartında cache okuma token'ı ayrı satır olarak gösteriliyor (toplam değişmedi).
- Tepsi simgesi varsayılan olarak uygulamanın logosu: veri göstermiyor, ipucunda da yalnızca "Ullage" yazıyor. Simgeye basınca uygulama penceresi (Kullanım) açılıyor; hızlı görünüm sağ tık menüsünde. Limitler yüzen widget'ta. Ayarlar > Görünüm'den "5s ve haftalık çubuklar" (etiketler büyütüldü, dış çizgili) ve "Tek sayı" seçenekleri de seçilebilir; bu ikisinde simgeye basınca hızlı görünüm açılır.
- Yüzen widget: şeffaf arka planlı yuvarlak kart, her zaman üstte, odak almaz, görev çubuğunda görünmez, sürüklenince konumu kaydedilir. İlk açılışta ekranın sağ üstünde başlar. Ayarlar > Görünüm'den ya da tepsi menüsünden açılıp kapanır.
- Widget'ın arkasındaki dikdörtgen ton farkı giderildi: gölge pencere kenarında kesiliyordu, boşluk genişletildi ve gölge küçültüldü. Widget'ta Claude girişi yoksa ne yapılacağı yazıyor.
- Kullanım sayfasındaki "Cache dahil" seçimi ayarlarda saklanıyor (`usageCache`), kapanıp açılınca korunur ve bugün/dün kartlarına, serilere, ısı haritasına ve grafiğe uygulanır. Windows ve Mac tarafında aynı düzeltme ayrı yapılmıştı; birleştirmede Mac sürümü (yorumsuz) alındı. Aralık, Sağlayıcı/Model ve filtre seçimleri hâlâ her açılışta sıfırlanıyor, popover'daki "Bugün" sayısı cache seçimini izlemiyor.
- `settings.json` UTF-8 BOM'lu yazılırsa artık sessizce sıfırlanmıyor.

## Çalıştığını gördüklerim
- `npm ci`, `npm test`, `node scripts/dump.js` ve `npm run dist` bu bilgisayarda sorunsuz geçti.
- Paketli `Ullage.exe` açılıyor, tepsiye yerleşiyor, popover açılıyor.
- Codex açıkken tepsi çubukları doğru çiziliyor (yakınlaştırılmış görüntüde etiketler okunuyor).
- Widget şeffaf kart olarak görünüyor (köşelerde arka plan duruyor). Fareyle sürüklenince x ve y konumu ayarlara kaydediliyor.
- Giriş durumu ve cache okuma için birim testleri geçiyor.

- Widget boyutu: Ayarlar > Görünüm'de %70 ile %180 arası kaydırıcı. %70, %150 ve %180'de widget'ın doğru boyutta çizildiğini ve %180'de ekran dışına taşmadığını gördüm. Kaydırıcıyı arayüzden sürüklemeyi denemedim, ayarı uygulamanın kendi çağrısıyla değiştirdim.
- Logo modunda tepsi simgesi gizli simgelerde logo olarak görünüyor ve UI Automation ile basınca dashboard penceresi açıldı.

## Claude limiti: yeni yollar (Mac'ten çevrildi)
- **Claude Code komutuyla ölçüm** (`src/main/cliprobe.js`, ayar `cliProbe`, varsayılan açık): Anthropic sorgusu işe yaramazsa, yalnızca yeni yerel Claude kullanımı olunca ve en sık 5 dakikada bir (aday olma eşiği: değer 90 saniyeden eskiyse, durum satırı dosyasından gelen değer için 15 dakikadan; sıklığı yalnızca 5 dakikalık kalıcı sınır belirler) `claude -p ...` çalıştırılıp `rate_limit_event` satırındaki `unifiedWindows` okunur. Sorgu zamanları (`claudeLastProbe`) kalıcı. Birim testleri geçiyor.
  - **Gerçek denemede (Claude Code 2.1.310'a güncellendikten sonra) çalıştı:** komut 5-6 saniyede çalışıyor (Windows'ta .cmd, kabuk üzerinden), `rate_limit_event` içinde `unifiedWindows` geliyor. Uygulama 5 saatlik %10-11 ve haftalık %71 kalan gösterdi, etiket "Kesin", not "Limit: Claude Code komutundan ölçüldü". Hemen ardından ikinci okumada yeni ölçüm yapılmadı, kalıcı zaman damgası ve `claudeLast` kaydı doğru. **Eski Claude Code 2.1.218'de `unifiedWindows` yok:** olay gelir ama yüzde yok, sonuç boş kalır ve bir saat tekrar denenmez. Uygulamayı kullanırken limitin canlı güncellenmesi (Claude uygulaması dahil) etkileşimli olarak denenmedi.
  - `macos/.../CLIProbe.swift` Mac'ten gelen zipte yoktu, tarif mesajdan alındı.
- **Durum satırından okuma** (`src/main/statusline.js`, Bildirim ve otomasyon'da "Claude limitini Claude Code'dan al", varsayılan kapalı): betik `statusline.ps1` (PowerShell, yalnızca ASCII), komut `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "<yol>/statusline.ps1"`. Claude Code komutları Windows'ta **Git Bash** ile çalıştırıyor (kanca testiyle görüldü); yolda boşluk olsa da komut çalıştı. Ayar dosyası yedeği, başka durum satırına dokunmama ve kaldırma birim testlerinde ve arayüzde (sahte kullanıcı klasörüyle) denendi.
  - **Gerçek durum satırı çalıştırması denenmedi:** Claude Code'un etkileşimli oturumunu otomatik süremedim (ilk açılış sorusunda kaldı) ve `rate_limits` alanının gerçekten gelip gelmediği görülmedi.
- Anthropic sorgusu artık kullanıma bağlı: yeni yerel Claude kullanımı varsa en sık dakikada bir, yoksa 10 dakikada bir. Eski değer "Tahmini" sayılmadan önce, değerden sonra yerel kullanım olması da aranıyor (Mac ile aynı).
- **`claude` komutunu bulma** (`src/main/claudebin.js`): komut PATH'te yoksa Claude Desktop uygulamasının kendi içindeki `claude.exe` aranır (Mac karşılığı `Automation.swift` içindeki `desktopBundled`; o dosya Mac'ten gelen zipte yoktu, tarif mesajdan alındı). Bakılan yerler: `%APPDATA%\Claude\claude-code\<sürüm>\...`, `%LOCALAPPDATA%\Claude-Data\<paket>\claude-code\<sürüm>\...` (Mağaza/MSIX kurulumu, bu bilgisayardaki yer) ve `%LOCALAPPDATA%\Packages\Claude_*\LocalCache\Roaming\Claude\claude-code\...`; en yüksek sürüm sayısal karşılaştırmayla seçilir. Hem komutla ölçüm hem oturum yenileme bunu kullanır. Hiçbir yerde yoksa hiçbir şey çalıştırılmaz ve ölçüm sayacı harcanmaz.
  - Gerçek denemede PATH'ten `claude` çıkarıldı, uygulama Desktop'ın `claude.exe` dosyasını (2.1.308) buldu ve 4,7 saniyede ölçtü (5 saatlik %2, haftalık %70 kalan). Birim testleri (sürüm sırası, üç klasör düzeni, PATH önceliği, komut satırı tırnakları) geçiyor.

## Henüz denenmedi
- Claude limiti: bu bilgisayarda Claude Code'a `/login` ile giriş yapılmadığı için gerçek limit verisi görülmedi.
- Popover'daki giriş mesajı ve düğmelerin ekranda görünüşü ve kopyalama düğmesi.
- Ayarlar > Görünüm sayfasındaki tepsi ve widget kontrolleri (widget'ı ayar dosyasından açtım, arayüzden değil), tepsi menüsündeki "Yüzen widget" kutusu.
- Widget'ın sağ üst varsayılan konumu görsel olarak kontrol edilmedi, yalnızca kod okundu.
- Widget'ın tam ekran oyunların üstünde kalıp kalmadığı.
- Açık renkli görev çubuğunda tepsi etiketlerinin okunurluğu, %125 ve %150 ekran ölçeklemesi.
- Kartın dışındaki şeffaf boşluktan tıklamaların alttaki pencereye geçmesi: ilk denemede sürükleme çalışmadı, bu özelliği kaldırınca çalıştı. Asıl sebebin bu olup olmadığı ayrıca doğrulanmadı. Kart ile pencere arasında yalnızca 6 px boşluk var.
