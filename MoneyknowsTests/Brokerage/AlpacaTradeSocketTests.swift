import XCTest
@testable import Moneyknows

final class AlpacaTradeSocketTests: XCTestCase {
    func testRoutesAuthorizationListenAndTradeUpdate() {
        let authorized = AlpacaTradeSocketEnvelope.decode(Data(#"""
        {"stream":"authorization","data":{"status":"authorized"}}
        """#.utf8))
        XCTAssertEqual(authorized.map(AlpacaTradeSocketEnvelope.route), [.authorized])

        let listening = AlpacaTradeSocketEnvelope.decode(Data(#"""
        {"stream":"listening","data":{"streams":["trade_updates"]}}
        """#.utf8))
        XCTAssertEqual(listening.map(AlpacaTradeSocketEnvelope.route), [.listening])

        let update = AlpacaTradeSocketEnvelope.decode(Data(#"""
        [{"stream":"trade_updates","data":{"event":"new","order":{"id":"o1","symbol":"AAPL","side":"buy","type":"limit","status":"new","qty":"1"}}}]
        """#.utf8))
        XCTAssertEqual(update.map(AlpacaTradeSocketEnvelope.route), [.tradeUpdate])
        XCTAssertEqual(MarketStreamPayload.order(from: AlpacaTradeSocketEnvelope.encode(update[0])!)?.id, "o1")
    }

    func testRoutesAuthenticatedAliasAndErrors() {
        let authenticated = AlpacaTradeSocketEnvelope.decode(Data(#"""
        {"T":"success","msg":"authenticated"}
        """#.utf8))
        XCTAssertEqual(authenticated.map(AlpacaTradeSocketEnvelope.route), [.authorized])

        let unauthorized = AlpacaTradeSocketEnvelope.decode(Data(#"""
        {"stream":"authorization","data":{"action":"authenticate","status":"unauthorized"}}
        """#.utf8))
        XCTAssertEqual(unauthorized.map(AlpacaTradeSocketEnvelope.route), [.unauthorized])
        XCTAssertEqual(AlpacaTradeSocketEnvelope.failure(for: .unauthorized), .unauthorized)

        let authFailed = AlpacaTradeSocketEnvelope.decode(Data(#"""
        {"stream":"error","data":{"message":"auth failed"}}
        """#.utf8))
        XCTAssertEqual(authFailed.map(AlpacaTradeSocketEnvelope.route), [.unauthorized])

        let code401 = AlpacaTradeSocketEnvelope.decode(Data(#"""
        {"T":"error","code":401,"msg":"key is invalid"}
        """#.utf8))
        XCTAssertEqual(code401.map(AlpacaTradeSocketEnvelope.route), [.unauthorized])

        let transient = AlpacaTradeSocketEnvelope.decode(Data(#"""
        {"stream":"error","data":{"message":"timeout"}}
        """#.utf8))
        XCTAssertEqual(transient.map(AlpacaTradeSocketEnvelope.route), [.error])
        XCTAssertEqual(AlpacaTradeSocketEnvelope.failure(for: .error), .retry)
    }

    func testPaperAndLiveStreamURLs() {
        XCTAssertEqual(
            BrokerageEnvironment.paper.streamURL.absoluteString,
            "wss://paper-api.alpaca.markets/stream"
        )
        XCTAssertEqual(
            BrokerageEnvironment.live.streamURL.absoluteString,
            "wss://api.alpaca.markets/stream"
        )
    }
}
