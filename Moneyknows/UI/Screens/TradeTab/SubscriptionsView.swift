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
                            quote: quotes.quote(for: symbol),
                            minutePlot: minutePlot(symbol),
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
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await summaries.prefetch(subscriptions.me)
                }
                group.addTask {
                    await watch.start(symbols: subscriptions.me, store: bars)
                }
                await group.waitForAll()
            }
        }
        .background(SubscriptionSecondExpiryPump())
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

    private func minutePlot(_ symbol: String) -> SparklinePlot {
        let line = SubscriptionSparklineAssembler.minuteLine(bars1m: watch.bars(for: symbol))
        return .line(values: line.values, times: line.times, timeKind: .minute)
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
    var quote: SymbolQuote?
    var minutePlot: SparklinePlot
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
            HStack(spacing: 8) {
                SparklinePane(
                    title: L10n.Chart.fiveMinutes,
                    plot: minutePlot,
                    baseline: summary.previousClose,
                    isLoading: isMinuteLoading,
                    errorText: minuteError,
                    retry: retryMinutes,
                    onOpen: onOpen
                )
                Button(action: onOpen) {
                    SubscriptionSecondPane(symbol: symbol)
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
        }
    }

    private var header: some View {
        SymbolRow(summary: summary, accessory: quoteAccessory)
    }

    private var quoteAccessory: String? {
        guard let bid = quote?.liveBid, let ask = quote?.liveAsk else { return nil }
        return "\(MarketFormat.price(bid))  |  \(MarketFormat.price(ask))"
    }
}

private struct SubscriptionSecondPane: View {
    @EnvironmentObject private var seconds: SecondBarStore
    var symbol: String

    var body: some View {
        let line = SubscriptionSparklineAssembler.secondLine(
            bars1s: seconds.bars(for: symbol),
            now: Date()
        )
        return SparklinePane(
            title: L10n.Chart.fiveSeconds,
            plot: .line(values: line.values, times: line.times, timeKind: .second),
            baseline: line.values.first,
            isLoading: false
        )
    }
}

private struct SubscriptionSecondExpiryPump: View {
    @EnvironmentObject private var seconds: SecondBarStore

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task {
                await seconds.startExpiring()
            }
    }
}
