import SwiftUI

@MainActor
enum DashboardWindow {
    private static var window: NSWindow?

    static func show(state: AppState) {
        if window == nil {
            let host = NSHostingController(rootView: DashboardView().environmentObject(state))
            let w = NSWindow(contentViewController: host)
            w.title = AppInfo.name
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 980, height: 700))
            w.minSize = NSSize(width: 860, height: 560)
            w.center()
            w.isReleasedWhenClosed = false
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum DashPage: String, CaseIterable, Identifiable {
    case history, providers, sync, menubar, appearance, automation, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .history: "Kullanım"
        case .providers: "Sağlayıcılar"
        case .sync: "Senkronizasyon"
        case .menubar: "Menü çubuğu"
        case .appearance: "Görünüm"
        case .automation: "Bildirim ve otomasyon"
        case .about: "Hakkında"
        }
    }

    var icon: String {
        switch self {
        case .history: "chart.bar.fill"
        case .providers: "square.grid.2x2.fill"
        case .sync: "arrow.triangle.2.circlepath"
        case .menubar: "menubar.rectangle"
        case .appearance: "paintpalette.fill"
        case .automation: "bell.badge.fill"
        case .about: "info.circle.fill"
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let t = state.theme
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    LogoMark(size: 30, palette: t.logo)
                    Text(AppInfo.name).font(t.font(17, .bold))
                }
                .padding(.bottom, 14).padding(.horizontal, 6)
                ForEach(DashPage.allCases) { p in
                    let sel = state.dashPage == p.rawValue
                    HStack(spacing: 9) {
                        Image(systemName: p.icon).frame(width: 18).foregroundStyle(sel ? t.accent : t.sub)
                        Text(L.t(p.title)).font(t.font(13, sel ? .semibold : .regular))
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(sel ? t.accent.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: max(6, t.radius - 4)))
                    .contentShape(Rectangle())
                    .contentShape(Rectangle())
                    .onTapGesture { state.dashPage = p.rawValue }
                }
                Spacer()
            }
            .padding(14)
            .frame(width: 230)
            .background(t.card.opacity(0.6))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L.t(DashPage(rawValue: state.dashPage)?.title ?? "")).font(t.font(26, .bold))
                    page
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(t.text)
        .background(t.bg)
        .themed(t)
        .environment(\.locale, L.locale)
    }

    @ViewBuilder private var page: some View {
        switch DashPage(rawValue: state.dashPage) ?? .history {
        case .history: HistoryPage()
        case .providers: ProvidersPage()
        case .sync: SyncPage()
        case .menubar: MenuBarPage()
        case .appearance: AppearancePage()
        case .automation: AutomationPage()
        case .about: AboutPage()
        }
    }
}

struct SettingRow<C: View>: View {
    @EnvironmentObject var state: AppState
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var control: C

    var body: some View {
        let t = state.theme
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(t.font(13, .semibold))
                if let s = subtitle {
                    Text(s).font(t.font(11)).foregroundStyle(t.sub).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .card(t, padding: 14)
    }
}

// MARK: Sayfalar

struct ProvidersPage: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let t = state.theme
        SetupCheckCard()
        Text(L.t("Menü çubuğunda ve popover'da görünecek sağlayıcıları seç.")).font(t.font(12)).foregroundStyle(t.sub)
        ForEach(Provider.allCases) { p in
            let u = state.usage[p] ?? .loading()
            HStack(spacing: 14) {
                BrandBadge(provider: p, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(p.name).font(t.font(14, .semibold))
                        Text(L.t("Limit")).font(t.font(10)).foregroundStyle(t.sub)
                        ConfidenceTag(c: u.limitConfidence)
                        Text(L.t("Token")).font(t.font(10)).foregroundStyle(t.sub)
                        ConfidenceTag(c: u.tokenConfidence)
                    }
                    ForEach(u.notes, id: \.self) { n in
                        Text(L.t(n)).font(t.font(10)).foregroundStyle(t.sub).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                Toggle("", isOn: state.binding(for: p)).toggleStyle(.switch).labelsHidden()
            }
            .card(t, padding: 14)
        }
    }
}

