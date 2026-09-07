import Foundation

@MainActor
final class SymbolChartSession: ObservableObject {
    @Published var interval: MinuteInterval = .five
    @Published var style: ChartStyle = .candle
    @Published var showVWAP = true
    @Published var fills: [Fill] = []
    @Published private(set) var regularBars: [Bar] = []
    @Published private(set) var preBars: [Bar] = []
    @Published private(set) var afterBars: [Bar] = []
    @Published private(set) var isLoadingRegular = false
    @Published private(set) var errorText: String?

    @Published private(set) var regularDate = ""
    @Published private(set) var extendedDate = ""

    private var symbol = ""
    private var loadID: UInt64 = 0
    private var summary: SymbolSummary?
    private var store: BarStore?

    var regularModel: ChartModel {
        MinuteChartAssembler.model(
            bars1m: regularBars,
            interval: interval,
            style: style,
            showVWAP: showVWAP,
            previousClose: summary?.previousClose,
            sessionOpen: summary?.sessionOpen,
            markers: DayFills.markers(fills, bars: regularBars, session: .regular),
            followLatest: false
        )
    }

    var preModel: ChartModel {
        MinuteChartAssembler.extendedHours(
            bars1m: preBars,
            markers: DayFills.markers(fills, bars: preBars, session: .premarket)
        )
    }

    var afterModel: ChartModel {
        MinuteChartAssembler.extendedHours(
            bars1m: afterBars,
            markers: DayFills.markers(fills, bars: afterBars, session: .aftermarket)
        )
    }

    func updateSummary(_ summary: SymbolSummary?) {
        self.summary = summary
        objectWillChange.send()
    }

    func start(symbol: String, store: BarStore, now: Date = Date()) async {
        loadID += 1
        let loadID = self.loadID
        let next = SymbolCode.normalize(symbol)
        if next != self.symbol, summary?.symbol != next {
            summary = nil
        }
        self.symbol = next
        self.store = store
        errorText = nil
        fills = []
        _ = syncDates(now: now)
        adoptCachedBars()
        await refreshAll()
        guard self.loadID == loadID, !Task.isCancelled else { return }
        await poll()
    }

    func retryRegular(now: Date = Date()) async {
        _ = syncDates(now: now)
        await refresh(.regular, date: regularDate, showLoading: true)
    }

    func syncDates(now: Date = Date()) -> Set<BarSession> {
        var rolled: Set<BarSession> = []
        let nextRegular = MarketClock.lastTradingDate(from: now)
        let nextExtended = MarketClock.extendedHoursDate(from: now)
        if nextRegular != regularDate {
            regularDate = nextRegular
            regularBars = store?.cached(symbol: symbol, date: nextRegular, session: .regular) ?? []
            fills = []
            errorText = nil
            rolled.insert(.regular)
        }
        if nextExtended != extendedDate {
            extendedDate = nextExtended
            preBars = store?.cached(symbol: symbol, date: nextExtended, session: .premarket) ?? []
            afterBars = store?.cached(symbol: symbol, date: nextExtended, session: .aftermarket) ?? []
            fills = []
            rolled.insert(.premarket)
            rolled.insert(.aftermarket)
        }
        return rolled
    }

    private func adoptCachedBars() {
        regularBars = store?.cached(symbol: symbol, date: regularDate, session: .regular) ?? []
        preBars = store?.cached(symbol: symbol, date: extendedDate, session: .premarket) ?? []
        afterBars = store?.cached(symbol: symbol, date: extendedDate, session: .aftermarket) ?? []
    }

    private func refreshAll() async {
        await refresh(.regular, date: regularDate, showLoading: true)
        await refresh(.premarket, date: extendedDate, showLoading: false)
        await refresh(.aftermarket, date: extendedDate, showLoading: false)
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
            let rolled = syncDates(now: now)
            if rolled.contains(.regular) || shouldPoll(.regular, now: now) {
                await refresh(.regular, date: regularDate, showLoading: false)
            }
            if rolled.contains(.premarket) || shouldPoll(.premarket, now: now) {
                await refresh(.premarket, date: extendedDate, showLoading: false)
            }
            if rolled.contains(.aftermarket) || shouldPoll(.aftermarket, now: now) {
                await refresh(.aftermarket, date: extendedDate, showLoading: false)
            }
        }
    }

    private func shouldPoll(_ session: BarSession, now: Date) -> Bool {
        let date = session == .regular ? regularDate : extendedDate
        return MarketClock.shouldPoll(session: session.clockWindow, date: date, now: now)
    }

    private func refresh(_ session: BarSession, date: String, showLoading: Bool) async {
        guard let store, !symbol.isEmpty, !date.isEmpty else { return }
        let loadID = self.loadID
        let symbol = self.symbol
        let requestedDate = date
        if showLoading { isLoadingRegular = true }
        do {
            let bars = try await store.load(symbol: symbol, date: requestedDate, session: session)
            guard self.loadID == loadID else { return }
            guard self.symbol == symbol, requestedDate == currentDate(for: session) else {
                if showLoading { isLoadingRegular = false }
                return
            }
            apply(bars, session: session)
            if showLoading { isLoadingRegular = false }
        } catch {
            guard self.loadID == loadID else { return }
            guard self.symbol == symbol, requestedDate == currentDate(for: session) else {
                if showLoading { isLoadingRegular = false }
                return
            }
            if showLoading { isLoadingRegular = false }
            if error.isCancellation { return }
            if session == .regular {
                errorText = UserFacingError.message(from: error)
            }
            AppLog.market.error("bars \(session.rawValue, privacy: .public) failed")
        }
    }

    private func currentDate(for session: BarSession) -> String {
        session == .regular ? regularDate : extendedDate
    }

    private func apply(_ bars: [Bar], session: BarSession) {
        switch session {
        case .regular:
            regularBars = bars
            errorText = nil
        case .premarket:
            preBars = bars
        case .aftermarket:
            afterBars = bars
        case .index:
            break
        }
    }
}
