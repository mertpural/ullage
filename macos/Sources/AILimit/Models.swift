import SwiftUI
import AppKit

enum Provider: String, CaseIterable, Identifiable {
    case claude, codex, gemini, antigravity
    var id: String { rawValue }

    var name: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .gemini: "Gemini"
        case .antigravity: "Antigravity"
        }
    }

    var letter: String {
        switch self {
        case .claude: "C"
        case .codex: "X"
        case .gemini: "G"
        case .antigravity: "A"
        }
    }

    var brandColor: Color {
        switch self {
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex: Color(red: 0.62, green: 0.63, blue: 0.66)
        case .gemini: Color(red: 0.26, green: 0.52, blue: 0.96)
        case .antigravity: Color(red: 0.16, green: 0.30, blue: 0.80)
        }
    }

    /// Sıra: kullanıcının kendi PNG'si, uygulamaya gömülü resmi logo (lobehub/icons), kurulu uygulamanın ikonu.
    var icon: NSImage? {
        let custom = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AILimit/Logos/\(rawValue).png")
        if let img = NSImage(contentsOf: custom) { return img }
        if let url = Bundle.main.url(forResource: rawValue, withExtension: "png", subdirectory: "Logos"),
           let img = NSImage(contentsOf: url) { return img }
        let apps: [String]
        switch self {
        case .claude: apps = ["/Applications/Claude.app"]
        case .codex: apps = ["/Applications/Codex.app", "/Applications/ChatGPT.app"]
        case .gemini: apps = []
        case .antigravity: apps = ["/Applications/Antigravity IDE.app", "/Applications/Antigravity.app"]
        }
        for path in apps where FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return nil
    }
}

enum Confidence {
    case exact      // sağlayıcının kendi verisi ya da loglardan birebir
    case estimate   // tahmin ya da çözümlenmiş alan eşlemesi
    case none       // kaynak yok

    var label: String {
        switch self {
        case .exact: "Kesin"
        case .estimate: "Tahmini"
        case .none: "Veri yok"
        }
    }

    var color: Color {
        switch self {
        case .exact: .green
        case .estimate: .orange
        case .none: .gray
        }
    }
}

struct LimitRow: Identifiable {
    let id = UUID()
    var title: String
    var left: Double
    var reset: Date?
}

struct Usage {
    var fiveHourLeft: Double?      // 0...1
    var weeklyLeft: Double?        // 0...1
    var fiveHourReset: Date?
    var weeklyReset: Date?
    var extra: [LimitRow] = []     // 5 saatlik/haftalık dışındaki pencereler (günlük kota, model grupları)
    var todayTokens: Int?
    /// Limit değeri güncellenemediyse en son alındığı zaman (eski değer gösteriliyor demektir).
    var staleSince: Date?
    var limitConfidence: Confidence = .none
    var tokenConfidence: Confidence = .none
    var notes: [String] = []

    static func loading() -> Usage { Usage(notes: ["Okunuyor…"]) }

    /// 5 saatlik pencerelerden en kısıtlayıcı olan (havuzlar varsa en düşüğü).
    var fiveRow: LimitRow? {
        if let l = fiveHourLeft { return LimitRow(title: "5 saatlik", left: l, reset: fiveHourReset) }
        return extra.filter { $0.title.contains("5 saatlik") }.min { $0.left < $1.left }
    }

    var weekRow: LimitRow? {
        if let l = weeklyLeft { return LimitRow(title: "Haftalık", left: l, reset: weeklyReset) }
        return extra.filter { $0.title.contains("Haftalık") }.min { $0.left < $1.left }
    }

    /// 5 saatlik ya da haftalık olmayan pencereler (ör. Gemini günlük kota).
    var otherRows: [LimitRow] {
        extra.filter { !$0.title.contains("5 saatlik") && !$0.title.contains("Haftalık") }
    }

