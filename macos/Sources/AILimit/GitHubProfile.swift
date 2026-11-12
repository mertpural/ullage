import Foundation
import SwiftUI
import Security

// MARK: - Profil kartı (SVG)

/// GitHub profil README'sine konan, token kullanım ısı haritası resmi. İçinde yalnızca günlük toplam token vardır;
/// proje adı, model ya da sohbet içeriği yoktur.
enum ProfileCard {
    private static let keyFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f }()

    private static let dayFmt: DateFormatter = { let f = DateFormatter(); f.locale = L.locale; f.dateStyle = .medium; return f }()

    static func svg(split: Bool, dark: Bool, now: Date = Date()) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 1
        let today = cal.startOfDay(for: now)
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: today)!.start
        let start = cal.date(byAdding: .weekOfYear, value: -52, to: thisWeek)!

        var days: [String: [String: Int]] = [:]
        var total = 0
        for p in HistoryStore.shared.series(since: start, hourly: false, includeCache: Prefs.includeCache) {
            days[keyFmt.string(from: p.bucket), default: [:]][p.provider, default: 0] += p.tokens
            total += p.tokens
        }
        let mx = max(1, days.values.map { $0.values.reduce(0, +) }.max() ?? 1)

        let bg = dark ? "#0d1117" : "#ffffff"
        let text = dark ? "#e6edf3" : "#1f2328"
        let sub = dark ? "#8b949e" : "#656d76"
        let line = dark ? "#30363d" : "#d0d7de"
        let scale = dark ? ["#161b22", "#0e4f47", "#1a8a7c", "#3fc0ad", "#7fe8d8"] : ["#ebedf0", "#b6ece3", "#6fd3c3", "#2fa896", "#17695d"]
        let provColor = ["claude": "#d97857", "codex": "#9ea1a8", "gemini": "#4285f5", "antigravity": "#294dcc", "opencode": "#4dcc8c", "kimi": "#855cea", "cline": "#f2bf40"]  // uygulamadaki marka renkleri
        let order = ["claude", "codex", "gemini", "antigravity", "opencode", "kimi", "cline"]
        let opacity = [0.0, 0.4, 0.6, 0.8, 1.0]

        let cell = 11, gap = 3, left = 20, top = 52
        let width = left * 2 + 53 * (cell + gap) - gap
        let height = top + 7 * (cell + gap) - gap + 40
        let en = L.en
        let title = "Ullage"
        let totalText = en ? "\(formatTokens(total)) tokens · last 12 months" : "\(formatTokens(total)) token · son 12 ay"

        var s = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(width)\" height=\"\(height)\" viewBox=\"0 0 \(width) \(height)\" role=\"img\" aria-label=\"\(title)\">\n"
        s += "<rect width=\"\(width)\" height=\"\(height)\" rx=\"10\" fill=\"\(bg)\" stroke=\"\(line)\"/>\n"
        s += "<style>text{font-family:-apple-system,'Segoe UI',Helvetica,Arial,sans-serif}</style>\n"
        s += "<text x=\"\(left)\" y=\"32\" font-size=\"15\" font-weight=\"600\" fill=\"\(text)\">\(title)</text>\n"
        s += "<text x=\"\(width - left)\" y=\"32\" font-size=\"12\" text-anchor=\"end\" fill=\"\(sub)\">\(totalText)</text>\n"

        s += "<defs><clipPath id=\"c\"><rect width=\"\(cell)\" height=\"\(cell)\" rx=\"2\"/></clipPath></defs>\n"
        for w in 0..<53 {
            for d in 0..<7 {
                guard let date = cal.date(byAdding: .day, value: w * 7 + d, to: start), date <= today else { continue }
                let day = days[keyFmt.string(from: date)] ?? [:]
                let v = day.values.reduce(0, +)
                let r = Double(v) / Double(mx)
                let lv = v == 0 ? 0 : (r < 0.15 ? 1 : (r < 0.4 ? 2 : (r < 0.7 ? 3 : 4)))
                let x = left + w * (cell + gap), y = top + d * (cell + gap)
                let tip = "<title>\(dayFmt.string(from: date)): \(v == 0 ? (en ? "no usage" : "kullanım yok") : formatTokens(v) + (en ? " tokens" : " token"))</title>"
                if split, lv > 0 {
                    // Uygulamadaki gibi: kare, o günkü servis paylarına göre dikey bölümlere ayrılır; koyuluk yoğunluğu gösterir.
                    s += "<g transform=\"translate(\(x) \(y))\" clip-path=\"url(#c)\" fill-opacity=\"\(opacity[lv])\">"
                    var yy = 0.0
                    for name in order {
                        guard let tv = day[name], tv > 0 else { continue }
                        let h = Double(cell) * Double(tv) / Double(v)
                        s += "<rect y=\"\(String(format: "%.2f", yy))\" width=\"\(cell)\" height=\"\(String(format: "%.2f", h + 0.3))\" fill=\"\(provColor[name] ?? scale[3])\"/>"
                        yy += h
                    }
                    s += tip + "</g>\n"
                } else {
                    s += "<rect x=\"\(x)\" y=\"\(y)\" width=\"\(cell)\" height=\"\(cell)\" rx=\"2\" fill=\"\(scale[lv])\">\(tip)</rect>\n"
                }
            }
        }
        let fy = height - 14
        if split {
            var x = width - left
            for (name, col) in Provider.allCases.reversed().map({ ($0.name, provColor[$0.rawValue] ?? "#888888") }) {
                s += "<text x=\"\(x)\" y=\"\(fy)\" font-size=\"10\" text-anchor=\"end\" fill=\"\(sub)\">\(name)</text>\n"
                let tw = name.count * 6 + 6
                s += "<rect x=\"\(x - tw - 10)\" y=\"\(fy - 9)\" width=\"9\" height=\"9\" rx=\"2\" fill=\"\(col)\"/>\n"
                x -= tw + 24
            }
        } else {
            let lessMore = en ? ("Less", "More") : ("Az", "Çok")
            var x = width - left
            s += "<text x=\"\(x)\" y=\"\(fy)\" font-size=\"10\" text-anchor=\"end\" fill=\"\(sub)\">\(lessMore.1)</text>\n"
            x -= lessMore.1.count * 6 + 6
            for lv in stride(from: 4, through: 0, by: -1) {
                x -= 11
                s += "<rect x=\"\(x)\" y=\"\(fy - 9)\" width=\"10\" height=\"10\" rx=\"2\" fill=\"\(scale[lv])\"/>\n"
                x -= 3
            }
            s += "<text x=\"\(x - 3)\" y=\"\(fy)\" font-size=\"10\" text-anchor=\"end\" fill=\"\(sub)\">\(lessMore.0)</text>\n"
        }
        s += "</svg>\n"
        return s
    }
}

