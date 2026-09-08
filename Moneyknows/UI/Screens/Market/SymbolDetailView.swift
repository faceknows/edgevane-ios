import SwiftUI

struct SymbolDetailView: View {
    let symbol: String
    @EnvironmentObject private var summaries: SymbolSummaryStore
    @EnvironmentObject private var bars: BarStore
    @EnvironmentObject private var realtime: MarketRealtimeSession
    @EnvironmentObject private var subscriptions: SubscriptionStore
    @EnvironmentObject private var quotes: QuoteStore
    @EnvironmentObject private var seconds: SecondBarStore
    @EnvironmentObject private var portfolio: PortfolioStore
    @EnvironmentObject private var brokerage: CurrentBrokerageStore
    @EnvironmentObject private var trading: TradingSession
    @EnvironmentObject private var orders: OrderStore
    @EnvironmentObject private var preferences: PreferencesStore
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var charts = SymbolChartSession()
    @StateObject private var indexCharts = IndexChartSession()
    @StateObject private var dailyCharts = DailyChartSession()
    @StateObject private var dayFills = DayFillsSession()
    @State private var summary: SymbolSummary?
    @State private var errorText: String?
    @State private var summaryGeneration: UInt64 = 0
    @State private var secondInterval: SecondInterval = .five
    @State private var secondStyle: ChartStyle = .candle
    @State private var subscriptionBusy = false
    @State private var subscriptionError: String?
    @State private var tradeAction: TradeActionKind?
    @State private var sliderPrice: Double?

    private var isSubscribed: Bool {
        subscriptions.contains(symbol)
    }

    private var showsDaily: Bool {
        preferences.values.showDailyBarInDetail
    }

    private var showsIndex: Bool {
        preferences.values.showIndexBarInDetail && !BarSession.isIndexSymbol(symbol)
    }

    private var fillTaskID: String {
        let days = DayFills.chartDays(regularDate: charts.regularDate, extendedDate: charts.extendedDate).joined(separator: ",")
        return "\(SymbolCode.normalize(symbol))|\(days)|\(brokerage.current?.id ?? "")|\(trading.sessionEpoch)"
    }

    private var dailyTaskID: String {
        DailyChartSession.taskID(symbol: symbol, enabled: showsDaily)
    }

