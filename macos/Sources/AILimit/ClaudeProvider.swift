import Foundation

/// Claude Code ve Claude Desktop (Code sekmesi) ~/.claude/projects altına yazar: token geçmişi oradan okunur.
/// Gerçek 5 saatlik/haftalık yüzde yerelde yok; Anthropic'in kullanım uç noktasından, Claude Code'un
/// Keychain'deki oturumuyla alınır. Erişilemezse kullanıcının kalibre ettiği tavanla tahmin edilir.
enum ClaudeProvider {
    static func read(now: Date = Date()) async -> Usage {
        ingest()
        let store = HistoryStore.shared
        let today = store.sums(provider: "claude", since: Calendar.current.startOfDay(for: now)).billable
        var u = Usage(todayTokens: today, tokenConfidence: .exact)
        u.notes.append(L.t("Token: ~/.claude kayıtlarından (Claude Code ve Desktop), cache okumaları hariç."))

        switch await ClaudeLimitAPI.fetch() {
        case .success(let r):
            // Sıfırlanma saati geçmiş pencere yenilenmiştir: eski değer yerine %100 gösterilir.
            u.fiveHourLeft = (r.fiveHourReset.map { $0 <= now } ?? false) ? 1 : r.fiveHourLeft
            u.weeklyLeft = (r.weeklyReset.map { $0 <= now } ?? false) ? 1 : r.weeklyLeft
            u.fiveHourReset = r.fiveHourReset
            u.weeklyReset = r.weeklyReset
            let age = Date().timeIntervalSince(r.fetchedAt)
            // Limit yalnızca Claude kullanılınca değişir: değerden sonra yerel kullanım yoksa eski sayılmaz.
            let usedSince = store.latestEvent(provider: "claude") > r.fetchedAt.addingTimeInterval(90)
            if age < 600 || !usedSince {
                u.limitConfidence = .exact
                u.notes.append(L.t(r.fromCLI
                    ? "Limit: Claude Code komutundan ölçüldü (tek satırlık küçük bir istek)."
                    : r.fromStatusLine
                    ? "Limit: Claude Code'un durum satırından (yerel, ağ gerekmez)."
                    : "Limit: Anthropic kullanım uç noktasından (resmi olmayan, Claude Code oturumuyla)."))
            } else {
                let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = age > 86400 ? .short : .none
                u.limitConfidence = .estimate
                u.staleSince = r.fetchedAt
                u.notes.append(L.f("Anthropic hız sınırı uyguladığı için son alınan değer gösteriliyor (%@); güncel olmayabilir.", f.string(from: r.fetchedAt)))
            }
        case .failure(let err):
            u.notes.append(L.f("Limit yüzdesi alınamadı: %@", err.message))
        }
        return u
    }

    private static func ingest() {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return }
        let store = HistoryStore.shared
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let marker = Data("\"usage\"".utf8)
        // Proje adı sonradan eklendi: eski kayıtlara işlemek için dosyalar bir kez baştan okunur.
        if !UserDefaults.standard.bool(forKey: "projectBackfill1") {
            store.rescan(pathContains: "/.claude/projects/")
            UserDefaults.standard.set(true, forKey: "projectBackfill1")
        }

        for case let url as URL in en where url.pathExtension == "jsonl" {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            let start = store.fileOffset(url.path)
            guard size > start, let h = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? h.close() }
            try? h.seek(toOffset: UInt64(start))
            guard let data = try? h.readToEnd(), !data.isEmpty else { continue }

            // Yarım yazılmış son satırı bir sonraki tura bırak.
            guard let lastNL = data.lastIndex(of: UInt8(ascii: "\n")) else { continue }
            let complete = data[data.startIndex...lastNL]

