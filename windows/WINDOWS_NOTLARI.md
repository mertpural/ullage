# Windows notları

Bu dosya Windows sürümünde ne yapıldığını, ne çalışırken görüldüğünü ve nelerin henüz denenmediğini tutar.
Mac tarafına (`macos/`) dokunulmadı. GitHub'a hiçbir şey gönderilmedi, commit'ler yereldir.

## Yapılanlar
- Claude giriş durumu dört ayrı durum olarak tanınıyor: dosya yok, giriş yok (yalnızca MCP), süresi dolmuş, tamam. Popover'da her biri için açık mesaj, "Komutu kopyala" ve "Girişi kontrol et" düğmeleri var.
- Claude kartında cache okuma token'ı ayrı satır olarak gösteriliyor (toplam değişmedi).
- Tepsi simgesi: varsayılan olarak 5 saatlik ve haftalık en düşük kalan limit iki çubuk olarak çiziliyor, etiketler büyütüldü ve dış çizgili. "Tek sayı" modu seçenek olarak duruyor.
- Yüzen widget: şeffaf arka planlı yuvarlak kart, her zaman üstte, odak almaz, görev çubuğunda görünmez, sürüklenince konumu kaydedilir. İlk açılışta ekranın sağ üstünde başlar. Ayarlar > Görünüm'den ya da tepsi menüsünden açılıp kapanır.
- Widget'ın arkasındaki dikdörtgen ton farkı giderildi: gölge pencere kenarında kesiliyordu, boşluk genişletildi ve gölge küçültüldü. Widget'ta Claude girişi yoksa ne yapılacağı yazıyor.
- `settings.json` UTF-8 BOM'lu yazılırsa artık sessizce sıfırlanmıyor.

## Çalıştığını gördüklerim
- `npm ci`, `npm test`, `node scripts/dump.js` ve `npm run dist` bu bilgisayarda sorunsuz geçti.
- Paketli `Ullage.exe` açılıyor, tepsiye yerleşiyor, popover açılıyor.
- Codex açıkken tepsi çubukları doğru çiziliyor (yakınlaştırılmış görüntüde etiketler okunuyor).
- Widget şeffaf kart olarak görünüyor (köşelerde arka plan duruyor). Fareyle sürüklenince x ve y konumu ayarlara kaydediliyor.
- Giriş durumu ve cache okuma için birim testleri geçiyor.

## Henüz denenmedi
- Claude limiti: bu bilgisayarda Claude Code'a `/login` ile giriş yapılmadığı için gerçek limit verisi görülmedi.
- Popover'daki giriş mesajı ve düğmelerin ekranda görünüşü ve kopyalama düğmesi.
- Ayarlar > Görünüm sayfasındaki tepsi ve widget kontrolleri (widget'ı ayar dosyasından açtım, arayüzden değil), tepsi menüsündeki "Yüzen widget" kutusu.
- Widget'ın sağ üst varsayılan konumu görsel olarak kontrol edilmedi, yalnızca kod okundu.
- Widget'ın tam ekran oyunların üstünde kalıp kalmadığı.
- Açık renkli görev çubuğunda tepsi etiketlerinin okunurluğu, %125 ve %150 ekran ölçeklemesi.
- Kartın dışındaki şeffaf boşluktan tıklamaların alttaki pencereye geçmesi: ilk denemede sürükleme çalışmadı, bu özelliği kaldırınca çalıştı. Asıl sebebin bu olup olmadığı ayrıca doğrulanmadı. Kart ile pencere arasında yalnızca 6 px boşluk var.
