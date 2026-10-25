import SwiftUI

// MARK: - Logo paleti

/// Logonun temaya göre değişen renkleri.
struct LogoPalette {
    var bg1: Color, bg2: Color
    var liquid1: Color, liquid2: Color
    var glass: Color
    var bracket: Color
    var glow: Color
    var outline: Color? = nil

    static let system = LogoPalette(
        bg1: Color(red: 0.16, green: 0.19, blue: 0.31), bg2: Color(red: 0.04, green: 0.05, blue: 0.10),
        liquid1: Color(red: 0.30, green: 0.88, blue: 0.62), liquid2: Color(red: 0.10, green: 0.62, blue: 0.78),
        glass: Color.white.opacity(0.85), bracket: Color(red: 0.98, green: 0.62, blue: 0.27),
        glow: Color(red: 0.30, green: 0.88, blue: 0.62))
    static let dark = LogoPalette(
        bg1: Color(red: 0.22, green: 0.15, blue: 0.38), bg2: Color(red: 0.06, green: 0.04, blue: 0.14),
        liquid1: Color(red: 0.74, green: 0.58, blue: 1.0), liquid2: Color(red: 0.34, green: 0.34, blue: 0.95),
        glass: Color.white.opacity(0.85), bracket: Color(red: 1.0, green: 0.45, blue: 0.70),
        glow: Color(red: 0.62, green: 0.45, blue: 1.0))
    static let light = LogoPalette(
        bg1: Color(red: 1.0, green: 0.97, blue: 0.92), bg2: Color(red: 0.96, green: 0.89, blue: 0.80),
        liquid1: Color(red: 1.0, green: 0.70, blue: 0.36), liquid2: Color(red: 0.93, green: 0.38, blue: 0.30),
        glass: Color(red: 0.18, green: 0.16, blue: 0.22).opacity(0.9), bracket: Color(red: 0.20, green: 0.20, blue: 0.28),
        glow: Color(red: 1.0, green: 0.62, blue: 0.30))
    static let terminal = LogoPalette(
        bg1: Color(red: 0.02, green: 0.09, blue: 0.03), bg2: .black,
        liquid1: Color(red: 0.45, green: 1.0, blue: 0.55), liquid2: Color(red: 0.10, green: 0.60, blue: 0.25),
        glass: Color(red: 0.45, green: 1.0, blue: 0.55).opacity(0.9), bracket: Color(red: 0.30, green: 0.75, blue: 0.40),
        glow: Color(red: 0.2, green: 0.9, blue: 0.35))
    static let sticker = LogoPalette(
        bg1: Color(red: 0.92, green: 0.98, blue: 0.94), bg2: Color(red: 0.76, green: 0.92, blue: 0.84),
        liquid1: Color(red: 1.0, green: 0.86, blue: 0.28), liquid2: Color(red: 0.30, green: 0.84, blue: 0.55),
        glass: .black, bracket: Color(red: 1.0, green: 0.33, blue: 0.55),
        glow: .clear, outline: .black)
}

extension LogoPalette {
    static let paper = LogoPalette(
        bg1: Color(red: 0.98, green: 0.95, blue: 0.87), bg2: Color(red: 0.91, green: 0.85, blue: 0.72),
        liquid1: Color(red: 0.86, green: 0.58, blue: 0.32), liquid2: Color(red: 0.62, green: 0.35, blue: 0.18),
        glass: Color(red: 0.25, green: 0.18, blue: 0.10).opacity(0.9), bracket: Color(red: 0.42, green: 0.28, blue: 0.14),
        glow: Color(red: 0.80, green: 0.55, blue: 0.30))
    static let neon = LogoPalette(
        bg1: Color(red: 0.06, green: 0.02, blue: 0.14), bg2: Color(red: 0.01, green: 0.01, blue: 0.03),
        liquid1: Color(red: 1.0, green: 0.25, blue: 0.80), liquid2: Color(red: 0.20, green: 0.95, blue: 1.0),
        glass: Color.white.opacity(0.9), bracket: Color(red: 1.0, green: 0.25, blue: 0.80),
        glow: Color(red: 0.20, green: 0.95, blue: 1.0))
    static let brutal = LogoPalette(
        bg1: Color(red: 1.0, green: 0.90, blue: 0.20), bg2: Color(red: 1.0, green: 0.90, blue: 0.20),
        liquid1: Color(red: 1.0, green: 0.35, blue: 0.35), liquid2: Color(red: 0.90, green: 0.20, blue: 0.20),
        glass: .black, bracket: .black, glow: .clear, outline: .black)
    static let glass = LogoPalette(
        bg1: Color(red: 0.30, green: 0.50, blue: 0.78), bg2: Color(red: 0.07, green: 0.14, blue: 0.26),
        liquid1: Color(red: 0.70, green: 0.92, blue: 1.0), liquid2: Color(red: 0.30, green: 0.60, blue: 1.0),
        glass: Color.white.opacity(0.9), bracket: Color(red: 0.75, green: 0.92, blue: 1.0),
        glow: Color(red: 0.50, green: 0.85, blue: 1.0))
}

