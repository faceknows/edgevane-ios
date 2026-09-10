import Foundation

@MainActor
final class BarStore: ObservableObject {
    static let maxBuckets = 240
    static let maxBarsPerBucket = 1000

    private let api: BarsAPI
    private var cache: [String: [Bar]] = [:]
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

    func load(symbol: String, date: String, session: BarSession, caches: Bool = true) async throws -> [Bar] {
        try Task.checkCancellation()
        let symbol = Self.normalized(symbol, session: session)
        let storeKey = cacheKey(symbol: symbol, date: date, session: session)
        let inflightKey = caches ? storeKey : "\(storeKey):ephemeral"
        if let existing = inflight[inflightKey], !existing.task.isCancelled {
            existing.addWaiter()
            return try await waitForInFlight(existing)
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
            try Task.checkCancellation()
            let dtos: [BarDTO]
            switch session {
            case .regular:
                dtos = try await self.api.intraday(symbol: symbol, date: date)
            case .premarket:
                dtos = try await self.api.preMarket(symbol: symbol, date: date)
            case .aftermarket:
                dtos = try await self.api.afterMarket(symbol: symbol, date: date)
            case .index:
                dtos = try await self.api.indexIntraday(symbol: symbol, date: date)
            }
            try Task.checkCancellation()
            guard self.epoch == epoch else { throw AppError.cancelled }
            let bars = Self.capped(MinuteBars.fromDTOs(dtos, date: date))
            if caches {
                if bars.isEmpty, let existing = self.cache[storeKey], !existing.isEmpty {
                    return existing
                }
                self.remember(storeKey, bars: bars)
            }
            return bars
        }
        let item = InFlight(id: inflightID, task: task)
        inflight[inflightKey] = item
        return try await waitForInFlight(item)
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
            self.remember(storeKey, bars: bars)
            return bars
        }
        inflight[inflightKey] = InFlight(id: inflightID, task: task)
        return try await task.value
    }

    private func remember(_ key: String, bars: [Bar]) {
        cache[key] = bars
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > Self.maxBuckets {
            let evicted = order.removeFirst()
            cache[evicted] = nil
        }
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
