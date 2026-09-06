import Foundation
@testable import Moneyknows

@MainActor
final class RefreshGate {
    private var continuation: CheckedContinuation<AuthSessionDTO, Error>?

    var isWaiting: Bool { continuation != nil }

    func wait() async throws -> AuthSessionDTO {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(_ session: AuthSessionDTO) {
        continuation?.resume(returning: session)
        continuation = nil
    }
}