// MARK: - Tema

/// Bar çizim biçimi: her temanın kendi ölçü dili var.
enum BarStyle { case capsule, thin, segmented, block, hairline }

struct Theme: Identifiable {
    let id: String
    let name: String
    let scheme: ColorScheme?
    let bg: Color
    let card: Color
    let text: Color
    let sub: Color
    let border: Color
    let borderW: CGFloat
    let radius: CGFloat
    let design: Font.Design
    let accent: Color
    var logo: LogoPalette = .system
    /// Bu tema seçilince menü çubuğu göstergelerinin varsayılan tipi.
    var menuStyle: MetricStyle = .percent
    /// Limit çubuklarının biçimi.
    var barStyle: BarStyle = .capsule
    /// Çubuk kalınlığı (pt).
    var barThickness: CGFloat = 6
    /// Sekme ve düğme köşe yarıçapı (büyük değer = hap şekli).
    var pillRadius: CGFloat = 999

    func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: design)
    }

    static let system = Theme(
        id: "system", name: "Sistem", scheme: nil,
        bg: Color(nsColor: .windowBackgroundColor), card: Color.primary.opacity(0.06),
        text: .primary, sub: .secondary, border: .clear, borderW: 0, radius: 14,
        design: .default, accent: Color(red: 0.35, green: 0.5, blue: 1),
        logo: .system, menuStyle: .percent, barStyle: .capsule, barThickness: 6, pillRadius: 999
    )
    static let dark = Theme(
        id: "dark", name: "Koyu", scheme: .dark,
        bg: Color(red: 0.08, green: 0.08, blue: 0.10), card: Color(red: 0.14, green: 0.14, blue: 0.17),
        text: .white, sub: Color(white: 0.62), border: Color.white.opacity(0.08), borderW: 1, radius: 14,
        design: .default, accent: Color(red: 0.55, green: 0.45, blue: 1),
        logo: .dark, menuStyle: .barPercent, barStyle: .capsule, barThickness: 8, pillRadius: 999
    )
    static let light = Theme(
        id: "light", name: "Açık", scheme: .light,
        bg: Color(red: 0.97, green: 0.96, blue: 0.94), card: .white,
        text: Color(white: 0.1), sub: Color(white: 0.42), border: Color.black.opacity(0.06), borderW: 0, radius: 22,
        design: .default, accent: Color(red: 0.85, green: 0.45, blue: 0.3),
        logo: .light, menuStyle: .ring, barStyle: .thin, barThickness: 3, pillRadius: 999
    )
    static let terminal = Theme(
        id: "terminal", name: "Terminal", scheme: .dark,
        bg: .black, card: Color(red: 0.03, green: 0.07, blue: 0.04),
        text: Color(red: 0.4, green: 1, blue: 0.5), sub: Color(red: 0.28, green: 0.62, blue: 0.34),
        border: Color(red: 0.2, green: 0.6, blue: 0.3).opacity(0.6), borderW: 1, radius: 3,
        design: .monospaced, accent: Color(red: 0.4, green: 1, blue: 0.5),
        logo: .terminal, menuStyle: .segments, barStyle: .segmented, barThickness: 10, pillRadius: 2
    )
    static let sticker = Theme(
        id: "sticker", name: "Sticker", scheme: .light,
        bg: Color(red: 0.90, green: 0.97, blue: 0.93), card: .white,
        text: .black, sub: Color(white: 0.35), border: .black, borderW: 2, radius: 16,
        design: .rounded, accent: Color(red: 0.1, green: 0.6, blue: 0.5),
        logo: .sticker, menuStyle: .battery, barStyle: .block, barThickness: 10, pillRadius: 12
    )
    static let paper = Theme(
        id: "paper", name: "Kağıt", scheme: .light,
        bg: Color(red: 0.97, green: 0.94, blue: 0.86), card: Color(red: 0.99, green: 0.97, blue: 0.91),
        text: Color(red: 0.20, green: 0.16, blue: 0.11), sub: Color(red: 0.48, green: 0.42, blue: 0.33),
        border: Color(red: 0.20, green: 0.16, blue: 0.11).opacity(0.25), borderW: 0.8, radius: 4,
        design: .serif, accent: Color(red: 0.56, green: 0.36, blue: 0.20),
        logo: .paper, menuStyle: .percent, barStyle: .hairline, barThickness: 2, pillRadius: 4
    )
    static let neon = Theme(
        id: "neon", name: "Neon", scheme: .dark,
        bg: Color(red: 0.02, green: 0.02, blue: 0.05), card: Color(red: 0.07, green: 0.07, blue: 0.13),
        text: Color(red: 0.92, green: 0.98, blue: 1), sub: Color(red: 0.50, green: 0.66, blue: 0.78),
        border: Color(red: 1.0, green: 0.25, blue: 0.80).opacity(0.7), borderW: 1, radius: 18,
        design: .default, accent: Color(red: 0.20, green: 0.95, blue: 1.0),
        logo: .neon, menuStyle: .barPercent, barStyle: .thin, barThickness: 3, pillRadius: 999
    )
    static let brutal = Theme(
        id: "brutal", name: "Brutal", scheme: .light,
        bg: Color(red: 1.0, green: 0.90, blue: 0.20), card: .white,
        text: .black, sub: Color(white: 0.25), border: .black, borderW: 3, radius: 0,
        design: .default, accent: Color(red: 1.0, green: 0.30, blue: 0.30),
        logo: .brutal, menuStyle: .bar, barStyle: .block, barThickness: 12, pillRadius: 0
    )
    static let glass = Theme(
        id: "glass", name: "Cam", scheme: .dark,
        bg: Color(red: 0.07, green: 0.14, blue: 0.26), card: Color.white.opacity(0.08),
        text: .white, sub: Color.white.opacity(0.62), border: Color.white.opacity(0.22), borderW: 1, radius: 22,
        design: .rounded, accent: Color(red: 0.55, green: 0.85, blue: 1.0),
        logo: .glass, menuStyle: .ring, barStyle: .thin, barThickness: 4, pillRadius: 999
    )

    static let all: [Theme] = [.system, .dark, .light, .terminal, .sticker, .paper, .neon, .brutal, .glass]
    static func byId(_ id: String) -> Theme { all.first { $0.id == id } ?? .system }
}

