import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            HomePlaceholderView()
                .tabItem { Label(L10n.Tabs.home, systemImage: "house") }
            TradePlaceholderView()
                .tabItem { Label(L10n.Tabs.trade, systemImage: "chart.line.uptrend.xyaxis") }
            SettingsPlaceholderView()
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

struct SettingsPlaceholderView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        NavigationView {
            List {
                Section(L10n.Settings.signedInAs) {
                    Text(appModel.session.user?.email ?? "—")
                    if !AppEnvironment.isProduction {
                        Text(AppEnvironment.debugSummary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Section {
                    Text(L10n.Settings.comingNext)
                        .foregroundColor(.secondary)
                }
                Section {
                    Button(L10n.Settings.signOut, role: .destructive) {
                        appModel.session.signOut()
                    }
                }
            }
            .navigationTitle(L10n.Settings.title)
        }
        .navigationViewStyle(.stack)
    }
}