// MARK: - GitHub'a gönderme

/// Kullanıcının kendi profil reposuna (kullanıcıadı/kullanıcıadı) `ullage.svg` dosyasını koyar ve günceller.
/// Anahtar yalnızca Anahtar Zinciri'nde durur. Veri değişmediyse ya da süre dolmadıysa hiç istek gönderilmez.
enum GitHubSync {
    private static let service = "com.mertpural.ailimit.github"
    static let fileName = "ullage.svg"
    private static let d = UserDefaults.standard

    static var enabled: Bool { d.bool(forKey: "ghOn") }
    static var user: String { d.string(forKey: "ghUser") ?? "" }
    static var interval: String { d.string(forKey: "ghInterval") ?? "daily" }
    static var split: Bool { d.object(forKey: "ghSplit") as? Bool ?? true }
    static var dark: Bool { d.object(forKey: "ghDark") as? Bool ?? true }
    static var status: String { d.string(forKey: "ghStatus") ?? "" }
    static var lastPush: Date? { let v = d.double(forKey: "ghLastPush"); return v > 0 ? Date(timeIntervalSince1970: v) : nil }

    static func markdown(_ user: String) -> String {
        "![Ullage](https://raw.githubusercontent.com/\(user)/\(user)/HEAD/\(fileName))"
    }

