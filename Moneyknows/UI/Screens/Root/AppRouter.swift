import SwiftUI

enum AppRoute: Hashable {
    case screenerCatalog
    case screenerResults(ScreenerKind)
    case portfolio
    case positions
    case positionDetail(String)
    case orders
    case credentials
    case historicalMinutes
    case sentiment
    case calendar
    case news
    case newsDetail(String)
}

enum AppOverlay: Identifiable, Equatable {
    case symbol(String)
    case news(String)

    var id: String {
        switch self {
        case .symbol(let symbol):
            return "symbol:\(symbol)"
        case .news(let newsID):
            return "news:\(newsID)"
        }
    }
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var overlay: AppOverlay?

    func openSymbol(_ raw: String) {
        overlay = .symbol(SymbolCode.normalize(raw))
    }

    func openNews(_ newsID: String) {
        overlay = .news(newsID)
    }

    func dismissOverlay() {
        overlay = nil
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
        case .positionDetail(let symbol):
            PositionDetailView(symbol: symbol)
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
        }
    }
}
