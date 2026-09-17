import SwiftUI
import XCTest
@testable import Moneyknows

final class ChartHitTestingTests: XCTestCase {
    func testSortsMarkersByTimeThenPriceThenId() {
        let start = Date(timeIntervalSince1970: 1_700_000_100)
        let later = ChartMarker(id: "b", time: start.addingTimeInterval(60), price: 10, kind: .sell, title: nil, position: .auto)
        let cheaper = ChartMarker(id: "a", time: start, price: 9, kind: .buy, title: nil, position: .auto)
        let pricier = ChartMarker(id: "c", time: start, price: 11, kind: .buy, title: nil, position: .auto)
        XCTAssertEqual(ChartHitTesting.sorted([later, pricier, cheaper]).map(\.id), ["a", "c", "b"])
    }

    func testPickedMarkerUsesLibraryIndexNotTradeId() {
        let time = Date(timeIntervalSince1970: 1_700_000_100)
        let zeroth = ChartMarker(id: "0", time: time, price: 10, kind: .buy, title: nil, position: .auto)
        let first = ChartMarker(id: "1", time: time, price: 11, kind: .sell, title: nil, position: .auto)
        XCTAssertNil(ChartHitTesting.pickedMarker(in: [zeroth, first], hoveredId: nil))
        XCTAssertNil(ChartHitTesting.pickedMarker(in: [zeroth, first], hoveredId: "0"))
        XCTAssertNil(ChartHitTesting.pickedMarker(in: [zeroth, first], hoveredId: "1"))
        XCTAssertEqual(
            ChartHitTesting.pickedMarker(in: [zeroth, first], hoveredId: ChartHitTesting.libraryID(index: 1))?.id,
            "1"
        )
        XCTAssertEqual(
            ChartHitTesting.pickedMarker(in: [zeroth, first], hoveredId: ChartHitTesting.libraryID(index: 0))?.id,
            "0"
        )
    }

    func testPickedBarUsesContainingBucketNotNearest() {
        let start = Date(timeIntervalSince1970: 1_700_000_100)
        let first = Bar(time: start, open: 1, high: 1, low: 1, close: 1, volume: 1)
        let second = Bar(time: start.addingTimeInterval(300), open: 2, high: 2, low: 2, close: 2, volume: 1)
        let insideFirst = start.addingTimeInterval(180)
        XCTAssertEqual(ChartHitTesting.pickedBar(in: [first, second], at: insideFirst)?.close, 1)
        XCTAssertEqual(ChartHitTesting.pickedBar(in: [first, second], at: start.addingTimeInterval(300))?.close, 2)
    }

    func testContainingBarDoesNotClampOutsideRange() {
        let start = Date(timeIntervalSince1970: 1_700_000_100)
        let first = Bar(time: start, open: 1, high: 1, low: 1, close: 1, volume: 1)
        let last = Bar(time: start.addingTimeInterval(300), open: 2, high: 2, low: 2, close: 2, volume: 1)
        XCTAssertNil(ChartHitTesting.containingBar(in: [first, last], at: start.addingTimeInterval(-1), duration: 60))
        XCTAssertEqual(ChartHitTesting.containingBar(in: [first, last], at: start.addingTimeInterval(30), duration: 60)?.close, 1)
        XCTAssertNil(ChartHitTesting.containingBar(in: [first, last], at: start.addingTimeInterval(60), duration: 60))
        XCTAssertEqual(ChartHitTesting.containingBar(in: [first, last], at: start.addingTimeInterval(300), duration: 60)?.close, 2)
        XCTAssertNil(ChartHitTesting.containingBar(in: [first, last], at: start.addingTimeInterval(360), duration: 60))
        XCTAssertEqual(ChartHitTesting.pickedBar(in: [first, last], at: start.addingTimeInterval(-1))?.close, 1)
        XCTAssertEqual(ChartHitTesting.pickedBar(in: [first, last], at: start.addingTimeInterval(360))?.close, 2)
    }
}

final class ChartTimeScalePagingTests: XCTestCase {
    func testIgnoresFitContentPaddingThenFiresAfterUserPansLeft() {
        var state = ChartTimeScalePaging.State()
        ChartTimeScalePaging.beginIgnoringFitContent(&state)
        XCTAssertFalse(ChartTimeScalePaging.handleLogicalRange(from: 0, hasBars: true, state: &state))
        XCTAssertTrue(state.ignoringFitContent)
        XCTAssertFalse(ChartTimeScalePaging.handleLogicalRange(from: -0.5, hasBars: true, state: &state))
        XCTAssertFalse(state.ignoringFitContent)
        XCTAssertFalse(ChartTimeScalePaging.handleLogicalRange(from: -0.5, hasBars: true, state: &state))
        XCTAssertTrue(ChartTimeScalePaging.handleLogicalRange(from: -1.2, hasBars: true, state: &state))
        XCTAssertTrue(state.reachedOldest)
        XCTAssertFalse(ChartTimeScalePaging.handleLogicalRange(from: -2, hasBars: true, state: &state))
    }

    func testDoesNotFireWithoutBars() {
        var state = ChartTimeScalePaging.State()
        XCTAssertFalse(ChartTimeScalePaging.handleLogicalRange(from: -1, hasBars: false, state: &state))
        XCTAssertFalse(state.reachedOldest)
    }

    func testDoesNotFireWhenLeftEdgeIsPinnedAtZero() {
        var state = ChartTimeScalePaging.State()
        ChartTimeScalePaging.beginIgnoringFitContent(&state)
        XCTAssertFalse(ChartTimeScalePaging.handleLogicalRange(from: 0, hasBars: true, state: &state))
        XCTAssertFalse(ChartTimeScalePaging.handleLogicalRange(from: 0, hasBars: true, state: &state))
        XCTAssertFalse(state.reachedOldest)
        XCTAssertFalse(ChartTimeScalePaging.locksLeftEdge(state))
    }

