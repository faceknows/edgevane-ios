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
                Section {
                    filterControls
                }
            }

            content
        }
        .navigationTitle(kind.title)
        .listStyle(.plain)
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
    private var filterControls: some View {
        switch kind {
        case .momentum:
            MomentumFilterView(query: $store.query) {
                Task { await store.load(.momentum, query: store.query) }
            }
        case .atr:
            ATRFilterView(query: $store.query) {
                Task { await store.load(.atr, query: store.query) }
            }
        case .stair:
            StairFilterView(query: $store.query) {
                Task { await store.load(.stair, query: store.query) }
            }
        case .priceSlope:
            PriceSlopeFilterView(query: $store.query) {
                Task { await store.load(.priceSlope, query: store.query) }
            }
        case .premarket:
            PremarketFilterView(query: $store.query) {
                Task { await store.load(.premarket, query: store.query) }
            }
        case .rsiAdx:
            RsiAdxFilterView(query: $store.query) {
                Task { await store.load(.rsiAdx, query: store.query) }
            }
        case .volume:
            VolumeFilterView(query: $store.query) {
                Task { await store.load(.volume, query: store.query) }
            }
        case .ibkr:
            IBKRFilterView(query: $store.query) {
                Task { await store.load(.ibkr, query: store.query) }
            }
        default:
            EmptyView()
        }
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
            ForEach(store.rows) { row in
                ScreenerResultRow(
                    summary: row,
                    bars: watch.bars(for: row.symbol),
                    isLoading: watch.isLoading(row.symbol),
                    errorText: watch.failureText(for: row.symbol),
                    retry: { watch.requestRetry(row.symbol) },
                    onOpen: { router.openSymbol(row.symbol) },
                    emptyText: watch.hasResolved(row.symbol) ? L10n.Chart.empty : nil,
                    showsATR: kind == .atr
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 4, trailing: 12))
                .listRowSeparator(.visible, edges: .bottom)
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
    var showsATR: Bool = false

    var body: some View {
        let plot = SubscriptionSparklineAssembler.minuteCandles(bars1m: bars)
        return VStack(alignment: .leading, spacing: 2) {
            Button(action: onOpen) {
                SymbolRow(summary: summary, arrangement: .distributed, showsATR: showsATR)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            SparklinePane(
                title: "",
                plot: .candles(bars: plot.bars, vwap: plot.vwap, timeKind: .minute),
                chartHeight: 150,
                isLoading: isLoading,
                errorText: errorText,
                retry: retry,
                onOpen: onOpen,
                emptyText: emptyText
            )
        }
    }
}
