import XCTest
@testable import Moneyknows

final class DayFillsTests: XCTestCase {
    func testBuyBelowSellAboveAndKeepsSameMinuteFillsSeparate() {
        let buyTime = eastern(2026, 9, 4, 10, 1)
        let sellTime = buyTime.addingTimeInterval(15)
        let orders = [
            sampleFilled(id: "b1", side: .buy, quantity: 1, price: 10, filledAt: buyTime),
            sampleFilled(id: "s1", side: .sell, quantity: 2, price: 10.5, filledAt: sellTime),
        ]
        let fills = DayFills.fills(from: orders, symbol: "AAPL", day: "2026-09-04")
        XCTAssertEqual(fills.map(\.id), [fillID("b1"), fillID("s1")])
        let markers = DayFills.markers(fills)
        XCTAssertEqual(markers.map(\.id), [fillID("b1"), fillID("s1")])
        XCTAssertEqual(markers[0].kind, .buy)
        XCTAssertEqual(markers[0].position, .belowBar)
        XCTAssertEqual(markers[1].kind, .sell)
        XCTAssertEqual(markers[1].position, .aboveBar)
        XCTAssertEqual(markers[0].title, "\(MarketFormat.quantity(1))@\(MarketFormat.price(10))")
        XCTAssertEqual(markers[1].title, "\(MarketFormat.quantity(2))@\(MarketFormat.price(10.5))")
    }

    func testDropsFillsWithoutFilledAtOrOutsideEasternDay() {
        let inside = eastern(2026, 9, 4, 15, 59)
        let outside = eastern(2026, 9, 5, 0, 1)
        var missingTime = sampleFilled(id: "missing", filledAt: inside)
        missingTime.filledAt = nil
        let orders = [
            missingTime,
            sampleFilled(id: "next-day", filledAt: outside),
            sampleFilled(id: "keep", filledAt: inside),
            sampleFilled(id: "other", symbol: "MSFT", filledAt: inside),
        ]
        XCTAssertEqual(
            DayFills.fills(from: orders, symbol: "AAPL", day: "2026-09-04").map(\.id),
            [fillID("keep")]
        )
    }

    func testMissingPriceUsesBarClose() {
        let time = eastern(2026, 9, 4, 10, 0)
        let fill = Fill(orderId: "no-px", symbol: "AAPL", side: .buy, quantity: 1, price: 0, filledAt: time)
        let bars = [
            Bar(time: time, open: 9, high: 11, low: 8, close: 10.25, volume: 1),
        ]
        let markers = DayFills.markers([fill], bars: bars)
        XCTAssertEqual(markers.first?.price, 10.25)
        XCTAssertEqual(markers.first?.time, time)
    }

    func testMergingPrefersLaterCopyAndDoesNotCollapseIds() {
        let time = eastern(2026, 9, 4, 11, 0)
        let first = Fill(orderId: "a", symbol: "AAPL", side: .buy, quantity: 1, price: 10, filledAt: time)
        let second = Fill(orderId: "a", symbol: "AAPL", side: .buy, quantity: 2, price: 11, filledAt: time)
        let extra = Fill(orderId: "b", symbol: "AAPL", side: .buy, quantity: 1, price: 9, filledAt: time)
        let merged = DayFills.merging([first], [second, extra])
        XCTAssertEqual(Set(merged.map(\.id)), [fillID("a"), fillID("b")])
        XCTAssertEqual(merged.first { $0.id == fillID("a") }?.quantity, 2)
        XCTAssertEqual(merged.first { $0.id == fillID("a") }?.price, 11)
    }

    func testCombinedMergesRemoteAndLocalOrders() {
        let time = eastern(2026, 9, 4, 11, 0)
        let remote = Fill(orderId: "a", symbol: "AAPL", side: .buy, quantity: 1, price: 10, filledAt: time)
        let local = sampleFilled(id: "b", quantity: 3, price: 12, filledAt: time)
        let combined = DayFills.combined(remote: [remote], orders: [local], symbol: "AAPL", day: "2026-09-04")
        XCTAssertEqual(combined.map(\.id), [fillID("a"), fillID("b")])
        XCTAssertEqual(DayFills.caption(remote), "\(MarketFormat.quantity(1))@\(MarketFormat.price(10))")
    }