    func testRightEdgeLockIsOnlyForInteractiveSourceCharts() {
        XCTAssertTrue(ChartTimeScalePaging.fixesRightEdge(allowsTimeScaleInteraction: true))
        XCTAssertFalse(ChartTimeScalePaging.fixesRightEdge(allowsTimeScaleInteraction: false))
        XCTAssertFalse(
            ChartTimeScalePaging.fixesRightEdge(
                allowsTimeScaleInteraction: true,
                restoringSyncedRange: true
            )
        )
        XCTAssertFalse(
            ChartTimeScalePaging.fixesRightEdge(
                allowsTimeScaleInteraction: true,
                hasCustomRightBound: true
            )
        )
        XCTAssertFalse(
            ChartTimeScalePaging.fixesRightEdge(
                allowsTimeScaleInteraction: false,
                restoringSyncedRange: true
            )
        )
    }

    func testLibraryFixRightEdgeZeroesAPositiveRightOffset() {
        XCTAssertEqual(ChartTimeScalePaging.libraryRightOffset(fixRightEdge: true, rightOffset: 13), 0)
        XCTAssertEqual(ChartTimeScalePaging.libraryRightOffset(fixRightEdge: false, rightOffset: 13), 13)
        XCTAssertEqual(ChartTimeScalePaging.libraryRightOffset(fixRightEdge: true, rightOffset: 0), 0)
    }

    func testLocksLeftEdgeOnlyAfterReachedOldest() {
        var state = ChartTimeScalePaging.State()
        XCTAssertFalse(ChartTimeScalePaging.locksLeftEdge(state))
        ChartTimeScalePaging.beginIgnoringFitContent(&state)
        XCTAssertFalse(ChartTimeScalePaging.handleLogicalRange(from: -0.5, hasBars: true, state: &state))
        XCTAssertFalse(ChartTimeScalePaging.locksLeftEdge(state))
        XCTAssertTrue(ChartTimeScalePaging.handleLogicalRange(from: -1.2, hasBars: true, state: &state))
        XCTAssertTrue(ChartTimeScalePaging.locksLeftEdge(state))
        state.reachedOldest = false
        XCTAssertFalse(ChartTimeScalePaging.locksLeftEdge(state))
    }
}

final class ChartVisibleExtremesTests: XCTestCase {
    func testCandleUsesWickHighLowInsideLogicalRange() {
        let bars = sampleBars(
            (high: 10, low: 8, close: 9),
            (high: 12, low: 9, close: 11),
            (high: 11, low: 7, close: 8),
            (high: 11, low: 10, close: 10.5)
        )
        let labels = ChartVisibleExtremes.labels(in: bars, from: 0.2, to: 2.4, style: .candle)
        XCTAssertEqual(labels?.highIndex, 1)
        XCTAssertEqual(labels?.high, 12)
        XCTAssertEqual(labels?.lowIndex, 2)
        XCTAssertEqual(labels?.low, 7)
        XCTAssertEqual(labels?.lastIndex, 3)
        XCTAssertEqual(labels?.last, 10.5)
    }

    func testLineModeUsesCloseNotWicks() {
        let bars = sampleBars(
            (high: 20, low: 1, close: 9),
            (high: 11, low: 8, close: 10),
            (high: 19, low: 2, close: 7)
        )
        let labels = ChartVisibleExtremes.labels(in: bars, from: 0, to: 2, style: .line)
        XCTAssertEqual(labels?.highIndex, 1)
        XCTAssertEqual(labels?.high, 10)
        XCTAssertEqual(labels?.lowIndex, 2)
        XCTAssertEqual(labels?.low, 7)
        XCTAssertEqual(labels?.last, 7)
    }

    func testKeepsLeftmostBarWhenExtremesTie() {
        let bars = sampleBars(
            (high: 12, low: 8, close: 9),
            (high: 11, low: 8, close: 10),
            (high: 12, low: 9, close: 11)
        )
        let labels = ChartVisibleExtremes.labels(in: bars, from: 0, to: 2, style: .candle)
        XCTAssertEqual(labels?.highIndex, 0)
        XCTAssertEqual(labels?.lowIndex, 0)
    }

    func testClampsPaddedLogicalRangeAndRejectsEmpty() {
        let bars = sampleBars(
            (high: 10, low: 8, close: 9),
            (high: 11, low: 7, close: 8)
        )
        let leftPad = ChartVisibleExtremes.labels(in: bars, from: -0.5, to: 0, style: .candle)
        XCTAssertEqual(leftPad?.highIndex, 0)
        XCTAssertEqual(leftPad?.high, 10)
        XCTAssertEqual(leftPad?.lastIndex, 0)
        let padded = ChartVisibleExtremes.labels(in: bars, from: -0.5, to: 1.2, style: .candle)
        XCTAssertEqual(padded?.highIndex, 1)
        XCTAssertEqual(padded?.high, 11)
        XCTAssertEqual(padded?.lowIndex, 1)
        XCTAssertEqual(padded?.low, 7)
        XCTAssertEqual(padded?.lastIndex, 1)
        XCTAssertEqual(padded?.last, 8)
        XCTAssertNil(ChartVisibleExtremes.labels(in: bars, from: nil, to: 1, style: .candle))
        XCTAssertNil(ChartVisibleExtremes.labels(in: [], from: 0, to: 1, style: .candle))
        XCTAssertNil(ChartVisibleExtremes.labels(in: bars, from: 8, to: 9, style: .candle))
    }

    func testPriceTextFollowsSeriesPrecision() {
        XCTAssertEqual(ChartVisibleExtremes.priceText(11.8, precision: 2), "11.80")
        XCTAssertEqual(ChartVisibleExtremes.priceText(11, precision: 2), "11.00")
        XCTAssertEqual(ChartVisibleExtremes.priceText(0.1234, precision: 4), "0.1234")
        XCTAssertEqual(ChartVisibleExtremes.priceText(0.1234, precision: 2), "0.12")
    }

    func testExtremeCaptionMatchesSparklineLeftAndRight() {
        XCTAssertEqual(ChartVisibleExtremes.extremeCaption(price: "10.93", onLeftHalf: true), "--10.93")
        XCTAssertEqual(ChartVisibleExtremes.extremeCaption(price: "11.17", onLeftHalf: false), "11.17--")
        XCTAssertTrue(ChartVisibleExtremes.isOnLeftHalf(index: 0, from: 0, to: 9))
        XCTAssertFalse(ChartVisibleExtremes.isOnLeftHalf(index: 8, from: 0, to: 9))
        XCTAssertEqual(ChartVisibleExtremes.lastLineEndX(plotRight: 100, canvasWidth: 160), 158)
        XCTAssertEqual(ChartVisibleExtremes.lastLineEndX(plotRight: 200, canvasWidth: 160), 200)
    }

