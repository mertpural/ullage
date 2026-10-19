import SwiftUI

// MARK: - Marka ikonu

/// Gemini için kurulu bir uygulama yok; dört köşeli yıldız (sparkle) şekli çizilir.
struct Sparkle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY)
        let k = r.width * 0.12
        p.move(to: CGPoint(x: c.x, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: c.y), control: CGPoint(x: c.x + k, y: c.y - k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: r.maxY), control: CGPoint(x: c.x + k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: c.y), control: CGPoint(x: c.x - k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: r.minY), control: CGPoint(x: c.x - k, y: c.y - k))
        return p
    }
}

struct BrandBadge: View {
    let provider: Provider
    var size: CGFloat = 14

    var body: some View {
        if let img = provider.icon {
            if provider == .codex {
                // Tek renkli maske: alfa kanalı şekli verir, renk marka grisiyle boyanır.
                Image(nsImage: img).resizable().renderingMode(.template).scaledToFit()
                    .foregroundStyle(provider.brandColor).frame(width: size, height: size)
            } else {
                Image(nsImage: img).resizable().scaledToFit().frame(width: size, height: size)
            }
        } else if provider == .gemini {
            Sparkle().fill(provider.brandColor).frame(width: size, height: size)
        } else {
            Text(provider.letter)
                .font(.system(size: size * 0.65, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(provider.brandColor, in: RoundedRectangle(cornerRadius: size * 0.28))
        }
    }
}

extension View {
    @ViewBuilder func themed(_ t: Theme) -> some View {
        if let s = t.scheme { self.environment(\.colorScheme, s) } else { self }
    }
}

// MARK: - Menü çubuğu

struct MiniBar: View {
    let left: Double?
    var width: CGFloat = 24

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.gray.opacity(0.35))
            if let l = left {
                Capsule().fill(statusColor(l)).frame(width: max(2, width * l))
            }
        }
        .frame(width: width, height: 4)
    }
}

/// Menü çubuğu etiketi. Her sağlayıcı için logo ve seçilen göstergeler; 5 saatlik "5s", haftalık "H"
/// etiketiyle ayırt edilir. MenuBarExtra etiketi yalnızca Text/Image render eder, bu yüzden görsele çevrilir.
struct MenuBarLabel: View {
    @EnvironmentObject var state: AppState
    var forceDark: Bool? = nil

    var body: some View {
        let isDark = forceDark ?? (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        let t = state.theme
        let themed = t.id != "system"  // tema renk, yazı tipi ve çerçeveyi verir; gösterge tipi kullanıcının seçimidir
        // Sistem temasında menü çubuğuna uyar; diğer temalarda tema renkleri, yazı tipi ve köşe biçimi uygulanır.
        let look = Self.look(t, isDark: isDark)
        let text: Color = look.number
        let chipRadius = min(t.pillRadius, 10)
        let content = HStack(spacing: 12) {
            ForEach(Provider.allCases.filter { state.enabled.contains($0) }) { p in
                ProviderStrip(provider: p, usage: state.usage[p], text: text, tagColor: look.tag)
            }
        }
        .frame(height: 18)
        .padding(.horizontal, themed ? 10 : 2)
        .padding(.vertical, themed ? 1 : 0)
        // Çerçeve yok: yalnızca temaya göre renkli dolgu.
        .background(look.fill, in: RoundedRectangle(cornerRadius: chipRadius, style: .continuous))
        .environmentObject(state)

        if let img = Self.render(content) {
            Image(nsImage: img)
        } else {
            Text("AI")
        }
    }

    /// Menü çubuğu etiketinin tema başına görünümü: dolgu, rakam rengi, 5s/H etiket rengi.
    static func look(_ t: Theme, isDark: Bool) -> (fill: Color, number: Color, tag: Color) {
        switch t.id {
        case "dark": return (Color(red: 0.55, green: 0.45, blue: 1).opacity(0.30), .white, Color(red: 0.76, green: 0.68, blue: 1))
        case "light": return (Color(red: 0.85, green: 0.45, blue: 0.30).opacity(0.20), Color(red: 0.30, green: 0.11, blue: 0.06), Color(red: 0.70, green: 0.38, blue: 0.25))
        case "terminal": return (.black, Color(red: 0.45, green: 1, blue: 0.55), Color(red: 0.28, green: 0.62, blue: 0.34))
        case "sticker": return (Color.white.opacity(0.95), .black, Color(red: 0.10, green: 0.60, blue: 0.50))
        case "paper": return (Color(red: 0.97, green: 0.94, blue: 0.86), Color(red: 0.20, green: 0.16, blue: 0.11), Color(red: 0.56, green: 0.36, blue: 0.20))
        case "neon": return (Color(red: 0.04, green: 0.04, blue: 0.10), Color(red: 0.20, green: 0.95, blue: 1.0), Color(red: 1.0, green: 0.25, blue: 0.80))
        case "brutal": return (Color(red: 1.0, green: 0.90, blue: 0.20), .black, Color(red: 0.75, green: 0.12, blue: 0.12))
        case "glass": return (Color.white.opacity(0.20), .white, Color(red: 0.72, green: 0.92, blue: 1.0))
        default:
            let base: Color = isDark ? .white : .black
            return (.clear, base, base.opacity(0.55))
        }
    }

    @MainActor
    static func render<V: View>(_ v: V) -> NSImage? {
        let renderer = ImageRenderer(content: v)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage
    }
}

struct ProviderStrip: View {
    @EnvironmentObject var state: AppState
    let provider: Provider
    let usage: Usage?
    let text: Color
    var tagColor: Color? = nil

