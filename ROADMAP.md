# Ullage — yol haritası

Benzer açık kaynak uygulamalar: CodexBar (steipete), ClaudeBar (tddworks). Aşağıdakiler onlardan ve kendi isteklerinden derlendi.

## Gerçek veri (öncelik 1)
- [x] Claude 5 saatlik ve haftalık limit (OAuth kullanım uç noktası), sıfırlanma saati
- [x] Codex 5 saatlik ve haftalık limit (yerel oturum kayıtları)
- [ ] Gemini: Gemini CLI'ın `~/.gemini/oauth_creds.json` oturumuyla Code Assist kota API'si (model başına kota). CodexBar bu yolu kullanıyor.
- [ ] Antigravity limit: yerel dil sunucusunu yoklamak (CodexBar "experimental" diyor). ClaudeBar'a göre Gemini ve Claude havuzları için 5 saatlik/haftalık pencere var.
- [ ] Claude model bazlı limitler (Opus, Sonnet ayrı), "Extra Usage"
- [ ] Antigravity token alanlarını doğrula (şu an "Tahmini")

## Arayüz
- [ ] Menü çubuğunda 5 saatlik ve haftalık ayrı: ikon + iki mini çubuk ya da `62% · 71%`
- [ ] Sağlayıcı başına ayrı menü öğesi ya da tek birleşik öğe (CodexBar'daki "Merge Icons")
- [ ] Popover: sağlayıcı kartları, halka/çubuk, sıfırlanma geri sayımı, uyarı seviyeleri (sağlıklı/uyarı/kritik/bitti)
- [ ] Ayrı pencere: geçmiş, model bazlı grafik, gün/hafta/ay, bugün ve dün karşılaştırma
- [ ] Gerçek logolar (yapıldı, `Resources/Logos`), açık/koyu menü çubuğu uyumu
- [ ] Doğruluk etiketleri: Kesin / Tahmini / Veri yok (yapıldı)

## Özellikler
- [ ] Limit dolmaya yaklaşınca bildirim (%90, %100), pencere sıfırlanınca bildirim
- [ ] Hız göstergesi: bu tempoyla limit ne zaman biter
- [ ] **Pencere başlatıcı** (opt-in): 5 saatlik limit sıfırlanınca, ya da sabah belirlenen saatte, en ucuz modele (Haiku) çok kısa bir mesaj atıp yeni pencereyi erken başlatır. Not: ek hak vermez, sadece pencerenin ne zaman başlayıp biteceğini kaydırır. Anthropic bunu resmi olarak belgelemiyor, topluluk bilgisi.
- [ ] Oturum açılışında otomatik başlat
- [ ] Komut satırı aracı ve `ailimit://` URL şeması (betikler için)
- [ ] Windows sürümü (Tauri ya da .NET, aynı ayrıştırma mantığıyla)

## Teknik borç
- [ ] `ClaudeLimitAPI` kilitlerini async-güvenli yap (derleyici uyarısı)
- [ ] Uygulamayı imzala ve DMG olarak paketle