    func testPriceLineCaptionSitsOnRightAxisOutsidePlot() {
        let plotRight = 100.0
        let priceX = ChartVisibleExtremes.priceLineLabelX(plotRight: plotRight)
        let lastX = ChartVisibleExtremes.lastLineEndX(plotRight: plotRight, canvasWidth: 160)
        XCTAssertEqual(priceX, 108)
        XCTAssertGreaterThan(priceX, plotRight)
        XCTAssertLessThan(priceX, lastX)
    }

    func testPriceLineYStaysInsideCanvasAfterNudge() {
        let top = ChartVisibleExtremes.priceLineLabelHalfHeight
        XCTAssertEqual(
            ChartVisibleExtremes.placedPriceLineY(proposed: -10, occupied: [], height: 200),
            top
        )
        XCTAssertEqual(
            ChartVisibleExtremes.placedPriceLineY(proposed: 999, occupied: [], height: 200),
            200 - top
        )
        let tight = 20.0
        let nearTop = ChartVisibleExtremes.placedPriceLineY(proposed: 8, occupied: [8], height: tight)
        XCTAssertGreaterThanOrEqual(nearTop, top)
        XCTAssertLessThanOrEqual(nearTop, tight - top)
        let nearBottom = ChartVisibleExtremes.placedPriceLineY(proposed: 18, occupied: [18], height: tight)
        XCTAssertGreaterThanOrEqual(nearBottom, top)
        XCTAssertLessThanOrEqual(nearBottom, tight - top)
    }

    func testPriceLineYKeepsGapAfterClampNearEdges() {
        let height = 200.0
        let gap = ChartVisibleExtremes.priceLineLabelMinGap
        let topLast = ChartVisibleExtremes.priceLineLabelHalfHeight
        let fromTop = ChartVisibleExtremes.placedPriceLineY(
            proposed: topLast,
            occupied: [topLast],
            height: height
        )
        XCTAssertNotEqual(fromTop, topLast)
        XCTAssertGreaterThanOrEqual(abs(fromTop - topLast), gap)
        XCTAssertGreaterThanOrEqual(fromTop, topLast)
        XCTAssertLessThanOrEqual(fromTop, height - topLast)

        let bottomLast = height - topLast
        let fromBottom = ChartVisibleExtremes.placedPriceLineY(
            proposed: bottomLast,
            occupied: [bottomLast],
            height: height
        )
        XCTAssertNotEqual(fromBottom, bottomLast)
        XCTAssertGreaterThanOrEqual(abs(fromBottom - bottomLast), gap)
        XCTAssertGreaterThanOrEqual(fromBottom, topLast)
        XCTAssertLessThanOrEqual(fromBottom, bottomLast)

        let second = ChartVisibleExtremes.placedPriceLineY(
            proposed: topLast,
            occupied: [topLast, fromTop],
            height: height
        )
        XCTAssertGreaterThanOrEqual(abs(second - topLast), gap)
        XCTAssertGreaterThanOrEqual(abs(second - fromTop), gap)
        XCTAssertGreaterThanOrEqual(second, topLast)
        XCTAssertLessThanOrEqual(second, bottomLast)
    }

    func testFractionDigitsUsesInstrumentTick() {
        XCTAssertEqual(
            ChartVisibleExtremes.fractionDigits(in: sampleBars((high: 11.8, low: 11.2, close: 11.4))),
            2
        )
        XCTAssertEqual(
            ChartVisibleExtremes.fractionDigits(in: sampleBars((high: 0.1234, low: 0.1201, close: 0.1211))),
            4
        )
        XCTAssertEqual(ChartVisibleExtremes.fractionDigits(in: []), 2)
    }

    private func sampleBars(_ values: (high: Double, low: Double, close: Double)...) -> [Bar] {
        let start = Date(timeIntervalSince1970: 1_700_000_100)
        return values.enumerated().map { index, value in
            Bar(
                time: start.addingTimeInterval(TimeInterval(index * 60)),
                open: value.close,
                high: value.high,
                low: value.low,
                close: value.close,
                volume: 1
            )
        }
    }
}

final class ChartViewportResetTests: XCTestCase {
    func testFirstLayoutFitsOnlyWhenBarsAndSizeAreReady() {
        XCTAssertFalse(ChartViewportReset.shouldFitOnFirstLayout(didFit: false, hasBars: false, hasSize: true))
        XCTAssertFalse(ChartViewportReset.shouldFitOnFirstLayout(didFit: false, hasBars: true, hasSize: false))
        XCTAssertFalse(ChartViewportReset.shouldFitOnFirstLayout(didFit: true, hasBars: true, hasSize: true))
        XCTAssertTrue(ChartViewportReset.shouldFitOnFirstLayout(didFit: false, hasBars: true, hasSize: true))
    }

    func testUsablePlotSizeRejectsZeroAndAcceptsLaidOutBounds() {
        XCTAssertFalse(ChartViewportReset.hasUsablePlotSize(width: 0, height: 260))
        XCTAssertFalse(ChartViewportReset.hasUsablePlotSize(width: 390, height: 0))
        XCTAssertFalse(ChartViewportReset.hasUsablePlotSize(width: 0, height: 0))
        XCTAssertTrue(ChartViewportReset.hasUsablePlotSize(width: 390, height: 260))
    }

    func testFitPreparesPagingToIgnoreThePaddedLogicalRange() {
        var state = ChartTimeScalePaging.State()
        ChartTimeScalePaging.beginIgnoringFitContent(&state)
        XCTAssertFalse(ChartTimeScalePaging.handleLogicalRange(from: -0.5, hasBars: true, state: &state))
        XCTAssertFalse(state.reachedOldest)
    }

