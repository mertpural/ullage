import SwiftUI
import Charts

enum HistoryRange: String, CaseIterable, Identifiable {
    case day = "24 saat", week = "7 gün", month = "30 gün"
    var id: String { rawValue }
    var hourly: Bool { self == .day }
    var since: Date {
        let cal = Calendar.current
        switch self {
        case .day: return Date().addingTimeInterval(-24 * 3600)
        case .week: return cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: Date()))!
        case .month: return cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: Date()))!
        }
    }
}

enum GroupBy: String, CaseIterable, Identifiable {
    case provider = "Sağlayıcı", model = "Model"
    var id: String { rawValue }
}

@MainActor
final class HistoryModel: ObservableObject {
    @Published var range: HistoryRange = .week { didSet { reload() } }
    @Published var group: GroupBy = .provider
    @Published var includeCache = false { didSet { reload() } }
    @Published var filter: String? = nil
    @Published var points: [HistoryStore.Point] = []
    /// "yyyy-MM-dd" -> sağlayıcı -> token (cache hariç), son 3 yıl.
    @Published var heat: [String: [String: Int]] = [:]
    @Published var hoverKey: String? = nil
    /// Açıkken her kare o günün sağlayıcı dağılımına göre renklere bölünür.
    @Published var heatByProvider: Bool = UserDefaults.standard.object(forKey: "heatByProvider") as? Bool ?? true {
        didSet { UserDefaults.standard.set(heatByProvider, forKey: "heatByProvider") }
    }
    @Published var allTime = 0
    @Published var today = 0
    @Published var yesterday = 0
    @Published var last7 = 0
    @Published var prev7 = 0
    @Published var last30 = 0
    @Published var costToday = 0.0
    @Published var cost7 = 0.0
    @Published var cost30 = 0.0

    static let keyFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }()

    func loadHeat() {
        let cal = Calendar.current
        let since = cal.date(byAdding: .year, value: -3, to: cal.startOfDay(for: Date()))!
        let pts = HistoryStore.shared.series(since: since, hourly: false, includeCache: false)
        var h: [String: [String: Int]] = [:]
        for p in pts { h[Self.keyFmt.string(from: p.bucket), default: [:]][p.provider, default: 0] += p.tokens }
        heat = h
        var total = 0
        for p in ["claude", "codex", "antigravity"] { total += HistoryStore.shared.sums(provider: p, since: .distantPast).billable }
        allTime = total
    }

    /// Seçili sağlayıcı filtresine göre bir günün toplamı.
    func dayTotal(_ key: String) -> Int {
        guard let d = heat[key] else { return 0 }
        if let f = filter { return d[f] ?? 0 }
        return d.values.reduce(0, +)
    }

    struct Streaks { var current = 0; var longest = 0; var activeDays = 0; var bestKey: String?; var bestTokens = 0 }

    var streaks: Streaks {
        var s = Streaks()
        let cal = Calendar.current
        let keys = heat.keys.filter { dayTotal($0) > 0 }.sorted()
        s.activeDays = keys.count
        for k in keys where dayTotal(k) > s.bestTokens { s.bestTokens = dayTotal(k); s.bestKey = k }
        var run = 0
        var prev: Date?
        for k in keys {
            guard let d = Self.keyFmt.date(from: k) else { continue }
            if let p = prev, cal.dateComponents([.day], from: p, to: d).day == 1 { run += 1 } else { run = 1 }
            s.longest = max(s.longest, run)
            prev = d
        }
        // Güncel seri: bugünden (bugün boşsa dünden) geriye doğru kesintisiz aktif günler.
        var day = cal.startOfDay(for: Date())
        if dayTotal(Self.keyFmt.string(from: day)) == 0 { day = cal.date(byAdding: .day, value: -1, to: day)! }
        while dayTotal(Self.keyFmt.string(from: day)) > 0 {
            s.current += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return s
    }

    init() {
        loadHeat()
        loadTotals()
        points = HistoryStore.shared.series(since: range.since, hourly: range.hourly, includeCache: includeCache)
    }

    func loadTotals() {
        let cal = Calendar.current
        let t0 = cal.startOfDay(for: Date())
        let y0 = cal.date(byAdding: .day, value: -1, to: t0)!
        let w0 = cal.date(byAdding: .day, value: -6, to: t0)!
        let pw0 = cal.date(byAdding: .day, value: -13, to: t0)!
        let m0 = cal.date(byAdding: .day, value: -29, to: t0)!
        var a = [0, 0, 0, 0, 0]
        for p in ["claude", "codex", "antigravity"] {
            let s = HistoryStore.shared
            a[0] += s.sums(provider: p, since: t0).billable
            a[1] += s.sums(provider: p, since: y0).billable
            a[2] += s.sums(provider: p, since: w0).billable
            a[3] += s.sums(provider: p, since: pw0).billable
            a[4] += s.sums(provider: p, since: m0).billable
        }
        today = a[0]; yesterday = a[1] - a[0]; last7 = a[2]; prev7 = a[3] - a[2]; last30 = a[4]
        func cost(_ since: Date) -> Double {
            HistoryStore.shared.modelSums(since: since).reduce(0) { $0 + Pricing.cost(model: $1.model, $1.sums) }
        }
        costToday = cost(t0); cost7 = cost(w0); cost30 = cost(m0)
    }

    func reload() {
        let r = range, c = includeCache
        Task.detached {
            let pts = HistoryStore.shared.series(since: r.since, hourly: r.hourly, includeCache: c)
            await MainActor.run { self.points = pts }
        }
    }

    var filtered: [HistoryStore.Point] {
        guard let f = filter else { return points }
        return points.filter { $0.provider == f }
    }

    func label(_ p: HistoryStore.Point) -> String {
        group == .provider ? (Provider(rawValue: p.provider)?.name ?? p.provider) : p.model
    }

    var totals: [(String, Int)] {
        Dictionary(grouping: filtered, by: label).map { ($0.key, $0.value.reduce(0) { $0 + $1.tokens }) }
            .sorted { $0.1 > $1.1 }
    }
}