    private var indexTaskID: String {
        IndexChartSession.taskID(date: charts.regularDate, enabled: showsIndex)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !realtime.isSocketConnected {
                    MarketDisconnectedBanner()
                }
                header
                if isSubscribed {
                    quoteRow
                    TradeBarView(symbol: symbol, action: $tradeAction, presetPrice: $sliderPrice)
                }
                indicators
                ChartChrome(
                    interval: $charts.interval,
                    style: $charts.style,
                    showVWAP: $charts.showVWAP
                )
                ChartPanel(
                    title: L10n.Detail.chart,
                    model: charts.regularModel,
                    height: 260,
                    isLoading: charts.isLoadingRegular,
                    errorText: charts.errorText,
                    retry: { Task { await charts.retryRegular() } }
                )
                if !charts.preBars.isEmpty {
                    ChartPanel(
                        title: L10n.Chart.preMarket,
                        model: charts.preModel,
                        height: 180
                    )
                }
                if !charts.afterBars.isEmpty {
                    ChartPanel(
                        title: L10n.Chart.afterMarket,
                        model: charts.afterModel,
                        height: 180
                    )
                }
                if let fillErrorText = dayFills.errorText {
                    Text(fillErrorText)
                        .font(.footnote)
                        .foregroundColor(.red)
                }
                if showsDaily {
                    VStack(alignment: .leading, spacing: 8) {
                        DailyChartChrome(style: $dailyCharts.style)
                        ChartPanel(
                            title: L10n.Chart.daily,
                            model: dailyCharts.model,
                            height: 220,
                            isLoading: dailyCharts.isLoading,
                            errorText: dailyCharts.errorText,
                            retry: { Task { await dailyCharts.retry() } },
                            onEvent: handleDailyChartEvent
                        )
                    }
                }
                if showsIndex {
                    VStack(alignment: .leading, spacing: 8) {
                        ChartChrome(
                            interval: $indexCharts.interval,
                            style: $indexCharts.style,
                            showVWAP: .constant(false),
                            showsVWAPToggle: false
                        )
                        ChartPanel(
                            title: L10n.Chart.nasdaq,
                            model: indexCharts.model,
                            height: 160,
                            isLoading: indexCharts.isLoading,
                            errorText: indexCharts.errorText,
                            retry: { Task { await indexCharts.reload(date: charts.regularDate) } }
                        )
                    }
                }
                if isSubscribed {
                    secondChart
                    unsubscribeButton
                } else {
                    subscribeButton
                }
                if let subscriptionError {
                    Text(subscriptionError)
                        .font(.footnote)
                        .foregroundColor(.red)
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
            subscriptionError = nil
            if summary?.symbol != SymbolCode.normalize(symbol) {
                summary = nil
            }
            async let summaryLoad: Void = loadSummary(generation)
            await charts.start(symbol: symbol, store: bars)
            await summaryLoad
        }
        .task(id: fillTaskID) {
            dayFills.reset()
            charts.fills = []
            let days = DayFills.chartDays(regularDate: charts.regularDate, extendedDate: charts.extendedDate)
            guard !days.isEmpty else { return }
            await dayFills.load(symbol: symbol, days: days, trading: trading)
            refreshMarkers()
        }
        .task(id: dailyTaskID) {
            await refreshDailyChart()
        }
        .task(id: indexTaskID) {
            await refreshIndexChart()
        }
        .onChange(of: summary) { value in
            if let value {
                charts.updateSummary(value)
            }
        }
        .onChange(of: dayFills.fills) { _ in
            refreshMarkers()
        }
        .onChange(of: orders.orders) { _ in
            dayFills.refresh(orders: orders.orders, trading: trading)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(symbol)
                    .font(.largeTitle.bold())
                accountPnlLabel
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(MarketFormat.price(headerPrice))
                    .font(.title.monospacedDigit())
                ChangePercentText(percent: headerChangePercent)
            }
        }
    }

    private var quoteRow: some View {
        HStack {
            Text("\(L10n.Detail.bid) \(MarketFormat.price(quotes.quote(for: symbol)?.displayBid))")
            Spacer()
            Text("\(L10n.Detail.ask) \(MarketFormat.price(quotes.quote(for: symbol)?.displayAsk))")
        }
        .font(.subheadline.monospacedDigit())
        .foregroundColor(.secondary)
    }

    private var secondChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.Chart.seconds).font(.headline)
            SecondChartChrome(interval: $secondInterval, style: $secondStyle)
            ChartSurface(
                model: secondModel,
                colors: ChartPalette.colors(scheme: colorScheme),
                height: 180
            )
            if let sliderRange {
                PriceSliderTradeView(range: sliderRange) { price in
                    sliderPrice = price
                    tradeAction = .slider
                }
            }
        }
    }

    private var sliderRange: ClosedRange<Double>? {
        _ = seconds.revision
        let bars = SecondChartAssembler.model(
            bars1s: seconds.bars(for: symbol),
            interval: secondInterval,
            style: secondStyle
        ).bars
        let highs = bars.map(\.high)
        let lows = bars.map(\.low)
        guard let min = lows.min(), let max = highs.max(), max >= min, max > 0,
              min.isFinite, max.isFinite else {
            if let last = quotes.quote(for: symbol)?.last, last > 0, last.isFinite {
                return OrderSizing.sliderBounds((last * 0.99)...(last * 1.01))
            }
            return nil
        }
        return OrderSizing.sliderBounds(min...max)
    }

    private var secondModel: ChartModel {
        _ = seconds.revision
        return SecondChartAssembler.model(
            bars1s: seconds.bars(for: symbol),
            interval: secondInterval,
            style: secondStyle
        )
    }

    private var subscribeButton: some View {
        Button {
            Task { await changeSubscription(subscribe: true) }
        } label: {
            Text(L10n.Detail.subscribe)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(subscriptionBusy)
    }

    private var unsubscribeButton: some View {
        Button(role: .destructive) {
            Task { await changeSubscription(subscribe: false) }
        } label: {
            Text(L10n.Detail.unsubscribe)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(subscriptionBusy)
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

    private var accountPnlLabel: some View {
        HStack(spacing: 6) {
            Text(L10n.Detail.accountPnl)
                .foregroundColor(.secondary)
            if brokerage.current == nil {
                Text(L10n.Dashboard.noBrokerage)
                    .foregroundColor(.secondary)
            } else if let snapshot = portfolio.snapshot {
                Text(MarketFormat.signedPrice(snapshot.profitLoss))
                    .foregroundColor(accountPnlColor(snapshot))
            } else {
                Text("—")
                    .foregroundColor(.secondary)
            }
        }
        .font(.caption)
    }

    private func accountPnlColor(_ snapshot: Portfolio) -> Color {
        switch DailyPnL.tone(percent: snapshot.profitLossPercent) {
        case .profit: return .green
        case .loss: return .red
        case .warning: return .orange
        }
    }

    private var headerPrice: Double? {
        if isSubscribed, let last = quotes.quote(for: symbol)?.last {
            return last
        }
        return summary?.lastPrice
    }

    private var headerChangePercent: Double? {
        guard let headerPrice, let previous = summary?.previousClose, previous != 0 else {
            return summary?.changePercent
        }
        return (headerPrice - previous) / previous * 100
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundColor(.secondary)
        }
    }

    private func refreshMarkers() {
        charts.fills = dayFills.fills
    }

    private func refreshDailyChart() async {
        guard showsDaily else {
            dailyCharts.reset()
            return
        }
        await dailyCharts.start(symbol: symbol, store: bars)
    }

    private func handleDailyChartEvent(_ event: ChartEvent) {
        if case .reachedOldest = event {
            Task { await dailyCharts.loadOlder() }
        }
    }

    private func refreshIndexChart() async {
        guard showsIndex, !charts.regularDate.isEmpty else {
            indexCharts.reset()
            return
        }
        await indexCharts.start(store: bars, date: charts.regularDate)
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

    private func changeSubscription(subscribe: Bool) async {
        subscriptionBusy = true
        defer { subscriptionBusy = false }
        do {
            if subscribe {
                try await realtime.subscribe([symbol])
            } else {
                try await realtime.unsubscribe([symbol])
            }
            subscriptionError = nil
        } catch {
            if error.isCancellation { return }
            subscriptionError = UserFacingError.message(from: error)
                ?? (subscribe ? L10n.Trade.subscribeFailed : L10n.Trade.unsubscribeFailed)
        }
    }
}