    var body: some View {
        let est = false  // kesin/tahmini bilgisi yalnızca Ayarlar'da gösterilir
        let tags = state.showTags
        HStack(spacing: 5) {
            BrandBadge(provider: provider, size: 15)
            let five = usage?.fiveRow, week = usage?.weekRow
            if five == nil && week == nil {
                let other = usage?.otherRows.map(\.left).min()
                MetricGlyph(left: other, style: state.styleFive, tag: other == nil ? nil : (tags ? "G" : nil), text: text, estimate: est, tagColor: tagColor)
            } else {
                if state.showFive {
                    MetricGlyph(left: five?.left, style: state.styleFive, tag: tags ? "5s" : nil, text: text, estimate: est, tagColor: tagColor)
                }
                if state.showWeek {
                    MetricGlyph(left: week?.left, style: state.styleWeek, tag: tags ? "H" : nil, text: text, estimate: est, tagColor: tagColor)
                }
            }
        }
    }
}

// MARK: - Popover

struct Pill<Content: View>: View {
    let t: Theme
    var selected = false
    let action: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        // Button, onTapGesture yerine: menü çubuğu penceresinde dokunuşların kaçmasını önler.
        Button(action: action) {
            content
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(selected ? t.accent.opacity(0.30) : t.card, in: RoundedRectangle(cornerRadius: t.pillRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: t.pillRadius, style: .continuous).stroke(selected ? t.accent : Color.clear, lineWidth: selected ? 1.5 : 0))
                .contentShape(RoundedRectangle(cornerRadius: t.pillRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct PopoverView: View {
    @EnvironmentObject var state: AppState
    /// Görüntü kontrolünde (ImageRenderer) kaydırma alanı boş çıktığı için içerik düz yığın olarak çizilir.
    static var snapshot = false

    private var visible: [Provider] { Provider.allCases.filter { state.enabled.contains($0) } }

    /// Pencere yüksekliği sabit: sekme değişince pencere boyutu kaymaz, arka plan her zaman tamamını doldurur.
    /// Üst (başlık, sekmeler) ve alt (düğmeler) sabit; ortadaki içerik kaydırılabilir.
    var body: some View {
        let t = state.theme
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(AppInfo.name).font(t.font(15, .bold))
                Spacer()
                if let u = state.updatedAt {
                    Text("Güncellendi \(Self.time.string(from: u))").font(t.font(10)).foregroundStyle(t.sub)
                }
            }
            TabBar()
            if PopoverView.snapshot {
                content(t)
            } else {
                // İçerik kadar yer kaplar; uzunsa en fazla 460 pt yüksekliğinde kaydırılır.
                ScrollView(.vertical, showsIndicators: false) {
                    content(t).frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(height: min(contentHeight, 460))
            }
            HStack(spacing: 8) {
                Pill(t: t, action: { state.openDashboard("history") }) { Label("Kullanım", systemImage: "chart.bar.fill").font(t.font(11, .medium)) }
                Pill(t: t, action: { state.openDashboard("providers") }) { Label("Ayarlar", systemImage: "gearshape.fill").font(t.font(11, .medium)) }
                Spacer()
                Pill(t: t, action: { state.refresh(force: true) }) { Image(systemName: "arrow.clockwise").font(t.font(11, .medium)) }
                Pill(t: t, action: { NSApplication.shared.terminate(nil) }) { Image(systemName: "power").font(t.font(11, .medium)) }
            }
        }
        .foregroundStyle(t.text)
        .padding(16)
        .frame(width: 380, height: totalHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)   // pencere büyük kalsa bile arka plan hepsini doldurur
        .background(t.bg)
        .background(WindowFitter(height: totalHeight))
        .themed(t)
    }

    /// Her sekmenin içerik yüksekliği duruma göre hesaplanır, böylece sekme değişince pencere boyu deterministik olur
    /// ve Tümü'ne dönünce aynı boya geri gelir.
    private var totalHeight: CGFloat { PopoverView.snapshot ? 640 : min(contentHeight, 460) + 170 }

    private var contentHeight: CGFloat {
        if visible.isEmpty { return 40 }
        let showAll = state.selectedTab == "all" || Provider(rawValue: state.selectedTab).map({ !state.enabled.contains($0) }) ?? true
        if showAll {
            let cards = visible.map { (state.usage[$0]?.rows.isEmpty ?? true) ? CGFloat(78) : CGFloat(128) }
            return cards.reduce(0, +) + CGFloat(max(0, cards.count - 1)) * 10
        }
        guard let p = Provider(rawValue: state.selectedTab), let u = state.usage[p] else { return 120 }
        var h: CGFloat = 40
        if u.rows.isEmpty { return h + 80 }
        if u.fiveRow != nil || u.weekRow != nil { h += 160 }
        if u.extra.count > 2 || !u.otherRows.isEmpty { h += 36 + CGFloat(u.extra.count) * 34 }
        if u.todayTokens != nil { h += 120 }
        return h
    }

    @ViewBuilder private func content(_ t: Theme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if visible.isEmpty {
                Text("Hiçbir sağlayıcı seçili değil. Ayarlardan aç.").font(t.font(12)).foregroundStyle(t.sub)
            } else if state.selectedTab == "all" || Provider(rawValue: state.selectedTab).map({ !state.enabled.contains($0) }) ?? true {
                ForEach(visible) { p in OverviewCard(provider: p, usage: state.usage[p] ?? .loading()) }
            } else if let p = Provider(rawValue: state.selectedTab) {
                ProviderDetail(provider: p, usage: state.usage[p] ?? .loading())
            }
        }
    }

    static let time: DateFormatter = { let f = DateFormatter(); f.timeStyle = .short; return f }()
}

struct TabBar: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let t = state.theme
        HStack(spacing: 6) {
            Pill(t: t, selected: state.selectedTab == "all", action: { state.selectedTab = "all" }) {
                Text("Tümü").font(t.font(12, .semibold))
            }
            ForEach(Provider.allCases.filter { state.enabled.contains($0) }) { p in
                Pill(t: t, selected: state.selectedTab == p.rawValue, action: { state.selectedTab = p.rawValue }) {
                    BrandBadge(provider: p, size: 16)
                }
            }
            Spacer()
        }
    }
}

struct ConfidenceTag: View {
    let c: Confidence

