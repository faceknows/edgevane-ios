import XCTest
@testable import Moneyknows

final class AuthFormValidationTests: XCTestCase {
    func testValidEmail() {
        XCTAssertTrue(AuthFormValidation.isValidEmail("user@example.com"))
        XCTAssertFalse(AuthFormValidation.isValidEmail("not-an-email"))
        XCTAssertFalse(AuthFormValidation.isValidEmail(""))
    }

    func testExpiryMilliseconds() {
        let ms: Double = 1_893_456_000_000
        let date = SessionTime.date(fromExpiresAt: ms)
        XCTAssertEqual(date.timeIntervalSince1970, 1_893_456_000, accuracy: 0.001)
    }

    func testResetPasswordRejectsBlankVerificationCode() {
        let error = AuthFormValidation.resetPasswordError(
            email: "user@example.com",
            verificationCode: "   ",
            newPassword: "password123",
            confirmPassword: "password123"
        )

        XCTAssertEqual(error, .verificationCodeRequired)
    }
}

@MainActor
final class SessionRestorationTests: XCTestCase {
    func testExpiredSessionRefreshesBeforeBecomingSignedIn() async throws {
        let fixture = try makeFixture(expiresAt: Date().addingTimeInterval(-60), refreshToken: "refresh")
        defer { fixture.clear() }
        var receivedRefreshToken: String?
        let store = SessionStore(
            keychain: fixture.keychain,
            disk: fixture.disk,
            refreshSession: { token in
                receivedRefreshToken = token
                return AuthSessionDTO(
                    accessToken: "new-access",
                    expiresAt: Date().addingTimeInterval(3600).timeIntervalSince1970,
                    refreshToken: "new-refresh",
                    user: AuthUserDTO(
                        id: "1",
                        email: "a@b.com",
                        username: nil,
                        nickname: nil,
                        role: nil
                    )
                )
            }
        )

        XCTAssertFalse(store.isSignedIn)
        XCTAssertTrue(store.isRestoringSession)

        try await store.restoreIfNeeded()

        XCTAssertEqual(receivedRefreshToken, "refresh")
        XCTAssertFalse(store.isRestoringSession)
        XCTAssertTrue(store.isSignedIn)
        XCTAssertEqual(store.accessToken, "new-access")
    }

    func testExpiredSessionWithoutRefreshTokenDoesNotSignIn() throws {
        let fixture = try makeFixture(expiresAt: Date().addingTimeInterval(-60), refreshToken: nil)
        defer { fixture.clear() }
        let store = SessionStore(
            keychain: fixture.keychain,
            disk: fixture.disk,
            refreshSession: { _ in
                XCTFail("Refresh must not be called without a refresh token")
                throw AppError.network
            }
        )

        XCTAssertFalse(store.isSignedIn)
        XCTAssertFalse(store.isRestoringSession)
        XCTAssertNil(store.accessToken)
    }

    private func makeFixture(expiresAt: Date, refreshToken: String?) throws -> SessionFixture {
        let id = UUID().uuidString
        let fixture = SessionFixture(
            keychain: MemoryCredentialStore(),
            disk: DiskStore(folder: "MoneyknowsTests-\(id)")
        )
        try fixture.keychain.set("expired-access", account: "session.accessToken")
        try fixture.keychain.set(
            String(expiresAt.timeIntervalSince1970),
            account: "session.expiresAt"
        )
        if let refreshToken {
            try fixture.keychain.set(refreshToken, account: "session.refreshToken")
        }
        return fixture
    }
}

private struct SessionFixture {
    let keychain: MemoryCredentialStore
    let disk: DiskStore

    func clear() {
        keychain.delete(account: "session.accessToken")
        keychain.delete(account: "session.refreshToken")
        keychain.delete(account: "session.expiresAt")
        disk.delete(name: "session-user.json")
    }
}

private final class MemoryCredentialStore: CredentialStoring {
    private var values: [String: String] = [:]

    func set(_ value: String, account: String) throws {
        values[account] = value
    }

    func string(account: String) -> String? {
        values[account]
    }

    func delete(account: String) {
        values.removeValue(forKey: account)
    }
}

final class HTTPClientDecodingTests: XCTestCase {
    func testUnwrapsEnvelope() throws {
        let json = #"{"data":{"accessToken":"abc","expiresAt":1893456000000,"user":{"id":"1","email":"a@b.com"}}}"#
        let data = Data(json.utf8)
        let client = HTTPClient(baseURL: AppEnvironment.apiURL)
        let session = try client.decode(AuthSessionDTO.self, from: data)
        XCTAssertEqual(session.accessToken, "abc")
        XCTAssertEqual(session.user?.email, "a@b.com")
    }

    func testReadsBareObject() throws {
        let json = #"{"accessToken":"abc","expiresAt":1893456000,"user":{"id":"1","email":"a@b.com"}}"#
        let data = Data(json.utf8)
        let client = HTTPClient(baseURL: AppEnvironment.apiURL)
        let session = try client.decode(AuthSessionDTO.self, from: data)
        XCTAssertEqual(session.accessToken, "abc")
    }
}
