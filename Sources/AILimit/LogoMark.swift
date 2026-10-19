import SwiftUI

/// Ullage logosu. Kap aynı zamanda ismin baş harfi olan "U": camsı bir U kabı. Sıvı kalan limiti, içinde yükselen
/// baloncuklar token'ları, üstteki kesikli turuncu parantezin kapsadığı boş hacim (ullage) harcananı gösterir.
/// Sağdaki çentikler ölçü cetvelidir. Renkler `LogoPalette` ile temaya göre değişir.
private struct UOutline: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let R = r.width / 2
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - R))
        p.addArc(center: CGPoint(x: r.midX, y: r.maxY - R), radius: R, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}

private struct UFill: Shape {
    func path(in r: CGRect) -> Path {
        var p = UOutline().path(in: r)
        p.closeSubpath()
        return p
    }
}

struct LogoMark: View {
    var size: CGFloat = 256
    var palette: LogoPalette = .system
    /// Kabın doluluk oranı (kalan limit).
    var level: Double = 0.64

    var body: some View {
        let s = size
        let pal = palette
        let bodyW = s * 0.34, bodyH = s * 0.58
        // Sağdaki cetvel soldaki parantezden geniş olduğu için gövde biraz sola kaydırılır.
        let x0 = s * 0.5 - bodyW / 2 - s * 0.030, y0 = s * 0.20
        let surfaceY = y0 + bodyH * (1 - level)
        let liquidH = bodyH * level
        let rightX = x0 + bodyW
        let thick = pal.outline != nil
        let glassW = thick ? s * 0.028 : s * 0.017
        let corner = s * 0.225

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(colors: [pal.bg1, pal.bg2], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(RadialGradient(colors: [pal.glow.opacity(0.20), .clear], center: UnitPoint(x: 0.5, y: 0.62), startRadius: 0, endRadius: s * 0.45))
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(pal.outline ?? Color.white.opacity(0.10), lineWidth: thick ? s * 0.03 : max(1, s * 0.006))

            // Üstte boş hacim (ullage): kesikli ince çizgiler
            ForEach(0..<2, id: \.self) { i in
                let y = y0 + s * 0.07 + CGFloat(i) * (surfaceY - y0 - s * 0.10) / 1.6
                Path { p in p.move(to: CGPoint(x: x0 + bodyW * 0.18, y: y)); p.addLine(to: CGPoint(x: x0 + bodyW * 0.82, y: y)) }
                    .stroke(pal.bracket.opacity(0.40), style: StrokeStyle(lineWidth: s * 0.010, lineCap: .round, dash: [s * 0.018, s * 0.022]))
            }

            // Sıvı (U biçimine kırpılı) ve baloncuklar
            ZStack(alignment: .topLeading) {
                UFill()
                    .fill(LinearGradient(colors: [pal.liquid1, pal.liquid2], startPoint: .top, endPoint: .bottom))
                    .frame(width: bodyW, height: bodyH)
                    .mask(
                        Rectangle().frame(width: bodyW, height: liquidH + 2)
                            .offset(y: bodyH - liquidH)
                            .frame(width: bodyW, height: bodyH, alignment: .topLeading)
                    )
                ForEach(Array([(0.30, 0.22, 0.020), (0.64, 0.46, 0.028), (0.42, 0.68, 0.016), (0.72, 0.20, 0.013), (0.28, 0.58, 0.012)].enumerated()), id: \.offset) { _, b in
                    let cx = bodyW * b.0
                    let cy = (bodyH - liquidH) + liquidH * b.1
                    Circle().fill(Color.white.opacity(0.32))
                        .overlay(Circle().stroke(thick ? Color.black : Color.white.opacity(0.65), lineWidth: thick ? s * 0.008 : s * 0.005))
                        .frame(width: s * b.2 * 2, height: s * b.2 * 2)
                        .position(x: cx, y: cy)
                }
            }
            .frame(width: bodyW, height: bodyH, alignment: .topLeading)
            .offset(x: x0, y: y0)
            .shadow(color: pal.glow.opacity(0.35), radius: s * 0.03)

            // Sıvı yüzeyi çizgisi
            Capsule().fill(thick ? Color.black : Color.white.opacity(0.80))
                .frame(width: bodyW * 0.84, height: thick ? s * 0.014 : s * 0.010)
                .offset(x: x0 + bodyW * 0.08, y: surfaceY - s * 0.005)

            // U gövdesi (cam) ve yansıma
            UOutline()
                .stroke(pal.glass, style: StrokeStyle(lineWidth: glassW, lineCap: .round, lineJoin: .round))
                .frame(width: bodyW, height: bodyH)
                .offset(x: x0, y: y0)
            RoundedRectangle(cornerRadius: s * 0.01)
                .fill(pal.glass.opacity(0.20))
                .frame(width: s * 0.014, height: bodyH * 0.46)
                .offset(x: x0 + s * 0.038, y: y0 + bodyH * 0.10)

            // Harf kulakçıkları: U'nun iki kolunun ucundaki yatay çıkıntılar
            ForEach(0..<2, id: \.self) { i in
                Capsule().fill(pal.glass)
                    .frame(width: s * 0.065, height: glassW)
                    .offset(x: i == 0 ? x0 - s * 0.050 : rightX - s * 0.015, y: y0 - glassW / 2)
            }

            // Sağda ölçü çentikleri: yüzeyin altındakiler parlak, üstündekiler soluk
            ForEach(0..<11, id: \.self) { i in
                let f = CGFloat(i) / 10
                let y = y0 + bodyH * 0.06 + (bodyH * 0.78) * f
                let long = i % 5 == 0
                Capsule()
                    .fill(y >= surfaceY ? pal.glass : pal.glass.opacity(0.25))
                    .frame(width: long ? s * 0.072 : s * 0.042, height: s * 0.011)
                    .offset(x: rightX + s * 0.040, y: y - s * 0.0055)
            }

            // Solda ullage parantezi: üstteki boş hacmi kapsar
            Path { p in
                let bx = x0 - s * 0.060
                p.move(to: CGPoint(x: bx + s * 0.024, y: y0 + s * 0.035))
                p.addLine(to: CGPoint(x: bx, y: y0 + s * 0.035))
                p.addLine(to: CGPoint(x: bx, y: surfaceY))
                p.addLine(to: CGPoint(x: bx + s * 0.024, y: surfaceY))
            }
            .stroke(pal.bracket, style: StrokeStyle(lineWidth: s * 0.017, lineCap: .round, lineJoin: .round, dash: [s * 0.022, s * 0.026]))
        }
        .frame(width: s, height: s)
    }
}