struct StatCard: View {
    @EnvironmentObject var state: AppState
    let title: String
    let value: Int
    let compareTo: Int?
    let compareLabel: String

    var body: some View {
        let t = state.theme
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(t.font(10, .bold)).foregroundStyle(t.sub)
            Text(formatTokens(value)).font(t.font(26, .bold).monospacedDigit())
            if let c = compareTo, c > 0 {
                let d = Double(value - c) / Double(c)
                let up = d >= 0
                HStack(spacing: 3) {
                    Image(systemName: up ? "arrow.up.right" : "arrow.down.right").font(.system(size: 9, weight: .bold))
                    Text("\(abs(Int((d * 100).rounded())))% \(compareLabel)").font(t.font(10))
                }
                .foregroundStyle(up ? Color.orange : Color.green)
            } else {
                Text(" ").font(t.font(10))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(t, padding: 14)
    }
}

struct CostCard: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var model: HistoryModel

    var body: some View {
        let t = state.theme
        HStack(alignment: .center, spacing: 22) {
            VStack(alignment: .leading, spacing: 2) {
                Text("TAHMİNİ API MALİYETİ").font(t.font(10, .bold)).foregroundStyle(t.sub)
                Text("Aynı token'ları API fiyatıyla alsaydın ödeyeceğin tutar. Abonelik ücretin değil, tahminidir.")
                    .font(t.font(10)).foregroundStyle(t.sub).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            ForEach([("Bugün", model.costToday), ("7 gün", model.cost7), ("30 gün", model.cost30)], id: \.0) { item in
                VStack(alignment: .trailing, spacing: 0) {
                    Text("~" + Pricing.format(item.1)).font(t.font(18, .bold).monospacedDigit())
                    Text(item.0).font(t.font(10)).foregroundStyle(t.sub)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(t, padding: 14)
    }
}

struct HistoryPage: View {
    @EnvironmentObject var state: AppState
    @StateObject private var model = HistoryModel()

    var body: some View {
        let t = state.theme
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                StatCard(title: "BUGÜN", value: model.today, compareTo: model.yesterday, compareLabel: "düne göre")
                StatCard(title: "DÜN", value: model.yesterday, compareTo: nil, compareLabel: "")
                StatCard(title: "SON 7 GÜN", value: model.last7, compareTo: model.prev7, compareLabel: "önceki haftaya göre")
                StatCard(title: "SON 30 GÜN", value: model.last30, compareTo: nil, compareLabel: "")
            }

            CostCard(model: model)
            ActivityStats(model: model)
            HeatmapCard(model: model)

            HStack(spacing: 10) {
                Picker("", selection: $model.range) {
                    ForEach(HistoryRange.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 260)
                Picker("", selection: $model.group) {
                    ForEach(GroupBy.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 180)
                Spacer()
                Toggle("Cache dahil", isOn: $model.includeCache).toggleStyle(.checkbox)
            }

            HStack(spacing: 6) {
                Pill(t: t, selected: model.filter == nil, action: { model.filter = nil }) { Text("Hepsi").font(t.font(11, .medium)) }
                ForEach(["claude", "codex", "antigravity"], id: \.self) { id in
                    if let p = Provider(rawValue: id) {
                        Pill(t: t, selected: model.filter == id, action: { model.filter = id }) {
                            HStack(spacing: 5) { BrandBadge(provider: p, size: 14); Text(p.name).font(t.font(11, .medium)) }
                        }
                    }
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Token kullanımı").font(t.font(13, .semibold))
                    Spacer()
                    Text(formatTokens(model.totals.reduce(0) { $0 + $1.1 }) + " toplam").font(t.font(12)).foregroundStyle(t.sub)
                }
                if model.filtered.isEmpty {
                    Text("Bu aralıkta kayıt yok.").foregroundStyle(t.sub)
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    Chart(model.filtered) { p in
                        BarMark(
                            x: .value("Zaman", p.bucket, unit: model.range.hourly ? .hour : .day),
                            y: .value("Token", p.tokens)
                        )
                        .foregroundStyle(by: .value("Grup", model.label(p)))
                        .cornerRadius(3)
                    }
                    .chartForegroundStyleScale(domain: model.totals.map(\.0), range: model.totals.map { color(for: $0.0) })
                    .chartLegend(.hidden)
                    .chartYAxis {
                        AxisMarks { v in
                            AxisGridLine().foregroundStyle(t.sub.opacity(0.2))
                            AxisValueLabel { if let n = v.as(Int.self) { Text(formatTokens(n)).foregroundStyle(t.sub) } }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 7)) { _ in
                            AxisValueLabel(format: model.range.hourly ? .dateTime.hour() : .dateTime.day().month(.abbreviated))
                                .foregroundStyle(t.sub)
                        }
                    }
                    .frame(height: 260)
                }
            }
            .card(t, padding: 16)

            VStack(alignment: .leading, spacing: 10) {
                Text("Dağılım").font(t.font(13, .semibold))
                let total = max(1, model.totals.reduce(0) { $0 + $1.1 })
                ForEach(model.totals, id: \.0) { name, tokens in
                    HStack(spacing: 10) {
                        Circle().fill(color(for: name)).frame(width: 9, height: 9)
                        Text(name).font(t.font(12)).frame(width: 170, alignment: .leading).lineLimit(1)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(t.sub.opacity(0.18))
                                Capsule().fill(color(for: name)).frame(width: g.size.width * CGFloat(tokens) / CGFloat(total))
                            }
                        }.frame(height: 6)
                        Text(formatTokens(tokens)).font(t.font(12, .medium).monospacedDigit()).frame(width: 64, alignment: .trailing)
                        Text("\(Int((Double(tokens) / Double(total) * 100).rounded()))%").font(t.font(11)).foregroundStyle(t.sub)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
            }
            .card(t, padding: 16)
        }
        .onAppear { model.loadHeat(); model.loadTotals(); model.reload() }
    }

    private func color(for name: String) -> Color {
        if let p = Provider.allCases.first(where: { $0.name == name }) { return p.brandColor }
        let palette: [Color] = [.blue, .orange, .teal, .pink, .purple, .mint, .indigo, .brown, .cyan]
        let idx = model.totals.map(\.0).firstIndex(of: name) ?? 0
        return palette[idx % palette.count]
    }
}


// MARK: - Etkinlik tablosu (GitHub tarzı)

struct ActivityStats: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var model: HistoryModel

    var body: some View {
        let s = model.streaks
        let avg = s.activeDays > 0 ? model.heat.keys.reduce(0) { $0 + model.dayTotal($1) } / s.activeDays : 0
        HStack(spacing: 12) {
            Stat(title: "TOPLAM TOKEN", value: formatTokens(model.allTime), sub: "tüm zamanlar", icon: "sum")
            Stat(title: "GÜNCEL SERİ", value: "\(s.current) gün", sub: s.current > 0 ? "kesintisiz kullanım" : "bugün kullanım yok", icon: "flame.fill")
            Stat(title: "EN UZUN SERİ", value: "\(s.longest) gün", sub: "\(s.activeDays) aktif gün", icon: "trophy.fill")
            Stat(title: "EN YOĞUN GÜN", value: formatTokens(s.bestTokens), sub: s.bestKey.map(Self.pretty) ?? "–", icon: "bolt.fill")
            Stat(title: "GÜNLÜK ORT.", value: formatTokens(avg), sub: "aktif gün başına", icon: "chart.line.uptrend.xyaxis")
        }
    }

    static func pretty(_ key: String) -> String {
        guard let d = HistoryModel.keyFmt.date(from: key) else { return key }
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }
}

struct Stat: View {
    @EnvironmentObject var state: AppState
    let title: String
    let value: String
    let sub: String
    let icon: String

    var body: some View {
        let t = state.theme
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 9)).foregroundStyle(t.accent)
                Text(title).font(t.font(9, .bold)).foregroundStyle(t.sub)
            }
            Text(value).font(t.font(20, .bold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(sub).font(t.font(10)).foregroundStyle(t.sub).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(t, padding: 12)
    }
}

struct HeatmapCard: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var model: HistoryModel