    func testMergingKeepsPartialFillsOfTheSameOrderOnDifferentDays() {
        let friday = Fill(orderId: "gtc", symbol: "AAPL", side: .buy, quantity: 1, price: 10, filledAt: eastern(2026, 9, 4, 15, 0))
        let monday = Fill(orderId: "gtc", symbol: "AAPL", side: .buy, quantity: 1, price: 11, filledAt: eastern(2026, 9, 8, 10, 0))
        let merged = DayFills.merging([friday], [monday])
        XCTAssertEqual(merged.map(\.orderId), ["gtc", "gtc"])
        XCTAssertEqual(merged.map(\.quantity), [1, 1])
        XCTAssertEqual(merged.map(\.id), [fillID("gtc"), fillID("gtc", "2026-09-08")])
        XCTAssertEqual(DayFills.markers(merged).map(\.id), merged.map(\.id))
    }

    func testCombinedPrefersRemoteDayQuantityOverLocalCumulative() {
        let monday = eastern(2026, 9, 8, 10, 0)
        let remote = Fill(orderId: "gtc", symbol: "AAPL", side: .buy, quantity: 1, price: 11, filledAt: monday)
        let local = sampleFilled(id: "gtc", quantity: 2, price: 10.5, filledAt: monday)
        let combined = DayFills.combined(remote: [remote], orders: [local], symbol: "AAPL", day: "2026-09-08")
        XCTAssertEqual(combined.map(\.id), [fillID("gtc", "2026-09-08")])
        XCTAssertEqual(combined.first?.quantity, 1)
        XCTAssertEqual(combined.first?.price, 11)
    }

    func testCombinedDoesNotBackfillAmbiguousGTCWhenActivitiesDayIsEmpty() {
        let fridayTime = eastern(2026, 9, 4, 15, 0)
        let mondayTime = eastern(2026, 9, 8, 10, 0)
        let friday = Fill(orderId: "gtc", symbol: "AAPL", side: .buy, quantity: 1, price: 10, filledAt: fridayTime)
        let local = sampleFilled(
            id: "gtc",
            quantity: 2,
            price: 10.5,
            filledAt: mondayTime,
            submittedAt: fridayTime,
            timeInForce: "gtc"
        )
        let days: Set<String> = ["2026-09-04", "2026-09-08"]
        let combined = DayFills.combined(
            remote: [friday],
            orders: [local],
            symbol: "AAPL",
            days: days,
            successfulDays: days
        )
        XCTAssertEqual(combined.map(\.id), [fillID("gtc")])
        XCTAssertEqual(combined.map(\.quantity), [1])
        XCTAssertTrue(
            DayFills.omitsAmbiguousOrders([local], symbol: "AAPL", days: days, remote: [friday])
        )
    }

    func testCombinedBackfillsUnambiguousSameDayOrderWhenActivitiesDayIsEmpty() {
        let fridayTime = eastern(2026, 9, 4, 15, 0)
        let mondayTime = eastern(2026, 9, 8, 10, 0)
        let friday = Fill(orderId: "a", symbol: "AAPL", side: .buy, quantity: 1, price: 10, filledAt: fridayTime)
        let local = sampleFilled(id: "b", quantity: 2, price: 12, filledAt: mondayTime)
        let days: Set<String> = ["2026-09-04", "2026-09-08"]
        let combined = DayFills.combined(
            remote: [friday],
            orders: [local],
            symbol: "AAPL",
            days: days,
            successfulDays: days
        )
        XCTAssertEqual(combined.map(\.id), [fillID("a"), fillID("b", "2026-09-08")])
        XCTAssertEqual(combined.map(\.quantity), [1, 2])
        XCTAssertFalse(
            DayFills.omitsAmbiguousOrders([local], symbol: "AAPL", days: days, remote: [friday])
        )
    }

