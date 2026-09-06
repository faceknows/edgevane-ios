import Foundation

@MainActor
final class SymbolSummaryStore: ObservableObject {
    @Published private(set) var isLookingUp = false

    private let api: ScreenerAPI
    private let cacheTTL: TimeInterval
    private let now: () -> Date
    private var cache: [String: CacheEntry] = [:]
    private var inflight: [String: InFlight] = [:]
    private var nextInflightID: UInt64 = 0
    private var epoch: UInt64 = 0
    private var lookupGeneration: UInt64 = 0
    private var lookupCount = 0

    init(
        api: ScreenerAPI,
        cacheTTL: TimeInterval = 60,
        now: @escaping () -> Date = Date.init
    ) {
        self.api = api
        self.cacheTTL = cacheTTL
        self.now = now
    }

    func reset() {
        epoch += 1
        lookupGeneration += 1
        cache = [:]
        inflight = [:]
        lookupCount = 0
        isLookingUp = false
    }

    func lookup(_ raw: String, forceRefresh: Bool = false) async throws -> SymbolSummary {
        let symbol = SymbolCode.normalize(raw)
        guard SymbolCode.isValid(symbol) else {
            throw AppError.http(status: 404, message: L10n.Market.unknownSymbol, errorCode: nil)
        }
        if !forceRefresh, let cached = cache[symbol], !cached.isExpired(now: now(), ttl: cacheTTL) {
            return cached.summary
        }
        if let existing = inflight[symbol] {
            return try await existing.task.value
        }

        let epoch = self.epoch
        let lookupGeneration = self.lookupGeneration
        beginLookup()
        let task = Task { @MainActor in
            let rows = try await self.api.summaries(symbols: symbol).map(SymbolSummary.init(dto:))
            guard self.epoch == epoch else { throw AppError.cancelled }
            guard let match = rows.first(where: { $0.symbol == symbol }) else {
                throw AppError.http(status: 404, message: L10n.Market.unknownSymbol, errorCode: nil)
            }
            self.cache[symbol] = CacheEntry(summary: match, fetchedAt: self.now())
            return match
        }
        nextInflightID += 1
        let inflightID = nextInflightID
        inflight[symbol] = InFlight(id: inflightID, task: task)
        defer {
            if inflight[symbol]?.id == inflightID {
                inflight[symbol] = nil
            }
            endLookup(generation: lookupGeneration)
        }
        return try await task.value
    }

    private func beginLookup() {
        lookupCount += 1
        isLookingUp = true
    }

    private func endLookup(generation: UInt64) {
        guard lookupGeneration == generation else { return }
        lookupCount = max(0, lookupCount - 1)
        isLookingUp = lookupCount > 0
    }
}

private struct InFlight {
    var id: UInt64
    var task: Task<SymbolSummary, Error>
}

private struct CacheEntry {
    var summary: SymbolSummary
    var fetchedAt: Date

    func isExpired(now: Date, ttl: TimeInterval) -> Bool {
        now.timeIntervalSince(fetchedAt) >= ttl
    }
}