    // Anahtar Zinciri
    static var hasToken: Bool { token() != nil }
    static func token() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func saveToken(_ t: String) {
        deleteToken()
        guard !t.isEmpty else { return }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecValueData as String: Data(t.utf8)]
        SecItemAdd(q as CFDictionary, nil)
    }
    static func deleteToken() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }

    private static func setStatus(_ s: String) { d.set(s, forKey: "ghStatus") }

    /// Arka planda çağrılır: süresi geldiyse ve kart değiştiyse gönderir.
    static func syncIfDue() async {
        guard enabled, !user.isEmpty, hasToken, interval != "manual" else { return }
        let now = Date().timeIntervalSince1970
        let need = interval == "weekly" ? 6.5 * 86400 : 20 * 3600
        guard now - d.double(forKey: "ghLastPush") >= need, now - d.double(forKey: "ghLastTry") >= 6 * 3600 else { return }
        _ = await push(force: false)
    }

    /// `force`: elle gönderimde değişiklik kontrolü yapılmaz.
    @discardableResult
    static func push(force: Bool) async -> String {
        guard let tok = ProcessInfo.processInfo.environment["AILIMIT_GHTOKEN"] ?? token(), !user.isEmpty else { return L.t("Kullanıcı adı ve anahtar gerekli") }
        let now = Date().timeIntervalSince1970
        d.set(now, forKey: "ghLastTry")
        let svg = ProfileCard.svg(split: split, dark: dark)
        let hash = String(svg.hashValue)
        if !force, d.string(forKey: "ghLastHash") == hash {
            d.set(now, forKey: "ghLastPush")
            return L.t("Kart değişmemiş, gönderilmedi")
        }
        let base = ProcessInfo.processInfo.environment["AILIMIT_GHAPI"] ?? "https://api.github.com"
        let url = URL(string: "\(base)/repos/\(user)/\(user)/contents/\(fileName)")!
        func req(_ method: String, body: Data? = nil) -> URLRequest {
            var r = URLRequest(url: url, timeoutInterval: 20)
            r.httpMethod = method
            r.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
            r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            r.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            r.setValue("Ullage", forHTTPHeaderField: "User-Agent")
            r.httpBody = body
            return r
        }
        do {
            var sha: String?
            let (gd, gr) = try await URLSession.shared.data(for: req("GET"))
            let gcode = (gr as? HTTPURLResponse)?.statusCode ?? 0
            if gcode == 200 { sha = (try? JSONSerialization.jsonObject(with: gd) as? [String: Any])?["sha"] as? String }
            else if gcode == 404 {
                // Dosya yoksa sorun değil; repo da yoksa PUT 404 döner.
            } else if gcode == 401 || gcode == 403 {
                let m = L.t("GitHub anahtarı geçersiz ya da yetkisiz (repo içeriğine yazma izni gerekir)")
                setStatus(m); return m
            }
            var body: [String: Any] = ["message": "Ullage profil kartı", "content": Data(svg.utf8).base64EncodedString()]
            if let sha { body["sha"] = sha }
            let (_, pr) = try await URLSession.shared.data(for: req("PUT", body: try JSONSerialization.data(withJSONObject: body)))
            let code = (pr as? HTTPURLResponse)?.statusCode ?? 0
            switch code {
            case 200, 201:
                d.set(now, forKey: "ghLastPush"); d.set(hash, forKey: "ghLastHash")
                let m = L.t("Gönderildi")
                setStatus(m); return m
            case 404:
                let m = L.f("%@/%@ reposu bulunamadı. GitHub'da bu adla bir repo aç (README'li, herkese açık).", user, user)
                setStatus(m); return m
            case 401, 403:
                let m = L.t("GitHub anahtarı geçersiz ya da yetkisiz (repo içeriğine yazma izni gerekir)")
                setStatus(m); return m
            default:
                let m = L.f("GitHub hatası (%lld)", code)
                setStatus(m); return m
            }
        } catch {
            let m = L.t("GitHub'a bağlanılamadı")
            setStatus(m); return m
        }
    }
}

// MARK: - Ayarlar

@MainActor
final class GitHubModel: ObservableObject {
    @Published var on = GitHubSync.enabled { didSet { UserDefaults.standard.set(on, forKey: "ghOn") } }
    @Published var user = GitHubSync.user { didSet { UserDefaults.standard.set(user.trimmingCharacters(in: .whitespaces), forKey: "ghUser") } }
    @Published var interval = GitHubSync.interval { didSet { UserDefaults.standard.set(interval, forKey: "ghInterval") } }
    @Published var split = GitHubSync.split { didSet { UserDefaults.standard.set(split, forKey: "ghSplit"); UserDefaults.standard.removeObject(forKey: "ghLastHash") } }
    @Published var dark = GitHubSync.dark { didSet { UserDefaults.standard.set(dark, forKey: "ghDark"); UserDefaults.standard.removeObject(forKey: "ghLastHash") } }
    @Published var tokenInput = ""
    @Published var hasToken = GitHubSync.hasToken
    @Published var status = GitHubSync.status
    @Published var busy = false

