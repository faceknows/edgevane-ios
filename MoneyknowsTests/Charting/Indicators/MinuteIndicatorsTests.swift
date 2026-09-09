import XCTest
@testable import Moneyknows

final class MinuteIndicatorsTests: XCTestCase {
    func testRSIIs100WhenClosesOnlyRise() {
        let bars = closes(10, 11, 12, 13, 14)
        let values = MinuteIndicators.rsiSeries(bars, period: 2)
        XCTAssertNil(values[1])
        XCTAssertEqual(values[2] ?? -1, 100, accuracy: 0.0001)
        XCTAssertEqual(values[4] ?? -1, 100, accuracy: 0.0001)
        XCTAssertEqual(MinuteIndicators.latest(values), 100)
    }

    func testATRAveragesTrueRangeAndPercentUsesLastClose() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let bars = [
            Bar(time: start, open: 10, high: 3, low: 1, close: 2, volume: 1),
            Bar(time: start.addingTimeInterval(60), open: 2, high: 4, low: 2, close: 3, volume: 1),
            Bar(time: start.addingTimeInterval(120), open: 3, high: 5, low: 3, close: 4, volume: 1),
        ]
        XCTAssertEqual(MinuteIndicators.averageATR(bars, count: 10) ?? -1, 2, accuracy: 0.0001)
        let snapshot = MinuteIndicators.snapshot(bars1m: bars, interval: .one, period: 10)
        XCTAssertEqual(snapshot.atr ?? -1, 2, accuracy: 0.0001)
        XCTAssertEqual(snapshot.atrPct ?? -1, 50, accuracy: 0.0001)
    }

    func testADXWilderSmoothingMatchesSeededBars() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let bars = [
            Bar(time: start, open: 10, high: 10, low: 10, close: 10, volume: 1),
            Bar(time: start.addingTimeInterval(60), open: 10, high: 12, low: 10, close: 11, volume: 1),
            Bar(time: start.addingTimeInterval(120), open: 11, high: 11, low: 9, close: 10, volume: 1),
            Bar(time: start.addingTimeInterval(180), open: 10, high: 13, low: 10, close: 12, volume: 1),
        ]
        let series = MinuteIndicators.adxSeries(bars, period: 2)
        XCTAssertEqual(series.plusDI[2] ?? -1, 50, accuracy: 0.0001)
        XCTAssertEqual(series.minusDI[2] ?? -1, 25, accuracy: 0.0001)
        XCTAssertNil(series.adx[2])
        XCTAssertEqual(series.plusDI[3] ?? -1, 60, accuracy: 0.0001)
        XCTAssertEqual(series.minusDI[3] ?? -1, 10, accuracy: 0.0001)
        XCTAssertEqual(series.adx[3] ?? -1, 52.380952, accuracy: 0.0001)
    }

    func testSnapshotUsesAggregatedTimeframeBars() {
        let start = Date(timeIntervalSince1970: 1_700_000_100)
        var bars: [Bar] = []
        for index in 0..<9 {
            let close = Double(10 + index)
            bars.append(
                Bar(
                    time: start.addingTimeInterval(TimeInterval(index * 60)),
                    open: close,
                    high: close,
                    low: close,
                    close: close,
                    volume: 1
                )
            )
        }
        let one = MinuteIndicators.snapshot(bars1m: bars, interval: .one, period: 2)
        let three = MinuteIndicators.snapshot(bars1m: bars, interval: .three, period: 2)
        XCTAssertEqual(one.rsi, 100)
        XCTAssertEqual(three.rsi, 100)
        XCTAssertLessThan(BarAggregator.aggregate(bars, minutes: 3).count, bars.count)
        XCTAssertNotEqual(one.atr, three.atr)
    }

    func testTooFewBarsLeaveSnapshotEmpty() {
        let bars = [Bar(time: Date(), open: 1, high: 1, low: 1, close: 1, volume: 1)]
        let snapshot = MinuteIndicators.snapshot(bars1m: bars, interval: .five)
        XCTAssertNil(snapshot.rsi)
        XCTAssertNil(snapshot.adx)
        XCTAssertNil(snapshot.atr)
        XCTAssertNil(snapshot.atrPct)
    }

    private func closes(_ values: Double...) -> [Bar] {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return values.enumerated().map { index, close in
            Bar(
                time: start.addingTimeInterval(TimeInterval(index * 60)),
                open: close,
                high: close,
                low: close,
                close: close,
                volume: 1
            )
        }
    }
}
