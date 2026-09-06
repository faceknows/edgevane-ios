import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var summaries: SymbolSummaryStore
    @EnvironmentObject private var brokerage: CurrentBrokerageStore
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
                NavigationLink(destination: ComingSoonView(title: L10n.Dashboard.todayPnl)) {
                    overviewRow(L10n.Dashboard.todayPnl, value: overviewValue)
                }
                NavigationLink(destination: ComingSoonView(title: L10n.Dashboard.positions)) {
                    overviewRow(L10n.Dashboard.positions, value: overviewValue)
                }
                NavigationLink(destination: ComingSoonView(title: L10n.Dashboard.orders)) {
                    overviewRow(L10n.Dashboard.orders, value: overviewValue)
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
                NavigationLink(destination: ComingSoonView(title: L10n.Dashboard.historical)) {
                    Label(L10n.Dashboard.historical, systemImage: "clock")
                }
            }
        }
        .navigationTitle(L10n.Dashboard.title)
    }

    private var overviewValue: String {
        brokerage.current == nil ? L10n.Dashboard.noBrokerage : L10n.Home.comingSoon
    }

    private func overviewRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
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