    func testCombinedDoesNotBackfillFailedDayFromLocalOrders() {
        let fridayTime = eastern(2026, 9, 4, 15, 0)
        let mondayTime = eastern(2026, 9, 8, 8, 0)
        let friday = Fill(orderId: "prior-regular", symbol: "AAPL", side: .buy, quantity: 1, price: 10, filledAt: fridayTime)
        let local = sampleFilled(id: "today-pre", quantity: 2, price: 11, filledAt: mondayTime)
        let combined = DayFills.combined(
            remote: [friday],
            orders: [local],
            symbol: "AAPL",
            days: ["2026-09-04", "2026-09-08"],
            successfulDays: ["2026-09-04"]
        )
        XCTAssertEqual(combined.map(\.id), [fillID("prior-regular")])
        XCTAssertFalse(
            DayFills.omitsAmbiguousOrders(
                [local],
                symbol: "AAPL",
                days: ["2026-09-04"],
                remote: [friday]
            )
        )
    }

    func testExtendedHoursFillsStayOnTheirSessionBars() {
        let preTime = eastern(2026, 9, 4, 8, 0)
        let openTime = eastern(2026, 9, 4, 9, 30)
        let afterTime = eastern(2026, 9, 4, 18, 0)
        let lastRegular = eastern(2026, 9, 4, 15, 59)
        let preFill = Fill(orderId: "pre", symbol: "AAPL", side: .buy, quantity: 1, price: 10, filledAt: preTime)
        let afterFill = Fill(orderId: "after", symbol: "AAPL", side: .sell, quantity: 1, price: 11, filledAt: afterTime)
        let overnight = Fill(orderId: "night", symbol: "AAPL", side: .buy, quantity: 1, price: 9, filledAt: eastern(2026, 9, 4, 21, 0))
        let regularBars = [
            Bar(time: openTime, open: 10, high: 10, low: 10, close: 10, volume: 1),
            Bar(time: lastRegular, open: 11, high: 11, low: 11, close: 11, volume: 1),
        ]
        let preBars = [
            Bar(time: preTime, open: 9, high: 9, low: 9, close: 9, volume: 1),
        ]
        let afterBars = [
            Bar(time: afterTime, open: 12, high: 12, low: 12, close: 12, volume: 1),
        ]
        XCTAssertEqual(DayFills.session(for: preFill), .premarket)
        XCTAssertEqual(DayFills.session(for: afterFill), .aftermarket)
        XCTAssertNil(DayFills.session(for: overnight))
        XCTAssertTrue(DayFills.markers([preFill, afterFill], bars: regularBars, session: .regular).isEmpty)
        XCTAssertEqual(DayFills.markers([preFill], bars: preBars, session: .premarket).map(\.id), [fillID("pre")])
        XCTAssertEqual(DayFills.markers([preFill], bars: preBars, session: .premarket).first?.time, preTime)
        XCTAssertEqual(DayFills.markers([afterFill], bars: afterBars, session: .aftermarket).map(\.id), [fillID("after")])
        XCTAssertTrue(DayFills.markers([overnight], bars: regularBars, session: .regular).isEmpty)
        XCTAssertTrue(DayFills.markers([overnight], bars: afterBars, session: .aftermarket).isEmpty)
        XCTAssertFalse(DayFills.isChartable(overnight))
        XCTAssertTrue(DayFills.isChartable(preFill))
        XCTAssertTrue(
            DayFills.isChartable(preFill, regularBars: regularBars, preBars: preBars, afterBars: afterBars)
        )
        let gapFill = Fill(orderId: "gap", symbol: "AAPL", side: .buy, quantity: 1, price: 10, filledAt: eastern(2026, 9, 4, 11, 0))
        XCTAssertTrue(DayFills.isChartable(gapFill))
        XCTAssertFalse(
            DayFills.isChartable(gapFill, regularBars: regularBars, preBars: preBars, afterBars: afterBars)
        )
        XCTAssertTrue(DayFills.markers([gapFill], bars: regularBars, session: .regular).isEmpty)
        XCTAssertEqual(
            DayFills.fills(
                from: [
                    sampleFilled(id: "night", filledAt: overnight.filledAt),
                    sampleFilled(id: "pre", filledAt: preTime),
                ],
                symbol: "AAPL",
                day: "2026-09-04"
            ).map(\.id),
            ["pre", "night"].map { fillID($0) }
        )
        XCTAssertEqual(ChartHitTesting.pickedBar(in: regularBars, at: preTime)?.time, openTime)
        XCTAssertEqual(ChartHitTesting.pickedBar(in: regularBars, at: afterTime)?.time, lastRegular)
    }

