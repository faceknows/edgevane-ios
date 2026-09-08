import XCTest
@testable import Moneyknows

final class ErrorCancellationTests: XCTestCase {
    func testRecognizesCancellationKinds() {
        XCTAssertTrue(AppError.cancelled.isCancellation)
        XCTAssertTrue((CancellationError() as Error).isCancellation)
        XCTAssertTrue(URLError(.cancelled).isCancellation)
        XCTAssertTrue(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled).isCancellation)
        XCTAssertFalse(AppError.network.isCancellation)
        XCTAssertFalse(URLError(.timedOut).isCancellation)
        XCTAssertNil(UserFacingError.message(from: CancellationError()))
        XCTAssertNil(UserFacingError.message(from: URLError(.cancelled)))
        XCTAssertEqual(UserFacingError.message(from: AppError.network), L10n.Errors.network)
        XCTAssertEqual(
            UserFacingError.message(from: AppError.orderHistoryIncomplete),
            L10n.Trading.orderHistoryIncomplete
        )
        XCTAssertTrue(AppError.http(status: 401, message: nil, errorCode: nil).isUnauthorized)
        XCTAssertTrue((AppError.http(status: 401, message: nil, errorCode: nil) as Error).isUnauthorized)
        XCTAssertFalse(AppError.http(status: 403, message: nil, errorCode: nil).isUnauthorized)
        XCTAssertFalse(AppError.network.isUnauthorized)
        XCTAssertTrue(AppError.http(status: 500, message: nil, errorCode: nil).isServerFailure)
        XCTAssertTrue((AppError.http(status: 503, message: nil, errorCode: nil) as Error).isServerFailure)
        XCTAssertFalse(AppError.http(status: 401, message: nil, errorCode: nil).isServerFailure)
        XCTAssertFalse(AppError.network.isServerFailure)
        XCTAssertEqual(AppError.decoding.logCode, "decoding")
        XCTAssertEqual(
            AppError.http(status: 422, message: "order abc123 rejected", errorCode: "invalid_qty").logCode,
            "http 422 invalid_qty"
        )
        XCTAssertEqual(
            AppError.http(status: 500, message: "account 99 exploded", errorCode: nil).logCode,
            "http 500"
        )
        XCTAssertFalse(
            AppError.http(status: 500, message: "account 99 exploded", errorCode: nil).logCode.contains("account")
        )
        XCTAssertEqual((NSError(domain: "test", code: 1) as Error).logCode, "unknown")
    }
}
