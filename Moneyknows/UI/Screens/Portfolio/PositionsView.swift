import SwiftUI

struct PositionsView: View {
    @EnvironmentObject private var trading: TradingSession
    @EnvironmentObject private var positions: PositionStore
    @EnvironmentObject private var portfolio: PortfolioStore
    @EnvironmentObject private var brokerage: CurrentBrokerageStore

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
                List {
                    Section {
                        if portfolio.snapshot?.tradingBlocked == true {
                            TradingBlockedBanner()
                        }
                        if !positions.positions.isEmpty {
                            TradingIssueBanner(errorText: positions.errorText) {
                                Task { await trading.refresh() }
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
                            ForEach(positions.positions) { position in
                                NavigationLink(destination: PositionDetailView(symbol: position.symbol)) {
                                    PositionRow(position: position)
                                }
                            }
                        }
                    }
                }
                .refreshable { await trading.refresh() }
            }
        }
        .navigationTitle(L10n.Positions.title)
    }
}

struct PositionRow: View {
    var position: Position

    var body: some View {
        SymbolRowLayout {
            Text(position.symbol).font(.headline)
            Text("\(MarketFormat.quantity(position.quantity)) · \(position.side == .short ? L10n.Positions.short : L10n.Positions.long)")
                .font(.caption)
                .foregroundColor(.secondary)
        } trailing: {
            Text(MarketFormat.signedPrice(position.unrealizedPL))
                .font(.headline.monospacedDigit())
                .foregroundColor(MarketFormat.changeColor(position.unrealizedPL))
            ChangePercentText(percent: position.unrealizedPLPercent)
        }
    }
}