struct StyleChoice: View {
    @EnvironmentObject var state: AppState
    let style: MetricStyle
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let t = state.theme
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.16))
                MetricGlyph(left: 0.57, style: style, tag: nil, text: .white)
            }
            .frame(height: 44)
            Text(L.t(style.label)).font(t.font(11, selected ? .semibold : .regular))
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(t.card, in: RoundedRectangle(cornerRadius: t.radius))
        .overlay(RoundedRectangle(cornerRadius: t.radius).stroke(selected ? t.accent : t.border, lineWidth: selected ? 2 : max(0.5, t.borderW)))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

struct MenuBarPage: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let t = state.theme
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("ÖNİZLEME")).font(t.font(10, .bold)).foregroundStyle(t.sub)
            HStack(spacing: 14) {
                MenuBarLabel(forceDark: true).environmentObject(state)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 8))
                MenuBarLabel(forceDark: false).environmentObject(state)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color(white: 0.92), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .card(t, padding: 14)

        SettingRow(title: L.t("Etiketleri göster"), subtitle: L.t("5 saatlik için \"5s\", haftalık için \"H\", günlük kota için \"G\". Aynı yüzdeler olsa bile hangisi olduğu anlaşılır.")) {
            Toggle("", isOn: $state.showTags).toggleStyle(.switch).labelsHidden()
        }

        SettingRow(title: L.t("5 saatlik limit"), subtitle: L.t("Menü çubuğunda göster.")) {
            Toggle("", isOn: $state.showFive).toggleStyle(.switch).labelsHidden()
        }
        if state.showFive {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(MetricStyle.allCases) { s in
                    StyleChoice(style: s, selected: state.styleFive == s) { state.styleFive = s }
                }
            }
        }

        SettingRow(title: L.t("Haftalık limit"), subtitle: L.t("Menü çubuğunda göster.")) {
            Toggle("", isOn: $state.showWeek).toggleStyle(.switch).labelsHidden()
        }
        if state.showWeek {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(MetricStyle.allCases) { s in
                    StyleChoice(style: s, selected: state.styleWeek == s) { state.styleWeek = s }
                }
            }
        }
        Text(L.t("Hangi sağlayıcıların görüneceğini Sağlayıcılar sayfasından seçersin.")).font(t.font(11)).foregroundStyle(t.sub)
    }
}

struct ThemeChoice: View {
    @EnvironmentObject var state: AppState
    let theme: Theme

    var body: some View {
        let selected = state.themeId == theme.id
        let t = state.theme
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: theme.radius).fill(theme.bg)
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: max(2, theme.radius - 8)).fill(theme.card)
                        .overlay(RoundedRectangle(cornerRadius: max(2, theme.radius - 8)).stroke(theme.border, lineWidth: theme.borderW))
                        .frame(height: 22)
                    HStack(spacing: 6) {
                        Capsule().fill(theme.accent).frame(width: 46, height: 8)
                        Spacer()
                        Text("62%").font(theme.font(11, .bold)).foregroundStyle(theme.text)
                    }
                }
                .padding(10)
            }
            .frame(height: 74)
            .overlay(RoundedRectangle(cornerRadius: theme.radius).stroke(theme.border, lineWidth: theme.borderW))
            Text(L.t(theme.name)).font(t.font(12, selected ? .bold : .medium))
        }
        .padding(8)
        .background(t.card, in: RoundedRectangle(cornerRadius: t.radius + 2))
        .overlay(RoundedRectangle(cornerRadius: t.radius + 2).stroke(selected ? t.accent : Color.clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture { state.themeId = theme.id }
    }
}

struct AppearancePage: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let t = state.theme
        SettingRow(title: L.t("Dil"), subtitle: L.t("Arayüz dilini seç. Değişiklik hemen uygulanır.")) {
            ThemedSegmented(t: t, items: [(L.t("Sistem"), "system"), ("Türkçe", "tr"), ("English", "en")], selection: $state.language)
        }
        Text(L.t("Tema popover'a ve bu pencereye uygulanır. Menü çubuğu her zaman sistemin açık/koyu görünümüne uyar.")).font(t.font(12)).foregroundStyle(t.sub)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            ForEach(Theme.all) { th in ThemeChoice(theme: th) }
        }
    }
}

