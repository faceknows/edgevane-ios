import SwiftUI

struct HistoricalMinutesView: View {
    @StateObject private var session = HistoricalMinutesSession()

    var body: some View {
        HistoricalMinutesBody(session: session, fills: session.dayFills)
    }
}

private struct HistoricalMinutesBody: View {
    @EnvironmentObject private var summaries: SymbolSummaryStore
    @EnvironmentObject private var bars: BarStore
    @EnvironmentObject private var trading: TradingSession
    @ObservedObject var session: HistoricalMinutesSession
    @ObservedObject var fills: DayFillsSession
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SymbolSearchField(
                        text: $session.draftSymbol,
                        placeholder: L10n.Historical.symbolPlaceholder,
                        busy: session.isLookingUp,
                        isFocused: $isSearchFocused,
                        onSubmit: submit
                    )
                    DatePicker(
                        L10n.Market.date,
                        selection: dateBinding,
                        displayedComponents: .date
                    )
                    .environment(\.timeZone, MarketClock.easternTimeZone)
                    .datePickerStyle(.compact)

                    if session.symbol.isEmpty == false {
                        ChartChrome(
                            interval: $session.interval,
                            style: $session.style,
                            showVWAP: $session.showVWAP
                        )
                        ChartPanel(
                            title: session.symbol,
                            model: session.regularModel,
                            height: 260,
                            isLoading: session.isLoading,
                            errorText: session.errorText,
                            retry: { Task { await session.reload(store: bars, trading: trading) } },
                            onEvent: handleChartEvent
                        )
                        if !session.preBars.isEmpty {
                            ChartPanel(
                                title: L10n.Chart.preMarket,
                                model: session.preModel,
                                height: 180,
                                onEvent: handleChartEvent
                            )
                        }
                        if !session.afterBars.isEmpty {
                            ChartPanel(
                                title: L10n.Chart.afterMarket,
                                model: session.afterModel,
                                height: 180,
                                onEvent: handleChartEvent
                            )
                        }
                        fillsSection
                    } else if let errorText = session.errorText {
                        EmptyStateView(title: errorText)
                    }
                }
                .padding()
            }
            .onChange(of: fills.selectedFillID) { id in
                guard let id else { return }
                withAnimation {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .navigationTitle(L10n.Historical.title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: session.dateString) { _ in
            Task { await session.reload(store: bars, trading: trading) }
        }
        .onChange(of: trading.orders.orders) { _ in
            session.refreshFills(trading: trading)
        }
        .onChange(of: trading.sessionEpoch) { _ in
            Task { await session.reloadFills(trading: trading) }
        }
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { session.pickerDate },
            set: { session.pickerDate = $0 }
        )
    }

    private var fillsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.Historical.fills).font(.headline)
            if let fillErrorText = fills.errorText {
                Text(fillErrorText)
                    .font(.footnote)
                    .foregroundColor(.red)
            }
            if fills.fills.isEmpty {
                Text(L10n.Historical.emptyFills)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(fills.fills) { fill in
                    Button {
                        fills.selectedFillID = fill.id
                    } label: {
                        HStack {
                            Text(MarketClock.usTimeString(from: fill.filledAt))
                                .font(.subheadline.monospacedDigit())
                            Text(fill.side == .buy ? L10n.Trading.buy : L10n.Trading.sell)
                            if !DayFills.isChartable(
                                fill,
                                regularBars: session.regularBars,
                                preBars: session.preBars,
                                afterBars: session.afterBars
                            ) {
                                Text(L10n.Historical.listOnly)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(DayFills.caption(fill))
                                .font(.subheadline.monospacedDigit())
                        }
                        .padding(.vertical, 4)
                        .foregroundColor(fills.selectedFillID == fill.id ? .accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                    .id(fill.id)
                }
            }
        }
    }

    private func handleChartEvent(_ event: ChartEvent) {
        if case let .pickedMarker(id) = event {
            fills.selectedFillID = id
        }
    }

    private func submit() {
        Task {
            await session.submit(
                lookup: { try await summaries.lookup($0) },
                store: bars,
                trading: trading
            )
        }
    }
}
