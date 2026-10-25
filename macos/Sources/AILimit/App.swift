import SwiftUI

@main
struct AILimitApp: App {
    @StateObject private var state = AppState()

    init() {
        // Uygulama yeni bir konuma taşınınca "girişte başlat" kaydını yeniden yapar.
        if ProcessInfo.processInfo.environment["AILIMIT_LOGIN_ON"] != nil { _ = LoginItem.set(true) }
        if ProcessInfo.processInfo.environment["AILIMIT_DUMP"] != nil {
            let st = AppState()
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
                for p in Provider.allCases {
                    let u = st.usage[p]!
                    print("== \(p.name) limit:\(u.limitConfidence.label) token:\(u.tokenConfidence.label)")
                    for r in u.rows { print("  row: \(r.title) left=\(String(format: "%.3f", r.left)) reset=\(r.reset.map { "\($0)" } ?? "-")") }
                    print("  today: \(u.todayTokens.map { String($0) } ?? "-")")
                    for n in u.notes { print("  - \(n)") }
                }
                fflush(stdout)
                exit(0)
            }
        }
        // Her temanın popover'ını ayrı PNG olarak çizer (kontrol için).
        if let dir = ProcessInfo.processInfo.environment["AILIMIT_THEMES"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 35) { MainActor.assumeIsolated {
                let st = AppState()
                PopoverView.snapshot = true
                // Önizlemede örnek değerler: yalnızca görünümü kontrol etmek için.
                for (i, p) in Provider.allCases.enumerated() {
                    var u = Usage(fiveHourLeft: 0.77 - Double(i) * 0.12, weeklyLeft: 0.48 + Double(i) * 0.1, limitConfidence: .exact)
                    u.todayTokens = 1_000_000
                    u.fiveHourReset = Date().addingTimeInterval(4 * 3600)
                    u.weeklyReset = Date().addingTimeInterval(5 * 86400)
                    st.usage[p] = u
                }
                st.enabled = Set(Provider.allCases)
                st.selectedTab = "all"
                for th in Theme.all {
                    st.themeId = th.id
                    let r = ImageRenderer(content: PopoverView().environmentObject(st))
                    r.scale = 1
                    if let img = r.nsImage, let tiff = img.tiffRepresentation,
                       let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("theme_\(th.id).png"))
                    }
                    let lr = ImageRenderer(content: MenuBarLabel(forceDark: true).environmentObject(st).padding(10).background(Color(white: 0.15)))
                    lr.scale = 2
                    if let img = lr.nsImage, let tiff = img.tiffRepresentation,
                       let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("bar_\(th.id).png"))
                    }
                }
                // Her temanın onay kutusu, kapalı ve açık.
                let checks = VStack(alignment: .leading, spacing: 10) {
                    ForEach(Theme.all) { th in
                        HStack(spacing: 30) {
                            ThemedCheck(t: th, title: th.name + " · Cache dahil", isOn: .constant(false))
                            ThemedCheck(t: th, title: th.name + " · Cache dahil", isOn: .constant(true))
                        }
                        .padding(10).frame(width: 440, alignment: .leading).background(th.bg)
                        .environment(\.colorScheme, th.scheme ?? .dark)
                    }
                }
                let segs = VStack(alignment: .leading, spacing: 10) {
                    ForEach(Theme.all) { th in
                        HStack(spacing: 24) {
                            ThemedSegmented(t: th, items: [("24 saat", 0), ("7 gün", 1), ("30 gün", 2)], selection: .constant(1))
                            ThemedSegmented(t: th, items: [("Sistem", 0), ("Türkçe", 1), ("English", 2)], selection: .constant(0))
                        }
                        .padding(10).frame(width: 560, alignment: .leading).background(th.bg)
                        .environment(\.colorScheme, th.scheme ?? .dark)
                    }
                }
                if let img = ImageRenderer(content: segs.padding(12).background(Color(white: 0.5))).nsImage, let tiff = img.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("segs.png"))
                }
                let cr = ImageRenderer(content: checks.padding(12).background(Color(white: 0.5)))
                cr.scale = 2
                if let img = cr.nsImage, let tiff = img.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("checks.png"))
                }
                exit(0)
            } }
        }
        // Tüm tema logolarını yan yana çizer (kontrol için).
        if let path = ProcessInfo.processInfo.environment["AILIMIT_LOGOS"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { MainActor.assumeIsolated {
                let v = HStack(spacing: 16) {
                    ForEach(Theme.all) { th in
                        VStack(spacing: 6) {
                            LogoMark(size: 220, palette: th.logo)
                            Text(th.name).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                        }
                    }
                }
                .padding(24).background(Color(white: 0.12))
                let r = ImageRenderer(content: v)
                r.scale = 1
                if let img = r.nsImage, let tiff = img.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path))
                }
                exit(0)
            } }
        }
        // İkon modu: logoyu 1024x1024 saydam tuvale (macOS ikon ölçüleri: 824 px kare) çizip çıkar.
        if let path = ProcessInfo.processInfo.environment["AILIMIT_ICON"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { MainActor.assumeIsolated {
                let v = LogoMark(size: 824).frame(width: 1024, height: 1024)
                let r = ImageRenderer(content: v)
                r.scale = 1
                if let img = r.nsImage, let tiff = img.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path))
                }
                exit(0)
            } }
        }
        // Test modu: görünümleri PNG'ye çizer. Veri gelsin diye görünümler geç oluşturulur.
        if let dir = ProcessInfo.processInfo.environment["AILIMIT_SNAPSHOT"] {
            let st = AppState()
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { MainActor.assumeIsolated {
                @MainActor func save<V: View>(_ v: V, _ name: String) {
                    let r = ImageRenderer(content: v.background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark))
                    r.scale = 2
                    if let img = r.nsImage, let tiff = img.tiffRepresentation,
                       let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
                    }
                }
                let origEnabled = st.enabled, origTab = st.selectedTab
                st.enabled = Set(Provider.allCases)
                st.selectedTab = "all"
                save(PopoverView().environmentObject(st), "popover_all.png")
                for p in [Provider.claude, .antigravity] {
                    st.selectedTab = p.rawValue
                    save(PopoverView().environmentObject(st), "popover_\(p.rawValue).png")
                }
                save(MenuBarLabel(forceDark: true).environmentObject(st).padding(8), "menubar.png")
                save(ShareCard(data: ShareData.load(), theme: st.theme), "share_card.png")
                save(SetupCheckCard().environmentObject(st).frame(width: 700).padding(16), "setup_check.png")
                save(HistoryPage().environmentObject(st).frame(width: 720).padding(24), "history_page.png")
                for pg in ["history", "menubar", "appearance"] {
                    st.dashPage = pg
                    save(DashboardView().environmentObject(st).frame(width: 980, height: 760), "dash_\(pg).png")
                }
                st.enabled = origEnabled
                st.selectedTab = origTab
                exit(0)
            } }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView().environmentObject(state)
        } label: {
            MenuBarLabel().environmentObject(state)
        }
        .menuBarExtraStyle(.window)
    }
}
