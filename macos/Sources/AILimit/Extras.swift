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
        .onChange(of: state.includeCache) { _, _ in model.load() }
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
                Text(L.t("Son 7 gün") + (Prefs.includeCache ? L.t(" · cache dahil") : "")).font(t.font(13)).foregroundStyle(t.sub)
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
                 hint: ClaudeLimitAPI.backoffEnd.map {
                     L.f("Anthropic bu hesaba geçici bir hız sınırı koydu. %@ sonrasında kendiliğinden düzelir, bir şey yapmana gerek yok. Uygulamayı o zamana kadar yeniden başlatma.", AppState.whenText($0))
                 } ?? "Claude Code'a giriş yapılı değilse ya da oturum bittiyse limit görünmez. Terminalde `claude` çalıştır, gerekirse /login yaz."),
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
                            Text(L.t(it.hint)).font(t.font(10)).foregroundStyle(t.sub).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(t, padding: 14)
    }
}

// MARK: - Temaya uyan onay kutusu

/// Sistemin onay kutusu yerine her temanın kendi diliyle çizilen kutu.
struct ThemedCheck: View {
    let t: Theme
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 8) {
                box
                Text(title).font(t.font(12, .medium)).foregroundStyle(t.text).lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private let size: CGFloat = 18

    @ViewBuilder private var box: some View {
        switch t.id {
        case "terminal":
            Text(isOn ? "[x]" : "[ ]").font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(t.accent)
        case "brutal":
            ZStack {
                Rectangle().fill(Color.black).frame(width: size, height: size).offset(x: 2.5, y: 2.5)
                Rectangle().fill(isOn ? t.accent : t.card).frame(width: size, height: size)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 3))
                if isOn { Image(systemName: "xmark").font(.system(size: 10, weight: .black)).foregroundStyle(.black) }
            }
            .frame(width: size + 3, height: size + 3)
        case "sticker":
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color.black).frame(width: size, height: size).offset(x: 1.5, y: 1.5)
                RoundedRectangle(cornerRadius: 6).fill(isOn ? t.accent : t.card).frame(width: size, height: size)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black, lineWidth: 2))
                if isOn { Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.black) }
            }
            .frame(width: size + 2, height: size + 2)
        case "neon":
            RoundedRectangle(cornerRadius: 4).stroke(t.accent, lineWidth: 1.5).frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: 4).fill(t.accent.opacity(isOn ? 0.25 : 0)))
                .shadow(color: t.accent.opacity(isOn ? 0.9 : 0.35), radius: isOn ? 5 : 2)
                .overlay { if isOn { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(t.accent) } }
        case "paper":
            RoundedRectangle(cornerRadius: 2).stroke(t.text.opacity(0.65), lineWidth: 1).frame(width: size - 2, height: size - 2)
                .overlay { if isOn { Text("✓").font(.system(size: 15, weight: .regular, design: .serif)).foregroundStyle(t.accent).offset(x: 1, y: -2) } }
        case "glass":
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(isOn ? 0.30 : 0.10)).frame(width: size, height: size)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.white.opacity(isOn ? 0.75 : 0.35), lineWidth: 1))
                .overlay { if isOn { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white) } }
        case "light":
            RoundedRectangle(cornerRadius: 5).fill(isOn ? t.accent : Color.clear).frame(width: size, height: size)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(isOn ? t.accent : t.sub, lineWidth: 1.5))
                .overlay { if isOn { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) } }
        default:   // sistem ve koyu
            RoundedRectangle(cornerRadius: 5).fill(isOn ? t.accent : t.card).frame(width: size, height: size)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(isOn ? t.accent : t.sub.opacity(0.75), lineWidth: 1.5))
                .overlay { if isOn { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) } }
        }
    }
}

// MARK: - Temaya uyan seçici (segmented)

/// Sistemin segmentli seçicisi yerine her temanın kendi diliyle çizilen seçici.
struct ThemedSegmented<V: Hashable>: View {
    let t: Theme
    let items: [(label: String, value: V)]
    @Binding var selection: V

    var body: some View {
        container {
            HStack(spacing: spacing) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                    Button { selection = it.value } label: { segment(it.label, on: selection == it.value) }
                        .buttonStyle(.plain)
                }
            }
        }
        .fixedSize()
    }

    private var spacing: CGFloat {
        switch t.id {
        case "terminal": 6
        case "sticker", "brutal": 6
        case "paper": 14
        default: 2
        }
    }

    @ViewBuilder private func container<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        switch t.id {
        case "terminal", "sticker", "brutal", "paper":
            c()
        case "neon":
            c().padding(3).background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(t.accent.opacity(0.5), lineWidth: 1))
        case "glass":
            c().padding(3).background(Color.white.opacity(0.08), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
        default:
            c().padding(3).background(t.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(t.border.opacity(0.8), lineWidth: 1))
        }
    }

    @ViewBuilder private func segment(_ label: String, on: Bool) -> some View {
        switch t.id {
        case "terminal":
            Text(on ? "[\(label)]" : " \(label) ")
                .font(.system(size: 12, weight: on ? .bold : .regular, design: .monospaced))
                .foregroundStyle(on ? Color.black : t.accent)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(on ? t.accent : Color.clear)
        case "sticker":
            Text(label).font(t.font(12, on ? .bold : .medium)).foregroundStyle(Color.black)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8).fill(on ? t.accent : t.card))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black, lineWidth: 2))
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black).offset(x: on ? 1.5 : 0, y: on ? 1.5 : 0))
        case "paper":
            VStack(spacing: 2) {
                Text(label).font(t.font(12, on ? .bold : .regular)).foregroundStyle(on ? t.text : t.sub)
                Rectangle().fill(on ? t.accent : Color.clear).frame(height: 1.5)
            }
        case "neon":
            Text(label).font(t.font(12, on ? .bold : .medium)).foregroundStyle(on ? t.accent : t.sub)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(t.accent.opacity(on ? 0.22 : 0)))
                .shadow(color: t.accent.opacity(on ? 0.8 : 0), radius: 4)
        case "brutal":
            Text(label).font(t.font(12, .heavy)).foregroundStyle(on ? t.card : Color.black)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Rectangle().fill(on ? Color.black : t.card))
                .overlay(Rectangle().stroke(Color.black, lineWidth: 3))
        case "glass":
            Text(label).font(t.font(12, on ? .semibold : .regular)).foregroundStyle(on ? Color.white : Color.white.opacity(0.7))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(on ? 0.28 : 0)))
        default:
            Text(label).font(t.font(12, on ? .semibold : .regular)).foregroundStyle(on ? t.text : t.sub)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? t.accent.opacity(0.28) : Color.clear))
        }
    }
}
