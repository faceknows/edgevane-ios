import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        RootSwitcher(versionGate: appModel.versionGate, session: appModel.session)
    }
}

private struct RootSwitcher: View {
    @ObservedObject var versionGate: VersionGateModel
    @ObservedObject var session: SessionStore
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        Group {
            switch versionGate.state {
            case .passed:
                if session.isRestoringSession {
                    ProgressView()
                } else if session.isSignedIn {
                    MainTabView()
                } else {
                    NavigationView {
                        LoginView()
                    }
                    .navigationViewStyle(.stack)
                }
            default:
                VersionGateView(model: versionGate)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .fullScreenCover(item: $router.overlay) { overlay in
            NavigationView {
                overlayDestination(overlay)
            }
            .navigationViewStyle(.stack)
        }
    }

    @ViewBuilder
    private func overlayDestination(_ overlay: AppOverlay) -> some View {
        switch overlay {
        case .symbol(let symbol):
            SymbolDetailView(symbol: symbol)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.Common.close) {
                            router.dismissOverlay()
                        }
                    }
                }
                .safeAreaInset(edge: .top) {
                    VStack(spacing: 0) {
                        TradingNoticeBanner()
                        NewsToastBanner()
                        NotificationToastBanner()
                    }
                }
        case .news(let newsID):
            NewsDetailView(newsID: newsID)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.Common.close) {
                            router.dismissOverlay()
                        }
                    }
                }
        case .notifications:
            NotificationsView()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.Common.close) {
                            router.dismissOverlay()
                        }
                    }
                }
        case .screenerCatalog(let symbols):
            ScreenerCatalogView(highlightedSymbols: symbols)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.Common.close) {
                            router.dismissOverlay()
                        }
                    }
                }
        }
    }
}
