import Foundation

struct SymbolSummary: Equatable, Identifiable {
    var symbol: String
    var lastPrice: Double?
    var previousClose: Double?
    var volume: Double?
    var rsi: Double?
    var adx: Double?
    var atr: Double?

    var id: String { symbol }

    init(
        symbol: String,
        lastPrice: Double? = nil,
        previousClose: Double? = nil,
        volume: Double? = nil,
        rsi: Double? = nil,
        adx: Double? = nil,
        atr: Double? = nil
    ) {
        self.symbol = SymbolCode.normalize(symbol)
        self.lastPrice = lastPrice
        self.previousClose = previousClose
        self.volume = volume
        self.rsi = rsi
        self.adx = adx
        self.atr = atr
    }

    init(dto: SymbolSummaryDTO) {
        self.init(
            symbol: dto.symbol,
            lastPrice: dto.snapshot?.currentPrice ?? dto.snapshot?.dailyBar?.c,
            previousClose: dto.snapshot?.prevDailyBar?.c,
            volume: dto.snapshot?.dailyBar?.v,
            rsi: dto.indicators?.rsi,
            adx: dto.indicators?.adx,
            atr: dto.indicators?.atr
        )
    }

    var changePercent: Double? {
        guard let lastPrice, let previousClose, previousClose != 0 else { return nil }
        return (lastPrice - previousClose) / previousClose * 100
    }
}

enum SymbolCode {
    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    static func isValid(_ symbol: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        return !symbol.isEmpty
            && symbol.count <= 12
            && symbol.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
