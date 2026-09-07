import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationView {
                DashboardView()
            }
            .navigationViewStyle(.stack)
            .tabItem { Label(L10n.Tabs.home, systemImage: "house") }
            NavigationView {
                SubscriptionsView()
            }
            .navigationViewStyle(.stack)
            .tabItem { Label(L10n.Tabs.trade, systemImage: "chart.line.uptrend.xyaxis") }
            NavigationView {
                SettingsHomeView()
            }
            .navigationViewStyle(.stack)
            .tabItem { Label(L10n.Tabs.settings, systemImage: "gearshape") }
        }
        .safeAreaInset(edge: .top) {
            TradingNoticeBanner()
        }
    }
}
