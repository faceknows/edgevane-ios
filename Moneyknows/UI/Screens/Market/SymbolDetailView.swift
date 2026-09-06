import SwiftUI

struct SymbolDetailView: View {
    let symbol: String
    @EnvironmentObject private var summaries: SymbolSummaryStore
    @EnvironmentObject private var bars: BarStore
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var charts = SymbolChartSession()
    @State private var summary: SymbolSummary?
    @State private var errorText: String?
    @State private var summaryGeneration: UInt64 = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                indicators
                ChartChrome(
                    interval: $charts.interval,
                    style: $charts.style,
                    showVWAP: $charts.showVWAP
                )
                chartSection(
                    title: L10n.Detail.chart,
                    model: charts.regularModel,
                    height: 260,
                    isLoading: charts.isLoadingRegular,
                    errorText: charts.errorText,
                    retry: { Task { await charts.retryRegular() } }
                )
                if !charts.preBars.isEmpty {
                    chartSection(
                        title: L10n.Chart.preMarket,
                        model: charts.preModel,
                        height: 180
                    )
                }
                if !charts.afterBars.isEmpty {
                    chartSection(
                        title: L10n.Chart.afterMarket,
                        model: charts.afterModel,
                        height: 180
                    )
                }
                if let errorText {
                    EmptyStateView(title: errorText)
                }
            }
            .padding()
        }
        .navigationTitle(symbol)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: symbol) {
            summaryGeneration += 1
            let generation = summaryGeneration
            errorText = nil
            if summary?.symbol != SymbolCode.normalize(symbol) {
                summary = nil
            }
            async let summaryLoad: Void = loadSummary(generation)
            await charts.start(symbol: symbol, store: bars)
            await summaryLoad
        }
        .onChange(of: summary) { value in
            if let value {
                charts.updateSummary(value)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(symbol)
                    .font(.largeTitle.bold())
                Text(L10n.Detail.accountPnl)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(MarketFormat.price(summary?.lastPrice))
                    .font(.title.monospacedDigit())
                ChangePercentText(percent: summary?.changePercent)
            }
        }
    }

    private var indicators: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.Detail.indicators)
                .font(.headline)
            row(L10n.Detail.rsi, MarketFormat.compact(summary?.rsi))
            row(L10n.Detail.adx, MarketFormat.compact(summary?.adx))
            row(L10n.Detail.atr, MarketFormat.price(summary?.atr))
        }
    }

    private func chartSection(
        title: String,
        model: ChartModel,
        height: CGFloat,
        isLoading: Bool = false,
        errorText: String? = nil,
        retry: (() -> Void)? = nil
    ) -> some View {
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
                isLoading: isLoading,
                errorText: errorText,
                retry: retry
            )
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundColor(.secondary)
        }
    }

    private func loadSummary(_ generation: UInt64) async {
        do {
            let loaded = try await summaries.lookup(symbol)
            guard generation == summaryGeneration else { return }
            summary = loaded
            charts.updateSummary(loaded)
        } catch {
            guard generation == summaryGeneration else { return }
            if error.isCancellation { return }
            errorText = UserFacingError.message(from: error)
        }
    }
}
