import SwiftUI

struct ScreenerResultsView: View {
    let kind: ScreenerKind
    @EnvironmentObject private var store: ScreenerStore
    @EnvironmentObject private var bars: BarStore
    @EnvironmentObject private var router: AppRouter
    @StateObject private var watch = SubscriptionWatchSession()

    var body: some View {
        List {
            if kind.showsFilters, isCurrentKind {
                Section(L10n.Market.filters) {
                    PriceSlopeFilterView(query: $store.query) {
                        Task { await store.applyPriceSlope(store.query) }
                    }
                }
            }

            content
        }
        .navigationTitle(kind.title)
        .task {
            await store.appear(kind)
        }
        .task(id: watchKey) {
            guard isCurrentKind else { return }
            await watch.start(symbols: store.rows.map(\.symbol), store: bars)
        }
    }

    private var isCurrentKind: Bool {
        store.kind == kind
    }

    private var watchKey: String {
        "\(kind.rawValue):\(store.rows.map(\.symbol).joined(separator: ","))"
    }

    @ViewBuilder
    private var content: some View {
        if !isCurrentKind || (store.isLoading && store.rows.isEmpty) {
            Section {
                ProgressView().frame(maxWidth: .infinity)
            }
        } else if let errorText = store.errorText {
            Section {
                EmptyStateView(
                    title: L10n.Errors.generic,
                    message: errorText,
                    retry: { Task { await store.load(kind, query: store.query) } }
                )
            }
        } else if !store.isLoading && store.rows.isEmpty {
            Section {
                EmptyStateView(title: L10n.Market.empty)
            }
        } else {
            Section {
                ForEach(store.rows) { row in
                    ScreenerResultRow(
                        summary: row,
                        bars: watch.bars(for: row.symbol),
                        isLoading: watch.isLoading(row.symbol),
                        errorText: watch.failureText(for: row.symbol),
                        retry: { watch.requestRetry(row.symbol) },
                        onOpen: { router.openSymbol(row.symbol) },
                        emptyText: watch.hasResolved(row.symbol) ? L10n.Chart.empty : nil
                    )
                }
            }
        }
    }
}

private struct ScreenerResultRow: View {
    var summary: SymbolSummary
    var bars: [Bar]
    var isLoading: Bool
    var errorText: String?
    var retry: () -> Void
    var onOpen: () -> Void
    var emptyText: String?

    var body: some View {
        let plot = SubscriptionSparklineAssembler.minuteCandles(bars1m: bars)
        return VStack(alignment: .leading, spacing: 10) {
            Button(action: onOpen) {
                SymbolRow(summary: summary)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            SparklinePane(
                title: "",
                plot: .candles(bars: plot.bars, vwap: plot.vwap),
                chartHeight: 180,
                isLoading: isLoading,
                errorText: errorText,
                retry: retry,
                onOpen: onOpen,
                emptyText: emptyText
            )
        }
        .padding(.vertical, 4)
    }
}
