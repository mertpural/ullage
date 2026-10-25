import Foundation

/// Token kullanımının API fiyatıyla karşılığı. Fiyatlar üçüncü taraf listelerden alınmış yaklaşık değerlerdir
/// (milyon token başına dolar); abonelik ücretini göstermez, sadece "API'den alsaydın" karşılaştırması içindir.
enum Pricing {
    struct Rate { let input, output, cacheWrite, cacheRead: Double }

    static func rate(_ model: String) -> Rate? {
        let m = model.lowercased()
        // Claude (Antigravity içindeki Claude modelleri de dahil)
        if m.contains("opus") { return Rate(input: 4, output: 20, cacheWrite: 5, cacheRead: 0.2) }
        if m.contains("sonnet") { return Rate(input: 2, output: 10, cacheWrite: 2.5, cacheRead: 0.1) }
        if m.contains("haiku") { return Rate(input: 0.1, output: 0.5, cacheWrite: 0.125, cacheRead: 0.01) }
        // OpenAI / Codex
        if m.contains("astra") { return Rate(input: 10, output: 50, cacheWrite: 12.5, cacheRead: 1) }
        if m.contains("luna") { return Rate(input: 0.2, output: 1, cacheWrite: 0.2, cacheRead: 0.02) }
        if m.contains("sol") || m.contains("terra") || m.hasPrefix("gpt") || m.contains("codex") {
            return Rate(input: 2, output: 10, cacheWrite: 2, cacheRead: 0.2)
        }
        // Gemini
        if m.contains("gemini") { return Rate(input: 0.3, output: 2.5, cacheWrite: 0.3, cacheRead: 0.03) }
        return nil
    }

    static func cost(model: String, _ s: TokenSums) -> Double {
        guard let r = rate(model) else { return 0 }
        return (Double(s.input) * r.input + Double(s.output) * r.output
                + Double(s.cacheWrite) * r.cacheWrite + Double(s.cacheRead) * r.cacheRead) / 1_000_000
    }

    static func format(_ usd: Double) -> String {
        usd >= 100 ? String(format: "$%.0f", usd) : String(format: "$%.2f", usd)
    }
}
