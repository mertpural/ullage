import Foundation
import SQLite3

private enum Wire {
    case varint(UInt64)
    case bytes(Data)
}

/// Şemasız, asgari protobuf okuyucu: yalnızca varint ve uzunluk-önekli alanları çözer.
private func pbFields(_ d: Data) -> [(Int, Wire)] {
    var out: [(Int, Wire)] = []
    var i = d.startIndex
    func varint() -> UInt64? {
        var r: UInt64 = 0, s: UInt64 = 0
        while i < d.endIndex {
            let b = d[i]; i = d.index(after: i)
            r |= UInt64(b & 0x7f) << s
            if b < 0x80 { return r }
            s += 7
            if s > 63 { return nil }
        }
        return nil
    }
    while i < d.endIndex {
        guard let key = varint() else { break }
        let field = Int(key >> 3)
        switch key & 7 {
        case 0:
            guard let v = varint() else { return out }
            out.append((field, .varint(v)))
        case 2:
            guard let l = varint(), let end = d.index(i, offsetBy: Int(l), limitedBy: d.endIndex) else { return out }
            out.append((field, .bytes(d[i..<end])))
            i = end
        case 1:
            guard let e = d.index(i, offsetBy: 8, limitedBy: d.endIndex) else { return out }
            i = e
        case 5:
            guard let e = d.index(i, offsetBy: 4, limitedBy: d.endIndex) else { return out }
            i = e
        default:
            return out
        }
    }
    return out
}

private func pbBytes(_ f: [(Int, Wire)], _ n: Int) -> Data? {
    for (k, w) in f where k == n { if case .bytes(let b) = w { return b } }
    return nil
}

private func pbVarint(_ f: [(Int, Wire)], _ n: Int) -> Int? {
    for (k, w) in f where k == n { if case .varint(let v) = w { return Int(v) } }
    return nil
}

/// Antigravity, her konuşmayı ~/.gemini/antigravity-ide/conversations/*.db (SQLite) içinde tutar.
/// gen_metadata tablosundaki protobuf blobları üretim başına model, zaman ve token sayılarını içerir.
/// Alan numaralarının anlamı resmi bir şemadan değil, blob içeriğinin çözümlenmesinden çıkarıldı.
enum AntigravityProvider {
    static let note = "Token alanları (girdi, cache yazma, çıktı, cache okuma) kayıt yapısından çıkarıldı; Antigravity resmi bir şema yayınlamıyor, bu yüzden tahminidir."

    static func read(now: Date = Date()) async -> Usage {
        ingest()
        let store = HistoryStore.shared
        let all = store.sums(provider: "antigravity", since: .distantPast)
        var u = Usage()
        if all.billable > 0 {
            u.todayTokens = store.sums(provider: "antigravity", since: Calendar.current.startOfDay(for: now)).billable
            u.tokenConfidence = .estimate
            u.notes.append(note)
        } else {
            u.notes.append("Yerel konuşma kayıtlarında token bulunamadı.")
        }
        switch await AntigravityQuota.fetch() {
        case .success(let rows):
            u.extra = rows
            u.limitConfidence = .exact
            u.notes.append("Limit: Antigravity'nin yerel dil sunucusundan (IDE açıkken).")
        case .failure(let e):
            u.notes.append("Limit alınamadı: \(e.message)")
        }
        return u
    }

    private static func ingest() {
        let fm = FileManager.default
        let dir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/antigravity-ide/conversations")
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let tmp = fm.temporaryDirectory.appendingPathComponent("ailimit-ag", isDirectory: true)
        try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)

        for url in files where url.pathExtension == "db" {
            let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let key = "agMod_\(url.lastPathComponent)"
            let seen = UserDefaults.standard.double(forKey: key)
            // Kopya üzerinde çalış (WAL kipindeki veritabanı salt okunur açılamıyor, kopya bize ait).
            if mod.timeIntervalSince1970 <= seen { continue }

            let copy = tmp.appendingPathComponent(url.lastPathComponent)
            for suffix in ["", "-wal", "-shm"] {
                let src = URL(fileURLWithPath: url.path + suffix)
                let dst = URL(fileURLWithPath: copy.path + suffix)
                try? fm.removeItem(at: dst)
                if fm.fileExists(atPath: src.path) { try? fm.copyItem(at: src, to: dst) }
            }

            var db: OpaquePointer?
            guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { sqlite3_close(db); continue }
            defer { sqlite3_close(db) }
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT idx, data FROM gen_metadata", -1, &st, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(st) }

            var events: [HistoryStore.Event] = []
            while sqlite3_step(st) == SQLITE_ROW {
                let idx = sqlite3_column_int64(st, 0)
                guard let p = sqlite3_column_blob(st, 1) else { continue }
                let blob = Data(bytes: p, count: Int(sqlite3_column_bytes(st, 1)))
                let top = pbFields(blob)
                guard let m1 = pbBytes(top, 1).map(pbFields),
                      let usage = pbBytes(m1, 4).map(pbFields),
                      let timing = pbBytes(m1, 9).map(pbFields),
                      let t = pbBytes(timing, 4).map(pbFields),
                      let secs = pbVarint(t, 1)
                else { continue }
                let model = pbBytes(m1, 19).flatMap { String(data: $0, encoding: .utf8) } ?? ""
                events.append(.init(
                    provider: "antigravity", key: "\(url.lastPathComponent)|\(idx)", ts: Double(secs),
                    model: model,
                    input: pbVarint(usage, 1) ?? 0,
                    output: pbVarint(usage, 3) ?? 0,
                    cacheWrite: pbVarint(usage, 2) ?? 0,
                    cacheRead: pbVarint(usage, 5) ?? 0
                ))
            }
            HistoryStore.shared.upsert(events)
            UserDefaults.standard.set(mod.timeIntervalSince1970, forKey: key)
        }
    }
}