struct AutomationPage: View {
    @EnvironmentObject var state: AppState

    private var starterNote: String {
        guard state.starterOn else { return "" }
        if let at = state.starterFireAt { return L.f(" Sonraki otomatik mesaj: %@.", AppState.whenText(at)) }
        return L.t(" Sıfırlanma saati bekleniyor.")
    }

    var body: some View {
        let t = state.theme
        SettingRow(title: L.t("Limit bildirimleri"), subtitle: L.t("Kalan %15 ve %5'in altına inince, ayrıca limit yenilenince bildirim gönderir.")) {
            Toggle("", isOn: $state.notificationsOn).toggleStyle(.switch).labelsHidden()
        }
        SettingRow(title: L.t("Bitiş tahmini notu"), subtitle: L.t("Kartların altında \"Bu hızla biter: 5 saatlik 19:40\" satırını gösterir.")) {
            Toggle("", isOn: $state.showForecast).toggleStyle(.switch).labelsHidden()
        }
        SettingRow(title: L.t("Sonraki otomatik mesaj notu"), subtitle: L.t("Claude kartında pencere başlatıcının bir sonraki mesaj saatini gösterir. Başlatıcı kapalıysa zaten görünmez.")) {
            Toggle("", isOn: $state.showNextStart).toggleStyle(.switch).labelsHidden()
        }
        SettingRow(title: L.t("Haftalık özet"), subtitle: L.t("Pazartesi sabahı geçen haftanın toplam token'ını, en yoğun gününü ve en çok kullandığın aracı bildirir. Bildirimler kapalıysa gelmez.")) {
            Toggle("", isOn: $state.weeklySummaryOn).toggleStyle(.switch).labelsHidden()
        }
        SettingRow(title: L.t("Claude limitini Claude Code'dan al"), subtitle: L.t("Claude Code, her cevaptan sonra limit yüzdesini yerel bir dosyaya yazar; Ullage onu okur. Ağ gerekmez, Anthropic'in hız sınırına takılmaz. Açınca ~/.claude/settings.json dosyasına küçük bir durum satırı betiği eklenir (önce yedeği alınır, başka bir durum satırı varsa dokunulmaz). Yalnızca Claude Code çalışırken güncellenir.") + (state.statusLineMessage.isEmpty ? "" : " — " + L.t(state.statusLineMessage))) {
            Toggle("", isOn: $state.statusLineOn).toggleStyle(.switch).labelsHidden()
        }
        SettingRow(title: L.t("Girişte otomatik başlat"), subtitle: L.t("Mac'e giriş yapınca uygulama kendiliğinden açılır.")) {
            Toggle("", isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) }))
                .toggleStyle(.switch).labelsHidden()
        }
        SettingRow(title: L.t("Claude oturumunu otomatik yenile"), subtitle: L.t("Claude Code oturumunun süresi dolarsa (yaklaşık 8 saatte bir) limit değeri eski kalır. Bu açıkken Ullage, Claude Code'a tek satırlık bir istek attırıp oturumunu yeniletir. Çok az token harcar, anahtarlarına dokunmaz.")) {
            Toggle("", isOn: $state.refreshLogin).toggleStyle(.switch).labelsHidden()
        }
        SettingRow(title: L.t("Claude pencere başlatıcı"), subtitle: "5 saatlik pencere bittiğinde Haiku'ya tek satırlık bir istek gönderip yeni pencereyi erken başlatır. Ek limit vermez, yalnızca pencerenin başlama saatini belirler. Her istek çok az token harcar.\(starterNote)") {
            Toggle("", isOn: $state.starterOn).toggleStyle(.switch).labelsHidden()
        }
    }
}