    var body: some View {
        Text(c.label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(c.color)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(c.color.opacity(0.16), in: Capsule())
    }
}

struct Chip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.16), in: Capsule())
    }
}

/// Kalan oranı çubuk olarak gösterir; biçimi ve kalınlığı temadan gelir. `expected` verilirse tempo işaretini çizer.
struct PaceBar: View {
    @EnvironmentObject var state: AppState
    let left: Double
    var expected: Double?
    var height: CGFloat = 8
    let track: Color

    var body: some View {
        let t = state.theme
        let h = t.barThickness
        GeometryReader { g in
            ZStack(alignment: .leading) {
                barLayer(t: t, h: h, width: g.size.width)
                if let e = expected {
                    Rectangle().fill(t.text.opacity(0.7)).frame(width: 2, height: h + 6)
                        .offset(x: g.size.width * e - 1)
                }
            }
            .frame(height: h + 6)
        }
        .frame(height: h + 6)
    }

    @ViewBuilder private func barLayer(t: Theme, h: CGFloat, width: CGFloat) -> some View {
        switch t.barStyle {
        case .segmented:
            HStack(spacing: 2) {
                ForEach(0..<20, id: \.self) { i in
                    Rectangle().fill(Double(i) / 20 < left ? statusColor(left) : track)
                }
            }
            .frame(height: h)
        case .block:
            ZStack(alignment: .leading) {
                Rectangle().fill(track)
                Rectangle().fill(statusColor(left)).frame(width: max(h, width * left))
            }
            .frame(height: h)
            .overlay(Rectangle().stroke(t.border, lineWidth: t.borderW))
        case .hairline:
            ZStack(alignment: .leading) {
                Rectangle().fill(track)
                Rectangle().fill(statusColor(left)).frame(width: max(2, width * left))
            }
            .frame(height: h)
        case .capsule, .thin:
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(statusColor(left)).frame(width: max(h, width * left))
            }
            .frame(height: h)
        }
    }
}

