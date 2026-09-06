import XCTest
@testable import Moneyknows

@MainActor
final class SymbolChartSessionTests: XCTestCase {
    func testDateRolloverClearsStaleSessionBars() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[{"d":"15:00","o":1,"h":1,"l":1,"c":1,"v":1}]"#.utf8)),
            .success(Data(#"[]"#.utf8)),
            .success(Data(#"[]"#.utf8)),
        ]
        let store = BarStore(api: BarsAPI(client: http))
        let session = SymbolChartSession()
        let task = Task {
            await session.start(symbol: "AAPL", store: store, now: Self.eastern(2026, 9, 4, 8))
        }
        await waitUntil { session.regularBars.count == 1 }
        XCTAssertEqual(session.regularDate, "2026-09-03")
        task.cancel()

        let rolled = session.syncDates(now: Self.eastern(2026, 9, 4, 10))
        XCTAssertTrue(rolled.contains(.regular))
        XCTAssertEqual(session.regularDate, "2026-09-04")
        XCTAssertTrue(session.regularBars.isEmpty)
    }

    func testStartOnNewSymbolAdoptsThatSymbolsCache() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[{"d":"15:00","o":1,"h":1,"l":1,"c":1,"v":1}]"#.utf8)),
            .success(Data(#"[]"#.utf8)),
            .success(Data(#"[]"#.utf8)),
            .success(Data(#"[{"d":"15:00","o":2,"h":2,"l":2,"c":2,"v":2}]"#.utf8)),
            .success(Data(#"[]"#.utf8)),
            .success(Data(#"[]"#.utf8)),
        ]
        let store = BarStore(api: BarsAPI(client: http))
        let session = SymbolChartSession()
        let now = Self.eastern(2026, 9, 4, 8)
        let first = Task { await session.start(symbol: "AAPL", store: store, now: now) }
        await waitUntil { session.regularBars.first?.close == 1 }
        session.updateSummary(SymbolSummary(symbol: "AAPL", previousClose: 100, sessionOpen: 101))
        XCTAssertEqual(session.regularModel.priceLines.map(\.id), ["prevClose", "sessionOpen"])
        first.cancel()

        http.pauseSends = true
        let second = Task { await session.start(symbol: "MSFT", store: store, now: now) }
        await waitUntil { session.regularBars.isEmpty }
        XCTAssertTrue(session.regularModel.priceLines.isEmpty)
        http.releasePaused()
        await waitUntil { session.regularBars.first?.close == 2 }
        second.cancel()
        XCTAssertEqual(session.regularBars.first?.close, 2)
    }

    func testRefreshFailureKeepsCachedBarsAndSurfacesError() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[{"d":"15:00","o":1,"h":1,"l":1,"c":1,"v":1}]"#.utf8)),
            .success(Data(#"[]"#.utf8)),
            .success(Data(#"[]"#.utf8)),
            .failure(AppError.network),
        ]
        let store = BarStore(api: BarsAPI(client: http))
        let session = SymbolChartSession()
        let task = Task {
            await session.start(symbol: "AAPL", store: store, now: Self.eastern(2026, 9, 4, 8))
        }
        await waitUntil { session.regularBars.first?.close == 1 }
        task.cancel()
        await session.retryRegular(now: Self.eastern(2026, 9, 4, 8))
        XCTAssertEqual(session.regularBars.first?.close, 1)
        XCTAssertEqual(session.errorText, L10n.Errors.network)
    }

    func testStaleDateResponseDoesNotReplaceRolledBars() async throws {
        let http = ScriptedHTTP()
        http.pauseSends = true
        http.rawResults = [
            .success(Data(#"[{"d":"15:00","o":1,"h":1,"l":1,"c":1,"v":1}]"#.utf8)),
            .success(Data(#"[]"#.utf8)),
            .success(Data(#"[]"#.utf8)),
        ]
        let store = BarStore(api: BarsAPI(client: http))
        let session = SymbolChartSession()
        let task = Task {
            await session.start(symbol: "AAPL", store: store, now: Self.eastern(2026, 9, 4, 8))
        }
        await waitUntil { http.requests.count == 1 }
        let rolled = session.syncDates(now: Self.eastern(2026, 9, 4, 10))
        XCTAssertTrue(rolled.contains(.regular))
        XCTAssertEqual(session.regularDate, "2026-09-04")
        http.releasePaused()
        await waitUntil { !session.isLoadingRegular }
        XCTAssertTrue(session.regularBars.isEmpty)
        task.cancel()
    }

    func testStartKeepsSummaryThatAlreadyMatchesSymbol() async throws {
        let http = ScriptedHTTP()
        http.pauseSends = true
        http.rawResults = [
            .success(Data(#"[{"d":"15:00","o":1,"h":1,"l":1,"c":1,"v":1}]"#.utf8)),
            .success(Data(#"[]"#.utf8)),
            .success(Data(#"[]"#.utf8)),
        ]
        let store = BarStore(api: BarsAPI(client: http))
        let session = SymbolChartSession()
        session.updateSummary(SymbolSummary(symbol: "MSFT", previousClose: 50, sessionOpen: 51))
        let task = Task {
            await session.start(symbol: "MSFT", store: store, now: Self.eastern(2026, 9, 4, 8))
        }
        await waitUntil { http.requests.count == 1 }
        XCTAssertEqual(session.regularModel.priceLines.map(\.id), ["prevClose", "sessionOpen"])
        task.cancel()
        http.releasePaused()
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
