import Foundation

@MainActor
final class ScreenerStore: ObservableObject {
    @Published private(set) var kind: ScreenerKind?
    @Published var query = ScreenerQuery.defaults(for: .yahoo)
    @Published private(set) var rows: [SymbolSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?

    private let api: ScreenerAPI
    private let now: () -> Date
    private var epoch: UInt64 = 0
    private var requestID: UInt64 = 0
    private var pending: (ScreenerKind, ScreenerQuery)?
    private var drainTask: Task<Void, Never>?
    private var queries: [ScreenerKind: ScreenerQuery] = [:]

    init(api: ScreenerAPI, now: @escaping () -> Date = { Date() }) {
        self.api = api
        self.now = now
    }

    func reset() {
        epoch += 1
        requestID += 1
        pending = nil
        kind = nil
        query = ScreenerQuery.defaults(for: .yahoo)
        queries.removeAll()
        rows = []
        errorText = nil
        isLoading = false
    }

    func appear(_ kind: ScreenerKind) async {
        await load(kind, query: kind == self.kind ? query : queries[kind])
    }

    func load(_ kind: ScreenerKind, query: ScreenerQuery? = nil) async {
        var resolved = query ?? queries[kind] ?? ScreenerQuery.defaults(for: kind, now: now())
        resolved.pinHiddenSession(for: kind, now: now())
        queries[kind] = resolved
        requestID += 1
        self.kind = kind
        self.query = resolved
        rows = []
        errorText = nil
        isLoading = true
        pending = (kind, resolved)
        await waitForIdleDrain()
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
                let rows = try await Self.fetch(work.0, query: work.1, api: api, now: now())
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
        api: ScreenerAPI,
        now: Date
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
                "time": query.time,
                "timeFrame": query.timeFrame,
                "barCount": query.barCount,
                "minPrice": query.minPrice,
                "minVolume": query.minVolume,
            ])
        case .priceSlope:
            let endTime = try MarketClock.resolvedPriceSlopeEndTime(query.endTime, now: now)
            dtos = try await api.priceSlope(query: [
                "market": query.market,
                "date": query.date,
                "endTime": endTime,
                "spanMinutes": query.spanMinutes,
                "direction": query.direction,
                "minPrice": query.minPrice,
                "minVolume": query.minVolume,
            ])
        case .premarket:
            dtos = try await api.premarketIndicator(query: [
                "direction": query.direction,
                "period": query.spanMinutes,
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
                "returnCount": "50",
            ])
        case .rsiAdx:
            let rsi = ScreenerRSIRange(rawValue: query.rsiRange) ?? .from50to60
            let adx = ScreenerADXRange(rawValue: query.adxRange) ?? .from20to30
            dtos = try await api.rsiAdx(query: [
                "rsiLow": rsi.low,
                "rsiHigh": rsi.high,
                "adxLow": adx.low,
                "adxHigh": adx.high,
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
