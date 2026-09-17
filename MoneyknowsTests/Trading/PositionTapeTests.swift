import XCTest
@testable import Moneyknows

final class PositionTapeTests: XCTestCase {
    func testSignedQuantityUsesSideEvenWhenQtyIsPositive() {
        XCTAssertEqual(tapePosition(side: .long, quantity: 6703).signedQuantity, 6703)
        XCTAssertEqual(tapePosition(side: .short, quantity: 6703).signedQuantity, -6703)
        XCTAssertEqual(tapePosition(side: .short, quantity: -6703).signedQuantity, -6703)
        XCTAssertEqual(tapePosition(side: .short, quantity: -6703).quantity, 6703)
        XCTAssertEqual(tapePosition(side: .long, quantity: -2).quantity, 2)
    }

    func testUnrealizedPercentUsesLiveMidForLongAndShort() {
        let long = tapePosition(side: .long, quantity: 10, entry: 10)
        XCTAssertEqual(long.unrealizedPercent(versus: 10.5) ?? -1, 5, accuracy: 0.0001)

        let short = tapePosition(side: .short, quantity: 6703, entry: 17.78)
        XCTAssertEqual(short.unrealizedPercent(versus: 17.88) ?? 1, -0.562429, accuracy: 0.0001)
    }

    func testUnrealizedPercentNilWhenEntryMissing() {
        XCTAssertNil(tapePosition(side: .long, quantity: 1, entry: 0).unrealizedPercent(versus: 10))
        XCTAssertNil(tapePosition(side: .long, quantity: 1, entry: .nan).unrealizedPercent(versus: 10))
    }

    func testTapePriceUsesBookNotLastTrade() {
        var quote = SymbolQuote(last: 17.87, bid: 17.87, ask: 17.88, bidSize: 300, askSize: 800)
        XCTAssertEqual(quote.tapePrice ?? 0, 17.875, accuracy: 0.0001)
        XCTAssertTrue(quote.hasTapeQuote)

        quote.bid = nil
        quote.snapshotBid = nil
        XCTAssertEqual(quote.tapePrice, 17.88)
        XCTAssertFalse(quote.hasTapeQuote)

        quote.ask = nil
        quote.snapshotAsk = nil
        XCTAssertNil(quote.tapePrice)
        XCTAssertEqual(quote.mid, 17.87)
    }

    func testShowsOnDetailTradeBarMatchesOpenWorkingOrders() {
        XCTAssertTrue(OrderStatus.new.showsOnDetailTradeBar)
        XCTAssertTrue(OrderStatus.accepted.showsOnDetailTradeBar)
        XCTAssertTrue(OrderStatus.acceptedForBidding.showsOnDetailTradeBar)
        XCTAssertFalse(OrderStatus.partiallyFilled.showsOnDetailTradeBar)
        XCTAssertFalse(OrderStatus.filled.showsOnDetailTradeBar)
    }

    func testExitButtonsUseCoveringSideTint() {
        XCTAssertTrue(TradeActionKind.takeProfit.isBuyTint(positionSide: .short))
        XCTAssertTrue(TradeActionKind.stopLoss.isBuyTint(positionSide: .short))
        XCTAssertTrue(TradeActionKind.limitClose.isBuyTint(positionSide: .short))
        XCTAssertTrue(TradeActionKind.marketClose.isBuyTint(positionSide: .short))
        XCTAssertFalse(TradeActionKind.takeProfit.isBuyTint(positionSide: .long))
        XCTAssertFalse(TradeActionKind.stopLoss.isBuyTint(positionSide: .long))
        XCTAssertFalse(TradeActionKind.limitClose.isBuyTint(positionSide: .long))
        XCTAssertTrue(TradeActionKind.buy.isBuyTint(positionSide: .short))
        XCTAssertFalse(TradeActionKind.sell.isBuyTint(positionSide: .long))
    }

    private func tapePosition(side: PositionSide, quantity: Double, entry: Double = 10) -> Position {
        Position(
            symbol: "AAPL",
            quantity: quantity,
            side: side,
            averageEntry: entry,
            currentPrice: entry,
            marketValue: 0,
            costBasis: 0,
            unrealizedPL: 0,
            unrealizedPLPercent: 0
        )
    }
}
