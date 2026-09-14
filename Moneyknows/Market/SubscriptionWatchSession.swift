import Foundation

enum SubscriptionSparklineAssembler {
    static let minuteInterval: MinuteInterval = .one
    static let secondInterval: SecondInterval = .one
    static let secondWindow: TimeInterval = TimeInterval(SecondBarStore.capacity)

    static func closes(bars1m: [Bar], interval: MinuteInterval = minuteInterval) -> [Double] {
        aligned(bars1m: bars1m, interval: interval).closes
    }

    static func minuteLine(
        bars1m: [Bar],
        interval: MinuteInterval = minuteInterval,
        includeVWAP: Bool = false
    ) -> (values: [Double], times: [Date], vwap: [Double]) {
        let plot = aligned(bars1m: bars1m, interval: interval, includeVWAP: includeVWAP)
        return (plot.closes, plot.times, plot.vwap)
    }

    static func vwap(bars1m: [Bar], interval: MinuteInterval = minuteInterval) -> [Double] {
        aligned(bars1m: bars1m, interval: interval, includeVWAP: true).vwap
    }

    static func minutePlot(
        bars1m: [Bar],
        interval: MinuteInterval = minuteInterval,
        includeVWAP: Bool = false
    ) -> (closes: [Double], vwap: [Double]) {
        let plot = aligned(bars1m: bars1m, interval: interval, includeVWAP: includeVWAP)
        return (plot.closes, plot.vwap)
    }

    /// 扫描器迷你图：1 分钟 OHLC 蜡烛 + 对齐后的 VWAP。缺一根 VWAP 就丢掉该棒，保证条数一致。
    static func minuteCandles(
        bars1m: [Bar],
        interval: MinuteInterval = .one,
        includeVWAP: Bool = true
    ) -> (bars: [Bar], vwap: [Double]) {
        let plot = aligned(bars1m: bars1m, interval: interval, includeVWAP: includeVWAP, requireOHLC: true)
        return (plot.bars, plot.vwap)
    }

    private static func aligned(
        bars1m: [Bar],
        interval: MinuteInterval,
        includeVWAP: Bool = false,
        requireOHLC: Bool = false
    ) -> (bars: [Bar], closes: [Double], times: [Date], vwap: [Double]) {
        let aggregated = BarAggregator.aggregate(bars1m, minutes: interval.minutes)
        let size = TimeInterval(max(interval.minutes, 1) * 60)
        let lookup = includeVWAP ? vwapByBucket(VWAP.series(from: bars1m), size: size) : [:]
        var bars: [Bar] = []
        var closes: [Double] = []
        var times: [Date] = []
        var overlays: [Double] = []
        for bar in aggregated {
            if requireOHLC {
                guard bar.open.isFinite, bar.high.isFinite, bar.low.isFinite, bar.close.isFinite else { continue }
            } else {
                guard bar.close.isFinite else { continue }
            }
            if includeVWAP {
                guard let value = lookup[bar.time], value.isFinite else { continue }
                overlays.append(value)
            }
            if bar.open.isFinite, bar.high.isFinite, bar.low.isFinite {
                bars.append(bar)
            }
            closes.append(bar.close)
            times.append(bar.time)
        }
        return (bars, closes, times, overlays)
    }

    /// 每个展示桶只保留桶内最后一根 1 分钟 VWAP，避免对每根聚合棒扫描整条序列。
    private static func vwapByBucket(_ points: [OverlayPoint], size: TimeInterval) -> [Date: Double] {
        var map: [Date: Double] = [:]
        map.reserveCapacity(points.count)
        for point in points {
            guard point.value.isFinite else { continue }
            map[BarAggregator.bucketStart(point.time, size: size)] = point.value
        }
        return map
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
        secondLine(bars1s: bars1s, interval: interval, now: now).values
    }

    static func secondLine(
        bars1s: [Bar],
        interval: SecondInterval = secondInterval,
        now: Date = Date()
    ) -> (values: [Double], times: [Date]) {
        var values: [Double] = []
        var times: [Date] = []
        for bar in BarAggregator.aggregate(recentSeconds(bars1s, now: now), seconds: interval.seconds) {
            guard bar.close.isFinite else { continue }
            values.append(bar.close)
            times.append(bar.time)
        }
        return (values, times)
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
    private var pendingRetries: [String] = []
    private var startGeneration: UInt64 = 0

    func bars(for raw: String) -> [Bar] {
        barsBySymbol[SymbolCode.normalize(raw)] ?? []
    }

    /// True after a successful fetch (including `[]`). Missing key means not yet loaded.
    func hasResolved(_ raw: String) -> Bool {
        barsBySymbol[SymbolCode.normalize(raw)] != nil
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
        guard !pendingRetries.contains(symbol) else { return }
        pendingRetries.append(symbol)
        retryContinuation?.yield(symbol)
    }

    func retry(_ raw: String) async {
        let symbol = SymbolCode.normalize(raw)
        guard symbols.contains(symbol) else { return }
        await refresh(symbol, showLoading: true, force: true)
    }

    func start(symbols: [String], store: BarStore, now: Date = Date()) async {
        guard !Task.isCancelled else { return }
        startGeneration += 1
        let generation = startGeneration
        var continuation: AsyncStream<String>.Continuation!
        let retries = AsyncStream<String> { continuation = $0 }
        retryContinuation = continuation
        flushPendingRetries()
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
                    await self.consumePendingRetry(symbol)
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
        self.symbols = Self.uniqued(symbols.map(SymbolCode.normalize).filter { !$0.isEmpty })
        dropRemoved()
        _ = syncDate(now: now)
        adoptCachedBars()
        await refreshAll(showLoading: true, now: now)
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

    private func consumePendingRetry(_ symbol: String) {
        pendingRetries.removeAll { $0 == symbol }
    }

    private func flushPendingRetries() {
        guard let retryContinuation else { return }
        for symbol in pendingRetries {
            retryContinuation.yield(symbol)
        }
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
            await refreshAll(showLoading: false, now: now)
        } else {
            await refreshFailed(showLoading: false, now: now)
        }
    }

    private func refreshFailed(showLoading: Bool, now: Date) async {
        let snapshot = symbols.filter { failed[$0] != nil }
        guard !snapshot.isEmpty else { return }
        await refreshAll(showLoading: showLoading, only: snapshot, now: now)
    }

    private func refreshAll(showLoading: Bool, only symbolsToLoad: [String]? = nil, now: Date = Date()) async {
        guard !Task.isCancelled else { return }
        let snapshot = symbolsToLoad ?? symbols
        await withTaskGroup(of: Void.self) { group in
            var remaining = snapshot.makeIterator()
            func spawn() {
                guard !Task.isCancelled, let symbol = remaining.next() else { return }
                group.addTask { await self.refresh(symbol, showLoading: showLoading, now: now) }
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

    private func refresh(_ symbol: String, showLoading: Bool, force: Bool = false, now: Date = Date()) async {
        guard !Task.isCancelled else { return }
        guard let store, !date.isEmpty else { return }
        let loadID = self.loadID
        let generation = self.startGeneration
        let date = self.date
        let hasBars = !(barsBySymbol[symbol] ?? []).isEmpty
        if showLoading, !hasBars || force {
            loading.insert(symbol)
        }
        do {
            let bars = try await store.load(symbol: symbol, date: date, session: .regular, force: force, now: now)
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

    private static func uniqued(_ symbols: [String]) -> [String] {
        var seen = Set<String>()
        return symbols.filter { seen.insert($0).inserted }
    }
}
