import SwiftUI

struct PositionDetailView: View {
    let symbol: String
    @EnvironmentObject private var trading: TradingSession
    @EnvironmentObject private var positions: PositionStore
    @EnvironmentObject private var portfolio: PortfolioStore
    @EnvironmentObject private var brokerage: CurrentBrokerageStore
    @EnvironmentObject private var preferences: PreferencesStore
    @State private var closeKind: TradeActionKind?
    @State private var tradeTicketBusy = false

    private var position: Position? {
        positions.position(for: symbol)
    }

    var body: some View {
        ZStack {
            Group {
                if let position {
                    List {
                        Section {
                            if portfolio.snapshot?.tradingBlocked == true {
                                TradingBlockedBanner()
                            }
                            TradingIssueBanner(errorText: positions.errorText) {
                                Task { await trading.refresh() }
                            }
                        }
                        Section(position.symbol) {
                            row(L10n.Positions.side, position.side == .short ? L10n.Positions.short : L10n.Positions.long)
                            row(L10n.Positions.quantity, MarketFormat.quantity(position.quantity))
                            row(L10n.Positions.entry, MarketFormat.price(position.averageEntry))
                            row(L10n.Positions.current, MarketFormat.price(position.currentPrice))
                            row(L10n.Positions.marketValue, MarketFormat.price(position.marketValue))
                            row(L10n.Positions.cost, MarketFormat.price(position.costBasis))
                        }
                        Section(L10n.Positions.unrealized) {
                            HStack {
                                Text(L10n.Positions.unrealized)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(MarketFormat.signedPrice(position.unrealizedPL))
                                        .font(.headline.monospacedDigit())
                                        .foregroundColor(MarketFormat.changeColor(position.unrealizedPL))
                                    ChangePercentText(percent: position.unrealizedPLPercent)
                                }
                            }
                        }
                        Section(L10n.Positions.close) {
                            Button(L10n.Trading.limitClose) {
                                closeKind = .limitClose
                            }
                            if preferences.values.showMarketTrade {
                                Button(L10n.Trading.marketClose) {
                                    closeKind = .marketClose
                                }
                            }
                        }
                    }
                } else if trading.needsCredentials {
                    TradingCredentialsPrompt(
                        title: L10n.Trading.credentialsInvalid,
                        message: L10n.Trading.credentialsInvalidBody
                    )
                } else {
                    EmptyStateView(
                        title: L10n.Positions.empty,
                        message: L10n.Positions.emptyBody,
                        retry: { Task { await trading.refresh() } }
                    )
                    .padding()
                }
            }
            if let closeKind {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .onTapGesture {
                        guard !tradeTicketBusy else { return }
                        self.closeKind = nil
                    }
                TradeTicketView(
                    symbol: symbol,
                    action: closeKind,
                    presetPrice: nil,
                    onDismiss: { self.closeKind = nil },
                    onBusyChange: { tradeTicketBusy = $0 }
                )
            }
        }
        .animation(.easeOut(duration: 0.16), value: closeKind != nil)
        .navigationTitle(symbol)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).font(.body.monospacedDigit())
        }
    }
}
