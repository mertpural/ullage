import Foundation
import UserNotifications
import ServiceManagement

// MARK: - Bildirimler

enum Notifier {
    private static let seenKey = "notifiedKeys"

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func send(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    /// Eşikler pencere başına bir kez bildirilir; limit yenilenince ayrıca haber verilir.
    static func check(old: [Provider: Usage], new: [Provider: Usage]) {
        var seen = Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? [])
        for p in Provider.allCases {
            guard let n = new[p], n.limitConfidence != .none else { continue }
            for row in n.rows {
                let stamp = Int(row.reset?.timeIntervalSince1970 ?? 0)
                let base = "\(p.rawValue)|\(row.title)|\(stamp)"

                for (level, label) in [(0.05, "%5"), (0.15, "%15")] where row.left <= level {
                    let key = "\(base)|\(level)"
                    if seen.contains(key) { break }
                    seen.insert(key)
                    // Daha düşük eşik geçildiyse üsttekini de işaretle ki ikinci bildirim gelmesin.
                    for (l2, _) in [(0.05, ""), (0.15, "")] where l2 >= level { seen.insert("\(base)|\(l2)") }
                    send("\(p.name): limit azaldı", "\(row.title) için kalan \(label) altına düştü (\(Int((row.left * 100).rounded()))%).")
                    break
                }

                if let o = old[p]?.rows.first(where: { $0.title == row.title }), o.left <= 0.2, row.left >= 0.9 {
                    send("\(p.name): limit yenilendi", "\(row.title) penceresi sıfırlandı, %\(Int((row.left * 100).rounded())) kaldı.")
                }
            }
        }
        UserDefaults.standard.set(Array(seen.suffix(300)), forKey: seenKey)
    }
}

// MARK: - Pencere başlatıcı

/// 5 saatlik pencere, hesabın pencere dışındaki ilk isteğiyle başlar. Pencere bittiğinde en ucuz modele
/// çok kısa bir istek gönderip yeni pencereyi erken başlatır, böylece sıfırlanma saati öne kayar.
/// Ek limit vermez; yalnızca pencerenin ne zaman başlayıp biteceğini belirler. Kullanıcı açarsa çalışır.
enum WindowStarter {
    static let lastKey = "starterLast"

    static func shouldStart(_ u: Usage, now: Date, startHour: Int, endHour: Int) -> Bool {
        guard u.limitConfidence == .exact, let f = u.fiveRow, f.left >= 0.999 else { return false }
        if let r = f.reset, r > now { return false }
        let hour = Calendar.current.component(.hour, from: now)
        let inside = startHour <= endHour ? (hour >= startHour && hour < endHour) : (hour >= startHour || hour < endHour)
        guard inside else { return false }
        let last = UserDefaults.standard.double(forKey: lastKey)
        return now.timeIntervalSince1970 - last > 4.5 * 3600
    }

    static var cliPath: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(home)/.local/bin/claude", "\(home)/.claude/local/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Haiku'ya tek satırlık istek gönderir, oturum kaydı bırakmaz. Dönen metin durum mesajıdır.
    static func ping() -> (ok: Bool, message: String) {
        guard let cli = cliPath else { return (false, "claude komutu bulunamadı") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cli)
        p.arguments = ["-p", "--model", "haiku", "--no-session-persistence", "--tools", "", "--", "Reply with only: ok"]
        p.currentDirectoryURL = FileManager.default.temporaryDirectory
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        do { try p.run() } catch { return (false, "Başlatılamadı: \(error.localizedDescription)") }

        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { p.waitUntilExit(); done.signal() }
        if done.wait(timeout: .now() + 120) == .timedOut {
            p.terminate()
            return (false, "Zaman aşımı")
        }
        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if p.terminationStatus == 0 {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastKey)
            return (true, "Yeni pencere başlatıldı")
        }
        return (false, "Hata: \(text.prefix(120))")
    }
}

// MARK: - Girişte başlat

enum LoginItem {
    static var enabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
