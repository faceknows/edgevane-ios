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

    private let tileColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        List {
            dashboardContent
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 32, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color(uiColor: .systemBackground))
        }
        .listStyle(.plain)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .navigationTitle(L10n.Dashboard.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await trading.refresh() }
    }

    private var dashboardContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            banners
            overviewSection
            shortcutsSection
        }
    }

    @ViewBuilder
    private var banners: some View {
        let hasBanner =
            !hasBrokerage
            || trading.environment != nil
            || brokerage.current?.environment != nil
            || portfolio.snapshot?.tradingBlocked == true
            || trading.needsCredentials
            || dashboardErrorText != nil
        if hasBanner {
            VStack(alignment: .leading, spacing: 8) {
                if !hasBrokerage {
                    NoBrokerageBanner()
                }
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
            }
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Dashboard.overview)
                .font(.title2.weight(.bold))

            HStack(alignment: .top, spacing: 10) {
                NavigationLink(destination: AppRouter.destination(.portfolio)) {
                    DashboardStatCard(
                        title: L10n.Dashboard.todayPnl,
                        fill: pnlCardFill
                    ) {
                        todayPnlValue
                    }
                }
                .buttonStyle(DashboardPressStyle())

                NavigationLink(destination: AppRouter.destination(.positions)) {
                    DashboardStatCard(title: L10n.Dashboard.positions) {
                        positionsValue
                    }
                }
                .buttonStyle(DashboardPressStyle())

                NavigationLink(destination: AppRouter.destination(.orders)) {
                    DashboardStatCard(
                        title: L10n.Dashboard.orders,
                        hint: hasBrokerage ? L10n.Dashboard.ordersHint : nil
                    ) {
                        ordersValue
                    }
                }
                .buttonStyle(DashboardPressStyle())
            }
        }
    }

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Dashboard.quickAccess)
                .font(.title2.weight(.bold))

            searchCard

            LazyVGrid(columns: tileColumns, spacing: 12) {
                ForEach(shortcuts) { item in
                    NavigationLink(destination: AppRouter.destination(item.route)) {
                        DashboardQuickTile(item: item)
                    }
                    .buttonStyle(DashboardPressStyle())
                }
            }
        }
    }

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SymbolSearchField(
                text: $searchText,
                placeholder: L10n.Dashboard.searchPlaceholder,
                busy: summaries.isLookingUp,
                chrome: .inset,
                onSubmit: submitSearch
            )
            if let searchError = search.errorText {
                Text(searchError)
                    .foregroundColor(.red)
                    .font(.footnote)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DashboardPalette.cardFill)
        .cornerRadius(20)
    }

    private var shortcuts: [DashboardShortcut] {
        [
            DashboardShortcut(
                id: "screeners",
                title: L10n.Dashboard.screeners,
                subtitle: "",
                systemImage: "chart.bar",
                tint: DashboardPalette.screeners,
                route: .screenerCatalog
            ),
            DashboardShortcut(
                id: "sentiment",
                title: L10n.Dashboard.sentiment,
                subtitle: L10n.Dashboard.sentimentSubtitle,
                systemImage: "brain",
                tint: DashboardPalette.sentiment,
                route: .sentiment
            ),
            DashboardShortcut(
                id: "events",
                title: L10n.Dashboard.events,
                subtitle: L10n.Dashboard.eventsSubtitle,
                systemImage: "calendar",
                tint: DashboardPalette.events,
                route: .calendar
            ),
            DashboardShortcut(
                id: "notifications",
                title: L10n.Dashboard.notifications,
                subtitle: "",
                systemImage: "bell.fill",
                tint: DashboardPalette.notifications,
                route: .notifications
            ),
            DashboardShortcut(
                id: "news",
                title: L10n.Dashboard.news,
                subtitle: "",
                systemImage: "newspaper",
                tint: DashboardPalette.news,
                route: .news
            ),
            DashboardShortcut(
                id: "historical",
                title: L10n.Dashboard.historical,
                subtitle: "",
                systemImage: "clock.arrow.circlepath",
                tint: DashboardPalette.historical,
                route: .historicalMinutes
            ),
        ]
    }

    private var dashboardErrorText: String? {
        if trading.needsCredentials { return nil }
        return portfolio.errorText ?? positions.errorText ?? orders.errorText
    }

    private var hasBrokerage: Bool {
        brokerage.current != nil
    }

    private var pnlCardFill: Color {
        guard hasBrokerage else { return DashboardPalette.cardFill }
        if DailyPnL.tone(percent: portfolio.snapshot?.profitLossPercent) == .warning {
            return DashboardPalette.pnlWarningFill
        }
        return DashboardPalette.cardFill
    }

    @ViewBuilder
    private var todayPnlValue: some View {
        if !hasBrokerage {
            noBrokerageValue
        } else if portfolio.isLoading && portfolio.snapshot == nil {
            ProgressView()
        } else {
            DailyPnLText(
                portfolio: portfolio.snapshot,
                alignment: .leading,
                valueFont: .title3.weight(.bold).monospacedDigit()
            )
        }
    }

    @ViewBuilder
    private var positionsValue: some View {
        if !hasBrokerage {
            noBrokerageValue
        } else if positions.isLoading && positions.positions.isEmpty {
            ProgressView()
        } else {
            Text("\(positions.positions.count)")
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundColor(.primary)
        }
    }

    @ViewBuilder
    private var ordersValue: some View {
        if !hasBrokerage {
            noBrokerageValue
        } else if orders.isLoading && orders.orders.isEmpty {
            ProgressView()
        } else {
            Text(ordersCountText)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundColor(.primary)
        }
    }

    private var noBrokerageValue: some View {
        Text(L10n.Dashboard.noBrokerage)
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var ordersCountText: String {
        orders.hasMoreClosed ? "\(orders.orders.count)+" : "\(orders.orders.count)"
    }

    private func submitSearch() {
        Task {
            if let symbol = await search.submit(searchText, lookup: { try await summaries.lookup($0) }) {
                router.openSymbol(symbol)
            }
        }
    }
}

private struct DashboardShortcut: Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var tint: Color
    var route: AppRoute
}

private struct DashboardStatCard<Value: View>: View {
    var title: String
    var hint: String? = nil
    var fill: Color = DashboardPalette.cardFill
    @ViewBuilder var value: () -> Value

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            value()
            if let hint, !hint.isEmpty {
                Text(hint)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(fill)
        .cornerRadius(16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct DashboardQuickTile: View {
    var item: DashboardShortcut

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(item.tint.opacity(0.14))
                    .frame(width: 56, height: 56)
                Image(systemName: item.systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(item.tint)
            }
            Text(item.title)
                .font(.headline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
            Text(item.subtitle.isEmpty ? " " : item.subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(minHeight: 32, alignment: .top)
                .opacity(item.subtitle.isEmpty ? 0 : 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 160)
        .background(DashboardPalette.cardFill)
        .cornerRadius(20)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(item.subtitle.isEmpty ? item.title : "\(item.title), \(item.subtitle)")
    }
}

private struct DashboardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
