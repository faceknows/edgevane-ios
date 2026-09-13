import SwiftUI

struct ScreenerCatalogView: View {
    var highlightedSymbols: [String] = []
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        List {
            if !highlightedSymbols.isEmpty {
                Section(L10n.Market.notificationSymbols) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(highlightedSymbols, id: \.self) { symbol in
                                Button {
                                    router.openSymbol(symbol)
                                } label: {
                                    Text(symbol)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color(uiColor: .secondarySystemBackground))
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            Section {
                ForEach(ScreenerKind.allCases) { kind in
                    NavigationLink(destination: AppRouter.destination(.screenerResults(kind))) {
                        Text(kind.title)
                    }
                }
            }
        }
        .navigationTitle(L10n.Market.catalogTitle)
    }
}
