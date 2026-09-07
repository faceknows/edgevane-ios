import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var summaries: SymbolSummaryStore
    @EnvironmentObject private var brokerage: CurrentBrokerageStore
    @EnvironmentObject private var trading: TradingSession
    @EnvironmentObject private var portfolio: PortfolioStore
    @EnvironmentObject private var positions: PositionStore
    @EnvironmentObject private var orders: OrderStore
    @EnvironmentObject private var router: AppRouter
    @StateObject private var search = SymbolSearchSession()
    @State private var searchText = ""

    var body: some View {
        List {
            Section(L10n.Dashboard.search) {
                SymbolSearchField(
                    text: $searchText,
                    placeholder: L10n.Dashboard.searchPlaceholder,
                    busy: summaries.isLookingUp,
                    onSubmit: submitSearch
                )
                if let searchError = search.errorText {
                    Text(searchError).foregroundColor(.red).font(.footnote)
                }
            }

            Section(L10n.Dashboard.overview) {
                if let environment = trading.environment ?? brokerage.current?.environment {
                    EnvironmentBanner(environment: environment)
                }
                if portfolio.snapshot?.tradingBlocked == true {
                    TradingBlockedBanner()
                }
                if trading.needsCredentials || dashboardErrorText != nil {
                    TradingIssueBanner(errorText: dashboardErrorText) {
                        Task { await trading.refresh() }
                    }
                }
                NavigationLink(destination: AppRouter.destination(.portfolio)) {
                    overviewRow(L10n.Dashboard.todayPnl, accessory: todayPnlValue)
                }
                NavigationLink(destination: AppRouter.destination(.positions)) {
                    overviewRow(L10n.Dashboard.positions, accessory: positionsValue)
                }
                NavigationLink(destination: AppRouter.destination(.orders)) {
                    overviewRow(L10n.Dashboard.orders, accessory: ordersValue)
                }
            }

            Section(L10n.Dashboard.quickAccess) {
                NavigationLink(destination: AppRouter.destination(.screenerCatalog)) {
                    Label(L10n.Dashboard.screeners, systemImage: "chart.bar")
                }
                NavigationLink(destination: ComingSoonView(title: L10n.Dashboard.sentiment)) {
                    Label(L10n.Dashboard.sentiment, systemImage: "brain")
                }
                NavigationLink(destination: ComingSoonView(title: L10n.Dashboard.events)) {
                    Label(L10n.Dashboard.events, systemImage: "calendar")
                }
                NavigationLink(destination: ComingSoonView(title: L10n.Dashboard.notifications)) {
                    Label(L10n.Dashboard.notifications, systemImage: "bell")
                }
                NavigationLink(destination: ComingSoonView(title: L10n.Dashboard.news)) {
                    Label(L10n.Dashboard.news, systemImage: "newspaper")
                }
                NavigationLink(destination: AppRouter.destination(.historicalMinutes)) {
                    Label(L10n.Dashboard.historical, systemImage: "clock")
                }
            }
        }
        .navigationTitle(L10n.Dashboard.title)
        .refreshable { await trading.refresh() }
    }

    private var dashboardErrorText: String? {
        if trading.needsCredentials { return nil }
        return portfolio.errorText ?? positions.errorText ?? orders.errorText
    }

    @ViewBuilder
    private var todayPnlValue: some View {
        if brokerage.current == nil {
            Text(L10n.Dashboard.noBrokerage).foregroundColor(.secondary)
        } else {
            DailyPnLText(portfolio: portfolio.snapshot)
        }
    }

    private var positionsValue: some View {
        Text(brokerage.current == nil ? L10n.Dashboard.noBrokerage : "\(positions.positions.count)")
            .foregroundColor(.secondary)
    }

    private var ordersValue: some View {
        Text(brokerage.current == nil ? L10n.Dashboard.noBrokerage : ordersCountText)
            .foregroundColor(.secondary)
    }

    private var ordersCountText: String {
        orders.hasMoreClosed ? "\(orders.orders.count)+" : "\(orders.orders.count)"
    }

    private func overviewRow<Content: View>(_ title: String, accessory: Content) -> some View {
        HStack {
            Text(title)
            Spacer()
            accessory
        }
    }

    private func submitSearch() {
        Task {
            if let symbol = await search.submit(searchText, lookup: { try await summaries.lookup($0) }) {
                router.openSymbol(symbol)
            }
        }
    }
}
