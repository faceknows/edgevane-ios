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

    func testDomainIncludesOverlay() {
        let domain = SparklineGeometry.domain(values: [10, 12], overlay: [8, 11])
        XCTAssertEqual(domain?.low, 8)
        XCTAssertEqual(domain?.high, 12)
        let size = CGSize(width: 100, height: 40)
        let overlay = SparklineGeometry.points(
            values: [8, 11],
            in: size,
            inset: 0,
            low: 8,
            high: 12
        )
        XCTAssertEqual(overlay[0].y, 40, accuracy: 0.001)
    }

    func testBarDomainUsesHighLowAndOverlay() {
        let bars = [
            Bar(time: Date(), open: 10, high: 12, low: 9, close: 11, volume: 1),
        ]
        let domain = SparklineGeometry.barDomain(bars: bars, overlay: [8])
        XCTAssertEqual(domain?.low, 8)
        XCTAssertEqual(domain?.high, 12)
    }

    func testCandleXIsCenteredInSlot() {
        let size = CGSize(width: 100, height: 40)
        XCTAssertEqual(SparklineGeometry.candleX(index: 0, count: 2, in: size, inset: 0), 25, accuracy: 0.001)
        XCTAssertEqual(SparklineGeometry.candleX(index: 1, count: 2, in: size, inset: 0), 75, accuracy: 0.001)
        XCTAssertEqual(SparklineGeometry.candleX(index: 0, count: 1, in: size, inset: 0), 50, accuracy: 0.001)
    }

    func testHigherPriceMapsHigherOnScreenForCandles() {
        let size = CGSize(width: 100, height: 40)
        let open = SparklineGeometry.y(10, low: 0, high: 20, in: size, inset: 0)
        let close = SparklineGeometry.y(15, low: 0, high: 20, in: size, inset: 0)
        XCTAssertLessThan(close, open)
    }

    func testEmptyPromptOnlyWhenCopyIsSetAndFetchFinished() {
        XCTAssertTrue(SparklinePlot.candles(bars: []).isEmpty)
        XCTAssertFalse(
            SparklinePlot.candles(
                bars: [Bar(time: Date(), open: 1, high: 1, low: 1, close: 1, volume: 1)]
            ).isEmpty
        )
        XCTAssertTrue(SparklinePlot.line(values: [.nan]).isEmpty)
        XCTAssertFalse(SparklinePlot.line(values: [1]).isEmpty)
        XCTAssertFalse(
            SparklineEmptyPolicy.showsPrompt(
                isLoading: false,
                errorText: nil,
                isEmpty: true,
                emptyText: nil
            )
        )
        XCTAssertTrue(
            SparklineEmptyPolicy.showsPrompt(
                isLoading: false,
                errorText: nil,
                isEmpty: true,
                emptyText: "No bars for this session."
            )
        )
        XCTAssertFalse(
            SparklineEmptyPolicy.showsPrompt(
                isLoading: true,
                errorText: nil,
                isEmpty: true,
                emptyText: "No bars for this session."
            )
        )
        XCTAssertFalse(
            SparklineEmptyPolicy.showsPrompt(
                isLoading: false,
                errorText: "failed",
                isEmpty: true,
                emptyText: "No bars for this session."
            )
        )
        XCTAssertFalse(
            SparklineEmptyPolicy.showsPrompt(
                isLoading: false,
                errorText: nil,
                isEmpty: false,
                emptyText: "No bars for this session."
            )
        )
    }

    func testPlotDropsMisalignedOverlay() {
        let lineMismatch = SparklinePlot.line(values: [1, 2], overlay: [1]).aligned()
        XCTAssertEqual(lineMismatch, .line(values: [1, 2], overlay: []))

        let lineNanClose = SparklinePlot.line(values: [1, .nan, 3], overlay: [10, 20, 30]).aligned()
        XCTAssertEqual(lineNanClose, .line(values: [1, 3], overlay: [10, 30]))

        let lineNanOverlay = SparklinePlot.line(values: [1, 2], overlay: [10, .nan]).aligned()
        XCTAssertEqual(lineNanOverlay, .line(values: [1, 2], overlay: []))

        let bar = Bar(time: Date(timeIntervalSince1970: 1), open: 1, high: 1, low: 1, close: 1, volume: 1)
        let candleMismatch = SparklinePlot.candles(bars: [bar], vwap: [1, 2]).aligned()
        XCTAssertEqual(candleMismatch, .candles(bars: [bar], vwap: []))

        let candleNan = SparklinePlot.candles(bars: [bar], vwap: [.nan]).aligned()
        XCTAssertEqual(candleNan, .candles(bars: [bar], vwap: []))

        let candleOk = SparklinePlot.candles(bars: [bar], vwap: [1.5]).aligned()
        XCTAssertEqual(candleOk, .candles(bars: [bar], vwap: [1.5]))

        let t0 = Date(timeIntervalSince1970: 100)
        let t1 = Date(timeIntervalSince1970: 160)
        let t2 = Date(timeIntervalSince1970: 220)
        let timesKept = SparklinePlot.line(
            values: [1, .nan, 3],
            times: [t0, t1, t2],
            overlay: [10, 20, 30]
        ).aligned()
        XCTAssertEqual(timesKept, .line(values: [1, 3], times: [t0, t2], overlay: [10, 30]))
    }

    func testLineXMatchesFirstAndLastPlotEdges() {
        let plot = CGRect(x: 10, y: 4, width: 100, height: 40)
        XCTAssertEqual(SparklineGeometry.lineX(index: 0, count: 3, in: plot), 10, accuracy: 0.001)
        XCTAssertEqual(SparklineGeometry.lineX(index: 2, count: 3, in: plot), 110, accuracy: 0.001)
        XCTAssertEqual(SparklineGeometry.lineX(index: 0, count: 1, in: plot), 60, accuracy: 0.001)
    }

    func testChromePlotRectLeavesRoomForAxes() {
        let rect = SparklineChrome.plotRect(in: CGSize(width: 200, height: 120))
        XCTAssertEqual(rect.minX, SparklineChrome.leadingInset)
        XCTAssertEqual(rect.minY, SparklineChrome.topInset)
        XCTAssertEqual(rect.maxX, 200 - SparklineChrome.trailingInset, accuracy: 0.001)
        XCTAssertEqual(rect.maxY, 120 - SparklineChrome.bottomInset, accuracy: 0.001)
    }

    func testChromeXTicksUseEasternTime() {
        let open = eastern(2026, 9, 4, 9, 30)
        let mid = eastern(2026, 9, 4, 12, 45)
        let close = eastern(2026, 9, 4, 16, 0)
        XCTAssertEqual(SparklineTimeKind.minute.tickKind, .time)
        XCTAssertEqual(SparklineTimeKind.second.tickKind, .timeWithSeconds)
        XCTAssertEqual(
            SparklineChrome.xTicks(times: [open, mid, close], kind: .time).map(\.text),
            ["09:30", "12:45", "16:00"]
        )
        let start = eastern(2026, 9, 4, 10, 1, 5)
        let end = eastern(2026, 9, 4, 10, 9, 55)
        XCTAssertEqual(
            SparklineChrome.xTicks(times: [start, end], kind: .timeWithSeconds).map(\.text),
            ["10:01:05", "10:09:55"]
        )
        XCTAssertTrue(SparklineChrome.xTicks(times: [], kind: .time).isEmpty)
        XCTAssertEqual(SparklineChrome.xTickIndices(count: 0), [])
        XCTAssertEqual(SparklineChrome.xTickIndices(count: 1), [0])
        XCTAssertEqual(SparklineChrome.xTickIndices(count: 2), [0, 1])
        XCTAssertEqual(SparklineChrome.xTickIndices(count: 5), [0, 1, 2, 3, 4])
        XCTAssertEqual(SparklineChrome.xTickIndices(count: 6), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(SparklineChrome.xTickIndices(count: 7).count, 6)
        XCTAssertEqual(SparklineChrome.xTickIndices(count: 7, capacity: 1), [6])
    }

    func testChromeXTickCountFollowsPlotWidth() {
        let open = eastern(2026, 9, 4, 9, 30)
        let times = (0..<12).map { open.addingTimeInterval(TimeInterval($0 * 60)) }
        XCTAssertEqual(SparklineChrome.xTickCapacity(plotWidth: 400, kind: .time), 6)
        XCTAssertEqual(
            SparklineChrome.xTicks(times: times, kind: .time, plotWidth: 400).count,
            6
        )
        XCTAssertEqual(SparklineChrome.xTickCapacity(plotWidth: 80, kind: .timeWithSeconds), 1)
        XCTAssertEqual(
            SparklineChrome.xTicks(times: times, kind: .timeWithSeconds, plotWidth: 80).count,
            1
        )
    }

    func testChromeYTicksAreEvenlySpacedFromHighToLow() {
        let ticks = SparklineChrome.yTickPrices(low: 7, high: 12)
        XCTAssertEqual(ticks.count, 4)
        XCTAssertEqual(ticks[0], 12)
        XCTAssertEqual(ticks[1], 12 - 5.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(ticks[2], 12 - 10.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(ticks[3], 7)
        XCTAssertEqual(SparklineChrome.yTickPrices(low: 10, high: 10), [10])
        XCTAssertEqual(SparklineChrome.extremeCaption(price: "11.17", onLeftHalf: false), "11.17--")
        XCTAssertEqual(SparklineChrome.extremeCaption(price: "10.93", onLeftHalf: true), "--10.93")
    }

    func testChromeLayoutMarksWickHighLowAndLastClose() {
        let t0 = eastern(2026, 9, 4, 9, 30)
        let t1 = eastern(2026, 9, 4, 9, 31)
        let bars = [
            Bar(time: t0, open: 10, high: 12, low: 9, close: 11, volume: 1),
            Bar(time: t1, open: 11, high: 11, low: 7, close: 8, volume: 1),
        ]
        let layout = SparklineChrome.layout(
            for: .candles(bars: bars, timeKind: .minute),
            in: CGSize(width: 200, height: 140)
        )
        XCTAssertEqual(layout?.high?.text, "--12.00")
        XCTAssertEqual(layout?.low?.text, "7.00--")
        XCTAssertEqual(layout?.last?.text, "8.00")
        XCTAssertEqual(layout?.xTicks.map(\.text), ["09:30", "09:31"])
        XCTAssertEqual(layout?.yTicks.count, 4)
        XCTAssertEqual(layout?.yTicks.first?.text, "12.00")
        XCTAssertEqual(layout?.yTicks.last?.text, "7.00")
        XCTAssertNil(layout?.vwapCaption)
        if let high = layout?.high, let low = layout?.low, let last = layout?.last {
            XCTAssertTrue(high.onLeftHalf)
            XCTAssertFalse(low.onLeftHalf)
            XCTAssertLessThan(high.point.y, low.point.y)
            XCTAssertEqual(last.x, low.point.x, accuracy: 0.001)
            XCTAssertLessThan(last.y, low.point.y)
            XCTAssertGreaterThan(layout!.lastEndX, last.x)
        } else {
            XCTFail("expected high, low, and last")
        }
        let withVWAP = SparklineChrome.layout(
            for: .candles(bars: bars, vwap: [10.5, 9.8], timeKind: .minute),
            in: CGSize(width: 200, height: 140)
        )
        XCTAssertEqual(withVWAP?.vwapCaption, "\(L10n.Chart.vwap):9.80")
        let line = SparklineChrome.layout(
            for: .line(
                values: [9, 11, 8],
                times: [t0, t1, t1.addingTimeInterval(60)],
                timeKind: .minute
            ),
            in: CGSize(width: 200, height: 140)
        )
        XCTAssertEqual(line?.high?.text, "11.00--")
        XCTAssertEqual(line?.low?.text, "8.00--")
        XCTAssertEqual(line?.last?.text, "8.00")
        XCTAssertEqual(line?.last?.x, line?.low?.point.x)
        XCTAssertEqual(line!.last!.x, line!.plot.maxX, accuracy: 0.001)
        XCTAssertGreaterThan(line!.lastEndX, line!.plot.maxX)
        XCTAssertEqual(line?.xTicks.map(\.text), ["09:30", "09:31", "09:32"])
        let seconds = SparklineChrome.layout(
            for: .line(
                values: [9, 11],
                times: [t0, eastern(2026, 9, 4, 16, 0)],
                timeKind: .second
            ),
            in: CGSize(width: 200, height: 140)
        )
        XCTAssertEqual(seconds?.xTicks.map(\.text), ["09:30:00", "16:00:00"])
        XCTAssertNil(SparklineChrome.layout(for: .line(values: []), in: CGSize(width: 200, height: 140)))
    }

    func testChromeLayoutKeepsSinglePointFlatLineAndLastDash() {
        let t0 = eastern(2026, 9, 4, 9, 30)
        let size = CGSize(width: 200, height: 140)
        let point = SparklineChrome.layout(
            for: .line(values: [10], times: [t0], timeKind: .minute),
            in: size
        )
        XCTAssertNotNil(point)
        XCTAssertEqual(point?.last?.text, "10.00")
        XCTAssertEqual(point?.yTicks.count, 1)
        XCTAssertGreaterThan(point!.lastEndX, point!.last!.x)

        let flat = SparklineChrome.layout(
            for: .line(
                values: [10, 10, 10],
                times: [t0, t0.addingTimeInterval(60), t0.addingTimeInterval(120)],
                timeKind: .minute
            ),
            in: size
        )
        XCTAssertNotNil(flat)
        XCTAssertEqual(flat?.last?.text, "10.00")
        XCTAssertEqual(flat!.last!.x, flat!.plot.maxX, accuracy: 0.001)
        XCTAssertGreaterThan(flat!.lastEndX, flat!.plot.maxX)

        let candle = SparklineChrome.layout(
            for: .candles(
                bars: [Bar(time: t0, open: 10, high: 10, low: 10, close: 10, volume: 1)],
                timeKind: .minute
            ),
            in: size
        )
        XCTAssertNotNil(candle)
        XCTAssertEqual(candle?.last?.text, "10.00")
        XCTAssertGreaterThan(candle!.lastEndX, candle!.last!.x)
    }

    private func eastern(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        var parts = DateComponents()
        parts.calendar = Calendar(identifier: .gregorian)
        parts.timeZone = MarketClock.easternTimeZone
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        parts.second = second
        return parts.date!
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
            now: Self.eastern(2026, 9, 4, 12, 1)
        )
        XCTAssertTrue(session.bars(for: "MSFT").isEmpty)
        XCTAssertEqual(session.bars(for: "AAPL").last?.close, 11)
        XCTAssertEqual(http.requests.filter { $0.query["symbol"] == "AAPL" }.count, 2)
        XCTAssertEqual(http.requests.last?.query["startTime"], "09:30")
    }

    func testDuplicateSymbolsShareOneMinuteRequest() async throws {
        let http = ScriptedHTTP()
        http.rawResultsBySymbol = [
            "MU": Data(#"[{"d":"09:30","o":1,"h":1,"l":1,"c":10,"v":1}]"#.utf8),
        ]
        let store = BarStore(api: BarsAPI(client: http))
        let session = SubscriptionWatchSession()
        await session.load(
            symbols: ["MU", "mu", "MU"],
            store: store,
            now: Self.eastern(2026, 9, 10, 10)
        )
        XCTAssertEqual(http.requests.count, 1)
        XCTAssertEqual(http.requests.first?.query["symbol"], "MU")
        XCTAssertNil(http.requests.first?.query["startTime"])
        XCTAssertEqual(session.bars(for: "MU").first?.close, 10)
        XCTAssertEqual(session.bars(for: "mu").first?.close, 10)
    }

    func testEmptySuccessIsResolvedWithoutBars() async throws {
        let http = ScriptedHTTP()
        http.rawResultsBySymbol = [
            "MU": Data(#"[]"#.utf8),
        ]
        let store = BarStore(api: BarsAPI(client: http))
        let session = SubscriptionWatchSession()
        XCTAssertFalse(session.hasResolved("MU"))
        await session.load(
            symbols: ["MU"],
            store: store,
            now: Self.eastern(2026, 9, 10, 10)
        )
        XCTAssertTrue(session.hasResolved("MU"))
        XCTAssertTrue(session.bars(for: "MU").isEmpty)
        XCTAssertFalse(session.isLoading("MU"))
        XCTAssertNil(session.failureText(for: "MU"))
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
        let minuteLine = SubscriptionSparklineAssembler.minuteLine(bars1m: bars, interval: .one)
        XCTAssertEqual(minuteLine.values, [1, 2.5])
        XCTAssertEqual(minuteLine.times, [now, now.addingTimeInterval(120)])
        XCTAssertTrue(minuteLine.vwap.isEmpty)
        XCTAssertEqual(SubscriptionSparklineAssembler.closes(bars1s: bars, interval: .one, now: now.addingTimeInterval(120)), [1, 2.5])
        let secondLine = SubscriptionSparklineAssembler.secondLine(bars1s: bars, interval: .one, now: now.addingTimeInterval(120))
        XCTAssertEqual(secondLine.values, [1, 2.5])
        XCTAssertEqual(secondLine.times, [now, now.addingTimeInterval(120)])
    }

    func testMinuteVWAPUsesOneMinuteBarsThenAlignsToInterval() {
        let t0 = Date(timeIntervalSince1970: 1_200)
        let bars = [
            Bar(time: t0, open: 10, high: 10, low: 10, close: 10, volume: 100),
            Bar(time: t0.addingTimeInterval(60), open: 20, high: 20, low: 20, close: 20, volume: 100),
        ]
        XCTAssertEqual(SubscriptionSparklineAssembler.closes(bars1m: bars, interval: .one), [10, 20])
        XCTAssertEqual(SubscriptionSparklineAssembler.vwap(bars1m: bars, interval: .one), [10, 15])
        let five = SubscriptionSparklineAssembler.minutePlot(bars1m: bars, interval: .five, includeVWAP: true)
        XCTAssertEqual(five.closes, [20])
        XCTAssertEqual(five.vwap, [15])
        XCTAssertTrue(SubscriptionSparklineAssembler.minutePlot(bars1m: bars).vwap.isEmpty)
        XCTAssertEqual(SubscriptionSparklineAssembler.minuteInterval, .one)
        let oneWithVWAP = SubscriptionSparklineAssembler.minuteLine(bars1m: bars, includeVWAP: true)
        XCTAssertEqual(oneWithVWAP.values, [10, 20])
        XCTAssertEqual(oneWithVWAP.vwap, [10, 15])
        XCTAssertEqual(oneWithVWAP.times, [t0, t0.addingTimeInterval(60)])
        let dense = (0..<8).map { offset in
            Bar(
                time: t0.addingTimeInterval(TimeInterval(offset * 60)),
                open: 10 + Double(offset),
                high: 10 + Double(offset),
                low: 10 + Double(offset),
                close: 10 + Double(offset),
                volume: 100
            )
        }
        let fiveDense = SubscriptionSparklineAssembler.minutePlot(bars1m: dense, interval: .five, includeVWAP: true)
        XCTAssertEqual(fiveDense.closes, [14, 17])
        XCTAssertEqual(fiveDense.vwap, [12, 13.5])
    }

    func testMinuteCandlesKeepOHLCAndAlignedVWAP() {
        let t0 = Date(timeIntervalSince1970: 1_200)
        let bars = [
            Bar(time: t0, open: 9, high: 11, low: 9, close: 10, volume: 100),
            Bar(time: t0.addingTimeInterval(60), open: 19, high: 21, low: 19, close: 20, volume: 100),
            Bar(time: t0.addingTimeInterval(120), open: 1, high: .nan, low: 1, close: 1, volume: 1),
        ]
        let plot = SubscriptionSparklineAssembler.minuteCandles(bars1m: bars)
        XCTAssertEqual(plot.bars.map(\.open), [9, 19])
        XCTAssertEqual(plot.bars.map(\.close), [10, 20])
        XCTAssertEqual(plot.vwap, [10, 15])
        XCTAssertTrue(SubscriptionSparklineAssembler.minuteCandles(bars1m: bars, includeVWAP: false).vwap.isEmpty)
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

    func testTradeTabSecondsStayAtOneSecond() {
        let t0 = Date(timeIntervalSince1970: 1_200)
        var bars: [Bar] = []
        for offset in 0..<5 {
            let price = Double(offset + 1)
            bars.append(
                Bar(
                    time: t0.addingTimeInterval(TimeInterval(offset)),
                    open: price,
                    high: price,
                    low: price,
                    close: price,
                    volume: 1
                )
            )
        }
        let line = SubscriptionSparklineAssembler.secondLine(
            bars1s: bars,
            now: t0.addingTimeInterval(5)
        )
        XCTAssertEqual(line.values, [1, 2, 3, 4, 5])
        XCTAssertEqual(SubscriptionSparklineAssembler.secondInterval, .one)
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

    func testRetryAfterStartCancelledIsFlushedOnNextStart() async throws {
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
        first.cancel()
        await first.value

        http.rawResults = [
            .success(Data(#"[{"d":"09:30","o":1,"h":1,"l":1,"c":10,"v":1}]"#.utf8)),
        ]
        session.requestRetry("AAPL")
        let second = Task {
            await session.start(
                symbols: ["AAPL"],
                store: store,
                now: Self.eastern(2026, 9, 4, 12)
            )
        }
        await waitUntil { session.bars(for: "AAPL").first?.close == 10 }
        XCTAssertNil(session.failureText(for: "AAPL"))
        second.cancel()
        await second.value
    }

    func testDuplicateRetryClicksShareOneForceRefresh() async throws {
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
            .success(Data(#"[{"d":"09:30","o":1,"h":1,"l":1,"c":11,"v":1}]"#.utf8)),
        ]
        session.requestRetry("AAPL")
        session.requestRetry("AAPL")
        session.requestRetry("AAPL")
        await waitUntil { http.requests.count >= 2 }
        XCTAssertEqual(http.requests.count, 2)
        XCTAssertTrue(session.isLoading("AAPL"))
        http.releasePaused()
        await waitUntil { session.bars(for: "AAPL").first?.close == 10 }
        XCTAssertEqual(http.requests.count, 2)
        XCTAssertFalse(session.isLoading("AAPL"))
        XCTAssertNil(session.failureText(for: "AAPL"))
        task.cancel()
        await task.value
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
