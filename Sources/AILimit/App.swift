import SwiftUI

@main
struct AILimitApp: App {
    @StateObject private var state = AppState()

    init() {
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
