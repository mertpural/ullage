import Foundation

/// Gemini CLI'ın Google oturumuyla (~/.gemini/oauth_creds.json) Code Assist kota API'sinden model
/// başına kalan kotayı okur. Erişim anahtarı süresi dolmuşsa yenilenir; yenilenen anahtar yalnızca
/// bellekte tutulur, Gemini CLI'ın dosyasına yazılmaz.
enum GeminiProvider {
    /// Oturumu yenilemek için gereken Google istemci kimliği kaynak kodda taşınmaz: ortam değişkenlerinden ya da kullanıcının
    /// kurulu Gemini CLI paketinden okunur. Bulunamazsa süresi geçmemiş erişim anahtarı yine kullanılır.
    nonisolated(unsafe) private static var cachedClient: (id: String, secret: String)??

    private static func sh(_ exe: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let d = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: d, encoding: .utf8) ?? ""
    }

    private static func oauthClient() -> (id: String, secret: String)? {
        if let c = cachedClient { return c }
        var found: (id: String, secret: String)?
        let env = ProcessInfo.processInfo.environment
        if let i = env["GEMINI_OAUTH_CLIENT_ID"], let s = env["GEMINI_OAUTH_CLIENT_SECRET"] {
            found = (i, s)
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let roots = ["/opt/homebrew/lib/node_modules", "/usr/local/lib/node_modules", "\(home)/.npm-global/lib/node_modules", "\(home)/.nvm/versions"]
                .filter { FileManager.default.fileExists(atPath: $0) }
            func grab(_ key: String, in dirs: [String]) -> String? {
                for d in dirs {
                    let out = sh("/usr/bin/grep", ["-rhoE", "-m1", "\(key) *= *['\"][^'\"]+", d, "--include=*.js"])
                    if let line = out.split(separator: "\n").first,
                       let q = line.firstIndex(where: { $0 == "'" || $0 == "\"" }) {
                        return String(line[line.index(after: q)...])
                    }
                }
                return nil
            }
            let pkgDirs = roots.flatMap { r in
                sh("/usr/bin/find", [r, "-maxdepth", "7", "-type", "d", "-name", "gemini-cli*"]).split(separator: "\n").map(String.init)
            }
            if let i = grab("OAUTH_CLIENT_ID", in: pkgDirs), let s = grab("OAUTH_CLIENT_SECRET", in: pkgDirs) { found = (i, s) }
        }
        cachedClient = .some(found)
        return found
    }

    private static let base = "https://cloudcode-pa.googleapis.com/v1internal"

    nonisolated(unsafe) private static var cachedToken: (value: String, expires: Date)?
    nonisolated(unsafe) private static var cachedResult: (at: Date, usage: Usage)?
    nonisolated(unsafe) static var lastRaw = ""

    static func invalidate() {
        if let c = cachedResult, Date().timeIntervalSince(c.at) > 30 { cachedResult = nil }
    }

    static func read() async -> Usage {
        if let c = cachedResult, Date().timeIntervalSince(c.at) < 120 { return c.usage }
        let u = await fetch()
        cachedResult = (Date(), u)
        return u
    }

    private static func fail(_ msg: String) -> Usage { Usage(notes: ["Limit alınamadı: \(msg)"]) }

    private static func accessToken() async -> Result<String, LimitError> {
        if let t = cachedToken, t.expires > Date().addingTimeInterval(60) { return .success(t.value) }
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/oauth_creds.json")
        guard let data = try? Data(contentsOf: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(LimitError(message: "Gemini CLI oturumu bulunamadı (~/.gemini/oauth_creds.json)"))
        }
        if let tok = obj["access_token"] as? String, let exp = obj["expiry_date"] as? Double,
           Date(timeIntervalSince1970: exp / 1000) > Date().addingTimeInterval(60) {
            cachedToken = (tok, Date(timeIntervalSince1970: exp / 1000))
            return .success(tok)
        }
        guard let refresh = obj["refresh_token"] as? String else {
            return .failure(LimitError(message: "Oturum süresi dolmuş ve yenileme anahtarı yok"))
        }
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        guard let client = oauthClient() else {
            return .failure(LimitError(message: "Oturum süresi dolmuş ve yenilemek için Gemini CLI kurulu değil (npm i -g @google/gemini-cli, sonra bir kez giriş yap)"))
        }
        let form = ["client_id": client.id, "client_secret": client.secret, "refresh_token": refresh, "grant_type": "refresh_token"]
        req.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        guard let (d, r) = try? await URLSession.shared.data(for: req) else { return .failure(LimitError(message: "Ağ hatası")) }
        let code = (r as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200, let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let tok = o["access_token"] as? String else {
            return .failure(LimitError(message: "Oturum yenilenemedi (\(code)); Gemini CLI'ı bir kez çalıştırıp giriş yap"))
        }
        let life = o["expires_in"] as? Double ?? 3000
        cachedToken = (tok, Date().addingTimeInterval(life))
        return .success(tok)
    }

    private static func call(_ method: String, token: String, body: [String: Any]) async -> (Int, [String: Any])? {
        var req = URLRequest(url: URL(string: "\(base):\(method)")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (d, r) = try? await URLSession.shared.data(for: req) else { return nil }
        lastRaw = String(data: d, encoding: .utf8) ?? ""
        return ((r as? HTTPURLResponse)?.statusCode ?? 0, (try? JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:])
    }

    private static func fetch() async -> Usage {
        let token: String
        switch await accessToken() {
        case .success(let t): token = t
        case .failure(let e): return fail(e.message)
        }
        let meta: [String: Any] = ["metadata": ["ideType": "IDE_UNSPECIFIED", "platform": "PLATFORM_UNSPECIFIED", "pluginType": "GEMINI"]]
        var project: String?
        if let (code, o) = await call("loadCodeAssist", token: token, body: meta), code == 200 {
            if let p = o["cloudaicompanionProject"] as? String { project = p }
            else if let p = (o["cloudaicompanionProject"] as? [String: Any])?["id"] as? String { project = p }
        }
        guard let (code, o) = await call("retrieveUserQuota", token: token, body: project.map { ["project": $0] } ?? [:]) else {
            return fail("Ağ hatası")
        }
        guard code == 200, let buckets = o["buckets"] as? [[String: Any]], !buckets.isEmpty else {
            let err = o["error"] as? [String: Any]
            let reason = ((err?["details"] as? [[String: Any]])?.compactMap { $0["reason"] as? String }.first)
            if reason == "SUBSCRIPTION_REQUIRED" {
                return fail("Bu Google hesabında Gemini Code Assist lisansı yok, Google kota bilgisini vermiyor (SUBSCRIPTION_REQUIRED)")
            }
            return fail("Kota yanıtı \(code) döndürdü\(reason.map { " (\($0))" } ?? "")")
        }

        // Model gruplarına göre en düşük kalan oranı al (CodexBar ile aynı gruplama).
        var groups: [String: (left: Double, reset: Date?)] = [:]
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for b in buckets {
            guard let f = b["remainingFraction"] as? Double, let id = (b["modelId"] as? String)?.lowercased() else { continue }
            let name = id.contains("flash-lite") ? "Flash Lite" : (id.contains("flash") ? "Flash" : (id.contains("pro") ? "Pro" : id))
            let reset = (b["resetTime"] as? String).flatMap { iso.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
            if let cur = groups[name], cur.left <= f { continue }
            groups[name] = (f, reset)
        }
        let order = ["Pro", "Flash", "Flash Lite"]
        let rows = groups.sorted { (order.firstIndex(of: $0.key) ?? 9) < (order.firstIndex(of: $1.key) ?? 9) }
            .map { LimitRow(title: "\($0.key) · günlük kota", left: max(0, min(1, $0.value.left)), reset: $0.value.reset) }
        var u = Usage(extra: rows, limitConfidence: .exact)
        u.notes.append("Limit: Google Code Assist kota API'sinden (Gemini CLI oturumuyla). Gemini'de 5 saatlik/haftalık pencere yok, günlük kota var.")
        u.notes.append("Token sayısı yerelde tutulmuyor.")
        return u
    }
}