    func testIncrementalBarsDoNotRefitAfterFirstPaint() {
        let open = Date(timeIntervalSince1970: 1_700_000_000)
        let previous = strideBars(from: open, count: 60, stride: 1)
        let next = strideBars(from: open, count: 61, stride: 1)
        XCTAssertTrue(
            ChartViewportReset.shouldRefitAfterDataChange(didFit: false, previous: [], next: previous)
        )
        XCTAssertFalse(
            ChartViewportReset.shouldRefitAfterDataChange(didFit: true, previous: previous, next: next)
        )
        XCTAssertTrue(
            ChartViewportReset.shouldRefitAfterDataChange(
                didFit: true,
                previous: previous,
                next: strideBars(from: open.addingTimeInterval(86_400), count: 10, stride: 1)
            )
        )
        XCTAssertFalse(
            ChartViewportReset.shouldRefitAfterDataChange(
                didFit: true,
                previous: previous,
                next: Array(strideBars(from: open.addingTimeInterval(-100), count: 100, stride: 1)) + previous
            )
        )
        let ring = strideBars(from: open.addingTimeInterval(1), count: 60, stride: 1)
        XCTAssertFalse(
            ChartViewportReset.shouldRefitAfterDataChange(didFit: true, previous: previous, next: ring)
        )
    }

    func testSameSessionTimesWithDifferentPricesAreANewSeries() {
        let open = Date(timeIntervalSince1970: 1_700_000_000)
        let apple = pricedBars(from: open, count: 60, stride: 60, close: 100)
        let microsoft = pricedBars(from: open, count: 60, stride: 60, close: 400)
        XCTAssertTrue(
            ChartViewportReset.shouldRefitAfterDataChange(didFit: true, previous: apple, next: microsoft)
        )
        var lastTick = apple
        lastTick[lastTick.count - 1].close = 101
        XCTAssertFalse(
            ChartViewportReset.shouldRefitAfterDataChange(didFit: true, previous: apple, next: lastTick)
        )
        let microsoftLonger = pricedBars(from: open, count: 61, stride: 60, close: 400)
        XCTAssertTrue(
            ChartViewportReset.shouldRefitAfterDataChange(didFit: true, previous: apple, next: microsoftLonger)
        )
        let appleTwo = pricedBars(from: open, count: 2, stride: 60, close: 100)
        let microsoftTwo = pricedBars(from: open, count: 2, stride: 60, close: 400)
        XCTAssertTrue(
            ChartViewportReset.shouldRefitAfterDataChange(didFit: true, previous: appleTwo, next: microsoftTwo)
        )
        var twoLastTick = appleTwo
        twoLastTick[1].close = 101
        XCTAssertFalse(
            ChartViewportReset.shouldRefitAfterDataChange(didFit: true, previous: appleTwo, next: twoLastTick)
        )
        let appleOne = pricedBars(from: open, count: 1, stride: 60, close: 100)
        let microsoftOne = pricedBars(from: open, count: 1, stride: 60, close: 400)
        XCTAssertTrue(
            ChartViewportReset.shouldRefitAfterDataChange(
                didFit: true,
                previous: appleOne,
                next: microsoftOne,
                previousSeriesID: "AAPL|regular",
                nextSeriesID: "MSFT|regular"
            )
        )
        var appleOneTick = appleOne
        appleOneTick[0].close = 101
        XCTAssertFalse(
            ChartViewportReset.shouldRefitAfterDataChange(didFit: true, previous: appleOne, next: appleOneTick)
        )
        XCTAssertFalse(
            ChartViewportReset.shouldRefitAfterDataChange(
                didFit: true,
                previous: appleOne,
                next: appleOneTick,
                previousSeriesID: "AAPL|regular",
                nextSeriesID: "AAPL|regular"
            )
        )
        XCTAssertFalse(
            ChartViewportReset.shouldRefitAfterDataChange(didFit: true, previous: appleOne, next: appleOne)
        )
        XCTAssertTrue(
            ChartViewportReset.seriesReplaced(previousSeriesID: "AAPL|regular", nextSeriesID: "MSFT|regular")
        )
        XCTAssertFalse(
            ChartViewportReset.seriesReplaced(previousSeriesID: "AAPL|regular", nextSeriesID: "AAPL|regular")
        )
    }

    private func strideBars(from open: Date, count: Int, stride: TimeInterval) -> [Bar] {
        pricedBars(from: open, count: count, stride: stride, close: 1)
    }

    private func pricedBars(from open: Date, count: Int, stride: TimeInterval, close: Double) -> [Bar] {
        (0..<count).map { index in
            Bar(
                time: open.addingTimeInterval(TimeInterval(index) * stride),
                open: close,
                high: close,
                low: close,
                close: close,
                volume: 1
            )
        }
    }
}

final class ChartPickedSelectionTests: XCTestCase {
    func testOverlappingTimesKeepTheBarOnlyWhenSeriesIdentityMatches() {
        let open = Date(timeIntervalSince1970: 1_700_000_000)
        let apple = Bar(time: open, open: 100, high: 100, low: 100, close: 100, volume: 1)
        var appleTick = apple
        appleTick.close = 101
        let microsoft = Bar(time: open, open: 400, high: 400, low: 400, close: 400, volume: 1)
        XCTAssertEqual(
            ChartPickedSelection.updated(
                picked: apple,
                previousSeriesID: "AAPL|regular",
                next: model([appleTick], id: "AAPL|regular")
            )?.close,
            101
        )
        XCTAssertNil(
            ChartPickedSelection.updated(
                picked: apple,
                previousSeriesID: "AAPL|regular",
                next: model([microsoft], id: "MSFT|regular")
            )
        )
        XCTAssertNil(
            ChartPickedSelection.updated(
                picked: apple,
                previousSeriesID: "AAPL|regular",
                next: model([], id: "AAPL|regular")
            )
        )
        XCTAssertNil(
            ChartPickedSelection.updated(
                picked: nil,
                previousSeriesID: "AAPL|regular",
                next: model([apple], id: "AAPL|regular")
            )
        )
    }

    private func model(_ bars: [Bar], id: String) -> ChartModel {
        ChartModel(
            bars: bars,
            style: .candle,
            overlays: [],
            priceLines: [],
            markers: [],
            showVolume: false,
            usesCalendarDays: false,
            seriesID: id
        )
    }
}

