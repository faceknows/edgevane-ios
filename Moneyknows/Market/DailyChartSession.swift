import Foundation

@MainActor
final class DailyChartSession: ObservableObject {
    @Published var style: ChartStyle = .candle
    @Published private(set) var bars: [Bar] = []
    @Published private(set) var isLoading = true
    @Published private(set) var isPaging = false
    @Published private(set) var errorText: String?

    private var symbol = ""
    private(set) var loadID: UInt64 = 0
    private var store: BarStore?
    private var hasMore = true
    private var lastOlderStartDate: String?

    static func taskID(symbol: String, enabled: Bool) -> String {
        "\(SymbolCode.normalize(symbol))|\(enabled)"
    }

    var model: ChartModel {
        DailyChartAssembler.model(
            bars: bars,
            style: style,
            showVolume: !BarSession.isIndexSymbol(symbol),
            seriesID: ChartSeriesIdentity.id(symbol: symbol, session: "daily")
        )
    }

    func reset() {
        loadID += 1
        bars = []
        errorText = nil
        isLoading = true
        isPaging = false
        hasMore = true
        lastOlderStartDate = nil
        symbol = ""
        store = nil
    }

    func start(symbol: String, store: BarStore, now: Date = Date()) async {
        loadID += 1
        let loadID = self.loadID
        let next = SymbolCode.normalize(symbol)
        self.symbol = next
        self.store = store
        errorText = nil
        isPaging = false
        hasMore = true
        lastOlderStartDate = nil
        bars = store.cachedDaily(symbol: next) ?? []
        isLoading = bars.isEmpty
        await refreshLatest(now: now, showLoading: bars.isEmpty, force: false, loadID: loadID)
    }

    func retry(now: Date = Date()) async {
        await refreshLatest(now: now, showLoading: bars.isEmpty, force: true, loadID: loadID)
    }

    func loadOlder() async {
        guard let store, !symbol.isEmpty, hasMore, !isPaging, let earliest = bars.first else { return }
        let earliestDay = MarketClock.usDateString(from: earliest.time)
        let startDate = MarketClock.addingCalendarDays(-DailyBars.pageCalendarDays, to: earliestDay)
        if lastOlderStartDate == startDate { return }
        lastOlderStartDate = startDate
        let loadID = self.loadID
        let symbol = self.symbol
        isPaging = true
        defer {
            if self.loadID == loadID {
                isPaging = false
            }
        }
        do {
            let loaded = try await store.loadDaily(symbol: symbol, startDate: startDate)
            guard self.loadID == loadID, self.symbol == symbol else { return }
            let older = loaded.filter { MarketClock.usDateString(from: $0.time) < earliestDay }
            if older.isEmpty {
                hasMore = false
            }
            bars = loaded
            errorText = nil
        } catch {
            guard self.loadID == loadID, self.symbol == symbol else { return }
            lastOlderStartDate = nil
            if error.isCancellation { return }
            errorText = UserFacingError.message(from: error)
            AppLog.market.error("daily bars older failed \(error.logCode, privacy: .public)")
        }
    }

    private func refreshLatest(now: Date, showLoading: Bool, force: Bool, loadID: UInt64) async {
        guard let store, !symbol.isEmpty else { return }
        guard force || DailyBars.needsLatest(bars, now: now) else { return }
        let symbol = self.symbol
        let startDate: String
        if let last = bars.last {
            startDate = MarketClock.usDateString(from: last.time)
        } else {
            startDate = MarketClock.addingCalendarDays(
                -DailyBars.pageCalendarDays,
                to: MarketClock.usDateString(from: now)
            )
        }
        if showLoading { isLoading = true }
        defer {
            if showLoading, self.loadID == loadID {
                isLoading = false
            }
        }
        do {
            let loaded = try await store.loadDaily(symbol: symbol, startDate: startDate)
            guard self.loadID == loadID, self.symbol == symbol else { return }
            bars = loaded
            errorText = nil
        } catch {
            guard self.loadID == loadID, self.symbol == symbol else { return }
            if error.isCancellation { return }
            errorText = UserFacingError.message(from: error)
            AppLog.market.error("daily bars failed \(error.logCode, privacy: .public)")
        }
    }
}
