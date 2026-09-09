import SwiftUI

struct SymbolNavigationTitle: View {
    var symbol: String
    var changePercent: Double?
    var volume: Double?

    var body: some View {
        HStack(spacing: 6) {
            Text(symbol)
                .font(.headline.bold())
            ChangePercentText(
                percent: changePercent,
                font: .subheadline.weight(.semibold).monospacedDigit()
            )
            if let volume, volume.isFinite {
                Text(MarketFormat.compact(volume))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.65)
        .accessibilityElement(children: .combine)
    }
}
