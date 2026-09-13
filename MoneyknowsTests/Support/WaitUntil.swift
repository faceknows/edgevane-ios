import Foundation
import XCTest

@MainActor
func waitUntil(
    _ condition: @escaping @MainActor () -> Bool,
    timeoutSeconds: TimeInterval = 2,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while Date() < deadline {
        if condition() { return }
        await Task.yield()
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("waitUntil timed out after \(timeoutSeconds)s", file: file, line: line)
}

@MainActor
final class WaitGate {
    private var continuation: CheckedContinuation<Void, Never>?

    var isWaiting: Bool { continuation != nil }

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
