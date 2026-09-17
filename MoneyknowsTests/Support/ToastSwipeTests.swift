import XCTest
@testable import Moneyknows

final class ToastSwipeTests: XCTestCase {
    func testHorizontalSwipeDismisses() {
        XCTAssertTrue(ToastSwipe.shouldDismiss(translation: CGSize(width: 72, height: 0)))
        XCTAssertTrue(ToastSwipe.shouldDismiss(translation: CGSize(width: -80, height: 10)))
        XCTAssertFalse(ToastSwipe.shouldDismiss(translation: CGSize(width: 40, height: 8)))
    }

    func testUpwardSwipeDismisses() {
        XCTAssertTrue(ToastSwipe.shouldDismiss(translation: CGSize(width: 0, height: -72)))
        XCTAssertFalse(ToastSwipe.shouldDismiss(translation: CGSize(width: 0, height: 40)))
        XCTAssertFalse(ToastSwipe.shouldDismiss(translation: CGSize(width: 12, height: -20)))
    }

    func testFlickPredictedEndDismisses() {
        XCTAssertTrue(
            ToastSwipe.shouldDismiss(
                translation: CGSize(width: 20, height: 0),
                predicted: CGSize(width: 140, height: 0)
            )
        )
        XCTAssertTrue(
            ToastSwipe.shouldDismiss(
                translation: CGSize(width: 0, height: -10),
                predicted: CGSize(width: 8, height: -160)
            )
        )
    }

    func testFlyOffFollowsDominantDirection() {
        let right = ToastSwipe.flyOffOffset(translation: CGSize(width: 90, height: -10), travel: 480)
        XCTAssertEqual(right.width, 480)
        XCTAssertEqual(right.height, -10)

        let left = ToastSwipe.flyOffOffset(translation: CGSize(width: -90, height: 4), travel: 480)
        XCTAssertEqual(left.width, -480)
        XCTAssertEqual(left.height, 4)

        let up = ToastSwipe.flyOffOffset(translation: CGSize(width: 8, height: -90), travel: 480)
        XCTAssertEqual(up.width, 8)
        XCTAssertEqual(up.height, -480)
    }
}
