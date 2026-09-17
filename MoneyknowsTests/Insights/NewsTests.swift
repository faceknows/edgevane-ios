import XCTest
@testable import Moneyknows

final class HTMLTextTests: XCTestCase {
    func testDecodesNamedAndNumericEntities() {
        XCTAssertEqual(HTMLText.decode("Tom &amp; Jerry &#39;Special&#39;"), "Tom & Jerry 'Special'")
        XCTAssertEqual(HTMLText.decode("Wait&mdash;now &#8217;s the time"), "Wait-now \u{2019}s the time")
    }

    func testStripsTagsAndKeepsLineBreaks() {
        XCTAssertEqual(
            HTMLText.decode("<p>First line</p><br /><div>Second&nbsp;line</div>"),
            "First line\nSecond line"
        )
    }
}

final class NewsPayloadTests: XCTestCase {
    func testParsesAlpacaAndIBKRNews() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let alpaca = MarketStreamPayload.news(
            from: Data(#"{"id":"n1","symbol":"aapl","headline":"Hello &amp; there","summary":"Body","url":"https://ex.com","timestamp":1700000000}"#.utf8),
            source: .alpaca,
            now: now
        )
        XCTAssertEqual(alpaca?.id, "n1")
        XCTAssertEqual(alpaca?.symbol, "AAPL")
        XCTAssertEqual(alpaca?.headline, "Hello & there")
        XCTAssertEqual(alpaca?.url, "https://ex.com")
        XCTAssertEqual(alpaca?.publishedAt?.timeIntervalSince1970, 1_700_000_000)

        let ibkr = MarketStreamPayload.news(
            from: Data(#"{"guid":"g2","title":"IB headline","symbols":["msft"],"publishedAt":"2023-11-14T22:13:20Z"}"#.utf8),
            source: .ibkr,
            now: now
        )
        XCTAssertEqual(ibkr?.id, "ibkr:g2")
        XCTAssertEqual(ibkr?.symbol, "MSFT")
        XCTAssertEqual(ibkr?.headline, "IB headline")
        XCTAssertEqual(ibkr?.source, "IBKR")
        XCTAssertNil(MarketStreamPayload.news(from: Data(#""nope""#.utf8), source: .alpaca))
    }

    func testKeepsIntegerAlpacaNewsID() {
        let first = MarketStreamPayload.news(
            from: Data(#"{"id":412345,"headline":"First title","updated_at":1700001000,"created_at":1700000000}"#.utf8),
            source: .alpaca,
            now: Date(timeIntervalSince1970: 1_700_000_200)
        )
        let updated = MarketStreamPayload.news(
            from: Data(#"{"id":412345,"headline":"Changed title","updated_at":1700001500,"created_at":1700000000}"#.utf8),
            source: .alpaca,
            now: Date(timeIntervalSince1970: 1_700_000_300)
        )
        XCTAssertEqual(first?.id, "412345")
        XCTAssertEqual(updated?.id, "412345")
        XCTAssertEqual(first?.publishedAt?.timeIntervalSince1970, 1_700_000_000)
        XCTAssertEqual(updated?.publishedAt?.timeIntervalSince1970, 1_700_000_000)
    }

    func testPublishedAtDoesNotUseUpdatedAt() {
        let item = MarketStreamPayload.news(
            from: Data(#"{"id":"n2","updated_at":1700001000,"created_at":1700000000}"#.utf8),
            source: .alpaca,
            now: Date(timeIntervalSince1970: 1_700_000_200)
        )
        XCTAssertEqual(item?.publishedAt?.timeIntervalSince1970, 1_700_000_000)
    }
}

@MainActor
final class NewsStoreTests: XCTestCase {
    func testDedupesCapsRestoresAndClearsOnReset() {
        let folder = "NewsStoreTests-\(UUID().uuidString)"
        let disk = DiskStore(folder: folder)
        let store = NewsStore(disk: disk)
        store.isForeground = true
        let first = NewsItem(id: "a", symbol: "AAPL", headline: "One", summary: nil, source: "Benzinga", url: nil, publishedAt: nil, receivedAt: Date(timeIntervalSince1970: 10))
        XCTAssertTrue(store.ingest(first))
        XCTAssertEqual(store.toast?.id, "a")
        XCTAssertFalse(store.ingest(first))
        XCTAssertEqual(store.items.count, 1)

        store.isForeground = false
        store.clearToast()
        for index in 1...NewsStore.capacity {
            _ = store.ingest(
                NewsItem(
                    id: "id-\(index)",
                    symbol: "MSFT",
                    headline: "H\(index)",
                    summary: nil,
                    source: nil,
                    url: nil,
                    publishedAt: nil,
                    receivedAt: Date(timeIntervalSince1970: TimeInterval(index))
                )
            )
        }
        XCTAssertEqual(store.items.count, NewsStore.capacity)
        XCTAssertEqual(store.items.first?.id, "id-\(NewsStore.capacity)")
        XCTAssertNil(store.toast)

        let restored = NewsStore(disk: disk)
        XCTAssertEqual(restored.items.count, NewsStore.capacity)
        XCTAssertNil(restored.toast)

        store.reset()
        XCTAssertTrue(store.items.isEmpty)
        let afterLogout = NewsStore(disk: disk)
        XCTAssertTrue(afterLogout.items.isEmpty)
    }

    func testResetDropsLateStreamIngestUntilActivated() {
        let folder = "NewsStoreLogout-\(UUID().uuidString)"
        let disk = DiskStore(folder: folder)
        let store = NewsStore(disk: disk)
        store.isForeground = false
        XCTAssertTrue(
            store.ingest(
                NewsItem(
                    id: "keep",
                    symbol: nil,
                    headline: "Before logout",
                    summary: nil,
                    source: nil,
                    url: nil,
                    publishedAt: nil,
                    receivedAt: Date()
                )
            )
        )
        store.reset()
        XCTAssertFalse(store.isActive)
        XCTAssertFalse(
            store.ingest(
                NewsItem(
                    id: "late",
                    symbol: nil,
                    headline: "After logout",
                    summary: nil,
                    source: nil,
                    url: nil,
                    publishedAt: nil,
                    receivedAt: Date()
                )
            )
        )
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertNil(NewsStore(disk: disk).items.first)
        store.activate()
        XCTAssertTrue(
            store.ingest(
                NewsItem(
                    id: "next",
                    symbol: nil,
                    headline: "Next session",
                    summary: nil,
                    source: nil,
                    url: nil,
                    publishedAt: nil,
                    receivedAt: Date()
                )
            )
        )
        XCTAssertEqual(store.items.first?.id, "next")
    }

    func testIntegerIDDoesNotDuplicateOnHeadlineChange() {
        let store = NewsStore(disk: DiskStore(folder: "NewsIntID-\(UUID().uuidString)"))
        store.isForeground = true
        XCTAssertTrue(store.ingest(Data(#"{"id":412345,"headline":"First"}"#.utf8), source: .alpaca))
        XCTAssertFalse(store.ingest(Data(#"{"id":412345,"headline":"Updated"}"#.utf8), source: .alpaca))
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.headline, "Updated")
        XCTAssertEqual(store.toast?.headline, "First")
    }

    func testRealtimeNewsReachesStoreWithoutUpdatingQuotes() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [.success(Data(#"{"me":["AAPL"],"all":["AAPL"]}"#.utf8))]
        let socket = FakeMarketSocket()
        let session = MarketRealtimeSession(
            subscriptions: SubscriptionStore(api: SubscribeAPI(client: http)),
            quotes: QuoteStore(),
            seconds: SecondBarStore(),
            socket: socket,
            barsAPI: BarsAPI(client: http)
        )
        session.now = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "America/New_York")!
            var parts = DateComponents()
            parts.year = 2026
            parts.month = 9
            parts.day = 5
            parts.hour = 10
            return calendar.date(from: parts)!
        }
        await session.refreshSubscriptions()
        session.disconnect()
        let folder = "NewsRealtimeTests-\(UUID().uuidString)"
        let news = NewsStore(disk: DiskStore(folder: folder))
        news.isForeground = true
        session.onNews = { news.ingest($0, source: .alpaca) }
        session.handle(
            event: MarketStreamEvent.news,
            data: Data(#"{"id":"n9","headline":"Live","symbol":"MSFT"}"#.utf8)
        )
        XCTAssertEqual(news.items.first?.id, "n9")
        XCTAssertEqual(news.items.first?.headline, "Live")
        XCTAssertNil(session.quotes.quote(for: "MSFT"))
        news.ingest(
            Data(#"{"id":"ib1","headline":"From IBKR","symbol":"TSLA"}"#.utf8),
            source: .ibkr
        )
        XCTAssertEqual(news.item(id: "ibkr:ib1")?.symbol, "TSLA")
    }
}

final class SocketCallbackGateTests: XCTestCase {
    func testInvalidateDropsQueuedCallbacks() {
        let gate = SocketCallbackGate()
        let snapshot = gate.snapshot()
        XCTAssertTrue(gate.isCurrent(snapshot))
        gate.invalidate()
        XCTAssertFalse(gate.isCurrent(snapshot))
        XCTAssertTrue(gate.isCurrent(gate.snapshot()))
    }
}
