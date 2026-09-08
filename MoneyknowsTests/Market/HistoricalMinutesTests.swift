import XCTest
@testable import Moneyknows

@MainActor
final class HistoricalMinutesTests: XCTestCase {
    func testLoadDoesNotWriteDetailTodayCacheAndOverlaysFills() async {
        let http = ScriptedHTTP()
        http.rawResultsByPath = Self.sessionPayloads()
        let store = BarStore(api: BarsAPI(client: http))
        let trading = TradingSession(enablesPolling: false)
        let fake = FakeBrokerage(environment: .paper)
        let filledAt = Self.eastern(2026, 9, 4, 9, 30)
        fake.orderRows = [Self.filledOrder(id: "buy-1", filledAt: filledAt)]
        trading.use(fake)
        let session = HistoricalMinutesSession(now: Self.eastern(2026, 9, 4, 11))
        session.draftSymbol = "aapl"
        await session.submit(
            lookup: { _ in SymbolSummary(symbol: "AAPL", previousClose: 9, sessionOpen: 10) },
            store: store,
            trading: trading
        )
        XCTAssertEqual(session.symbol, "AAPL")
        XCTAssertEqual(session.dateString, "2026-09-04")
        XCTAssertEqual(session.regularBars.first?.close, 1.5)
        XCTAssertEqual(session.dayFills.fills.map(\.id), [Self.fillID("buy-1")])
        XCTAssertEqual(session.regularModel.markers.map(\.kind), [.buy])
        XCTAssertEqual(session.regularModel.markers.first?.position, .belowBar)
        XCTAssertTrue(session.regularModel.priceLines.isEmpty)
        XCTAssertTrue(session.regularModel.showVolume)
        XCTAssertTrue(session.preModel.showVolume)
        XCTAssertNil(store.cached(symbol: "AAPL", date: "2026-09-04", session: .regular))
        XCTAssertEqual(
            Set(http.requests.map(\.path)),
            [
                "alpaca/market/intraday-bars",
                "alpaca/market/intraday/pre/bars",
                "alpaca/market/intraday/after/bars",
            ]
        )
    }

    func testIncompleteFillHistoryKeepsBarsAndClearsRemoteMarkers() async {
        let http = ScriptedHTTP()
        http.rawResultsByPath = Self.sessionPayloads()
        let store = BarStore(api: BarsAPI(client: http))
        let trading = TradingSession(enablesPolling: false)
        let fake = FakeBrokerage(environment: .paper)
        fake.orderRows = [Self.filledOrder(id: "buy-1", filledAt: Self.eastern(2026, 9, 4, 9, 30))]
        fake.ordersError = AppError.orderHistoryIncomplete
        trading.use(fake)
        let session = HistoricalMinutesSession(now: Self.eastern(2026, 9, 4, 11))
        session.draftSymbol = "AAPL"
        await session.submit(
            lookup: { _ in SymbolSummary(symbol: "AAPL", previousClose: 9, sessionOpen: 10) },
            store: store,
            trading: trading
        )
        XCTAssertEqual(session.regularBars.first?.close, 1.5)
        XCTAssertNil(session.errorText)
        XCTAssertTrue(session.regularModel.markers.isEmpty)
        XCTAssertEqual(session.dayFills.errorText, L10n.Trading.orderHistoryIncomplete)
        XCTAssertTrue(session.dayFills.fills.isEmpty)
    }

    func testExtendedHoursFillsGoToMatchingChartsNotRegular() async {
        let http = ScriptedHTTP()
        http.rawResultsByPath = Self.sessionPayloads()
        let store = BarStore(api: BarsAPI(client: http))
        let trading = TradingSession(enablesPolling: false)
        let fake = FakeBrokerage(environment: .paper)
        fake.orderRows = [
            Self.filledOrder(id: "pre", side: .buy, filledAt: Self.eastern(2026, 9, 4, 8, 0)),
            Self.filledOrder(id: "regular", side: .buy, filledAt: Self.eastern(2026, 9, 4, 9, 30)),
            Self.filledOrder(id: "after", side: .sell, filledAt: Self.eastern(2026, 9, 4, 18, 0)),
        ]
        trading.use(fake)
        let session = HistoricalMinutesSession(now: Self.eastern(2026, 9, 4, 11))
        session.draftSymbol = "AAPL"
        await session.submit(
            lookup: { _ in SymbolSummary(symbol: "AAPL", previousClose: 9, sessionOpen: 10) },
            store: store,
            trading: trading
        )
        XCTAssertEqual(session.preModel.markers.map(\.id), [Self.fillID("pre")])
        XCTAssertEqual(session.regularModel.markers.map(\.id), [Self.fillID("regular")])
        XCTAssertEqual(session.afterModel.markers.map(\.id), [Self.fillID("after")])
        XCTAssertTrue(session.regularModel.priceLines.isEmpty)
    }

