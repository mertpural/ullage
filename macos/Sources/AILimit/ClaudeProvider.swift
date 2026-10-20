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
        u.notes.append("Token: ~/.claude kayıtlarından (Claude Code ve Desktop), cache okumaları hariç.")

        switch await ClaudeLimitAPI.fetch() {
        case .success(let r):
            // Sıfırlanma saati geçmiş pencere yenilenmiştir: eski değer yerine %100 gösterilir.
            u.fiveHourLeft = (r.fiveHourReset.map { $0 <= now } ?? false) ? 1 : r.fiveHourLeft
            u.weeklyLeft = (r.weeklyReset.map { $0 <= now } ?? false) ? 1 : r.weeklyLeft
            u.fiveHourReset = r.fiveHourReset
            u.weeklyReset = r.weeklyReset
            let age = Date().timeIntervalSince(r.fetchedAt)
            if age < 600 {
                u.limitConfidence = .exact
                u.notes.append("Limit: Anthropic kullanım uç noktasından (resmi olmayan, Claude Code oturumuyla).")
            } else {
                let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = age > 86400 ? .short : .none
                u.limitConfidence = .estimate
                u.staleSince = r.fetchedAt
                u.notes.append("Anthropic hız sınırı uyguladığı için son alınan değer gösteriliyor (\(f.string(from: r.fetchedAt))); güncel olmayabilir.")
            }
        case .failure(let err):
            u.notes.append("Limit yüzdesi alınamadı: \(err.message)")
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
                    cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0
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
}

/// Claude Code'un Keychain'e yazdığı OAuth erişim anahtarıyla kullanım yüzdelerini okur.
/// Anahtar yenilenmez (Claude Code'un kendi oturumunu bozmamak için), yalnızca bellekte tutulur,
/// diske yazılmaz ve loglanmaz.
enum ClaudeLimitAPI {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var token: (value: String, expires: Date?)?
    nonisolated(unsafe) private static var cached: (at: Date, result: Result<ClaudeLimits, LimitError>)?

    /// Hız sınırı bekleme süresi uygulama yeniden başlatılınca da korunur (her açılışta tekrar sınıra çarpmamak için).
    nonisolated(unsafe) private static var backoffUntil = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "claudeBackoffUntil"))

    /// Anthropic'e iki sorgu arasındaki en kısa süre. Uygulama kapanıp açılsa da korunur (son deneme zamanı saklanır).
    private static let minInterval: TimeInterval = 60
    private static let lastAttemptKey = "claudeLastAttempt"

    /// Elle yenilemede önbelleği atlar, ama 30 saniyeden sık sorgu yapılmaz (Anthropic hız sınırı).
    static func invalidate() {
        lock.lock(); defer { lock.unlock() }
        // Elle yenileme en sık 2 dakikada bir gerçek sorgu yapar.
        let last = UserDefaults.standard.double(forKey: lastAttemptKey)
        if Date().timeIntervalSince1970 - last > 30 {
            cached = nil
            UserDefaults.standard.set(0, forKey: lastAttemptKey)
        }
    }
    private static let storeKey = "claudeLastLimits"

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
        lock.lock()
        if let c = cached, Date().timeIntervalSince(c.at) < minInterval { lock.unlock(); return c.result }
        let waiting = Date() < backoffUntil
        lock.unlock()

        if waiting {
            if let old = stored() { return .success(old) }
            return .failure(LimitError(message: "Anthropic hız sınırı uyguladı; biraz sonra yeniden denenecek"))
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
        lock.unlock()

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return .failure(LimitError(message: "Keychain okunamadı")) }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let access = oauth["accessToken"] as? String
        else { return .failure(LimitError(message: "Claude Code oturumu Keychain'de bulunamadı ya da erişim reddedildi")) }

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
                return .failure(LimitError(message: "Oturum süresi dolmuş; Claude Code'u açınca yenilenir"))
            }
            if code == 429 {
                let ra = ((resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "retry-after")).flatMap(Double.init) ?? 300
                return .failure(LimitError(message: "Anthropic hız sınırı uyguladı (429)", retryAfter: ra))
            }
            guard code == 200, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(LimitError(message: "Uç nokta \(code) döndürdü"))
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
            if five == nil && week == nil { return .failure(LimitError(message: "Yanıtta limit alanı yok")) }
            return .success(ClaudeLimits(
                fiveHourLeft: five?.0, weeklyLeft: week?.0,
                fiveHourReset: five?.1, weeklyReset: week?.1
            ))
        } catch {
            return .failure(LimitError(message: "Ağ hatası"))
        }
    }
}
