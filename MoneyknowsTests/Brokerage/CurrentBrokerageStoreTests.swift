import XCTest
@testable import Moneyknows

@MainActor
final class CurrentBrokerageStoreTests: XCTestCase {
    func testFailedReplaceKeepsPreviousAccount() async throws {
        let keychain = MemoryCredentialStore()
        let disk = DiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)

        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)
        XCTAssertEqual(store.current?.id, "acct-1")
        XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-OLD")

        validator.result = .failure(AppError.http(status: 401, message: "invalid", errorCode: nil))
        do {
            try await store.replace(key: "PK-NEW", secret: "SEC-NEW", environment: .paper)
            XCTFail("replace should fail")
        } catch {
            XCTAssertEqual(store.current?.id, "acct-1")
            XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-OLD")
            XCTAssertEqual(store.credentials(for: .paper)?.secret, "SEC-OLD")
        }
    }

    func testClearAllRemovesCredentials() async throws {
        let keychain = MemoryCredentialStore()
        let disk = DiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-2", provider: "alpaca", environment: .live))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        try await store.replace(key: "PK", secret: "SEC", environment: .live)
        store.clearAll()
        XCTAssertNil(store.current)
        XCTAssertNil(store.credentials(for: .live))
    }

    func testSecretWriteFailureRollsBackKey() async throws {
        let keychain = FailingSecretCredentialStore()
        let disk = DiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)

        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)
        XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-OLD")

        keychain.failNextSecretWrite = true
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        do {
            try await store.replace(key: "PK-NEW", secret: "SEC-NEW", environment: .paper)
            XCTFail("secret write should fail")
        } catch {
            XCTAssertEqual(store.current?.id, "acct-1")
            XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-OLD")
            XCTAssertEqual(store.credentials(for: .paper)?.secret, "SEC-OLD")
        }
    }

    func testPersistentKeychainFailureDoesNotLeaveMixedCredentials() async throws {
        let keychain = PersistentLiveFailingCredentialStore()
        let disk = DiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)

        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)
        XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-OLD")
        XCTAssertEqual(store.credentials(for: .paper)?.secret, "SEC-OLD")

        keychain.failLiveWrites = true
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        do {
            try await store.replace(key: "PK-NEW", secret: "SEC-NEW", environment: .paper)
            XCTFail("live keychain write should fail")
        } catch {
            let credentials = store.credentials(for: .paper)
            if let credentials {
                XCTAssertEqual(credentials.key, "PK-OLD")
                XCTAssertEqual(credentials.secret, "SEC-OLD")
            }
            XCTAssertFalse(credentials?.key == "PK-NEW" && credentials?.secret == "SEC-OLD")
            XCTAssertFalse(credentials?.key == "PK-OLD" && credentials?.secret == "SEC-NEW")
            XCTAssertNotEqual(keychain.string(account: "brokerage.acct-1.key"), "PK-NEW")
        }
    }

    func testInitDiscardsUncommittedPendingCredentials() throws {
        let keychain = MemoryCredentialStore()
        let disk = DiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        try keychain.set("PK-NEW", account: "brokerage.acct-new.key.pending")
        try keychain.set("SEC-NEW", account: "brokerage.acct-new.secret.pending")
        try keychain.set("PK-NEW", account: "brokerage.acct-new.key")
        try keychain.set("SEC-NEW", account: "brokerage.acct-new.secret")
        disk.write(
            BrokerageStateProbe(pendingAccountIds: ["acct-new"]),
            name: "brokerage-state.json"
        )

        let store = CurrentBrokerageStore(
            keychain: keychain,
            disk: disk,
            validator: ScriptedBrokerageValidator()
        )

        XCTAssertNil(store.current)
        XCTAssertNil(store.credentials(for: .paper))
        XCTAssertNil(keychain.string(account: "brokerage.acct-new.key.pending"))
        XCTAssertNil(keychain.string(account: "brokerage.acct-new.secret.pending"))
        XCTAssertNil(keychain.string(account: "brokerage.acct-new.key"))
        XCTAssertNil(keychain.string(account: "brokerage.acct-new.secret"))
    }

    func testClearAllRemovesPendingOrphansNotInState() async throws {
        let keychain = MemoryCredentialStore()
        let disk = DiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-2", provider: "alpaca", environment: .live))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        try await store.replace(key: "PK", secret: "SEC", environment: .live)

        try keychain.set("PK-ORPHAN", account: "brokerage.acct-orphan.key.pending")
        try keychain.set("SEC-ORPHAN", account: "brokerage.acct-orphan.secret.pending")
        try keychain.set("PK-ORPHAN", account: "brokerage.acct-orphan.key")
        try keychain.set("SEC-ORPHAN", account: "brokerage.acct-orphan.secret")

        store.clearAll()

        XCTAssertNil(store.current)
        XCTAssertNil(store.credentials(for: .live))
        XCTAssertTrue(keychain.accounts().isEmpty)
    }

    func testInitKeepsCommittedCredentialsWhenPendingLeftBehind() async throws {
        let keychain = MemoryCredentialStore()
        let disk = DiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)

        try keychain.set("PK-NEW", account: "brokerage.acct-1.key.pending")
        try keychain.set("SEC-NEW", account: "brokerage.acct-1.secret.pending")

        let restored = CurrentBrokerageStore(
            keychain: keychain,
            disk: disk,
            validator: ScriptedBrokerageValidator()
        )
        XCTAssertEqual(restored.current?.id, "acct-1")
        XCTAssertEqual(restored.credentials(for: .paper)?.key, "PK-OLD")
        XCTAssertEqual(restored.credentials(for: .paper)?.secret, "SEC-OLD")
        XCTAssertNil(keychain.string(account: "brokerage.acct-1.key.pending"))
        XCTAssertNil(keychain.string(account: "brokerage.acct-1.secret.pending"))
    }

    func testDelayedReplaceAfterClearAllDoesNotRestoreCredentials() async throws {
        let keychain = MemoryCredentialStore()
        let disk = DiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = GatedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-late", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)

        let pending = Task {
            try await store.replace(key: "PK-LATE", secret: "SEC-LATE", environment: .paper)
        }
        await waitUntil { validator.isWaiting }

        store.clearAll()
        XCTAssertNil(store.current)
        XCTAssertNil(store.credentials(for: .paper))

        validator.resume()

        do {
            try await pending.value
            XCTFail("replace after logout must not succeed")
        } catch {
            XCTAssertEqual(error as? AppError, .cancelled)
        }

        XCTAssertNil(store.current)
        XCTAssertNil(store.credentials(for: .paper))
        XCTAssertNil(keychain.string(account: "brokerage.acct-late.key"))
        XCTAssertNil(keychain.string(account: "brokerage.acct-late.secret"))
        XCTAssertTrue(keychain.accounts().isEmpty)
    }
}