final class ChartLiveViewportTests: XCTestCase {
    func testZoomedWindowStaysWhenABarIsAppended() {
        let open = Date(timeIntervalSince1970: 1_700_000_000)
        let previous = bars(from: open, count: 60, stride: 1)
        let next = bars(from: open, count: 61, stride: 1)
        let preserved = ChartLiveViewport.logicalRangeAfterDataChange(
            from: 20,
            to: 40,
            previous: previous,
            next: next,
            previousDuration: 1,
            nextDuration: 1,
            hasCustomRightBound: false
        )
        XCTAssertEqual(preserved?.from ?? 0, 20, accuracy: 0.01)
        XCTAssertEqual(preserved?.to ?? 0, 40, accuracy: 0.01)
        XCTAssertFalse(
            ChartLiveViewport.shouldFollowNewBar(to: 40, barCount: 60, hasCustomRightBound: false)
        )
    }

    func testShowingLastBarShiftsToIncludeTheNewBar() {
        let open = Date(timeIntervalSince1970: 1_700_000_000)
        let previous = bars(from: open, count: 60, stride: 1)
        let next = bars(from: open, count: 61, stride: 1)
        XCTAssertTrue(
            ChartLiveViewport.shouldFollowNewBar(to: 59.4, barCount: 60, hasCustomRightBound: false)
        )
        let followed = ChartLiveViewport.logicalRangeAfterDataChange(
            from: 20,
            to: 59.4,
            previous: previous,
            next: next,
            previousDuration: 1,
            nextDuration: 1,
            hasCustomRightBound: false
        )
        XCTAssertEqual(followed?.to ?? 0, 60.4, accuracy: 0.01)
        XCTAssertEqual(followed?.from ?? 0, 21, accuracy: 0.01)
    }

    func testRingBufferDropKeepsTheSameBarsWhenZoomed() {
        let open = Date(timeIntervalSince1970: 1_700_000_000)
        let previous = bars(from: open, count: 60, stride: 1)
        let next = bars(from: open.addingTimeInterval(1), count: 60, stride: 1)
        XCTAssertEqual(ChartLiveViewport.indexShift(from: previous, to: next) ?? 0, -1, accuracy: 0.01)
        let preserved = ChartLiveViewport.logicalRangeAfterDataChange(
            from: 20,
            to: 40,
            previous: previous,
            next: next,
            previousDuration: 1,
            nextDuration: 1,
            hasCustomRightBound: false
        )
        XCTAssertEqual(preserved?.from ?? 0, 19, accuracy: 0.01)
        XCTAssertEqual(preserved?.to ?? 0, 39, accuracy: 0.01)
    }

    func testCustomRightBoundDoesNotFollowShift() {
        let open = Date(timeIntervalSince1970: 1_700_000_000)
        let previous = bars(from: open, count: 60, stride: 1)
        let next = bars(from: open, count: 61, stride: 1)
        XCTAssertFalse(
            ChartLiveViewport.shouldFollowNewBar(to: 72, barCount: 60, hasCustomRightBound: true)
        )
        let preserved = ChartLiveViewport.logicalRangeAfterDataChange(
            from: 12,
            to: 72,
            previous: previous,
            next: next,
            previousDuration: 1,
            nextDuration: 1,
            hasCustomRightBound: true
        )
        XCTAssertEqual(preserved?.from ?? 0, 12, accuracy: 0.01)
        XCTAssertEqual(preserved?.to ?? 0, 72, accuracy: 0.01)
    }

    func testDurationChangeKeepsTheWallClockWindow() {
        let open = Date(timeIntervalSince1970: 1_700_000_000)
        let oneSecond = bars(from: open, count: 60, stride: 1)
        let fiveSecond = bars(from: open, count: 12, stride: 5)
        let preserved = ChartLiveViewport.logicalRangeAfterDataChange(
            from: 10,
            to: 40,
            previous: oneSecond,
            next: fiveSecond,
            previousDuration: 1,
            nextDuration: 5,
            hasCustomRightBound: false
        )
        XCTAssertEqual(preserved?.from ?? 0, 2, accuracy: 0.01)
        XCTAssertEqual(preserved?.to ?? 0, 8, accuracy: 0.01)
    }

    func testFollowerForcesLinkedRestoreWhenBarTimesChange() {
        XCTAssertTrue(
            ChartLiveViewport.shouldForceLinkedRestore(
                isFollower: true,
                timesChanged: true,
                durationChanged: false,
                seriesReplaced: false
            )
        )
        XCTAssertFalse(
            ChartLiveViewport.shouldForceLinkedRestore(
                isFollower: true,
                timesChanged: false,
                durationChanged: false,
                seriesReplaced: false
            )
        )
        XCTAssertFalse(
            ChartLiveViewport.shouldForceLinkedRestore(
                isFollower: false,
                timesChanged: true,
                durationChanged: false,
                seriesReplaced: false
            )
        )
        let open = Date(timeIntervalSince1970: 1_700_000_000)
        let previous = bars(from: open, count: 60, stride: 300)
        let next = bars(from: open, count: 61, stride: 300)
        XCTAssertTrue(ChartLiveViewport.timesChanged(previous: previous, next: next))
        let window = ChartVisibleTimeRange(
            from: open,
            to: open.addingTimeInterval(6 * 3600)
        )
        XCTAssertNotNil(
            ChartVisibleTimeRangeSync.logicalRange(for: window, in: next, barDuration: 300)
        )
        XCTAssertTrue(
            ChartVisibleTimeRangeSync.shouldRestore(current: window, target: window, dataChanged: true),
            "Follower bar updates must remap the same wall-clock window, even if SwiftUI did not publish a new range."
        )
        XCTAssertFalse(
            ChartVisibleTimeRangeSync.shouldRestore(current: window, target: window, dataChanged: false)
        )
    }

    private func bars(from open: Date, count: Int, stride: TimeInterval) -> [Bar] {
        (0..<count).map { index in
            Bar(
                time: open.addingTimeInterval(TimeInterval(index) * stride),
                open: 1,
                high: 1,
                low: 1,
                close: 1,
                volume: 1
            )
        }
    }
}

final class ChartLibraryOptionsTests: XCTestCase {
    func testAttachesFormattersOnlyUntilInstalled() {
        XCTAssertTrue(ChartLibraryOptions.attachFormatters(alreadyInstalled: false))
        XCTAssertFalse(ChartLibraryOptions.attachFormatters(alreadyInstalled: true))
    }

