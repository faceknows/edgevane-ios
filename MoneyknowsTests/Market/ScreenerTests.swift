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
    }
}

@MainActor
final class ScreenerStoreTests: XCTestCase {
    func testAllEightKindsHaveDefaultQueries() {
        XCTAssertEqual(ScreenerKind.allCases.count, 8)
        let priceSlope = ScreenerQuery.defaults(for: .priceSlope, now: Date(timeIntervalSince1970: 1_778_000_000))
        XCTAssertEqual(priceSlope.spanMinutes, "30")
        XCTAssertEqual(priceSlope.minPrice, "6")
        XCTAssertFalse(priceSlope.date.isEmpty)
        XCTAssertEqual(ScreenerQuery.defaults(for: .atr).barCount, "10")
        XCTAssertEqual(ScreenerQuery.defaults(for: .stair).barCount, "0")
        XCTAssertEqual(ScreenerQuery.defaults(for: .stair).timeFrame, "1Min")
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
        let http = ScriptedHTTP()
        http.rawResults = [.success(Data("[]".utf8))]
        let store = ScreenerStore(api: ScreenerAPI(client: http))
        await store.load(.priceSlope)
        XCTAssertEqual(http.requests.first?.path, "intraday-stocks/price-slope")
        let endTime = try XCTUnwrap(http.requests.first?.query["endTime"])
        XCTAssertEqual(MarketClock.normalizeEndTime(endTime), endTime)
        XCTAssertFalse(endTime.isEmpty)
    }

    func testInvalidPriceSlopeEndTimeDoesNotFetch() async {
        let http = ScriptedHTTP()
        let store = ScreenerStore(api: ScreenerAPI(client: http))
        var query = ScreenerQuery.defaults(for: .priceSlope)
        query.endTime = "08:00"
        await store.load(.priceSlope, query: query)
        XCTAssertTrue(http.requests.isEmpty)
        XCTAssertEqual(store.errorText, L10n.Market.invalidEndTime)
        XCTAssertTrue(store.rows.isEmpty)
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

    func testStairDefaultSendsBarCountZero() async {
        let http = ScriptedHTTP()
        http.rawResults = [.success(Data("[]".utf8))]
        let store = ScreenerStore(api: ScreenerAPI(client: http))
        await store.load(.stair)
        XCTAssertEqual(http.requests.first?.path, "intraday-stocks/top-stair-setups")
        XCTAssertEqual(http.requests.first?.query["barCount"], "0")
        XCTAssertEqual(http.requests.first?.query["timeFrame"], "1Min")
        XCTAssertEqual(http.requests.first?.query["direction"], "up")
    }

    func testATRDefaultKeepsBarCountTen() async {
        let http = ScriptedHTTP()
        http.rawResults = [.success(Data("[]".utf8))]
        let store = ScreenerStore(api: ScreenerAPI(client: http))
        await store.load(.atr)
        XCTAssertEqual(http.requests.first?.query["barCount"], "10")
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