private final class LocalTLSDelegate: NSObject, URLSessionDelegate {
    /// Yerel dil sunucusu kendinden imzalı sertifika kullanır; yalnızca 127.0.0.1 için kabul edilir.
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.host == "127.0.0.1", let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

/// Antigravity IDE açıkken çalışan yerel dil sunucusundan (Connect/HTTPS) kota özetini okur.
/// Yöntem CodexBar'ın belgelediği yolu izler. IDE kapalıysa sunucu yoktur ve limit alınamaz.
enum AntigravityQuota {
    nonisolated(unsafe) static var lastRaw = ""

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

    private struct Server { var pid: Int; var csrf: String; var extPort: Int? }

    private static func findServers() -> [Server] {
        var found: [Server] = []
        for line in sh("/bin/ps", ["-ax", "-o", "pid=,command="]).split(separator: "\n") {
            let l = String(line)
            guard l.contains("language_server"), l.contains("antigravity") else { continue }
            func flag(_ name: String) -> String? {
                guard let r = l.range(of: "--\(name) ") else { return nil }
                return l[r.upperBound...].split(separator: " ").first.map(String.init)
            }
            guard let pidS = l.trimmingCharacters(in: .whitespaces).split(separator: " ").first, let pid = Int(pidS),
                  let csrf = flag("csrf_token") else { continue }
            found.append(Server(pid: pid, csrf: csrf, extPort: flag("extension_server_port").flatMap(Int.init)))
        }
        return found
    }

    private static func ports(of pid: Int) -> [Int] {
        sh("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", "\(pid)"])
            .split(separator: "\n")
            .compactMap { line -> Int? in
                guard let r = line.range(of: ":", options: .backwards, range: line.startIndex..<(line.range(of: " (LISTEN)")?.lowerBound ?? line.endIndex)) else { return nil }
                return Int(line[r.upperBound..<(line.range(of: " (LISTEN)")?.lowerBound ?? line.endIndex)])
            }
    }

    private static func post(_ port: Int, _ method: String, csrf: String, body: String, session: URLSession) async -> (Int, Data)? {
        var req = URLRequest(url: URL(string: "https://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/\(method)")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 4
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(csrf, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        req.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        req.httpBody = Data(body.utf8)
        guard let (d, r) = try? await session.data(for: req), let code = (r as? HTTPURLResponse)?.statusCode else { return nil }
        return (code, d)
    }

    static func fetch() async -> Result<[LimitRow], LimitError> {
        let servers = findServers()
        guard !servers.isEmpty else { return .failure(LimitError(message: "Antigravity IDE çalışmıyor; açınca okunur")) }
        let session = URLSession(configuration: .ephemeral, delegate: LocalTLSDelegate(), delegateQueue: nil)
        let meta = #"{"metadata":{"ideName":"antigravity","extensionName":"antigravity","locale":"en"}}"#

        for s in servers {
            for port in ports(of: s.pid) {
                guard let probe = await post(port, "GetUnleashData", csrf: s.csrf, body: meta, session: session), probe.0 == 200 else { continue }
                for method in ["RetrieveUserQuotaSummary", "GetUserStatus"] {
                    guard let (code, data) = await post(port, method, csrf: s.csrf, body: meta, session: session), code == 200,
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    lastRaw = String(data: data, encoding: .utf8) ?? ""
                    let rows = parse(obj)
                    if !rows.isEmpty { return .success(rows) }
                }
            }
        }
        return .failure(LimitError(message: "Yerel sunucudan kota okunamadı"))
    }

    private static func parseDate(_ any: Any?) -> Date? {
        if let s = any as? String {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
        }
        if let n = any as? Double { return Date(timeIntervalSince1970: n) }
        return nil
    }

    static func parse(_ root: [String: Any]) -> [LimitRow] {
        let resp = (root["response"] as? [String: Any]) ?? root
        var rows: [LimitRow] = []
        if let groups = resp["groups"] as? [[String: Any]] {
            for g in groups {
                let gname = (g["displayName"] as? String ?? "Grup")
                    .replacingOccurrences(of: " Models", with: "").replacingOccurrences(of: " models", with: "")
                    .replacingOccurrences(of: "Claude and GPT", with: "Claude + GPT")
                for b in (g["buckets"] as? [[String: Any]]) ?? [] {
                    let frac = ((b["remaining"] as? [String: Any])?["remainingFraction"] as? Double) ?? (b["remainingFraction"] as? Double)
                    guard let f = frac else { continue }
                    let key = "\(b["window"] ?? "") \(b["bucketId"] ?? "") \(b["displayName"] ?? "")".lowercased()
                    let win = key.contains("week") ? "Haftalık" : (key.contains("five") || key.contains("5") || key.contains("hour") ? "5 saatlik" : (b["displayName"] as? String ?? ""))
                    rows.append(LimitRow(title: "\(gname) · \(win)", left: max(0, min(1, f)), reset: parseDate(b["resetTime"])))
                }
            }
        }
        if rows.isEmpty,
           let cfgs = ((resp["userStatus"] as? [String: Any])?["cascadeModelConfigData"] as? [String: Any])?["clientModelConfigs"] as? [[String: Any]] {
            for c in cfgs {
                guard let q = c["quotaInfo"] as? [String: Any], let f = q["remainingFraction"] as? Double else { continue }
                rows.append(LimitRow(title: c["label"] as? String ?? "Model", left: max(0, min(1, f)), reset: parseDate(q["resetTime"])))
            }
        }
        return rows
    }
}
