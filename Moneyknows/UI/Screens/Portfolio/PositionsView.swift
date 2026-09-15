import SwiftUI

struct PositionsView: View {
    @EnvironmentObject private var trading: TradingSession
    @EnvironmentObject private var positions: PositionStore
    @EnvironmentObject private var portfolio: PortfolioStore
    @EnvironmentObject private var brokerage: CurrentBrokerageStore
    @EnvironmentObject private var realtime: MarketRealtimeSession
    @EnvironmentObject private var bars: BarStore
    @EnvironmentObject private var summaries: SymbolSummaryStore
    @EnvironmentObject private var router: AppRouter
    @StateObject private var watch = SubscriptionWatchSession()
    @State private var detailSymbol: String?

    var body: some View {
        Group {
            if brokerage.current == nil {
                NoBrokerageView()
            } else if trading.needsCredentials, positions.positions.isEmpty {
                TradingCredentialsPrompt(
                    title: L10n.Trading.credentialsInvalid,
                    message: L10n.Trading.credentialsInvalidBody
                )
            } else {
                list
            }
        }
        .background(detailLink)
        .navigationTitle(L10n.Positions.title)
        .task(id: watchKey) {
            await watch.start(symbols: watchSymbols, store: bars)
        }
        .task(id: summaryWatchKey) {
            guard !watch.date.isEmpty else { return }
            await summaries.prefetch(watchSymbols)
        }
        .background(SecondBarExpiryPump())
    }

    private var watchSymbols: [String] {
        Array(
            Set(
                positions.positions.map { SymbolCode.normalize($0.symbol) }.filter { !$0.isEmpty }
            )
        ).sorted()
    }

    private var watchKey: String {
        watchSymbols.joined(separator: ",")
    }

    private var summaryWatchKey: String {
        "\(watchKey)|\(watch.date)"
    }

    private var showsBanners: Bool {
        !realtime.isSocketConnected
            || portfolio.snapshot?.tradingBlocked == true
            || (!positions.positions.isEmpty && (trading.needsCredentials || !(positions.errorText ?? "").isEmpty))
    }

    private var list: some View {
        List {
            if showsBanners {
                Section {
                    if !realtime.isSocketConnected {
                        MarketDisconnectedBanner()
                    }
                    if portfolio.snapshot?.tradingBlocked == true {
                        TradingBlockedBanner()
                    }
                    if !positions.positions.isEmpty {
                        TradingIssueBanner(errorText: positions.errorText) {
                            Task { await trading.refresh() }
                        }
                    }
                }
            }
            if positions.isLoading && positions.positions.isEmpty {
                Section {
                    ProgressView().frame(maxWidth: .infinity)
                }
            } else if let errorText = positions.errorText, positions.positions.isEmpty {
                Section {
                    EmptyStateView(
                        title: L10n.Errors.generic,
                        message: errorText,
                        retry: { Task { await trading.refresh() } }
                    )
                }
            } else if positions.positions.isEmpty {
                Section {
                    EmptyStateView(
                        title: L10n.Positions.empty,
                        message: L10n.Positions.emptyBody
                    )
                }
            } else {
                Section {
                    summaryRow
                }
                ForEach(positions.positions) { position in
                    Section {
                        PositionWatchCard(
                            position: position,
                            summary: rowSummary(position.symbol),
                            minutePlot: .watchMinutes(bars1m: watch.bars(for: position.symbol)),
                            isMinuteLoading: watch.isLoading(position.symbol),
                            minuteError: watch.failureText(for: position.symbol),
                            retryMinutes: { watch.requestRetry(position.symbol) },
                            onOpenSymbol: { router.openSymbol(position.symbol) },
                            onOpenDetail: { detailSymbol = position.symbol }
                        )
                        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await trading.refresh() }
    }

    private var detailLink: some View {
        NavigationLink(
            destination: PositionDetailView(symbol: detailSymbol ?? ""),
            isActive: Binding(
                get: { detailSymbol != nil },
                set: { if !$0 { detailSymbol = nil } }
            )
        ) {
            EmptyView()
        }
        .hidden()
    }

    private var summaryRow: some View {
        HStack(alignment: .top, spacing: 16) {
            summaryMetric(
                title: L10n.Positions.unrealizedTotal,
                value: MarketFormat.signedPrice(totalUnrealized),
                color: MarketFormat.changeColor(totalUnrealized)
            )
            summaryMetric(
                title: L10n.Portfolio.todayPnl,
                value: MarketFormat.signedPrice(portfolio.snapshot?.profitLoss),
                color: todayColor
            )
        }
    }

    private func summaryMetric(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundColor(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }

    private var totalUnrealized: Double {
        positions.positions.reduce(0) { $0 + $1.unrealizedPL }
    }

    private var todayColor: Color {
        switch DailyPnL.tone(percent: portfolio.snapshot?.profitLossPercent) {
        case .profit: return .green
        case .loss: return .red
        case .warning: return .orange
        }
    }

    private func rowSummary(_ symbol: String) -> SymbolSummary {
        summaries.cached(symbol) ?? SymbolSummary(symbol: symbol)
    }
}

private struct PositionWatchCard: View {
    var position: Position
    var summary: SymbolSummary
    var minutePlot: SparklinePlot
    var isMinuteLoading: Bool
    var minuteError: String? = nil
    var retryMinutes: (() -> Void)? = nil
    var onOpenSymbol: () -> Void
    var onOpenDetail: () -> Void

    @EnvironmentObject private var quotes: QuoteStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onOpenDetail) {
                header
            }
            .buttonStyle(.plain)
            WatchSparklinePair(
                symbol: position.symbol,
                minutePlot: minutePlot,
                previousClose: summary.previousClose,
                isMinuteLoading: isMinuteLoading,
                minuteError: minuteError,
                retryMinutes: retryMinutes,
                onOpen: onOpenSymbol
            )
            LastTradeQuoteStrip(
                lastPrice: lastPrice,
                quote: quotes.quote(for: position.symbol),
                compact: true
            )
        }
    }

    private var lastPrice: Double? {
        quotes.quote(for: position.symbol)?.last ?? position.currentPrice
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Text(position.symbol)
                        .font(.title2.weight(.bold))
                    Text(L10n.Positions.sidePosition(position.side))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(sideColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(sideColor.opacity(0.16))
                        .cornerRadius(8)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(L10n.Positions.unrealized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(MarketFormat.signedPrice(position.unrealizedPL))
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundColor(MarketFormat.changeColor(position.unrealizedPL))
                    ChangePercentText(
                        percent: position.unrealizedPLPercent,
                        font: .caption.weight(.semibold).monospacedDigit()
                    )
                }
            }
            HStack(alignment: .top, spacing: 8) {
                metric(L10n.Positions.quantity, MarketFormat.quantity(position.quantity), alignment: .leading)
                metric(L10n.Positions.cost, MarketFormat.price(position.costBasis))
                metric(L10n.Positions.marketValue, MarketFormat.price(position.marketValue), alignment: .trailing)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func metric(_ title: String, _ value: String, alignment: HorizontalAlignment = .center) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : (alignment == .trailing ? .trailing : .center))
    }

    private var sideColor: Color {
        position.side == .short ? .red : .green
    }
}
