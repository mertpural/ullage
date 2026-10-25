import Foundation
import SQLite3

/// Kullanıcının seçtiği, her yerde ortak geçerli ayarlar.
enum Prefs {
    /// Açıksa token toplamlarına cache okumaları da eklenir (popover, geçmiş, paylaşım kartı, özet).
    static var includeCache: Bool { UserDefaults.standard.bool(forKey: "includeCache") }
}

struct TokenSums {
    var input = 0, output = 0, cacheWrite = 0, cacheRead = 0
    /// "Harcanan token" olarak gösterilen değer. Cache okumaları yalnızca kullanıcı "Cache dahil" dediyse eklenir.
    var billable: Int { input + output + cacheWrite + (Prefs.includeCache ? cacheRead : 0) }
}

/// Tüm sağlayıcıların token olaylarını kalıcı tutar. Log dosyaları silinse bile geçmiş kalır.
final class HistoryStore: @unchecked Sendable {
    static let shared = HistoryStore()

    private var db: OpaquePointer?
    private let lock = NSLock()

    private init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AILimit")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        sqlite3_open(dir.appendingPathComponent("history.sqlite").path, &db)
        exec("PRAGMA journal_mode=WAL")
        exec("""
        CREATE TABLE IF NOT EXISTS events(
          provider TEXT NOT NULL, key TEXT NOT NULL, ts REAL NOT NULL, model TEXT,
          input INTEGER, output INTEGER, cache_write INTEGER, cache_read INTEGER,
          PRIMARY KEY(provider, key))
        """)
        exec("ALTER TABLE events ADD COLUMN project TEXT")   // eski veritabanlarında yoksa eklenir, varsa hata verip geçer
        exec("CREATE INDEX IF NOT EXISTS idx_events_ts ON events(provider, ts)")
        exec("CREATE TABLE IF NOT EXISTS file_state(path TEXT PRIMARY KEY, offset INTEGER NOT NULL)")
        exec("CREATE TABLE IF NOT EXISTS file_total(path TEXT PRIMARY KEY, total INTEGER NOT NULL)")
    }

    private func exec(_ sql: String) { sqlite3_exec(db, sql, nil, nil, nil) }

    func fileOffset(_ path: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        var st: OpaquePointer?
        defer { sqlite3_finalize(st) }
        sqlite3_prepare_v2(db, "SELECT offset FROM file_state WHERE path=?", -1, &st, nil)
        sqlite3_bind_text(st, 1, path, -1, SQLITE_TRANSIENT)
        return sqlite3_step(st) == SQLITE_ROW ? Int(sqlite3_column_int64(st, 0)) : 0
    }

    func setFileOffset(_ path: String, _ offset: Int) {
        lock.lock(); defer { lock.unlock() }
        var st: OpaquePointer?
        defer { sqlite3_finalize(st) }
        sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO file_state(path, offset) VALUES(?,?)", -1, &st, nil)
        sqlite3_bind_text(st, 1, path, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(st, 2, Int64(offset))
        sqlite3_step(st)
    }

    func fileTotal(_ path: String) -> Int? {
        lock.lock(); defer { lock.unlock() }
        var st: OpaquePointer?
        defer { sqlite3_finalize(st) }
        sqlite3_prepare_v2(db, "SELECT total FROM file_total WHERE path=?", -1, &st, nil)
        sqlite3_bind_text(st, 1, path, -1, SQLITE_TRANSIENT)
        return sqlite3_step(st) == SQLITE_ROW ? Int(sqlite3_column_int64(st, 0)) : nil
    }

    func setFileTotal(_ path: String, _ total: Int) {
        lock.lock(); defer { lock.unlock() }
        var st: OpaquePointer?
        defer { sqlite3_finalize(st) }
        sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO file_total(path, total) VALUES(?,?)", -1, &st, nil)
        sqlite3_bind_text(st, 1, path, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(st, 2, Int64(total))
        sqlite3_step(st)
    }

    /// Ayrıştırma mantığı değiştiğinde bir sağlayıcının kayıtlarını ve okuma konumlarını sıfırlar.
    func reset(provider: String, pathContains: String) {
        lock.lock(); defer { lock.unlock() }
        exec("DELETE FROM events WHERE provider='\(provider)'")
        exec("DELETE FROM file_state WHERE path LIKE '%\(pathContains)%'")
        exec("DELETE FROM file_total WHERE path LIKE '%\(pathContains)%'")
    }

    struct Event {
        var provider: String, key: String, ts: Double, model: String
        var input: Int, output: Int, cacheWrite: Int, cacheRead: Int
        var project = ""   // yalnızca klasör adı; tam yol saklanmaz
    }

    /// Dosyaları baştan okutur ama olayları silmez: kayıtlar (provider,key) ile eşlenir, değerler en büyükle korunur.
    /// Log dosyası silinmiş eski olaylar kalır.
    func rescan(pathContains: String) {
        lock.lock(); defer { lock.unlock() }
        exec("DELETE FROM file_state WHERE path LIKE '%\(pathContains)%'")
    }

    /// Akış sırasında aynı mesaj birkaç kez yazılır; en büyük değerler tutulur.
    func upsert(_ events: [Event]) {
        guard !events.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        exec("BEGIN")
        var st: OpaquePointer?
        sqlite3_prepare_v2(db, """
        INSERT INTO events(provider,key,ts,model,input,output,cache_write,cache_read,project)
        VALUES(?,?,?,?,?,?,?,?,?)
        ON CONFLICT(provider,key) DO UPDATE SET
          project=CASE WHEN excluded.project<>'' THEN excluded.project ELSE project END,
          input=MAX(input,excluded.input), output=MAX(output,excluded.output),
          cache_write=MAX(cache_write,excluded.cache_write),
          cache_read=MAX(cache_read,excluded.cache_read)
        """, -1, &st, nil)
        for e in events {
            sqlite3_reset(st)
            sqlite3_bind_text(st, 1, e.provider, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(st, 2, e.key, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(st, 3, e.ts)
            sqlite3_bind_text(st, 4, e.model, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(st, 5, Int64(e.input))
            sqlite3_bind_int64(st, 6, Int64(e.output))
            sqlite3_bind_int64(st, 7, Int64(e.cacheWrite))
            sqlite3_bind_int64(st, 8, Int64(e.cacheRead))
            sqlite3_bind_text(st, 9, e.project, -1, SQLITE_TRANSIENT)
            sqlite3_step(st)
        }
        sqlite3_finalize(st)
        exec("COMMIT")
    }

    struct Point: Identifiable {
        let id = UUID()
        let bucket: Date, provider: String, model: String, tokens: Int
    }

    /// bucketFormat: "%Y-%m-%d %H:00" (saatlik) ya da "%Y-%m-%d" (günlük), yerel saatle.
    func series(since: Date, hourly: Bool, includeCache: Bool) -> [Point] {
        lock.lock(); defer { lock.unlock() }
        let fmt = hourly ? "%Y-%m-%d %H:00" : "%Y-%m-%d"
        let expr = includeCache ? "input+output+cache_write+cache_read" : "input+output+cache_write"
        var st: OpaquePointer?
        defer { sqlite3_finalize(st) }
        sqlite3_prepare_v2(db, """
        SELECT strftime('\(fmt)', ts, 'unixepoch', 'localtime') b, provider, model, SUM(\(expr))
        FROM events WHERE ts>=? GROUP BY b, provider, model ORDER BY b
        """, -1, &st, nil)
        sqlite3_bind_double(st, 1, since.timeIntervalSince1970)
        let f = DateFormatter()
        f.dateFormat = hourly ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd"
        var out: [Point] = []
        while sqlite3_step(st) == SQLITE_ROW {
            guard let b = sqlite3_column_text(st, 0), let p = sqlite3_column_text(st, 1),
                  let d = f.date(from: String(cString: b)) else { continue }
            let m = sqlite3_column_text(st, 2).map { String(cString: $0) } ?? ""
            out.append(Point(bucket: d, provider: String(cString: p), model: m.isEmpty ? "?" : m,
                             tokens: Int(sqlite3_column_int64(st, 3))))
        }
        return out
    }

    /// Son `days` günün (bugün dahil) günlük token toplamları, eskiden yeniye; cache hariç.
    func dailyTotals(provider: String, days: Int) -> [Int] {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: Date()))!
        lock.lock(); defer { lock.unlock() }
        var st: OpaquePointer?
        defer { sqlite3_finalize(st) }
        sqlite3_prepare_v2(db, """
        SELECT strftime('%Y-%m-%d', ts, 'unixepoch', 'localtime') d, SUM(\(Prefs.includeCache ? "input+output+cache_write+cache_read" : "input+output+cache_write"))
        FROM events WHERE provider=? AND ts>=? GROUP BY d
        """, -1, &st, nil)
        sqlite3_bind_text(st, 1, provider, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(st, 2, start.timeIntervalSince1970)
        var byDay: [String: Int] = [:]
        while sqlite3_step(st) == SQLITE_ROW {
            if let d = sqlite3_column_text(st, 0) { byDay[String(cString: d)] = Int(sqlite3_column_int64(st, 1)) }
        }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return (0..<days).map { i in
            byDay[f.string(from: cal.date(byAdding: .day, value: i, to: start)!)] ?? 0
        }
    }

    func sums(provider: String, since: Date) -> TokenSums {
        lock.lock(); defer { lock.unlock() }
        var st: OpaquePointer?
        defer { sqlite3_finalize(st) }
        sqlite3_prepare_v2(db, """
        SELECT COALESCE(SUM(input),0),COALESCE(SUM(output),0),
               COALESCE(SUM(cache_write),0),COALESCE(SUM(cache_read),0)
        FROM events WHERE provider=? AND ts>=?
        """, -1, &st, nil)
        sqlite3_bind_text(st, 1, provider, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(st, 2, since.timeIntervalSince1970)
        var s = TokenSums()
        if sqlite3_step(st) == SQLITE_ROW {
            s.input = Int(sqlite3_column_int64(st, 0))
            s.output = Int(sqlite3_column_int64(st, 1))
            s.cacheWrite = Int(sqlite3_column_int64(st, 2))
            s.cacheRead = Int(sqlite3_column_int64(st, 3))
        }
        return s
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

extension HistoryStore {
    /// Model başına dört token türünün toplamı (maliyet tahmini için).
    func modelSums(since: Date) -> [(model: String, sums: TokenSums)] {
        lock.lock(); defer { lock.unlock() }
        var st: OpaquePointer?
        defer { sqlite3_finalize(st) }
        sqlite3_prepare_v2(db, """
        SELECT model, SUM(input), SUM(output), SUM(cache_write), SUM(cache_read)
        FROM events WHERE ts>=? GROUP BY model
        """, -1, &st, nil)
        sqlite3_bind_double(st, 1, since.timeIntervalSince1970)
        var out: [(String, TokenSums)] = []
        while sqlite3_step(st) == SQLITE_ROW {
            var s = TokenSums()
            s.input = Int(sqlite3_column_int64(st, 1))
            s.output = Int(sqlite3_column_int64(st, 2))
            s.cacheWrite = Int(sqlite3_column_int64(st, 3))
            s.cacheRead = Int(sqlite3_column_int64(st, 4))
            out.append((sqlite3_column_text(st, 0).map { String(cString: $0) } ?? "", s))
        }
        return out
    }
}

extension HistoryStore {
    /// Proje (klasör adı) ve model başına toplamlar; adı olmayan kayıtlar atlanır.
    func projectSums(since: Date) -> [(project: String, model: String, sums: TokenSums)] {
        lock.lock(); defer { lock.unlock() }
        var st: OpaquePointer?
        defer { sqlite3_finalize(st) }
        sqlite3_prepare_v2(db, """
        SELECT project, model, SUM(input), SUM(output), SUM(cache_write), SUM(cache_read)
        FROM events WHERE ts>=? AND project IS NOT NULL AND project<>'' GROUP BY project, model
        """, -1, &st, nil)
        sqlite3_bind_double(st, 1, since.timeIntervalSince1970)
        var out: [(String, String, TokenSums)] = []
        while sqlite3_step(st) == SQLITE_ROW {
            var s = TokenSums()
            s.input = Int(sqlite3_column_int64(st, 2))
            s.output = Int(sqlite3_column_int64(st, 3))
            s.cacheWrite = Int(sqlite3_column_int64(st, 4))
            s.cacheRead = Int(sqlite3_column_int64(st, 5))
            out.append((String(cString: sqlite3_column_text(st, 0)),
                        sqlite3_column_text(st, 1).map { String(cString: $0) } ?? "", s))
        }
        return out
    }

    /// Günlük, sağlayıcı ve model başına toplamlar (CSV için). Satır: tarih,sağlayıcı,model,input,output,cache_write,cache_read.
    func exportCSV() -> String {
        lock.lock(); defer { lock.unlock() }
        var st: OpaquePointer?
        defer { sqlite3_finalize(st) }
        sqlite3_prepare_v2(db, """
        SELECT strftime('%Y-%m-%d', ts, 'unixepoch', 'localtime') d, provider, COALESCE(model,''),
               SUM(input), SUM(output), SUM(cache_write), SUM(cache_read)
        FROM events GROUP BY d, provider, model ORDER BY d, provider, model
        """, -1, &st, nil)
        var out = "date,provider,model,input,output,cache_write,cache_read\n"
        while sqlite3_step(st) == SQLITE_ROW {
            let f = (0..<3).map { i -> String in
                let v = sqlite3_column_text(st, Int32(i)).map { String(cString: $0) } ?? ""
                return v.contains(",") ? "\"\(v)\"" : v
            }
            let n = (3..<7).map { String(sqlite3_column_int64(st, Int32($0))) }
            out += (f + n).joined(separator: ",") + "\n"
        }
        return out
    }
}
