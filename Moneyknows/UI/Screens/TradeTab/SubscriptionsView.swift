import SwiftUI

struct SubscriptionsView: View {
    @EnvironmentObject private var realtime: MarketRealtimeSession
    @EnvironmentObject private var subscriptions: SubscriptionStore
    @EnvironmentObject private var quotes: QuoteStore
    @EnvironmentObject private var summaries: SymbolSummaryStore
    @EnvironmentObject private var bars: BarStore
    @EnvironmentObject private var router: AppRouter
    @StateObject private var watch = SubscriptionWatchSession()
    @State private var addText = ""
    @State private var isAdding = false
    @State private var addError: String?
    @State private var showAdd = false

    var body: some View {
        List {
            if !realtime.isSocketConnected {
                Section {
                    MarketDisconnectedBanner()
                }
            }

            if let bannerError {
                Section {
                    FormMessage(text: bannerError)
                }
            }

            if subscriptions.isLoading && subscriptions.me.isEmpty {
                Section {
                    ProgressView().frame(maxWidth: .infinity)
                }
            } else if subscriptions.me.isEmpty {
                Section {
                    EmptyStateView(
                        title: L10n.Trade.empty,
                        message: L10n.Trade.emptyBody
                    )
                }
            } else {
                Section {
                    ForEach(subscriptions.me, id: \.self) { symbol in
                        SubscriptionWatchRow(
                            symbol: symbol,
                            summary: rowSummary(symbol),
                            bars1m: watch.bars(for: symbol),
                            isMinuteLoading: watch.isLoading(symbol),
                            minuteError: watch.failureText(for: symbol),
                            retryMinutes: { watch.requestRetry(symbol) },
                            onOpen: { router.openSymbol(symbol) }
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 4, trailing: 12))
                    }
                    .onDelete(perform: unsubscribe)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.Trade.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addError = nil
                    addText = ""
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            addSheet
        }
        .task {
            await realtime.refreshSubscriptions()
        }
        .task(id: subscriptions.me.joined(separator: ",")) {
            await watch.start(symbols: subscriptions.me, store: bars)
        }
        .task(id: "\(subscriptions.me.joined(separator: ","))|\(watch.date)") {
            guard !watch.date.isEmpty else { return }
            await summaries.prefetch(subscriptions.me)
        }
        .background(SecondBarExpiryPump())
    }

    private var bannerError: String? {
        addError ?? subscriptions.errorText
    }

    private var addSheet: some View {
        NavigationView {
            Form {
                Section {
                    TextField(L10n.Trade.addPlaceholder, text: $addText)
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                }
                if let addError {
                    Section {
                        FormMessage(text: addError)
                    }
                }
            }
            .navigationTitle(L10n.Trade.add)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) {
                        showAdd = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.save) {
                        Task { await addSymbols() }
                    }
                    .disabled(isAdding)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func rowSummary(_ symbol: String) -> SymbolSummary {
        var summary = summaries.cached(symbol) ?? SymbolSummary(symbol: symbol)
        if let last = quotes.quote(for: symbol)?.last {
            summary.lastPrice = last
        }
        return summary
    }

    private func addSymbols() async {
        let symbols = addText
            .split { $0 == "," || $0.isWhitespace }
            .map { SymbolCode.normalize(String($0)) }
            .filter { SymbolCode.isValid($0) }
        guard !symbols.isEmpty else {
            addError = L10n.Trade.symbolsRequired
            return
        }
        isAdding = true
        defer { isAdding = false }
        do {
            try await realtime.subscribe(symbols)
            addError = nil
            showAdd = false
        } catch {
            if error.isCancellation { return }
            addError = UserFacingError.message(from: error) ?? L10n.Trade.subscribeFailed
        }
    }

    private func unsubscribe(at offsets: IndexSet) {
        let symbols = offsets.map { subscriptions.me[$0] }
        Task {
            do {
                try await realtime.unsubscribe(symbols)
                addError = nil
            } catch {
                if error.isCancellation { return }
                addError = UserFacingError.message(from: error) ?? L10n.Trade.unsubscribeFailed
            }
        }
    }
}

struct SubscriptionWatchRow: View {
    var symbol: String
    var summary: SymbolSummary
    var bars1m: [Bar]
    var isMinuteLoading: Bool
    var minuteError: String? = nil
    var retryMinutes: (() -> Void)? = nil
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: onOpen) {
                header
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            WatchSparklinePair(
                symbol: symbol,
                minutePlot: .watchMinutes(bars1m: bars1m),
                previousClose: summary.previousClose,
                isMinuteLoading: isMinuteLoading,
                minuteError: minuteError,
                retryMinutes: retryMinutes,
                onOpen: onOpen
            )
        }
    }

    private var header: some View {
        SymbolRow(summary: summary, arrangement: .distributed)
    }
}
