import XCTest
@testable import Moneyknows

@MainActor
final class AppRouterTests: XCTestCase {
    func testOpenSymbolSetsOverlay() {
        let router = AppRouter()
        router.openSymbol(" aapl ")
        XCTAssertEqual(router.overlay, .symbol("AAPL"))
        router.openNews("n1")
        XCTAssertEqual(router.overlay, .news("n1"))
        router.handleNotification(
            AppNotification(
                id: "m",
                title: "T",
                body: "",
                sentAt: 1,
                data: [
                    "type": NotificationKind.marketTrendUpReversal.rawValue,
                    "symbols": "AMD,NVDA",
                    "screen": "Markets",
                ]
            ),
            versionPassed: true,
            signedIn: true
        )
        XCTAssertEqual(router.overlay, .screenerCatalog(["AMD", "NVDA"]))
        router.dismissOverlay()
        XCTAssertNil(router.overlay)
    }
}

final class SymbolCodeTests: XCTestCase {
    func testNormalizesAndRejectsInvalidSymbols() {
        XCTAssertEqual(SymbolCode.normalize("  aapl "), "AAPL")
        XCTAssertTrue(SymbolCode.isValid("AAPL"))
        XCTAssertTrue(SymbolCode.isValid("BRK.B"))
        XCTAssertFalse(SymbolCode.isValid(""))
        XCTAssertFalse(SymbolCode.isValid("AAPL AAPL AAPL"))
        XCTAssertFalse(SymbolCode.isValid("AA PL"))
    }
}

final class MarketClockTests: XCTestCase {
    func testFormatsUSEasternDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 9
        parts.day = 4
        parts.hour = 16
        parts.minute = 30
        let date = calendar.date(from: parts)!
        XCTAssertEqual(MarketClock.usDateString(from: date), "2026-09-04")
        XCTAssertEqual(MarketClock.usTimeString(from: date), "16:30")
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(utc.component(.hour, from: date), 20)
        XCTAssertNotNil(MarketClock.date(fromUSDate: "2026-09-04"))
        let bounds = MarketClock.easternDayBounds("2026-09-04")!
        XCTAssertEqual(MarketClock.usDateString(from: bounds.start), "2026-09-04")
        XCTAssertEqual(MarketClock.usTimeString(from: bounds.start), "00:00")
        XCTAssertEqual(MarketClock.usDateString(from: bounds.end), "2026-09-05")
        XCTAssertEqual(MarketClock.usTimeString(from: bounds.end), "00:00")
        XCTAssertEqual(MarketClock.normalizeEndTime(""), "")
        XCTAssertEqual(MarketClock.normalizeEndTime("9:30"), "09:30")
        XCTAssertEqual(MarketClock.normalizeEndTime("0930"), "09:30")
        XCTAssertNil(MarketClock.normalizeEndTime("abc"))
        XCTAssertTrue(MarketClock.isValidRegularSessionEndTime(""))
        XCTAssertTrue(MarketClock.isValidRegularSessionEndTime("09:30"))
        XCTAssertFalse(MarketClock.isValidRegularSessionEndTime("08:00"))
        XCTAssertEqual(MarketClock.regularSessionEndTime(from: date), "16:00")
        XCTAssertEqual(try MarketClock.resolvedPriceSlopeEndTime("", now: date), "16:00")
        XCTAssertEqual(try MarketClock.resolvedPriceSlopeEndTime("10:15", now: date), "10:15")
    }

    func testLastTradingDateSkipsWeekendsAndHolidays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            var parts = DateComponents()
            parts.year = year
            parts.month = month
            parts.day = day
            parts.hour = hour
            parts.minute = minute
            return calendar.date(from: parts)!
        }
        XCTAssertEqual(MarketClock.lastTradingDate(from: date(2026, 9, 4, 10)), "2026-09-04")
        XCTAssertEqual(MarketClock.lastTradingDate(from: date(2026, 9, 4, 9, 15)), "2026-09-03")
        XCTAssertEqual(MarketClock.lastTradingDate(from: date(2026, 9, 4, 9, 30)), "2026-09-04")
        XCTAssertEqual(MarketClock.lastTradingDate(from: date(2026, 9, 4, 8)), "2026-09-03")
        XCTAssertEqual(MarketClock.lastTradingDate(from: date(2026, 9, 5, 12)), "2026-09-04")
        XCTAssertEqual(MarketClock.lastTradingDate(from: date(2026, 9, 7, 10)), "2026-09-04")
        XCTAssertEqual(MarketClock.extendedHoursDate(from: date(2026, 9, 8, 3)), "2026-09-04")
        XCTAssertEqual(MarketClock.extendedHoursDate(from: date(2026, 9, 8, 10)), "2026-09-08")
        XCTAssertEqual(MarketClock.extendedHoursDate(from: date(2026, 9, 5, 10)), "2026-09-04")
        XCTAssertEqual(MarketClock.extendedHoursDate(from: date(2026, 9, 7, 10)), "2026-09-04")
        XCTAssertEqual(MarketClock.sessionWindow(at: date(2026, 9, 4, 8)), .premarket)
        XCTAssertEqual(MarketClock.sessionWindow(at: date(2026, 9, 4, 10)), .regular)
        XCTAssertEqual(MarketClock.sessionWindow(at: date(2026, 9, 4, 18)), .aftermarket)
        XCTAssertNil(MarketClock.sessionWindow(at: date(2026, 9, 4, 3, 59)))
        XCTAssertNil(MarketClock.sessionWindow(at: date(2026, 9, 4, 20)))
        XCTAssertTrue(MarketClock.isSessionActive(.regular, at: date(2026, 9, 4, 10)))
        XCTAssertFalse(MarketClock.isSessionActive(.regular, at: date(2026, 9, 5, 10)))
        XCTAssertFalse(MarketClock.isSessionActive(.premarket, at: date(2026, 9, 7, 8)))
        XCTAssertFalse(MarketClock.isSessionActive(.aftermarket, at: date(2026, 9, 7, 17)))
        XCTAssertTrue(MarketClock.shouldFetchLatestSnapshot(at: date(2026, 9, 4, 8)))
        XCTAssertTrue(MarketClock.shouldFetchLatestSnapshot(at: date(2026, 9, 4, 10)))
        XCTAssertFalse(MarketClock.shouldFetchLatestSnapshot(at: date(2026, 9, 5, 10)))
        XCTAssertFalse(MarketClock.shouldFetchLatestSnapshot(at: date(2026, 9, 7, 10)))
        XCTAssertEqual(MarketClock.latestSnapshotIntervalNanoseconds(symbolCount: 1, at: date(2026, 9, 4, 10)), 1_000_000_000)
        XCTAssertEqual(MarketClock.latestSnapshotIntervalNanoseconds(symbolCount: 3, at: date(2026, 9, 4, 10)), 1_000_000_000)
        XCTAssertEqual(MarketClock.latestSnapshotIntervalNanoseconds(symbolCount: 4, at: date(2026, 9, 4, 10)), 2_000_000_000)
        XCTAssertEqual(MarketClock.latestSnapshotIntervalNanoseconds(symbolCount: 8, at: date(2026, 9, 4, 10)), 2_000_000_000)
        XCTAssertEqual(MarketClock.latestSnapshotIntervalNanoseconds(symbolCount: 9, at: date(2026, 9, 4, 10)), 3_000_000_000)
        XCTAssertEqual(MarketClock.latestSnapshotIntervalNanoseconds(symbolCount: 1, at: date(2026, 9, 4, 8)), 5_000_000_000)
        XCTAssertEqual(MarketClock.latestSnapshotIntervalNanoseconds(symbolCount: 4, at: date(2026, 9, 4, 18)), 10_000_000_000)
        XCTAssertEqual(MarketClock.latestSnapshotIntervalNanoseconds(symbolCount: 9, at: date(2026, 9, 5, 10)), 15_000_000_000)
        XCTAssertFalse(MarketClock.shouldPoll(session: .premarket, date: "2026-09-07", now: date(2026, 9, 7, 8)))
        XCTAssertTrue(MarketClock.shouldPoll(session: .premarket, date: "2026-09-04", now: date(2026, 9, 4, 8)))
        XCTAssertFalse(MarketClock.shouldPoll(session: .regular, date: "2026-09-03", now: date(2026, 9, 4, 10)))
        XCTAssertGreaterThan(MarketClock.nanosecondsUntilNextMinute(from: date(2026, 9, 4, 10, 0)), 0)
        let knownHolidays = [
            "2026-01-01", "2026-01-19", "2026-02-16", "2026-04-03", "2026-05-25",
            "2026-06-19", "2026-07-03", "2026-09-07", "2026-11-26", "2026-12-25",
            "2027-01-01", "2027-01-18", "2027-02-15", "2027-03-26", "2027-05-31",
            "2027-06-18", "2027-07-05", "2027-09-06", "2027-11-25", "2027-12-24",
        ]
        for day in knownHolidays {
            XCTAssertTrue(MarketClock.isUSMarketHoliday(day), day)
        }
        XCTAssertTrue(MarketClock.isUSMarketHoliday("2028-09-04"))
        XCTAssertTrue(MarketClock.isUSMarketHoliday("2027-12-31"))
        XCTAssertFalse(MarketClock.isUSMarketHoliday("2026-09-04"))
    }

    func testOpeningProtectionAndExtendedHours() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            var parts = DateComponents()
            parts.year = year
            parts.month = month
            parts.day = day
            parts.hour = hour
            parts.minute = minute
            return calendar.date(from: parts)!
        }
        XCTAssertEqual(MarketClock.remainingOpeningProtectionMinutes(minutes: 30, at: date(2026, 9, 4, 9, 35)), 25)
        XCTAssertTrue(MarketClock.isOpeningProtectionActive(minutes: 30, at: date(2026, 9, 4, 9, 30)))
        XCTAssertFalse(MarketClock.isOpeningProtectionActive(minutes: 30, at: date(2026, 9, 4, 10, 0)))
        XCTAssertFalse(MarketClock.isOpeningProtectionActive(minutes: 0, at: date(2026, 9, 4, 9, 35)))
        XCTAssertFalse(MarketClock.isOpeningProtectionActive(minutes: 30, at: date(2026, 9, 5, 9, 35)))
        XCTAssertFalse(MarketClock.isOpeningProtectionActive(minutes: 30, at: date(2026, 9, 7, 9, 35)))
        XCTAssertTrue(MarketClock.isExtendedHoursSession(at: date(2026, 9, 4, 8, 0)))
        XCTAssertTrue(MarketClock.isExtendedHoursSession(at: date(2026, 9, 4, 17, 0)))
        XCTAssertFalse(MarketClock.isExtendedHoursSession(at: date(2026, 9, 4, 11, 0)))
        XCTAssertFalse(MarketClock.isExtendedHoursSession(at: date(2026, 9, 5, 8, 0)))
    }
}