    func testVerticalTouchDragIsOffSoThePageCanScroll() {
        XCTAssertFalse(ChartTouchScrolling.verticalTouchDrag)
        XCTAssertTrue(ChartTouchScrolling.horizontalTouchDrag)
    }

    func testVerticalPanBelongsToThePage() {
        XCTAssertFalse(ChartTouchScrolling.chartOwnsPan(translationX: 2, translationY: 20))
        XCTAssertFalse(ChartTouchScrolling.chartOwnsPan(translationX: 0, translationY: -12))
        XCTAssertFalse(ChartTouchScrolling.chartOwnsPan(translationX: 10, translationY: 10))
    }

    func testHorizontalPanBelongsToTheChart() {
        XCTAssertTrue(ChartTouchScrolling.chartOwnsPan(translationX: 20, translationY: 2))
        XCTAssertTrue(ChartTouchScrolling.chartOwnsPan(translationX: -12, translationY: 0))
    }

    func testFollowerChartDoesNotOwnTimeScaleGestures() {
        XCTAssertFalse(ChartTouchScrolling.horzTouchDrag(allowsTimeScaleInteraction: false))
        XCTAssertTrue(ChartTouchScrolling.horzTouchDrag(allowsTimeScaleInteraction: true))
        XCTAssertFalse(ChartTouchScrolling.pinch(allowsTimeScaleInteraction: false))
        XCTAssertTrue(ChartTouchScrolling.pinch(allowsTimeScaleInteraction: true))
        XCTAssertFalse(
            ChartTouchScrolling.chartOwnsPan(
                translationX: 20,
                translationY: 2,
                allowsTimeScaleInteraction: false
            )
        )
        XCTAssertTrue(
            ChartTouchScrolling.chartOwnsPan(
                translationX: 20,
                translationY: 2,
                allowsTimeScaleInteraction: true
            )
        )
    }

    func testDirectionLockWaitsUntilTheFingerMovesFarEnough() {
        XCTAssertFalse(ChartTouchScrolling.hasLockedDirection(translationX: 3, translationY: 4))
        XCTAssertTrue(ChartTouchScrolling.hasLockedDirection(translationX: 10, translationY: 1))
        XCTAssertTrue(ChartTouchScrolling.hasLockedDirection(translationX: 0, translationY: -8))
    }

    func testPageScrollCooperationIgnoresNestedWebScrollPans() {
        let page = UIScrollView()
        let web = UIScrollView()
        XCTAssertTrue(ChartTouchScrolling.isPageScrollPan(page.panGestureRecognizer, enclosingScroll: page))
        XCTAssertFalse(ChartTouchScrolling.isPageScrollPan(web.panGestureRecognizer, enclosingScroll: page))
        XCTAssertFalse(ChartTouchScrolling.isPageScrollPan(page.panGestureRecognizer, enclosingScroll: nil))
    }

    func testVolumeStripSitsBelowPriceAndLeavesAGap() {
        let total: CGFloat = 260
        let volumeHeight = ChartVolumeLayout.defaultVolumeHeight(in: total)
        let price = ChartVolumeLayout.priceMargins(volumeHeight: volumeHeight, totalHeight: total)
        let volume = ChartVolumeLayout.volumeMargins(volumeHeight: volumeHeight, totalHeight: total)
        XCTAssertGreaterThan(volume.top, 1 - price.bottom)
        XCTAssertLessThan(volume.top + volume.bottom, 1)
        let without = ChartVolumeLayout.priceMargins(volumeHeight: nil, totalHeight: total)
        XCTAssertEqual(without.bottom, ChartVolumeLayout.priceBottomWithoutVolume)
        XCTAssertEqual(ChartVolumeLayout.defaultVolumeHeight(in: total), total * CGFloat(ChartVolumeLayout.defaultVolumeFraction))
    }

    func testCustomVolumeHeightChangesPriceBottomMargin() {
        let total: CGFloat = 200
        let compact = ChartVolumeLayout.priceMargins(volumeHeight: 20, totalHeight: total)
        let tall = ChartVolumeLayout.priceMargins(volumeHeight: 80, totalHeight: total)
        XCTAssertGreaterThan(tall.bottom, compact.bottom)
        XCTAssertEqual(ChartVolumeLayout.priceMargins(volumeHeight: nil, totalHeight: total).bottom, ChartVolumeLayout.priceBottomWithoutVolume)
    }
}

final class ChartVisibleTimeRangeSyncTests: XCTestCase {
    func testSameWindowIsNotRestoredAgain() {
        let range = ChartVisibleTimeRange(from: t(0), to: t(3_600))
        XCTAssertFalse(ChartVisibleTimeRangeSync.shouldRestore(current: range, target: range, dataChanged: false))
        XCTAssertTrue(ChartVisibleTimeRangeSync.shouldRestore(current: nil, target: range, dataChanged: false))
        XCTAssertTrue(ChartVisibleTimeRangeSync.shouldRestore(current: range, target: range, dataChanged: true))
        XCTAssertFalse(ChartVisibleTimeRangeSync.shouldPublish(applied: range, observed: range))
        XCTAssertTrue(ChartVisibleTimeRangeSync.shouldPublish(applied: nil, observed: range))
    }