    @MainActor
    func testSessionClearsRemoteFillsWhenAccountResets() async {
        let trading = TradingSession(enablesPolling: false)
        let fake = FakeBrokerage(environment: .paper)
        let filledAt = eastern(2026, 9, 4, 10, 15)
        fake.orderRows = [sampleFilled(id: "keep", filledAt: filledAt)]
        trading.use(fake)
        let session = DayFillsSession()
        await session.load(symbol: "AAPL", day: "2026-09-04", trading: trading)
        XCTAssertEqual(session.fills.map(\.id), [fillID("keep")])
        trading.reset()
        session.refresh(orders: trading.orders.orders, trading: trading)
        XCTAssertTrue(session.fills.isEmpty)
        XCTAssertNil(session.errorText)
    }

    @MainActor
    func testLoadClearsFillsBeforeFetchingTheNextDay() async {
        let trading = TradingSession(enablesPolling: false)
        let fake = FakeBrokerage(environment: .paper)
        fake.orderRows = [sampleFilled(id: "yesterday", filledAt: eastern(2026, 9, 3, 10, 0))]
        trading.use(fake)
        let session = DayFillsSession()
        await session.load(symbol: "AAPL", day: "2026-09-03", trading: trading)
        XCTAssertEqual(session.fills.map(\.id), [fillID("yesterday", "2026-09-03")])
        fake.pauseSends = true
        fake.orderRows = [sampleFilled(id: "today", filledAt: eastern(2026, 9, 4, 10, 0))]
        let next = Task {
            await session.load(symbol: "AAPL", day: "2026-09-04", trading: trading)
        }
        await waitUntil { session.fills.isEmpty }
        fake.releasePaused()
        await next.value
        XCTAssertEqual(session.fills.map(\.id), [fillID("today")])
    }

    func testChartDaysDuringPremarketIncludesExtendedDate() {
        let premarket = eastern(2026, 9, 8, 8)
        XCTAssertEqual(
            DayFills.chartDays(
                regularDate: MarketClock.lastTradingDate(from: premarket),
                extendedDate: MarketClock.extendedHoursDate(from: premarket)
            ),
            ["2026-09-04", "2026-09-08"]
        )
        let regular = eastern(2026, 9, 4, 10)
        XCTAssertEqual(
            DayFills.chartDays(
                regularDate: MarketClock.lastTradingDate(from: regular),
                extendedDate: MarketClock.extendedHoursDate(from: regular)
            ),
            ["2026-09-04"]
        )
    }

    @MainActor
    func testLoadMergesFillsFromRegularAndExtendedDates() async {
        let trading = TradingSession(enablesPolling: false)
        let fake = FakeBrokerage(environment: .paper)
        fake.orderRows = [
            sampleFilled(id: "prior-regular", filledAt: eastern(2026, 9, 4, 15, 0)),
            sampleFilled(id: "today-pre", filledAt: eastern(2026, 9, 8, 8, 0)),
        ]
        trading.use(fake)
        let session = DayFillsSession()
        await session.load(symbol: "AAPL", days: ["2026-09-04", "2026-09-08"], trading: trading)
        XCTAssertEqual(session.fills.map(\.id), [fillID("prior-regular"), fillID("today-pre", "2026-09-08")])
    }

    @MainActor
    func testLoadKeepsSuccessfulDayWhenAnotherDayFails() async {
        let trading = TradingSession(enablesPolling: false)
        let fake = FakeBrokerage(environment: .paper)
        fake.orderRows = [
            sampleFilled(id: "prior-regular", filledAt: eastern(2026, 9, 4, 15, 0)),
            sampleFilled(id: "today-pre", filledAt: eastern(2026, 9, 8, 8, 0)),
        ]
        fake.fillsDayErrors = ["2026-09-08": AppError.orderHistoryIncomplete]
        trading.use(fake)
        trading.orders.apply(fake.orderRows)
        let session = DayFillsSession()
        await session.load(symbol: "AAPL", days: ["2026-09-04", "2026-09-08"], trading: trading)
        XCTAssertEqual(session.fills.map(\.id), [fillID("prior-regular")])
        XCTAssertEqual(session.errorText, L10n.Trading.orderHistoryIncomplete)
    }

