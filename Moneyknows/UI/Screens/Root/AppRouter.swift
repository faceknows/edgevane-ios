import SwiftUI

enum AppRoute: Hashable {
    case screenerCatalog
    case screenerResults(ScreenerKind)
}

enum AppOverlay: Identifiable, Equatable {
    case symbol(String)

    var id: String {
        switch self {
        case .symbol(let symbol):
            return "symbol:\(symbol)"
        }
    }
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var overlay: AppOverlay?

    func openSymbol(_ raw: String) {
        overlay = .symbol(SymbolCode.normalize(raw))
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
        }
    }
}