    func testLogicalBarCountIsNotTheWindow() {
        let open = t(0)
        let close = t(6 * 3600)
        let window = ChartVisibleTimeRange(from: open, to: close)
        let oneMinute = bars(from: open, count: 360, stride: 60)
        let fiveMinute = bars(from: open, count: 72, stride: 300)
        XCTAssertTrue(ChartVisibleTimeRangeSync.intersects(window, bars: oneMinute))
        XCTAssertTrue(ChartVisibleTimeRangeSync.intersects(window, bars: fiveMinute))
        let one = ChartVisibleTimeRangeSync.logicalRange(for: window, in: oneMinute, barDuration: 60)
        let five = ChartVisibleTimeRangeSync.logicalRange(for: window, in: fiveMinute, barDuration: 300)
        XCTAssertEqual(one?.from ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(five?.from ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(one?.to ?? 0, 360, accuracy: 0.01)
        XCTAssertEqual(five?.to ?? 0, 72, accuracy: 0.01)
        XCTAssertLessThan(five?.to ?? 0, one?.to ?? 0)
    }

    func testShorterSeriesKeepsTheSameWallClockEnd() {
        let open = t(0)
        let close = t(6 * 3600)
        let window = ChartVisibleTimeRange(from: open, to: close)
        let nasdaq = bars(from: open, count: 60, stride: 300)
        let logical = ChartVisibleTimeRangeSync.logicalRange(for: window, in: nasdaq, barDuration: 300)
        XCTAssertEqual(logical?.from ?? -1, 0, accuracy: 0.01)
        XCTAssertGreaterThan(logical?.to ?? 0, 59)
        XCTAssertEqual(logical?.to ?? 0, 72, accuracy: 0.01)
        XCTAssertGreaterThan(logical?.to ?? 0, Double(nasdaq.count - 1))
        XCTAssertEqual(
            ChartVisibleTimeRangeSync.rightOffset(
                to: logical?.to ?? 0,
                lastIndex: ChartVisibleTimeRangeSync.lastIndex(barCount: nasdaq.count)
            ),
            13,
            accuracy: 0.01
        )
        XCTAssertEqual(
            ChartVisibleTimeRangeSync.customMaxLogicalTo(to: logical?.to ?? 0, barCount: nasdaq.count) ?? 0,
            72,
            accuracy: 0.01
        )
        XCTAssertTrue(
            ChartVisibleTimeRangeSync.extendsPastLastBar(to: logical?.to ?? 0, barCount: nasdaq.count)
        )
        XCTAssertFalse(
            ChartTimeScalePaging.fixesRightEdge(allowsTimeScaleInteraction: false)
        )
    }

    func testRestoredWindowKeepsItsRightBoundButBlocksFurtherFuturePan() {
        let open = t(0)
        let close = t(6 * 3600)
        let window = ChartVisibleTimeRange(from: open, to: close)
        let fiveMinute = bars(from: open, count: 60, stride: 300)
        let logical = ChartVisibleTimeRangeSync.logicalRange(for: window, in: fiveMinute, barDuration: 300)
        XCTAssertEqual(logical?.to ?? 0, 72, accuracy: 0.01)
        let lastIndex = ChartVisibleTimeRangeSync.lastIndex(barCount: fiveMinute.count)
        XCTAssertEqual(
            ChartVisibleTimeRangeSync.rightOffset(to: logical?.to ?? 0, lastIndex: lastIndex),
            13,
            accuracy: 0.01
        )
        XCTAssertEqual(
            ChartTimeScalePaging.libraryRightOffset(fixRightEdge: true, rightOffset: 13),
            0
        )
        let maxTo = ChartVisibleTimeRangeSync.customMaxLogicalTo(
            to: logical?.to ?? 0,
            barCount: fiveMinute.count
        )
        XCTAssertEqual(maxTo ?? 0, 72, accuracy: 0.01)
        XCTAssertFalse(
            ChartTimeScalePaging.fixesRightEdge(
                allowsTimeScaleInteraction: true,
                hasCustomRightBound: maxTo != nil,
                restoringSyncedRange: true
            )
        )
        XCTAssertFalse(
            ChartTimeScalePaging.fixesRightEdge(
                allowsTimeScaleInteraction: true,
                hasCustomRightBound: maxTo != nil
            )
        )
        let overshoot = ChartVisibleTimeRangeSync.clampedLogicalRange(
            from: 20,
            to: 80,
            maxTo: maxTo ?? 0
        )
        XCTAssertEqual(overshoot?.to ?? 0, 72, accuracy: 0.01)
        XCTAssertEqual(overshoot?.from ?? 0, 12, accuracy: 0.01)
        XCTAssertNil(
            ChartVisibleTimeRangeSync.clampedLogicalRange(from: 0, to: 50, maxTo: maxTo ?? 0)
        )
        XCTAssertNil(
            ChartVisibleTimeRangeSync.clampedLogicalRange(from: 12, to: 72, maxTo: maxTo ?? 0)
        )
        XCTAssertTrue(
            ChartVisibleTimeRangeSync.extendsPastLastBar(to: 77.8, barCount: 78)
        )
        XCTAssertEqual(
            ChartVisibleTimeRangeSync.customMaxLogicalTo(to: 77.8, barCount: 78) ?? 0,
            77.8,
            accuracy: 0.01
        )
        XCTAssertFalse(
            ChartVisibleTimeRangeSync.extendsPastLastBar(to: 77, barCount: 78)
        )
        XCTAssertNil(
            ChartVisibleTimeRangeSync.customMaxLogicalTo(to: 77, barCount: 78)
        )
        XCTAssertNil(
            ChartVisibleTimeRangeSync.customMaxLogicalTo(to: 72, barCount: 80)
        )
    }

    func testVisibleTimeOvershootIsNotPublishedBeforeLogicalClamp() {
        XCTAssertTrue(ChartVisibleTimeRangeSync.visibleTimeNotifiesBeforeLogicalRange)
        XCTAssertFalse(ChartVisibleTimeRangeSync.shouldPublishLibraryVisibleTime)
        let open = t(0)
        let fiveMinute = bars(from: open, count: 60, stride: 300)
        let last = fiveMinute[fiveMinute.count - 1].time
        let restored = ChartVisibleTimeRange(
            from: open,
            to: last.addingTimeInterval(13 * 300)
        )
        // Library visible-time never includes empty future; `to` is the last bar.
        let clippedByLibrary = ChartVisibleTimeRange(from: open, to: last)
        XCTAssertEqual(clippedByLibrary.to, last)
        XCTAssertTrue(
            ChartVisibleTimeRangeSync.shouldPublish(applied: restored, observed: clippedByLibrary),
            "Clipped library visible-time looks like a new window; do not publish it."
        )
        let published = ChartVisibleTimeRangeSync.visibleTimeRange(
            from: 0,
            to: 72,
            in: fiveMinute,
            duration: 300
        )
        XCTAssertEqual(
            published?.to.timeIntervalSince(last) ?? 0,
            13 * 300,
            accuracy: 0.01
        )
        XCTAssertEqual(
            ChartVisibleTimeRangeSync.time(atLogical: 77.8, in: bars(from: open, count: 78, stride: 300), duration: 300)?
                .timeIntervalSince(open) ?? 0,
            77.8 * 300,
            accuracy: 0.01
        )
        let overshoot = ChartVisibleTimeRangeSync.clampedLogicalRange(from: 20, to: 80, maxTo: 72)
        let afterClamp = ChartVisibleTimeRangeSync.visibleTimeRange(
            from: overshoot?.from ?? 0,
            to: overshoot?.to ?? 0,
            in: fiveMinute,
            duration: 300
        )
        XCTAssertEqual(afterClamp?.to.timeIntervalSince(open) ?? 0, 72 * 300, accuracy: 0.01)
        XCTAssertGreaterThan(afterClamp?.to.timeIntervalSince(last) ?? 0, 0)
    }

    func testZeroOffsetRightBoundIsLastIndex() {
        XCTAssertEqual(ChartVisibleTimeRangeSync.lastIndex(barCount: 78), 77)
        XCTAssertFalse(
            ChartVisibleTimeRangeSync.extendsPastLastBar(to: 77, barCount: 78)
        )
        XCTAssertNil(
            ChartVisibleTimeRangeSync.customMaxLogicalTo(to: 77, barCount: 78)
        )
        XCTAssertTrue(
            ChartVisibleTimeRangeSync.extendsPastLastBar(to: 77.8, barCount: 78)
        )
        let open = t(0)
        let close = t(6 * 3600)
        let window = ChartVisibleTimeRange(from: open, to: close)
        let fiveMinute = bars(from: open, count: 72, stride: 300)
        let logical = ChartVisibleTimeRangeSync.logicalRange(for: window, in: fiveMinute, barDuration: 300)
        XCTAssertEqual(logical?.to ?? 0, 72, accuracy: 0.01)
        XCTAssertTrue(
            ChartVisibleTimeRangeSync.extendsPastLastBar(to: logical?.to ?? 0, barCount: fiveMinute.count)
        )
        XCTAssertEqual(
            ChartVisibleTimeRangeSync.rightOffset(
                to: logical?.to ?? 0,
                lastIndex: ChartVisibleTimeRangeSync.lastIndex(barCount: fiveMinute.count)
            ),
            1,
            accuracy: 0.01
        )
        XCTAssertNotNil(
            ChartVisibleTimeRangeSync.customMaxLogicalTo(to: logical?.to ?? 0, barCount: fiveMinute.count)
        )
        XCTAssertTrue(
            ChartTimeScalePaging.fixesRightEdge(allowsTimeScaleInteraction: true)
        )
        XCTAssertFalse(
            ChartTimeScalePaging.fixesRightEdge(
                allowsTimeScaleInteraction: true,
                hasCustomRightBound: true
            )
        )
    }

    func testBarTimeMapsToItsIndex() {
        let start = t(0)
        let sample = bars(from: start, count: 12, stride: 300)
        XCTAssertEqual(
            ChartVisibleTimeRangeSync.logicalIndex(of: start.addingTimeInterval(1_500), in: sample, duration: 300),
            5,
            accuracy: 0.01
        )
    }

    func testSingleFiveMinuteBarUsesPassedDurationNotOneMinute() {
        XCTAssertEqual(MinuteInterval.five.barDuration, 300)
        XCTAssertEqual(MinuteInterval.three.barDuration, 180)
        let open = t(0)
        let window = ChartVisibleTimeRange(from: open, to: open.addingTimeInterval(1_800))
        let single = bars(from: open, count: 1, stride: 300)
        let logical = ChartVisibleTimeRangeSync.logicalRange(for: window, in: single, barDuration: 300)
        XCTAssertEqual(logical?.from ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(logical?.to ?? 0, 6, accuracy: 0.01)
        XCTAssertNil(ChartVisibleTimeRangeSync.logicalRange(for: window, in: single, barDuration: 0))
    }

    func testLeadingGapDoesNotBecomeTheBarDuration() {
        let open = t(0)
        let window = ChartVisibleTimeRange(from: open, to: open.addingTimeInterval(1_800))
        let gapped = [
            bar(at: open),
            bar(at: open.addingTimeInterval(900))
        ]
        let logical = ChartVisibleTimeRangeSync.logicalRange(for: window, in: gapped, barDuration: 300)
        XCTAssertEqual(logical?.from ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(logical?.to ?? 0, 4, accuracy: 0.01)
    }

    func testRangeOutsideTheSessionDoesNotIntersect() {
        let session = bars(from: t(0), count: 10, stride: 60)
        let otherDay = ChartVisibleTimeRange(from: t(86_400), to: t(90_000))
        XCTAssertFalse(ChartVisibleTimeRangeSync.intersects(otherDay, bars: session))
        XCTAssertFalse(ChartVisibleTimeRangeSync.intersects(otherDay, bars: []))
    }

    func testSubSecondJitterCountsAsTheSameWindow() {
        let range = ChartVisibleTimeRange(from: t(0), to: t(3_600))
        let jittered = ChartVisibleTimeRange(from: t(0.4), to: t(3_600.4))
        XCTAssertTrue(range.isApproximatelyEqual(to: jittered))
        XCTAssertFalse(ChartVisibleTimeRangeSync.shouldRestore(current: range, target: jittered, dataChanged: false))
    }

    private func t(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func bars(from start: Date, count: Int, stride: TimeInterval) -> [Bar] {
        (0..<count).map { index in
            bar(at: start.addingTimeInterval(TimeInterval(index) * stride))
        }
    }

    private func bar(at time: Date) -> Bar {
        Bar(time: time, open: 1, high: 1, low: 1, close: 1, volume: 1)
    }
}

final class ChartPaletteTests: XCTestCase {
    func testBuyAndSellMarkersAreBlue() {
        let dark = ChartPalette.colors(scheme: .dark)
        let light = ChartPalette.colors(scheme: .light)
        XCTAssertGreaterThan(dark.buy.blue, dark.buy.red)
        XCTAssertGreaterThan(dark.buy.blue, dark.buy.green)
        XCTAssertGreaterThan(dark.sell.blue, dark.sell.red)
        XCTAssertGreaterThan(dark.sell.blue, dark.sell.green)
        XCTAssertGreaterThan(light.buy.blue, light.buy.red)
        XCTAssertGreaterThan(light.buy.blue, light.buy.green)
        XCTAssertGreaterThan(light.sell.blue, light.sell.red)
        XCTAssertGreaterThan(light.sell.blue, light.sell.green)
    }
}
