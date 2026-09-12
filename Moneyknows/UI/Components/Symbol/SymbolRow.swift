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
    var accessory: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(summary.symbol)
                .font(.headline.weight(.bold))
            Text(MarketFormat.price(summary.lastPrice))
                .font(.headline.monospacedDigit())
            ChangePercentText(
                percent: summary.changePercent,
                font: .subheadline.weight(.semibold).monospacedDigit()
            )
            if let volume = summary.volume, volume.isFinite {
                Text(MarketFormat.compact(volume))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundColor(.secondary)
            }
            if let accessory {
                Text(accessory)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
    }
}
