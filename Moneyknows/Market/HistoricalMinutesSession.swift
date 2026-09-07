import Foundation

@MainActor
final class HistoricalMinutesSession: ObservableObject {
    @Published var draftSymbol = ""
    @Published var dateString: String
    @Published var interval: MinuteInterval = .five
    @Published var style: ChartStyle = .candle
    @Published var showVWAP = true
    @Published private(set) var symbol = ""
    @Published private(set) var summary: SymbolSummary?
    @Published private(set) var regularBars: [Bar] = []
    @Published private(set) var preBars: [Bar] = []
    @Published private(set) var afterBars: [Bar] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLookingUp = false
    @Published private(set) var errorText: String?

    let dayFills = DayFillsSession()
    private var lookupID: UInt64 = 0
    private var loadID: UInt64 = 0

    var pickerDate: Date {
        get { MarketClock.date(fromUSDate: dateString) ?? Date() }
        set { dateString = MarketClock.usDateString(from: newValue) }
    }

    var regularModel: ChartModel {
        MinuteChartAssembler.model(
            bars1m: regularBars,
            interval: interval,
            style: style,
            showVWAP: showVWAP,
            previousClose: nil,
            sessionOpen: nil,
            markers: dayFills.markers(bars: regularBars, session: .regular),
            followLatest: false
        )
    }

    var preModel: ChartModel {
        MinuteChartAssembler.extendedHours(
            bars1m: preBars,
            markers: dayFills.markers(bars: preBars, session: .premarket)
        )
    }

    var afterModel: ChartModel {
        MinuteChartAssembler.extendedHours(
            bars1m: afterBars,
            markers: dayFills.markers(bars: afterBars, session: .aftermarket)
        )
    }

    init(now: Date = Date()) {
        dateString = MarketClock.lastTradingDate(from: now)
    }

    func submit(
        lookup: (String) async throws -> SymbolSummary,
        store: BarStore,
        trading: TradingSession
    ) async {
        errorText = nil
        let raw = SymbolCode.normalize(draftSymbol)
        lookupID += 1
        loadID += 1
        let lookupID = self.lookupID
        isLoading = false
        guard SymbolCode.isValid(raw) else {
            isLookingUp = false
            errorText = L10n.Market.invalidSymbol
            return
        }
        isLookingUp = true
        do {
            let summary = try await lookup(raw)
            guard self.lookupID == lookupID else { return }
            isLookingUp = false
            self.summary = summary
            symbol = summary.symbol
            draftSymbol = summary.symbol
            await reload(store: store, trading: trading)
        } catch {
            guard self.lookupID == lookupID else { return }
            isLookingUp = false
            isLoading = false
            if error.isCancellation { return }
            errorText = UserFacingError.message(from: error) ?? L10n.Market.unknownSymbol
        }
    }

    func reload(store: BarStore, trading: TradingSession) async {
        guard !symbol.isEmpty, !dateString.isEmpty else { return }
        loadID += 1
        let loadID = self.loadID
        let symbol = self.symbol
        let date = dateString
        isLoading = true
        errorText = nil
        dayFills.reset()
        defer {
            if self.loadID == loadID {
                isLoading = false
            }
        }
        async let regular = load(session: .regular, symbol: symbol, date: date, store: store)
        async let pre = load(session: .premarket, symbol: symbol, date: date, store: store)
        async let after = load(session: .aftermarket, symbol: symbol, date: date, store: store)
        let bars = await (regular, pre, after)
        guard self.loadID == loadID else { return }
        switch bars.0 {
        case let .success(value):
            regularBars = value
        case let .failure(error):
            if !error.isCancellation {
                errorText = UserFacingError.message(from: error)
            }
            regularBars = []
        }
        preBars = (try? bars.1.get()) ?? []
        afterBars = (try? bars.2.get()) ?? []
        await dayFills.load(symbol: symbol, day: date, trading: trading)
        guard self.loadID == loadID else { return }
        objectWillChange.send()
    }

    func reloadFills(trading: TradingSession) async {
        if !trading.hasAccount || symbol.isEmpty || dateString.isEmpty {
            dayFills.reset()
            objectWillChange.send()
            return
        }
        await dayFills.load(symbol: symbol, day: dateString, trading: trading)
        objectWillChange.send()
    }

    func refreshFills(trading: TradingSession) {
        dayFills.refresh(orders: trading.orders.orders, trading: trading)
        objectWillChange.send()
    }

    private func load(
        session: BarSession,
        symbol: String,
        date: String,
        store: BarStore
    ) async -> Result<[Bar], Error> {
        do {
            return .success(try await store.load(symbol: symbol, date: date, session: session, caches: false))
        } catch {
            return .failure(error)
        }
    }
}
