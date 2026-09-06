import XCTest
@testable import Moneyknows

@MainActor
final class AuthorizedSessionTests: XCTestCase {
    func testRetriesAfterRefreshOnUnauthorized() async throws {
        let fixture = try makeSignedInFixture()
        defer { fixture.disk.delete(name: "session-user.json") }

        let scripted = ScriptedHTTP()
        scripted.rawResults = [
            .failure(AppError.http(status: 401, message: nil, errorCode: nil)),
            .success(Data(#"{"nickname":"Ada","id":"1","email":"a@b.com"}"#.utf8)),
        ]

        var refreshed = false
        let session = SessionStore(
            keychain: fixture.keychain,
            disk: fixture.disk,
            refreshSession: { token in
                XCTAssertEqual(token, "refresh")
                refreshed = true
                return AuthSessionDTO(
                    accessToken: "new-access",
                    expiresAt: Date().addingTimeInterval(3600).timeIntervalSince1970,
                    refreshToken: "refresh-2",
                    user: AuthUserDTO(id: "1", email: "a@b.com", username: nil, nickname: "Ada", role: nil)
                )
            }
        )
        XCTAssertTrue(session.isSignedIn)

        let authorized = AuthorizedSession(client: scripted, session: session)
        let user: AuthUserDTO = try await authorized.send(HTTPRequest(method: .get, path: "v1/users/me"))

        XCTAssertTrue(refreshed)
        XCTAssertEqual(user.nickname, "Ada")
        XCTAssertEqual(session.accessToken, "new-access")
        XCTAssertEqual(scripted.requests.count, 2)
        XCTAssertEqual(scripted.requests.last?.extraHeaders["Authorization"], "Bearer new-access")
    }

    func testDelayedSuccessDoesNotApplyAfterSessionSwitch() async throws {
        let fixture = try makeSignedInFixture()
        defer { fixture.disk.delete(name: "session-user.json") }

        let scripted = ScriptedHTTP()
        scripted.pauseSends = true
        scripted.rawResults = [.success(Data())]

        let session = SessionStore(
            keychain: fixture.keychain,
            disk: fixture.disk,
            refreshSession: { _ in
                XCTFail("refresh should not run")
                throw AppError.network
            }
        )
        XCTAssertTrue(session.isSignedIn)

        let authorized = AuthorizedSession(client: scripted, session: session)
        let pending = Task {
            try await authorized.send(HTTPRequest(method: .delete, path: "v1/users/me"))
        }
        await waitUntil { !scripted.requests.isEmpty }

        session.signOut()
        try session.applySignIn(
            AuthSessionDTO(
                accessToken: "access-b",
                expiresAt: Date().addingTimeInterval(3600).timeIntervalSince1970,
                refreshToken: "refresh-b",
                user: AuthUserDTO(id: "user-b", email: "b@b.com", username: nil, nickname: "Bea", role: nil)
            )
        )
        XCTAssertEqual(session.user?.id, "user-b")

        scripted.releasePaused()

        do {
            try await pending.value
            XCTFail("stale success must not apply")
        } catch {
            XCTAssertEqual(error as? AppError, .cancelled)
        }
        XCTAssertTrue(session.isSignedIn)
        XCTAssertEqual(session.user?.id, "user-b")
        XCTAssertEqual(session.accessToken, "access-b")
    }

    func testRefreshWaitIsScopedToSessionGeneration() async throws {
        let fixture = try makeSignedInFixture()
        defer { fixture.disk.delete(name: "session-user.json") }

        let aGate = RefreshGate()
        var refreshTokens: [String] = []
        let session = SessionStore(
            keychain: fixture.keychain,
            disk: fixture.disk,
            refreshSession: { token in
                refreshTokens.append(token)
                if token == "refresh" {
                    return try await aGate.wait()
                }
                return AuthSessionDTO(
                    accessToken: "access-b-new",
                    expiresAt: Date().addingTimeInterval(3600).timeIntervalSince1970,
                    refreshToken: "refresh-b-new",
                    user: AuthUserDTO(id: "user-b", email: "b@b.com", username: nil, nickname: "Bea", role: nil)
                )
            }
        )

        let scripted = ScriptedHTTP()
        scripted.rawResults = [
            .failure(AppError.http(status: 401, message: nil, errorCode: nil)),
            .failure(AppError.http(status: 401, message: nil, errorCode: nil)),
            .success(Data(#"{"id":"user-b","email":"b@b.com","nickname":"Bea"}"#.utf8)),
        ]
        let authorized = AuthorizedSession(client: scripted, session: session)

        let aRequest = Task { () -> AuthUserDTO in
            try await authorized.send(HTTPRequest(method: .get, path: "v1/users/me"))
        }
        await waitUntil { aGate.isWaiting }

        session.signOut()
        try session.applySignIn(
            AuthSessionDTO(
                accessToken: "access-b",
                expiresAt: Date().addingTimeInterval(3600).timeIntervalSince1970,
                refreshToken: "refresh-b",
                user: AuthUserDTO(id: "user-b", email: "b@b.com", username: nil, nickname: "Bea", role: nil)
            )
        )

        let bUser: AuthUserDTO = try await authorized.send(HTTPRequest(method: .get, path: "v1/users/me"))
        XCTAssertEqual(bUser.id, "user-b")
        XCTAssertTrue(refreshTokens.contains("refresh-b"))
        XCTAssertEqual(session.accessToken, "access-b-new")

        aGate.resume(
            AuthSessionDTO(
                accessToken: "late-access",
                expiresAt: Date().addingTimeInterval(3600).timeIntervalSince1970,
                refreshToken: "late-refresh",
                user: AuthUserDTO(id: "1", email: "a@b.com", username: nil, nickname: "Ada", role: nil)
            )
        )

        do {
            _ = try await aRequest.value
            XCTFail("account A refresh must not complete after switch")
        } catch {
            XCTAssertEqual(error as? AppError, .cancelled)
        }
        XCTAssertTrue(session.isSignedIn)
        XCTAssertEqual(session.user?.id, "user-b")
        XCTAssertEqual(session.accessToken, "access-b-new")
    }

    func testLoginStyleUnauthorizedDoesNotUseAuthorizedSession() {
        // Public AuthAPI stays on HTTPClient; a 401 there must not sign out.
        let fixture = try! makeSignedInFixture()
        let session = SessionStore(
            keychain: fixture.keychain,
            disk: fixture.disk,
            refreshSession: { _ in
                XCTFail("login 401 must not refresh the session")
                throw AppError.network
            }
        )
        XCTAssertTrue(session.isSignedIn)
    }

    private func makeSignedInFixture() throws -> (keychain: MemoryCredentialStore, disk: DiskStore) {
        let keychain = MemoryCredentialStore()
        let disk = DiskStore(folder: "MoneyknowsTests-authz-\(UUID().uuidString)")
        try keychain.set("access", account: "session.accessToken")
        try keychain.set("refresh", account: "session.refreshToken")
        try keychain.set(
            String(Date().addingTimeInterval(3600).timeIntervalSince1970),
            account: "session.expiresAt"
        )
        disk.write(
            AppUser(id: "1", email: "a@b.com", username: nil, nickname: nil, role: nil),
            name: "session-user.json"
        )
        return (keychain, disk)
    }
}
