import XCTest
@testable import Moneyknows

final class DailyPnLTests: XCTestCase {
    func testToneUsesWarningAtThreshold() {
        XCTAssertEqual(DailyPnL.tone(percent: -1.5), .warning)
        XCTAssertEqual(DailyPnL.tone(percent: -3), .warning)
        XCTAssertEqual(DailyPnL.tone(percent: -1.49), .loss)
        XCTAssertEqual(DailyPnL.tone(percent: 0), .profit)
        XCTAssertEqual(DailyPnL.tone(percent: 2), .profit)
        XCTAssertEqual(DailyPnL.tone(percent: nil), .profit)
    }

    func testPortfolioPercentWhenLastEquityIsZero() {
        let snapshot = Portfolio(
            equity: 10,
            lastEquity: 0,
            cash: 0,
            buyingPower: 0,
            portfolioValue: 10,
            tradingBlocked: false
        )
        XCTAssertEqual(snapshot.profitLoss, 10)
        XCTAssertEqual(snapshot.profitLossPercent, 0)
    }

    func testPortfolioPercentFromEquityChange() {
        let snapshot = Portfolio(
            equity: 98.5,
            lastEquity: 100,
            cash: 1,
            buyingPower: 2,
            portfolioValue: 98.5,
            tradingBlocked: false
        )
        XCTAssertEqual(snapshot.profitLoss, -1.5, accuracy: 0.0001)
        XCTAssertEqual(snapshot.profitLossPercent, -1.5, accuracy: 0.0001)
        XCTAssertEqual(DailyPnL.tone(percent: snapshot.profitLossPercent), .warning)
    }
}

final class OrderFilterTests: XCTestCase {
    func testFilledIncludesPartialAndNewIsExactStatus() {
        XCTAssertTrue(sampleOrder(status: .filled).matches(.filled))
        XCTAssertTrue(sampleOrder(status: .partiallyFilled).matches(.filled))
        XCTAssertFalse(sampleOrder(status: .new).matches(.filled))
        XCTAssertTrue(sampleOrder(status: .new).matches(.new))
        XCTAssertFalse(sampleOrder(status: .accepted).matches(.new))
        XCTAssertTrue(sampleOrder(status: .canceled).matches(.all))
        var canceledFill = sampleOrder(status: .canceled)
        canceledFill.quantity = 10
        canceledFill.filledQuantity = 4
        canceledFill.limitPrice = 11
        canceledFill.filledAvgPrice = 10.5
        XCTAssertTrue(canceledFill.matches(.filled))
        XCTAssertEqual(canceledFill.listQuantity, 4)
        XCTAssertEqual(canceledFill.listPrice, 10.5)
    }

    func testCancellableStatusesExcludePendingCancel() {
        XCTAssertTrue(sampleOrder(status: .new).isCancellable)
        XCTAssertTrue(sampleOrder(status: .partiallyFilled).isCancellable)
        XCTAssertTrue(sampleOrder(status: .accepted).isCancellable)
        XCTAssertTrue(sampleOrder(status: .pendingNew).isCancellable)
        XCTAssertTrue(sampleOrder(status: .acceptedForBidding).isCancellable)
        XCTAssertFalse(sampleOrder(status: .pendingCancel).isCancellable)
        XCTAssertFalse(sampleOrder(status: .held).isCancellable)
        XCTAssertFalse(sampleOrder(status: .filled).isCancellable)
        XCTAssertFalse(sampleOrder(status: .canceled).isCancellable)
        XCTAssertFalse(sampleOrder(status: .calculated).isCancellable)
        XCTAssertFalse(OrderStatus.calculated.isOpen)
        XCTAssertTrue(OrderStatus.held.isOpen)
    }

    func testStatusAndTypeTitlesAreLocalized() {
        XCTAssertEqual(OrderStatus.filled.title, L10n.Orders.statusFilled)
        XCTAssertEqual(OrderType.limit.title, L10n.Orders.typeLimit)
        XCTAssertEqual(OrderStatus(brokerValue: "mystery_status"), .other)
        XCTAssertEqual(OrderType(brokerValue: "iceberg"), .other)
        XCTAssertEqual(OrderStatus(brokerValue: "held"), .held)
        XCTAssertEqual(OrderStatus.held.title, L10n.Orders.statusHeld)
        XCTAssertEqual(OrderStatus.other.title, L10n.Orders.statusOther)
    }

    func testFilledOrdersExposeFillQuantityAndAveragePrice() {
        var filled = sampleOrder(status: .filled)
        filled.quantity = 10
        filled.filledQuantity = 4
        filled.limitPrice = 11
        filled.filledAvgPrice = 10.5
        XCTAssertEqual(filled.listQuantity, 4)
        XCTAssertEqual(filled.listPrice, 10.5)

        var filledWithoutAverage = filled
        filledWithoutAverage.filledAvgPrice = nil
        XCTAssertNil(filledWithoutAverage.listPrice)

        let open = sampleOrder(status: .new)
        XCTAssertEqual(open.listQuantity, 10)
        XCTAssertEqual(open.listPrice, 11)

        var canceledWithoutFill = sampleOrder(status: .canceled)
        canceledWithoutFill.quantity = 10
        canceledWithoutFill.filledQuantity = 0
        canceledWithoutFill.limitPrice = 11
        XCTAssertFalse(canceledWithoutFill.matches(.filled))
        XCTAssertEqual(canceledWithoutFill.listQuantity, 10)
        XCTAssertEqual(canceledWithoutFill.listPrice, 11)
    }

    func testOpenPartialFillExposesRemainingQuantityAndLimit() {
        let partial = sampleOrder(status: .partiallyFilled)
        XCTAssertTrue(partial.showsPartialFill)
        XCTAssertEqual(partial.quantity, 10)
        XCTAssertEqual(partial.filledQuantity, 4)
        XCTAssertEqual(partial.remainingQuantity, 6)
        XCTAssertEqual(partial.filledAvgPrice, 11)
        XCTAssertEqual(partial.limitPrice, 11)
        XCTAssertTrue(partial.matches(.filled))
        XCTAssertTrue(partial.isCancellable)

        let filled = sampleOrder(status: .filled)
        XCTAssertFalse(filled.showsPartialFill)
        XCTAssertEqual(filled.remainingQuantity, 0)

        let open = sampleOrder(status: .new)
        XCTAssertFalse(open.showsPartialFill)
        XCTAssertEqual(open.remainingQuantity, 10)

        let copy = L10n.Orders.partialFill("4", "10", "6")
        XCTAssertTrue(copy.contains("4"))
        XCTAssertTrue(copy.contains("10"))
        XCTAssertTrue(copy.contains("6"))

        var stop = sampleOrder(status: .partiallyFilled)
        stop.type = .stop
        stop.limitPrice = nil
        stop.stopPrice = 9
        XCTAssertTrue(stop.showsPartialFill)
        XCTAssertNil(stop.limitPrice)
        XCTAssertEqual(stop.stopPrice, 9)
        XCTAssertEqual(L10n.Orders.priceStop("9.00").contains("9"), true)

        var stopLimit = sampleOrder(status: .partiallyFilled)
        stopLimit.type = .stopLimit
        stopLimit.limitPrice = 11
        stopLimit.stopPrice = 9
        XCTAssertEqual(stopLimit.limitPrice, 11)
        XCTAssertEqual(stopLimit.stopPrice, 9)
    }
}

