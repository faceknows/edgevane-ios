import XCTest
@testable import Moneyknows

final class VWAPTests: XCTestCase {
    func testTypicalPriceVolumeWeightedAndZeroVolumeUsesClose() {
        let start = Date(timeIntervalSince1970: 1_778_000_000)
        let bars = [
            Bar(time: start, open: 1, high: 3, low: 1, close: 2, volume: 10),
            Bar(time: start.addingTimeInterval(60), open: 2, high: 4, low: 2, close: 3, volume: 0),
            Bar(time: start.addingTimeInterval(120), open: 3, high: 5, low: 3, close: 4, volume: 10),
        ]
        let series = VWAP.series(from: bars)
        XCTAssertEqual(series.count, 3)
        XCTAssertEqual(series[0].value, 2, accuracy: 0.0001)
        XCTAssertEqual(series[1].value, 2, accuracy: 0.0001)
        XCTAssertEqual(series[2].value, 3, accuracy: 0.0001)
        XCTAssertEqual(series[2].time, bars[2].time)
    }

    func testEmptyBarsProduceNoPoints() {
        XCTAssertTrue(VWAP.series(from: []).isEmpty)
    }
}

final class BarAggregatorTests: XCTestCase {
    func testAggregatesOHLCAndVolumeByBucket() {
        let start = Date(timeIntervalSince1970: 1_700_000_100)
        let bars = [
            Bar(time: start, open: 10, high: 11, low: 9, close: 10.5, volume: 1),
            Bar(time: start.addingTimeInterval(60), open: 10.5, high: 12, low: 8, close: 11, volume: 2),
            Bar(time: start.addingTimeInterval(120), open: 11, high: 11.5, low: 10, close: 10.2, volume: 3),
            Bar(time: start.addingTimeInterval(180), open: 10.2, high: 10.4, low: 10, close: 10.1, volume: 4),
        ]
        let aggregated = BarAggregator.aggregate(bars, minutes: 3)
        XCTAssertEqual(aggregated.count, 2)
        XCTAssertEqual(aggregated[0].open, 10)
        XCTAssertEqual(aggregated[0].high, 12)
        XCTAssertEqual(aggregated[0].low, 8)
        XCTAssertEqual(aggregated[0].close, 10.2)
        XCTAssertEqual(aggregated[0].volume, 6)
        XCTAssertEqual(aggregated[1].open, 10.2)
        XCTAssertEqual(aggregated[1].volume, 4)
    }

    func testSecondsAggregatorSharesBucketRules() {
        let start = Date(timeIntervalSince1970: 1_700_000_100)
        let bars = [
            Bar(time: start, open: 1, high: 2, low: 1, close: 1.5, volume: 1),
            Bar(time: start.addingTimeInterval(1), open: 1.5, high: 3, low: 1, close: 2, volume: 2),
            Bar(time: start.addingTimeInterval(5), open: 2, high: 2.5, low: 2, close: 2.2, volume: 3),
        ]
        let aggregated = BarAggregator.aggregate(bars, seconds: 5)
        XCTAssertEqual(aggregated.count, 2)
        XCTAssertEqual(aggregated[0].open, 1)
        XCTAssertEqual(aggregated[0].high, 3)
        XCTAssertEqual(aggregated[0].close, 2)
        XCTAssertEqual(aggregated[0].volume, 3)
        XCTAssertEqual(BarAggregator.aggregate(bars, seconds: 1), bars)
    }

    func testOneMinuteReturnsOriginalBars() {
        let bars = [Bar(time: Date(), open: 1, high: 1, low: 1, close: 1, volume: 1)]
        XCTAssertEqual(BarAggregator.aggregate(bars, minutes: 1), bars)
    }
}

final class BarTimeTests: XCTestCase {
    func testParsesUnixSecondsMillisecondsAndISO() {
        let seconds = BarTime.parse("1693827000")
        XCTAssertEqual(seconds?.timeIntervalSince1970, 1_693_827_000)
        XCTAssertEqual(BarTime.parseUnix(1_693_827_000)?.timeIntervalSince1970, 1_693_827_000)
        XCTAssertEqual(BarTime.parseUnix(1_693_827_000_000)?.timeIntervalSince1970, 1_693_827_000)
        XCTAssertNil(BarTime.parseUnix(500))
        let millis = BarTime.parse("1693827000000")
        XCTAssertEqual(millis?.timeIntervalSince1970, 1_693_827_000)
        XCTAssertNotNil(BarTime.parse("2026-09-04T13:30:00Z"))
        XCTAssertEqual(BarTime.parse("2026-09-04T13:30:00Z")?.timeIntervalSince1970, ISO8601DateFormatter().date(from: "2026-09-04T13:30:00Z")?.timeIntervalSince1970)
        XCTAssertNil(BarTime.parse(" "))
        XCTAssertNil(BarTime.parse("not-a-date"))
        XCTAssertNil(BarTime.parse("09:30"))
        let clock = BarTime.parse("09:30", date: "2026-09-04")
        XCTAssertEqual(MarketClock.usDateString(from: clock!), "2026-09-04")
        XCTAssertEqual(MarketClock.usTimeString(from: clock!), "09:30")
        XCTAssertEqual(BarTime.parse("0930", date: "2026-09-04"), clock)
        let day = BarTime.parse("2026-09-04")
        XCTAssertEqual(MarketClock.usDateString(from: day!), "2026-09-04")
        XCTAssertEqual(MarketClock.usTimeString(from: day!), "00:00")
        XCTAssertNil(BarTime.parse("1e20"))
        XCTAssertNil(BarTime.parse("1e+20"))
        XCTAssertNil(BarTime.parse("1e16"))
    }
}

final class MinuteChartAssemblerTests: XCTestCase {
    func testVWAPUsesOneMinuteBarsAndPriceLinesFollowSnapshot() {
        let start = Date(timeIntervalSince1970: 1_700_000_100)
        let bars1m = (0..<6).map { index in
            Bar(
                time: start.addingTimeInterval(TimeInterval(index * 60)),
                open: 10,
                high: 11,
                low: 9,
                close: 10,
                volume: 1
            )
        }
        let marker = ChartMarker(
            id: "fill-1",
            time: start,
            price: 10,
            kind: .buy,
            title: "1@10",
            position: .auto
        )
        let model = MinuteChartAssembler.model(
            bars1m: bars1m,
            interval: .five,
            style: .candle,
            showVWAP: true,
            previousClose: 9.5,
            sessionOpen: 10.1,
            markers: [marker]
        )
        XCTAssertEqual(model.bars.count, 2)
        XCTAssertEqual(model.overlays.first?.id, "vwap")
        XCTAssertEqual(model.overlays.first?.points.count, bars1m.count)
        XCTAssertEqual(model.priceLines.map(\.id), ["prevClose", "sessionOpen"])
        XCTAssertTrue(model.priceLines.allSatisfy(\.dashed))
        XCTAssertEqual(model.markers, [marker])
        XCTAssertFalse(model.followLatest)

        let hidden = MinuteChartAssembler.model(
            bars1m: bars1m,
            interval: .one,
            style: .line,
            showVWAP: false,
            previousClose: nil,
            sessionOpen: nil
        )
        XCTAssertTrue(hidden.overlays.isEmpty)
        XCTAssertTrue(hidden.priceLines.isEmpty)
        XCTAssertEqual(hidden.bars.count, 6)
    }
}