    @MainActor
    func testLoadKeepsLaterDayWhenTheFirstDayFails() async {
        let trading = TradingSession(enablesPolling: false)
        let fake = FakeBrokerage(environment: .paper)
        fake.orderRows = [
            sampleFilled(id: "prior-regular", filledAt: eastern(2026, 9, 4, 15, 0)),
            sampleFilled(id: "today-pre", filledAt: eastern(2026, 9, 8, 8, 0)),
        ]
        fake.fillsDayErrors = ["2026-09-04": AppError.network]
        trading.use(fake)
        trading.orders.apply(fake.orderRows)
        let session = DayFillsSession()
        await session.load(symbol: "AAPL", days: ["2026-09-04", "2026-09-08"], trading: trading)
        XCTAssertEqual(session.fills.map(\.id), [fillID("today-pre", "2026-09-08")])
        XCTAssertEqual(session.errorText, L10n.Errors.network)
    }

    @MainActor
    func testLoadKeepsPartialFillsOfTheSameOrderOnDifferentDays() async {
        let trading = TradingSession(enablesPolling: false)
        let fake = FakeBrokerage(environment: .paper)
        fake.fillRows = [
            Fill(orderId: "gtc", symbol: "AAPL", side: .buy, quantity: 1, price: 10, filledAt: eastern(2026, 9, 4, 15, 0)),
            Fill(orderId: "gtc", symbol: "AAPL", side: .buy, quantity: 1, price: 11, filledAt: eastern(2026, 9, 8, 10, 0)),
        ]
        trading.use(fake)
        trading.orders.apply([
            sampleFilled(
                id: "gtc",
                quantity: 2,
                price: 10.5,
                filledAt: eastern(2026, 9, 8, 10, 0),
                submittedAt: eastern(2026, 9, 4, 15, 0),
                timeInForce: "gtc"
            ),
        ])
        let session = DayFillsSession()
        await session.load(symbol: "AAPL", days: ["2026-09-04", "2026-09-08"], trading: trading)
        XCTAssertEqual(session.fills.map(\.orderId), ["gtc", "gtc"])
        XCTAssertEqual(session.fills.map(\.quantity), [1, 1])
        XCTAssertEqual(session.fills.map(\.id), [fillID("gtc"), fillID("gtc", "2026-09-08")])
        session.refresh(orders: trading.orders.orders, trading: trading)
        XCTAssertEqual(session.fills.map(\.quantity), [1, 1])
        XCTAssertNil(session.errorText)
    }

    @MainActor
    func testRefreshKeepsRemoteQuantityUntilTodayActivitiesReload() async {
        let trading = TradingSession(enablesPolling: false)
        let fake = FakeBrokerage(environment: .paper)
        let filledAt = eastern(2026, 9, 4, 10, 0)
        let initial = Fill(orderId: "gtc", symbol: "AAPL", side: .buy, quantity: 1, price: 10, filledAt: filledAt)
        fake.fillRows = [initial]
        trading.use(fake)
        trading.orders.apply([sampleFilled(id: "gtc", quantity: 1, price: 10, filledAt: filledAt)])
        let session = liveSession()
        await session.load(symbol: "AAPL", day: "2026-09-04", trading: trading)
        XCTAssertEqual(session.fills.map(\.quantity), [1])
        XCTAssertEqual(fake.fillsCalls, 1)
        fake.pauseSends = true
        fake.fillRows = [
            Fill(orderId: "gtc", symbol: "AAPL", side: .buy, quantity: 3, price: 10.5, filledAt: filledAt),
        ]
        let next = sampleFilled(id: "gtc", quantity: 3, price: 10.5, filledAt: filledAt)
        trading.orders.apply([next])
        session.refresh(orders: [next], trading: trading)
        XCTAssertEqual(session.fills.map(\.quantity), [1])
        XCTAssertEqual(session.fills.first?.price, 10)
        fake.releasePaused()
        await waitUntil { session.fills.first?.quantity == 3 }
        XCTAssertEqual(session.fills.first?.price, 10.5)
        XCTAssertEqual(fake.fillsCalls, 2)
        XCTAssertEqual(fake.fillsDays, ["2026-09-04", "2026-09-04"])
    }