final class AlpacaTradingAPIDecodingTests: XCTestCase {
    func testDecodesAccountStringNumbersAndTradingBlocked() throws {
        let dto = try AlpacaTradingAPI.decodeAccount(from: Data(#"""
        {"id":"acct-1","equity":"101.50","last_equity":"100","cash":"12.3","buying_power":"40","portfolio_value":"101.50","trading_blocked":true}
        """#.utf8))
        XCTAssertEqual(dto.id, "acct-1")
        XCTAssertEqual(dto.equity, 101.5)
        XCTAssertEqual(dto.lastEquity, 100)
        XCTAssertEqual(dto.cash, 12.3)
        XCTAssertEqual(dto.buyingPower, 40)
        XCTAssertEqual(dto.portfolioValue, 101.5)
        XCTAssertTrue(dto.tradingBlocked)
    }

    func testDecodesPositionsAndScalesUnrealizedPercent() throws {
        let rows = try AlpacaTradingAPI.decodePositions(from: Data(#"""
        [{"symbol":" aapl ","qty":"10","side":"long","avg_entry_price":"10","current_price":"11","market_value":"110","cost_basis":"100","unrealized_pl":"10","unrealized_plpc":"0.025"}]
        """#.utf8))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].symbol, "AAPL")
        XCTAssertEqual(rows[0].qty, 10)
        XCTAssertEqual(rows[0].unrealizedPLPercent, 0.025)
    }

    func testDecodesOrdersAndRejectsMissingSymbol() {
        XCTAssertThrowsError(try AlpacaTradingAPI.decodeOrders(from: Data(#"""
        [
          {"id":"keep","symbol":"msft","side":"sell","type":"limit","status":"new","qty":"3","filled_qty":"0","limit_price":"9.5","submitted_at":"2024-01-15T14:30:00.123Z"},
          {"id":"drop","side":"buy","status":"new","qty":"1"}
        ]
        """#.utf8))) { error in
            XCTAssertEqual(error as? AppError, .decoding)
        }
    }

    func testDecodesNestedLegs() throws {
        let rows = try AlpacaTradingAPI.decodeOrders(from: Data(#"""
        [
          {
            "id":"parent","symbol":"AAPL","side":"buy","type":"limit","status":"new","qty":"2",
            "legs":[
              {"id":"tp","symbol":"AAPL","side":"sell","type":"limit","status":"held","qty":"2","limit_price":"12"},
              {"id":"sl","symbol":"AAPL","side":"sell","type":"stop","status":"held","qty":"2","stop_price":"8"}
            ]
          }
        ]
        """#.utf8))
        XCTAssertEqual(rows.map(\.id), ["parent", "tp", "sl"])
        XCTAssertEqual(rows[1].type, "limit")
        XCTAssertEqual(rows[2].type, "stop")
        XCTAssertEqual(rows[1].status, "held")
        XCTAssertEqual(rows[2].status, "held")
    }

    func testClosedPageCursorUsesTopLevelOrderId() throws {
        let page = try AlpacaTradingAPI.decodeOrderPage(
            from: Data(#"""
            [{
              "id":"parent","symbol":"AAPL","side":"buy","type":"limit","status":"filled","qty":"2",
              "filled_qty":"2","filled_avg_price":"10",
              "submitted_at":"2024-01-02T00:00:00Z","updated_at":"2024-01-01T00:00:00Z",
              "legs":[{
                "id":"leg","symbol":"AAPL","side":"sell","type":"limit","status":"filled","qty":"2",
                "filled_qty":"2","filled_avg_price":"12",
                "submitted_at":"2024-01-03T00:00:00Z","updated_at":"2024-01-04T00:00:00Z"
              }]
            }]
            """#.utf8),
            requestedLimit: 1
        )
        XCTAssertEqual(page.orders.map(\.id), ["parent", "leg"])
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.nextBeforeOrderId, "parent")
        XCTAssertNotEqual(page.nextBeforeOrderId, "leg")
    }

    func testClosedPageAllowsMissingSubmittedAtWhenUsingOrderId() throws {
        let page = try AlpacaTradingAPI.decodeOrderPage(
            from: Data(#"""
            [{"id":"a","symbol":"AAPL","side":"buy","type":"limit","status":"filled","qty":"1","filled_qty":"1","filled_avg_price":"1"}]
            """#.utf8),
            requestedLimit: 1
        )
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.nextBeforeOrderId, "a")
    }

    func testFilledOrderMissingAveragePriceThrows() {
        XCTAssertThrowsError(try AlpacaTradingAPI.decodeOrders(from: Data(#"""
        [{"id":"filled","symbol":"AAPL","side":"buy","type":"limit","status":"filled","qty":"2","filled_qty":"2"}]
        """#.utf8))) { error in
            XCTAssertEqual(error as? AppError, .decoding)
        }
    }

    func testFilledOrderMissingFilledQtyThrows() {
        XCTAssertThrowsError(try AlpacaTradingAPI.decodeOrders(from: Data(#"""
        [{"id":"filled","symbol":"AAPL","side":"buy","type":"limit","status":"filled","qty":"2","filled_avg_price":"10.5"}]
        """#.utf8))) { error in
            XCTAssertEqual(error as? AppError, .decoding)
        }
    }

    func testPartiallyFilledMissingFilledQtyThrows() {
        XCTAssertThrowsError(try AlpacaTradingAPI.decodeOrders(from: Data(#"""
        [{"id":"partial","symbol":"AAPL","side":"buy","type":"limit","status":"partially_filled","qty":"2","filled_avg_price":"10.5"}]
        """#.utf8))) { error in
            XCTAssertEqual(error as? AppError, .decoding)
        }
    }

    func testFilledZeroQuantityThrows() {
        XCTAssertThrowsError(try AlpacaTradingAPI.decodeOrders(from: Data(#"""
        [{"id":"filled","symbol":"AAPL","side":"buy","type":"limit","status":"filled","qty":"2","filled_qty":"0","filled_avg_price":"10.5"}]
        """#.utf8))) { error in
            XCTAssertEqual(error as? AppError, .decoding)
        }
    }

    func testFilledZeroAveragePriceThrows() {
        XCTAssertThrowsError(try AlpacaTradingAPI.decodeOrders(from: Data(#"""
        [{"id":"filled","symbol":"AAPL","side":"buy","type":"limit","status":"filled","qty":"2","filled_qty":"2","filled_avg_price":"0"}]
        """#.utf8))) { error in
            XCTAssertEqual(error as? AppError, .decoding)
        }
    }

    func testFilledQuantityAboveOrderQtyThrows() {
        XCTAssertThrowsError(try AlpacaTradingAPI.decodeOrders(from: Data(#"""
        [{"id":"filled","symbol":"AAPL","side":"buy","type":"limit","status":"filled","qty":"2","filled_qty":"3","filled_avg_price":"10.5"}]
        """#.utf8))) { error in
            XCTAssertEqual(error as? AppError, .decoding)
        }
    }

    func testAccountMissingTradingBlockedThrows() {
        XCTAssertThrowsError(try AlpacaTradingAPI.decodeAccount(from: Data(#"""
        {"id":"acct-1","equity":"101.50","last_equity":"100","cash":"12.3","buying_power":"40"}
        """#.utf8))) { error in
            XCTAssertEqual(error as? AppError, .decoding)
        }
    }

    func testAccountNumericTradingBlockedThrows() {
        XCTAssertThrowsError(try AlpacaTradingAPI.decodeAccount(from: Data(#"""
        {"id":"acct-1","equity":"101.50","last_equity":"100","cash":"12.3","buying_power":"40","trading_blocked":0}
        """#.utf8))) { error in
            XCTAssertEqual(error as? AppError, .decoding)
        }
    }

    func testAccountMissingEquityThrows() {
        XCTAssertThrowsError(try AlpacaTradingAPI.decodeAccount(from: Data(#"""
        {"id":"acct-1","last_equity":"100","cash":"1","buying_power":"2"}
        """#.utf8))) { error in
            XCTAssertEqual(error as? AppError, .decoding)
        }
    }

    func testPositionMissingQtyThrows() {
        XCTAssertThrowsError(try AlpacaTradingAPI.decodePositions(from: Data(#"""
        [{"symbol":"AAPL","side":"long","avg_entry_price":"10","current_price":"11","market_value":"110","cost_basis":"100","unrealized_pl":"10","unrealized_plpc":"0.025"}]
        """#.utf8))) { error in
            XCTAssertEqual(error as? AppError, .decoding)
        }
    }
}

@MainActor
final class AlpacaBrokerageTests: XCTestCase {
    func testMapsPercentAndOrderEnums() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"""
            {"id":"acct-1","equity":"98.5","last_equity":"100","cash":"1","buying_power":"2","portfolio_value":"98.5","trading_blocked":false}
            """#.utf8)),
            .success(Data(#"""
            [{"symbol":"AAPL","qty":"4","side":"short","avg_entry_price":"20","current_price":"18","market_value":"-72","cost_basis":"-80","unrealized_pl":"8","unrealized_plpc":"0.1"}]
            """#.utf8)),
            .success(Data(#"""
            [
              {"id":"keep","symbol":"AAPL","side":"buy","type":"limit","status":"new","qty":"4","filled_qty":"0","submitted_at":"2024-01-16T15:00:00Z"},
              {"id":"unknown","symbol":"MSFT","side":"buy","type":"iceberg","status":"mystery","qty":"1"}
            ]
            """#.utf8)),
            .success(Data(#"""
            [{"id":"filled","symbol":"AAPL","side":"buy","type":"limit","status":"filled","qty":"4","filled_qty":"4","filled_avg_price":"10.5","limit_price":"11"}]
            """#.utf8)),
        ]
        let serving = AlpacaBrokerage(
            account: BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper),
            api: AlpacaTradingAPI(client: http)
        )
        let snapshot = try await serving.portfolio()
        XCTAssertEqual(snapshot.profitLoss, -1.5, accuracy: 0.0001)
        XCTAssertEqual(snapshot.profitLossPercent, -1.5, accuracy: 0.0001)

        let positions = try await serving.positions()
        XCTAssertEqual(positions[0].symbol, "AAPL")
        XCTAssertEqual(positions[0].side, .short)
        XCTAssertEqual(positions[0].unrealizedPLPercent, 10, accuracy: 0.0001)

        let open = try await serving.openOrders()
        XCTAssertEqual(open.map(\.id), ["keep", "unknown"])
        XCTAssertEqual(open[0].type, .limit)
        XCTAssertEqual(open[0].status, .new)
        XCTAssertEqual(open[1].type, .other)
        XCTAssertEqual(open[1].status, .other)

        let closed = try await serving.closedOrders(limit: 100)
        XCTAssertEqual(closed.orders.map(\.id), ["filled"])
        XCTAssertEqual(closed.orders[0].listQuantity, 4)
        XCTAssertEqual(closed.orders[0].listPrice, 10.5)
        XCTAssertEqual(http.requests.map(\.path), ["v2/account", "v2/positions", "v2/orders", "v2/orders"])
        XCTAssertEqual(http.requests[2].query["status"], "open")
        XCTAssertEqual(http.requests[2].query["limit"], "500")
        XCTAssertEqual(http.requests[2].query["direction"], "desc")
        XCTAssertEqual(http.requests[2].query["nested"], "true")
        XCTAssertEqual(http.requests[3].query["status"], "closed")
        XCTAssertEqual(http.requests[3].query["limit"], "100")
        XCTAssertNil(http.requests[3].query["until"])
        XCTAssertNil(http.requests[3].query["before_order_id"])

        http.rawResults = [
            .success(Data(#"""
            [{"id":"older","symbol":"AAPL","side":"buy","type":"limit","status":"filled","qty":"1","filled_qty":"1","filled_avg_price":"9"}]
            """#.utf8)),
        ]
        _ = try await serving.closedOrders(limit: 50, beforeOrderId: "filled")
        XCTAssertEqual(http.requests.last?.query["before_order_id"], "filled")
        XCTAssertNil(http.requests.last?.query["until"])
    }

    func testOpenOrdersPaginatesWithBeforeOrderId() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"""
            [
              {"id":"o1","symbol":"AAPL","side":"buy","type":"limit","status":"new","qty":"1"},
              {"id":"o2","symbol":"MSFT","side":"buy","type":"limit","status":"new","qty":"1"}
            ]
            """#.utf8)),
            .success(Data(#"""
            [{"id":"o3","symbol":"NVDA","side":"sell","type":"limit","status":"accepted","qty":"2"}]
            """#.utf8)),
        ]
        let serving = AlpacaBrokerage(
            account: BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper),
            api: AlpacaTradingAPI(client: http, openPageSize: 2)
        )
        let open = try await serving.openOrders()
        XCTAssertEqual(open.map(\.id), ["o1", "o2", "o3"])
        XCTAssertEqual(http.requests.map(\.path), ["v2/orders", "v2/orders"])
        XCTAssertEqual(http.requests[0].query["status"], "open")
        XCTAssertEqual(http.requests[0].query["limit"], "2")
        XCTAssertNil(http.requests[0].query["before_order_id"])
        XCTAssertEqual(http.requests[1].query["before_order_id"], "o2")
        XCTAssertEqual(http.requests[1].query["limit"], "2")
    }

    func testOpenOrdersPaginationCycleThrows() async {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"""
            [{"id":"a","symbol":"AAPL","side":"buy","type":"limit","status":"new","qty":"1"}]
            """#.utf8)),
            .success(Data(#"""
            [{"id":"b","symbol":"MSFT","side":"buy","type":"limit","status":"new","qty":"1"}]
            """#.utf8)),
            .success(Data(#"""
            [{"id":"a","symbol":"AAPL","side":"buy","type":"limit","status":"new","qty":"1"}]
            """#.utf8)),
        ]
        let serving = AlpacaBrokerage(
            account: BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper),
            api: AlpacaTradingAPI(client: http, openPageSize: 1)
        )
        do {
            _ = try await serving.openOrders()
            XCTFail("cursor cycle must reject the snapshot")
        } catch {
            XCTAssertEqual(error as? AppError, .decoding)
        }
        XCTAssertEqual(http.requests.count, 3)
        XCTAssertNil(http.requests[0].query["before_order_id"])
        XCTAssertEqual(http.requests[1].query["before_order_id"], "a")
        XCTAssertEqual(http.requests[2].query["before_order_id"], "b")
    }

    func testOpenOrdersPaginationExceedsPageCapThrows() async {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"""
            [{"id":"p1","symbol":"AAPL","side":"buy","type":"limit","status":"new","qty":"1"}]
            """#.utf8)),
            .success(Data(#"""
            [{"id":"p2","symbol":"MSFT","side":"buy","type":"limit","status":"new","qty":"1"}]
            """#.utf8)),
            .success(Data(#"""
            [{"id":"p3","symbol":"NVDA","side":"buy","type":"limit","status":"new","qty":"1"}]
            """#.utf8)),
        ]
        let serving = AlpacaBrokerage(
            account: BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper),
            api: AlpacaTradingAPI(client: http, openPageSize: 1, maxOpenPages: 2)
        )
        do {
            _ = try await serving.openOrders()
            XCTFail("page cap must reject the snapshot")
        } catch {
            XCTAssertEqual(error as? AppError, .decoding)
        }
        XCTAssertEqual(http.requests.count, 3)
    }

    func testOpenOrdersPaginationAllowsTerminatorPageAtCap() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"""
            [
              {"id":"p1","symbol":"AAPL","side":"buy","type":"limit","status":"new","qty":"1"},
              {"id":"p2","symbol":"MSFT","side":"buy","type":"limit","status":"new","qty":"1"}
            ]
            """#.utf8)),
            .success(Data(#"""
            [
              {"id":"p3","symbol":"NVDA","side":"buy","type":"limit","status":"new","qty":"1"},
              {"id":"p4","symbol":"TSLA","side":"buy","type":"limit","status":"new","qty":"1"}
            ]
            """#.utf8)),
            .success(Data("[]".utf8)),
        ]
        let serving = AlpacaBrokerage(
            account: BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper),
            api: AlpacaTradingAPI(client: http, openPageSize: 2, maxOpenPages: 2, maxOpenOrders: 4)
        )
        let open = try await serving.openOrders()
        XCTAssertEqual(open.map(\.id), ["p1", "p2", "p3", "p4"])
        XCTAssertEqual(http.requests.count, 3)
        XCTAssertEqual(http.requests[2].query["before_order_id"], "p4")
    }

    func testOpenOrdersPaginationRejectsNonEmptyProbePage() async {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"""
            [
              {"id":"p1","symbol":"AAPL","side":"buy","type":"limit","status":"new","qty":"1"},
              {"id":"p2","symbol":"MSFT","side":"buy","type":"limit","status":"new","qty":"1"}
            ]
            """#.utf8)),
            .success(Data(#"""
            [
              {"id":"p3","symbol":"NVDA","side":"buy","type":"limit","status":"new","qty":"1"},
              {"id":"p4","symbol":"TSLA","side":"buy","type":"limit","status":"new","qty":"1"}
            ]
            """#.utf8)),
            .success(Data(#"""
            [{"id":"p5","symbol":"AMD","side":"buy","type":"limit","status":"new","qty":"1"}]
            """#.utf8)),
        ]
        let serving = AlpacaBrokerage(
            account: BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper),
            api: AlpacaTradingAPI(client: http, openPageSize: 2, maxOpenPages: 2, maxOpenOrders: 10)
        )
        do {
            _ = try await serving.openOrders()
            XCTFail("non-empty probe page must reject the snapshot")
        } catch {
            XCTAssertEqual(error as? AppError, .decoding)
        }
        XCTAssertEqual(http.requests.count, 3)
    }

    func testMalformedOrderRejectsEntireSnapshot() async {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"""
            [
              {"id":"keep","symbol":"AAPL","side":"buy","type":"limit","status":"new","qty":"4"},
              {"id":"drop","side":"buy","status":"new","qty":"1"}
            ]
            """#.utf8)),
        ]
        let serving = AlpacaBrokerage(
            account: BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper),
            api: AlpacaTradingAPI(client: http)
        )
        do {
            _ = try await serving.openOrders()
            XCTFail("malformed order must reject the snapshot")
        } catch {
            XCTAssertEqual(error as? AppError, .decoding)
        }
    }

    func testMapsNestedLegsIntoOrderList() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"""
            [{
              "id":"parent","symbol":"AAPL","side":"buy","type":"limit","status":"new","qty":"2",
              "legs":[
                {"id":"tp","symbol":"AAPL","side":"sell","type":"limit","status":"held","qty":"2","limit_price":"12"},
                {"id":"sl","symbol":"AAPL","side":"sell","type":"stop","status":"held","qty":"2","stop_price":"8"}
              ]
            }]
            """#.utf8)),
        ]
        let serving = AlpacaBrokerage(
            account: BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper),
            api: AlpacaTradingAPI(client: http)
        )
        let open = try await serving.openOrders()
        XCTAssertEqual(open.map(\.id), ["parent", "tp", "sl"])
        XCTAssertEqual(open.first { $0.id == "tp" }?.type, .limit)
        XCTAssertEqual(open.first { $0.id == "sl" }?.type, .stop)
        XCTAssertEqual(open.first { $0.id == "tp" }?.status, .held)
        XCTAssertEqual(open.first { $0.id == "sl" }?.status, .held)
        XCTAssertTrue(OrderStatus.held.isOpen)
        XCTAssertFalse(OrderStatus.held.isCancellable)
    }

    func testLookupOrderHitsMemberPath() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"""
            {"id":"ord-9","symbol":"AAPL","side":"buy","type":"limit","status":"filled","qty":"2","filled_qty":"2","filled_avg_price":"10.25"}
            """#.utf8)),
        ]
        let serving = AlpacaBrokerage(
            account: BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper),
            api: AlpacaTradingAPI(client: http)
        )
        let rows = try await serving.order(id: "ord-9")
        XCTAssertEqual(rows.map(\.id), ["ord-9"])
        XCTAssertEqual(rows[0].status, .filled)
        XCTAssertEqual(http.requests.first?.method, .get)
        XCTAssertEqual(http.requests.first?.path, "v2/orders/ord-9")
    }

    func testMissingAccountNumbersThrowInsteadOfZeroing() async {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"""
            {"id":"acct-1","cash":"1","buying_power":"2","trading_blocked":false}
            """#.utf8)),
        ]
        let serving = AlpacaBrokerage(
            account: BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper),
            api: AlpacaTradingAPI(client: http)
        )
        do {
            _ = try await serving.portfolio()
            XCTFail("missing equity must throw")
        } catch {
            XCTAssertEqual(error as? AppError, .decoding)
        }
    }

    func testUnknownPositionSideThrows() async {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"""
            [{"symbol":"AAPL","qty":"4","side":"flat","avg_entry_price":"20","current_price":"18","market_value":"-72","cost_basis":"-80","unrealized_pl":"8","unrealized_plpc":"0.1"}]
            """#.utf8)),
        ]
        let serving = AlpacaBrokerage(
            account: BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper),
            api: AlpacaTradingAPI(client: http)
        )
        do {
            _ = try await serving.positions()
            XCTFail("unknown side must throw")
        } catch {
            XCTAssertEqual(error as? AppError, .decoding)
        }
    }

    func testCancelHitsOrderPath() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [.success(Data())]
        let serving = AlpacaBrokerage(
            account: BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .live),
            api: AlpacaTradingAPI(client: http)
        )
        try await serving.cancel(orderId: "ord-9")
        XCTAssertEqual(http.requests.first?.method, .delete)
        XCTAssertEqual(http.requests.first?.path, "v2/orders/ord-9")
    }
}

@MainActor
final class TradingSessionTests: XCTestCase {
    func testRefreshFillsStores() async {
        let session = TradingSession(enablesPolling: false)
        let fake = FakeBrokerage(environment: .paper)
        session.use(fake)
        await session.refresh()
        XCTAssertEqual(session.portfolio.snapshot?.equity, 101)
        XCTAssertEqual(session.positions.positions.map(\.symbol), ["AAPL"])
        XCTAssertEqual(session.orders.orders.map(\.id), ["open", "filled"])
        XCTAssertEqual(session.environment, .paper)
    }

    func testResetClearsMemory() async {
        let session = TradingSession(enablesPolling: false)
        session.use(FakeBrokerage(environment: .paper))
        await session.refresh()
        session.reset()
        XCTAssertNil(session.portfolio.snapshot)
        XCTAssertTrue(session.positions.positions.isEmpty)
        XCTAssertTrue(session.orders.orders.isEmpty)
        XCTAssertNil(session.serving)
    }

    func testSwitchingEnvironmentReplacesLists() async {
        let session = TradingSession(enablesPolling: false)
        let paper = FakeBrokerage(environment: .paper)
        let live = FakeBrokerage(environment: .live)
        live.positionRows = [samplePosition(symbol: "MSFT")]
        live.orderRows = [sampleOrder(id: "live-1", symbol: "MSFT", status: .filled)]
        live.portfolioValue = Portfolio(
            equity: 50,
            lastEquity: 40,
            cash: 5,
            buyingPower: 10,
            portfolioValue: 50,
            tradingBlocked: true
        )

        session.use(paper)
        await session.refresh()
        XCTAssertEqual(session.positions.positions.first?.symbol, "AAPL")
        XCTAssertEqual(session.orders.orders.first?.id, "open")

        session.use(live)
        XCTAssertNil(session.portfolio.snapshot)
        XCTAssertTrue(session.positions.positions.isEmpty)
        await session.refresh()
        XCTAssertEqual(session.environment, .live)
        XCTAssertEqual(session.positions.positions.map(\.symbol), ["MSFT"])
        XCTAssertEqual(session.orders.orders.map(\.id), ["live-1"])
        XCTAssertEqual(session.portfolio.snapshot?.equity, 50)
        XCTAssertTrue(session.tradingBlocked)
    }

    func testCancelReloadsOrders() async throws {
        let session = TradingSession(enablesPolling: false)
        let fake = FakeBrokerage(environment: .paper)
        session.use(fake)
        await session.refresh()
        try await session.cancel(orderId: "open")
        XCTAssertEqual(fake.canceled, ["open"])
        XCTAssertEqual(session.orders.orders.map(\.id), ["open", "filled"])
        XCTAssertEqual(session.orders.orders.first?.status, .canceled)
        XCTAssertFalse(session.orders.orders.contains { $0.id == "open" && $0.status.isOpen })
    }

    func testOrderStoreFiltersByStatusAndSymbol() {
        let store = OrderStore()
        store.apply([
            sampleOrder(id: "1", symbol: "AAPL", status: .new),
            sampleOrder(id: "2", symbol: "MSFT", status: .filled),
            sampleOrder(id: "3", symbol: "AAPL", status: .partiallyFilled),
        ])
        XCTAssertEqual(store.filtered(.all).map(\.id), ["1", "2", "3"])
        XCTAssertEqual(store.filtered(.filled).map(\.id), ["2", "3"])
        XCTAssertEqual(store.filtered(.new).map(\.id), ["1"])
        XCTAssertEqual(store.filtered(.all, symbol: "aapl").map(\.id), ["1", "3"])
    }

    func testSameAccountCredentialSwapDiscardsStaleRefresh() async {
        let session = TradingSession(enablesPolling: false)
        let old = FakeBrokerage(environment: .paper, id: "acct")
        let new = FakeBrokerage(environment: .paper, id: "acct")
        new.portfolioValue = samplePortfolio(equity: 200, lastEquity: 100)

        session.use(old)
        await session.refresh()
        XCTAssertEqual(session.portfolio.snapshot?.equity, 101)

        old.pauseSends = true
        let stale = Task { await session.refresh() }
        await waitUntil { old.portfolioCalls == 2 }

        session.use(new)
        XCTAssertEqual(session.portfolio.snapshot?.equity, 101)
        await session.refresh()
        XCTAssertEqual(session.portfolio.snapshot?.equity, 200)

        old.releasePaused()
        await stale.value
        XCTAssertEqual(session.portfolio.snapshot?.equity, 200)
        XCTAssertEqual(session.portfolio.errorText, nil)
    }

    func testConcurrentRefreshCoalesces() async {
        let session = TradingSession(enablesPolling: false)
        let fake = FakeBrokerage(environment: .paper)
        session.use(fake)
        fake.pauseSends = true
        let first = Task { await session.refresh() }
        let second = Task { await session.refresh() }
        await waitUntil { fake.portfolioCalls == 1 }
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(fake.portfolioCalls, 1)
        XCTAssertEqual(fake.positionsCalls, 1)
        XCTAssertEqual(fake.openCalls, 1)
        XCTAssertEqual(fake.closedCalls, 0)
        fake.releasePaused()
        await first.value
        await second.value
        XCTAssertEqual(fake.portfolioCalls, 1)
        XCTAssertEqual(fake.openCalls, 1)
        XCTAssertEqual(fake.closedCalls, 1)
        XCTAssertEqual(session.portfolio.snapshot?.equity, 101)
    }

    func testPollFetchesRecentClosedAfterFirstLoad() async {
        let session = TradingSession(enablesPolling: false)
        let fake = FakeBrokerage(environment: .paper)
        session.use(fake)
        await session.refresh()
        XCTAssertEqual(fake.openCalls, 1)
        XCTAssertEqual(fake.closedCalls, 1)
        await session.refresh(includingClosed: false)
        XCTAssertEqual(fake.openCalls, 2)
        XCTAssertEqual(fake.closedCalls, 2)
        await session.refresh(includingClosed: true)
        XCTAssertEqual(fake.openCalls, 3)
        XCTAssertEqual(fake.closedCalls, 3)
    }

    func testPollKeepsFilledOrder() async {
        let session = TradingSession(enablesPolling: false)
        let fake = FakeBrokerage(environment: .paper)
        session.use(fake)
        await session.refresh()
        fake.fill("open")
        await session.refresh(includingClosed: false)
        XCTAssertEqual(session.orders.orders.first { $0.id == "open" }?.status, .filled)
        XCTAssertEqual(fake.orderLookups, 0)
    }

    func testPollLooksUpDisappearedOrderMissingFromRecentClosed() async {
        let session = TradingSession(enablesPolling: false)
        let fake = FakeBrokerage(environment: .paper)
        session.use(fake)
        await session.refresh()
        fake.fill("open")
        fake.hiddenClosed = ["open"]
        await session.refresh(includingClosed: false)
        XCTAssertEqual(fake.orderLookups, 1)
        XCTAssertEqual(session.orders.orders.first { $0.id == "open" }?.status, .filled)
    }

    func testClosedHistoryPaginates() async {
        let session = TradingSession(enablesPolling: false, closedPageSize: 2)
        let fake = FakeBrokerage(environment: .paper)
        let submitted = Date(timeIntervalSince1970: 20)
        fake.orderRows = [
            sampleOrder(
                id: "c1",
                symbol: "AAPL",
                status: .filled,
                submittedAt: submitted,
                updatedAt: Date(timeIntervalSince1970: 10)
            ),
            sampleOrder(
                id: "c2",
                symbol: "AAPL",
                status: .filled,
                submittedAt: submitted,
                updatedAt: Date(timeIntervalSince1970: 50)
            ),
            sampleOrder(
                id: "c3",
                symbol: "AAPL",
                status: .filled,
                submittedAt: submitted,
                updatedAt: Date(timeIntervalSince1970: 40)
            ),
        ]
        session.use(fake)
        await session.refresh()
        XCTAssertEqual(Set(session.orders.orders.map(\.id)), ["c1", "c2"])
        XCTAssertTrue(session.orders.hasMoreClosed)
        XCTAssertEqual(fake.closedCalls, 1)
        XCTAssertEqual(fake.closedBeforeIds, [nil])

        await session.loadMoreClosed()
        XCTAssertEqual(Set(session.orders.orders.map(\.id)), ["c1", "c2", "c3"])
        XCTAssertFalse(session.orders.hasMoreClosed)
        XCTAssertEqual(fake.closedCalls, 2)
        XCTAssertEqual(fake.closedBeforeIds, [nil, "c2"])
    }

    func testStaleLoadMoreDoesNotOverrideFirstPageRefresh() async {
        let session = TradingSession(enablesPolling: false, closedPageSize: 2)
        let fake = FakeBrokerage(environment: .paper)
        let submitted = Date(timeIntervalSince1970: 20)
        fake.orderRows = [
            sampleOrder(id: "c1", symbol: "AAPL", status: .filled, submittedAt: submitted),
            sampleOrder(id: "c2", symbol: "AAPL", status: .filled, submittedAt: submitted),
            sampleOrder(id: "c3", symbol: "AAPL", status: .filled, submittedAt: submitted),
        ]
        session.use(fake)
        await session.refresh()
        XCTAssertEqual(Set(session.orders.orders.map(\.id)), ["c1", "c2"])

        fake.pauseWhenBeforeOrderId = true
        let more = Task { await session.loadMoreClosed() }
        await waitUntil { fake.closedCalls == 2 }
        await session.refresh()
        XCTAssertEqual(Set(session.orders.orders.map(\.id)), ["c1", "c2"])
        XCTAssertTrue(session.orders.hasMoreClosed)

        fake.releasePaused()
        await more.value
        XCTAssertEqual(Set(session.orders.orders.map(\.id)), ["c1", "c2"])
        XCTAssertFalse(session.orders.orders.contains { $0.id == "c3" })
        XCTAssertTrue(session.orders.hasMoreClosed)
    }

    func testHeldLegSurvivesClosedReplace() {
        let store = OrderStore()
        _ = store.applyOpen([
            sampleOrder(id: "parent", symbol: "AAPL", status: .new),
            sampleOrder(id: "tp", symbol: "AAPL", status: .held),
            sampleOrder(id: "sl", symbol: "AAPL", status: .held),
        ])
        store.applyClosed(
            [sampleOrder(id: "old", symbol: "MSFT", status: .filled)],
            replacingClosed: true
        )
        XCTAssertEqual(store.orders.first { $0.id == "tp" }?.status, .held)
        XCTAssertEqual(store.orders.first { $0.id == "sl" }?.status, .held)
        XCTAssertTrue(store.orders.contains { $0.id == "parent" })
        XCTAssertTrue(store.orders.contains { $0.id == "old" })
    }

    func testLookupAppliesSuccessfulResultsWhenAnotherFails() async {
        let session = TradingSession(
            enablesPolling: false,
            lookupRetryNanoseconds: 0,
            lookupMaxAttempts: 2
        )
        let fake = FakeBrokerage(environment: .paper)
        fake.orderRows = [
            sampleOrder(id: "open-a", symbol: "AAPL", status: .new),
            sampleOrder(id: "open-b", symbol: "MSFT", status: .new),
        ]
        session.use(fake)
        await session.refresh()
        fake.fill("open-a")
        fake.fill("open-b")
        fake.hiddenClosed = ["open-a", "open-b"]
        fake.orderErrors = ["open-b": AppError.network]
        await session.refresh(includingClosed: false)
        XCTAssertEqual(session.orders.orders.first { $0.id == "open-a" }?.status, .filled)
        XCTAssertEqual(session.orders.orders.first { $0.id == "open-b" }?.status, .new)
        XCTAssertEqual(session.orders.errorText, L10n.Errors.network)
        XCTAssertGreaterThanOrEqual(fake.orderLookups, 3)
    }

    func testMalformedOrdersKeepPreviousSnapshot() async {
        let session = TradingSession(enablesPolling: false)
        let fake = FakeBrokerage(environment: .paper)
        session.use(fake)
        await session.refresh()
        XCTAssertEqual(session.orders.orders.map(\.id), ["open", "filled"])
        fake.ordersError = AppError.decoding
        await session.refresh()
        XCTAssertEqual(session.orders.orders.map(\.id), ["open", "filled"])
        XCTAssertEqual(session.orders.errorText, L10n.Errors.generic)
    }

    func testCancelIgnoresStaleInFlightOpenOrders() async throws {
        let session = TradingSession(enablesPolling: false)
        let fake = FakeBrokerage(environment: .paper)
        session.use(fake)
        await session.refresh()
        XCTAssertTrue(session.orders.orders.contains { $0.id == "open" && $0.status.isOpen })

        fake.pauseSends = true
        let poll = Task { await session.refresh(includingClosed: false) }
        await waitUntil { fake.openCalls == 2 }
        fake.stopPausingNewRequests()
        try await session.cancel(orderId: "open")
        XCTAssertEqual(session.orders.orders.first { $0.id == "open" }?.status, .canceled)

        fake.releasePaused()
        await poll.value
        XCTAssertEqual(session.orders.orders.first { $0.id == "open" }?.status, .canceled)
        XCTAssertFalse(session.orders.orders.contains { $0.id == "open" && $0.status.isOpen })
    }

    func testApplyOpenKeepsDisappearedUntilClosedUpsert() {
        let store = OrderStore()
        _ = store.applyOpen([sampleOrder(id: "open", symbol: "AAPL", status: .new)])
        store.applyClosed([sampleOrder(id: "filled", symbol: "AAPL", status: .filled)])
        let disappeared = store.applyOpen([])
        XCTAssertEqual(Set(disappeared), ["open"])
        XCTAssertEqual(Set(store.orders.map(\.id)), ["open", "filled"])
        store.applyClosed(
            [sampleOrder(id: "open", symbol: "AAPL", status: .filled, updatedAt: Date(timeIntervalSince1970: 1_700_000_200))],
            replacingClosed: false
        )
        XCTAssertEqual(store.orders.first { $0.id == "open" }?.status, .filled)
        XCTAssertEqual(store.filtered(.all, symbol: "aapl").map(\.id).sorted(), ["filled", "open"])
    }

    func testFailedRefreshKeepsSnapshotAndSurfacesError() async {
        let session = TradingSession(enablesPolling: false)
        let fake = FakeBrokerage(environment: .paper)
        session.use(fake)
        await session.refresh()
        XCTAssertEqual(session.portfolio.snapshot?.equity, 101)

        fake.portfolioError = AppError.network
        await session.refresh()
        XCTAssertEqual(session.portfolio.snapshot?.equity, 101)
        XCTAssertEqual(session.portfolio.errorText, L10n.Errors.network)
        XCTAssertFalse(session.needsCredentials)
    }

    func testUnauthorizedPausesPollingAndKeepsSnapshot() async {
        let session = TradingSession(enablesPolling: true)
        let fake = FakeBrokerage(environment: .paper)
        session.use(fake)
        await session.refresh()
        XCTAssertTrue(session.isPolling)
        XCTAssertEqual(session.portfolio.snapshot?.equity, 101)

        fake.portfolioError = AppError.http(status: 401, message: "invalid", errorCode: nil)
        await session.refresh()
        XCTAssertTrue(session.needsCredentials)
        XCTAssertFalse(session.isPolling)
        XCTAssertEqual(session.portfolio.snapshot?.equity, 101)
        XCTAssertEqual(session.portfolio.errorText, L10n.Trading.credentialsInvalid)
        XCTAssertEqual(session.positions.errorText, L10n.Trading.credentialsInvalid)
    }
}

private final class FakeBrokerage: BrokerageServing {
    var account: BrokerageAccount
    private let lock = NSLock()
    private var _portfolioValue: Portfolio
    private var _positionRows: [Position]
    private var _orderRows: [Order]
    private var _canceled: [String] = []
    private var _cancelError: Error?
    private var _portfolioError: Error?
    private var _positionsError: Error?
    private var _ordersError: Error?
    private var _portfolioCalls = 0
    private var _positionsCalls = 0
    private var _openCalls = 0
    private var _closedCalls = 0
    private var _orderLookups = 0
    private var _closedBeforeIds: [String?] = []
    private var _orderErrors: [String: Error] = [:]
    private var _hiddenClosed: Set<String> = []
    private var _pauseSends = false
    private var _pauseWhenBeforeOrderId = false
    private var paused: [CheckedContinuation<Void, Never>] = []

    var portfolioValue: Portfolio {
        get { withLock { _portfolioValue } }
        set { withLock { _portfolioValue = newValue } }
    }

    var positionRows: [Position] {
        get { withLock { _positionRows } }
        set { withLock { _positionRows = newValue } }
    }

    var orderRows: [Order] {
        get { withLock { _orderRows } }
        set { withLock { _orderRows = newValue } }
    }

    var canceled: [String] { withLock { _canceled } }

    var cancelError: Error? {
        get { withLock { _cancelError } }
        set { withLock { _cancelError = newValue } }
    }

    var portfolioError: Error? {
        get { withLock { _portfolioError } }
        set { withLock { _portfolioError = newValue } }
    }

    var positionsError: Error? {
        get { withLock { _positionsError } }
        set { withLock { _positionsError = newValue } }
    }

    var ordersError: Error? {
        get { withLock { _ordersError } }
        set { withLock { _ordersError = newValue } }
    }

    var portfolioCalls: Int { withLock { _portfolioCalls } }
    var positionsCalls: Int { withLock { _positionsCalls } }
    var openCalls: Int { withLock { _openCalls } }
    var closedCalls: Int { withLock { _closedCalls } }
    var orderLookups: Int { withLock { _orderLookups } }

    var closedBeforeIds: [String?] { withLock { _closedBeforeIds } }

    var hiddenClosed: Set<String> {
        get { withLock { _hiddenClosed } }
        set { withLock { _hiddenClosed = newValue } }
    }

    var orderErrors: [String: Error] {
        get { withLock { _orderErrors } }
        set { withLock { _orderErrors = newValue } }
    }

    var pauseWhenBeforeOrderId: Bool {
        get { withLock { _pauseWhenBeforeOrderId } }
        set { withLock { _pauseWhenBeforeOrderId = newValue } }
    }

    var pauseSends: Bool {
        get { withLock { _pauseSends } }
        set { withLock { _pauseSends = newValue } }
    }

    init(environment: BrokerageEnvironment, id: String? = nil) {
        account = BrokerageAccount(
            id: id ?? "acct-\(environment.rawValue)",
            provider: "alpaca",
            environment: environment
        )
        _portfolioValue = samplePortfolio(equity: 101, lastEquity: 100)
        _positionRows = [samplePosition(symbol: "AAPL")]
        _orderRows = [
            sampleOrder(id: "open", symbol: "AAPL", status: .new),
            sampleOrder(
                id: "filled",
                symbol: "AAPL",
                status: .filled,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
        ]
    }

    func releasePaused() {
        let pending: [CheckedContinuation<Void, Never>] = withLock {
            _pauseSends = false
            _pauseWhenBeforeOrderId = false
            let pending = paused
            paused.removeAll()
            return pending
        }
        pending.forEach { $0.resume() }
    }

    func stopPausingNewRequests() {
        withLock { _pauseSends = false }
    }

    func portfolio() async throws -> Portfolio {
        let value: Portfolio = withLock {
            _portfolioCalls += 1
            return _portfolioValue
        }
        await waitIfPaused()
        if let error = withLock({ _portfolioError }) { throw error }
        return value
    }

    func positions() async throws -> [Position] {
        let rows: [Position] = withLock {
            _positionsCalls += 1
            return _positionRows
        }
        await waitIfPaused()
        if let error = withLock({ _positionsError }) { throw error }
        return rows
    }

    func openOrders() async throws -> [Order] {
        let snapshot: [Order] = withLock {
            _openCalls += 1
            return _orderRows.filter { $0.status.isOpen }
        }
        await waitIfPaused()
        if let error = withLock({ _ordersError }) { throw error }
        return snapshot
    }

    func closedOrders(limit: Int, beforeOrderId: String?) async throws -> OrderPage {
        let snapshot: OrderPage = withLock {
            _closedCalls += 1
            _closedBeforeIds.append(beforeOrderId)
            var closed = _orderRows.filter { !$0.status.isOpen && !_hiddenClosed.contains($0.id) }
            closed.sort {
                let lhs = $0.submittedAt ?? .distantPast
                let rhs = $1.submittedAt ?? .distantPast
                if lhs != rhs { return lhs > rhs }
                return $0.id < $1.id
            }
            if let beforeOrderId, let index = closed.firstIndex(where: { $0.id == beforeOrderId }) {
                closed = Array(closed.dropFirst(index + 1))
            } else if beforeOrderId != nil {
                closed = []
            }
            let page = Array(closed.prefix(limit))
            let hasMore = page.count >= limit
            return OrderPage(
                orders: page,
                nextBeforeOrderId: hasMore ? page.last?.id : nil,
                hasMore: hasMore
            )
        }
        await waitIfPaused(forCursor: beforeOrderId != nil)
        if let error = withLock({ _ordersError }) { throw error }
        return snapshot
    }

    func order(id: String) async throws -> [Order] {
        let rows: [Order] = withLock {
            _orderLookups += 1
            return _orderRows.filter { $0.id == id }
        }
        await waitIfPaused()
        if let error = withLock({ _orderErrors[id] }) { throw error }
        if let error = withLock({ _ordersError }) { throw error }
        if rows.isEmpty {
            throw AppError.http(status: 404, message: nil, errorCode: nil)
        }
        return rows
    }

    func fill(_ id: String) {
        withLock {
            _orderRows = _orderRows.map { order in
                guard order.id == id else { return order }
                var next = order
                next.status = .filled
                next.filledQuantity = order.quantity
                next.filledAvgPrice = order.limitPrice
                next.updatedAt = Date(timeIntervalSince1970: 1_700_000_250)
                return next
            }
        }
    }

    func cancel(orderId: String) async throws {
        if let error = withLock({ _cancelError }) { throw error }
        withLock {
            _canceled.append(orderId)
            _orderRows = _orderRows.map { order in
                guard order.id == orderId else { return order }
                var next = order
                next.status = .canceled
                next.updatedAt = Date(timeIntervalSince1970: 1_700_000_200)
                return next
            }
        }
    }

    private func waitIfPaused(forCursor: Bool = false) async {
        await withCheckedContinuation { continuation in
            let shouldWait = withLock { () -> Bool in
                if _pauseSends || (_pauseWhenBeforeOrderId && forCursor) {
                    paused.append(continuation)
                    return true
                }
                return false
            }
            if !shouldWait {
                continuation.resume()
            }
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private func samplePortfolio(equity: Double, lastEquity: Double) -> Portfolio {
    Portfolio(
        equity: equity,
        lastEquity: lastEquity,
        cash: 10,
        buyingPower: 20,
        portfolioValue: equity,
        tradingBlocked: false
    )
}

private func samplePosition(symbol: String) -> Position {
    Position(
        symbol: symbol,
        quantity: 2,
        side: .long,
        averageEntry: 10,
        currentPrice: 11,
        marketValue: 22,
        costBasis: 20,
        unrealizedPL: 2,
        unrealizedPLPercent: 10
    )
}

private func sampleOrder(
    id: String = "1",
    symbol: String = "AAPL",
    status: OrderStatus = .new,
    side: OrderSide = .buy,
    type: OrderType = .limit,
    submittedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
    updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_100)
) -> Order {
    Order(
        id: id,
        symbol: symbol,
        side: side,
        type: type,
        status: status,
        quantity: 10,
        filledQuantity: status == .filled ? 10 : (status == .partiallyFilled ? 4 : 0),
        limitPrice: 11,
        stopPrice: nil,
        filledAvgPrice: status == .filled || status == .partiallyFilled ? 11 : nil,
        timeInForce: "day",
        submittedAt: submittedAt,
        updatedAt: updatedAt,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        clientOrderId: nil
    )
}
