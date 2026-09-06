import SwiftUI

struct SymbolDetailView: View {
    let symbol: String
    @EnvironmentObject private var summaries: SymbolSummaryStore
    @State private var summary: SymbolSummary?
    @State private var errorText: String?

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(symbol)
                            .font(.largeTitle.bold())
                        Text(L10n.Detail.accountPnl)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(MarketFormat.price(summary?.lastPrice))
                            .font(.title.monospacedDigit())
                        ChangePercentText(percent: summary?.changePercent)
                    }
                }
            }

            Section(L10n.Detail.indicators) {
                row(L10n.Detail.rsi, MarketFormat.compact(summary?.rsi))
                row(L10n.Detail.adx, MarketFormat.compact(summary?.adx))
                row(L10n.Detail.atr, MarketFormat.price(summary?.atr))
            }

            Section(L10n.Detail.chart) {
                Text(L10n.Detail.chartLater)
                    .foregroundColor(.secondary)
            }

            if let errorText {
                Section {
                    Text(errorText).foregroundColor(.red)
                }
            }
        }
        .navigationTitle(symbol)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundColor(.secondary)
        }
    }

    private func load() async {
        do {
            summary = try await summaries.lookup(symbol)
        } catch {
            if error.isCancellation { return }
            errorText = UserFacingError.message(from: error)
        }
    }
}