    func saveToken() {
        GitHubSync.saveToken(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines))
        tokenInput = ""
        hasToken = GitHubSync.hasToken
    }

    func removeToken() {
        GitHubSync.deleteToken()
        hasToken = false
        status = ""
    }

    func sendNow() {
        busy = true
        Task {
            let m = await GitHubSync.push(force: true)
            status = m
            busy = false
        }
    }

    func copyMarkdown() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(GitHubSync.markdown(user), forType: .string)
        status = L.t("Markdown kopyalandı")
    }
}

struct GitHubProfileSettings: View {
    @EnvironmentObject var state: AppState
    @StateObject private var m = GitHubModel()

    var body: some View {
        let t = state.theme
        SettingRow(title: L.t("GitHub profil kartı"), subtitle: L.t("Token kullanımının ısı haritasını, kendi profil reposundaki bir resim olarak günceller. Resimde yalnızca günlük toplam token vardır (proje, model, sohbet yok). Her güncelleme profilinde bir commit olarak görünür.")) {
            Toggle("", isOn: $m.on).toggleStyle(.switch).labelsHidden()
        }
        if m.on {
            SettingRow(title: L.t("GitHub kullanıcı adı"), subtitle: L.t("Resim, kullanıcıadı/kullanıcıadı adlı profil reposuna yüklenir. Repo yoksa GitHub'da bu adla boş bir herkese açık repo aç.")) {
                TextField("kullanıcıadı", text: $m.user).textFieldStyle(.roundedBorder).frame(width: 180)
            }
            SettingRow(title: L.t("GitHub anahtarı"), subtitle: L.t("GitHub > Settings > Developer settings > Fine-grained tokens: yalnızca bu profil reposunu seç, izin olarak Contents: Read and write ver. Anahtar yalnızca bu Mac'in Anahtar Zinciri'nde durur.")) {
                if m.hasToken {
                    HStack(spacing: 8) {
                        Text(L.t("Kayıtlı")).font(t.font(12)).foregroundStyle(t.sub)
                        Button(L.t("Kaldır")) { m.removeToken() }
                    }
                } else {
                    HStack(spacing: 8) {
                        SecureField("github_pat_…", text: $m.tokenInput).textFieldStyle(.roundedBorder).frame(width: 170)
                        Button(L.t("Kaydet")) { m.saveToken() }.disabled(m.tokenInput.isEmpty)
                    }
                }
            }
            SettingRow(title: L.t("Ne sıklıkta güncellensin"), subtitle: L.t("Veri değişmediyse ya da o gün kullanım yoksa hiçbir şey gönderilmez.")) {
                ThemedSegmented(t: t, items: [(L.t("Günde bir"), "daily"), (L.t("Haftada bir"), "weekly"), (L.t("Elle"), "manual")], selection: $m.interval)
            }
            SettingRow(title: L.t("Servislere göre renklendir"), subtitle: L.t("Kapalıysa tek renk (yeşil tonları).")) {
                Toggle("", isOn: $m.split).toggleStyle(.switch).labelsHidden()
            }
            SettingRow(title: L.t("Koyu kart"), subtitle: L.t("Kapalıysa açık renkli kart.")) {
                Toggle("", isOn: $m.dark).toggleStyle(.switch).labelsHidden()
            }
            SettingRow(title: L.t("Şimdi gönder"), subtitle: m.status.isEmpty ? L.t("Sonra README'ne bu satırı ekle: ") + GitHubSync.markdown(m.user.isEmpty ? "kullanıcıadı" : m.user) : m.status) {
                HStack(spacing: 8) {
                    Button(L.t("Markdown'ı kopyala")) { m.copyMarkdown() }.disabled(m.user.isEmpty)
                    Button(L.t("Şimdi gönder")) { m.sendNow() }.disabled(m.busy || !m.hasToken || m.user.isEmpty)
                }
            }
        }
    }
}
