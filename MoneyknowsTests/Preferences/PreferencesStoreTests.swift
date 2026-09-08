import XCTest
@testable import Moneyknows

@MainActor
final class PreferencesStoreTests: XCTestCase {
    func testColdStartSameUserStillFetchesServerPreferences() async {
        let disk = DiskStore(folder: "MoneyknowsTests-prefs-\(UUID().uuidString)")
        disk.write(UserPreferences.defaults, name: "user-preferences.json")
        disk.write(PreferenceMetaProbe(userId: "user-1"), name: "user-preferences-meta.json")

        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"{"valuePerTrade":80,"showMarketTrade":true}"#.utf8)),
        ]
        let store = PreferencesStore(api: PreferencesAPI(client: http), disk: disk)
        store.prepareForUser("user-1")

        XCTAssertEqual(store.values.valuePerTrade, 100)
        await store.refreshIfNeeded(userId: "user-1")

        XCTAssertEqual(http.requests.count, 1)
        XCTAssertEqual(http.requests.first?.method, .get)
        XCTAssertEqual(store.values.valuePerTrade, 80)
        XCTAssertTrue(store.values.showMarketTrade)

        await store.refreshIfNeeded(userId: "user-1")
        XCTAssertEqual(http.requests.count, 1)
    }

    func testFailedPatchDoesNotRevertEarlierSuccessfulChange() async {
        let disk = DiskStore(folder: "MoneyknowsTests-prefs-\(UUID().uuidString)")
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"{"showOTOAction":true}"#.utf8)),
            .failure(AppError.network),
        ]
        let store = PreferencesStore(api: PreferencesAPI(client: http), disk: disk)
        store.prepareForUser("user-1")

        await store.apply(
            { $0.showOTOAction = true },
            patch: UserPreferencePatch(showOTOAction: true),
            userId: "user-1"
        )
        await store.apply(
            { $0.showMarketTrade = true },
            patch: UserPreferencePatch(showMarketTrade: true),
            userId: "user-1"
        )

        XCTAssertTrue(store.values.showOTOAction)
        XCTAssertFalse(store.values.showMarketTrade)
    }

    func testLateGetDoesNotOverwriteSuccessfulPatch() async {
        let disk = DiskStore(folder: "MoneyknowsTests-prefs-\(UUID().uuidString)")
        let http = ScriptedHTTP()
        http.pauseSends = true
        http.rawResults = [
            .success(Data(#"{"showOTOAction":false,"valuePerTrade":80}"#.utf8)),
            .success(Data(#"{"showOTOAction":true,"valuePerTrade":80}"#.utf8)),
        ]
        let store = PreferencesStore(api: PreferencesAPI(client: http), disk: disk)
        store.prepareForUser("user-1")

        let refresh = Task { await store.refresh(userId: "user-1") }
        await waitUntil { !http.requests.isEmpty }

        let apply = Task {
            await store.apply(
                { $0.showOTOAction = true },
                patch: UserPreferencePatch(showOTOAction: true),
                userId: "user-1"
            )
        }
        await waitUntil { store.isSaving }

        http.releasePaused()
        await refresh.value
        await apply.value

        XCTAssertTrue(store.values.showOTOAction)
        XCTAssertEqual(store.values.valuePerTrade, 80)
        XCTAssertEqual(http.requests.count, 2)
        XCTAssertEqual(http.requests.first?.method, .get)
        XCTAssertEqual(http.requests.last?.method, .patch)
    }

    func testQueuedWriteForPreviousUserDoesNotPatchAfterSwitch() async {
        let disk = DiskStore(folder: "MoneyknowsTests-prefs-\(UUID().uuidString)")
        let http = ScriptedHTTP()
        http.pauseSends = true
        http.rawResults = [
            .success(Data(#"{"showOTOAction":true}"#.utf8)),
            .success(Data(#"{"showMarketTrade":true}"#.utf8)),
        ]
        let store = PreferencesStore(api: PreferencesAPI(client: http), disk: disk)
        store.prepareForUser("user-a")

        let first = Task {
            await store.apply(
                { $0.showOTOAction = true },
                patch: UserPreferencePatch(showOTOAction: true),
                userId: "user-a"
            )
        }
        let second = Task {
            await store.apply(
                { $0.showMarketTrade = true },
                patch: UserPreferencePatch(showMarketTrade: true),
                userId: "user-a"
            )
        }

        await waitUntil { !http.requests.isEmpty }
        store.markSessionStale()
        store.prepareForUser("user-b")
        http.releasePaused()
        await first.value
        await second.value

        XCTAssertEqual(http.requests.count, 1)
        XCTAssertFalse(store.values.showOTOAction)
        XCTAssertFalse(store.values.showMarketTrade)
    }
}

@MainActor
final class ProfileStoreTests: XCTestCase {
    func testResetClearsRoleConfiguration() async throws {
        let keychain = MemoryCredentialStore()
        let disk = DiskStore(folder: "MoneyknowsTests-profile-\(UUID().uuidString)")
        try keychain.set("access", account: "session.accessToken")
        try keychain.set(
            String(Date().addingTimeInterval(3600).timeIntervalSince1970),
            account: "session.expiresAt"
        )
        let session = SessionStore(
            keychain: keychain,
            disk: disk,
            refreshSession: { _ in
                XCTFail("refresh should not run")
                throw AppError.network
            }
        )
        session.applyUser(AppUser(id: "1", email: "a@b.com", username: nil, nickname: nil, role: nil))

        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"{"id":"1","email":"a@b.com","nickname":"Ada"}"#.utf8)),
            .success(Data(#"{"configuration":{"MAX_ORDER_VALUE":75,"SCANNERS":true}}"#.utf8)),
        ]
        let store = ProfileStore(api: UserAPI(client: http), session: session)
        await store.refresh()

        XCTAssertEqual(store.roleConfiguration?.maxOrderValue, 75)
        store.reset()
        XCTAssertNil(store.roleConfiguration)
        XCTAssertNil(store.errorText)
    }

    func testDelayedRefreshAfterResetDoesNotApplyPreviousUser() async throws {
        let keychain = MemoryCredentialStore()
        let disk = DiskStore(folder: "MoneyknowsTests-profile-\(UUID().uuidString)")
        try keychain.set("access", account: "session.accessToken")
        try keychain.set(
            String(Date().addingTimeInterval(3600).timeIntervalSince1970),
            account: "session.expiresAt"
        )
        disk.write(
            AppUser(id: "user-b", email: "b@b.com", username: nil, nickname: nil, role: nil),
            name: "session-user.json"
        )
        let session = SessionStore(
            keychain: keychain,
            disk: disk,
            refreshSession: { _ in
                XCTFail("refresh should not run")
                throw AppError.network
            }
        )
        let http = ScriptedHTTP()
        http.pauseSends = true
        http.rawResults = [
            .success(Data(#"{"id":"user-a","email":"a@b.com","nickname":"Old"}"#.utf8)),
            .success(Data(#"{"configuration":{"MAX_ORDER_VALUE":10}}"#.utf8)),
        ]
        let store = ProfileStore(api: UserAPI(client: http), session: session)
        let refresh = Task { await store.refresh() }

        await waitUntil { !http.requests.isEmpty }
        store.reset()
        http.releasePaused()
        await refresh.value

        XCTAssertEqual(session.user?.id, "user-b")
        XCTAssertNil(store.roleConfiguration)
    }

    func testRefreshRecoversUserWhenLocalCacheMissing() async throws {
        let keychain = MemoryCredentialStore()
        let disk = DiskStore(folder: "MoneyknowsTests-profile-\(UUID().uuidString)")
        try keychain.set("access", account: "session.accessToken")
        try keychain.set(
            String(Date().addingTimeInterval(3600).timeIntervalSince1970),
            account: "session.expiresAt"
        )
        let session = SessionStore(
            keychain: keychain,
            disk: disk,
            refreshSession: { _ in
                XCTFail("refresh should not run")
                throw AppError.network
            }
        )
        XCTAssertTrue(session.isSignedIn)
        XCTAssertNil(session.user)

        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"{"id":"1","email":"a@b.com","nickname":"Ada"}"#.utf8)),
            .success(Data(#"{"configuration":{"MAX_ORDER_VALUE":75}}"#.utf8)),
        ]
        let store = ProfileStore(api: UserAPI(client: http), session: session)
        await store.refresh()

        XCTAssertEqual(session.user?.id, "1")
        XCTAssertEqual(session.user?.email, "a@b.com")
        XCTAssertEqual(store.roleConfiguration?.maxOrderValue, 75)
    }

    func testRefreshIdentityAppliesUserWithoutWaitingForRoleConfig() async throws {
        let keychain = MemoryCredentialStore()
        let disk = DiskStore(folder: "MoneyknowsTests-profile-identity-\(UUID().uuidString)")
        try keychain.set("access", account: "session.accessToken")
        try keychain.set(
            String(Date().addingTimeInterval(3600).timeIntervalSince1970),
            account: "session.expiresAt"
        )
        let session = SessionStore(
            keychain: keychain,
            disk: disk,
            refreshSession: { _ in
                XCTFail("refresh should not run")
                throw AppError.network
            }
        )
        XCTAssertNil(session.user)

        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"{"id":"1","email":"a@b.com","nickname":"Ada"}"#.utf8)),
            .success(Data(#"{"configuration":{"MAX_ORDER_VALUE":75}}"#.utf8)),
        ]
        let store = ProfileStore(api: UserAPI(client: http), session: session)
        await store.refreshIdentity()

        XCTAssertEqual(session.user?.id, "1")
        XCTAssertNil(store.roleConfiguration)
        XCTAssertEqual(http.requests.map(\.path), ["v1/users/me"])
    }
}

private struct PreferenceMetaProbe: Codable {
    var userId: String?
}
