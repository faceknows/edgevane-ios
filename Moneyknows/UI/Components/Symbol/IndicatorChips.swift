import SwiftUI

struct IndicatorChips: View {
    var summary: SymbolSummary

    var body: some View {
        HStack(spacing: 8) {
            if let rsi = summary.rsi {
                Text(L10n.Market.rsiValue(MarketFormat.compact(rsi)))
            }
            if let adx = summary.adx {
                Text(L10n.Market.adxValue(MarketFormat.compact(adx)))
            }
            if let atr = summary.atr {
                Text(L10n.Market.atrValue(MarketFormat.price(atr)))
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }
}
