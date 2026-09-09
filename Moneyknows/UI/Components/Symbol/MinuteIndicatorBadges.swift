import SwiftUI

struct MinuteIndicatorBadges: View {
    var snapshot: MinuteIndicatorSnapshot
    var period: Int = MinuteIndicators.period

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 96), spacing: 8, alignment: .leading)],
            alignment: .leading,
            spacing: 8
        ) {
            pill(
                L10n.Detail.rsiPeriod(period),
                MarketFormat.fixed(snapshot.rsi, digits: 2)
            )
            pill(
                L10n.Detail.adxPeriod(period),
                MarketFormat.fixed(snapshot.adx, digits: 2)
            )
            pill(
                L10n.Detail.plusDI,
                MarketFormat.fixed(snapshot.plusDI, digits: 2),
                valueColor: .green
            )
            pill(
                L10n.Detail.minusDI,
                MarketFormat.fixed(snapshot.minusDI, digits: 2),
                valueColor: .red
            )
            pill(
                L10n.Detail.atrPeriod(period),
                MarketFormat.fixed(snapshot.atr, digits: 3)
            )
            pill(
                L10n.Detail.atrPct,
                MarketFormat.fixed(snapshot.atrPct, digits: 3)
            )
        }
        .padding(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(uiColor: .separator), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.Detail.indicators)
    }

    private func pill(_ label: String, _ value: String, valueColor: Color = .primary) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundColor(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .foregroundColor(valueColor)
                .monospacedDigit()
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .overlay(
            Capsule()
                .stroke(Color(uiColor: .separator), lineWidth: 1)
        )
    }
}
