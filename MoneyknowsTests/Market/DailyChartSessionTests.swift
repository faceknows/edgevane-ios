import XCTest
@testable import Moneyknows

@MainActor
final class DailyChartSessionTests: XCTestCase {
    func testStartSkipsNetworkWhenCachedBarIsLatestTradingDay() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[{"d":"2026-09-04","o":1,"h":1,"l":1,"c":1,"v":1}]"#.utf8)),
        ]
        let store = BarStore(api: BarsAPI(client: http))
        _ = try await store.loadDaily(symbol: "AAPL", startDate: "2026-05-27")
        let session = DailyChartSession()
        await session.start(symbol: "AAPL", store: store, now: Self.eastern(2026, 9, 4, 10))
        XCTAssertEqual(session.bars.map(\.close), [1])
        XCTAssertTrue(session.model.usesCalendarDays)
        XCTAssertTrue(session.model.showVolume)
        XCTAssertEqual(http.requests.count, 1)
        XCTAssertNil(session.errorText)
    }

    func testStartFetchesWhenTodayIsMissingAndSurfacesDecodingAsGenericError() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[{"d":"2026-09-03","o":1,"h":1,"l":1,"c":1,"v":1}]"#.utf8)),
            .success(Data(#"{"unexpected":true}"#.utf8)),
        ]
        let store = BarStore(api: BarsAPI(client: http))
        _ = try await store.loadDaily(symbol: "AAPL", startDate: "2026-05-27")
        let session = DailyChartSession()
        await session.start(symbol: "AAPL", store: store, now: Self.eastern(2026, 9, 4, 10))
        XCTAssertEqual(session.bars.map(\.close), [1])
        XCTAssertEqual(session.errorText, L10n.Errors.generic)
        XCTAssertEqual(http.requests.last?.path, "alpaca/market/daily-bars")
        XCTAssertEqual(http.requests.last?.query["startDate"], "2026-09-03")
        XCTAssertFalse(session.isLoading)
    }

    func testRetryReloadsLatestAndClearsError() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [
            .failure(AppError.decoding),
            .success(Data(#"[{"d":"2026-09-04","o":2,"h":2,"l":2,"c":2,"v":2}]"#.utf8)),
        ]
        let store = BarStore(api: BarsAPI(client: http))
        let session = DailyChartSession()
        await session.start(symbol: "AAPL", store: store, now: Self.eastern(2026, 9, 4, 10))
        XCTAssertEqual(session.errorText, L10n.Errors.generic)
        await session.retry(now: Self.eastern(2026, 9, 4, 10))
        XCTAssertEqual(session.bars.map(\.close), [2])
        XCTAssertNil(session.errorText)
    }

    func testLoadOlderPrependsHistoryAndStopsWhenEmpty() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[{"d":"2026-09-04","o":2,"h":2,"l":2,"c":2,"v":2}]"#.utf8)),
            .success(Data(#"[{"d":"2026-06-01","o":1,"h":1,"l":1,"c":1,"v":1},{"d":"2026-09-04","o":2,"h":2,"l":2,"c":2,"v":2}]"#.utf8)),
            .success(Data(#"[{"d":"2026-06-01","o":1,"h":1,"l":1,"c":1,"v":1},{"d":"2026-09-04","o":2,"h":2,"l":2,"c":2,"v":2}]"#.utf8)),
        ]
        let store = BarStore(api: BarsAPI(client: http))
        let session = DailyChartSession()
        await session.start(symbol: "AAPL", store: store, now: Self.eastern(2026, 9, 4, 10))
        XCTAssertEqual(session.bars.map(\.close), [2])
        await session.loadOlder()
        XCTAssertEqual(session.bars.map { MarketClock.usDateString(from: $0.time) }, ["2026-06-01", "2026-09-04"])
        XCTAssertEqual(http.requests.last?.query["startDate"], "2026-05-27")
        await session.loadOlder()
        XCTAssertEqual(http.requests.count, 3)
        await session.loadOlder()
        XCTAssertEqual(http.requests.count, 3)
    }

    func testIndexSymbolHidesVolume() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[{"d":"2026-09-04","o":1,"h":1,"l":1,"c":1,"v":1}]"#.utf8)),
        ]
        let store = BarStore(api: BarsAPI(client: http))
        let session = DailyChartSession()
        await session.start(symbol: "COMP", store: store, now: Self.eastern(2026, 9, 4, 10))
        XCTAssertFalse(session.model.showVolume)
        XCTAssertTrue(session.model.usesCalendarDays)
    }

    func testStartClearsStaleLoadingWhenNextSymbolIsCached() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[{"d":"2026-09-04","o":2,"h":2,"l":2,"c":2,"v":2}]"#.utf8)),
            .success(Data(#"[{"d":"2026-09-04","o":1,"h":1,"l":1,"c":1,"v":1}]"#.utf8)),
        ]
        let store = BarStore(api: BarsAPI(client: http))
        _ = try await store.loadDaily(symbol: "MSFT", startDate: "2026-05-27")
        http.pauseSends = true
        let session = DailyChartSession()
        let first = Task { await session.start(symbol: "AAPL", store: store, now: Self.eastern(2026, 9, 4, 10)) }
        await waitUntil { session.isLoading }
        await session.start(symbol: "MSFT", store: store, now: Self.eastern(2026, 9, 4, 10))
        XCTAssertFalse(session.isLoading)
        XCTAssertFalse(session.isPaging)
        XCTAssertEqual(session.bars.map(\.close), [2])
        http.releasePaused()
        await first.value
        XCTAssertFalse(session.isLoading)
        XCTAssertEqual(session.bars.map(\.close), [2])
    }

    func testStartClearsStalePagingSoHistoryCanLoadAgain() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[{"d":"2026-09-04","o":2,"h":2,"l":2,"c":2,"v":2}]"#.utf8)),
            .success(Data(#"[{"d":"2026-09-04","o":1,"h":1,"l":1,"c":1,"v":1}]"#.utf8)),
            .success(Data(#"[{"d":"2026-06-01","o":1,"h":1,"l":1,"c":1,"v":1},{"d":"2026-09-04","o":1,"h":1,"l":1,"c":1,"v":1}]"#.utf8)),
            .success(Data(#"[{"d":"2026-06-01","o":0.5,"h":0.5,"l":0.5,"c":0.5,"v":1},{"d":"2026-09-04","o":2,"h":2,"l":2,"c":2,"v":2}]"#.utf8)),
        ]
        let store = BarStore(api: BarsAPI(client: http))
        _ = try await store.loadDaily(symbol: "MSFT", startDate: "2026-05-27")
        let session = DailyChartSession()
        await session.start(symbol: "AAPL", store: store, now: Self.eastern(2026, 9, 4, 10))
        http.pauseSends = true
        let paging = Task { await session.loadOlder() }
        await waitUntil { session.isPaging }
        await session.start(symbol: "MSFT", store: store, now: Self.eastern(2026, 9, 4, 10))
        XCTAssertFalse(session.isPaging)
        XCTAssertFalse(session.isLoading)
        XCTAssertEqual(session.bars.map(\.close), [2])
        http.releasePaused()
        await paging.value
        XCTAssertFalse(session.isPaging)
        await session.loadOlder()
        XCTAssertEqual(session.bars.map { MarketClock.usDateString(from: $0.time) }, ["2026-06-01", "2026-09-04"])
        XCTAssertEqual(session.bars.last?.close, 2)
    }

    func testTaskIDIncludesSymbolAndEnabled() {
        XCTAssertEqual(
            DailyChartSession.taskID(symbol: "aapl", enabled: true),
            DailyChartSession.taskID(symbol: "AAPL", enabled: true)
        )
        XCTAssertNotEqual(
            DailyChartSession.taskID(symbol: "AAPL", enabled: true),
            DailyChartSession.taskID(symbol: "MSFT", enabled: true)
        )
        XCTAssertNotEqual(
            DailyChartSession.taskID(symbol: "AAPL", enabled: true),
            DailyChartSession.taskID(symbol: "AAPL", enabled: false)
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