func resetText(_ r: Date?) -> String {
    guard let r else { return "" }
    return r > Date() ? "Sıfırlanma \(formatRemaining(r))" : "Pencere sıfırlandı"
}

// MARK: Tümü sayfası

struct OverviewCard: View {
    @EnvironmentObject var state: AppState
    let provider: Provider
    let usage: Usage

    var body: some View {
        let t = state.theme
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                BrandBadge(provider: provider, size: 22)
                Text(provider.name).font(t.font(14, .semibold))
                Spacer()
                if let tk = usage.todayTokens {
                    Text("Bugün \(formatTokens(tk))")
                        .font(t.font(11)).foregroundStyle(t.sub)
                }
            }
            if usage.fiveRow != nil || usage.weekRow != nil {
                HStack(alignment: .top, spacing: 14) {
                    if let f = usage.fiveRow { OverviewMetric(title: "5 SAATLİK", row: f, window: 5 * 3600) }
                    if let w = usage.weekRow { OverviewMetric(title: "HAFTALIK", row: w, window: 7 * 86400) }
                }
            }
            ForEach(usage.otherRows) { r in
                OverviewMetric(title: r.title.replacingOccurrences(of: " · günlük kota", with: "").uppercased(), row: r, window: 86400)
            }
            if usage.rows.isEmpty {
                Text("Veri alınamadı. Ayrıntı için Sağlayıcılar sayfasına bak.").font(t.font(10)).foregroundStyle(t.sub)
            }
        }
        .card(t)
    }
}

struct OverviewMetric: View {
    @EnvironmentObject var state: AppState
    let title: String
    let row: LimitRow
    let window: TimeInterval

    var body: some View {
        let t = state.theme
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(t.font(9, .bold)).foregroundStyle(t.sub)
                Spacer()
                Text("\(Int((row.left * 100).rounded()))%").font(t.font(15, .bold).monospacedDigit())
            }
            PaceBar(left: row.left, expected: Pace.of(row, window: window)?.expectedLeft, height: 6, track: t.sub.opacity(0.25))
            Text(resetText(row.reset)).font(t.font(10)).foregroundStyle(t.sub).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Sağlayıcı sayfası

struct MetricCard: View {
    @EnvironmentObject var state: AppState
    let title: String
    let icon: String
    let row: LimitRow
    let window: TimeInterval

    var body: some View {
        let t = state.theme
        let status = statusWord(row.left)
        let pace = Pace.of(row, window: window)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).font(.system(size: 10)).foregroundStyle(t.sub)
                Text(title).font(t.font(9, .bold)).foregroundStyle(t.sub)
                Spacer()
                Chip(text: status.0, color: status.1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int((row.left * 100).rounded()))%").font(t.font(30, .bold).monospacedDigit())
                Text("kaldı").font(t.font(11)).foregroundStyle(t.sub)
            }
            PaceBar(left: row.left, expected: pace?.expectedLeft, track: t.sub.opacity(0.25))
            HStack {
                Text(row.reset.map { $0 > Date() ? formatRemaining($0) : "sıfırlandı" } ?? "")
                    .font(t.font(10, .medium)).foregroundStyle(t.sub)
                Spacer()
                if let p = pace { Chip(text: p.label, color: p.color) }
            }
        }
        .card(t)
        .frame(maxWidth: .infinity)
    }
}

