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
        cache[cacheKey(symbol: SymbolCode.normalize(symbol), date: date, session: session)]
    }

    func load(symbol: String, date: String, session: BarSession) async throws -> [Bar] {
        let symbol = SymbolCode.normalize(symbol)
        let key = cacheKey(symbol: symbol, date: date, session: session)
        if let existing = inflight[key] {
            return try await existing.task.value
        }

        let epoch = self.epoch
        nextInflightID += 1
        let inflightID = nextInflightID
        let task = Task { @MainActor in
            defer {
                if self.inflight[key]?.id == inflightID {
                    self.inflight[key] = nil
                }
            }
            let dtos: [BarDTO]
            switch session {
            case .regular:
                dtos = try await self.api.intraday(symbol: symbol, date: date)
            case .premarket:
                dtos = try await self.api.preMarket(symbol: symbol, date: date)
            case .aftermarket:
                dtos = try await self.api.afterMarket(symbol: symbol, date: date)
            }
            guard self.epoch == epoch else { throw AppError.cancelled }
            let bars = Self.capped(MinuteBars.fromDTOs(dtos, date: date))
            if bars.isEmpty, let existing = self.cache[key], !existing.isEmpty {
                return existing
            }
            self.remember(key, bars: bars)
            return bars
        }
        inflight[key] = InFlight(id: inflightID, task: task)
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
}

private struct InFlight {
    var id: UInt64
    var task: Task<[Bar], Error>
}

enum BarSession: String, Equatable, Hashable {
    case regular
    case premarket
    case aftermarket

    var clockWindow: MarketClock.USSessionWindow {
        switch self {
        case .regular: return .regular
        case .premarket: return .premarket
        case .aftermarket: return .aftermarket
        }
    }
}
