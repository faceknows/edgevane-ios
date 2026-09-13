import SwiftUI

struct PortfolioView: View {
    @EnvironmentObject private var trading: TradingSession
    @EnvironmentObject private var portfolio: PortfolioStore
    @EnvironmentObject private var brokerage: CurrentBrokerageStore

    var body: some View {
        Group {
            if brokerage.current == nil {
                NoBrokerageView()
            } else if trading.needsCredentials, portfolio.snapshot == nil {
                TradingCredentialsPrompt(
                    title: L10n.Trading.credentialsInvalid,
                    message: L10n.Trading.credentialsInvalidBody
                )
            } else if portfolio.isLoading && portfolio.snapshot == nil {
                ProgressView()
            } else if let errorText = portfolio.errorText, portfolio.snapshot == nil {
                EmptyStateView(
                    title: L10n.Errors.generic,
                    message: errorText,
                    retry: { Task { await trading.refresh() } }
                )
            } else {
                List {
                    banners
                    Section(L10n.Portfolio.todayPnl) {
                        HStack {
                            Text(L10n.Portfolio.todayPnl)
                            Spacer()
                            DailyPnLText(portfolio: portfolio.snapshot)
                        }
                    }
                    Section(L10n.Portfolio.value) {
                        row(L10n.Portfolio.equity, MarketFormat.price(portfolio.snapshot?.equity))
                        row(L10n.Portfolio.lastEquity, MarketFormat.price(portfolio.snapshot?.lastEquity))
                        row(L10n.Portfolio.portfolioValue, MarketFormat.price(portfolio.snapshot?.portfolioValue))
                    }
                    Section(L10n.Portfolio.account) {
                        row(L10n.Portfolio.buyingPower, MarketFormat.price(portfolio.snapshot?.buyingPower))
                        row(L10n.Portfolio.cash, MarketFormat.price(portfolio.snapshot?.cash))
                    }
                }
                .refreshable { await trading.refresh() }
            }
        }
        .navigationTitle(L10n.Portfolio.title)
    }

    @ViewBuilder
    private var banners: some View {
        Section {
            if portfolio.snapshot?.tradingBlocked == true {
                TradingBlockedBanner()
            }
            TradingIssueBanner(errorText: portfolio.errorText) {
                Task { await trading.refresh() }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).font(.body.monospacedDigit())
        }
    }
}
