import Foundation

@MainActor
final class BarStore: ObservableObject {
    static let maxBuckets = 240
    static let maxBarsPerBucket = 1000

    private let api: BarsAPI
    private var cache: [String: [Bar]] = [:]
    private var fetchedAt: [String: Date] = [:]
    private var order: [String] = []
    private var inflight: [String: InFlight] = [:]
    private var nextInflightID: UInt64 = 0
    private var epoch: UInt64 = 0

    init(api: BarsAPI) {
        self.api = api
    }

    func reset() {
        epoch += 1
        cache = [:]
        fetchedAt = [:]
        order = []
        inflight = [:]
    }

    func cached(symbol: String, date: String, session: BarSession) -> [Bar]? {
        let symbol = Self.normalized(symbol, session: session)
        return cache[cacheKey(symbol: symbol, date: date, session: session)]
    }

    func cachedDaily(symbol: String) -> [Bar]? {
        cache[dailyKey(symbol: Self.normalized(symbol, session: .regular))]
    }

    func load(
        symbol: String,
        date: String,
        session: BarSession,
        caches: Bool = true,
        force: Bool = false,
        now: Date = Date()
    ) async throws -> [Bar] {
        try Task.checkCancellation()
        let symbol = Self.normalized(symbol, session: session)
        let storeKey = cacheKey(symbol: symbol, date: date, session: session)
        let inflightKey = caches ? storeKey : "\(storeKey):ephemeral"
        if let existing = inflight[inflightKey], !existing.task.isCancelled {
            existing.addWaiter()
            return try await waitForInFlight(existing)
        }

        if caches, !force,
           let fetched = fetchedAt[storeKey],
           MarketClock.isSameUSMinute(fetched, now)
        {
            touch(storeKey)
            return cache[storeKey] ?? []
        }

        let existing = caches ? (cache[storeKey] ?? []) : []
        let startTime: String? = {
            guard caches, let last = existing.last else { return nil }
            return MarketClock.usTimeString(from: last.time)
        }()

        let epoch = self.epoch
        nextInflightID += 1
        let inflightID = nextInflightID
        let task = Task { @MainActor in
            defer {
                if self.inflight[inflightKey]?.id == inflightID {
                    self.inflight[inflightKey] = nil
                }
            }
            try Task.checkCancellation()
            let dtos = try await self.fetchDTOs(
                session: session,
                symbol: symbol,
                date: date,
                startTime: startTime
            )
            try Task.checkCancellation()
            guard self.epoch == epoch else { throw AppError.cancelled }
            let incoming = Self.capped(MinuteBars.fromDTOs(dtos, date: date))
            if caches {
                let latestExisting = self.cache[storeKey] ?? []
                if incoming.isEmpty, !latestExisting.isEmpty {
                    self.fetchedAt[storeKey] = now
                    self.touch(storeKey)
                    return latestExisting
                }
                let merged = latestExisting.isEmpty
                    ? incoming
                    : Self.capped(MinuteBars.mergeIncremental(latestExisting, with: incoming))
                self.remember(storeKey, bars: merged, at: now)
                return merged
            }
            return incoming
        }
        let item = InFlight(id: inflightID, task: task)
        inflight[inflightKey] = item
        return try await waitForInFlight(item)
    }

    private func fetchDTOs(
        session: BarSession,
        symbol: String,
        date: String,
        startTime: String?
    ) async throws -> [BarDTO] {
        switch session {
        case .regular:
            return try await api.intraday(symbol: symbol, date: date, startTime: startTime)
        case .premarket:
            return try await api.preMarket(symbol: symbol, date: date, startTime: startTime)
        case .aftermarket:
            return try await api.afterMarket(symbol: symbol, date: date, startTime: startTime)
        case .index:
            return try await api.indexIntraday(symbol: symbol, date: date)
        }
    }

    private func waitForInFlight(_ item: InFlight) async throws -> [Bar] {
        let bars = try await withTaskCancellationHandler {
            try await item.task.value
        } onCancel: {
            item.cancelWaiter()
        }
        try Task.checkCancellation()
        return bars
    }

    func loadDaily(symbol: String, startDate: String) async throws -> [Bar] {
        let symbol = Self.normalized(symbol, session: .regular)
        let storeKey = dailyKey(symbol: symbol)
        let inflightKey = "\(storeKey):\(startDate)"
        if let existing = inflight[inflightKey] {
            return try await existing.task.value
        }

        let epoch = self.epoch
        nextInflightID += 1
        let inflightID = nextInflightID
        let task = Task { @MainActor in
            defer {
                if self.inflight[inflightKey]?.id == inflightID {
                    self.inflight[inflightKey] = nil
                }
            }
            let dtos = try await self.api.daily(symbol: symbol, startDate: startDate)
            guard self.epoch == epoch else { throw AppError.cancelled }
            let incoming = DailyBars.fromDTOs(dtos)
            if incoming.isEmpty, let existing = self.cache[storeKey], !existing.isEmpty {
                return existing
            }
            let bars = DailyBars.merge(self.cache[storeKey] ?? [], with: incoming)
            self.remember(storeKey, bars: bars, at: Date())
            return bars
        }
        inflight[inflightKey] = InFlight(id: inflightID, task: task)
        return try await task.value
    }

    private func remember(_ key: String, bars: [Bar], at now: Date) {
        cache[key] = bars
        fetchedAt[key] = now
        touch(key)
        while order.count > Self.maxBuckets {
            let evicted = order.removeFirst()
            cache[evicted] = nil
            fetchedAt[evicted] = nil
        }
    }

    private func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private static func capped(_ bars: [Bar]) -> [Bar] {
        guard bars.count > maxBarsPerBucket else { return bars }
        return Array(bars.suffix(maxBarsPerBucket))
    }

    private func cacheKey(symbol: String, date: String, session: BarSession) -> String {
        "us:\(symbol):\(date):\(session.rawValue):1Min"
    }

    private func dailyKey(symbol: String) -> String {
        "us:\(symbol):daily:1Day"
    }

    private static func normalized(_ symbol: String, session: BarSession) -> String {
        session == .index ? BarSession.indexSymbol : SymbolCode.normalize(symbol)
    }
}

private final class InFlight {
    let id: UInt64
    let task: Task<[Bar], Error>
    private let lock = NSLock()
    private var waiters = 1

    init(id: UInt64, task: Task<[Bar], Error>) {
        self.id = id
        self.task = task
    }

    func addWaiter() {
        lock.lock()
        waiters += 1
        lock.unlock()
    }

    func cancelWaiter() {
        lock.lock()
        waiters -= 1
        let abandoned = waiters <= 0
        lock.unlock()
        if abandoned {
            task.cancel()
        }
    }
}

enum BarSession: String, Equatable, Hashable {
    case regular
    case premarket
    case aftermarket
    case index

    static let indexSymbol = "COMP"

    static func isIndexSymbol(_ raw: String) -> Bool {
        let symbol = SymbolCode.normalize(raw)
        return symbol == indexSymbol || symbol == "NASDAQ"
    }

    var clockWindow: MarketClock.USSessionWindow {
        switch self {
        case .regular, .index: return .regular
        case .premarket: return .premarket
        case .aftermarket: return .aftermarket
        }
    }
}
