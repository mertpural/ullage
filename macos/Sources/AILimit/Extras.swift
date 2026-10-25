import SwiftUI
import AppKit

// MARK: - Proje bazlı kullanım

@MainActor
final class ProjectsModel: ObservableObject {
    @Published var rows: [(name: String, tokens: Int, cost: Double)] = []

    func load() {
        let since = Calendar.current.date(byAdding: .day, value: -29, to: Calendar.current.startOfDay(for: Date()))!
        DispatchQueue.global().async {
            var byProject: [String: (Int, Double)] = [:]
            for r in HistoryStore.shared.projectSums(since: since) {
                var cur = byProject[r.project] ?? (0, 0)
                cur.0 += r.sums.billable
                cur.1 += Pricing.cost(model: r.model, r.sums)
                byProject[r.project] = cur
            }
            let top = byProject.map { (name: $0.key, tokens: $0.value.0, cost: $0.value.1) }
                .sorted { $0.tokens > $1.tokens }.prefix(6).map { $0 }
            DispatchQueue.main.async { self.rows = top }
        }
    }
}

struct ProjectsCard: View {
    @EnvironmentObject var state: AppState
    @StateObject private var model = ProjectsModel()

    var body: some View {
        let t = state.theme
        let rows = model.rows
        let mx = max(1, rows.map(\.tokens).max() ?? 1)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L.t("EN ÇOK KULLANILAN PROJELER")).font(t.font(10, .bold)).foregroundStyle(t.sub)
                Spacer()
                Text(L.t("Son 30 gün · yalnızca Claude Code, klasör adıyla")).font(t.font(10)).foregroundStyle(t.sub)
            }
            if rows.isEmpty {
                Text(L.t("Henüz proje verisi yok.")).font(t.font(11)).foregroundStyle(t.sub)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                HStack(spacing: 10) {
                    Text(r.name).font(t.font(12, .medium)).lineLimit(1).frame(width: 150, alignment: .leading)
                    GeometryReader { g in
                        Capsule().fill(Provider.claude.brandColor.opacity(0.85))
                            .frame(width: max(4, g.size.width * CGFloat(r.tokens) / CGFloat(mx)))
                    }
                    .frame(height: 8)
                    Text(formatTokens(r.tokens)).font(t.font(11).monospacedDigit()).frame(width: 52, alignment: .trailing)
                    Text("~" + Pricing.format(r.cost)).font(t.font(10).monospacedDigit()).foregroundStyle(t.sub)
                        .frame(width: 56, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(t, padding: 14)
        .onAppear { model.load() }
    }
}

// MARK: - Dışa aktarma ve paylaşım

enum Exporter {
    @MainActor static func saveCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ullage-gecmis.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? HistoryStore.shared.exportCSV().write(to: url, atomically: true, encoding: .utf8)
    }

    @MainActor static func saveShareCard(state: AppState) {
        let data = ShareData.load()
        let r = ImageRenderer(content: ShareCard(data: data, theme: state.theme))
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ullage-hafta.png"
        panel.allowedContentTypes = [.png]
        // Kaydetmeden önce panoya da koyulur; sohbete doğrudan yapıştırılabilir.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([img])
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? png.write(to: url)
    }
}

struct ShareData {
    var total = 0
    var days: [Int] = []
    var dayLabels: [String] = []
    var byProvider: [(Provider, Int)] = []
    var cost = 0.0

    static func load() -> ShareData {
        let cal = Calendar.current
        let t0 = cal.startOfDay(for: Date())
        let since = cal.date(byAdding: .day, value: -6, to: t0)!
        var d = ShareData()
        let store = HistoryStore.shared
        for p in Provider.allCases {
            let v = store.dailyTotals(provider: p.rawValue, days: 7)
            if d.days.isEmpty { d.days = Array(repeating: 0, count: 7) }
            for i in 0..<7 { d.days[i] += v[i] }
            let sum = v.reduce(0, +)
            if sum > 0 { d.byProvider.append((p, sum)) }
        }
        d.byProvider.sort { $0.1 > $1.1 }
        d.total = d.days.reduce(0, +)
        d.cost = store.modelSums(since: since).reduce(0) { $0 + Pricing.cost(model: $1.model, $1.sums) }
        let f = DateFormatter(); f.locale = L.locale; f.dateFormat = "EEEEE"
        d.dayLabels = (0..<7).map { f.string(from: cal.date(byAdding: .day, value: $0, to: since)!) }
        return d
    }
}

