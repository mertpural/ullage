import Foundation
import AppKit
import CryptoKit
import SwiftUI

/// Güncelleme: sitedeki küçük `latest.json` dosyasına günde bir bakar (yalnızca sürüm numarası okunur, kullanıcıya dair
/// hiçbir şey gönderilmez). Yeni sürüm varsa kullanıcı onaylayınca zip'i indirir, SHA-256'yı ve kod imzasının bu uygulamayla
/// aynı sertifikadan olduğunu doğrular, uygulamayı yenisiyle değiştirip yeniden açar. Doğrulama olmazsa hiçbir şey değiştirilmez.
struct UpdateInfo {
    let version: String
    let url: URL
    let sha256: String
    let notes: String
}

@MainActor
final class UpdateModel: ObservableObject {
    static let shared = UpdateModel()

    @Published var available: UpdateInfo?
    @Published var status = ""
    @Published var busy = false
    @Published var autoCheck: Bool = UserDefaults.standard.object(forKey: "updateCheck") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoCheck, forKey: "updateCheck") }
    }

    static var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    static var feedURL: URL {
        if let s = ProcessInfo.processInfo.environment["AILIMIT_UPDATE_URL"], let u = URL(string: s) { return u }
        return URL(string: "https://ullage-app.netlify.app/latest.json")!
    }

    /// "0.10.1" > "0.9" gibi sayısal karşılaştırma.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    /// Günde en fazla bir kez, arka planda. Kapalıysa hiçbir istek gitmez.
    func checkIfDue() {
        guard autoCheck, !busy else { return }
        let last = UserDefaults.standard.double(forKey: "updateLastCheck")
        guard Date().timeIntervalSince1970 - last > 20 * 3600 else { return }
        Task { await check(manual: false) }
    }

    func check(manual: Bool) async {
        if manual { busy = true; status = L.t("Denetleniyor…") }
        defer { if manual { busy = false } }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "updateLastCheck")
        var req = URLRequest(url: Self.feedURL, timeoutInterval: 15)
        req.setValue("Ullage/\(Self.current)", forHTTPHeaderField: "User-Agent")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, resp) = try await URLSession(configuration: .ephemeral).data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let o = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let v = o["version"] as? String, let us = o["url"] as? String, let url = URL(string: us),
                  url.scheme == "https" || url.isFileURL || url.host == "127.0.0.1",
                  let sha = o["sha256"] as? String else {
                if manual { status = L.t("Güncelleme bilgisi okunamadı") }
                return
            }
            if Self.isNewer(v, than: Self.current) {
                let info = UpdateInfo(version: v, url: url, sha256: sha.lowercased(), notes: o["notes"] as? String ?? "")
                available = info
                if manual { status = L.f("Yeni sürüm var: %@", v) }
                let notified = UserDefaults.standard.string(forKey: "updateNotified")
                if !manual, notified != v, UserDefaults.standard.object(forKey: "notificationsOn") as? Bool ?? true {
                    UserDefaults.standard.set(v, forKey: "updateNotified")
                    Notifier.send(L.f("Ullage %@ hazır", v), L.t("Ayarlar > Hakkında bölümünden güncelleyebilirsin."))
                }
            } else {
                available = nil
                if manual { status = L.t("Güncelsin") }
            }
        } catch {
            if manual { status = L.t("Güncelleme sunucusuna bağlanılamadı") }
        }
    }

    // MARK: Kurulum

    private func fail(_ m: String) { status = m; busy = false }

    func install() async {
        guard let info = available, !busy else { return }
        busy = true
        status = L.t("İndiriliyor…")

        let bundle = Bundle.main.bundlePath
        let parent = (bundle as NSString).deletingLastPathComponent
        guard bundle.hasSuffix(".app"), FileManager.default.isWritableFile(atPath: parent) else {
            return fail(L.t("Uygulama bu konumda güncellenemiyor. Yeni sürümü siteden indir."))
        }
        guard let want = Self.leafHash(of: bundle) else {
            return fail(L.t("Bu sürüm imzalı değil, kendiliğinden güncellenemez. Yeni sürümü siteden indir."))
        }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("ullage-update-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let (tmp, resp) = try await URLSession(configuration: .ephemeral).download(from: info.url)
            guard (resp as? HTTPURLResponse)?.statusCode ?? 200 == 200 else { return fail(L.t("İndirilemedi")) }
            guard Self.sha256(of: tmp) == info.sha256 else { return fail(L.t("İndirilen dosya doğrulanamadı (SHA-256 uyuşmuyor). Güncelleme yapılmadı.")) }
            let zip = work.appendingPathComponent("update.zip")
            try FileManager.default.moveItem(at: tmp, to: zip)

            status = L.t("Doğrulanıyor…")
            guard Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path]) == 0 else { return fail(L.t("Zip açılamadı")) }
            let newApp = work.appendingPathComponent("\(AppInfo.name).app").path
            guard FileManager.default.fileExists(atPath: newApp) else { return fail(L.t("Zip içinde uygulama bulunamadı")) }
            let req = "=identifier \"com.mertpural.ailimit\" and certificate leaf = H\"\(want)\""
            guard Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R", req, newApp]) == 0 else {
                return fail(L.t("Yeni sürümün imzası bu uygulamayla eşleşmiyor. Güncelleme yapılmadı."))
            }
            let newVersion = (NSDictionary(contentsOfFile: newApp + "/Contents/Info.plist")?["CFBundleShortVersionString"] as? String) ?? ""
            guard newVersion == info.version, Self.isNewer(newVersion, than: Self.current) else {
                return fail(L.t("Sürüm bilgisi tutmuyor. Güncelleme yapılmadı."))
            }

            // Kendini değiştiremez: uygulama kapandıktan sonra çalışan küçük bir betik yerine koyar, olmazsa eskisini geri getirir.
            let script = work.appendingPathComponent("replace.sh")
            let sh = """
            #!/bin/sh
            PID="$1"; NEW="$2"; DEST="$3"
            while kill -0 "$PID" 2>/dev/null; do sleep 0.3; done
            rm -rf "$DEST.old"
            mv "$DEST" "$DEST.old" || exit 1
            if ditto --norsrc --noextattr "$NEW" "$DEST" && xattr -cr "$DEST" && codesign -v "$DEST"; then
              rm -rf "$DEST.old"
            else
              rm -rf "$DEST"; mv "$DEST.old" "$DEST"
            fi
            open "$DEST"
            """
            try sh.write(to: script, atomically: true, encoding: .utf8)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), newApp, bundle]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try p.run()
            status = L.t("Yeniden başlatılıyor…")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { NSApp.terminate(nil) }
        } catch {
            fail(L.t("Güncelleme başarısız oldu"))
        }
    }

    // MARK: Yardımcılar

    @discardableResult
    static func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    /// Çalışan uygulamanın imza sertifikasının özeti (designated requirement içindeki H"…").
    static func leafHash(of app: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        p.arguments = ["-d", "-r-", app]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let s = String(decoding: data, as: UTF8.self)
        guard let r = s.range(of: #"certificate leaf = H"[0-9a-fA-F]{40}""#, options: .regularExpression) else { return nil }
        return String(s[r]).components(separatedBy: "\"")[1].lowercased()
    }

    static func sha256(of url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try? h.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

struct UpdateCard: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var m = UpdateModel.shared

    var body: some View {
        let t = state.theme
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L.f("Sürüm %@", UpdateModel.current)).font(t.font(13, .semibold))
                Spacer()
                if let a = m.available {
                    Button(L.f("%@ sürümüne güncelle", a.version)) { Task { await m.install() } }.disabled(m.busy)
                } else {
                    Button(L.t("Güncellemeleri denetle")) { Task { await m.check(manual: true) } }.disabled(m.busy)
                }
            }
            if !m.status.isEmpty {
                Text(m.status).font(t.font(11)).foregroundStyle(t.sub).fixedSize(horizontal: false, vertical: true)
            }
            if let a = m.available, !a.notes.isEmpty {
                Text(a.notes).font(t.font(11)).foregroundStyle(t.sub).fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.t("Güncellemeleri kendiliğinden denetle")).font(t.font(12, .semibold))
                    Text(L.t("Günde bir kez sitedeki küçük bir dosyaya bakar; yalnızca sürüm numarası okunur, sana dair bir şey gönderilmez. Yeni sürüm varsa bildirim gelir, yüklemek için sen onaylarsın."))
                        .font(t.font(11)).foregroundStyle(t.sub).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: $m.autoCheck).toggleStyle(.switch).labelsHidden()
            }
        }
        .card(t, padding: 16)
    }
}
