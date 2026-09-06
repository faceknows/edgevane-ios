import SwiftUI

struct ChartChrome: View {
    @Binding var interval: MinuteInterval
    @Binding var style: ChartStyle
    @Binding var showVWAP: Bool
    var showsVWAPToggle = true

    var body: some View {
        HStack(spacing: 8) {
            Picker(L10n.Chart.interval, selection: $interval) {
                ForEach(MinuteInterval.allCases) { item in
                    Text(item.chromeTitle).tag(item)
                }
            }
            .pickerStyle(.segmented)

            styleButton
            vwapButton
        }
    }
}

struct SecondChartChrome: View {
    @Binding var interval: SecondInterval
    @Binding var style: ChartStyle

    var body: some View {
        HStack(spacing: 8) {
            Picker(L10n.Chart.interval, selection: $interval) {
                ForEach(SecondInterval.allCases) { item in
                    Text(item.chromeTitle).tag(item)
                }
            }
            .pickerStyle(.segmented)

            Button(style == .candle ? L10n.Chart.line : L10n.Chart.candle) {
                style = style == .candle ? .line : .candle
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(AppTheme.fieldCorner)
        }
    }
}

private extension ChartChrome {
    var styleButton: some View {
        Button(style == .candle ? L10n.Chart.line : L10n.Chart.candle) {
            style = style == .candle ? .line : .candle
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(AppTheme.fieldCorner)
    }

    var vwapButton: some View {
        Group {
            if showsVWAPToggle {
                Button(L10n.Chart.vwap) {
                    showVWAP.toggle()
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(showVWAP ? Color.accentColor.opacity(0.15) : Color(uiColor: .secondarySystemBackground))
                .cornerRadius(AppTheme.fieldCorner)
            }
        }
    }
}
