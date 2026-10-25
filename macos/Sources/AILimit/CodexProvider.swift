import Foundation

/// ~/.codex/sessions altındaki oturum kayıtlarından limit ve token okur. Codex kayıtları .jsonl veya
/// sıkıştırılmış .jsonl.zst olarak yazılır; ikincisi için sistemdeki zstd kullanılır.
enum CodexProvider {
    private static let mtimeKey = "codexMtimes"

    private struct Window { let used: Double; let resets: Double }

    private static let zstdPath: String? = ["/opt/homebrew/bin/zstd", "/usr/local/bin/zstd", "/usr/bin/zstd"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    private static func sessionsRoot() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
    }

    private static func sessionFiles() -> [(url: URL, mod: Date)] {
        guard let en = FileManager.default.enumerator(at: sessionsRoot(), includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var out: [(url: URL, mod: Date)] = []
        for case let url as URL in en {
            let name = url.lastPathComponent
            guard name.hasSuffix(".jsonl") || name.hasSuffix(".jsonl.zst") else { continue }
            let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            out.append((url, mod))
        }
        return out
    }

    /// Dosyanın açık hâlini döndürür. .zst dosyaları zstd ile açılır; zstd yoksa nil.
    private static func readSession(_ url: URL) -> Data? {
        guard url.pathExtension == "zst" else { return try? Data(contentsOf: url) }
        guard let zstd = zstdPath else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: zstd)
        p.arguments = ["-dc", url.path]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? data : nil
    }

    static func read(now: Date = Date()) -> Usage {
        ingest()
        let files = sessionFiles().sorted { $0.mod > $1.mod }
        if zstdPath == nil && files.contains(where: { $0.url.pathExtension == "zst" }) {
            return Usage(notes: [L.t("Codex kayıtları sıkıştırılmış (.zst). Okumak için zstd gerekli: brew install zstd")])
        }
        // En yeni dosyadan başlayıp ilk limit kaydında dur: daha eski dosyalar daha eski değer taşır.
        var latest: (primary: Window?, secondary: Window?, stamp: Date)?
        for f in files {
            guard let data = readSession(f.url), let r = latestRateLimits(in: data) else { continue }
            latest = r
            break
        }
        guard let r = latest else { return Usage(notes: [L.t("Codex kayıtlarında limit bilgisi bulunamadı.")]) }

        var u = Usage(
            fiveHourLeft: left(r.primary, now: now),
            weeklyLeft: left(r.secondary, now: now),
            fiveHourReset: r.primary.map { Date(timeIntervalSince1970: $0.resets) },
            weeklyReset: r.secondary.map { Date(timeIntervalSince1970: $0.resets) },
            todayTokens: HistoryStore.shared.sums(provider: "codex", since: Calendar.current.startOfDay(for: now)).billable,
            limitConfidence: .exact,
            tokenConfidence: .exact
        )
        let fmt = DateFormatter()
        fmt.dateStyle = .medium; fmt.timeStyle = .short
        u.notes.append(L.f("Limit ve token: Codex oturum kayıtlarından (son kayıt %@).", fmt.string(from: r.stamp)))
        if let p = r.primary, p.resets <= now.timeIntervalSince1970 {
            u.notes.append(L.t("Son kayıttan beri 5 saatlik pencere sıfırlandı; yeni kullanım olmadığı için %100 gösteriliyor."))
        }
        if let w = r.secondary, w.resets <= now.timeIntervalSince1970 {
            u.notes.append(L.t("Haftalık pencere sıfırlandı; yeni kullanım olmadığı için %100 gösteriliyor."))
        }
        return u
    }

    private static func latestRateLimits(in data: Data) -> (primary: Window?, secondary: Window?, stamp: Date)? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var best: (primary: Window?, secondary: Window?, stamp: Date)?
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard line.range(of: Data("rate_limits".utf8)) != nil,
                  let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any],
                  let rl = payload["rate_limits"] as? [String: Any],
                  let ts = (obj["timestamp"] as? String).flatMap(iso.date(from:))
            else { continue }
            if best == nil || ts > best!.stamp {
                best = (window(rl["primary"]), window(rl["secondary"]), ts)
            }
        }
        return best
    }

    /// Bu dosyaların token kayıtlarını HistoryStore'a işler. Değişmemiş dosyalar atlanır, değişenler
    /// kaldığı yerden (bayt konumu) okunur.
    private static func ingest() {
        if !UserDefaults.standard.bool(forKey: "codexIngestV3") {
            HistoryStore.shared.reset(provider: "codex", pathContains: "/.codex/sessions/")
            UserDefaults.standard.removeObject(forKey: mtimeKey)
            UserDefaults.standard.set(true, forKey: "codexIngestV3")
        }
        let store = HistoryStore.shared
        var mtimes = UserDefaults.standard.dictionary(forKey: mtimeKey) as? [String: Double] ?? [:]
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for f in sessionFiles() {
            let mod = f.mod.timeIntervalSince1970
            if mtimes[f.url.path] == mod { continue }
            guard let data = readSession(f.url) else { continue }
            let start = store.fileOffset(f.url.path)
            if data.count > start, let lastNL = data.lastIndex(of: UInt8(ascii: "\n")), lastNL >= start {
                let complete = data[start...lastNL]
                var model = "codex"
                var prevTotal = store.fileTotal(f.url.path) ?? 0
                var events: [HistoryStore.Event] = []
                for line in complete.split(separator: UInt8(ascii: "\n")) {
                    guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                          let payload = obj["payload"] as? [String: Any] else { continue }
                    if obj["type"] as? String == "turn_context", let m = payload["model"] as? String { model = m; continue }
                    guard payload["type"] as? String == "token_count",
                          let info = payload["info"] as? [String: Any],
                          let last = info["last_token_usage"] as? [String: Any],
                          let total = (info["total_token_usage"] as? [String: Any])?["total_tokens"] as? Int,
                          let ts = (obj["timestamp"] as? String).flatMap(iso.date(from:)),
                          let ord = obj["ordinal"] as? Int else { continue }
                    // Aynı toplamı taşıyan tekrar olaylar çift sayılmasın.
                    if total == prevTotal { continue }
                    prevTotal = total
                    let input = last["input_tokens"] as? Int ?? 0
                    let cached = last["cached_input_tokens"] as? Int ?? 0
                    events.append(.init(
                        provider: "codex", key: "\(f.url.lastPathComponent)|\(ord)", ts: ts.timeIntervalSince1970,
                        model: model, input: max(0, input - cached),
                        output: last["output_tokens"] as? Int ?? 0, cacheWrite: 0, cacheRead: cached
                    ))
                }
                store.upsert(events)
                store.setFileTotal(f.url.path, prevTotal)
                store.setFileOffset(f.url.path, lastNL + 1)
            }
            mtimes[f.url.path] = mod
        }
        UserDefaults.standard.set(mtimes, forKey: mtimeKey)
    }

    private static func window(_ any: Any?) -> Window? {
        guard let d = any as? [String: Any],
              let used = d["used_percent"] as? Double,
              let resets = d["resets_at"] as? Double else { return nil }
        return Window(used: used, resets: resets)
    }

    /// Pencere sıfırlandıysa (resets_at geçmişte) kullanım 0 sayılır.
    private static func left(_ w: Window?, now: Date) -> Double? {
        guard let w else { return nil }
        if w.resets <= now.timeIntervalSince1970 { return 1 }
        return max(0, min(1, 1 - w.used / 100))
    }
}