    func testGapFillStaysOffTheChart() async {
        let http = ScriptedHTTP()
        http.rawResultsByPath = Self.sessionPayloads()
        let store = BarStore(api: BarsAPI(client: http))
        let trading = TradingSession(enablesPolling: false)
        let fake = FakeBrokerage(environment: .paper)
        fake.orderRows = [
            Self.filledOrder(id: "gap", filledAt: Self.eastern(2026, 9, 4, 11, 0)),
        ]
        trading.use(fake)
        let session = HistoricalMinutesSession(now: Self.eastern(2026, 9, 4, 11))
        session.draftSymbol = "AAPL"
        await session.submit(
            lookup: { _ in SymbolSummary(symbol: "AAPL", previousClose: 9, sessionOpen: 10) },
            store: store,
            trading: trading
        )
        XCTAssertEqual(session.dayFills.fills.map(\.id), [Self.fillID("gap")])
        XCTAssertTrue(session.regularModel.markers.isEmpty)
        XCTAssertFalse(
            DayFills.isChartable(
                session.dayFills.fills[0],
                regularBars: session.regularBars,
                preBars: session.preBars,
                afterBars: session.afterBars
            )
        )
    }

    func testPaperFillsDoNotAppearOnLiveAccount() async {
        let paper = FakeBrokerage(environment: .paper)
        let live = FakeBrokerage(environment: .live)
        let filledAt = Self.eastern(2026, 9, 4, 11)
        paper.orderRows = [Self.filledOrder(id: "paper-fill", filledAt: filledAt)]
        live.orderRows = []
        let paperFills = try? await paper.fills(symbol: "AAPL", day: filledAt)
        let liveFills = try? await live.fills(symbol: "AAPL", day: filledAt)
        XCTAssertEqual(paperFills?.map(\.id), [Self.fillID("paper-fill")])
        XCTAssertEqual(liveFills?.map(\.id) ?? [], [])
    }

    func testAccountResetClearsHistoricalFills() async {
        let http = ScriptedHTTP()
        http.rawResultsByPath = Self.sessionPayloads()
        let store = BarStore(api: BarsAPI(client: http))
        let trading = TradingSession(enablesPolling: false)
        let fake = FakeBrokerage(environment: .paper)
        fake.orderRows = [Self.filledOrder(id: "keep", filledAt: Self.eastern(2026, 9, 4, 9, 30))]
        trading.use(fake)
        let session = HistoricalMinutesSession(now: Self.eastern(2026, 9, 4, 11))
        session.draftSymbol = "AAPL"
        await session.submit(
            lookup: { _ in SymbolSummary(symbol: "AAPL") },
            store: store,
            trading: trading
        )
        XCTAssertEqual(session.dayFills.fills.map(\.id), [Self.fillID("keep")])
        trading.reset()
        session.refreshFills(trading: trading)
        XCTAssertTrue(session.dayFills.fills.isEmpty)
        await session.reloadFills(trading: trading)
        XCTAssertTrue(session.dayFills.fills.isEmpty)
    }

    func testSupersededLookupDoesNotLeaveLookingUp() async {
        let http = ScriptedHTTP()
        http.rawResultsByPath = Self.sessionPayloads()
        let store = BarStore(api: BarsAPI(client: http))
        let trading = TradingSession(enablesPolling: false)
        let session = HistoricalMinutesSession(now: Self.eastern(2026, 9, 4, 11))
        let gate = LookupGate()
        session.draftSymbol = "aapl"
        let first = Task {
            await session.submit(lookup: { _ in try await gate.wait() }, store: store, trading: trading)
        }
        await waitUntil { gate.isWaiting }
        XCTAssertTrue(session.isLookingUp)
        session.draftSymbol = "msft"
        await session.submit(
            lookup: { _ in SymbolSummary(symbol: "MSFT") },
            store: store,
            trading: trading
        )
        XCTAssertEqual(session.symbol, "MSFT")
        XCTAssertFalse(session.isLookingUp)
        XCTAssertFalse(session.isLoading)
        gate.resume(SymbolSummary(symbol: "AAPL", previousClose: 9))
        await first.value
        XCTAssertEqual(session.symbol, "MSFT")
        XCTAssertFalse(session.isLookingUp)
        XCTAssertFalse(session.isLoading)
    }