extension View {
    func card(_ t: Theme, padding: CGFloat = 12) -> some View {
        self.padding(padding)
            .background(t.card, in: RoundedRectangle(cornerRadius: t.radius))
            .overlay(RoundedRectangle(cornerRadius: t.radius).stroke(t.border, lineWidth: t.borderW))
    }
}

// MARK: - Menü çubuğu gösterge stilleri

enum MetricStyle: String, CaseIterable, Identifiable {
    case percent, bar, barPercent, ring, dot, battery, segments
    var id: String { rawValue }

    var label: String {
        switch self {
        case .percent: "Yüzde"
        case .bar: "Çubuk"
        case .barPercent: "Çubuk + yüzde"
        case .ring: "Halka"
        case .dot: "Nokta"
        case .battery: "Pil"
        case .segments: "Segment"
        }
    }
}

struct MiniRing: View {
    let left: Double
    var size: CGFloat = 14

    var body: some View {
        ZStack {
            Circle().stroke(Color.gray.opacity(0.35), lineWidth: 2.5)
            Circle().trim(from: 0, to: max(0.02, left))
                .stroke(statusColor(left), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

struct MiniBattery: View {
    let left: Double
    let text: Color

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).stroke(text.opacity(0.55), lineWidth: 1)
                RoundedRectangle(cornerRadius: 2).fill(statusColor(left).opacity(0.85))
                    .frame(width: max(2, 24 * left)).padding(1)
                Text("\(Int((left * 100).rounded()))")
                    .font(.system(size: 8, weight: .bold).monospacedDigit())
                    .foregroundStyle(text).frame(maxWidth: .infinity)
            }
            .frame(width: 26, height: 12)
            RoundedRectangle(cornerRadius: 1).fill(text.opacity(0.55)).frame(width: 2, height: 5)
        }
    }
}

