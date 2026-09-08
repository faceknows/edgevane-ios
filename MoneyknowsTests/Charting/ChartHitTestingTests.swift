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

final class ChartLibraryOptionsTests: XCTestCase {
    func testAttachesFormattersOnlyUntilInstalled() {
        XCTAssertTrue(ChartLibraryOptions.attachFormatters(alreadyInstalled: false))
        XCTAssertFalse(ChartLibraryOptions.attachFormatters(alreadyInstalled: true))
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
