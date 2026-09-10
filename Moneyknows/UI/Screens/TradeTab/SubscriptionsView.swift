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
                            minuteCloses: minuteCloses(symbol),
                            isMinuteLoading: watch.isLoading(symbol),
                            minuteError: watch.failureText(for: symbol),
                            retryMinutes: { watch.requestRetry(symbol) },
                            onOpen: { router.openSymbol(symbol) }
                        )
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

    private func minuteCloses(_ symbol: String) -> [Double] {
        SubscriptionSparklineAssembler.closes(bars1m: watch.bars(for: symbol))
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
    var minuteCloses: [Double]
    var isMinuteLoading: Bool
    var minuteError: String? = nil
    var retryMinutes: (() -> Void)? = nil
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onOpen) {
                header
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            HStack(spacing: 10) {
                SparklinePane(
                    title: L10n.Chart.fiveMinutes,
                    values: minuteCloses,
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
        .padding(.vertical, 4)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(symbol)
                    .font(.headline)
                if let bid = quote?.liveBid, let ask = quote?.liveAsk {
                    Text("\(MarketFormat.price(bid))  |  \(MarketFormat.price(ask))")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(MarketFormat.price(summary.lastPrice))
                    .font(.headline.monospacedDigit())
                ChangePercentText(percent: changePercent)
            }
        }
    }

    private var changePercent: Double? {
        guard let last = summary.lastPrice, let previous = summary.previousClose, previous != 0 else {
            return summary.changePercent
        }
        return (last - previous) / previous * 100
    }
}

private struct SubscriptionSecondPane: View {
    @EnvironmentObject private var seconds: SecondBarStore
    var symbol: String

    var body: some View {
        let values = SubscriptionSparklineAssembler.closes(
            bars1s: seconds.bars(for: symbol),
            now: Date()
        )
        return SparklinePane(
            title: L10n.Chart.fiveSeconds,
            values: values,
            baseline: values.first,
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

private struct SparklinePane: View {
    var title: String
    var values: [Double]
    var baseline: Double?
    var isLoading: Bool
    var errorText: String? = nil
    var retry: (() -> Void)? = nil
    var onOpen: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
            ZStack {
                Group {
                    if let onOpen {
                        Button(action: onOpen) {
                            sparkline
                                .opacity(errorText == nil ? 1 : 0.28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHidden(true)
                    } else {
                        sparkline
                    }
                }
                if onOpen != nil, let errorText, !isLoading {
                    SparklineFailure(text: errorText, retry: retry)
                }
            }
            .frame(height: 72)
            .frame(maxWidth: .infinity)
        }
    }

    private var sparkline: some View {
        SparklineView(
            values: values,
            color: MarketFormat.changeColor(SparklineGeometry.delta(values: values, baseline: baseline)),
            isLoading: isLoading,
            errorText: onOpen == nil ? errorText : nil,
            retry: onOpen == nil ? retry : nil
        )
    }
}
