import XCTest
@testable import Moneyknows

final class AIAPITests: XCTestCase {
    func testDecodesAvailableSentimentBareAndEnvelope() throws {
        let json = Data(#"""
        {"available":true,"market":"US","date":"2026-09-07","language":"en","sentiment":"bullish","summary":"Risk on","confidence":"medium","scenarios":[{"label":"trend_day_up","probability":"60%","evidence":["gap"],"confirmation_after_open":["vwap"],"invalidation":["lose"]}],"key_drivers":["CPI"],"sources":[{"title":"Fed","url":"https://example.com"}]}
        """#.utf8)
        let sentiment = try AIAPI.decodeSentiment(from: json)
        guard case let .available(value) = sentiment else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(value.sentiment, .bullish)
        XCTAssertEqual(value.summary, "Risk on")
        XCTAssertEqual(value.scenarios.first?.label, "trend_day_up")
        XCTAssertEqual(value.scenarios.first?.confirmationAfterOpen, ["vwap"])
        XCTAssertEqual(value.keyDrivers, ["CPI"])
        XCTAssertEqual(value.sources.first?.url, "https://example.com")

        let enveloped = Data(#"{"data":{"available":false,"market":"US","date":"2026-09-07","language":"zh","message":"closed","allowed_refetch_window":"09:00-16:00","current_time_et":"20:00"}}"#.utf8)
        let unavailable = try AIAPI.decodeSentiment(from: enveloped)
        guard case let .unavailable(value) = unavailable else {
            return XCTFail("expected unavailable")
        }
        XCTAssertEqual(value.message, "closed")
        XCTAssertEqual(value.allowedRefetchWindow, "09:00-16:00")
        XCTAssertEqual(value.currentTimeET, "20:00")
    }

    func testDecodesCalendarBareAndEnvelope() throws {
        let json = Data(#"""
        {"market":"US","date":"2026-09-07","language":"en","day_risk":"elevated","events":[{"title":"Speeches","date":"2026-09-07","time":"10:00","impact":"Low"},{"title":"CPI","date":"2026-09-07","time":"08:30","impact":"High"}]}
        """#.utf8)
        let calendar = try AIAPI.decodeCalendar(from: json)
        XCTAssertEqual(calendar.highImpactCount, 1)
        XCTAssertEqual(calendar.sortedEvents.map(\.title), ["CPI", "Speeches"])

        let enveloped = Data(#"{"data":{"market":"US","date":"2026-09-07","events":[]}}"#.utf8)
        XCTAssertTrue(try AIAPI.decodeCalendar(from: enveloped).events.isEmpty)
    }

    func testAILanguageFollowsPreferenceThenSystem() {
        XCTAssertEqual(AILanguage.code(locale: .zh), "zh")
        XCTAssertEqual(AILanguage.code(locale: .en), "en")
        XCTAssertEqual(AILanguage.code(locale: nil, preferredLanguages: ["zh-Hans-US"]), "zh")
        XCTAssertEqual(AILanguage.code(locale: nil, preferredLanguages: ["en-US"]), "en")
    }
}

@MainActor
final class InsightsStoreTests: XCTestCase {
    func testLoadsSentimentAndCalendarIndependentlyAndSendsLanguage() async {
        let http = ScriptedHTTP()
        http.rawResultsByPath = [
            "v1/ai/intraday-market-sentiment": Data(#"{"available":true,"market":"US","date":"2026-09-07","language":"zh","sentiment":"mixed","summary":"ok"}"#.utf8),
        ]
        http.rawResults = [.failure(AppError.network)]
        let store = InsightsStore(api: AIAPI(client: http))
        await store.refreshSentiment(language: "zh")
        await store.refreshCalendar(language: "zh")
        XCTAssertEqual(http.requests.map(\.path), [
            "v1/ai/intraday-market-sentiment",
            "v1/ai/economic-calendar",
        ])
        XCTAssertEqual(http.requests[0].query["language"], "zh")
        XCTAssertEqual(http.requests[1].query["language"], "zh")
        XCTAssertTrue(store.sentiment?.isAvailable == true)
        XCTAssertNil(store.calendar)
        XCTAssertNotNil(store.calendarError)
        XCTAssertFalse(http.requests.contains { $0.path.contains("symbol-sentiment") })
    }

    func testCalendarSuccessDoesNotDependOnSentimentFailure() async {
        let http = ScriptedHTTP()
        http.rawResultsByPath = [
            "v1/ai/economic-calendar": Data(#"{"market":"US","date":"2026-09-07","events":[{"title":"CPI","date":"2026-09-07","impact":"High"}]}"#.utf8),
        ]
        http.rawResults = [.failure(AppError.network)]
        let store = InsightsStore(api: AIAPI(client: http))
        await store.refreshSentiment(language: "en")
        await store.refreshCalendar(language: "en")
        XCTAssertNil(store.sentiment)
        XCTAssertNotNil(store.sentimentError)
        XCTAssertEqual(store.calendar?.events.count, 1)
        XCTAssertEqual(http.requests[0].query["language"], "en")
    }
}