    @MainActor
    func testRefreshDebouncesTodayActivityReloads() async {
        let trading = TradingSession(enablesPolling: false)
        let fake = FakeBrokerage(environment: .paper)
        let filledAt = eastern(2026, 9, 4, 10, 0)
        fake.fillRows = [
            Fill(orderId: "gtc", symbol: "AAPL", side: .buy, quantity: 1, price: 10, filledAt: filledAt),
        ]
        trading.use(fake)
        trading.orders.apply([sampleFilled(id: "gtc", quantity: 1, price: 10, filledAt: filledAt)])
        let session = liveSession(delay: 50_000_000)
        await session.load(symbol: "AAPL", day: "2026-09-04", trading: trading)
        fake.fillRows = [
            Fill(orderId: "gtc", symbol: "AAPL", side: .buy, quantity: 3, price: 10.5, filledAt: filledAt),
        ]
        let second = sampleFilled(id: "gtc", quantity: 2, price: 10.2, filledAt: filledAt)
        let third = sampleFilled(id: "gtc", quantity: 3, price: 10.5, filledAt: filledAt)
        trading.orders.apply([second])
        session.refresh(orders: [second], trading: trading)
        trading.orders.apply([third])
        session.refresh(orders: [third], trading: trading)
        XCTAssertEqual(session.fills.map(\.quantity), [1])
        await waitUntil { session.fills.first?.quantity == 3 }
        XCTAssertEqual(fake.fillsCalls, 2)
    }

    @MainActor
    func testRefreshDoesNotReloadAHistoricalDay() async {
        let trading = TradingSession(enablesPolling: false)
        let fake = FakeBrokerage(environment: .paper)
        let friday = eastern(2026, 9, 4, 15, 0)
        let monday = eastern(2026, 9, 8, 10, 0)
        fake.fillRows = [
            Fill(orderId: "gtc", symbol: "AAPL", side: .buy, quantity: 1, price: 10, filledAt: friday),
            Fill(orderId: "gtc", symbol: "AAPL", side: .buy, quantity: 1, price: 11, filledAt: monday),
        ]
        trading.use(fake)
        trading.orders.apply([sampleFilled(id: "gtc", quantity: 2, price: 10.5, filledAt: monday)])
        let session = liveSession(now: eastern(2026, 9, 8, 11))
        await session.load(symbol: "AAPL", days: ["2026-09-04", "2026-09-08"], trading: trading)
        XCTAssertEqual(session.fills.map(\.quantity), [1, 1])
        XCTAssertEqual(fake.fillsDays, ["2026-09-04", "2026-09-08"])
        fake.fillRows = [
            Fill(orderId: "gtc", symbol: "AAPL", side: .buy, quantity: 1, price: 10, filledAt: friday),
            Fill(orderId: "gtc", symbol: "AAPL", side: .buy, quantity: 2, price: 10.5, filledAt: monday),
        ]
        let next = sampleFilled(id: "gtc", quantity: 3, price: 10.5, filledAt: monday)
        trading.orders.apply([next])
        session.refresh(orders: [next], trading: trading)
        await waitUntil {
            session.fills.map(\.quantity) == [1.0, 2.0]
        }
        XCTAssertEqual(fake.fillsDays.filter { $0 == "2026-09-04" }.count, 1)
        XCTAssertEqual(fake.fillsDays.filter { $0 == "2026-09-08" }.count, 2)
        XCTAssertEqual(session.fills.map(\.id), [fillID("gtc"), fillID("gtc", "2026-09-08")])
    }