struct DayBars: View {
    let values: [Int]
    let color: Color
    let track: Color

    var body: some View {
        let mx = max(1, values.max() ?? 1)
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i == values.count - 1 ? color : color.opacity(0.45))
                    .frame(height: max(3, 34 * CGFloat(v) / CGFloat(mx)))
                    .frame(maxWidth: .infinity)
                    .background(track.opacity(0), in: Rectangle())
            }
        }
        .frame(height: 34)
    }
}

struct ProviderDetail: View {
    @EnvironmentObject var state: AppState
    let provider: Provider
    let usage: Usage

    var body: some View {
        let t = state.theme
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                BrandBadge(provider: provider, size: 26)
                Text(provider.name).font(t.font(17, .bold))
                Spacer()
            }

            if usage.rows.isEmpty {
                Text(usage.notes.first ?? "Veri alınamadı.")
                    .font(t.font(12)).foregroundStyle(t.sub)
                    .fixedSize(horizontal: false, vertical: true)
                    .card(t)
            }
            if usage.fiveRow != nil || usage.weekRow != nil {
                HStack(alignment: .top, spacing: 10) {
                    if let f = usage.fiveRow { MetricCard(title: "5 SAATLİK", icon: "bolt.fill", row: f, window: 5 * 3600) }
                    if let w = usage.weekRow { MetricCard(title: "HAFTALIK", icon: "calendar", row: w, window: 7 * 86400) }
                }
            }

            if usage.extra.count > 2 || !usage.otherRows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(usage.otherRows.isEmpty ? "HAVUZLAR" : "KOTALAR").font(t.font(9, .bold)).foregroundStyle(t.sub)
                    ForEach(usage.extra) { r in
                        LimitBar(title: r.title, left: r.left, reset: r.reset, estimate: false)
                    }
                }
                .card(t)
            }

            if let tk = usage.todayTokens {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("TOKEN").font(t.font(9, .bold)).foregroundStyle(t.sub)
                        Spacer()
                        Text("Son 7 gün").font(t.font(10)).foregroundStyle(t.sub)
                    }
                    HStack(alignment: .bottom, spacing: 14) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(formatTokens(tk)).font(t.font(24, .bold).monospacedDigit())
                            Text("bugün").font(t.font(10)).foregroundStyle(t.sub)
                        }
                        DayBars(values: state.daily[provider] ?? [], color: provider.brandColor, track: t.sub)
                    }
                }
                .card(t)
            }

        }
    }
}

struct LimitBar: View {
    @EnvironmentObject var state: AppState
    let title: String
    let left: Double
    let reset: Date?
    let estimate: Bool

    var body: some View {
        let t = state.theme
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(title).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(estimate ? "~" : "")\(Int((left * 100).rounded()))%").monospacedDigit().foregroundStyle(t.text)
                if let r = reset {
                    Text(r > Date() ? "· \(formatRemaining(r))" : "· sıfırlandı").lineLimit(1).fixedSize()
                }
            }
            .font(t.font(11)).foregroundStyle(t.sub)
            PaceBar(left: left, height: 4, track: t.sub.opacity(0.25))
        }
    }
}

func formatTokens(_ n: Int) -> String {
    switch n {
    case 1_000_000_000...: String(format: "%.1fB", Double(n) / 1_000_000_000)
    case 1_000_000...: String(format: "%.1fM", Double(n) / 1_000_000)
    case 1_000...: "\(n / 1_000)K"
    default: "\(n)"
    }
}


/// Menü çubuğu penceresini istenen yüksekliğe getirir. SwiftUI içerik küçülünce pencereyi kendiliğinden küçültmediği için
/// (arada şeffaf boşluk kalıyordu) çerçeve doğrudan ayarlanır; üst kenar sabit kalır.
struct WindowFitter: NSViewRepresentable {
    let height: CGFloat

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let h = height
        DispatchQueue.main.async {
            guard let w = view.window else { return }
            let extra = w.frame.height - w.contentLayoutRect.height
            let newH = h + extra
            guard abs(w.frame.height - newH) > 1 else { return }
            var f = w.frame
            f.origin.y += f.height - newH
            f.size.height = newH
            w.setFrame(f, display: true)
        }
    }
}
