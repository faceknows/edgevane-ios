import Foundation

@MainActor
final class ScreenerStore: ObservableObject {
    @Published private(set) var kind: ScreenerKind?
    @Published var query = ScreenerQuery.defaults(for: .yahoo)
    @Published private(set) var rows: [SymbolSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?

    private let api: ScreenerAPI
    private var epoch: UInt64 = 0
    private var requestID: UInt64 = 0
    private var pending: (ScreenerKind, ScreenerQuery)?
    private var drainTask: Task<Void, Never>?

    init(api: ScreenerAPI) {
        self.api = api
    }

    func reset() {
        epoch += 1
        requestID += 1
        pending = nil
        kind = nil
        rows = []
        errorText = nil
        isLoading = false
    }

    func appear(_ kind: ScreenerKind) async {
        await load(kind, query: self.kind == kind ? query : nil)
    }

    func load(_ kind: ScreenerKind, query: ScreenerQuery? = nil) async {
        let resolved = query ?? (self.kind == kind ? self.query : ScreenerQuery.defaults(for: kind))
        requestID += 1
        self.kind = kind
        self.query = resolved
        rows = []
        errorText = nil
        isLoading = true
        pending = (kind, resolved)
        await waitForIdleDrain()
    }

    func applyPriceSlope(_ query: ScreenerQuery) async {
        await load(.priceSlope, query: query)
    }

    private func waitForIdleDrain() async {
        while pending != nil {
            if let drainTask {
                await drainTask.value
            } else {
                let task = Task { await self.runDrain() }
                drainTask = task
                await task.value
            }
        }
    }

    private func runDrain() async {
        defer { drainTask = nil }
        while let work = takePending() {
            let requestID = self.requestID
            let epoch = self.epoch
            do {
                let rows = try await Self.fetch(work.0, query: work.1, api: api)
                guard isCurrent(epoch: epoch, requestID: requestID), pending == nil else { continue }
                self.rows = rows
                isLoading = false
            } catch {
                guard isCurrent(epoch: epoch, requestID: requestID), pending == nil else { continue }
                isLoading = false
                if error.isCancellation { return }
                rows = []
                errorText = UserFacingError.message(from: error)
                AppLog.market.error("screener \(work.0.rawValue, privacy: .public) failed")
            }
        }
    }

    private func takePending() -> (ScreenerKind, ScreenerQuery)? {
        let next = pending
        pending = nil
        return next
    }

    private func isCurrent(epoch: UInt64, requestID: UInt64) -> Bool {
        self.epoch == epoch && self.requestID == requestID
    }

    private static func fetch(
        _ kind: ScreenerKind,
        query: ScreenerQuery,
        api: ScreenerAPI
    ) async throws -> [SymbolSummary] {
        let dtos: [SymbolSummaryDTO]
        switch kind {
        case .yahoo:
            dtos = try await api.yahooScreener(
                market: query.market,
                scrIds: query.scrIds,
                count: query.count
            )
        case .momentum:
            dtos = try await api.topMomentum(query: [
                "market": query.market,
                "date": query.date,
                "direction": query.direction,
                "timeFrame": query.timeFrame,
                "minVolume": query.minVolume,
            ])
        case .atr:
            dtos = try await api.topATR(query: [
                "market": query.market,
                "date": query.date,
                "timeFrame": query.timeFrame,
                "barCount": query.barCount,
                "minPrice": query.minPrice,
                "minVolume": query.minVolume,
            ])
        case .priceSlope:
            let endTime = try MarketClock.resolvedPriceSlopeEndTime(query.endTime)
            dtos = try await api.priceSlope(query: [
                "market": query.market,
                "date": query.date,
                "endTime": endTime,
                "spanMinutes": query.spanMinutes,
                "direction": query.direction,
                "minPrice": query.minPrice,
                "minVolume": query.minVolume,
            ])
        case .stair:
            dtos = try await api.stairSetups(query: [
                "market": query.market,
                "date": query.date,
                "timeFrame": query.timeFrame,
                "barCount": query.barCount,
                "minPrice": query.minPrice,
                "minVolume": query.minVolume,
                "direction": query.direction,
            ])
        case .volume:
            dtos = try await api.topVolumes(query: [
                "market": query.market,
                "minVolume": query.minVolume,
                "returnCount": query.returnCount,
            ])
        case .rsiAdx:
            dtos = try await api.rsiAdx(query: [
                "rsiLow": query.rsiLow,
                "rsiHigh": query.rsiHigh,
                "adxLow": query.adxLow,
                "adxHigh": query.adxHigh,
                "diGap": query.diGap,
                "direction": query.direction,
                "timeFrame": query.timeFrame,
            ])
        case .ibkr:
            dtos = try await api.ibkrScreener(query: [
                "date": query.date,
                "type": query.ibkrType,
                "filters": query.ibkrFilters,
            ])
        }
        let rows = dtos.map(SymbolSummary.init(dto:))
        switch kind {
        case .ibkr:
            return rows.sorted { ($0.volume ?? 0) > ($1.volume ?? 0) }
        default:
            return rows
        }
    }
}
