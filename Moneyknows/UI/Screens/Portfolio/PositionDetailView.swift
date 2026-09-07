import SwiftUI

struct PositionDetailView: View {
    let symbol: String
    @EnvironmentObject private var trading: TradingSession
    @EnvironmentObject private var positions: PositionStore
    @EnvironmentObject private var portfolio: PortfolioStore
    @EnvironmentObject private var brokerage: CurrentBrokerageStore
    @EnvironmentObject private var preferences: PreferencesStore
    @State private var closeKind: TradeActionKind?

    private var position: Position? {
        positions.position(for: symbol)
    }

    var body: some View {
        Group {
            if let position {
                List {
                    Section {
                        if let environment = trading.environment ?? brokerage.current?.environment {
                            EnvironmentBanner(environment: environment)
                        }
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
                .sheet(item: $closeKind) { kind in
                    NavigationView {
                        TradeTicketView(symbol: symbol, action: kind, presetPrice: nil)
                    }
                    .navigationViewStyle(.stack)
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