@MainActor
final class ScreenerAPIDecodingTests: XCTestCase {
    func testDecodesBareArray() throws {
        let json = Data(#"[{"symbol":"AAPL","snapshot":{"currentPrice":190.5,"dailyBar":{"o":189,"c":190.5,"v":1000},"prevDailyBar":{"c":180}}}]"#.utf8)
        let rows = try ScreenerAPI.decodeList(from: json).map(SymbolSummary.init(dto:))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].symbol, "AAPL")
        XCTAssertEqual(rows[0].lastPrice, 190.5)
        XCTAssertEqual(rows[0].previousClose, 180)
        XCTAssertEqual(rows[0].sessionOpen, 189)
        XCTAssertEqual(rows[0].changePercent ?? 0, 190.5 / 180 * 100 - 100, accuracy: 0.0001)
    }

    func testDecodesEnvelopeAndRecord() throws {
        let envelope = Data(#"{"data":[{"symbol":"msft"}]}"#.utf8)
        XCTAssertEqual(try ScreenerAPI.decodeList(from: envelope).first?.symbol, "msft")

        let record = Data(#"{"TSLA":{"symbol":"TSLA"}}"#.utf8)
        XCTAssertEqual(try ScreenerAPI.decodeList(from: record).first?.symbol, "TSLA")
    }

    func testDecodesNumericStrings() throws {
        let json = Data(#"""
        [{"symbol":"AAPL","snapshot":{"currentPrice":"190.5","dailyBar":{"c":"191","v":"1000"},"prevDailyBar":{"c":"180"}},"indicators":{"rsi":"52.3","adx":"18","atr":"1.25"}}]
        """#.utf8)
        let rows = try ScreenerAPI.decodeList(from: json).map(SymbolSummary.init(dto:))
        XCTAssertEqual(rows[0].lastPrice, 190.5)
        XCTAssertEqual(rows[0].previousClose, 180)
        XCTAssertEqual(rows[0].volume, 1000)
        XCTAssertEqual(rows[0].rsi, 52.3)
        XCTAssertEqual(rows[0].adx, 18)
        XCTAssertEqual(rows[0].atr, 1.25)
        XCTAssertEqual(rows[0].atrPercent ?? -1, 1.25 / 190.5 * 100, accuracy: 0.0001)
    }

    func testDecodesTopLevelATRWhenIndicatorsOmitIt() throws {
        let json = Data(#"""
        [{"symbol":"AAPL","atr":"2.5","snapshot":{"currentPrice":"190.5"}}]
        """#.utf8)
        let rows = try ScreenerAPI.decodeList(from: json).map(SymbolSummary.init(dto:))
        XCTAssertEqual(rows[0].atr, 2.5)
    }

    func testPrefersIndicatorsATROverTopLevel() throws {
        let json = Data(#"""
        [{"symbol":"AAPL","atr":"9","indicators":{"atr":"1.25"}}]
        """#.utf8)
        let rows = try ScreenerAPI.decodeList(from: json).map(SymbolSummary.init(dto:))
        XCTAssertEqual(rows[0].atr, 1.25)
    }

    func testIgnoresNonFiniteNumericStrings() throws {
        let json = Data(#"""
        [{"symbol":"AAPL","snapshot":{"currentPrice":"NaN","dailyBar":{"c":"Infinity","v":"-Infinity"}},"indicators":{"rsi":"NaN"}}]
        """#.utf8)
        let rows = try ScreenerAPI.decodeList(from: json).map(SymbolSummary.init(dto:))
        XCTAssertNil(rows[0].lastPrice)
        XCTAssertNil(rows[0].volume)
        XCTAssertNil(rows[0].rsi)
        XCTAssertNil(rows[0].changePercent)
        XCTAssertNil(rows[0].atrPercent)
    }

    func testATRPercentRequiresFinitePrice() {
        XCTAssertEqual(
            SymbolSummary(symbol: "AAPL", lastPrice: 100, atr: 2.5).atrPercent ?? -1,
            2.5,
            accuracy: 0.0001
        )
        XCTAssertNil(SymbolSummary(symbol: "AAPL", lastPrice: 0, atr: 2.5).atrPercent)
        XCTAssertNil(SymbolSummary(symbol: "AAPL", atr: 2.5).atrPercent)
    }
}

@MainActor
final class ScreenerStoreTests: XCTestCase {
    func testAllNineKindsHaveDefaultQueries() {
        XCTAssertEqual(ScreenerKind.allCases.count, 9)
        let priceSlope = ScreenerQuery.defaults(for: .priceSlope, now: Date(timeIntervalSince1970: 1_778_000_000))
        XCTAssertEqual(priceSlope.spanMinutes, "30")
        XCTAssertEqual(priceSlope.minPrice, "6")
        XCTAssertFalse(priceSlope.date.isEmpty)
        let premarket = ScreenerQuery.defaults(for: .premarket)
        XCTAssertEqual(premarket.direction, "up")
        XCTAssertEqual(premarket.spanMinutes, "60")
        XCTAssertEqual(ScreenerSpanMinutes.premarket.map(\.rawValue), ["30", "60", "90", "120"])
        XCTAssertEqual(ScreenerQuery.defaults(for: .atr).barCount, "10")
        XCTAssertEqual(ScreenerQuery.defaults(for: .stair).barCount, "0")
        XCTAssertEqual(ScreenerQuery.defaults(for: .stair).timeFrame, "1Min")
        XCTAssertEqual(ScreenerQuery.defaults(for: .momentum).minVolume, "1M")
        XCTAssertEqual(ScreenerQuery.defaults(for: .atr).minVolume, "1M")
        XCTAssertEqual(ScreenerQuery.defaults(for: .stair).minVolume, "5M")
        XCTAssertEqual(ScreenerQuery.defaults(for: .volume).minVolume, "5M")
        XCTAssertTrue(ScreenerKind.momentum.showsFilters)
        XCTAssertTrue(ScreenerKind.atr.showsFilters)
        XCTAssertTrue(ScreenerKind.priceSlope.showsFilters)
        XCTAssertTrue(ScreenerKind.premarket.showsFilters)
        XCTAssertTrue(ScreenerKind.stair.showsFilters)
        XCTAssertTrue(ScreenerKind.rsiAdx.showsFilters)
        XCTAssertTrue(ScreenerKind.volume.showsFilters)
        XCTAssertTrue(ScreenerKind.ibkr.showsFilters)
        XCTAssertFalse(ScreenerKind.yahoo.showsFilters)
        XCTAssertTrue(ScreenerKind.momentum.usesImplicitTradingDate)
        XCTAssertTrue(ScreenerKind.atr.usesImplicitTradingDate)
        XCTAssertTrue(ScreenerKind.stair.usesImplicitTradingDate)
        XCTAssertFalse(ScreenerKind.priceSlope.usesImplicitTradingDate)
        XCTAssertFalse(ScreenerKind.premarket.usesImplicitTradingDate)
        XCTAssertFalse(ScreenerKind.rsiAdx.usesImplicitTradingDate)
        XCTAssertFalse(ScreenerKind.volume.usesImplicitTradingDate)
        XCTAssertFalse(ScreenerKind.ibkr.usesImplicitTradingDate)
    }

    func testMomentumDefaultsUseLastTradingDateAndFilterValues() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 9
        parts.day = 5
        parts.hour = 12
        let saturday = calendar.date(from: parts)!
        let query = ScreenerQuery.defaults(for: .momentum, now: saturday)
        XCTAssertEqual(query.date, "2026-09-04")
        XCTAssertEqual(query.direction, "up")
        XCTAssertEqual(query.timeFrame, "5Min")
        XCTAssertEqual(query.minVolume, "1M")
    }

    func testATRDefaultsUseLastTradingDateAndFilterValues() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 9
        parts.day = 5
        parts.hour = 12
        let saturday = calendar.date(from: parts)!
        let query = ScreenerQuery.defaults(for: .atr, now: saturday)
        XCTAssertEqual(query.date, "2026-09-04")
        XCTAssertEqual(query.timeFrame, "1Min")
        XCTAssertEqual(query.barCount, "10")
        XCTAssertEqual(query.minPrice, "6")
        XCTAssertEqual(query.minVolume, "1M")
        XCTAssertTrue(query.time.isEmpty)
    }

    func testResetDiscardsInFlightResults() async {
        let http = ScriptedHTTP()
        http.pauseSends = true
        http.rawResults = [
            .success(Data(#"[{"symbol":"OLD"}]"#.utf8)),
        ]
        let store = ScreenerStore(api: ScreenerAPI(client: http))
        let load = Task { await store.load(.yahoo) }
        await waitUntil { !http.requests.isEmpty }
        store.reset()
        http.releasePaused()
        await load.value
        XCTAssertTrue(store.rows.isEmpty)
        XCTAssertNil(store.kind)
    }

    func testLookupRequiresExactSymbol() async {
        let http = ScriptedHTTP()
        http.rawResults = [.success(Data(#"[{"symbol":"MSFT"}]"#.utf8))]
        let store = SymbolSummaryStore(api: ScreenerAPI(client: http))
        do {
            _ = try await store.lookup("AAPL")
            XCTFail("must not accept a different symbol")
        } catch {
            XCTAssertEqual(error as? AppError, .http(status: 404, message: L10n.Market.unknownSymbol, errorCode: nil))
        }
    }

    func testLookupCacheExpiresAndForceRefresh() async throws {
        var now = Date()
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[{"symbol":"AAPL","snapshot":{"currentPrice":100}}]"#.utf8)),
            .success(Data(#"[{"symbol":"AAPL","snapshot":{"currentPrice":200}}]"#.utf8)),
            .success(Data(#"[{"symbol":"AAPL","snapshot":{"currentPrice":300}}]"#.utf8)),
        ]
        let store = SymbolSummaryStore(api: ScreenerAPI(client: http), cacheTTL: 60, now: { now })
        let first = try await store.lookup("AAPL")
        let cached = try await store.lookup("AAPL")
        XCTAssertEqual(first.lastPrice, 100)
        XCTAssertEqual(cached.lastPrice, 100)
        XCTAssertEqual(http.requests.count, 1)

        now = now.addingTimeInterval(61)
        let expired = try await store.lookup("AAPL")
        XCTAssertEqual(expired.lastPrice, 200)
        XCTAssertEqual(http.requests.count, 2)

        let forced = try await store.lookup("AAPL", forceRefresh: true)
        XCTAssertEqual(forced.lastPrice, 300)
        XCTAssertEqual(http.requests.count, 3)
    }

    func testLookupCoalescesInFlightAndKeepsLookingUpFlag() async throws {
        let http = ScriptedHTTP()
        http.pauseSends = true
        http.rawResults = [
            .success(Data(#"[{"symbol":"AAPL","snapshot":{"currentPrice":1}}]"#.utf8)),
            .success(Data(#"[{"symbol":"MSFT","snapshot":{"currentPrice":2}}]"#.utf8)),
        ]
        let store = SymbolSummaryStore(api: ScreenerAPI(client: http))
        let firstA = Task { try await store.lookup("AAPL") }
        let secondA = Task { try await store.lookup("AAPL") }
        await waitUntil { http.requests.count == 1 }
        XCTAssertTrue(store.isLookingUp)

        let msft = Task { try await store.lookup("MSFT") }
        await waitUntil { http.requests.count == 2 }
        XCTAssertTrue(store.isLookingUp)

        http.releaseNext()
        let firstResult = try await firstA.value
        let secondResult = try await secondA.value
        XCTAssertEqual(firstResult.symbol, "AAPL")
        XCTAssertEqual(secondResult.symbol, "AAPL")
        XCTAssertTrue(store.isLookingUp)
        XCTAssertEqual(http.requests.count, 2)

        http.releaseNext()
        let msftResult = try await msft.value
        XCTAssertEqual(msftResult.symbol, "MSFT")
        XCTAssertFalse(store.isLookingUp)
    }

    func testLookupResetDoesNotDropNextInflight() async throws {
        let http = ScriptedHTTP()
        http.pauseSends = true
        http.rawResults = [
            .success(Data(#"[{"symbol":"AAPL","snapshot":{"currentPrice":1}}]"#.utf8)),
            .success(Data(#"[{"symbol":"AAPL","snapshot":{"currentPrice":2}}]"#.utf8)),
        ]
        let store = SymbolSummaryStore(api: ScreenerAPI(client: http))
        let stale = Task { try await store.lookup("AAPL") }
        await waitUntil { http.requests.count == 1 }
        store.reset()
        let next = Task { try await store.lookup("AAPL") }
        await waitUntil { http.requests.count == 2 }
        XCTAssertTrue(store.isLookingUp)

        http.releaseNext()
        do {
            _ = try await stale.value
            XCTFail("stale lookup must not apply after reset")
        } catch {
            XCTAssertEqual(error as? AppError, .cancelled)
        }
        XCTAssertTrue(store.isLookingUp)

        http.releaseNext()
        let result = try await next.value
        XCTAssertEqual(result.lastPrice, 2)
        XCTAssertFalse(store.isLookingUp)
    }

    func testLookupUnknownSymbolFails() async {
        let http = ScriptedHTTP()
        http.rawResults = [.success(Data("[]".utf8))]
        let store = SymbolSummaryStore(api: ScreenerAPI(client: http))
        do {
            _ = try await store.lookup("ZZZZ")
            XCTFail("unknown symbol must fail")
        } catch {
            XCTAssertEqual((error as? AppError), .http(status: 404, message: L10n.Market.unknownSymbol, errorCode: nil))
        }
    }

    func testLookupRejectsInvalidSymbolWithoutRequest() async {
        let http = ScriptedHTTP()
        let store = SymbolSummaryStore(api: ScreenerAPI(client: http))
        do {
            _ = try await store.lookup("AA PL")
            XCTFail("invalid symbol must fail")
        } catch {
            XCTAssertTrue(http.requests.isEmpty)
        }
    }

    func testLaterRequestWinsWhenEarlierCompletesLast() async {
        let http = ScriptedHTTP()
        http.pauseSends = true
        http.rawResults = [
            .success(Data(#"[{"symbol":"OLD"}]"#.utf8)),
            .success(Data(#"[{"symbol":"MOM"}]"#.utf8)),
        ]
        let store = ScreenerStore(api: ScreenerAPI(client: http))
        let first = Task { await store.load(.yahoo) }
        await waitUntil { http.requests.count == 1 }
        let second = Task { await store.load(.momentum) }
        await waitUntil { store.kind == .momentum }
        XCTAssertEqual(http.requests.count, 1)
        XCTAssertTrue(store.rows.isEmpty)
        XCTAssertTrue(store.isLoading)

        http.releaseNext()
        await waitUntil { http.requests.count == 2 }
        http.releaseNext()
        await first.value
        await second.value
        XCTAssertEqual(store.rows.map(\.symbol), ["MOM"])
        XCTAssertEqual(store.kind, .momentum)
        XCTAssertFalse(store.isLoading)
    }

    func testAppearSameKindReusesQueryAndRefetches() async {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[{"symbol":"AAPL"}]"#.utf8)),
            .success(Data(#"[{"symbol":"MSFT"}]"#.utf8)),
        ]
        let store = ScreenerStore(api: ScreenerAPI(client: http))
        var query = ScreenerQuery.defaults(for: .priceSlope)
        query.minPrice = "10"
        query.direction = "down"
        await store.load(.priceSlope, query: query)
        XCTAssertEqual(http.requests.count, 1)
        XCTAssertEqual(store.rows.map(\.symbol), ["AAPL"])

        await store.appear(.priceSlope)
        XCTAssertEqual(http.requests.count, 2)
        XCTAssertEqual(store.query.minPrice, "10")
        XCTAssertEqual(store.query.direction, "down")
        XCTAssertEqual(store.rows.map(\.symbol), ["MSFT"])
    }

    func testAppearDifferentKindLoadsDefaults() async {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[{"symbol":"OLD"}]"#.utf8)),
            .success(Data(#"[{"symbol":"NEW"}]"#.utf8)),
        ]
        let store = ScreenerStore(api: ScreenerAPI(client: http))
        var query = ScreenerQuery.defaults(for: .priceSlope)
        query.minPrice = "10"
        await store.load(.priceSlope, query: query)
        await store.appear(.yahoo)
        XCTAssertEqual(http.requests.count, 2)
        XCTAssertEqual(store.kind, .yahoo)
        XCTAssertEqual(store.query.scrIds, "most_actives")
        XCTAssertEqual(store.rows.map(\.symbol), ["NEW"])
    }

    func testIntermediateFilterChangeIsCoalesced() async {
        let http = ScriptedHTTP()
        http.pauseSends = true
        http.rawResults = [
            .success(Data(#"[{"symbol":"OLD"}]"#.utf8)),
            .success(Data(#"[{"symbol":"NEW"}]"#.utf8)),
        ]
        let store = ScreenerStore(api: ScreenerAPI(client: http))
        let first = Task { await store.load(.priceSlope) }
        await waitUntil { http.requests.count == 1 }

        var down = store.query
        down.direction = "down"
        let middle = Task { await store.load(.priceSlope, query: down) }
        var last = down
        last.minPrice = "10"
        let latest = Task { await store.load(.priceSlope, query: last) }
        await waitUntil { store.query.minPrice == "10" }
        XCTAssertEqual(http.requests.count, 1)

        http.releaseNext()
        await waitUntil { http.requests.count == 2 }
        XCTAssertEqual(http.requests.last?.query["direction"], "down")
        XCTAssertEqual(http.requests.last?.query["minPrice"], "10")
        http.releaseNext()
        await first.value
        await middle.value
        await latest.value
        XCTAssertEqual(store.rows.map(\.symbol), ["NEW"])
        XCTAssertEqual(store.query.minPrice, "10")
    }

    func testPriceSlopeSendsResolvedEndTime() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 9
        parts.day = 4
        parts.hour = 15
        parts.minute = 12
        let now = calendar.date(from: parts)!
        let http = ScriptedHTTP()
        http.rawResults = [.success(Data("[]".utf8))]
        let store = ScreenerStore(api: ScreenerAPI(client: http), now: { now })
        await store.load(.priceSlope)
        XCTAssertEqual(http.requests.first?.path, "intraday-stocks/price-slope")
        XCTAssertEqual(http.requests.first?.query["date"], "2026-09-04")
        XCTAssertEqual(http.requests.first?.query["endTime"], "15:12")
        XCTAssertTrue(store.query.endTime.isEmpty)
    }

    func testPriceSlopeClearsStaleEndTimeBeforeFetch() async {
        let http = ScriptedHTTP()
        http.rawResults = [.success(Data("[]".utf8))]
        let store = ScreenerStore(api: ScreenerAPI(client: http))
        var query = ScreenerQuery.defaults(for: .priceSlope)
        query.endTime = "08:00"
        await store.load(.priceSlope, query: query)
        XCTAssertEqual(http.requests.count, 1)
        XCTAssertTrue(store.query.endTime.isEmpty)
        XCTAssertNil(store.errorText)
    }

    func testSearchLaterSymbolWins() async {
        let http = ScriptedHTTP()
        http.pauseSends = true
        http.rawResults = [
            .success(Data(#"[{"symbol":"AAPL","snapshot":{"currentPrice":1}}]"#.utf8)),
            .success(Data(#"[{"symbol":"MSFT","snapshot":{"currentPrice":2}}]"#.utf8)),
        ]
        let store = SymbolSummaryStore(api: ScreenerAPI(client: http))
        let search = SymbolSearchSession()
        let first = Task { await search.submit("AAPL", lookup: { try await store.lookup($0) }) }
        await waitUntil { http.requests.count == 1 }
        let second = Task { await search.submit("MSFT", lookup: { try await store.lookup($0) }) }
        await waitUntil { http.requests.count == 2 }
        http.releaseNext()
        let earlier = await first.value
        XCTAssertNil(earlier)

        http.releaseNext()
        let later = await second.value
        XCTAssertEqual(later, "MSFT")
        XCTAssertNil(search.errorText)
    }

    func testYahooRequestUsesDefaultQuery() async {
        let http = ScriptedHTTP()
        http.rawResults = [.success(Data("[]".utf8))]
        let store = ScreenerStore(api: ScreenerAPI(client: http))
        await store.load(.yahoo)
        XCTAssertEqual(http.requests.first?.path, "intraday-stocks/yahoo/screener")
        XCTAssertEqual(http.requests.first?.query["scrIds"], "most_actives")
        XCTAssertEqual(http.requests.first?.query["market"], "us")
    }

    func testMomentumRequestSendsDirectionTimeFrameAndMinVolume() async {
        let http = ScriptedHTTP()
        http.rawResults = [.success(Data(#"[{"symbol":"NVDA"}]"#.utf8))]
        let store = ScreenerStore(api: ScreenerAPI(client: http))
        var query = ScreenerQuery.defaults(for: .momentum)
        query.direction = "down"
        query.timeFrame = "1Min"
        query.minVolume = "5M"
        await store.load(.momentum, query: query)
        XCTAssertEqual(http.requests.first?.path, "intraday-stocks/top-momentum")
        XCTAssertEqual(http.requests.first?.query["direction"], "down")
        XCTAssertEqual(http.requests.first?.query["timeFrame"], "1Min")
        XCTAssertEqual(http.requests.first?.query["minVolume"], "5M")
        XCTAssertEqual(http.requests.first?.query["date"], query.date)
        XCTAssertEqual(store.rows.map(\.symbol), ["NVDA"])
    }

    func testMomentumReloadsRefreshLastTradingDateAndKeepFilters() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
            var parts = DateComponents()
            parts.year = year
            parts.month = month
            parts.day = day
            parts.hour = hour
            return calendar.date(from: parts)!
        }
        let friday = date(2026, 9, 4, 15)
        let nextSession = date(2026, 9, 8, 10)
        var now = friday
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[{"symbol":"OLD"}]"#.utf8)),
            .success(Data(#"[{"symbol":"NEW"}]"#.utf8)),
            .success(Data(#"[{"symbol":"TAP"}]"#.utf8)),
        ]
        let store = ScreenerStore(api: ScreenerAPI(client: http), now: { now })
        var query = ScreenerQuery.defaults(for: .momentum, now: friday)
        query.direction = "down"
        query.timeFrame = "1Min"
        query.minVolume = "5M"
        query.date = "2026-08-01"
        await store.load(.momentum, query: query)
        XCTAssertEqual(http.requests[0].query["date"], "2026-09-04")
        XCTAssertEqual(store.query.date, "2026-09-04")
        XCTAssertEqual(store.query.direction, "down")
        XCTAssertEqual(store.query.timeFrame, "1Min")
        XCTAssertEqual(store.query.minVolume, "5M")

        now = nextSession
        await store.appear(.momentum)
        XCTAssertEqual(http.requests[1].query["date"], "2026-09-08")
        XCTAssertEqual(store.query.date, "2026-09-08")
        XCTAssertEqual(store.query.direction, "down")
        XCTAssertEqual(store.query.timeFrame, "1Min")
        XCTAssertEqual(store.query.minVolume, "5M")

        await store.load(.momentum, query: store.query)
        XCTAssertEqual(http.requests[2].query["date"], "2026-09-08")
        XCTAssertEqual(store.query.direction, "down")
        XCTAssertEqual(store.rows.map(\.symbol), ["TAP"])
    }

    func testATRReloadsRefreshLastTradingDateAndKeepFilters() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
            var parts = DateComponents()
            parts.year = year
            parts.month = month
            parts.day = day
            parts.hour = hour
            return calendar.date(from: parts)!
        }
        let friday = date(2026, 9, 4, 15)
        let nextSession = date(2026, 9, 8, 10)
        var now = friday
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[{"symbol":"OLD"}]"#.utf8)),
            .success(Data(#"[{"symbol":"NEW"}]"#.utf8)),
        ]
        let store = ScreenerStore(api: ScreenerAPI(client: http), now: { now })
        var query = ScreenerQuery.defaults(for: .atr, now: friday)
        query.timeFrame = "5Min"
        query.barCount = "20"
        query.minPrice = "10"
        query.minVolume = "2M"
        query.date = "2026-08-01"
        await store.load(.atr, query: query)
        now = nextSession
        await store.appear(.atr)
        XCTAssertEqual(http.requests.last?.query["date"], "2026-09-08")
        XCTAssertEqual(store.query.timeFrame, "5Min")
        XCTAssertEqual(store.query.barCount, "20")
        XCTAssertEqual(store.query.minPrice, "10")
        XCTAssertEqual(store.query.minVolume, "2M")
    }

    func testPriceSlopeReloadsRefreshCalendarDateAndKeepFilters() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
            var parts = DateComponents()
            parts.year = year
            parts.month = month
            parts.day = day
            parts.hour = hour
            return calendar.date(from: parts)!
        }
        var now = date(2026, 9, 4, 15)
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[{"symbol":"AAPL"}]"#.utf8)),
            .success(Data(#"[{"symbol":"MSFT"}]"#.utf8)),
        ]
        let store = ScreenerStore(api: ScreenerAPI(client: http), now: { now })
        var query = ScreenerQuery.defaults(for: .priceSlope, now: now)
        query.date = "2026-08-01"
        query.direction = "down"
        query.spanMinutes = "60"
        await store.load(.priceSlope, query: query)
        XCTAssertEqual(http.requests[0].query["date"], "2026-09-04")
        XCTAssertEqual(http.requests[0].query["endTime"], "15:00")
        now = date(2026, 9, 8, 10)
        await store.appear(.priceSlope)
        XCTAssertEqual(store.query.date, "2026-09-08")
        XCTAssertEqual(http.requests.last?.query["date"], "2026-09-08")
        XCTAssertEqual(http.requests.last?.query["endTime"], "10:00")
        XCTAssertEqual(store.query.direction, "down")
        XCTAssertEqual(store.query.spanMinutes, "60")
        XCTAssertTrue(store.query.endTime.isEmpty)
    }

    func testPremarketRequestSendsDirectionAndPeriod() async {
        let http = ScriptedHTTP()
        http.rawResults = [.success(Data(#"[{"symbol":"AMD"}]"#.utf8))]
        let store = ScreenerStore(api: ScreenerAPI(client: http))
        var query = ScreenerQuery.defaults(for: .premarket)
        query.direction = "down"
        query.spanMinutes = "90"
        await store.load(.premarket, query: query)
        XCTAssertEqual(http.requests.first?.path, "intraday-stocks/premarket-indicator")
        XCTAssertEqual(http.requests.first?.query["direction"], "down")
        XCTAssertEqual(http.requests.first?.query["period"], "90")
        XCTAssertNil(http.requests.first?.query["market"])
        XCTAssertNil(http.requests.first?.query["date"])
        XCTAssertNil(http.requests.first?.query["spanMinutes"])
        XCTAssertEqual(store.rows.map(\.symbol), ["AMD"])
    }

    func testPremarketDefaultSendsUpAndPeriod60() async {
        let http = ScriptedHTTP()
        http.rawResults = [.success(Data("[]".utf8))]
        let store = ScreenerStore(api: ScreenerAPI(client: http))
        await store.load(.premarket)
        XCTAssertEqual(http.requests.first?.path, "intraday-stocks/premarket-indicator")
        XCTAssertEqual(http.requests.first?.query["direction"], "up")
        XCTAssertEqual(http.requests.first?.query["period"], "60")
        XCTAssertEqual(http.requests.first?.query.count, 2)
    }

    func testPremarketRemembersQueryAfterSwitchingToAnotherScreener() async {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[{"symbol":"PRE"}]"#.utf8)),
            .success(Data(#"[{"symbol":"VOL"}]"#.utf8)),
            .success(Data(#"[{"symbol":"BACK"}]"#.utf8)),
        ]
        let store = ScreenerStore(api: ScreenerAPI(client: http))
        var query = ScreenerQuery.defaults(for: .premarket)
        query.direction = "down"
        query.spanMinutes = "120"
        await store.load(.premarket, query: query)
        await store.appear(.volume)
        await store.appear(.premarket)
        XCTAssertEqual(http.requests.last?.path, "intraday-stocks/premarket-indicator")
        XCTAssertEqual(http.requests.last?.query["direction"], "down")
        XCTAssertEqual(http.requests.last?.query["period"], "120")
        XCTAssertEqual(store.query.direction, "down")
        XCTAssertEqual(store.query.spanMinutes, "120")
        XCTAssertEqual(store.rows.map(\.symbol), ["BACK"])
    }

    func testStairDefaultSendsBarCountZero() async {
        let http = ScriptedHTTP()
        http.rawResults = [.success(Data("[]".utf8))]
        let store = ScreenerStore(api: ScreenerAPI(client: http))
        await store.load(.stair)
        XCTAssertEqual(http.requests.first?.path, "intraday-stocks/top-stair-setups")
        XCTAssertEqual(http.requests.first?.query["barCount"], "0")
        XCTAssertEqual(http.requests.first?.query["timeFrame"], "1Min")
        XCTAssertEqual(http.requests.first?.query["direction"], "up")
        XCTAssertEqual(http.requests.first?.query["minPrice"], "6")
        XCTAssertEqual(http.requests.first?.query["minVolume"], "5M")
        XCTAssertEqual(http.requests.first?.query["date"], store.query.date)
    }

    func testStairReloadsRefreshLastTradingDateAndKeepFilters() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
            var parts = DateComponents()
            parts.year = year
            parts.month = month
            parts.day = day
            parts.hour = hour
            return calendar.date(from: parts)!
        }
        let friday = date(2026, 9, 4, 15)
        let nextSession = date(2026, 9, 8, 10)
        var now = friday
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[{"symbol":"OLD"}]"#.utf8)),
            .success(Data(#"[{"symbol":"NEW"}]"#.utf8)),
        ]
        let store = ScreenerStore(api: ScreenerAPI(client: http), now: { now })
        var query = ScreenerQuery.defaults(for: .stair, now: friday)
        query.direction = "down"
        query.timeFrame = "5Min"
        query.barCount = "20"
        query.minPrice = "10"
        query.minVolume = "2M"
        query.date = "2026-08-01"
        await store.load(.stair, query: query)
        now = nextSession
        await store.appear(.stair)
        XCTAssertEqual(http.requests.last?.query["date"], "2026-09-08")
        XCTAssertEqual(store.query.direction, "down")
        XCTAssertEqual(store.query.timeFrame, "5Min")
        XCTAssertEqual(store.query.barCount, "20")
        XCTAssertEqual(store.query.minPrice, "10")
        XCTAssertEqual(store.query.minVolume, "2M")
    }

    func testRSIADXDefaultSendsClosedRangesLikeRN() async {
        let http = ScriptedHTTP()
        http.rawResults = [.success(Data("[]".utf8))]
        let store = ScreenerStore(api: ScreenerAPI(client: http))
        await store.load(.rsiAdx)
        XCTAssertEqual(http.requests.first?.path, "intraday-stocks/indicators-rsi-adx")
        XCTAssertEqual(http.requests.first?.query["rsiLow"], "50")
        XCTAssertEqual(http.requests.first?.query["rsiHigh"], "60")
        XCTAssertEqual(http.requests.first?.query["adxLow"], "20")
        XCTAssertEqual(http.requests.first?.query["adxHigh"], "30")
        XCTAssertEqual(http.requests.first?.query["diGap"], "20")
        XCTAssertEqual(http.requests.first?.query["direction"], "up")
        XCTAssertEqual(http.requests.first?.query["timeFrame"], "1Min")
        XCTAssertNil(http.requests.first?.query["date"])
    }

    func testRSIADXOpenEndedRangeOmitsMissingBounds() async {
        let http = ScriptedHTTP()
        http.rawResults = [.success(Data("[]".utf8))]
        let store = ScreenerStore(api: ScreenerAPI(client: http))
        var query = ScreenerQuery.defaults(for: .rsiAdx)
        query.rsiRange = ScreenerRSIRange.lt40.rawValue
        query.adxRange = ScreenerADXRange.gt50.rawValue
        query.diGap = ScreenerDIGap.ten.rawValue
        query.direction = "down"
        query.timeFrame = "5Min"
        await store.load(.rsiAdx, query: query)
        XCTAssertEqual(http.requests.first?.query["rsiHigh"], "40")
        XCTAssertNil(http.requests.first?.query["rsiLow"])
        XCTAssertEqual(http.requests.first?.query["adxLow"], "50")
        XCTAssertNil(http.requests.first?.query["adxHigh"])
        XCTAssertEqual(http.requests.first?.query["diGap"], "10")
        XCTAssertEqual(http.requests.first?.query["direction"], "down")
        XCTAssertEqual(http.requests.first?.query["timeFrame"], "5Min")
        XCTAssertEqual(store.query.rsiRange, "lt40")
        XCTAssertEqual(store.query.adxRange, "gt50")
    }

    func testRSIADXReloadsKeepFilters() async {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[{"symbol":"OLD"}]"#.utf8)),
            .success(Data(#"[{"symbol":"NEW"}]"#.utf8)),
        ]
        let store = ScreenerStore(api: ScreenerAPI(client: http))
        var query = ScreenerQuery.defaults(for: .rsiAdx)
        query.rsiRange = ScreenerRSIRange.from60to70.rawValue
        query.adxRange = ScreenerADXRange.from30to40.rawValue
        query.diGap = "30"
        query.direction = "down"
        query.timeFrame = "3Min"
        await store.load(.rsiAdx, query: query)
        await store.appear(.rsiAdx)
        XCTAssertEqual(http.requests.last?.query["rsiLow"], "60")
        XCTAssertEqual(http.requests.last?.query["rsiHigh"], "70")
        XCTAssertEqual(http.requests.last?.query["adxLow"], "30")
        XCTAssertEqual(http.requests.last?.query["adxHigh"], "40")
        XCTAssertEqual(store.query.diGap, "30")
        XCTAssertEqual(store.query.direction, "down")
        XCTAssertEqual(store.query.timeFrame, "3Min")
        XCTAssertEqual(store.rows.map(\.symbol), ["NEW"])
    }

    func testVolumeDefaultSendsMinVolumeAndFirstFifty() async {
        let http = ScriptedHTTP()
        http.rawResults = [.success(Data("[]".utf8))]
        let store = ScreenerStore(api: ScreenerAPI(client: http))
        await store.load(.volume)
        XCTAssertEqual(http.requests.first?.path, "intraday-stocks/top-volumes-increased")
        XCTAssertEqual(http.requests.first?.query["market"], "us")
        XCTAssertEqual(http.requests.first?.query["minVolume"], "5M")
        XCTAssertEqual(http.requests.first?.query["returnCount"], "50")
        XCTAssertNil(http.requests.first?.query["minPrice"])
        XCTAssertNil(http.requests.first?.query["date"])
    }

    func testVolumeAlwaysRequestsFirstFifty() async {
        let http = ScriptedHTTP()
        http.rawResults = [.success(Data("[]".utf8))]
        let store = ScreenerStore(api: ScreenerAPI(client: http))
        var query = ScreenerQuery.defaults(for: .volume)
        query.returnCount = "200"
        query.minPrice = "10"
        query.minVolume = "2M"
        await store.load(.volume, query: query)
        XCTAssertEqual(http.requests.first?.query["returnCount"], "50")
        XCTAssertEqual(http.requests.first?.query["minVolume"], "2M")
        XCTAssertNil(http.requests.first?.query["minPrice"])
    }

    func testVolumeReloadsKeepMinVolume() async {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[{"symbol":"OLD"}]"#.utf8)),
            .success(Data(#"[{"symbol":"NEW"}]"#.utf8)),
        ]
        let store = ScreenerStore(api: ScreenerAPI(client: http))
        var query = ScreenerQuery.defaults(for: .volume)
        query.minVolume = "10M"
        await store.load(.volume, query: query)
        await store.appear(.volume)
        XCTAssertEqual(http.requests.last?.query["minVolume"], "10M")
        XCTAssertEqual(http.requests.last?.query["returnCount"], "50")
        XCTAssertNil(http.requests.last?.query["minPrice"])
        XCTAssertEqual(store.query.minVolume, "10M")
        XCTAssertEqual(store.rows.map(\.symbol), ["NEW"])
    }

    func testATRDefaultKeepsBarCountTen() async {
        let http = ScriptedHTTP()
        http.rawResults = [.success(Data("[]".utf8))]
        let store = ScreenerStore(api: ScreenerAPI(client: http))
        await store.load(.atr)
        XCTAssertEqual(http.requests.first?.path, "intraday-stocks/top-atr-stocks")
        XCTAssertEqual(http.requests.first?.query["barCount"], "10")
        XCTAssertEqual(http.requests.first?.query["timeFrame"], "1Min")
        XCTAssertEqual(http.requests.first?.query["minPrice"], "6")
        XCTAssertEqual(http.requests.first?.query["minVolume"], "1M")
        XCTAssertEqual(http.requests.first?.query["date"], store.query.date)
        XCTAssertNil(http.requests.first?.query["time"])
    }

    func testATRSendsTimeWhenProvidedLikeRN() async {
        let http = ScriptedHTTP()
        http.rawResults = [.success(Data("[]".utf8))]
        let store = ScreenerStore(api: ScreenerAPI(client: http))
        var query = ScreenerQuery.defaults(for: .atr)
        query.time = "10:15"
        await store.load(.atr, query: query)
        XCTAssertEqual(http.requests.first?.query["time"], "10:15")
    }

    func testATRFilterChangeSendsUpdatedQueryAndOmitsEmptyTime() async {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[{"symbol":"AMD"}]"#.utf8)),
            .success(Data(#"[{"symbol":"NVDA"}]"#.utf8)),
        ]
        let store = ScreenerStore(api: ScreenerAPI(client: http))
        var query = ScreenerQuery.defaults(for: .atr)
        await store.load(.atr, query: query)
        query.timeFrame = "5Min"
        query.barCount = "20"
        query.minPrice = "10"
        query.minVolume = "5M"
        await store.load(.atr, query: query)
        XCTAssertEqual(http.requests.last?.query["timeFrame"], "5Min")
        XCTAssertEqual(http.requests.last?.query["barCount"], "20")
        XCTAssertEqual(http.requests.last?.query["minPrice"], "10")
        XCTAssertEqual(http.requests.last?.query["minVolume"], "5M")
        XCTAssertNil(http.requests.last?.query["time"])
        XCTAssertEqual(store.rows.map(\.symbol), ["NVDA"])
    }

    func testIBKRDefaultSendsDateTypePriceAndMarketCap() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 9
        parts.day = 4
        parts.hour = 15
        let now = calendar.date(from: parts)!
        let http = ScriptedHTTP()
        http.rawResults = [.success(Data("[]".utf8))]
        let store = ScreenerStore(api: ScreenerAPI(client: http), now: { now })
        await store.load(.ibkr)
        XCTAssertEqual(http.requests.first?.path, "intraday-stocks/ibkr/screener")
        XCTAssertEqual(http.requests.first?.query["date"], "2026-09-04")
        XCTAssertEqual(http.requests.first?.query["type"], "MOST_ACTIVE")
        XCTAssertEqual(http.requests.first?.query["filters"], "priceAbove=10,marketCapAbove=1000000000")
    }

    func testIBKRReloadsKeepSelectedDateAndFilters() async {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[{"symbol":"OLD"}]"#.utf8)),
            .success(Data(#"[{"symbol":"NEW"}]"#.utf8)),
        ]
        let store = ScreenerStore(api: ScreenerAPI(client: http))
        var query = ScreenerQuery.defaults(for: .ibkr)
        query.date = "2026-08-01"
        query.ibkrType = ScreenerIBKRType.hotByVolume.rawValue
        query.minPrice = ScreenerMinPrice.five.rawValue
        query.ibkrMarketCap = ScreenerMinMarketCap.fiveHundredMillion.rawValue
        await store.load(.ibkr, query: query)
        await store.appear(.ibkr)
        XCTAssertEqual(http.requests.last?.query["date"], "2026-08-01")
        XCTAssertEqual(http.requests.last?.query["type"], "HOT_BY_VOLUME")
        XCTAssertEqual(http.requests.last?.query["filters"], "priceAbove=5,marketCapAbove=500000000")
        XCTAssertEqual(store.query.date, "2026-08-01")
        XCTAssertEqual(store.query.ibkrType, "HOT_BY_VOLUME")
        XCTAssertEqual(store.query.minPrice, "5")
        XCTAssertEqual(store.query.ibkrMarketCap, "500000000")
        XCTAssertEqual(store.rows.map(\.symbol), ["NEW"])
    }

    func testIBKRRemembersQueryAfterSwitchingToAnotherScreener() async {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[{"symbol":"IBKR"}]"#.utf8)),
            .success(Data(#"[{"symbol":"VOL"}]"#.utf8)),
            .success(Data(#"[{"symbol":"BACK"}]"#.utf8)),
        ]
        let store = ScreenerStore(api: ScreenerAPI(client: http))
        var query = ScreenerQuery.defaults(for: .ibkr)
        query.date = "2026-08-01"
        query.ibkrType = ScreenerIBKRType.hotByVolume.rawValue
        query.minPrice = ScreenerMinPrice.five.rawValue
        query.ibkrMarketCap = ScreenerMinMarketCap.fiveHundredMillion.rawValue
        await store.load(.ibkr, query: query)
        await store.appear(.volume)
        await store.appear(.ibkr)
        XCTAssertEqual(http.requests.last?.path, "intraday-stocks/ibkr/screener")
        XCTAssertEqual(http.requests.last?.query["date"], "2026-08-01")
        XCTAssertEqual(http.requests.last?.query["type"], "HOT_BY_VOLUME")
        XCTAssertEqual(http.requests.last?.query["filters"], "priceAbove=5,marketCapAbove=500000000")
        XCTAssertEqual(store.query.date, "2026-08-01")
        XCTAssertEqual(store.query.ibkrType, "HOT_BY_VOLUME")
        XCTAssertEqual(store.query.minPrice, "5")
        XCTAssertEqual(store.query.ibkrMarketCap, "500000000")
        XCTAssertEqual(store.rows.map(\.symbol), ["BACK"])
    }

    func testResetClearsRememberedScreenerQueries() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 9
        parts.day = 4
        parts.hour = 15
        let now = calendar.date(from: parts)!
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[{"symbol":"OLD"}]"#.utf8)),
            .success(Data(#"[{"symbol":"NEW"}]"#.utf8)),
        ]
        let store = ScreenerStore(api: ScreenerAPI(client: http), now: { now })
        var query = ScreenerQuery.defaults(for: .ibkr, now: now)
        query.date = "2026-08-01"
        query.ibkrType = ScreenerIBKRType.hotByVolume.rawValue
        await store.load(.ibkr, query: query)
        store.reset()
        await store.load(.ibkr)
        XCTAssertEqual(http.requests.last?.query["date"], "2026-09-04")
        XCTAssertEqual(http.requests.last?.query["type"], "MOST_ACTIVE")
        XCTAssertEqual(http.requests.last?.query["filters"], "priceAbove=10,marketCapAbove=1000000000")
    }

    func testIBKRResultsSortedByDailyVolumeDescending() async {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"""
            [
              {"symbol":"LOW","snapshot":{"dailyBar":{"v":10}}},
              {"symbol":"HIGH","snapshot":{"dailyBar":{"v":500}}},
              {"symbol":"NONE"}
            ]
            """#.utf8)),
        ]
        let store = ScreenerStore(api: ScreenerAPI(client: http))
        await store.load(.ibkr)
        XCTAssertEqual(store.rows.map(\.symbol), ["HIGH", "LOW", "NONE"])
    }
}

final class TappableChipFlowTests: XCTestCase {
    func testLayoutWrapsWhenRowWouldOverflow() {
        let sizes = Array(repeating: CGSize(width: 60, height: TappableChipFlow.minTapLength), count: 5)
        let packed = TappableChipFlow.layout(sizes: sizes, limit: 200)
        XCTAssertEqual(packed.origins.count, 5)
        XCTAssertEqual(packed.origins[0], .zero)
        XCTAssertEqual(packed.origins[2].y, 0)
        XCTAssertGreaterThan(packed.origins[3].y, 0)
        XCTAssertEqual(packed.origins[3].x, 0)
        XCTAssertEqual(packed.size.height, TappableChipFlow.minTapLength * 2 + TappableChipFlow.spacing)
    }

    func testLayoutKeepsASingleChipWithinTheLimit() {
        let packed = TappableChipFlow.layout(
            sizes: [CGSize(width: 180, height: 50)],
            limit: 120
        )
        XCTAssertEqual(packed.origins, [.zero])
        XCTAssertEqual(packed.size.width, 120)
        XCTAssertEqual(packed.size.height, 50)
    }

    func testMinTapLengthIsAtLeastFortyFour() {
        XCTAssertGreaterThanOrEqual(TappableChipFlow.minTapLength, 44)
    }

    func testResolvedWidthIgnoresInfiniteAndMissingProposal() {
        XCTAssertEqual(TappableChipFlow.resolvedWidth(proposal: 320, arranged: 180), 320)
        XCTAssertEqual(TappableChipFlow.resolvedWidth(proposal: nil, arranged: 180), 180)
        XCTAssertEqual(TappableChipFlow.resolvedWidth(proposal: .infinity, arranged: 180), 180)
        XCTAssertEqual(TappableChipFlow.resolvedWidth(proposal: -.infinity, arranged: 180), 180)
        XCTAssertEqual(TappableChipFlow.resolvedWidth(proposal: .nan, arranged: 180), 180)
    }

    func testLayoutWithInfiniteLimitReturnsFiniteSingleRowWidth() {
        let sizes = [
            CGSize(width: 60, height: 44),
            CGSize(width: 80, height: 44),
        ]
        let packed = TappableChipFlow.layout(sizes: sizes, limit: .infinity)
        XCTAssertTrue(packed.size.width.isFinite)
        XCTAssertEqual(packed.size.width, 60 + TappableChipFlow.spacing + 80)
        XCTAssertEqual(packed.origins.map(\.y), [0, 0])
    }
}
