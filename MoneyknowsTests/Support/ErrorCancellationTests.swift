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
        XCTAssertTrue(AppError.http(status: 401, message: nil, errorCode: nil).isUnauthorized)
        XCTAssertTrue((AppError.http(status: 401, message: nil, errorCode: nil) as Error).isUnauthorized)
        XCTAssertFalse(AppError.http(status: 403, message: nil, errorCode: nil).isUnauthorized)
        XCTAssertFalse(AppError.network.isUnauthorized)
    }
}