    /// Kartta ve çubukta gösterilecek tüm pencereler.
    var rows: [LimitRow] {
        if !extra.isEmpty { return extra }
        var r: [LimitRow] = []
        if let l = fiveHourLeft { r.append(LimitRow(title: "5 saatlik", left: l, reset: fiveHourReset)) }
        if let l = weeklyLeft { r.append(LimitRow(title: "Haftalık", left: l, reset: weeklyReset)) }
        return r
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var enabled: Set<Provider> {
        didSet { UserDefaults.standard.set(enabled.map(\.rawValue), forKey: "enabled") }
    }
    @Published var statusMessage = ""
    @Published var selectedTab: String = UserDefaults.standard.string(forKey: "selectedTab") ?? "all" {
        didSet {
            UserDefaults.standard.set(selectedTab, forKey: "selectedTab")
        }
    }
    @Published var notificationsOn: Bool = UserDefaults.standard.object(forKey: "notificationsOn") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(notificationsOn, forKey: "notificationsOn")
            if notificationsOn { Notifier.requestAuthorization() }
        }
    }
    /// Claude Code oturumu bitmişse, Claude Code'a kendini yenilettir (aksi hâlde limit değeri eski kalır).
    @Published var refreshLogin: Bool = UserDefaults.standard.object(forKey: "refreshLogin") as? Bool ?? true {
        didSet { UserDefaults.standard.set(refreshLogin, forKey: "refreshLogin") }
    }
    @Published var starterOn: Bool = UserDefaults.standard.bool(forKey: "starterOn") {
        didSet { UserDefaults.standard.set(starterOn, forKey: "starterOn") }
    }
    @Published var starterStatus = ""
    /// Kartlarda "Bu hızla biter" ve "Sonraki otomatik mesaj" notları.
    @Published var showForecast: Bool = UserDefaults.standard.object(forKey: "showForecast") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showForecast, forKey: "showForecast") }
    }
    @Published var showNextStart: Bool = UserDefaults.standard.object(forKey: "showNextStart") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showNextStart, forKey: "showNextStart") }
    }
    /// "system", "tr" ya da "en"; değişince tüm görünümler yeniden çizilir.
    @Published var language: String = UserDefaults.standard.string(forKey: "language") ?? "system" {
        didSet {
            UserDefaults.standard.set(language, forKey: "language")
            applyThemeIcon()
        }
    }
    var starterTimer: Timer?
    @Published var starterFireAt: Date?
    @Published var weeklySummaryOn: Bool = UserDefaults.standard.object(forKey: "weeklySummaryOn") as? Bool ?? true {
        didSet { UserDefaults.standard.set(weeklySummaryOn, forKey: "weeklySummaryOn") }
    }
    @Published var launchAtLogin = LoginItem.enabled
    @Published var themeId: String = UserDefaults.standard.string(forKey: "themeId") ?? "system" {
        didSet {
            UserDefaults.standard.set(themeId, forKey: "themeId")
            applyThemeIcon()
        }
    }
    @Published var showFive: Bool = UserDefaults.standard.object(forKey: "showFive") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showFive, forKey: "showFive") }
    }
    @Published var showWeek: Bool = UserDefaults.standard.object(forKey: "showWeek") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showWeek, forKey: "showWeek") }
    }
    @Published var showTags: Bool = UserDefaults.standard.object(forKey: "showTags") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showTags, forKey: "showTags") }
    }
    @Published var styleFive: MetricStyle = MetricStyle(rawValue: UserDefaults.standard.string(forKey: "styleFive") ?? "") ?? .percent {
        didSet { UserDefaults.standard.set(styleFive.rawValue, forKey: "styleFive") }
    }
    @Published var styleWeek: MetricStyle = MetricStyle(rawValue: UserDefaults.standard.string(forKey: "styleWeek") ?? "") ?? .percent {
        didSet { UserDefaults.standard.set(styleWeek.rawValue, forKey: "styleWeek") }
    }
    /// Arka plan yenileme aralığı (saniye). 0 = yalnızca elle.
    @Published var refreshInterval: Int = UserDefaults.standard.object(forKey: "refreshInterval") as? Int ?? 30 {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval")
            restartTimer()
        }
    }
    @Published var daily: [Provider: [Int]] = [:]
    @Published var dashPage = "history"
    @Published var updatedAt: Date?
    @Published var syncing = false

    var theme: Theme { Theme.byId(themeId) }

    /// Uygulama ikonunu (Dock, uygulama değiştirici, bildirimler) temanın logosuyla anında değiştirir.
    func applyThemeIcon() {
        let pal = theme.logo
        let r = ImageRenderer(content: LogoMark(size: 412, palette: pal).frame(width: 512, height: 512))
        r.scale = 2
        if let img = r.nsImage { NSApplication.shared.applicationIconImage = img }
    }
    @Published var usage: [Provider: Usage] = Dictionary(
        uniqueKeysWithValues: Provider.allCases.map { ($0, Usage.loading()) }
    )

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: "enabled")
        enabled = saved.map { Set($0.compactMap(Provider.init(rawValue:))) }
            ?? [.claude, .codex, .antigravity]
        if notificationsOn { Notifier.requestAuthorization() }
        startRefreshing()
        DispatchQueue.main.async { self.applyThemeIcon() }
        if !UserDefaults.standard.bool(forKey: "onboardingDone") {
            UserDefaults.standard.set(true, forKey: "onboardingDone")
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { self.openDashboard("providers") }
        }
        if let page = ProcessInfo.processInfo.environment["AILIMIT_OPEN"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { self.openDashboard(page) }
        }
    }

    private var timer: Timer?

    func startRefreshing() {
        refresh()
        restartTimer()
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = nil
        guard refreshInterval > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(refreshInterval), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// `force`: elle yenilemede ağ önbelleklerini (30 saniyeden eskilerse) atlar; hız sınırına takılmamak için
    /// 30 saniyeden sık sorgu yapılmaz.
    func refresh(force: Bool = false) {
        if force {
            ClaudeLimitAPI.invalidate()
            GeminiProvider.invalidate()
        }
        syncing = true
        Task.detached {
            let codex = CodexProvider.read()
            async let antiTask = AntigravityProvider.read()
            async let geminiTask = GeminiProvider.read()
            let claude = await ClaudeProvider.read()
            let anti = await antiTask
            let gemini = await geminiTask
            var daily: [Provider: [Int]] = [:]
            for p in Provider.allCases { daily[p] = HistoryStore.shared.dailyTotals(provider: p.rawValue, days: 7) }
            await MainActor.run {
                self.daily = daily
                self.updatedAt = Date()
                self.syncing = false
                let old = self.usage
                self.usage[.claude] = claude
                self.usage[.codex] = codex
                self.usage[.antigravity] = anti
                self.usage[.gemini] = gemini
                if self.notificationsOn { Notifier.check(old: old, new: self.usage) }
                self.scheduleStarter(claude)
                if self.weeklySummaryOn && self.notificationsOn { WeeklySummary.sendIfDue() }
            }
        }
    }

    /// Açık menü çubuğu penceresini içeriğin ideal boyuna getirir; üst kenar sabit kalır.
    @MainActor static func fitPopover() {
        guard let w = NSApp.keyWindow, w.level != .normal, let view = w.contentView else { return }
        let size = view.fittingSize
        guard size.height > 40, abs(size.height - w.contentLayoutRect.height) > 1 else { return }
        var frame = w.frame
        let newH = size.height + (frame.height - w.contentLayoutRect.height)
        frame.origin.y += frame.height - newH
        frame.size.height = newH
        w.setFrame(frame, display: true, animate: false)
    }

    func openDashboard(_ page: String? = nil) {
        if let page { dashPage = page }
        let popover = NSApp.keyWindow   // açılan menü çubuğu penceresi
        DashboardWindow.show(state: self)
        popover?.orderOut(nil)
    }

    private static let dayTime: DateFormatter = {
        let f = DateFormatter(); f.locale = L.locale; f.dateFormat = "EEE HH:mm"; return f
    }()
    private static let clock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    /// Saati bugünse yalnızca "HH:mm", değilse gün kısaltmasıyla yazar.
    static func whenText(_ d: Date) -> String {
        Calendar.current.isDateInToday(d) ? clock.string(from: d) : dayTime.string(from: d)
    }

    /// Kartın altında gösterilen kısa notlar: limitin ne zaman biteceği ve sonraki otomatik mesaj.
    func footnotes(_ p: Provider, _ u: Usage) -> [String] {
        var out: [String] = []
        if showForecast, u.staleSince == nil {
            var parts: [String] = []
            if let f = u.fiveRow, let at = Pace.exhaustion(f, window: 5 * 3600) { parts.append(L.f("5 saatlik %@", Self.whenText(at))) }
            if let w = u.weekRow, let at = Pace.exhaustion(w, window: 7 * 86400) { parts.append(L.f("haftalık %@", Self.whenText(at))) }
            if !parts.isEmpty { out.append(L.t("Bu hızla biter: ") + parts.joined(separator: ", ")) }
        }
        if showNextStart, p == .claude, starterOn, let at = starterFireAt { out.append(L.f("Sonraki otomatik mesaj: %@", Self.whenText(at))) }
        return out
    }

    /// Sıfırlanma saatine tek seferlik zamanlayıcı kurar; her yenilemede yalnızca saat değiştiyse yeniden kurulur.
    /// Sıfırlanma çoktan geçmişse (uygulama geç açıldıysa) bir kez hemen dener.
    @MainActor func scheduleStarter(_ claude: Usage) {
        guard starterOn else { starterTimer?.invalidate(); starterTimer = nil; starterFireAt = nil; return }
        let now = Date()
        if let at = WindowStarter.nextFire(claude, now: now) {
            if let cur = starterFireAt, abs(cur.timeIntervalSince(at)) < 60, starterTimer?.isValid == true { return }
            starterTimer?.invalidate()
            starterFireAt = at
            starterTimer = Timer.scheduledTimer(withTimeInterval: max(1, at.timeIntervalSince(now)), repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.starterTimer = nil
                    self?.starterFireAt = nil
                    self?.startWindow()
                }
            }
            starterTimer?.tolerance = 5
        } else if starterTimer == nil, WindowStarter.shouldStart(claude, now: now) {
            startWindow()
        }
    }

    /// Claude'un yeni 5 saatlik penceresini hemen başlatır.
    func startWindow() {
        starterStatus = L.t("Başlatılıyor…")
        Task.detached {
            let r = WindowStarter.ping()
            await MainActor.run {
                let f = DateFormatter(); f.timeStyle = .short
                self.starterStatus = "\(f.string(from: Date())) · \(r.message)"
                if r.ok { DispatchQueue.main.asyncAfter(deadline: .now() + 15) { self.refresh() } }
            }
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        if let err = LoginItem.set(on) { statusMessage = "Girişte başlatma ayarlanamadı: \(err)" }
        launchAtLogin = LoginItem.enabled
    }

    func binding(for p: Provider) -> Binding<Bool> {
        Binding(
            get: { self.enabled.contains(p) },
            set: { on in
                if on { self.enabled.insert(p) } else { self.enabled.remove(p) }
            }
        )
    }

    /// Menü çubuğunda gösterilen değer: 5 saatlik ve haftalıktan kısıtlayıcı olan; veri yoksa nil.
    func tightest(_ p: Provider) -> Double? {
        guard let u = usage[p] else { return nil }
        return u.rows.map(\.left).min()
    }
}

func statusColor(_ left: Double) -> Color {
    left > 0.4 ? .green : (left > 0.15 ? .orange : .red)
}

func formatRemaining(_ date: Date, now: Date = Date()) -> String {
    let s = Int(date.timeIntervalSince(now))
    if s <= 0 { return L.t("şimdi") }
    let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
    let u = L.en ? ("d", "h", "m") : ("g", "s", "dk")
    if d > 0 { return "\(d)\(u.0) \(h)\(u.1)" }
    if h > 0 { return "\(h)\(u.1) \(m)\(u.2)" }
    return "\(m)\(u.2)"
}
