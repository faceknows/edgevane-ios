import SwiftUI

struct SymbolRowLayout<Leading: View, Trailing: View>: View {
    var leading: Leading
    var trailing: Trailing

    init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                leading
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                trailing
            }
        }
        .padding(.vertical, 4)
    }
}

struct SymbolRow: View {
    var summary: SymbolSummary

    var body: some View {
        SymbolRowLayout {
            Text(summary.symbol)
                .font(.headline)
            IndicatorChips(summary: summary)
        } trailing: {
            Text(MarketFormat.price(summary.lastPrice))
                .font(.headline.monospacedDigit())
            ChangePercentText(percent: summary.changePercent)
        }
    }
}
