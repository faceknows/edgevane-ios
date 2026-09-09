import XCTest
@testable import Moneyknows

final class SubscribeAPITests: XCTestCase {
    func testDecodesMeAndAll() throws {
        let json = Data(#"{"all":[" msft ","AAPL"],"me":["aapl"]}"#.utf8)
        let listed = try SubscribeAPI.decodeList(from: json)
        XCTAssertEqual(listed.all, ["AAPL", "MSFT"])
        XCTAssertEqual(listed.me, ["AAPL"])
    }

    func testDecodesEnvelope() throws {
        let json = Data(#"{"data":{"all":["TSLA"],"me":["TSLA"]}}"#.utf8)
        let listed = try SubscribeAPI.decodeList(from: json)
        XCTAssertEqual(listed.me, ["TSLA"])
    }
}

final class MarketStreamPayloadTests: XCTestCase {
    func testParsesTradeCoreAndWrappedUpdate() {
        let core = MarketStreamPayload.trade(from: Data(#"{"s":"aapl","p":12.5}"#.utf8))
        XCTAssertEqual(core?.symbol, "AAPL")
        XCTAssertEqual(core?.price, 12.5)
        let wrapped = MarketStreamPayload.trade(from: Data(#"{"symbol":"msft","trade":{"p":9}}"#.utf8))
        XCTAssertEqual(wrapped?.symbol, "MSFT")
        XCTAssertEqual(wrapped?.price, 9)
    }

    func testParsesQuoteWithoutRollingCalendarDay() {
        let quote = MarketStreamPayload.quote(from: Data(#"{"s":"AAPL","bp":10.1,"ap":10.3}"#.utf8))
        XCTAssertEqual(quote?.bid, 10.1)
        XCTAssertEqual(quote?.ask, 10.3)
        let wrapped = MarketStreamPayload.quote(from: Data(#"{"symbol":"AAPL","quote":{"bp":11,"ap":12}}"#.utf8))
        XCTAssertEqual(wrapped?.bid, 11)
        XCTAssertEqual(wrapped?.ask, 12)
    }

    func testParsesSecondBarAndNestedSnapshotMaps() {
        let bar = MarketStreamPayload.secondBar(from: Data(
            #"{"symbol":"AAPL","bar":{"o":1,"h":2,"l":0.5,"c":1.5,"v":10,"t":1700000100}}"#.utf8
        ))
        XCTAssertEqual(bar?.symbol, "AAPL")
        XCTAssertEqual(bar?.close, 1.5)
        XCTAssertEqual(bar?.volume, 10)
        XCTAssertEqual(bar?.time.timeIntervalSince1970, 1_700_000_100)
        let snapshot = Data(#"""
        {"quotes":{"quotes":{"AAPL":{"bp":1,"ap":2}}},"trades":{"trades":{"AAPL":{"p":1.5}}}}
        """#.utf8)
        XCTAssertEqual(MarketStreamPayload.snapshotQuotes(from: snapshot).first?.bid, 1)
        XCTAssertEqual(MarketStreamPayload.snapshotTrades(from: snapshot).first?.price, 1.5)
    }

    func testParsesNestedTradeUpdateOrder() {
        let order = MarketStreamPayload.order(from: Data(#"""
        {"data":{"event":"fill","order":{"id":"o1","symbol":"msft","side":"sell","type":"limit","status":"filled","qty":"3","filled_qty":"3","filled_avg_price":"9.5","limit_price":"9.4","client_order_id":"auto-tp-1","parent_order_id":"parent-1"}}}
        """#.utf8))
        XCTAssertEqual(order?.id, "o1")
        XCTAssertEqual(order?.symbol, "MSFT")
        XCTAssertEqual(order?.side, "sell")
        XCTAssertEqual(order?.status, "filled")
        XCTAssertEqual(order?.filledAvgPrice, 9.5)
        XCTAssertEqual(order?.clientOrderId, "auto-tp-1")
        XCTAssertEqual(order?.parentOrderId, "parent-1")
        XCTAssertNil(MarketStreamPayload.order(from: Data(#"{"hello":"nope"}"#.utf8)))
    }
}

@MainActor
final class QuoteStoreTests: XCTestCase {
    func testPrefersSocketQuoteAndFallsBackToLast() {
        let store = QuoteStore()
        store.applyTrade(symbol: "aapl", price: 10)
        XCTAssertEqual(store.quote(for: "AAPL")?.displayBid, 10)
        store.applyQuote(StreamQuote(symbol: "AAPL", bid: 9.9, ask: 10.1, bidSize: 1, askSize: 2))
        XCTAssertEqual(store.quote(for: "AAPL")?.displayBid, 9.9)
        XCTAssertEqual(store.quote(for: "AAPL")?.displayAsk, 10.1)
        store.applySnapshot(
            quotes: [StreamQuote(symbol: "AAPL", bid: 1, ask: 2, bidSize: nil, askSize: nil)],
            trades: []
        )
        XCTAssertEqual(store.quote(for: "AAPL")?.displayBid, 9.9)
        XCTAssertEqual(store.quote(for: "AAPL")?.snapshotBid, 1)
        store.applySnapshot(
            quotes: [StreamQuote(symbol: "MSFT", bid: 20, ask: 21, bidSize: nil, askSize: nil)],
            trades: [("MSFT", 20.5)]
        )
        XCTAssertEqual(store.quote(for: "MSFT")?.last, 20.5)
        XCTAssertEqual(store.quote(for: "MSFT")?.displayBid, 20)
        store.remove(["MSFT"])
        XCTAssertNil(store.quote(for: "MSFT"))
    }

    func testSnapshotKeepsSizesUntilSocketQuoteArrives() {
        let store = QuoteStore()
        store.applySnapshot(
            quotes: [StreamQuote(symbol: "AAPL", bid: 17.87, ask: 17.88, bidSize: 300, askSize: 800)],
            trades: []
        )
        XCTAssertEqual(store.quote(for: "AAPL")?.displayBid, 17.87)
        XCTAssertEqual(store.quote(for: "AAPL")?.displayAsk, 17.88)
        XCTAssertEqual(store.quote(for: "AAPL")?.displayBidSize, 300)
        XCTAssertEqual(store.quote(for: "AAPL")?.displayAskSize, 800)
        store.applyQuote(StreamQuote(symbol: "AAPL", bid: 17.86, ask: 17.89, bidSize: 100, askSize: 200))
        XCTAssertEqual(store.quote(for: "AAPL")?.displayBidSize, 100)
        XCTAssertEqual(store.quote(for: "AAPL")?.displayAskSize, 200)
    }

    func testSnapshotSizeNotUsedWithSocketPrice() {
        var quote = SymbolQuote(
            snapshotBid: 17.87,
            snapshotAsk: 17.88,
            snapshotBidSize: 300,
            snapshotAskSize: 800
        )
        XCTAssertEqual(quote.displayBidSize, 300)
        XCTAssertEqual(quote.displayAskSize, 800)

        quote.bid = 17.85
        quote.ask = 17.90
        XCTAssertEqual(quote.liveBid, 17.85)
        XCTAssertNil(quote.displayBidSize)
        XCTAssertNil(quote.displayAskSize)

        quote.bidSize = 100
        XCTAssertEqual(quote.displayBidSize, 100)
        XCTAssertNil(quote.displayAskSize)
    }

    func testSocketPriceWithoutSizeDoesNotKeepPriorSize() {
        let store = QuoteStore()
        store.applyQuote(StreamQuote(symbol: "AAPL", bid: 17.86, ask: 17.89, bidSize: 100, askSize: 200))
        store.applyQuote(StreamQuote(symbol: "AAPL", bid: 17.85, ask: 17.90, bidSize: nil, askSize: nil))
        XCTAssertEqual(store.quote(for: "AAPL")?.displayBid, 17.85)
        XCTAssertNil(store.quote(for: "AAPL")?.displayBidSize)
        XCTAssertNil(store.quote(for: "AAPL")?.displayAskSize)
    }
}

@MainActor
final class SecondBarStoreTests: XCTestCase {
    func testCapsRingAndUsesVolumeDeltaForSameSecond() {
        let store = SecondBarStore()
        let start = Date(timeIntervalSince1970: 1_700_000_100)
        store.apply(StreamSecondBar(
            symbol: "AAPL", time: start, timeKey: "t1",
            open: 1, high: 2, low: 1, close: 1.5, volume: 10
        ))
        store.apply(StreamSecondBar(
            symbol: "AAPL", time: start, timeKey: "t1",
            open: 1, high: 3, low: 1, close: 2, volume: 15
        ))
        XCTAssertEqual(store.bars(for: "AAPL").count, 1)
        XCTAssertEqual(store.bars(for: "AAPL")[0].high, 3)
        XCTAssertEqual(store.bars(for: "AAPL")[0].volume, 15)
        for offset in 1...SecondBarStore.capacity {
            store.apply(StreamSecondBar(
                symbol: "AAPL",
                time: start.addingTimeInterval(TimeInterval(offset)),
                timeKey: "t\(offset)",
                open: 1, high: 1, low: 1, close: 1, volume: 1
            ))
        }
        XCTAssertEqual(store.bars(for: "AAPL").count, SecondBarStore.capacity)
        store.remove(["AAPL"])
        XCTAssertTrue(store.bars(for: "AAPL").isEmpty)
    }
}

@MainActor
final class MarketRealtimeSessionTests: XCTestCase {
    func testIgnoresUnsubscribedEventsAndClearsOnUnsubscribe() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"{"me":["AAPL"],"all":["AAPL"]}"#.utf8)),
            .success(Data("{}".utf8)),
            .success(Data(#"{}"#.utf8)),
            .success(Data(#"{"me":[],"all":[]}"#.utf8)),
        ]
        let socket = FakeMarketSocket()
        let session = MarketRealtimeSession(
            subscriptions: SubscriptionStore(api: SubscribeAPI(client: http)),
            quotes: QuoteStore(),
            seconds: SecondBarStore(),
            socket: socket,
            barsAPI: BarsAPI(client: http)
        )
        await session.refreshSubscriptions()
        XCTAssertEqual(session.subscriptions.me, ["AAPL"])
        session.handle(event: MarketStreamEvent.trade, data: Data(#"{"s":"MSFT","p":9}"#.utf8))
        XCTAssertNil(session.quotes.quote(for: "MSFT"))
        session.handle(event: MarketStreamEvent.trade, data: Data(#"{"s":"AAPL","p":11}"#.utf8))
        session.handle(
            event: MarketStreamEvent.quote,
            data: Data(#"{"s":"AAPL","bp":10.9,"ap":11.1}"#.utf8)
        )
        session.handle(
            event: MarketStreamEvent.secondTrade,
            data: Data(#"{"s":"AAPL","o":1,"h":2,"l":1,"c":1.5,"v":3,"t":1700000100}"#.utf8)
        )
        XCTAssertEqual(session.quotes.quote(for: "AAPL")?.last, 11)
        XCTAssertEqual(session.quotes.quote(for: "AAPL")?.bid, 10.9)
        XCTAssertEqual(session.seconds.bars(for: "AAPL").count, 1)
        var received: Data?
        session.onTradeUpdate = { received = $0 }
        let payload = Data(#"{"order":{"id":"o1","symbol":"AAPL"}}"#.utf8)
        session.handle(event: MarketStreamEvent.tradeUpdates, data: payload)
        XCTAssertEqual(received, payload)
        try await session.unsubscribe(["AAPL"])
        XCTAssertFalse(session.subscriptions.contains("AAPL"))
        XCTAssertNil(session.quotes.quote(for: "AAPL"))
        XCTAssertTrue(session.seconds.bars(for: "AAPL").isEmpty)
    }

    func testSurfacesGatewaySubscribeErrorAndResetClearsMemory() async {
        let http = ScriptedHTTP()
        http.rawResults = [
            .failure(AppError.http(status: 403, message: "too many symbols", errorCode: nil)),
            .success(Data(#"{"me":["AAPL"],"all":["AAPL"]}"#.utf8)),
            .success(Data("{}".utf8)),
        ]
        let socket = FakeMarketSocket()
        socket.connect(token: "token")
        let session = MarketRealtimeSession(
            subscriptions: SubscriptionStore(api: SubscribeAPI(client: http)),
            quotes: QuoteStore(),
            seconds: SecondBarStore(),
            socket: socket,
            barsAPI: BarsAPI(client: http)
        )
        do {
            try await session.subscribe(["AAPL"])
            XCTFail("subscribe should fail")
        } catch {
            XCTAssertEqual(UserFacingError.message(from: error), "too many symbols")
        }
        XCTAssertFalse(session.subscriptions.contains("AAPL"))
        await session.refreshSubscriptions()
        session.handle(event: MarketStreamEvent.trade, data: Data(#"{"s":"AAPL","p":11}"#.utf8))
        XCTAssertEqual(session.quotes.quote(for: "AAPL")?.last, 11)
        session.reset()
        XCTAssertTrue(session.subscriptions.me.isEmpty)
        XCTAssertNil(session.quotes.quote(for: "AAPL"))
        XCTAssertEqual(socket.status, .closed)
        XCTAssertNil(socket.connectedToken)
    }
}

final class SecondChartAssemblerTests: XCTestCase {
    func testFollowsLatestWithVolumeAndWithoutVWAP() {
        let start = Date(timeIntervalSince1970: 1_700_000_100)
        let bars = (0..<5).map { offset in
            Bar(
                time: start.addingTimeInterval(TimeInterval(offset)),
                open: 1, high: 1, low: 1, close: 1, volume: 1
            )
        }
        let model = SecondChartAssembler.model(bars1s: bars, interval: .five, style: .line)
        XCTAssertEqual(model.bars.count, 1)
        XCTAssertTrue(model.followLatest)
        XCTAssertTrue(model.overlays.isEmpty)
        XCTAssertTrue(model.priceLines.isEmpty)
        XCTAssertTrue(model.showVolume)
        XCTAssertEqual(model.style, .line)
        XCTAssertFalse(
            SecondChartAssembler.model(bars1s: bars, interval: .five, style: .line, showVolume: false).showVolume
        )
    }
}

@MainActor
final class FakeMarketSocket: MarketSocketing {
    private(set) var status: SocketStatus = .closed
    private var events: [String: [(Data) -> Void]] = [:]
    private var statusHandlers: [(SocketStatus) -> Void] = []
    var connectedToken: String?

    func connect(token: String) {
        connectedToken = token
        status = .open
        statusHandlers.forEach { $0(.open) }
    }

    func disconnect() {
        connectedToken = nil
        status = .closed
        statusHandlers.forEach { $0(.closed) }
    }

    func on(_ event: String, handler: @escaping (Data) -> Void) {
        events[event, default: []].append(handler)
    }

    func onStatusChange(_ handler: @escaping (SocketStatus) -> Void) {
        statusHandlers.append(handler)
    }
}
