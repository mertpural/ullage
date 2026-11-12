import Foundation

/// Ek araçlar: OpenCode, Kimi CLI, Cline / Roo Code. Yalnızca token sayısı okunur (bu araçlarda kalan limit yok,
/// kullanıcının kendi API anahtarıyla çalışırlar). Bilgisayarda izi yoksa hiç görünmezler; çekirdek dört servise dokunmaz.
///
/// Kayıt biçimleri belgelerden alındı, bu Mac'te araçlar kurulu olmadığı için gerçek veriyle değil örnek dosyalarla denendi.
/// Alanlar okunamazsa o kayıt atlanır, hata vermez.
enum ExtraProviders {
    static let all: [Provider] = [.opencode, .kimi, .cline]

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: (at: Date, list: [Provider])?

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// Kayıt klasörleri.
    static func roots(_ p: Provider) -> [URL] {
        switch p {
        case .opencode:
            return [home.appendingPathComponent(".local/share/opencode/storage/message")]
        case .kimi:
            return [home.appendingPathComponent(".kimi/sessions"), home.appendingPathComponent(".kimi-code/sessions")]
        case .cline:
            let apps = ["Code", "Code - Insiders", "Cursor", "Windsurf", "VSCodium"]
            let ids = ["saoudrizwan.claude-dev", "rooveterinaryinc.roo-cline"]
            return apps.flatMap { a in ids.map { home.appendingPathComponent("Library/Application Support/\(a)/User/globalStorage/\($0)/tasks") } }
        default:
            return []
        }
    }

    /// Verisi bulunan ek araçlar (klasörü var ya da daha önce olay kaydedilmiş). 60 saniye önbelleğe alınır.
    static func present(force: Bool = false) -> [Provider] {
        lock.lock(); defer { lock.unlock() }
        if !force, let c = cache, Date().timeIntervalSince(c.at) < 60 { return c.list }
        let fm = FileManager.default
        let list = all.filter { p in
            roots(p).contains { fm.fileExists(atPath: $0.path) } || HistoryStore.shared.latestEvent(provider: p.rawValue) > .distantPast
        }
        cache = (Date(), list)
        return list
    }

    static func read(_ p: Provider, now: Date = Date()) -> Usage {
        ingest(p)
        let today = HistoryStore.shared.sums(provider: p.rawValue, since: Calendar.current.startOfDay(for: now)).billable
        var u = Usage(todayTokens: today, tokenConfidence: .exact)
        u.notes.append(L.t("Bu araçta kalan limit okunmuyor; yalnızca token sayılıyor."))
        return u
    }

    // MARK: Okuma

    private static func files(_ p: Provider) -> [(url: URL, mod: Double)] {
        var out: [(URL, Double)] = []
        for root in roots(p) {
            guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for case let url as URL in en {
                let n = url.lastPathComponent
                let ok: Bool
                switch p {
                case .opencode: ok = n.hasPrefix("msg_") && n.hasSuffix(".json")
                case .kimi: ok = n == "wire.jsonl"
                default: ok = n == "ui_messages.json"
                }
                guard ok else { continue }
                let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970 ?? 0
                out.append((url, mod))
            }
        }
        return out
    }

    private static func int(_ any: Any?) -> Int {
        if let n = any as? NSNumber { return max(0, n.intValue) }
        if let s = any as? String, let v = Int(s) { return max(0, v) }
        return 0
    }

