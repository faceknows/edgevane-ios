import SwiftUI

enum AppRoute: Hashable {
    case screenerCatalog
    case screenerResults(ScreenerKind)
    case portfolio
    case positions
    case orders
    case credentials
    case historicalMinutes
    case sentiment
    case calendar
    case news
    case newsDetail(String)
    case notifications
}

enum AppOverlay: Identifiable, Equatable {
    case symbol(String)
    case news(String)
    case notifications
    case screenerCatalog([String])

    var id: String {
        switch self {
        case .symbol(let symbol):
            return "symbol:\(symbol)"
        case .news(let newsID):
            return "news:\(newsID)"
        case .notifications:
            return "notifications"
        case .screenerCatalog(let symbols):
            return "screener:\(symbols.joined(separator: ","))"
        }
    }
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var overlay: AppOverlay?
    private(set) var pendingNotification: NotificationDestination?
    private(set) var pendingNotificationUserId: String?
    private(set) var isViewingNotifications = false

    func openSymbol(_ raw: String) {
        overlay = .symbol(SymbolCode.normalize(raw))
    }

    func openNews(_ newsID: String) {
        overlay = .news(newsID)
    }

    func setViewingNotifications(_ viewing: Bool) {
        isViewingNotifications = viewing
    }

    var isShowingNotificationHistory: Bool {
        isViewingNotifications || overlay == .notifications
    }

    func dismissOverlay() {
        overlay = nil
    }

    func handleNotification(
        _ notification: AppNotification,
        versionPassed: Bool,
        signedIn: Bool,
        currentUserId: String? = nil,
        alreadyShowingHistory: Bool = false
    ) {
        let owner = notification.ownerUserId
        let destination = NotificationParser.destination(for: notification)
        if signedIn, let owner, !owner.isEmpty {
            if let currentUserId, !currentUserId.isEmpty {
                guard owner == currentUserId else { return }
            } else {
                pendingNotification = destination
                pendingNotificationUserId = owner
                return
            }
        }
        if alreadyShowingHistory || isShowingNotificationHistory, destination == .notifications {
            return
        }
        apply(
            destination,
            versionPassed: versionPassed,
            signedIn: signedIn,
            userId: owner
        )
    }

    func consumePending(versionPassed: Bool, signedIn: Bool, currentUserId: String? = nil) {
        guard versionPassed, signedIn, let pendingNotification else { return }
        if let pendingNotificationUserId {
            guard let currentUserId, !currentUserId.isEmpty else { return }
            guard pendingNotificationUserId == currentUserId else {
                clearPending()
                return
            }
        }
        applyNow(pendingNotification)
    }

    func clearPending() {
        pendingNotification = nil
        pendingNotificationUserId = nil
    }

    func apply(
        _ destination: NotificationDestination,
        versionPassed: Bool,
        signedIn: Bool,
        userId: String? = nil
    ) {
        if !versionPassed || !signedIn {
            pendingNotification = destination
            pendingNotificationUserId = userId
            return
        }
        applyNow(destination)
    }

    private func applyNow(_ destination: NotificationDestination) {
        pendingNotification = nil
        pendingNotificationUserId = nil
        switch destination {
        case .symbol(let symbol):
            openSymbol(symbol)
        case .screenerCatalog(let symbols):
            overlay = .screenerCatalog(symbols)
        case .notifications:
            if !isShowingNotificationHistory {
                overlay = .notifications
            }
        }
    }

    @ViewBuilder
    static func destination(_ route: AppRoute) -> some View {
        switch route {
        case .screenerCatalog:
            ScreenerCatalogView()
        case .screenerResults(let kind):
            ScreenerResultsView(kind: kind)
        case .portfolio:
            PortfolioView()
        case .positions:
            PositionsView()
        case .orders:
            OrdersView()
        case .credentials:
            CredentialsView()
        case .historicalMinutes:
            HistoricalMinutesView()
        case .sentiment:
            MarketSentimentView()
        case .calendar:
            EconomicCalendarView()
        case .news:
            NewsListView()
        case .newsDetail(let newsID):
            NewsDetailView(newsID: newsID)
        case .notifications:
            NotificationsView()
        }
    }
}