    @MainActor
    func testRefreshSkipsTodayReloadWhenLocalFillsUnchanged() async {
        let trading = TradingSession(enablesPolling: false)
        let fake = FakeBrokerage(environment: .paper)
        let filledAt = eastern(2026, 9, 4, 10, 0)
        let order = sampleFilled(id: "gtc", quantity: 1, price: 10, filledAt: filledAt)
        fake.fillRows = [
            Fill(orderId: "gtc", symbol: "AAPL", side: .buy, quantity: 1, price: 10, filledAt: filledAt),
        ]
        trading.use(fake)
        trading.orders.apply([order])
        let session = liveSession(delay: 20_000_000)
        await session.load(symbol: "AAPL", day: "2026-09-04", trading: trading)
        let calls = fake.fillsCalls
        session.refresh(orders: [order], trading: trading)
        session.refresh(
            orders: [
                order,
                sampleFilled(id: "msft", symbol: "MSFT", quantity: 4, price: 9, filledAt: filledAt),
            ],
            trading: trading
        )
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(fake.fillsCalls, calls)
        XCTAssertEqual(session.fills.map(\.quantity), [1])
    }

    @MainActor
    func testLoadDoesNotScheduleATodayReload() async {
        let trading = TradingSession(enablesPolling: false)
        let fake = FakeBrokerage(environment: .paper)
        let filledAt = eastern(2026, 9, 4, 10, 0)
        fake.fillRows = [
            Fill(orderId: "gtc", symbol: "AAPL", side: .buy, quantity: 1, price: 10, filledAt: filledAt),
        ]
        trading.use(fake)
        trading.orders.apply([sampleFilled(id: "gtc", quantity: 1, price: 10, filledAt: filledAt)])
        let session = liveSession(delay: 20_000_000)
        await session.load(symbol: "AAPL", day: "2026-09-04", trading: trading)
        let calls = fake.fillsCalls
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(fake.fillsCalls, calls)
    }

    @MainActor
    func testResetCancelsPendingTodayReload() async {
        let trading = TradingSession(enablesPolling: false)
        let fake = FakeBrokerage(environment: .paper)
        let filledAt = eastern(2026, 9, 4, 10, 0)
        fake.fillRows = [
            Fill(orderId: "gtc", symbol: "AAPL", side: .buy, quantity: 1, price: 10, filledAt: filledAt),
        ]
        trading.use(fake)
        trading.orders.apply([sampleFilled(id: "gtc", quantity: 1, price: 10, filledAt: filledAt)])
        let session = liveSession(delay: 50_000_000)
        await session.load(symbol: "AAPL", day: "2026-09-04", trading: trading)
        fake.fillRows = [
            Fill(orderId: "gtc", symbol: "AAPL", side: .buy, quantity: 3, price: 10.5, filledAt: filledAt),
        ]
        let next = sampleFilled(id: "gtc", quantity: 3, price: 10.5, filledAt: filledAt)
        trading.orders.apply([next])
        session.refresh(orders: [next], trading: trading)
        session.reset()
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertTrue(session.fills.isEmpty)
        XCTAssertEqual(fake.fillsCalls, 1)
    }

    @MainActor
    func testLoadDoesNotBackfillFailedDayFromTradingOrders() async {
        let trading = TradingSession(enablesPolling: false)
        let fake = FakeBrokerage(environment: .paper)
        let friday = sampleFilled(id: "prior-regular", filledAt: eastern(2026, 9, 4, 15, 0))
        let monday = sampleFilled(id: "today-pre", quantity: 4, filledAt: eastern(2026, 9, 8, 8, 0))
        fake.orderRows = [friday]
        fake.fillsDayErrors = ["2026-09-08": AppError.orderHistoryIncomplete]
        trading.use(fake)
        trading.orders.apply([friday, monday])
        let session = DayFillsSession()
        await session.load(symbol: "AAPL", days: ["2026-09-04", "2026-09-08"], trading: trading)
        XCTAssertEqual(session.fills.map(\.id), [fillID("prior-regular")])
        XCTAssertEqual(session.fills.map(\.quantity), [1])
        XCTAssertEqual(session.errorText, L10n.Trading.orderHistoryIncomplete)
    }

