import Foundation

/// Claude Code her cevaptan sonra durum satırı komutuna oturum bilgisini (5 saatlik ve haftalık limit dahil) verir.
/// Ullage bu bilgiyi bir dosyaya yazan küçük bir betiği Claude Code ayarlarına ekler ve dosyayı okur:
/// ağ yok, hız sınırı yok. Yalnızca Claude Code çalışırken güncellenir.
enum StatusLine {
    static var dir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AILimit")
    }
    static var dataFile: URL { dir.appendingPathComponent("claude-status.json") }
    static var script: URL { dir.appendingPathComponent("statusline.sh") }
    static var settingsFile: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json") }

    static let scriptText = """
    #!/bin/sh
    # Ullage: Claude Code'un durum satırı girdisini (limitler dahil) Ullage'in okuyacağı dosyaya yazar. Ekrana bir şey basmaz.
    umask 077
    d="$HOME/Library/Application Support/AILimit"
    mkdir -p "$d"
    cat > "$d/claude-status.json.tmp" && mv "$d/claude-status.json.tmp" "$d/claude-status.json"

    """

    /// Ayarlarda şu an bizim betiğimiz mi tanımlı?
    static var installed: Bool {
        guard let obj = settings(), let sl = obj["statusLine"] as? [String: Any], let cmd = sl["command"] as? String else { return false }
        return cmd == script.path
    }

    /// Başka bir durum satırı tanımlıysa ona dokunulmaz.
    static var otherInstalled: Bool {
        guard let obj = settings(), let sl = obj["statusLine"] as? [String: Any], let cmd = sl["command"] as? String else { return false }
        return cmd != script.path
    }

    private static func settings() -> [String: Any]? {
        guard let d = try? Data(contentsOf: settingsFile) else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }

    /// Betiği yazar ve Claude Code ayarlarına ekler. Değişmeden önce ayar dosyasının yedeği alınır. Dönen metin hata mesajıdır.
    @discardableResult
    static func install() -> String? {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        do { try scriptText.write(to: script, atomically: true, encoding: .utf8) } catch { return error.localizedDescription }
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        var obj: [String: Any] = [:]
        if fm.fileExists(atPath: settingsFile.path) {
            guard let o = settings() else { return "settings.json okunamadı, dokunulmadı" }
            obj = o
            let backup = settingsFile.deletingLastPathComponent().appendingPathComponent("settings.json.ullage-yedek")
            if !fm.fileExists(atPath: backup.path) { try? fm.copyItem(at: settingsFile, to: backup) }
        }
        if let sl = obj["statusLine"] as? [String: Any], let cmd = sl["command"] as? String, cmd != script.path {
            return "Başka bir durum satırı tanımlı, değiştirilmedi"
        }
        obj["statusLine"] = ["type": "command", "command": script.path, "padding": 0]
        do {
            let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try data.write(to: settingsFile, options: .atomic)
        } catch { return error.localizedDescription }
        return nil
    }

    /// Yalnızca bizim eklediğimiz tanımı kaldırır.
    static func uninstall() {
        guard var obj = settings(), installed else { return }
        obj.removeValue(forKey: "statusLine")
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            try? data.write(to: settingsFile, options: .atomic)
        }
    }

    /// Dosyadaki son oturum bilgisinden limitleri okur.
    static func read() -> ClaudeLimits? {
        guard let d = try? Data(contentsOf: dataFile),
              let m = (try? FileManager.default.attributesOfItem(atPath: dataFile.path))?[.modificationDate] as? Date,
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let rl = obj["rate_limits"] as? [String: Any] else { return nil }

        func window(_ key: String) -> (left: Double?, reset: Date?) {
            guard let w = rl[key] as? [String: Any] else { return (nil, nil) }
            let used = (w["used_percentage"] as? NSNumber)?.doubleValue
            var reset: Date?
            if let n = (w["resets_at"] as? NSNumber)?.doubleValue {
                reset = Date(timeIntervalSince1970: n > 1e11 ? n / 1000 : n)
            } else if let s = w["resets_at"] as? String {
                let a = ISO8601DateFormatter(); a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                reset = a.date(from: s) ?? ISO8601DateFormatter().date(from: s)
            }
            return (used.map { max(0, min(1, 1 - $0 / 100)) }, reset)
        }
        let five = window("five_hour"), week = window("seven_day")
        guard five.left != nil || week.left != nil else { return nil }
        var l = ClaudeLimits(fiveHourLeft: five.left, weeklyLeft: week.left, fiveHourReset: five.reset, weeklyReset: week.reset, fetchedAt: m)
        l.fromStatusLine = true
        return l
    }
}