    func testSupersededReloadDoesNotLeaveLoading() async {
        let http = ScriptedHTTP()
        http.rawResultsByPath = Self.sessionPayloads()
        let store = BarStore(api: BarsAPI(client: http))
        let trading = TradingSession(enablesPolling: false)
        let session = HistoricalMinutesSession(now: Self.eastern(2026, 9, 4, 11))
        session.draftSymbol = "AAPL"
        await session.submit(
            lookup: { _ in SymbolSummary(symbol: "AAPL") },
            store: store,
            trading: trading
        )
        XCTAssertFalse(session.isLoading)
        let requestCount = http.requests.count
        http.pauseSends = true
        let first = Task { await session.reload(store: store, trading: trading) }
        await waitUntil { session.isLoading }
        session.dateString = "2026-09-03"
        let second = Task { await session.reload(store: store, trading: trading) }
        await waitUntil { http.requests.count >= requestCount + 6 }
        http.releasePaused()
        await first.value
        await second.value
        XCTAssertFalse(session.isLoading)
        XCTAssertFalse(session.isLookingUp)
    }

    func testNewSearchDoesNotLeaveLoadingFromSupersededReload() async {
        let http = ScriptedHTTP()
        http.rawResultsByPath = Self.sessionPayloads()
        let store = BarStore(api: BarsAPI(client: http))
        let trading = TradingSession(enablesPolling: false)
        let session = HistoricalMinutesSession(now: Self.eastern(2026, 9, 4, 11))
        session.draftSymbol = "AAPL"
        await session.submit(
            lookup: { _ in SymbolSummary(symbol: "AAPL") },
            store: store,
            trading: trading
        )
        http.pauseSends = true
        let hanging = Task { await session.reload(store: store, trading: trading) }
        await waitUntil { session.isLoading }
        let gate = LookupGate()
        session.draftSymbol = "msft"
        let search = Task {
            await session.submit(lookup: { _ in try await gate.wait() }, store: store, trading: trading)
        }
        await waitUntil { session.isLookingUp }
        XCTAssertFalse(session.isLoading)
        http.releasePaused()
        await hanging.value
        XCTAssertFalse(session.isLoading)
        gate.resume(SymbolSummary(symbol: "MSFT"))
        await search.value
        XCTAssertEqual(session.symbol, "MSFT")
        XCTAssertFalse(session.isLookingUp)
        XCTAssertFalse(session.isLoading)
    }

    private static func fillID(_ orderId: String, day: String = "2026-09-04") -> String {
        DayFills.fillID(orderId: orderId, day: day)
    }

    private static func sessionPayloads() -> [String: Data] {
        [
            "alpaca/market/intraday-bars": Data(#"[{"d":"09:30","o":1,"h":1,"l":1,"c":1.5,"v":10}]"#.utf8),
            "alpaca/market/intraday/pre/bars": Data(#"[{"d":"08:00","o":1,"h":1,"l":1,"c":1,"v":1}]"#.utf8),
            "alpaca/market/intraday/after/bars": Data(#"[{"d":"18:00","o":1,"h":1,"l":1,"c":1,"v":1}]"#.utf8),
        ]
    }

    private static func filledOrder(
        id: String,
        side: OrderSide = .buy,
        filledAt: Date
    ) -> Order {
        Order(
            id: id,
            symbol: "AAPL",
            side: side,
            type: .limit,
            status: .filled,
            quantity: 1,
            filledQuantity: 1,
            limitPrice: 10,
            stopPrice: nil,
            filledAvgPrice: 10,
            timeInForce: "day",
            submittedAt: filledAt,
            updatedAt: filledAt,
            createdAt: filledAt,
            filledAt: filledAt,
            clientOrderId: nil,
            orderClass: nil,
            parentOrderId: nil
        )
    }

    private static func eastern(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        return calendar.date(from: parts)!
    }
}

@MainActor
private final class LookupGate {
    private var continuation: CheckedContinuation<SymbolSummary, Error>?

    var isWaiting: Bool { continuation != nil }

    func wait() async throws -> SymbolSummary {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(_ summary: SymbolSummary) {
        continuation?.resume(returning: summary)
        continuation = nil
    }
}