    /// Saniye ya da milisaniye (sayı) ya da ISO metin olarak gelen zamanı saniyeye çevirir.
    private static func seconds(_ any: Any?) -> Double? {
        if let n = any as? NSNumber {
            let v = n.doubleValue
            return v > 1e11 ? v / 1000 : v
        }
        if let s = any as? String {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: s) { return d.timeIntervalSince1970 }
            f.formatOptions = [.withInternetDateTime]
            return f.date(from: s)?.timeIntervalSince1970
        }
        return nil
    }

    private static func ingest(_ p: Provider) {
        let mtimeKey = "extraMtimes_\(p.rawValue)"
        var mtimes = UserDefaults.standard.dictionary(forKey: mtimeKey) as? [String: Double] ?? [:]
        var events: [HistoryStore.Event] = []
        for f in files(p) {
            if mtimes[f.url.path] == f.mod { continue }
            guard let data = try? Data(contentsOf: f.url) else { continue }
            switch p {
            case .opencode: events += parseOpenCode(data, name: f.url.lastPathComponent)
            case .kimi: events += parseKimi(data, path: f.url.path, fallback: f.mod)
            default: events += parseCline(data, task: f.url.deletingLastPathComponent().lastPathComponent, roo: f.url.path.contains("roo-cline"))
            }
            mtimes[f.url.path] = f.mod
            if events.count > 2000 { HistoryStore.shared.upsert(events); events.removeAll() }
        }
        if !events.isEmpty { HistoryStore.shared.upsert(events) }
        UserDefaults.standard.set(mtimes, forKey: mtimeKey)
    }

    // OpenCode: storage/message/<oturum>/msg_<id>.json → {role, modelID, time.created (ms), tokens{input,output,reasoning,cache{read,write}}}
    static func parseOpenCode(_ data: Data, name: String) -> [HistoryStore.Event] {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              o["role"] as? String == "assistant",
              let t = o["tokens"] as? [String: Any] else { return [] }
        let cache = t["cache"] as? [String: Any] ?? [:]
        let input = int(t["input"]), output = int(t["output"]) + int(t["reasoning"])
        let cw = int(cache["write"]), cr = int(cache["read"])
        guard input + output + cw + cr > 0,
              let ts = seconds((o["time"] as? [String: Any])?["created"]) else { return [] }
        let model = (o["modelID"] as? String) ?? "opencode"
        return [.init(provider: "opencode", key: name, ts: ts, model: model, input: input, output: output, cacheWrite: cw, cacheRead: cr)]
    }

    // Kimi: wire.jsonl satırlarında bir yerde token_usage{input_other, output, input_cache_read, input_cache_creation}
    static func parseKimi(_ data: Data, path: String, fallback: Double) -> [HistoryStore.Event] {
        func find(_ any: Any?, depth: Int = 0) -> [String: Any]? {
            guard depth < 5 else { return nil }
            if let d = any as? [String: Any] {
                if let u = d["token_usage"] as? [String: Any] { return u }
                for v in d.values { if let r = find(v, depth: depth + 1) { return r } }
            } else if let a = any as? [Any] {
                for v in a { if let r = find(v, depth: depth + 1) { return r } }
            }
            return nil
        }
        var out: [HistoryStore.Event] = []
        for (i, line) in data.split(separator: UInt8(ascii: "\n")).enumerated() {
            guard line.range(of: Data("token_usage".utf8)) != nil,
                  let o = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  let u = find(o) else { continue }
            let input = int(u["input_other"]), output = int(u["output"])
            let cr = int(u["input_cache_read"]), cw = int(u["input_cache_creation"])
            guard input + output + cw + cr > 0 else { continue }
            let ts = seconds(o["timestamp"]) ?? fallback
            out.append(.init(provider: "kimi", key: "\(path)|\(i)", ts: ts, model: "kimi", input: input, output: output, cacheWrite: cw, cacheRead: cr))
        }
        return out
    }

    // Cline / Roo Code: ui_messages.json dizisinde say == "api_req_started", text = JSON {tokensIn, tokensOut, cacheWrites, cacheReads}
    static func parseCline(_ data: Data, task: String, roo: Bool) -> [HistoryStore.Event] {
        guard let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        var out: [HistoryStore.Event] = []
        for m in arr where m["say"] as? String == "api_req_started" {
            guard let text = m["text"] as? String, let td = text.data(using: .utf8),
                  let u = (try? JSONSerialization.jsonObject(with: td)) as? [String: Any],
                  let ts = seconds(m["ts"]) else { continue }
            let input = int(u["tokensIn"]), output = int(u["tokensOut"])
            let cw = int(u["cacheWrites"]), cr = int(u["cacheReads"])
            guard input + output + cw + cr > 0 else { continue }
            out.append(.init(provider: "cline", key: "\(task)|\(Int(ts * 1000))", ts: ts, model: roo ? "roo-code" : "cline",
                             input: input, output: output, cacheWrite: cw, cacheRead: cr))
        }
        return out
    }
}
