import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            HomePlaceholderView()
                .tabItem { Label(L10n.Tabs.home, systemImage: "house") }
            TradePlaceholderView()
                .tabItem { Label(L10n.Tabs.trade, systemImage: "chart.line.uptrend.xyaxis") }
            NavigationView {
                SettingsHomeView()
            }
            .navigationViewStyle(.stack)
            .tabItem { Label(L10n.Tabs.settings, systemImage: "gearshape") }
        }
    }
}

struct HomePlaceholderView: View {
    var body: some View {
        NavigationView {
            Text(L10n.Home.placeholder)
                .foregroundColor(.secondary)
                .padding()
                .navigationTitle(L10n.Tabs.home)
        }
        .navigationViewStyle(.stack)
    }
}

struct TradePlaceholderView: View {
    var body: some View {
        NavigationView {
            Text(L10n.Trade.placeholder)
                .foregroundColor(.secondary)
                .padding()
                .navigationTitle(L10n.Tabs.trade)
        }
        .navigationViewStyle(.stack)
    }
}