/// Paylaşılabilir haftalık kart. Yalnızca toplam sayılar; proje adı, yol ya da hesap bilgisi içermez.
struct ShareCard: View {
    let data: ShareData
    let theme: Theme

    var body: some View {
        let t = theme
        let mx = max(1, data.days.max() ?? 1)
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                LogoMark(size: 34, palette: t.logo)
                Text(AppInfo.name).font(t.font(20, .bold))
                Spacer()
                Text(L.t("Son 7 gün")).font(t.font(13)).foregroundStyle(t.sub)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(formatTokens(data.total)).font(t.font(54, .bold).monospacedDigit())
                Text(L.t("token")).font(t.font(18)).foregroundStyle(t.sub)
                Spacer()
                Text("~" + Pricing.format(data.cost)).font(t.font(20, .semibold).monospacedDigit())
                Text(L.t("API değeri")).font(t.font(12)).foregroundStyle(t.sub)
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<data.days.count, id: \.self) { i in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4).fill(t.accent.opacity(i == data.days.count - 1 ? 1 : 0.6))
                            .frame(height: max(4, 70 * CGFloat(data.days[i]) / CGFloat(mx)))
                        Text(data.dayLabels[i].uppercased()).font(t.font(10)).foregroundStyle(t.sub)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 96, alignment: .bottom)
            HStack(spacing: 14) {
                ForEach(Array(data.byProvider.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 6) {
                        Circle().fill(item.0.brandColor).frame(width: 9, height: 9)
                        Text(item.0.name).font(t.font(12, .medium))
                        Text(formatTokens(item.1)).font(t.font(12).monospacedDigit()).foregroundStyle(t.sub)
                    }
                }
                Spacer()
            }
        }
        .foregroundStyle(t.text)
        .padding(28)
        .frame(width: 560)
        .background(t.bg)
    }
}

// MARK: - İlk kurulum kontrolü

struct SetupCheck {
    struct Item: Identifiable { let id = UUID(); let ok: Bool; let title: String; let hint: String }

    @MainActor static func items(_ state: AppState) -> [Item] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        func exists(_ rel: String) -> Bool { FileManager.default.fileExists(atPath: home.appendingPathComponent(rel).path) }
        let claude = state.usage[.claude]
        let codex = state.usage[.codex]
        return [
            Item(ok: WindowStarter.cliPath != nil || exists(".claude"), title: L.t("Claude Code kurulu"),
                 hint: "Terminalde `claude` komutunu bir kez çalıştırıp giriş yap. Ullage limiti oradaki oturumdan okur."),
            Item(ok: claude?.limitConfidence == .exact, title: L.t("Claude limiti okunuyor"),
                 hint: "Claude Code'a giriş yapılı değilse ya da oturum bittiyse limit görünmez. Terminalde `claude` çalıştır, gerekirse /login yaz."),
            Item(ok: exists(".codex/sessions"), title: L.t("Codex kullanımı bulundu"),
                 hint: "Codex'i hiç kullanmadıysan bu normal. Kullanınca kendiliğinden görünür."),
            Item(ok: codex?.limitConfidence == .exact, title: L.t("Codex limiti okunuyor"),
                 hint: "Codex ile bir mesaj yazınca limit değeri kayıtlara düşer."),
            Item(ok: exists(".gemini/oauth_creds.json"), title: L.t("Gemini CLI oturumu var"),
                 hint: "Gemini istemiyorsan boş bırak. Kullanacaksan terminalde `gemini` çalıştırıp giriş yap.")
        ]
    }
}

struct SetupCheckCard: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let t = state.theme
        let items = SetupCheck.items(state)
        VStack(alignment: .leading, spacing: 10) {
            Text(L.t("KURULUM KONTROLÜ")).font(t.font(10, .bold)).foregroundStyle(t.sub)
            ForEach(items) { it in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: it.ok ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(it.ok ? Color.green : Color.orange).font(.system(size: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(it.title).font(t.font(12, .semibold))
                        if !it.ok {
                            Text(it.hint).font(t.font(10)).foregroundStyle(t.sub).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(t, padding: 14)
    }
}