    @MainActor
    func testLoadDoesNotBackfillAmbiguousGTCWhenMondayActivitiesAreEmpty() async {
        let trading = TradingSession(enablesPolling: false)
        let fake = FakeBrokerage(environment: .paper)
        let fridayTime = eastern(2026, 9, 4, 15, 0)
        let mondayTime = eastern(2026, 9, 8, 10, 0)
        fake.fillRows = [
            Fill(orderId: "gtc", symbol: "AAPL", side: .buy, quantity: 1, price: 10, filledAt: fridayTime),
        ]
        trading.use(fake)
        trading.orders.apply([
            sampleFilled(
                id: "gtc",
                quantity: 2,
                price: 10.5,
                filledAt: mondayTime,
                submittedAt: fridayTime,
                timeInForce: "gtc"
            ),
        ])
        let session = liveSession(now: eastern(2026, 9, 8, 11))
        await session.load(symbol: "AAPL", days: ["2026-09-04", "2026-09-08"], trading: trading)
        XCTAssertEqual(session.fills.map(\.id), [fillID("gtc")])
        XCTAssertEqual(session.fills.map(\.quantity), [1])
        XCTAssertEqual(session.errorText, L10n.Trading.orderHistoryIncomplete)
    }

    @MainActor
    func testLoadReloadsTodayWhenOrdersChangeDuringInitialFetch() async {
        let trading = TradingSession(enablesPolling: false)
        let fake = FakeBrokerage(environment: .paper)
        let filledAt = eastern(2026, 9, 4, 10, 0)
        let initial = sampleFilled(id: "gtc", quantity: 1, price: 10, filledAt: filledAt)
        let updated = sampleFilled(id: "gtc", quantity: 3, price: 10.5, filledAt: filledAt)
        fake.fillRowsQueue = [
            [Fill(orderId: "gtc", symbol: "AAPL", side: .buy, quantity: 1, price: 10, filledAt: filledAt)],
            [Fill(orderId: "gtc", symbol: "AAPL", side: .buy, quantity: 3, price: 10.5, filledAt: filledAt)],
        ]
        trading.use(fake)
        trading.orders.apply([initial])
        let session = liveSession(delay: 50_000_000)
        fake.pauseSends = true
        let loading = Task {
            await session.load(symbol: "AAPL", day: "2026-09-04", trading: trading)
        }
        await waitUntil { fake.fillsCalls == 1 }
        trading.orders.apply([updated])
        session.refresh(orders: [updated], trading: trading)
        XCTAssertTrue(session.fills.isEmpty)
        fake.releasePaused()
        await loading.value
        XCTAssertEqual(session.fills.map(\.quantity), [1])
        await waitUntil { session.fills.first?.quantity == 3 }
        XCTAssertEqual(fake.fillsCalls, 2)
        XCTAssertEqual(session.fills.first?.price, 10.5)
    }

    @MainActor
    private func liveSession(now: Date? = nil, delay: UInt64 = 0) -> DayFillsSession {
        let now = now ?? eastern(2026, 9, 4, 11)
        return DayFillsSession(now: { now }, reloadDelayNanoseconds: delay)
    }

    private func fillID(_ orderId: String, _ day: String = "2026-09-04") -> String {
        DayFills.fillID(orderId: orderId, day: day)
    }

    private func sampleFilled(
        id: String,
        symbol: String = "AAPL",
        side: OrderSide = .buy,
        quantity: Double = 1,
        price: Double = 10,
        filledAt: Date,
        submittedAt: Date? = nil,
        timeInForce: String = "day"
    ) -> Order {
        let submittedAt = submittedAt ?? filledAt
        return Order(
            id: id,
            symbol: symbol,
            side: side,
            type: .limit,
            status: .filled,
            quantity: quantity,
            filledQuantity: quantity,
            limitPrice: price,
            stopPrice: nil,
            filledAvgPrice: price,
            timeInForce: timeInForce,
            submittedAt: submittedAt,
            updatedAt: filledAt,
            createdAt: submittedAt,
            filledAt: filledAt,
            clientOrderId: nil,
            orderClass: nil,
            parentOrderId: nil
        )
    }

    private func eastern(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
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
