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
    @State private var secondInterval: SecondInterval = .one
    @State private var secondStyle: ChartStyle = .line
    @State private var subscriptionBusy = false
    @State private var subscriptionError: String?
    @State private var tradeAction: TradeActionKind?
    @State private var sliderPrice: Double?
    @State private var tradeTicketBusy = false
    @State private var sessionTimeRange: ChartVisibleTimeRange?

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
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !realtime.isSocketConnected {
                        MarketDisconnectedBanner()
                    }
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
                            //DailyChartChrome(style: $dailyCharts.style)
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
                        ChartPanel(
                            title: L10n.Chart.nasdaq,
                            model: indexCharts.model(interval: charts.interval, style: charts.style),
                            height: 160,
                            isLoading: indexCharts.isLoading,
                            errorText: indexCharts.errorText,
                            retry: { Task { await indexCharts.reload(date: charts.regularDate) } },
                            visibleTimeRange: sessionTimeRange,
                            allowsTimeScaleInteraction: false,
                            barDuration: charts.interval.barDuration
                        )
                    }
                    ChartPanel(
                        title: L10n.Detail.chart,
                        model: charts.regularModel,
                        height: 260,
                        isLoading: charts.isLoadingRegular,
                        errorText: charts.errorText,
                        retry: { Task { await charts.retryRegular() } },
                        onEvent: handleSessionChartEvent,
                        visibleTimeRange: sessionTimeRange,
                        publishesVisibleTimeRange: true,
                        barDuration: charts.interval.barDuration
                    )
                    ChartChrome(
                        interval: $charts.interval,
                        style: $charts.style,
                        showVWAP: $charts.showVWAP
                    )
                    MinuteIndicatorBadges(snapshot: charts.minuteIndicators)
                    if isSubscribed {
                        LastTradeQuoteStrip(
                            lastPrice: quotes.quote(for: symbol)?.last ?? summary?.lastPrice,
                            quote: quotes.quote(for: symbol)
                        )
                    } else {
                        Text(MarketFormat.price(headerPrice))
                            .font(.title.bold())
                            .monospacedDigit()
                    }
                    if isSubscribed {
                        if hasSecondBars {
                            secondChart
                            if let sliderRange {
                                PriceSliderTradeView(range: sliderRange) { price in
                                    sliderPrice = price
                                    tradeAction = .slider
                                }
                            }
                        }
                        TradeBarView(symbol: symbol, action: $tradeAction, presetPrice: $sliderPrice)
                    }
                    if let subscriptionError {
                        Text(subscriptionError)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                    if let errorText {
                        EmptyStateView(title: errorText)
                    }
                    subscriptionIconButton
                }
                .padding()
            }
            if let tradeAction {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .onTapGesture {
                        guard !tradeTicketBusy else { return }
                        dismissTradeTicket()
                    }
                TradeTicketView(
                    symbol: symbol,
                    action: tradeAction,
                    presetPrice: sliderPrice,
                    onDismiss: dismissTradeTicket,
                    onBusyChange: { tradeTicketBusy = $0 }
                )
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.16), value: tradeAction != nil)
        .navigationTitle(symbol)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                SymbolNavigationTitle(
                    symbol: symbol,
                    changePercent: headerChangePercent,
                    volume: summary?.volume
                )
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                DailyPnLBadge(portfolio: brokerage.current == nil ? nil : portfolio.snapshot)
            }
        }
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
        .onChange(of: charts.regularDate) { _ in
            sessionTimeRange = nil
        }
        .onChange(of: orders.orders) { _ in
            dayFills.refresh(orders: orders.orders, trading: trading)
        }
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
        }
    }

    private var hasSecondBars: Bool {
        _ = seconds.revision
        return !seconds.bars(for: symbol).isEmpty
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

    private var subscriptionIconButton: some View {
        Button {
            Task { await changeSubscription(subscribe: !isSubscribed) }
        } label: {
            Group {
                if subscriptionBusy {
                    ProgressView()
                        .scaleEffect(0.85)
                } else {
                    Image(systemName: isSubscribed ? "minus" : "plus")
                        .font(.title3.weight(.bold))
                        .foregroundColor(isSubscribed ? .red : .green)
                }
            }
            .frame(width: 40, height: 40)
            .overlay(
                Circle()
                    .stroke(Color(uiColor: .separator), lineWidth: 1)
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(subscriptionBusy)
        .accessibilityLabel(isSubscribed ? L10n.Detail.unsubscribe : L10n.Detail.subscribe)
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

    private func refreshMarkers() {
        charts.fills = dayFills.fills
    }

    private func dismissTradeTicket() {
        tradeAction = nil
        sliderPrice = nil
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

    private func handleSessionChartEvent(_ event: ChartEvent) {
        if case let .visibleTimeRange(range) = event {
            if sessionTimeRange?.isApproximatelyEqual(to: range) != true {
                sessionTimeRange = range
            }
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