            var events: [HistoryStore.Event] = []
            for line in complete.split(separator: UInt8(ascii: "\n")) {
                guard line.range(of: marker) != nil,
                      let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      obj["type"] as? String == "assistant",
                      let msg = obj["message"] as? [String: Any],
                      let usage = msg["usage"] as? [String: Any],
                      let mid = msg["id"] as? String,
                      let ts = (obj["timestamp"] as? String).flatMap(iso.date(from:))
                else { continue }
                let req = obj["requestId"] as? String ?? ""
                events.append(.init(
                    provider: "claude", key: "\(mid)|\(req)", ts: ts.timeIntervalSince1970,
                    model: msg["model"] as? String ?? "",
                    input: usage["input_tokens"] as? Int ?? 0,
                    output: usage["output_tokens"] as? Int ?? 0,
                    cacheWrite: usage["cache_creation_input_tokens"] as? Int ?? 0,
                    cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0,
                    project: (obj["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
                ))
            }
            store.upsert(events)
            store.setFileOffset(url.path, start + complete.count)
        }
    }
}

struct LimitError: Error {
    let message: String
    var retryAfter: TimeInterval? = nil
}

struct ClaudeLimits {
    var fiveHourLeft: Double?, weeklyLeft: Double?
    var fiveHourReset: Date?, weeklyReset: Date?
    var fetchedAt = Date()
    var fromStatusLine = false
    var fromCLI = false
}

/// Claude Code'un Keychain'e yazdığı OAuth erişim anahtarıyla kullanım yüzdelerini okur.
/// Anahtar yenilenmez (Claude Code'un kendi oturumunu bozmamak için), yalnızca bellekte tutulur,
/// diske yazılmaz ve loglanmaz.
enum ClaudeLimitAPI {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var token: (value: String, expires: Date?)?
    nonisolated(unsafe) private static var keychainRetryAt = Date.distantPast
    nonisolated(unsafe) private static var cached: (at: Date, result: Result<ClaudeLimits, LimitError>)?