struct MetricGlyph: View {
    @EnvironmentObject var state: AppState
    let left: Double?
    let style: MetricStyle
    let tag: String?
    let text: Color
    var estimate = false
    var tagColor: Color? = nil

    private var pct: String {
        guard let l = left else { return "–" }
        return "\(estimate ? "~" : "")\(Int((l * 100).rounded()))%"
    }

    var body: some View {
        HStack(spacing: 3) {
            if let tag {
                Text(tag).font(.system(size: 9, weight: .bold, design: state.theme.design)).foregroundStyle(tagColor ?? text.opacity(0.55))
            }
            if let l = left {
                switch style {
                case .percent:
                    Text(pct).font(.system(size: 13, weight: .bold, design: state.theme.design).monospacedDigit()).foregroundStyle(text)
                case .bar:
                    MiniBar(left: l, width: 26)
                case .barPercent:
                    MiniBar(left: l, width: 22)
                    Text(pct).font(.system(size: 13, weight: .bold, design: state.theme.design).monospacedDigit()).foregroundStyle(text)
                case .ring:
                    MiniRing(left: l)
                case .dot:
                    Circle().fill(statusColor(l)).frame(width: 8, height: 8)
                case .battery:
                    MiniBattery(left: l, text: text)
                case .segments:
                    HStack(spacing: 1.5) {
                        ForEach(0..<5, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Double(i) < (l * 5).rounded(.up) ? statusColor(l) : text.opacity(0.2))
                                .frame(width: 4, height: 10)
                        }
                    }
                }
            } else {
                Text("–").font(.system(size: 11)).foregroundStyle(text.opacity(0.6))
            }
        }
    }
}

// MARK: - Tempo

struct Pace {
    let label: String
    let color: Color
    /// Pencere süresince beklenen kalan oran (çubuktaki işaret konumu).
    let expectedLeft: Double

    /// Kullanım, geçen süreyle orantılıysa "dengeli"; öndeyse "hızlı", gerideyse "rahat".
    static func of(_ row: LimitRow, window: TimeInterval, now: Date = Date()) -> Pace? {
        guard let reset = row.reset, reset > now else { return nil }
        let remaining = reset.timeIntervalSince(now)
        guard remaining <= window + 60 else { return nil }
        let elapsed = max(0, min(1, 1 - remaining / window))
        let used = 1 - row.left
        let delta = used - elapsed
        let expected = 1 - elapsed
        if row.left <= 0.001 { return Pace(label: "Bitti", color: .red, expectedLeft: expected) }
        if delta > 0.25 { return Pace(label: "Çok hızlı", color: .red, expectedLeft: expected) }
        if delta > 0.1 { return Pace(label: "Hızlı", color: .orange, expectedLeft: expected) }
        if delta < -0.15 { return Pace(label: "Rahat", color: .blue, expectedLeft: expected) }
        return Pace(label: "Dengeli", color: .green, expectedLeft: expected)
    }
}

extension Pace {
    /// Şimdiki harcama hızı sürerse limitin biteceği an; pencere bitmeden dolmayacaksa nil.
    static func exhaustion(_ row: LimitRow, window: TimeInterval, now: Date = Date()) -> Date? {
        guard let reset = row.reset, reset > now, row.left > 0.001 else { return nil }
        let remaining = reset.timeIntervalSince(now)
        guard remaining <= window + 60 else { return nil }
        let elapsed = window - remaining
        let used = 1 - row.left
        guard elapsed / window >= 0.08, used >= 0.03 else { return nil }
        let eta = row.left / (used / elapsed)
        let at = now.addingTimeInterval(eta)
        return at < reset.addingTimeInterval(-60) ? at : nil
    }
}

func statusWord(_ left: Double) -> (String, Color) {
    if left > 0.4 { return ("Sağlıklı", .green) }
    if left > 0.15 { return ("Dikkat", .orange) }
    return ("Kritik", .red)
}
