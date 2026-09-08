import Foundation

@MainActor
final class IndexChartSession: ObservableObject {
    static let symbol = BarSession.indexSymbol

    @Published var interval: MinuteInterval = .five
    @Published var style: ChartStyle = .candle
    @Published private(set) var bars: [Bar] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?

    private var date = ""
    private(set) var loadID: UInt64 = 0
    private var store: BarStore?

    static func isIndexSymbol(_ raw: String) -> Bool {
        BarSession.isIndexSymbol(raw)
    }

    static func taskID(date: String, enabled: Bool) -> String {
        "\(date)|\(enabled)"
    }

    var model: ChartModel {
        MinuteChartAssembler.model(
            bars1m: bars,
            interval: interval,
            style: style,
            showVWAP: false,
            previousClose: nil,
            sessionOpen: nil,
            followLatest: false,
            showVolume: false
        )
    }

    func reset() {
        loadID += 1
        bars = []
        errorText = nil
        isLoading = false
        date = ""
        store = nil
    }

    func start(store: BarStore, date: String) async {
        loadID += 1
        let loadID = self.loadID
        self.store = store
        self.date = date
        errorText = nil
        bars = store.cached(symbol: Self.symbol, date: date, session: .index) ?? []
        await refresh(showLoading: true)
        guard self.loadID == loadID, !Task.isCancelled else { return }
        await poll()
    }

    func reload(date: String) async {
        self.date = date
        bars = store?.cached(symbol: Self.symbol, date: date, session: .index) ?? []
        await refresh(showLoading: true)
    }

    private func poll() async {
        let loadID = self.loadID
        while !Task.isCancelled {
            let delay = MarketClock.nanosecondsUntilNextMinute()
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            guard self.loadID == loadID, !Task.isCancelled else { return }
            let now = Date()
            if MarketClock.shouldPoll(session: .regular, date: date, now: now) {
                await refresh(showLoading: false)
            }
        }
    }

    private func refresh(showLoading: Bool) async {
        guard let store, !date.isEmpty else { return }
        let loadID = self.loadID
        let date = self.date
        if showLoading { isLoading = true }
        do {
            let bars = try await store.load(symbol: Self.symbol, date: date, session: .index)
            guard self.loadID == loadID, self.date == date else { return }
            self.bars = bars
            errorText = nil
            if showLoading { isLoading = false }
        } catch {
            guard self.loadID == loadID, self.date == date else { return }
            if showLoading { isLoading = false }
            if error.isCancellation { return }
            errorText = UserFacingError.message(from: error)
            AppLog.market.error("index bars failed")
        }
    }
}
