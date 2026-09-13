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

struct DailyChartChrome: View {
    @Binding var style: ChartStyle

    var body: some View {
        HStack(spacing: 8) {
            Button(style == .candle ? L10n.Chart.line : L10n.Chart.candle) {
                style = style == .candle ? .line : .candle
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(AppTheme.fieldCorner)
            Spacer()
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

struct ChartPanel: View {
    var title: String
    var model: ChartModel
    var height: CGFloat
    var volumeHeight: CGFloat? = nil
    var isLoading = false
    var errorText: String? = nil
    var retry: (() -> Void)? = nil
    var onEvent: (ChartEvent) -> Void = { _ in }
    var visibleTimeRange: ChartVisibleTimeRange? = nil
    var publishesVisibleTimeRange = false
    var allowsTimeScaleInteraction = true
    var barDuration: TimeInterval? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if isLoading {
                    ProgressView()
                }
            }
            ChartSurface(
                model: model,
                colors: ChartPalette.colors(scheme: colorScheme),
                height: height,
                volumeHeight: volumeHeight,
                isLoading: isLoading,
                errorText: errorText,
                retry: retry,
                onEvent: onEvent,
                visibleTimeRange: visibleTimeRange,
                publishesVisibleTimeRange: publishesVisibleTimeRange,
                allowsTimeScaleInteraction: allowsTimeScaleInteraction,
                barDuration: barDuration
            )
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
