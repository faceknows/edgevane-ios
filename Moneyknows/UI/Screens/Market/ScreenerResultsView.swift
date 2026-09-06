import SwiftUI

struct ScreenerResultsView: View {
    let kind: ScreenerKind
    @EnvironmentObject private var store: ScreenerStore
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        List {
            if kind.showsFilters, isCurrentKind {
                Section(L10n.Market.filters) {
                    PriceSlopeFilterView(query: $store.query) {
                        Task { await store.applyPriceSlope(store.query) }
                    }
                }
            }

            content
        }
        .navigationTitle(kind.title)
        .task {
            await store.appear(kind)
        }
    }

    private var isCurrentKind: Bool {
        store.kind == kind
    }

    @ViewBuilder
    private var content: some View {
        if !isCurrentKind || (store.isLoading && store.rows.isEmpty) {
            Section {
                ProgressView().frame(maxWidth: .infinity)
            }
        } else if let errorText = store.errorText {
            Section {
                EmptyStateView(
                    title: L10n.Errors.generic,
                    message: errorText,
                    retry: { Task { await store.load(kind, query: store.query) } }
                )
            }
        } else if !store.isLoading && store.rows.isEmpty {
            Section {
                EmptyStateView(title: L10n.Market.empty)
            }
        } else {
            Section {
                ForEach(store.rows) { row in
                    Button {
                        router.openSymbol(row.symbol)
                    } label: {
                        SymbolRow(summary: row)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
