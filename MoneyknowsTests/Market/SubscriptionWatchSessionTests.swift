import XCTest
@testable import Moneyknows

final class SparklineGeometryTests: XCTestCase {
    func testEmptyAndZeroSizeAreEmpty() {
        XCTAssertTrue(SparklineGeometry.points(values: [1, 2], in: .zero).isEmpty)
        XCTAssertTrue(SparklineGeometry.points(values: [], in: CGSize(width: 100, height: 40)).isEmpty)
        XCTAssertTrue(SparklineGeometry.points(values: [.nan], in: CGSize(width: 100, height: 40)).isEmpty)
    }

    func testHigherCloseMapsHigherOnScreen() {
        let points = SparklineGeometry.points(
            values: [1, 2, 3],
            in: CGSize(width: 102, height: 42),
            inset: 1
        )
        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points[0].x, 1, accuracy: 0.001)
        XCTAssertEqual(points[2].x, 101, accuracy: 0.001)
        XCTAssertGreaterThan(points[0].y, points[2].y)
        XCTAssertEqual(points[0].y, 41, accuracy: 0.001)
        XCTAssertEqual(points[2].y, 1, accuracy: 0.001)
    }

    func testFlatSeriesSitsOnMidline() {
        let points = SparklineGeometry.points(
            values: [10, 10, 10],
            in: CGSize(width: 100, height: 40),
            inset: 0
        )
        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points[0].y, 20, accuracy: 0.001)
        XCTAssertEqual(points[1].y, 20, accuracy: 0.001)
    }

    func testDeltaUsesBaselineThenFirstLast() {
        XCTAssertEqual(SparklineGeometry.delta(values: [10, 12], baseline: 11), 1)
        XCTAssertEqual(SparklineGeometry.delta(values: [10, 12]), 2)
        XCTAssertNil(SparklineGeometry.delta(values: []))
    }

    func testChartXDomainIsNonZeroForSinglePoint() {
        XCTAssertEqual(SparklineGeometry.chartXDomain(count: 0), -1...1)
        XCTAssertEqual(SparklineGeometry.chartXDomain(count: 1), -1...1)
        XCTAssertEqual(SparklineGeometry.chartXDomain(count: 2), 0...1)
        XCTAssertEqual(SparklineGeometry.chartXDomain(count: 5), 0...4)
    }

    func testMinuteClockParsesWithSessionDate() throws {
        let parsed = BarTime.parse("09:30", date: "2026-09-04")
        XCTAssertEqual(MarketClock.usTimeString(from: parsed!), "09:30")
        let dtos = try BarsAPI.decodeBars(from: Data(#"[{"d":"09:30","o":1,"h":2,"l":0.5,"c":1.5,"v":10}]"#.utf8))
        XCTAssertEqual(MinuteBars.fromDTOs(dtos, date: "2026-09-04").first?.close, 1.5)
    }
}

@MainActor
final class SubscriptionWatchSessionTests: XCTestCase {
    func testLoadsEachSymbolAndDropsRemoved() async throws {
        let http = ScriptedHTTP()
        http.rawResultsBySymbol = [
            "AAPL": Data(#"[{"d":"09:30","o":1,"h":1,"l":1,"c":10,"v":1}]"#.utf8),
            "MSFT": Data(#"[{"d":"09:30","o":2,"h":2,"l":2,"c":20,"v":1}]"#.utf8),
        ]
        let store = BarStore(api: BarsAPI(client: http))
        let session = SubscriptionWatchSession()
        await session.load(
            symbols: ["AAPL", "MSFT"],
            store: store,
            now: Self.eastern(2026, 9, 4, 12)
        )
        XCTAssertEqual(session.bars(for: "AAPL").first?.close, 10)
        XCTAssertEqual(session.bars(for: "MSFT").first?.close, 20)
        XCTAssertEqual(session.date, "2026-09-04")
        XCTAssertEqual(
            SubscriptionSparklineAssembler.closes(bars1m: session.bars(for: "AAPL")),
            [10]
        )

        http.rawResultsBySymbol = [
            "AAPL": Data(#"[{"d":"09:31","o":1,"h":1,"l":1,"c":11,"v":1}]"#.utf8),
        ]
        await session.load(
            symbols: ["AAPL"],
            store: store,
            now: Self.eastern(2026, 9, 4, 12)
        )
        XCTAssertTrue(session.bars(for: "MSFT").isEmpty)
        XCTAssertEqual(session.bars(for: "AAPL").first?.close, 11)
    }

    func testDateRolloverClearsStaleBars() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[{"d":"15:00","o":1,"h":1,"l":1,"c":1,"v":1}]"#.utf8)),
        ]
        let store = BarStore(api: BarsAPI(client: http))
        let session = SubscriptionWatchSession()
        await session.load(
            symbols: ["AAPL"],
            store: store,
            now: Self.eastern(2026, 9, 3, 16)
        )
        XCTAssertEqual(session.bars(for: "AAPL").count, 1)
        XCTAssertEqual(session.date, "2026-09-03")

        let rolled = session.syncDate(now: Self.eastern(2026, 9, 4, 10))
        XCTAssertTrue(rolled)
        XCTAssertEqual(session.date, "2026-09-04")
        XCTAssertTrue(session.bars(for: "AAPL").isEmpty)
    }

    func testAssemblerUsesCloseAndDropsNonFinite() {
        let now = Date()
        let bars = [
            Bar(time: now, open: 1, high: 1, low: 1, close: 1, volume: 1),
            Bar(time: now.addingTimeInterval(60), open: 1, high: 1, low: 1, close: .nan, volume: 1),
            Bar(time: now.addingTimeInterval(120), open: 2, high: 3, low: 1, close: 2.5, volume: 1),
        ]
        XCTAssertEqual(SubscriptionSparklineAssembler.closes(bars1m: bars, interval: .one), [1, 2.5])
        XCTAssertEqual(SubscriptionSparklineAssembler.closes(bars1s: bars, interval: .one, now: now.addingTimeInterval(120)), [1, 2.5])
    }

    func testSecondClosesKeepOnlyRecentWindow() {
        let now = Date()
        let bars = [
            Bar(time: now.addingTimeInterval(-11 * 60), open: 1, high: 1, low: 1, close: 1, volume: 1),
            Bar(time: now.addingTimeInterval(-30), open: 2, high: 2, low: 2, close: 2, volume: 1),
            Bar(time: now.addingTimeInterval(30), open: 3, high: 3, low: 3, close: 3, volume: 1),
        ]
        XCTAssertEqual(SubscriptionSparklineAssembler.recentSeconds(bars, now: now).map(\.close), [2])
        XCTAssertEqual(SubscriptionSparklineAssembler.closes(bars1s: bars, interval: .one, now: now), [2])
    }

    func testRefreshStaysWithinLimitUntilSlotsFree() async throws {
        let http = ScriptedHTTP()
        http.pauseSends = true
        let symbols = ["AAPL", "MSFT", "GOOG", "AMZN", "NVDA"]
        for symbol in symbols {
            http.rawResultsBySymbol[symbol] = Data(#"[{"d":"09:30","o":1,"h":1,"l":1,"c":1,"v":1}]"#.utf8)
        }
        let store = BarStore(api: BarsAPI(client: http))
        let session = SubscriptionWatchSession()
        let task = Task {
            await session.load(
                symbols: symbols,
                store: store,
                now: Self.eastern(2026, 9, 4, 12)
            )
        }
        await waitUntil { http.requests.count >= SubscriptionWatchSession.refreshLimit }
        XCTAssertEqual(http.requests.count, SubscriptionWatchSession.refreshLimit)
        http.releasePaused()
        await task.value
        XCTAssertEqual(http.requests.count, symbols.count)
        XCTAssertEqual(session.bars(for: "NVDA").first?.close, 1)
    }

    func testLoadFailureSurfacesRetryAndClosedMarketTickRetries() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [.failure(AppError.network)]
        let store = BarStore(api: BarsAPI(client: http))
        let session = SubscriptionWatchSession()
        await session.load(
            symbols: ["AAPL"],
            store: store,
            now: Self.eastern(2026, 9, 4, 12)
        )
        XCTAssertTrue(session.bars(for: "AAPL").isEmpty)
        XCTAssertEqual(session.failureText(for: "AAPL"), L10n.Errors.network)

        http.rawResults = [
            .success(Data(#"[{"d":"09:30","o":1,"h":1,"l":1,"c":10,"v":1}]"#.utf8)),
        ]
        await session.retry("AAPL")
        XCTAssertEqual(session.bars(for: "AAPL").first?.close, 10)
        XCTAssertNil(session.failureText(for: "AAPL"))
    }

    func testRefreshFailureKeepsCachedBarsAndSurfacesError() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[{"d":"09:30","o":1,"h":1,"l":1,"c":10,"v":1}]"#.utf8)),
        ]
        let store = BarStore(api: BarsAPI(client: http))
        let session = SubscriptionWatchSession()
        await session.load(
            symbols: ["AAPL"],
            store: store,
            now: Self.eastern(2026, 9, 4, 12)
        )
        XCTAssertEqual(session.bars(for: "AAPL").first?.close, 10)
        XCTAssertNil(session.failureText(for: "AAPL"))

        http.rawResults = [.failure(AppError.network)]
        await session.tick(now: Self.eastern(2026, 9, 4, 12, 1))
        XCTAssertEqual(session.bars(for: "AAPL").first?.close, 10)
        XCTAssertEqual(session.failureText(for: "AAPL"), L10n.Errors.network)
        XCTAssertFalse(SubscriptionSparklineAssembler.closes(bars1m: session.bars(for: "AAPL")).isEmpty)
    }

    func testClosedMarketTickRetriesFailedSymbol() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [.failure(AppError.network)]
        let store = BarStore(api: BarsAPI(client: http))
        let session = SubscriptionWatchSession()
        await session.load(
            symbols: ["AAPL"],
            store: store,
            now: Self.eastern(2026, 9, 4, 12)
        )
        XCTAssertEqual(session.failureText(for: "AAPL"), L10n.Errors.network)
        http.rawResults = [
            .success(Data(#"[{"d":"09:30","o":1,"h":1,"l":1,"c":11,"v":1}]"#.utf8)),
        ]
        await session.tick(now: Self.eastern(2026, 9, 4, 17))
        XCTAssertEqual(session.bars(for: "AAPL").first?.close, 11)
        XCTAssertNil(session.failureText(for: "AAPL"))
    }

    func testCancelledLoadDoesNotPublish() async throws {
        let http = ScriptedHTTP()
        http.pauseSends = true
        http.rawResultsBySymbol = [
            "AAPL": Data(#"[{"d":"09:30","o":1,"h":1,"l":1,"c":10,"v":1}]"#.utf8),
        ]
        let store = BarStore(api: BarsAPI(client: http))
        let session = SubscriptionWatchSession()
        let task = Task {
            await session.load(
                symbols: ["AAPL"],
                store: store,
                now: Self.eastern(2026, 9, 4, 12)
            )
        }
        await waitUntil { !http.requests.isEmpty }
        task.cancel()
        await task.value
        XCTAssertTrue(session.bars(for: "AAPL").isEmpty)
        XCTAssertNil(store.cached(symbol: "AAPL", date: "2026-09-04", session: .regular))
    }

    func testCancelledRetryDoesNotWriteCache() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [.failure(AppError.network)]
        let store = BarStore(api: BarsAPI(client: http))
        let session = SubscriptionWatchSession()
        let task = Task {
            await session.start(
                symbols: ["AAPL"],
                store: store,
                now: Self.eastern(2026, 9, 4, 12)
            )
        }
        await waitUntil { session.failureText(for: "AAPL") != nil }
        http.pauseSends = true
        http.rawResults = [
            .success(Data(#"[{"d":"09:30","o":1,"h":1,"l":1,"c":10,"v":1}]"#.utf8)),
        ]
        session.requestRetry("AAPL")
        await waitUntil { http.requests.count >= 2 }
        task.cancel()
        await task.value
        XCTAssertTrue(session.bars(for: "AAPL").isEmpty)
        XCTAssertNil(store.cached(symbol: "AAPL", date: "2026-09-04", session: .regular))
    }

    func testOverlappingStartKeepsRetryWorking() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [.failure(AppError.network)]
        let store = BarStore(api: BarsAPI(client: http))
        let session = SubscriptionWatchSession()
        let first = Task {
            await session.start(
                symbols: ["AAPL"],
                store: store,
                now: Self.eastern(2026, 9, 4, 12)
            )
        }
        await waitUntil { session.failureText(for: "AAPL") != nil }
        http.rawResults = [.failure(AppError.network)]
        let second = Task {
            await session.start(
                symbols: ["AAPL"],
                store: store,
                now: Self.eastern(2026, 9, 4, 12)
            )
        }
        await waitUntil { http.requests.count >= 2 }
        first.cancel()
        await first.value
        http.rawResults = [
            .success(Data(#"[{"d":"09:30","o":1,"h":1,"l":1,"c":10,"v":1}]"#.utf8)),
        ]
        session.requestRetry("AAPL")
        await waitUntil { session.bars(for: "AAPL").first?.close == 10 }
        XCTAssertNil(session.failureText(for: "AAPL"))
        second.cancel()
        await second.value
    }

    func testCancelledQueuedStartDoesNotStealRetryOwnership() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [.failure(AppError.network)]
        let store = BarStore(api: BarsAPI(client: http))
        let session = SubscriptionWatchSession()
        let owner = Task {
            await session.start(
                symbols: ["AAPL"],
                store: store,
                now: Self.eastern(2026, 9, 4, 12)
            )
        }
        await waitUntil { session.failureText(for: "AAPL") != nil }

        let stale = Task {
            await session.start(
                symbols: ["MSFT"],
                store: store,
                now: Self.eastern(2026, 9, 4, 12)
            )
        }
        stale.cancel()
        await stale.value

        http.rawResults = [
            .success(Data(#"[{"d":"09:30","o":1,"h":1,"l":1,"c":10,"v":1}]"#.utf8)),
        ]
        session.requestRetry("AAPL")
        await waitUntil { session.bars(for: "AAPL").first?.close == 10 }
        XCTAssertNil(session.failureText(for: "AAPL"))
        XCTAssertTrue(session.bars(for: "MSFT").isEmpty)
        owner.cancel()
        await owner.value
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
