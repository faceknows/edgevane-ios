import SwiftUI

struct ChartSurface: View {
    var model: ChartModel
    var colors: ChartColors
    var height: CGFloat = 260
    var volumeHeight: CGFloat? = nil
    var isLoading = false
    var errorText: String? = nil
    var retry: (() -> Void)? = nil
    var onEvent: (ChartEvent) -> Void = { _ in }
    var visibleTimeRange: ChartVisibleTimeRange? = nil
    var publishesVisibleTimeRange = false
    var allowsTimeScaleInteraction = true
    var barDuration: TimeInterval? = nil

    @State private var picked: Bar?
    @State private var engineGeneration = 0
    @State private var engineFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let picked, !model.bars.isEmpty {
                Text(readout(picked))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            if let errorText, !model.bars.isEmpty {
                staleBanner(errorText)
            }
            chartBody
                .frame(height: height)
        }
        .onChange(of: model) { _ in
            picked = nil
        }
    }

    @ViewBuilder
    private var chartBody: some View {
        if isLoading, model.bars.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorText, model.bars.isEmpty {
            EmptyStateView(title: errorText, retry: retry)
        } else if model.bars.isEmpty {
            EmptyStateView(title: L10n.Chart.empty, retry: retry)
        } else if engineFailed {
            EmptyStateView(title: L10n.Chart.loadFailed, retry: retryEngine)
        } else {
            LightweightChartView(
                model: model,
                colors: colors,
                volumeHeight: resolvedVolumeHeight,
                chartHeight: height,
                visibleTimeRange: visibleTimeRange,
                publishesVisibleTimeRange: publishesVisibleTimeRange,
                allowsTimeScaleInteraction: allowsTimeScaleInteraction,
                barDuration: barDuration,
                onEvent: handle
            )
            .id(engineGeneration)
        }
    }

    private var resolvedVolumeHeight: CGFloat? {
        guard model.showVolume else { return nil }
        return volumeHeight ?? ChartVolumeLayout.defaultVolumeHeight(in: height)
    }

    private func staleBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            if let retry {
                Button(L10n.Common.retry, action: retry)
                    .font(.caption.weight(.semibold))
            }
        }
    }

    private func handle(_ event: ChartEvent) {
        if case .loadFailed = event {
            engineFailed = true
            return
        }
        if case let .picked(bar) = event {
            picked = bar
        }
        onEvent(event)
    }

    private func retryEngine() {
        engineFailed = false
        engineGeneration += 1
    }

    private func readout(_ bar: Bar) -> String {
        let stamp = model.usesCalendarDays
            ? MarketClock.usDateString(from: bar.time)
            : MarketClock.usTimeString(from: bar.time)
        return "\(stamp)  O \(MarketFormat.price(bar.open))  H \(MarketFormat.price(bar.high))  L \(MarketFormat.price(bar.low))  C \(MarketFormat.price(bar.close))  V \(MarketFormat.compact(bar.volume))"
    }
}