struct AboutPage: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let t = state.theme
        HStack(spacing: 16) {
            LogoMark(size: 72, palette: t.logo)
            VStack(alignment: .leading, spacing: 4) {
                Text(AppInfo.name).font(t.font(22, .bold))
                Text(L.t("Yapay zekâ araçlarının limitini ve token kullanımını menü çubuğundan takip et."))
                    .font(t.font(12)).foregroundStyle(t.sub).fixedSize(horizontal: false, vertical: true)
            }
        }
        .card(t, padding: 16)
        VStack(alignment: .leading, spacing: 10) {
            Text(L.t("Veri doğruluğu etiketleri")).font(t.font(13, .semibold))
            HStack(spacing: 8) { ConfidenceTag(c: .exact); Text(L.t("Sağlayıcının kendi verisi ya da kayıtlardan birebir.")).font(t.font(12)).foregroundStyle(t.sub) }
            HStack(spacing: 8) { ConfidenceTag(c: .estimate); Text(L.t("Tahmin ya da kayıt yapısından çözümlenmiş alanlar.")).font(t.font(12)).foregroundStyle(t.sub) }
            HStack(spacing: 8) { ConfidenceTag(c: .none); Text(L.t("Kaynak yok ya da erişilemedi; uydurma değer gösterilmez.")).font(t.font(12)).foregroundStyle(t.sub) }
        }
        .card(t, padding: 16)
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("Veri kaynakları")).font(t.font(13, .semibold))
            Text(L.t("Claude: ~/.claude kayıtları (token), Anthropic kullanım uç noktası (limit)")).font(t.font(12)).foregroundStyle(t.sub)
            Text(L.t("Codex: ~/.codex oturum kayıtları (limit ve token)")).font(t.font(12)).foregroundStyle(t.sub)
            Text(L.t("Antigravity: yerel konuşma veritabanı (token), yerel dil sunucusu (limit)")).font(t.font(12)).foregroundStyle(t.sub)
            Text(L.t("Gemini: Google Code Assist kota API'si (Gemini CLI oturumuyla)")).font(t.font(12)).foregroundStyle(t.sub)
        }
        .card(t, padding: 16)
    }
}


struct SyncPage: View {
    @EnvironmentObject var state: AppState

    private static let options: [(String, Int)] = [
        ("15 saniye", 15), ("30 saniye", 30), ("1 dakika", 60), ("2 dakika", 120), ("5 dakika", 300),
        ("10 dakika", 600), ("15 dakika", 900), ("Yalnızca elle", 0),
    ]

    var body: some View {
        let t = state.theme
        SettingRow(title: L.t("Otomatik yenileme"), subtitle: L.t("Verilerin arka planda ne sıklıkla okunacağı. Yerel kayıtlar (token geçmişi, Codex, Antigravity) her yenilemede okunur, 15 saniye bile sorun olmaz.")) {
            Picker("", selection: $state.refreshInterval) {
                ForEach(Self.options, id: \.1) { Text(L.t($0.0)).tag($0.1) }
            }
            .labelsHidden().frame(width: 160)
        }
        SettingRow(
            title: L.t("Şimdi senkronize et"),
            subtitle: state.syncing ? L.t("Okunuyor…") : (state.updatedAt.map { L.f("Son senkron: %@", Self.stamp($0)) } ?? L.t("Henüz okunmadı."))
        ) {
            Button(L.t("Senkronize et")) { state.refresh(force: true) }
        }

        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("Kaynak başına sınırlar")).font(t.font(13, .semibold))
            Text(L.t("Claude limit yüzdesi: Anthropic'in kullanım bilgisi sınırlı olduğu için seçtiğin süre ne olursa olsun en sık 1 dakikada bir sorgulanır; hız sınırına takılırsa 5 dakika beklenir. Arada son alınan değer gösterilir, yenilenen pencereler hemen %100 olur."))
            Text(L.t("Gemini kotası: en sık 2 dakikada bir."))
            Text(L.t("Antigravity limiti: IDE açıksa her yenilemede yerel sunucudan okunur, kapalıysa okunamaz."))
            Text(L.t("Codex ve token geçmişi: yerel dosyalardan, her yenilemede."))
        }
        .font(t.font(12)).foregroundStyle(t.sub)
        .fixedSize(horizontal: false, vertical: true)
        .card(t, padding: 16)
    }

    static func stamp(_ d: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .medium
        return f.string(from: d)
    }
}
