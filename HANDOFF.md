# Devir notu (Windows'ta devam için)

Bu proje Mac'te yazıldı, Windows'ta test edilip geliştirilecek. Yeni bir Claude oturumu bunu okuyarak devam edebilir.

## Proje
Ullage: Claude, Codex, Gemini ve Antigravity için kalan 5 saatlik ve haftalık limiti, token geçmişini gösteren menü çubuğu / sistem tepsisi uygulaması.
- `macos/`: Swift 6 + SwiftUI (SwiftPM, Xcode yok). Tamamlanmış, referans sürüm. Sadece okunur; Windows'ta derlenmez.
- `windows/`: Electron (düz JS). Çalışıyor ama bu bilgisayarda hiç denenmedi. Asıl iş burada.

## Windows'ta çalıştırma
```
cd windows
npm install
npm start          # geliştirme
npm test           # birim testler
npm run dist       # Ullage-Setup.exe ve Ullage-Portable.exe (dist klasörüne)
```
Limit görünmesi için Claude Code ve Codex'e bu PC'de giriş yapılmış olmalı.

## Windows'ta yapılacaklar
1. Önce hiçbir şeye dokunmadan çalışıyor mu, tepsi simgesi ve açılır pencere doğru mu, gerçek veriyi okuyor mu kontrol et. Hatalar çıkarsa önce onları düzelt.
2. Mac'te eklenenlerin Windows karşılığı (mantık `macos/Sources/AILimit/` içinde, JS'e çevir):
   - Bitiş tahmini ("Bu hızla biter", `Theme.swift` içinde `Pace.exhaustion`) ve kart altı notlar (`Models.swift` `footnotes`)
   - Tahmini API maliyeti (`Pricing.swift`) ve maliyet kartı
   - Proje bazlı kullanım (`ClaudeProvider.swift` `cwd` alanından klasör adı, `HistoryStore.swift` `projectSums`), yalnızca klasör adı saklanır
   - CSV dışa aktarma, paylaşım kartı (PNG), kurulum kontrolü (`Extras.swift`)
   - "Cache dahil" ayarı: her yerde geçerli, kalıcı (`Prefs.includeCache`)
   - Haftalık özet bildirimi (`Automation.swift` `WeeklySummary`), pencere başlatıcı zamanlayıcısı (sıfırlanma saatine tek zamanlayıcı, saat sınırı yok)
   - Dil: Türkçe/English, `L10n.swift` tablosu (`L.t`, `L.f`); sistem dili Türkçe değilse İngilizce
   - Tema uyumlu onay kutusu ve seçici (`ThemedCheck`, `ThemedSegmented`)
3. Windows'a özgü: tepsi simgesinin üstüne gelince ipucu (5 saatlik ve haftalık yüzde), Windows 11 görev çubuğunda simge görünürlüğü, otomatik başlatma (giriş öğesi).

## Önemli kurallar ve bilgiler
- **GitHub:** Kullanıcının hesabı bu proje sırasında askıya alındı (otomatik işlemler: force-push, workflow tetikleme, release yükleme). Kullanıcı açıkça "yap" demeden hiçbir şeyi GitHub'a gönderme, workflow tetikleme, repo oluşturma/silme, geçmiş yeniden yazma. Yeni hesap açma. Commit'ler yerelde kalır; mesajlar kısa ve düz, Claude eş-yazar satırı yok.
- **Kullanıcı:** Türkçe yazar, kısa ve çoğu zaman sinirli. "Yap, sorma" der ama tasarım kalitesini önemser: adım adım git, her adımı kontrol et (görüntü al), baştan savma yapma.
- **Ekran görüntüsü:** Tüm ekranı yakalama (başka uygulamaların gizli içeriği çıkıyor). Yalnızca kendi uygulamanın pencerelerini/çıktısını üret ve onlara bak.
- **Tek uygulama kopyası:** Kullanıcının açtığı uygulamanın üstüne yaz, ikinci kopya (zip açıp bırakma, test kopyası) bırakma. Spotlight'ta çoğul görünüyordu.
- **Doğruluk:** Emin olunmayan veri "Tahmini" ya da "Veri yok" diye etiketlenir, uydurma değer gösterilmez.
- **Anthropic kullanım uç noktası** (`/api/oauth/usage`) hız sınırlı: en sık 1 dakikada bir sorgula, 429'da en az 5 dakika bekle, son iyi değeri sakla, süresi geçmiş pencere %100 sayılır. Süresi biten Claude Code oturumu `claude -p --model haiku ...` ile yenilettirilir.
- **Gizlilik:** Anahtar/token yazdırma, kaydetme, dışarı gönderme. Proje yolu yerine yalnızca klasör adı.
- Mac uygulaması /Applications/Ullage.app içinde durur (Belgeler korumalı klasör, izin sorar); build_app.sh yeni sürümü onun üzerine yazar.
- Mac tarafı yardımcı betikler: `macos/scripts/build_app.sh`, `package.sh`. Görsel kontrol ortam değişkenleri: `AILIMIT_SNAPSHOT`, `AILIMIT_THEMES`, `AILIMIT_LANG`. Windows'ta karşılığı `--shots=DIR`.
