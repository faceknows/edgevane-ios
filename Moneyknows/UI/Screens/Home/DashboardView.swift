import SwiftUI
import UIKit

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
    @FocusState private var isSearchFocused: Bool

    private let tileColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if showsBanners {
                    banners
                }
                overviewSection
                shortcutsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ios15PullToRefresh)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .navigationTitle(L10n.Dashboard.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await trading.refresh() }
        .dismissKeyboardOnScroll()
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L10n.Common.done) {
                    isSearchFocused = false
                }
            }
        }
    }

    private var showsBanners: Bool {
        !hasBrokerage
            || portfolio.snapshot?.tradingBlocked == true
            || trading.needsCredentials
            || dashboardErrorText != nil
    }

    private var banners: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !hasBrokerage {
                NoBrokerageBanner()
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

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Dashboard.overview)
                .font(.title2.weight(.bold))
                .onTapGesture { isSearchFocused = false }

            HStack(alignment: .top, spacing: 10) {
                cardLink(.portfolio) {
                    DashboardStatCard(
                        title: L10n.Dashboard.todayPnl,
                        fill: pnlCardFill,
                        environment: trading.environment ?? brokerage.current?.environment
                    ) {
                        todayPnlValue
                    }
                }
                cardLink(.positions) {
                    DashboardStatCard(title: L10n.Dashboard.positions) {
                        positionsValue
                    }
                }
                cardLink(.orders) {
                    DashboardStatCard(
                        title: L10n.Dashboard.orders,
                        hint: hasBrokerage ? L10n.Dashboard.ordersHint : nil
                    ) {
                        ordersValue
                    }
                }
            }
        }
    }

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Dashboard.quickAccess)
                .font(.title2.weight(.bold))
                .onTapGesture { isSearchFocused = false }
            searchCard
            LazyVGrid(columns: tileColumns, spacing: 12) {
                ForEach(shortcuts) { item in
                    cardLink(item.route) {
                        DashboardQuickTile(item: item)
                    }
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
                isFocused: $isSearchFocused,
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

    private func cardLink<Label: View>(
        _ route: AppRoute,
        @ViewBuilder label: () -> Label
    ) -> some View {
        NavigationLink(destination: AppRouter.destination(route)) {
            label()
        }
        .buttonStyle(DashboardPressStyle())
    }

    private func submitSearch() {
        isSearchFocused = false
        Task {
            if let symbol = await search.submit(searchText, lookup: { try await summaries.lookup($0) }) {
                router.openSymbol(symbol)
            }
        }
    }

    @ViewBuilder
    private var ios15PullToRefresh: some View {
        if #available(iOS 16.0, *) {
            EmptyView()
        } else {
            IOS15ScrollRefreshControl {
                await trading.refresh()
            }
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
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
    var environment: BrokerageEnvironment? = nil
    @ViewBuilder var value: () -> Value

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let environment {
                    EnvironmentBanner(environment: environment)
                }
            }
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

private extension View {
    @ViewBuilder
    func dismissKeyboardOnScroll() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollDismissesKeyboard(.immediately)
        } else {
            self
        }
    }
}

/// SwiftUI `.refreshable` on `ScrollView` only runs from iOS 16. Dashboard still
/// targets 15, so attach `UIRefreshControl` to the underlying scroll view.
private struct IOS15ScrollRefreshControl: UIViewRepresentable {
    var action: () async -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.onInstalled = { [weak coordinator = context.coordinator, weak view] in
            guard let view else { return }
            coordinator?.install(from: view)
        }
        return view
    }

    func updateUIView(_ uiView: AnchorView, context: Context) {
        context.coordinator.action = action
        uiView.onInstalled = { [weak coordinator = context.coordinator, weak uiView] in
            guard let uiView else { return }
            coordinator?.install(from: uiView)
        }
        context.coordinator.install(from: uiView)
    }

    final class AnchorView: UIView {
        var onInstalled: (() -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            onInstalled?()
        }
    }

    final class Coordinator: NSObject {
        var action: () async -> Void
        private weak var control: UIRefreshControl?
        private var running = false

        init(action: @escaping () async -> Void) {
            self.action = action
        }

        func install(from view: UIView) {
            guard let scrollView = view.enclosingScrollView() else { return }
            scrollView.alwaysBounceVertical = true
            if let existing = scrollView.refreshControl {
                if control !== existing {
                    existing.addTarget(self, action: #selector(refresh), for: .valueChanged)
                    control = existing
                }
                return
            }
            let fresh = UIRefreshControl()
            fresh.addTarget(self, action: #selector(refresh), for: .valueChanged)
            scrollView.refreshControl = fresh
            control = fresh
        }

        @objc func refresh() {
            guard !running else { return }
            running = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                await action()
                self.control?.endRefreshing()
                self.running = false
            }
        }
    }
}

private extension UIView {
    func enclosingScrollView() -> UIScrollView? {
        var current: UIView? = self
        while let view = current {
            if let scroll = view as? UIScrollView {
                return scroll
            }
            current = view.superview
        }
        current = superview
        while let view = current {
            if let scroll = view.firstScrollViewInSubtree() {
                return scroll
            }
            current = view.superview
        }
        return nil
    }

    func firstScrollViewInSubtree() -> UIScrollView? {
        if let scroll = self as? UIScrollView {
            return scroll
        }
        for child in subviews {
            if let found = child.firstScrollViewInSubtree() {
                return found
            }
        }
        return nil
    }
}
