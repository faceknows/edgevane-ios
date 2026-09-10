import Foundation

enum SubscriptionSparklineAssembler {
    static let minuteInterval: MinuteInterval = .five
    static let secondInterval: SecondInterval = .five
    static let secondWindow: TimeInterval = TimeInterval(SecondBarStore.capacity)

    static func closes(bars1m: [Bar], interval: MinuteInterval = minuteInterval) -> [Double] {
        BarAggregator.aggregate(bars1m, minutes: interval.minutes)
            .map(\.close)
            .filter { $0.isFinite }
    }

    static func recentSeconds(
        _ bars: [Bar],
        now: Date = Date(),
        window: TimeInterval = secondWindow
    ) -> [Bar] {
        let cutoff = now.addingTimeInterval(-window)
        return bars.filter { $0.time >= cutoff && $0.time <= now }
    }

    static func closes(
        bars1s: [Bar],
        interval: SecondInterval = secondInterval,
        now: Date = Date()
    ) -> [Double] {
        BarAggregator.aggregate(recentSeconds(bars1s, now: now), seconds: interval.seconds)
            .map(\.close)
            .filter { $0.isFinite }
    }
}

@MainActor
final class SubscriptionWatchSession: ObservableObject {
    static let refreshLimit = 4

    @Published private(set) var barsBySymbol: [String: [Bar]] = [:]
    @Published private(set) var loading: Set<String> = []
    @Published private(set) var failed: [String: String] = [:]
    @Published private(set) var date = ""

    private var symbols: [String] = []
    private var loadID: UInt64 = 0
    private var store: BarStore?
    private var retryContinuation: AsyncStream<String>.Continuation?
    private var startGeneration: UInt64 = 0

    func bars(for raw: String) -> [Bar] {
        barsBySymbol[SymbolCode.normalize(raw)] ?? []
    }

    func isLoading(_ raw: String) -> Bool {
        loading.contains(SymbolCode.normalize(raw))
    }

    func failureText(for raw: String) -> String? {
        failed[SymbolCode.normalize(raw)]
    }

    func requestRetry(_ raw: String) {
        let symbol = SymbolCode.normalize(raw)
        guard !symbol.isEmpty else { return }
        retryContinuation?.yield(symbol)
    }

    func retry(_ raw: String) async {
        let symbol = SymbolCode.normalize(raw)
        guard symbols.contains(symbol) else { return }
        await refresh(symbol, showLoading: true)
    }

    func start(symbols: [String], store: BarStore, now: Date = Date()) async {
        guard !Task.isCancelled else { return }
        startGeneration += 1
        let generation = startGeneration
        var continuation: AsyncStream<String>.Continuation!
        let retries = AsyncStream<String> { continuation = $0 }
        retryContinuation = continuation
        defer {
            continuation.finish()
            if startGeneration == generation {
                retryContinuation = nil
            }
        }
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.load(symbols: symbols, store: store, now: now, generation: generation)
                await self.pollIfCurrent(generation: generation)
            }
            group.addTask {
                for await symbol in retries {
                    guard !Task.isCancelled else { return }
                    await self.retryIfCurrent(symbol, generation: generation)
                }
            }
            await group.next()
            group.cancelAll()
        }
    }

    func load(
        symbols: [String],
        store: BarStore,
        now: Date = Date(),
        generation: UInt64? = nil
    ) async {
        guard !Task.isCancelled else { return }
        if let generation, startGeneration != generation { return }
        loadID += 1
        self.store = store
        self.symbols = symbols.map(SymbolCode.normalize).filter { !$0.isEmpty }
        dropRemoved()
        _ = syncDate(now: now)
        adoptCachedBars()
        await refreshAll(showLoading: true)
    }

    func syncDate(now: Date = Date()) -> Bool {
        let next = MarketClock.lastTradingDate(from: now)
        guard next != date else { return false }
        date = next
        barsBySymbol = [:]
        failed = [:]
        adoptCachedBars()
        return true
    }

    private func dropRemoved() {
        let keep = Set(symbols)
        barsBySymbol = barsBySymbol.filter { keep.contains($0.key) }
        loading = loading.intersection(keep)
        failed = failed.filter { keep.contains($0.key) }
    }

    private func adoptCachedBars() {
        guard let store, !date.isEmpty else { return }
        for symbol in symbols {
            if let cached = store.cached(symbol: symbol, date: date, session: .regular) {
                barsBySymbol[symbol] = cached
            }
        }
    }

    private func pollIfCurrent(generation: UInt64) async {
        guard !Task.isCancelled, startGeneration == generation else { return }
        await poll(generation: generation)
    }

    private func retryIfCurrent(_ symbol: String, generation: UInt64) async {
        guard !Task.isCancelled, startGeneration == generation else { return }
        await retry(symbol)
    }

    private func poll(generation: UInt64) async {
        while !Task.isCancelled {
            let delay = MarketClock.nanosecondsUntilNextMinute()
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            guard self.startGeneration == generation, !Task.isCancelled else { return }
            await tick(now: Date())
        }
    }

    func tick(now: Date = Date()) async {
        let rolled = syncDate(now: now)
        if rolled || MarketClock.shouldPoll(session: .regular, date: date, now: now) {
            await refreshAll(showLoading: false)
        } else {
            await refreshFailed(showLoading: false)
        }
    }

    private func refreshFailed(showLoading: Bool) async {
        let snapshot = symbols.filter { failed[$0] != nil }
        guard !snapshot.isEmpty else { return }
        await refreshAll(showLoading: showLoading, only: snapshot)
    }

    private func refreshAll(showLoading: Bool, only symbolsToLoad: [String]? = nil) async {
        guard !Task.isCancelled else { return }
        let snapshot = symbolsToLoad ?? symbols
        await withTaskGroup(of: Void.self) { group in
            var remaining = snapshot.makeIterator()
            func spawn() {
                guard !Task.isCancelled, let symbol = remaining.next() else { return }
                group.addTask { await self.refresh(symbol, showLoading: showLoading) }
            }
            for _ in 0..<min(Self.refreshLimit, snapshot.count) {
                spawn()
            }
            for await _ in group {
                if Task.isCancelled {
                    group.cancelAll()
                    return
                }
                spawn()
            }
        }
    }

    private func refresh(_ symbol: String, showLoading: Bool) async {
        guard !Task.isCancelled else { return }
        guard let store, !date.isEmpty else { return }
        let loadID = self.loadID
        let generation = self.startGeneration
        let date = self.date
        let hasBars = !(barsBySymbol[symbol] ?? []).isEmpty
        if showLoading, !hasBars {
            loading.insert(symbol)
        }
        do {
            let bars = try await store.load(symbol: symbol, date: date, session: .regular)
            guard !Task.isCancelled else { return }
            guard self.startGeneration == generation, self.loadID == loadID, self.date == date, symbols.contains(symbol) else { return }
            barsBySymbol[symbol] = bars
            loading.remove(symbol)
            failed.removeValue(forKey: symbol)
        } catch {
            guard !Task.isCancelled else { return }
            guard self.startGeneration == generation, self.loadID == loadID, self.date == date, symbols.contains(symbol) else { return }
            loading.remove(symbol)
            if error.isCancellation { return }
            failed[symbol] = UserFacingError.message(from: error) ?? L10n.Chart.loadFailed
            AppLog.market.error("subscription watch bars failed")
        }
    }
}
