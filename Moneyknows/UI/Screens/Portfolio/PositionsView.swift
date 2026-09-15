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
    @State private var trade: PositionTrade?
    @State private var tradeTicketBusy = false

    var body: some View {
        ZStack {
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
            if let trade {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .onTapGesture {
                        guard !tradeTicketBusy else { return }
                        dismissTradeTicket()
                    }
                TradeTicketView(
                    symbol: trade.symbol,
                    action: trade.action,
                    presetPrice: trade.fallbackPrice,
                    onDismiss: dismissTradeTicket,
                    onBusyChange: { tradeTicketBusy = $0 }
                )
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.16), value: trade != nil)
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
                            onOpen: { router.openSymbol(position.symbol) },
                            onTrade: { action in
                                guard !tradesDisabled else { return }
                                trade = PositionTrade(
                                    symbol: position.symbol,
                                    action: action,
                                    fallbackPrice: Self.listFallbackPrice(position.currentPrice)
                                )
                            },
                            tradesDisabled: tradesDisabled
                        )
                        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await trading.refresh() }
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

    private var tradesDisabled: Bool {
        !trading.hasAccount
            || brokerage.current == nil
            || trading.needsCredentials
            || portfolio.snapshot?.tradingBlocked == true
    }

    private func rowSummary(_ symbol: String) -> SymbolSummary {
        summaries.cached(symbol) ?? SymbolSummary(symbol: symbol)
    }

    private func dismissTradeTicket() {
        trade = nil
        tradeTicketBusy = false
    }

    private static func listFallbackPrice(_ price: Double) -> Double? {
        price.isFinite && price > 0 ? price : nil
    }
}

private struct PositionTrade: Equatable {
    var symbol: String
    var action: TradeActionKind
    var fallbackPrice: Double?
}

private struct PositionWatchCard: View {
    var position: Position
    var summary: SymbolSummary
    var minutePlot: SparklinePlot
    var isMinuteLoading: Bool
    var minuteError: String? = nil
    var retryMinutes: (() -> Void)? = nil
    var onOpen: () -> Void
    var onTrade: (TradeActionKind) -> Void
    var tradesDisabled: Bool

    @EnvironmentObject private var quotes: QuoteStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onOpen) {
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
                onOpen: onOpen
            )
            Button(action: onOpen) {
                LastTradeQuoteStrip(
                    lastPrice: lastPrice,
                    quote: quotes.quote(for: position.symbol),
                    compact: true
                )
            }
            .buttonStyle(.plain)
            PromptTradeButtons(
                disabled: tradesDisabled,
                positionSide: position.side,
                onSelect: onTrade
            )
        }
    }

    private var lastPrice: Double? {
        quotes.quote(for: position.symbol)?.last ?? position.currentPrice
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(position.symbol)
                .font(.headline.weight(.bold))
            Text(L10n.Positions.sidePosition(position.side))
                .font(.caption2.weight(.semibold))
                .foregroundColor(sideColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(sideColor.opacity(0.16))
                .cornerRadius(6)
            Text(verbatim: qtyCostText)
                .font(.subheadline.monospacedDigit())
            Spacer(minLength: 6)
            ChangePercentText(
                percent: position.unrealizedPLPercent,
                font: .subheadline.weight(.semibold).monospacedDigit()
            )
            Text(MarketFormat.signedPrice(position.unrealizedPL))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundColor(MarketFormat.changeColor(position.unrealizedPL))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(headerAccessibilityLabel)
    }

    private var qtyCostText: String {
        "\(MarketFormat.quantity(position.absQuantity))|\(MarketFormat.price(position.averageEntry))"
    }

    private var headerAccessibilityLabel: String {
        [
            position.symbol,
            L10n.Positions.sidePosition(position.side),
            "\(L10n.Positions.quantity) \(MarketFormat.quantity(position.absQuantity))",
            "\(L10n.Positions.averageEntry) \(MarketFormat.price(position.averageEntry))",
            "\(L10n.Positions.unrealized) \(MarketFormat.percent(position.unrealizedPLPercent)) \(MarketFormat.signedPrice(position.unrealizedPL))"
        ].joined(separator: ", ")
    }

    private var sideColor: Color {
        position.side == .short ? .red : .green
    }
}