    /// Hız sınırı bekleme süresi uygulama yeniden başlatılınca da korunur (her açılışta tekrar sınıra çarpmamak için).
    nonisolated(unsafe) private static var backoffUntil = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "claudeBackoffUntil"))

    /// Anthropic'e iki sorgu arasındaki en kısa süre. Uygulama kapanıp açılsa da korunur (son deneme zamanı saklanır).
    /// Yeni yerel Claude kullanımı varsa dakikada bir, yoksa 10 dakikada bir sorulur: limit yalnızca kullanınca değişir.
    private static var minInterval: TimeInterval {
        let last = UserDefaults.standard.double(forKey: "claudeLastAttempt")
        let newest = HistoryStore.shared.latestEvent(provider: "claude").timeIntervalSince1970
        return newest > last - 5 ? 60 : 600
    }
    private static let lastAttemptKey = "claudeLastAttempt"

    /// Elle yenilemede önbelleği atlar, ama 30 saniyeden sık sorgu yapılmaz (Anthropic hız sınırı).
    static func invalidate() {
        lock.lock(); defer { lock.unlock() }
        // Elle yenileme de Claude için en sık dakikada bir gerçek sorgu yapar (senkron süresi ne olursa olsun).
        let last = UserDefaults.standard.double(forKey: lastAttemptKey)
        if Date().timeIntervalSince1970 - last > minInterval {
            cached = nil
            UserDefaults.standard.set(0, forKey: lastAttemptKey)
        }
    }
    private static let storeKey = "claudeLastLimits"

    /// Anthropic'in hız sınırı bekleme süresi bitiş saati; bekleme yoksa nil.
    static var backoffEnd: Date? {
        let d = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "claudeBackoffUntil"))
        return d > Date() ? d : nil
    }

    private static func store(_ l: ClaudeLimits) {
        var d: [String: Double] = ["at": l.fetchedAt.timeIntervalSince1970]
        if let v = l.fiveHourLeft { d["five"] = v }
        if let v = l.weeklyLeft { d["week"] = v }
        if let v = l.fiveHourReset { d["fiveReset"] = v.timeIntervalSince1970 }
        if let v = l.weeklyReset { d["weekReset"] = v.timeIntervalSince1970 }
        UserDefaults.standard.set(d, forKey: storeKey)
    }

    private static func stored() -> ClaudeLimits? {
        guard let d = UserDefaults.standard.dictionary(forKey: storeKey) as? [String: Double], let at = d["at"] else { return nil }
        return ClaudeLimits(
            fiveHourLeft: d["five"], weeklyLeft: d["week"],
            fiveHourReset: d["fiveReset"].map { Date(timeIntervalSince1970: $0) },
            weeklyReset: d["weekReset"].map { Date(timeIntervalSince1970: $0) },
            fetchedAt: Date(timeIntervalSince1970: at)
        )
    }

    /// Uç noktayı en fazla 5 dakikada bir sorgular; hız sınırına (429) takılırsa Retry-After süresince
    /// beklenir ve bu sürede son başarılı değer (yaşıyla birlikte) döndürülür.
    static func fetch() async -> Result<ClaudeLimits, LimitError> {
        let r = await fetchViaAPI()
        if case .success(let l) = r {
            let age = Date().timeIntervalSince(l.fetchedAt)
            // Taze sayılır: durum satırı 15 dakikaya, diğerleri bir buçuk dakikaya kadar. Daha eskiyse (hız sınırı, bekleme)
            // ve yeni kullanım varsa ölçüm CLIProbe'un kendi 5 dakikalık sınırıyla yapılır.
            if age < 90 || (l.fromStatusLine && age < 900) { return r }
        }
        // Taze değer yok (hız sınırı, bekleme ya da hiç kayıt yok): Claude'un kendi komutundan ölçmeyi dene.
        if let p = await CLIProbe.measureIfDue(stored: { lock.lock(); defer { lock.unlock() }; return stored() }) {
            lock.lock(); store(p); lock.unlock()
            return .success(p)
        }
        return r
    }

    private static func fetchViaAPI() async -> Result<ClaudeLimits, LimitError> {
        // Claude Code'un durum satırından yazılan yerel dosya taze ise ağa hiç gidilmez.
        if let f = StatusLine.read(), Date().timeIntervalSince(f.fetchedAt) < 900 {
            lock.lock(); store(f); lock.unlock()
            return .success(f)
        }
        lock.lock()
        if let c = cached, Date().timeIntervalSince(c.at) < minInterval { lock.unlock(); return c.result }
        let waiting = Date() < backoffUntil
        lock.unlock()

        if waiting {
            if let old = stored() { return .success(old) }
            return .failure(LimitError(message: L.t("Anthropic hız sınırı uyguladı; biraz sonra yeniden denenecek")))
        }

        let sinceLast = Date().timeIntervalSince1970 - UserDefaults.standard.double(forKey: lastAttemptKey)
        if sinceLast < minInterval, let old = stored() { return .success(old) }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastAttemptKey)

        let result = await request(retryWithFreshToken: true)
        lock.lock(); defer { lock.unlock() }
        switch result {
        case .success(let l):
            store(l)
            cached = (Date(), result)
            return result
        case .failure(let e):
            if let r = e.retryAfter { backoffUntil = Date().addingTimeInterval(max(300, r)); UserDefaults.standard.set(backoffUntil.timeIntervalSince1970, forKey: "claudeBackoffUntil") }
            else { cached = (Date().addingTimeInterval(-minInterval + 120), result) } // hata durumunda 1 dk sonra yeniden dene
            if let old = stored() { return .success(old) }
            return result
        }
    }

    private static func loadToken(forceReload: Bool) -> Result<String, LimitError> {
        lock.lock()
        if !forceReload, let t = token, (t.expires ?? .distantFuture) > Date().addingTimeInterval(30) {
            lock.unlock(); return .success(t.value)
        }
        // Keychain okuması reddedildiyse (izin penceresi kapatıldı ya da "İzin verme" seçildi) 15 dakika yeniden sorulmaz;
        // aksi hâlde uyku sonrası her yenilemede izin penceresi tekrar çıkar.
        if Date() < keychainRetryAt {
            lock.unlock()
            return .failure(LimitError(message: L.t("Claude Code oturumu Keychain'de bulunamadı ya da erişim reddedildi")))
        }
        lock.unlock()

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return .failure(LimitError(message: L.t("Keychain okunamadı"))) }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let access = oauth["accessToken"] as? String
        else {
            lock.lock(); keychainRetryAt = Date().addingTimeInterval(900); lock.unlock()
            return .failure(LimitError(message: L.t("Claude Code oturumu Keychain'de bulunamadı ya da erişim reddedildi")))
        }

        let expires = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        lock.lock(); token = (access, expires); lock.unlock()
        return .success(access)
    }

    /// Claude Code'un oturum anahtarı süresi dolduğunda, onu Claude Code'un kendisine yeniletir: tek satırlık bir Haiku
    /// isteği çalıştırır, Claude Code anahtarı kendi yenileyip Keychain'e yazar. Anahtarlara bu uygulama dokunmaz.
    /// En sık 30 dakikada bir denenir; Ayarlar'dan kapatılabilir.
    private static func refreshLoginViaCLI() async -> Bool {
        let d = UserDefaults.standard
        if d.object(forKey: "refreshLogin") as? Bool == false { return false }
        if Date().timeIntervalSince1970 - d.double(forKey: "claudeLoginRefreshAt") < 1800 { return false }
        d.set(Date().timeIntervalSince1970, forKey: "claudeLoginRefreshAt")
        guard let cli = WindowStarter.cliPath else { return false }
        return await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: cli)
                p.arguments = ["-p", "--model", "haiku", "--no-session-persistence", "--tools", "", "--", "Reply with only: ok"]
                p.currentDirectoryURL = FileManager.default.temporaryDirectory
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                p.environment = env
                p.standardOutput = Pipe(); p.standardError = Pipe()
                do { try p.run() } catch { cont.resume(returning: false); return }
                let done = DispatchSemaphore(value: 0)
                DispatchQueue.global().async { p.waitUntilExit(); done.signal() }
                if done.wait(timeout: .now() + 90) == .timedOut { p.terminate(); cont.resume(returning: false); return }
                cont.resume(returning: p.terminationStatus == 0)
            }
        }
    }

    private static func request(retryWithFreshToken: Bool) async -> Result<ClaudeLimits, LimitError> {
        var tok: String
        switch loadToken(forceReload: !retryWithFreshToken) {
        case .success(let t): tok = t
        case .failure(let e): return .failure(e)
        }
        // Süresi dolmuş oturum: anahtara dokunmadan, Claude Code'un kendisine yeniletilir.
        lock.lock(); let exp = token?.expires; lock.unlock()
        if let e = exp, e < Date().addingTimeInterval(120), await refreshLoginViaCLI(),
           case .success(let fresh) = loadToken(forceReload: true) { tok = fresh }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.timeoutInterval = 15
        req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 {
                if retryWithFreshToken {
                    _ = await refreshLoginViaCLI()
                    return await request(retryWithFreshToken: false)
                }
                return .failure(LimitError(message: L.t("Oturum süresi dolmuş; Claude Code'u açınca yenilenir")))
            }
            if code == 429 {
                let ra = ((resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "retry-after")).flatMap(Double.init) ?? 300
                return .failure(LimitError(message: L.t("Anthropic hız sınırı uyguladı (429)"), retryAfter: ra))
            }
            guard code == 200, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(LimitError(message: L.f("Uç nokta %lld döndürdü", code)))
            }
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let iso2 = ISO8601DateFormatter()
            func window(_ key: String) -> (Double, Date?)? {
                guard let w = obj[key] as? [String: Any], let u = w["utilization"] as? Double else { return nil }
                let reset = (w["resets_at"] as? String).flatMap { iso.date(from: $0) ?? iso2.date(from: $0) }
                return (max(0, min(1, 1 - u / 100)), reset)
            }
            let five = window("five_hour"), week = window("seven_day")
            if five == nil && week == nil { return .failure(LimitError(message: L.t("Yanıtta limit alanı yok"))) }
            return .success(ClaudeLimits(
                fiveHourLeft: five?.0, weeklyLeft: week?.0,
                fiveHourReset: five?.1, weeklyReset: week?.1
            ))
        } catch {
            return .failure(LimitError(message: L.t("Ağ hatası")))
        }
    }
}
