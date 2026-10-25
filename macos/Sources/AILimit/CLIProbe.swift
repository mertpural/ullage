import Foundation

/// Limiti Claude Code'un kendi komutuyla ölçer: `claude -p` çalışırken akışa bir `rate_limit_event` yazar ve içinde
/// 5 saatlik ve haftalık kullanım oranı vardır. Anthropic'in sert sınırlı kullanım adresini kullanmaz, Terminal ya da
/// durum satırı gerekmez; Claude uygulamasında çalışanlar için de geçerlidir. Bedeli tek satırlık bir Haiku isteğidir.
enum CLIProbe {
    private static let lastKey = "claudeLastProbe"
    /// İki ölçüm arası en az 5 dakika. Yalnızca son değerden sonra yeni yerel Claude kullanımı olduysa ölçülür.
    private static let minInterval: TimeInterval = 300

    static var enabled: Bool { UserDefaults.standard.object(forKey: "cliProbe") as? Bool ?? true }

    static func measureIfDue(stored: () -> ClaudeLimits?) async -> ClaudeLimits? {
        guard enabled, let cli = WindowStarter.cliPath else { return nil }
        let d = UserDefaults.standard
        let last = Date(timeIntervalSince1970: d.double(forKey: lastKey))
        guard Date().timeIntervalSince(last) >= minInterval else { return nil }
        let ref = max(stored()?.fetchedAt ?? .distantPast, last)
        let activity = HistoryStore.shared.latestEvent(provider: "claude")
        guard stored() == nil || activity > ref else { return nil }
        d.set(Date().timeIntervalSince1970, forKey: lastKey)
        return await withCheckedContinuation { cont in
            DispatchQueue.global().async { cont.resume(returning: run(cli)) }
        }
    }

    private static func run(_ cli: String) -> ClaudeLimits? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cli)
        p.arguments = ["-p", ".", "--model", "haiku", "--output-format", "stream-json", "--verbose",
                       "--no-session-persistence", "--tools", "", "--strict-mcp-config", "--disable-slash-commands"]
        p.currentDirectoryURL = FileManager.default.temporaryDirectory
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        p.environment = env
        p.standardInput = FileHandle.nullDevice
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        var data = Data()
        let reader = DispatchQueue.global()
        let done = DispatchSemaphore(value: 0)
        reader.async { data = out.fileHandleForReading.readDataToEndOfFile(); done.signal() }
        if done.wait(timeout: .now() + 90) == .timedOut { p.terminate(); return nil }
        p.waitUntilExit()
        return parse(data)
    }

    /// Çıktıdaki `rate_limit_event` satırından limitleri okur (utilization 0...1 = kullanılan oran).
    static func parse(_ data: Data) -> ClaudeLimits? {
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard line.range(of: Data("rate_limit_event".utf8)) != nil,
                  let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  obj["type"] as? String == "rate_limit_event",
                  let info = obj["rate_limit_info"] as? [String: Any],
                  let w = info["unifiedWindows"] as? [String: Any] else { continue }
            func win(_ k: String) -> (Double?, Date?) {
                guard let x = w[k] as? [String: Any] else { return (nil, nil) }
                let u = (x["utilization"] as? NSNumber)?.doubleValue
                let r = (x["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue > 1e11 ? $0.doubleValue / 1000 : $0.doubleValue) }
                return (u.map { max(0, min(1, 1 - $0)) }, r)
            }
            let five = win("five_hour"), week = win("seven_day")
            guard five.0 != nil || week.0 != nil else { continue }
            var l = ClaudeLimits(fiveHourLeft: five.0, weeklyLeft: week.0, fiveHourReset: five.1, weeklyReset: week.1)
            l.fromCLI = true
            return l
        }
        return nil
    }
}
