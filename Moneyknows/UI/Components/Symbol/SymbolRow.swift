import SwiftUI

struct SymbolRow: View {
    var summary: SymbolSummary

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.symbol)
                    .font(.headline)
                IndicatorChips(summary: summary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(MarketFormat.price(summary.lastPrice))
                    .font(.headline.monospacedDigit())
                ChangePercentText(percent: summary.changePercent)
            }
        }
        .padding(.vertical, 4)
    }
}