    private let weeks = 53
    /// Her şey kare boyutu `u` cinsinden ölçeklenir: böylece tablo genişliğe göre büyür ve yüksekliği
    /// oranla belirlenir (altında boşluk kalmaz).
    private var unitsW: CGFloat { 2.4 + CGFloat(weeks) + CGFloat(weeks - 1) * 0.25 }
    private let unitsH: CGFloat = 1.4 + 7 + 6 * 0.25

    private var cal: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }

    /// Haftanın pazartesisinden başlayan, `weeks` sütunlu ızgara. Gelecek günler nil.
    private var grid: [[Date?]] {
        let c = cal
        let today = c.startOfDay(for: Date())
        let thisMonday = c.date(from: c.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        let start = c.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisMonday)!
        return (0..<weeks).map { w in
            (0..<7).map { r in
                let d = c.date(byAdding: .day, value: w * 7 + r, to: start)!
                return d > today ? nil : d
            }
        }
    }

    private func level(_ v: Int, thresholds: [Int]) -> Int {
        if v <= 0 { return 0 }
        for (i, th) in thresholds.enumerated() where v <= th { return i + 1 }
        return thresholds.count + 1
    }

    private func color(_ lv: Int, _ t: Theme) -> Color {
        lv == 0 ? t.sub.opacity(0.14) : t.accent.opacity([0, 0.28, 0.5, 0.75, 1.0][min(lv, 4)])
    }

    /// Tek bir günün karesi. Sağlayıcıya göre modda kare, o günkü token paylarına göre dikey renk bölümlerine ayrılır;
    /// koyuluk yine günün yoğunluğunu gösterir.
    @ViewBuilder private func dayCell(key: String, value: Int, lv: Int, size: CGFloat, t: Theme) -> some View {
        if model.heatByProvider, value > 0, let day = model.heat[key] {
            let parts: [(Color, CGFloat)] = Provider.allCases.compactMap { p in
                guard let v = day[p.rawValue], v > 0, model.filter == nil || model.filter == p.rawValue else { return nil }
                return (p.brandColor, CGFloat(v) / CGFloat(value))
            }
            VStack(spacing: 0) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    Rectangle().fill(part.0).frame(height: size * part.1)
                }
            }
            .frame(width: size, height: size)
            .opacity([0.0, 0.5, 0.68, 0.84, 1.0][min(lv, 4)])
            .clipShape(RoundedRectangle(cornerRadius: 2))
        } else {
            RoundedRectangle(cornerRadius: 2)
                .fill(model.heatByProvider ? t.sub.opacity(0.14) : color(lv, t))
                .frame(width: size, height: size)
        }
    }

    private var readout: String {
        guard let k = model.hoverKey, let d = HistoryModel.keyFmt.date(from: k) else {
            return "Bir günün üzerine gel, o günkü kullanımı gör."
        }
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = "d MMMM yyyy, EEEE"
        let day = model.heat[k] ?? [:]
        let total = model.dayTotal(k)
        if total == 0 { return "\(f.string(from: d)) · kullanım yok" }
        let parts = day.filter { model.filter == nil || $0.key == model.filter }
            .sorted { $0.value > $1.value }
            .map { "\(Provider(rawValue: $0.key)?.name ?? $0.key) \(formatTokens($0.value))" }
            .joined(separator: " · ")
        return "\(f.string(from: d)) · \(formatTokens(total)) token · \(parts)"
    }

    var body: some View {
        let t = state.theme
        let g = grid
        let values = g.flatMap { $0 }.compactMap { $0 }.map { model.dayTotal(HistoryModel.keyFmt.string(from: $0)) }.filter { $0 > 0 }.sorted()
        let thresholds: [Int] = values.isEmpty ? [] : [0.25, 0.5, 0.75].map { values[min(values.count - 1, Int(Double(values.count) * $0))] }
        let months: [Int: String] = {
            var m: [Int: String] = [:]
            var last = -1
            let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = "MMM"
            for (i, col) in g.enumerated() {
                guard let d = col.compactMap({ $0 }).first else { continue }
                let mo = cal.component(.month, from: d)
                if mo != last { m[i] = f.string(from: d); last = mo }
            }
            return m
        }()

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Etkinlik").font(t.font(13, .semibold))
                Text("Son 53 hafta").font(t.font(11)).foregroundStyle(t.sub)
                Spacer()
                Pill(t: t, selected: model.heatByProvider, action: { model.heatByProvider = true }) {
                    Text("Sağlayıcıya göre renk").font(t.font(11, .medium))
                }
                Pill(t: t, selected: !model.heatByProvider, action: { model.heatByProvider = false }) {
                    Text("Yoğunluk").font(t.font(11, .medium))
                }
            }

            GeometryReader { geo in
                let cell = geo.size.width / unitsW
                let gap = cell * 0.25
                let labelW = cell * 2.4
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        Color.clear.frame(height: cell * 1.4)
                        ForEach(Array(months.keys.sorted()), id: \.self) { i in
                            Text(months[i] ?? "").font(t.font(9)).foregroundStyle(t.sub)
                                .offset(x: labelW + CGFloat(i) * (cell + gap))
                        }
                    }
                    HStack(alignment: .top, spacing: 0) {
                        VStack(alignment: .leading, spacing: gap) {
                            ForEach(0..<7, id: \.self) { r in
                                Text([0, 2, 4].contains(r) ? ["Pzt", "", "Çar", "", "Cum", "", ""][r] : "")
                                    .font(t.font(9)).foregroundStyle(t.sub).frame(height: cell, alignment: .leading)
                            }
                        }
                        .frame(width: labelW, alignment: .leading)
                        HStack(alignment: .top, spacing: gap) {
                            ForEach(0..<weeks, id: \.self) { w in
                                VStack(spacing: gap) {
                                    ForEach(0..<7, id: \.self) { r in
                                        if let d = g[w][r] {
                                            let key = HistoryModel.keyFmt.string(from: d)
                                            let v = model.dayTotal(key)
                                            dayCell(key: key, value: v, lv: level(v, thresholds: thresholds), size: cell, t: t)
                                                .overlay(RoundedRectangle(cornerRadius: 2)
                                                    .stroke(t.text.opacity(model.hoverKey == key ? 0.9 : 0), lineWidth: 1.5))
                                                .onHover { inside in
                                                    if inside { model.hoverKey = key } else if model.hoverKey == key { model.hoverKey = nil }
                                                }
                                        } else {
                                            Color.clear.frame(width: cell, height: cell)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .aspectRatio(unitsW / unitsH, contentMode: .fit)

            HStack {
                Text(readout).font(t.font(12, .medium)).lineLimit(1)
                Spacer()
                if model.heatByProvider {
                    HStack(spacing: 10) {
                        ForEach(["claude", "codex", "antigravity"], id: \.self) { id in
                            if let p = Provider(rawValue: id), model.filter == nil || model.filter == id {
                                HStack(spacing: 4) {
                                    Circle().fill(p.brandColor).frame(width: 8, height: 8)
                                    Text(p.name).font(t.font(10)).foregroundStyle(t.sub)
                                }
                            }
                        }
                    }
                } else {
                    HStack(spacing: 4) {
                        Text("Az").font(t.font(10)).foregroundStyle(t.sub)
                        ForEach(0..<5, id: \.self) { lv in
                            RoundedRectangle(cornerRadius: 2).fill(color(lv, t)).frame(width: 11, height: 11)
                        }
                        Text("Çok").font(t.font(10)).foregroundStyle(t.sub)
                    }
                }
            }
        }
        .card(t, padding: 16)
    }
}