private struct BrokerageStateProbe: Codable {
    var pendingAccountIds: [String]?
}

private final class PersistentLiveFailingCredentialStore: CredentialStoring {
    var failLiveWrites = false
    private var values: [String: String] = [:]

    func set(_ value: String, account: String) throws {
        if failLiveWrites, !account.hasSuffix(".pending") {
            throw AppError.decoding
        }
        values[account] = value
    }

    func string(account: String) -> String? {
        values[account]
    }

    func delete(account: String) {
        values.removeValue(forKey: account)
    }

    func accounts() -> [String] {
        Array(values.keys)
    }
}

private final class FailingSecretCredentialStore: CredentialStoring {
    var failNextSecretWrite = false
    private var values: [String: String] = [:]

    func set(_ value: String, account: String) throws {
        if failNextSecretWrite, account.hasSuffix(".secret") {
            failNextSecretWrite = false
            throw AppError.decoding
        }
        values[account] = value
    }

    func string(account: String) -> String? {
        values[account]
    }

    func delete(account: String) {
        values.removeValue(forKey: account)
    }

    func accounts() -> [String] {
        Array(values.keys)
    }
}

private final class ScriptedBrokerageValidator: BrokerageAccountValidating {
    var result: Result<BrokerageAccount, Error> = .failure(AppError.network)

    func validate(key: String, secret: String, environment: BrokerageEnvironment) async throws -> BrokerageAccount {
        try result.get()
    }
}

@MainActor
private final class GatedBrokerageValidator: BrokerageAccountValidating {
    var result: Result<BrokerageAccount, Error> = .failure(AppError.network)
    private var continuation: CheckedContinuation<Void, Never>?

    var isWaiting: Bool { continuation != nil }

    func validate(key: String, secret: String, environment: BrokerageEnvironment) async throws -> BrokerageAccount {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return try result.get()
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
