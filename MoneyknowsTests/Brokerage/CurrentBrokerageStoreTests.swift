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
        try store.clearAll()
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
            XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r1.key"), "PK-OLD")
            XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r1.secret"), "SEC-OLD")
            XCTAssertNil(keychain.string(account: "brokerage.acct-1.paper.r2.key"))
        }
    }

    func testReplaceStoresCredentialsInVersionedSlot() async throws {
        let keychain = MemoryCredentialStore()
        let disk = DiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)

        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)
        XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r1.key"), "PK-OLD")
        XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r1.secret"), "SEC-OLD")
        XCTAssertNil(keychain.string(account: "brokerage.acct-1.key"))

        try await store.replace(key: "PK-NEW", secret: "SEC-NEW", environment: .paper)
        XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-NEW")
        XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r2.key"), "PK-NEW")
        XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r2.secret"), "SEC-NEW")
        XCTAssertNil(keychain.string(account: "brokerage.acct-1.paper.r1.key"))
        XCTAssertNil(keychain.string(account: "brokerage.acct-1.paper.r1.secret"))
    }

    func testStatePersistFailureKeepsPreviousCredentials() async throws {
        let keychain = MemoryCredentialStore()
        let disk = ScriptedDiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)

        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)
        let generation = store.generation
        XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-OLD")

        disk.failCheckedWrites = true
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        do {
            try await store.replace(key: "PK-NEW", secret: "SEC-NEW", environment: .paper)
            XCTFail("state persist should fail")
        } catch {
            XCTAssertEqual(store.current?.id, "acct-1")
            XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-OLD")
            XCTAssertEqual(store.credentials(for: .paper)?.secret, "SEC-OLD")
            XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r1.key"), "PK-OLD")
            XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r1.secret"), "SEC-OLD")
            XCTAssertNil(keychain.string(account: "brokerage.acct-1.paper.r2.key"))
            XCTAssertNil(keychain.string(account: "brokerage.acct-1.paper.r2.secret"))
            XCTAssertEqual(store.generation, generation)
        }
    }

    func testReplacePersistVerifyFailureKeepsCommittedSlot() async throws {
        let keychain = MemoryCredentialStore()
        let disk = ScriptedDiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)

        disk.failCheckedVerifyOnceNames = ["brokerage-state.json"]
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        try await store.replace(key: "PK-NEW", secret: "SEC-NEW", environment: .paper)
        XCTAssertEqual(store.current?.id, "acct-1")
        XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-NEW")
        XCTAssertEqual(store.credentials(for: .paper)?.secret, "SEC-NEW")
        XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r2.key"), "PK-NEW")
        XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r2.secret"), "SEC-NEW")
        XCTAssertNil(keychain.string(account: "brokerage.acct-1.paper.r1.key"))
    }

    func testReplacePersistVerifyFailureIsolatesWhenDurableStateUnreadable() async throws {
        let keychain = MemoryCredentialStore()
        let disk = ScriptedDiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(
            keychain: keychain,
            disk: disk,
            validator: validator,
            clearRetryNanoseconds: 20_000_000
        )
        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)

        disk.resetIOCounts()
        disk.failCheckedVerifyOnceNames = ["brokerage-state.json"]
        disk.failReadsAfterSuccesses = ["brokerage-state.json": 3]
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        do {
            try await store.replace(key: "PK-NEW", secret: "SEC-NEW", environment: .paper)
            XCTFail("unreadable durable state must not succeed")
        } catch {
            XCTAssertNil(store.current)
            XCTAssertNil(store.credentials(for: .paper))
            XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r2.key"), "PK-NEW")
            XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r1.key"), "PK-OLD")
            XCTAssertTrue(disk.exists(name: "brokerage-pending-deletes.json"))
        }

        disk.failReadsAfterSuccesses = [:]
        store.setForeground(true)
        await waitUntil {
            store.credentials(for: .paper)?.key == "PK-NEW"
        }
        XCTAssertEqual(store.current?.id, "acct-1")
        XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r2.key"), "PK-NEW")
    }

    func testReplaceDoesNotClobberOtherEnvironmentWhenStateReadFails() async throws {
        let keychain = MemoryCredentialStore()
        let disk = ScriptedDiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-paper", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        try await store.replace(key: "PK-PAPER", secret: "SEC-PAPER", environment: .paper)
        validator.result = .success(BrokerageAccount(id: "acct-live", provider: "alpaca", environment: .live))
        try await store.replace(key: "PK-LIVE", secret: "SEC-LIVE", environment: .live)

        disk.failReads = true
        validator.result = .success(BrokerageAccount(id: "acct-paper", provider: "alpaca", environment: .paper))
        do {
            try await store.replace(key: "PK-PAPER-NEW", secret: "SEC-PAPER-NEW", environment: .paper)
            XCTFail("unreadable state must not be treated as empty")
        } catch {
            XCTAssertEqual(keychain.string(account: "brokerage.acct-paper.paper.r1.key"), "PK-PAPER")
            XCTAssertEqual(keychain.string(account: "brokerage.acct-live.live.r1.key"), "PK-LIVE")
            XCTAssertNil(keychain.string(account: "brokerage.acct-paper.paper.r2.key"))
        }

        disk.failReads = false
        XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-PAPER")
        XCTAssertEqual(store.credentials(for: .live)?.key, "PK-LIVE")
    }

    func testReplaceDoesNotClobberOtherEnvironmentWhenStateRereadFails() async throws {
        let keychain = MemoryCredentialStore()
        let disk = ScriptedDiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-paper", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(
            keychain: keychain,
            disk: disk,
            validator: validator,
            clearRetryNanoseconds: 20_000_000
        )
        store.setForeground(true)
        try await store.replace(key: "PK-PAPER", secret: "SEC-PAPER", environment: .paper)
        validator.result = .success(BrokerageAccount(id: "acct-live", provider: "alpaca", environment: .live))
        try await store.replace(key: "PK-LIVE", secret: "SEC-LIVE", environment: .live)

        disk.resetIOCounts()
        disk.failReadsAfterSuccesses = ["brokerage-state.json": 1]
        validator.result = .success(BrokerageAccount(id: "acct-paper", provider: "alpaca", environment: .paper))
        do {
            try await store.replace(key: "PK-PAPER-NEW", secret: "SEC-PAPER-NEW", environment: .paper)
            XCTFail("state reread failure must not persist a paper-only state")
        } catch {
            XCTAssertNil(store.current)
            XCTAssertEqual(keychain.string(account: "brokerage.acct-paper.paper.r1.key"), "PK-PAPER")
            XCTAssertEqual(keychain.string(account: "brokerage.acct-live.live.r1.key"), "PK-LIVE")
        }

        disk.failReadsAfterSuccesses = [:]
        await waitUntil {
            store.credentials(for: .paper)?.key == "PK-PAPER"
                && store.credentials(for: .live)?.key == "PK-LIVE"
                && keychain.string(account: "brokerage.acct-paper.paper.r2.key") == nil
        }
        XCTAssertEqual(store.current?.id, "acct-live")
        XCTAssertEqual(keychain.string(account: "brokerage.acct-paper.paper.r1.key"), "PK-PAPER")
        XCTAssertEqual(keychain.string(account: "brokerage.acct-live.live.r1.key"), "PK-LIVE")
    }

    func testReplaceAbortsWhenKeychainAccountsUnreadable() async throws {
        let keychain = StickyCredentialStore()
        let disk = DiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)

        keychain.failAccounts = true
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        do {
            try await store.replace(key: "PK-NEW", secret: "SEC-NEW", environment: .paper)
            XCTFail("unreadable keychain accounts must abort replace")
        } catch {
            XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r1.key"), "PK-OLD")
            XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r1.secret"), "SEC-OLD")
            XCTAssertNil(keychain.string(account: "brokerage.acct-1.paper.r2.key"))
            XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-OLD")
        }
    }

    func testReplaceAbortsWhenKeychainCollisionReadFails() async throws {
        let keychain = StickyCredentialStore()
        let disk = DiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)

        keychain.failStringReads = true
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        do {
            try await store.replace(key: "PK-NEW", secret: "SEC-NEW", environment: .paper)
            XCTFail("keychain read errors must not be treated as missing slots")
        } catch {
            keychain.failStringReads = false
            XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r1.key"), "PK-OLD")
            XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r1.secret"), "SEC-OLD")
            XCTAssertNil(keychain.string(account: "brokerage.acct-1.paper.r2.key"))
            XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-OLD")
        }
    }

    func testReplaceKeepsNewStateWhenPendingManifestCleanupFails() async throws {
        let keychain = MemoryCredentialStore()
        let disk = ScriptedDiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(
            keychain: keychain,
            disk: disk,
            validator: validator,
            clearRetryNanoseconds: 20_000_000
        )
        store.setForeground(true)
        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)

        disk.resetIOCounts()
        disk.failCheckedAfterSuccesses = ["brokerage-pending-deletes.json": 2]
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        do {
            try await store.replace(key: "PK-NEW", secret: "SEC-NEW", environment: .paper)
            XCTFail("pending manifest cleanup should fail after state commit")
        } catch {
            XCTAssertEqual(store.current?.id, "acct-1")
            XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-NEW")
            XCTAssertEqual(store.credentials(for: .paper)?.secret, "SEC-NEW")
            XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r2.key"), "PK-NEW")
            XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r1.key"), "PK-OLD")
        }

        disk.failCheckedAfterSuccesses = [:]
        await waitUntil {
            store.credentials(for: .paper)?.key == "PK-NEW"
                && keychain.string(account: "brokerage.acct-1.paper.r1.key") == nil
        }
        XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r2.key"), "PK-NEW")
        XCTAssertFalse(disk.exists(name: "brokerage-logout.json"))

        disk.resetIOCounts()
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(disk.readSuccesses["brokerage-state.json"] ?? 0, 0)
        XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-NEW")
    }

    func testLogoutDoesNotWriteLowEpochTombstoneWhenStateUnreadable() async throws {
        let keychain = StickyCredentialStore()
        let disk = ScriptedDiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)
        let originalEpoch = try XCTUnwrap(disk.peek(BrokerageEpochProbe.self, name: "brokerage-state.json")?.writeEpoch)
        XCTAssertGreaterThan(originalEpoch, 0)

        keychain.failDeletes = true
        disk.resetIOCounts()
        disk.failReadsAfterSuccesses = ["brokerage-state.json": 1]
        do {
            try store.clearAll()
            XCTFail("unreadable epoch must not write a logout tombstone")
        } catch {
            XCTAssertFalse(disk.exists(name: "brokerage-logout.json"))
            XCTAssertEqual(
                try disk.peek(BrokerageEpochProbe.self, name: "brokerage-state.json")?.writeEpoch,
                originalEpoch
            )
            XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r1.key"), "PK-OLD")
        }

        disk.failReadsAfterSuccesses = [:]
        keychain.failDeletes = false
        let restored = CurrentBrokerageStore(
            keychain: keychain,
            disk: disk,
            validator: ScriptedBrokerageValidator()
        )
        XCTAssertFalse(disk.exists(name: "brokerage-logout.json"))
        XCTAssertEqual(restored.current?.id, "acct-1")
        XCTAssertEqual(restored.credentials(for: .paper)?.key, "PK-OLD")
        XCTAssertEqual(
            try disk.peek(BrokerageEpochProbe.self, name: "brokerage-state.json")?.writeEpoch,
            originalEpoch
        )
    }

    func testReplaceDoesNotWriteLowEpochStateWhenExistingEpochUnreadable() async throws {
        let keychain = MemoryCredentialStore()
        let disk = ScriptedDiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)
        let originalEpoch = try XCTUnwrap(disk.peek(BrokerageEpochProbe.self, name: "brokerage-state.json")?.writeEpoch)

        disk.resetIOCounts()
        disk.failReadsAfterSuccesses = ["brokerage-state.json": 2]
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        do {
            try await store.replace(key: "PK-NEW", secret: "SEC-NEW", environment: .paper)
            XCTFail("unreadable epoch must not persist a new state")
        } catch {
            XCTAssertFalse(disk.exists(name: "brokerage-logout.json"))
            XCTAssertEqual(
                try disk.peek(BrokerageEpochProbe.self, name: "brokerage-state.json")?.writeEpoch,
                originalEpoch
            )
            XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r1.key"), "PK-OLD")
        }

        disk.failReadsAfterSuccesses = [:]
        let restored = CurrentBrokerageStore(
            keychain: keychain,
            disk: disk,
            validator: ScriptedBrokerageValidator()
        )
        XCTAssertEqual(restored.current?.id, "acct-1")
        XCTAssertEqual(restored.credentials(for: .paper)?.key, "PK-OLD")
        XCTAssertEqual(
            try disk.peek(BrokerageEpochProbe.self, name: "brokerage-state.json")?.writeEpoch,
            originalEpoch
        )
    }

    func testReplaceAbortsWhenRevisionWouldOverflow() async throws {
        let folder = "MoneyknowsTests-brokerage-\(UUID().uuidString)"
        let keychain = MemoryCredentialStore()
        let disk = DiskStore(folder: folder)
        try keychain.set("PK-OLD", account: "brokerage.acct-1.paper.r\(Int.max).key")
        try keychain.set("SEC-OLD", account: "brokerage.acct-1.paper.r\(Int.max).secret")
        try writeBrokerageState(
            folder: folder,
            json: #"""
            {
              "current": {"id":"acct-1","provider":"alpaca","environment":"paper"},
              "paperAccountId":"acct-1",
              "paperRevision": \#(Int.max),
              "liveRevision":0,
              "pendingAccountIds":[]
            }
            """#
        )
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-OLD")

        do {
            try await store.replace(key: "PK-NEW", secret: "SEC-NEW", environment: .paper)
            XCTFail("revision overflow must abort replace")
        } catch {
            XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r\(Int.max).key"), "PK-OLD")
            XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r\(Int.max).secret"), "SEC-OLD")
            XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-OLD")
        }
    }

    func testClearPersistFailureKeepsCredentials() async throws {
        let keychain = MemoryCredentialStore()
        let disk = ScriptedDiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)
        let generation = store.generation

        disk.failCheckedWrites = true
        do {
            try store.clear(environment: .paper)
            XCTFail("clear persist should fail")
        } catch {
            XCTAssertEqual(store.current?.id, "acct-1")
            XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-OLD")
            XCTAssertEqual(store.credentials(for: .paper)?.secret, "SEC-OLD")
            XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r1.key"), "PK-OLD")
            XCTAssertEqual(store.generation, generation)
        }

        do {
            try store.clearAll()
            XCTFail("clearAll persist should fail")
        } catch {
            XCTAssertNil(store.current)
            XCTAssertNil(store.credentials(for: .paper))
            XCTAssertNil(keychain.string(account: "brokerage.acct-1.paper.r1.key"))
            XCTAssertNil(keychain.string(account: "brokerage.acct-1.paper.r1.secret"))
            XCTAssertGreaterThan(store.generation, generation)
        }
    }

    func testClearEnvironmentVerifyFailureRollsBackState() async throws {
        let keychain = MemoryCredentialStore()
        let disk = ScriptedDiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)
        let generation = store.generation

        disk.failCheckedVerifyOnceNames = ["brokerage-state.json"]
        do {
            try store.clear(environment: .paper)
            XCTFail("clear persist verify should fail")
        } catch {
            XCTAssertEqual(store.current?.id, "acct-1")
            XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-OLD")
            XCTAssertEqual(store.credentials(for: .paper)?.secret, "SEC-OLD")
            XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r1.key"), "PK-OLD")
            XCTAssertEqual(store.generation, generation)
        }
    }

    func testClearEnvironmentVerifyFailureIsolatesWhenRollbackFails() async throws {
        let keychain = MemoryCredentialStore()
        let disk = ScriptedDiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)
        let generation = store.generation

        disk.failCheckedVerifyNames = ["brokerage-state.json"]
        do {
            try store.clear(environment: .paper)
            XCTFail("clear persist verify should fail")
        } catch {
            XCTAssertNil(store.current)
            XCTAssertNil(store.credentials(for: .paper))
            XCTAssertGreaterThan(store.generation, generation)
        }

        disk.failCheckedVerifyNames = []
        store.setForeground(true)
        await waitUntil {
            store.current?.id == "acct-1" && store.credentials(for: .paper)?.key == "PK-OLD"
        }
        XCTAssertEqual(store.credentials(for: .paper)?.secret, "SEC-OLD")
        XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r1.key"), "PK-OLD")
    }

    func testIsolationRecoveryResumesAfterSwitchingBackToOwner() async throws {
        let keychain = MemoryCredentialStore()
        let disk = ScriptedDiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(
            keychain: keychain,
            disk: disk,
            validator: validator,
            clearRetryNanoseconds: 20_000_000
        )
        store.prepareForUser("user-a")
        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)

        disk.failCheckedVerifyNames = ["brokerage-state.json"]
        do {
            try store.clear(environment: .paper)
            XCTFail("clear persist verify should fail")
        } catch {
            XCTAssertNil(store.current)
            XCTAssertNil(store.credentials(for: .paper))
        }

        disk.failCheckedVerifyNames = []
        store.prepareForUser("user-b")
        XCTAssertNil(store.current)
        XCTAssertNil(store.credentials(for: .paper))

        store.prepareForUser("user-a")
        XCTAssertEqual(store.current?.id, "acct-1")
        XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-OLD")
        XCTAssertEqual(store.credentials(for: .paper)?.secret, "SEC-OLD")
    }

    func testPaperAndLiveSameAccountIdUseSeparateSlots() async throws {
        let keychain = MemoryCredentialStore()
        let disk = DiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-same", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        try await store.replace(key: "PK-PAPER", secret: "SEC-PAPER", environment: .paper)
        validator.result = .success(BrokerageAccount(id: "acct-same", provider: "alpaca", environment: .live))
        try await store.replace(key: "PK-LIVE", secret: "SEC-LIVE", environment: .live)

        XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-PAPER")
        XCTAssertEqual(store.credentials(for: .paper)?.secret, "SEC-PAPER")
        XCTAssertEqual(store.credentials(for: .live)?.key, "PK-LIVE")
        XCTAssertEqual(store.credentials(for: .live)?.secret, "SEC-LIVE")
        XCTAssertEqual(keychain.string(account: "brokerage.acct-same.paper.r1.key"), "PK-PAPER")
        XCTAssertEqual(keychain.string(account: "brokerage.acct-same.live.r1.key"), "PK-LIVE")
        XCTAssertNil(keychain.string(account: "brokerage.acct-same.r1.key"))

        try store.clear(environment: .paper)
        XCTAssertNil(store.credentials(for: .paper))
        XCTAssertEqual(store.credentials(for: .live)?.key, "PK-LIVE")
        XCTAssertNil(keychain.string(account: "brokerage.acct-same.paper.r1.key"))
        XCTAssertEqual(keychain.string(account: "brokerage.acct-same.live.r1.key"), "PK-LIVE")
    }

    func testFailedLiveReplaceDoesNotDeletePaperLegacySlot() async throws {
        let folder = "MoneyknowsTests-brokerage-\(UUID().uuidString)"
        let keychain = FailingSecretCredentialStore()
        let disk = ScriptedDiskStore(folder: folder)
        try keychain.set("PK-PAPER", account: "brokerage.acct-1.r1.key")
        try keychain.set("SEC-PAPER", account: "brokerage.acct-1.r1.secret")
        try writeBrokerageState(
            folder: folder,
            json: #"""
            {
              "current": {"id":"acct-1","provider":"alpaca","environment":"paper"},
              "paperAccountId":"acct-1",
              "paperRevision":1,
              "liveRevision":0,
              "pendingAccountIds":[]
            }
            """#
        )
        let validator = ScriptedBrokerageValidator()
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-PAPER")

        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .live))
        disk.failCheckedNames = ["brokerage-state.json"]
        do {
            try await store.replace(key: "PK-LIVE", secret: "SEC-LIVE", environment: .live)
            XCTFail("live persist should fail")
        } catch {
            XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-PAPER")
            XCTAssertEqual(store.credentials(for: .paper)?.secret, "SEC-PAPER")
            XCTAssertEqual(keychain.string(account: "brokerage.acct-1.r1.key"), "PK-PAPER")
            XCTAssertEqual(keychain.string(account: "brokerage.acct-1.r1.secret"), "SEC-PAPER")
            XCTAssertNil(store.credentials(for: .live))
            XCTAssertNil(keychain.string(account: "brokerage.acct-1.live.r1.key"))
            XCTAssertNil(keychain.string(account: "brokerage.acct-1.live.r1.secret"))
        }

        disk.failCheckedNames = []
        keychain.failNextSecretWrite = true
        do {
            try await store.replace(key: "PK-LIVE", secret: "SEC-LIVE", environment: .live)
            XCTFail("live secret write should fail")
        } catch {
            XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-PAPER")
            XCTAssertEqual(keychain.string(account: "brokerage.acct-1.r1.key"), "PK-PAPER")
            XCTAssertEqual(keychain.string(account: "brokerage.acct-1.r1.secret"), "SEC-PAPER")
            XCTAssertNil(store.credentials(for: .live))
            XCTAssertNil(keychain.string(account: "brokerage.acct-1.live.r1.key"))
        }
    }

    func testFailedReplacePersistsPendingDeleteWhenRollbackDeleteFails() async throws {
        let keychain = StickyCredentialStore()
        let disk = ScriptedDiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(
            keychain: keychain,
            disk: disk,
            validator: validator,
            clearRetryNanoseconds: 20_000_000
        )
        store.setForeground(true)
        disk.failCheckedNames = ["brokerage-state.json"]
        keychain.failDeletes = true
        do {
            try await store.replace(key: "PK-NEW", secret: "SEC-NEW", environment: .paper)
            XCTFail("state persist should fail")
        } catch {
            XCTAssertNil(store.current)
            XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r1.key"), "PK-NEW")
            XCTAssertTrue(disk.exists(name: "brokerage-pending-deletes.json"))
        }

        disk.failCheckedNames = []
        keychain.failDeletes = false
        await waitUntil {
            keychain.string(account: "brokerage.acct-1.paper.r1.key") == nil
                && keychain.string(account: "brokerage.acct-1.paper.r1.secret") == nil
        }
        XCTAssertNil(store.current)
        XCTAssertFalse(disk.exists(name: "brokerage-pending-deletes.json"))
    }

    func testReconcileDoesNotPublishOtherOwnersAccount() throws {
        let folder = "MoneyknowsTests-brokerage-\(UUID().uuidString)"
        let keychain = MemoryCredentialStore()
        let disk = DiskStore(folder: folder)
        try keychain.set("PK-A", account: "brokerage.acct-1.paper.r1.key")
        try keychain.set("SEC-A", account: "brokerage.acct-1.paper.r1.secret")
        try writeBrokerageState(
            folder: folder,
            json: #"""
            {
              "current": {"id":"acct-1","provider":"alpaca","environment":"paper"},
              "paperAccountId":"acct-1",
              "paperRevision":1,
              "liveRevision":0,
              "pendingAccountIds":["acct-orphan"],
              "ownerUserId":"user-a"
            }
            """#
        )
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: ScriptedBrokerageValidator())
        store.prepareForUser("user-b")
        XCTAssertNil(store.current)
        let generation = store.generation
        store.setForeground(true)
        XCTAssertNil(store.current)
        XCTAssertNil(store.credentials(for: .paper))
        XCTAssertEqual(store.generation, generation)
    }

    func testLegacyReferenceCheckDoesNotTreatExistsFailureAsMissing() async throws {
        let folder = "MoneyknowsTests-brokerage-\(UUID().uuidString)"
        let keychain = FailingSecretCredentialStore()
        let disk = ScriptedDiskStore(folder: folder)
        try keychain.set("PK-PAPER", account: "brokerage.acct-1.r1.key")
        try keychain.set("SEC-PAPER", account: "brokerage.acct-1.r1.secret")
        try writeBrokerageState(
            folder: folder,
            json: #"""
            {
              "current": {"id":"acct-1","provider":"alpaca","environment":"paper"},
              "paperAccountId":"acct-1",
              "paperRevision":1,
              "liveRevision":0,
              "pendingAccountIds":[]
            }
            """#
        )
        let validator = ScriptedBrokerageValidator()
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-PAPER")

        disk.failExists = true
        disk.failCheckedNames = ["brokerage-state.json"]
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .live))
        do {
            try await store.replace(key: "PK-LIVE", secret: "SEC-LIVE", environment: .live)
            XCTFail("live persist should fail")
        } catch {
            XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-PAPER")
            XCTAssertEqual(keychain.string(account: "brokerage.acct-1.r1.key"), "PK-PAPER")
            XCTAssertEqual(keychain.string(account: "brokerage.acct-1.r1.secret"), "SEC-PAPER")
        }
    }

    func testClearEnvironmentKeychainDeleteFailureRetries() async throws {
        let keychain = StickyCredentialStore()
        let disk = DiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-paper", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(
            keychain: keychain,
            disk: disk,
            validator: validator,
            clearRetryNanoseconds: 20_000_000
        )
        store.setForeground(true)
        try await store.replace(key: "PK-PAPER", secret: "SEC-PAPER", environment: .paper)
        validator.result = .success(BrokerageAccount(id: "acct-live", provider: "alpaca", environment: .live))
        try await store.replace(key: "PK-LIVE", secret: "SEC-LIVE", environment: .live)
        XCTAssertEqual(store.current?.id, "acct-live")

        keychain.failDeletes = true
        do {
            try store.clear(environment: .paper)
            XCTFail("keychain delete should fail")
        } catch {
            XCTAssertNil(store.credentials(for: .paper))
            XCTAssertEqual(store.current?.id, "acct-live")
            XCTAssertEqual(store.credentials(for: .live)?.key, "PK-LIVE")
            XCTAssertEqual(keychain.string(account: "brokerage.acct-paper.paper.r1.key"), "PK-PAPER")
            XCTAssertEqual(keychain.string(account: "brokerage.acct-paper.paper.r1.secret"), "SEC-PAPER")
            XCTAssertEqual(keychain.string(account: "brokerage.acct-live.live.r1.key"), "PK-LIVE")
        }

        keychain.failDeletes = false
        await waitUntil {
            keychain.string(account: "brokerage.acct-paper.paper.r1.key") == nil
                && keychain.string(account: "brokerage.acct-paper.paper.r1.secret") == nil
        }
        XCTAssertNil(store.credentials(for: .paper))
        XCTAssertEqual(store.current?.id, "acct-live")
        XCTAssertEqual(store.credentials(for: .live)?.key, "PK-LIVE")
        XCTAssertEqual(keychain.string(account: "brokerage.acct-live.live.r1.key"), "PK-LIVE")
        XCTAssertEqual(keychain.string(account: "brokerage.acct-live.live.r1.secret"), "SEC-LIVE")
    }

    func testClearEnvironmentIsRejectedWhileLogoutTombstoneExists() async throws {
        let keychain = MemoryCredentialStore()
        let disk = ScriptedDiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-paper", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(
            keychain: keychain,
            disk: disk,
            validator: validator,
            clearRetryNanoseconds: 60_000_000_000
        )
        try await store.replace(key: "PK-PAPER", secret: "SEC-PAPER", environment: .paper)
        validator.result = .success(BrokerageAccount(id: "acct-live", provider: "alpaca", environment: .live))
        try await store.replace(key: "PK-LIVE", secret: "SEC-LIVE", environment: .live)
        let generation = store.generation

        disk.failCheckedNames = ["brokerage-state.json"]
        do {
            try store.clearAll()
            XCTFail("empty state persist should fail")
        } catch {
            XCTAssertNil(store.current)
            XCTAssertTrue(disk.exists(name: "brokerage-logout.json"))
        }

        disk.failCheckedNames = []
        do {
            try store.clear(environment: .paper)
            XCTFail("clear during logout isolation must be rejected")
        } catch {
            XCTAssertEqual(error as? AppError, .cancelled)
            XCTAssertNil(store.current)
            XCTAssertNil(store.credentials(for: .paper))
            XCTAssertNil(store.credentials(for: .live))
            XCTAssertEqual(store.generation, generation + 1)
            XCTAssertTrue(disk.exists(name: "brokerage-logout.json"))
        }

        let restored = CurrentBrokerageStore(
            keychain: keychain,
            disk: disk,
            validator: ScriptedBrokerageValidator()
        )
        XCTAssertNil(restored.current)
        XCTAssertNil(restored.credentials(for: .paper))
        XCTAssertNil(restored.credentials(for: .live))
    }

    func testClearAllPersistFailureRetriesWhenDiskRecovers() async throws {
        let keychain = MemoryCredentialStore()
        let disk = ScriptedDiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(
            keychain: keychain,
            disk: disk,
            validator: validator,
            clearRetryNanoseconds: 20_000_000
        )
        store.setForeground(true)
        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)

        disk.failCheckedWrites = true
        do {
            try store.clearAll()
            XCTFail("clearAll persist should fail")
        } catch {
            XCTAssertNil(store.current)
            XCTAssertNil(store.credentials(for: .paper))
        }

        disk.failCheckedWrites = false
        await waitUntil {
            let probe = CurrentBrokerageStore(
                keychain: keychain,
                disk: disk,
                validator: ScriptedBrokerageValidator()
            )
            return probe.current == nil
        }
        XCTAssertNil(store.current)
        XCTAssertNil(store.credentials(for: .paper))
    }

    func testPersistRetryPausesInBackground() async throws {
        let keychain = MemoryCredentialStore()
        let disk = ScriptedDiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(
            keychain: keychain,
            disk: disk,
            validator: validator,
            clearRetryNanoseconds: 20_000_000
        )
        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)

        disk.failCheckedNames = ["brokerage-state.json"]
        do {
            try store.clearAll()
            XCTFail("clearAll persist should fail")
        } catch {
            XCTAssertTrue(disk.exists(name: "brokerage-logout.json"))
        }

        disk.failCheckedNames = []
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertTrue(disk.exists(name: "brokerage-logout.json"))

        store.setForeground(true)
        await waitUntil { !disk.exists(name: "brokerage-logout.json") }
        XCTAssertNil(store.current)
        XCTAssertNil(store.credentials(for: .paper))
    }

    func testPendingDeletesSurviveEmptyLogoutAndNewReplace() async throws {
        let keychain = StickyCredentialStore()
        let disk = DiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-old", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)

        keychain.failDeletes = true
        do {
            try store.clearAll()
            XCTFail("keychain wipe should fail")
        } catch {
            XCTAssertNil(store.current)
            XCTAssertTrue(disk.exists(name: "brokerage-pending-deletes.json"))
            XCTAssertEqual(keychain.string(account: "brokerage.acct-old.paper.r1.key"), "PK-OLD")
        }

        keychain.failDeletes = false
        validator.result = .success(BrokerageAccount(id: "acct-new", provider: "alpaca", environment: .paper))
        try await store.replace(key: "PK-NEW", secret: "SEC-NEW", environment: .paper)
        XCTAssertEqual(store.current?.id, "acct-new")
        XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-NEW")
        XCTAssertNil(keychain.string(account: "brokerage.acct-old.paper.r1.key"))
        XCTAssertNil(keychain.string(account: "brokerage.acct-old.paper.r1.secret"))
        XCTAssertFalse(disk.exists(name: "brokerage-pending-deletes.json"))
    }

    func testClearEnvironmentPendingDeletesSurviveRestartWithoutEnumeration() async throws {
        let keychain = StickyCredentialStore()
        let disk = DiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-paper", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        try await store.replace(key: "PK-PAPER", secret: "SEC-PAPER", environment: .paper)
        validator.result = .success(BrokerageAccount(id: "acct-live", provider: "alpaca", environment: .live))
        try await store.replace(key: "PK-LIVE", secret: "SEC-LIVE", environment: .live)

        keychain.failDeletes = true
        do {
            try store.clear(environment: .paper)
            XCTFail("keychain delete should fail")
        } catch {
            XCTAssertTrue(disk.exists(name: "brokerage-pending-deletes.json"))
            XCTAssertEqual(keychain.string(account: "brokerage.acct-paper.paper.r1.key"), "PK-PAPER")
            XCTAssertEqual(keychain.string(account: "brokerage.acct-live.live.r1.key"), "PK-LIVE")
        }

        keychain.failDeletes = false
        keychain.failAccounts = true
        let restored = CurrentBrokerageStore(
            keychain: keychain,
            disk: disk,
            validator: ScriptedBrokerageValidator()
        )
        XCTAssertEqual(keychain.string(account: "brokerage.acct-paper.paper.r1.key"), "PK-PAPER")
        restored.setForeground(true)
        await waitUntil {
            keychain.string(account: "brokerage.acct-paper.paper.r1.key") == nil
                && keychain.string(account: "brokerage.acct-paper.paper.r1.secret") == nil
        }
        XCTAssertNil(restored.credentials(for: .paper))
        XCTAssertEqual(restored.credentials(for: .live)?.key, "PK-LIVE")
        XCTAssertEqual(keychain.string(account: "brokerage.acct-live.live.r1.key"), "PK-LIVE")
        XCTAssertFalse(disk.exists(name: "brokerage-pending-deletes.json"))
    }

    func testCorruptPendingDeletesDoesNotDropCleanupWhenKeychainUnreadable() async throws {
        let keychain = StickyCredentialStore()
        let folder = "MoneyknowsTests-brokerage-\(UUID().uuidString)"
        let disk = DiskStore(folder: folder)
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(
            keychain: keychain,
            disk: disk,
            validator: validator,
            clearRetryNanoseconds: 20_000_000
        )
        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)
        try keychain.set("PK-ORPHAN", account: "brokerage.acct-1.paper.r2.key")
        try keychain.set("SEC-ORPHAN", account: "brokerage.acct-1.paper.r2.secret")
        try writeBrokeragePendingDeletes(folder: folder, json: "{")

        let restored = CurrentBrokerageStore(
            keychain: keychain,
            disk: disk,
            validator: ScriptedBrokerageValidator(),
            clearRetryNanoseconds: 20_000_000
        )
        keychain.failAccounts = true
        restored.setForeground(true)
        try await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r2.key"), "PK-ORPHAN")
        XCTAssertTrue(disk.exists(name: "brokerage-pending-deletes.json"))

        keychain.failAccounts = false
        await waitUntil {
            keychain.string(account: "brokerage.acct-1.paper.r2.key") == nil
                && keychain.string(account: "brokerage.acct-1.paper.r2.secret") == nil
        }
        XCTAssertEqual(restored.credentials(for: .paper)?.key, "PK-OLD")
        XCTAssertFalse(disk.exists(name: "brokerage-pending-deletes.json"))
    }

    func testUnreadableStateDoesNotDeleteCredentials() async throws {
        let keychain = MemoryCredentialStore()
        let disk = ScriptedDiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)

        disk.failReads = true
        let restored = CurrentBrokerageStore(
            keychain: keychain,
            disk: disk,
            validator: ScriptedBrokerageValidator()
        )
        XCTAssertNil(restored.current)
        XCTAssertNil(restored.credentials(for: .paper))
        XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r1.key"), "PK-OLD")
        XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r1.secret"), "SEC-OLD")
    }

    func testCorruptStateFileDoesNotDeleteCredentials() async throws {
        let folder = "MoneyknowsTests-brokerage-\(UUID().uuidString)"
        let keychain = MemoryCredentialStore()
        let disk = DiskStore(folder: folder)
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)

        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = base.appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent("brokerage-state.json")
        try Data("{".utf8).write(to: url)

        let restored = CurrentBrokerageStore(
            keychain: keychain,
            disk: disk,
            validator: ScriptedBrokerageValidator()
        )
        XCTAssertNil(restored.current)
        XCTAssertNil(restored.credentials(for: .paper))
        XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r1.key"), "PK-OLD")
        XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r1.secret"), "SEC-OLD")
    }

    func testLogoutTombstoneBlocksRestoreWhenStatePersistFails() async throws {
        let keychain = MemoryCredentialStore()
        let disk = ScriptedDiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)

        disk.failCheckedNames = ["brokerage-state.json"]
        do {
            try store.clearAll()
            XCTFail("empty state persist should fail")
        } catch {
            XCTAssertNil(store.current)
            XCTAssertNil(store.credentials(for: .paper))
        }

        let restored = CurrentBrokerageStore(
            keychain: keychain,
            disk: disk,
            validator: ScriptedBrokerageValidator()
        )
        XCTAssertNil(restored.current)
        XCTAssertNil(restored.credentials(for: .paper))
        XCTAssertTrue(disk.exists(name: "brokerage-logout.json"))
    }

    func testKeychainDeleteFailureStillIsolatesAfterTombstone() async throws {
        let keychain = StickyCredentialStore()
        let disk = DiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)

        keychain.failDeletes = true
        do {
            try store.clearAll()
            XCTFail("keychain wipe should fail")
        } catch {
            XCTAssertNil(store.current)
            XCTAssertNil(store.credentials(for: .paper))
            XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r1.key"), "PK-OLD")
        }

        let restored = CurrentBrokerageStore(
            keychain: keychain,
            disk: disk,
            validator: ScriptedBrokerageValidator()
        )
        XCTAssertNil(restored.current)
        XCTAssertNil(restored.credentials(for: .paper))
        XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r1.key"), "PK-OLD")
    }

    func testOwnerMismatchDoesNotExposePreviousUserAccount() async throws {
        let keychain = MemoryCredentialStore()
        let disk = DiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        store.prepareForUser("user-a")
        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)
        XCTAssertEqual(store.current?.id, "acct-1")

        let other = CurrentBrokerageStore(
            keychain: keychain,
            disk: disk,
            validator: ScriptedBrokerageValidator()
        )
        other.prepareForUser("user-b")
        XCTAssertNil(other.current)
        XCTAssertNil(other.credentials(for: .paper))
        XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r1.key"), "PK-OLD")

        other.prepareForUser("user-a")
        XCTAssertEqual(other.current?.id, "acct-1")
        XCTAssertEqual(other.credentials(for: .paper)?.key, "PK-OLD")
    }

    func testClearEnvironmentIsRejectedForMismatchedOwner() async throws {
        let keychain = MemoryCredentialStore()
        let disk = DiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-paper", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        store.prepareForUser("user-a")
        try await store.replace(key: "PK-PAPER", secret: "SEC-PAPER", environment: .paper)
        validator.result = .success(BrokerageAccount(id: "acct-live", provider: "alpaca", environment: .live))
        try await store.replace(key: "PK-LIVE", secret: "SEC-LIVE", environment: .live)

        let other = CurrentBrokerageStore(
            keychain: keychain,
            disk: disk,
            validator: ScriptedBrokerageValidator()
        )
        other.prepareForUser("user-b")
        do {
            try other.clear(environment: .paper)
            XCTFail("mismatched owner must not clear previous user state")
        } catch {
            XCTAssertEqual(error as? AppError, .cancelled)
        }
        XCTAssertNil(other.current)
        XCTAssertEqual(keychain.string(account: "brokerage.acct-paper.paper.r1.key"), "PK-PAPER")
        XCTAssertEqual(keychain.string(account: "brokerage.acct-live.live.r1.key"), "PK-LIVE")

        let restored = CurrentBrokerageStore(
            keychain: keychain,
            disk: disk,
            validator: ScriptedBrokerageValidator()
        )
        restored.prepareForUser("user-a")
        XCTAssertEqual(restored.current?.id, "acct-live")
        XCTAssertEqual(restored.credentials(for: .paper)?.key, "PK-PAPER")
        XCTAssertEqual(restored.credentials(for: .live)?.key, "PK-LIVE")
    }

    func testUnboundOwnerStaysUnavailableUntilBindPersists() async throws {
        let keychain = MemoryCredentialStore()
        let disk = ScriptedDiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)
        XCTAssertEqual(store.current?.id, "acct-1")

        disk.failCheckedWrites = true
        store.prepareForUser("user-a")
        XCTAssertNil(store.current)
        XCTAssertNil(store.credentials(for: .paper))
        XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r1.key"), "PK-OLD")

        disk.failCheckedWrites = false
        store.prepareForUser("user-a")
        XCTAssertEqual(store.current?.id, "acct-1")
        XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-OLD")
    }

    func testReplaceKeepsNewCredentialsWhenTombstoneDeleteFails() async throws {
        let keychain = MemoryCredentialStore()
        let disk = ScriptedDiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(
            keychain: keychain,
            disk: disk,
            validator: validator,
            clearRetryNanoseconds: 20_000_000
        )
        store.setForeground(true)
        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)

        disk.failCheckedNames = ["brokerage-state.json"]
        do {
            try store.clearAll()
            XCTFail("empty state persist should fail")
        } catch {
            XCTAssertNil(store.current)
        }

        disk.failCheckedNames = []
        disk.failDeleteNames = ["brokerage-logout.json"]
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        do {
            try await store.replace(key: "PK-NEW", secret: "SEC-NEW", environment: .paper)
            XCTFail("tombstone delete should fail")
        } catch {
            XCTAssertEqual(store.current?.id, "acct-1")
            XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-NEW")
            XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r2.key"), "PK-NEW")
        }

        let restored = CurrentBrokerageStore(
            keychain: keychain,
            disk: disk,
            validator: ScriptedBrokerageValidator()
        )
        XCTAssertEqual(restored.current?.id, "acct-1")
        XCTAssertEqual(restored.credentials(for: .paper)?.key, "PK-NEW")

        disk.failDeleteNames = []
        await waitUntil { !disk.exists(name: "brokerage-logout.json") }
        XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-NEW")
        XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r2.key"), "PK-NEW")
        XCTAssertNil(keychain.string(account: "brokerage.acct-1.paper.r1.key"))
    }

    func testIsolatedReplaceDoesNotReuseLeftoverRevision() async throws {
        let keychain = StickyCredentialStore()
        let disk = ScriptedDiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)
        XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r1.key"), "PK-OLD")

        keychain.failDeletes = true
        disk.failCheckedNames = ["brokerage-state.json"]
        do {
            try store.clearAll()
            XCTFail("empty state persist should fail")
        } catch {
            XCTAssertNil(store.current)
            XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r1.key"), "PK-OLD")
            XCTAssertTrue(disk.exists(name: "brokerage-logout.json"))
        }

        disk.failCheckedNames = []
        keychain.failDeletes = false
        keychain.failNextSecretWrite = true
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        do {
            try await store.replace(key: "PK-NEW", secret: "SEC-NEW", environment: .paper)
            XCTFail("secret write should fail")
        } catch {
            XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r1.key"), "PK-OLD")
            XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r1.secret"), "SEC-OLD")
            XCTAssertNil(keychain.string(account: "brokerage.acct-1.paper.r2.key"))
            XCTAssertNil(keychain.string(account: "brokerage.acct-1.paper.r2.secret"))
            XCTAssertNil(store.credentials(for: .paper))
        }
    }

    func testReplaceDuringTombstoneDeletesLeftoverCredentials() async throws {
        let keychain = StickyCredentialStore()
        let disk = ScriptedDiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-paper", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        try await store.replace(key: "PK-PAPER", secret: "SEC-PAPER", environment: .paper)
        validator.result = .success(BrokerageAccount(id: "acct-live", provider: "alpaca", environment: .live))
        try await store.replace(key: "PK-LIVE", secret: "SEC-LIVE", environment: .live)

        keychain.failDeletes = true
        disk.failCheckedNames = ["brokerage-state.json"]
        do {
            try store.clearAll()
            XCTFail("logout wipe should fail")
        } catch {
            XCTAssertNil(store.current)
            XCTAssertEqual(keychain.string(account: "brokerage.acct-paper.paper.r1.key"), "PK-PAPER")
            XCTAssertEqual(keychain.string(account: "brokerage.acct-live.live.r1.key"), "PK-LIVE")
            XCTAssertTrue(disk.exists(name: "brokerage-logout.json"))
        }

        keychain.failDeletes = false
        disk.failCheckedNames = []
        validator.result = .success(BrokerageAccount(id: "acct-new", provider: "alpaca", environment: .paper))
        try await store.replace(key: "PK-NEW", secret: "SEC-NEW", environment: .paper)

        XCTAssertEqual(store.current?.id, "acct-new")
        XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-NEW")
        XCTAssertNil(store.credentials(for: .live))
        XCTAssertEqual(keychain.string(account: "brokerage.acct-new.paper.r1.key"), "PK-NEW")
        XCTAssertEqual(keychain.string(account: "brokerage.acct-new.paper.r1.secret"), "SEC-NEW")
        XCTAssertNil(keychain.string(account: "brokerage.acct-paper.paper.r1.key"))
        XCTAssertNil(keychain.string(account: "brokerage.acct-paper.paper.r1.secret"))
        XCTAssertNil(keychain.string(account: "brokerage.acct-live.live.r1.key"))
        XCTAssertNil(keychain.string(account: "brokerage.acct-live.live.r1.secret"))
        XCTAssertFalse(disk.exists(name: "brokerage-logout.json"))
    }

    func testLogoutDeletesReferencedSlotsWhenAccountsEnumerationFails() async throws {
        let keychain = FailingAccountsCredentialStore()
        let disk = DiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)

        keychain.failAccounts = true
        do {
            try store.clearAll()
            XCTFail("accounts enumeration should fail closed")
        } catch {
            XCTAssertNil(store.current)
            XCTAssertNil(store.credentials(for: .paper))
            XCTAssertNil(keychain.string(account: "brokerage.acct-1.paper.r1.key"))
            XCTAssertNil(keychain.string(account: "brokerage.acct-1.paper.r1.secret"))
            XCTAssertTrue(disk.exists(name: "brokerage-logout.json"))
        }
    }

    func testInconsistentAccountIdsFailClosedWithoutDeletingCredentials() throws {
        let folder = "MoneyknowsTests-brokerage-\(UUID().uuidString)"
        let keychain = MemoryCredentialStore()
        let disk = DiskStore(folder: folder)
        try keychain.set("PK-A", account: "brokerage.acct-A.r1.key")
        try keychain.set("SEC-A", account: "brokerage.acct-A.r1.secret")
        try keychain.set("PK-B", account: "brokerage.acct-B.r1.key")
        try keychain.set("SEC-B", account: "brokerage.acct-B.r1.secret")
        try writeBrokerageState(
            folder: folder,
            json: #"""
            {
              "current": {"id":"acct-A","provider":"alpaca","environment":"paper"},
              "paperAccountId":"acct-B",
              "paperRevision":1,
              "liveRevision":0,
              "pendingAccountIds":[]
            }
            """#
        )

        let store = CurrentBrokerageStore(
            keychain: keychain,
            disk: disk,
            validator: ScriptedBrokerageValidator()
        )
        XCTAssertNil(store.current)
        XCTAssertNil(store.credentials(for: .paper))
        XCTAssertEqual(keychain.string(account: "brokerage.acct-A.r1.key"), "PK-A")
        XCTAssertEqual(keychain.string(account: "brokerage.acct-B.r1.key"), "PK-B")
    }

    func testMismatchedProviderFailsClosed() throws {
        let folder = "MoneyknowsTests-brokerage-\(UUID().uuidString)"
        let keychain = MemoryCredentialStore()
        let disk = DiskStore(folder: folder)
        try keychain.set("PK", account: "brokerage.acct-1.paper.r1.key")
        try keychain.set("SEC", account: "brokerage.acct-1.paper.r1.secret")
        try writeBrokerageState(
            folder: folder,
            json: #"""
            {
              "current": {"id":"acct-1","provider":"schwab","environment":"paper"},
              "paperAccountId":"acct-1",
              "paperRevision":1,
              "liveRevision":0,
              "pendingAccountIds":[]
            }
            """#
        )
        let store = CurrentBrokerageStore(
            keychain: keychain,
            disk: disk,
            validator: ScriptedBrokerageValidator()
        )
        XCTAssertNil(store.current)
        XCTAssertNil(store.credentials(for: .paper))
        XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r1.key"), "PK")
    }

    func testInitDiscardsIncompleteNewRevisionAndKeepsLivePair() async throws {
        let keychain = MemoryCredentialStore()
        let disk = DiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)

        try keychain.set("PK-NEW", account: "brokerage.acct-1.paper.r2.key")

        let restored = CurrentBrokerageStore(
            keychain: keychain,
            disk: disk,
            validator: ScriptedBrokerageValidator()
        )
        XCTAssertEqual(restored.credentials(for: .paper)?.key, "PK-OLD")
        XCTAssertEqual(restored.credentials(for: .paper)?.secret, "SEC-OLD")
        XCTAssertEqual(keychain.string(account: "brokerage.acct-1.paper.r2.key"), "PK-NEW")
        restored.setForeground(true)
        XCTAssertEqual(restored.credentials(for: .paper)?.key, "PK-OLD")
        XCTAssertEqual(restored.credentials(for: .paper)?.secret, "SEC-OLD")
        XCTAssertNil(keychain.string(account: "brokerage.acct-1.paper.r2.key"))
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
        XCTAssertEqual(keychain.string(account: "brokerage.acct-new.key.pending"), "PK-NEW")
        XCTAssertEqual(keychain.string(account: "brokerage.acct-new.key"), "PK-NEW")
        store.setForeground(true)
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

        try store.clearAll()

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
        XCTAssertEqual(keychain.string(account: "brokerage.acct-1.key.pending"), "PK-NEW")
        restored.setForeground(true)
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

        try store.clearAll()
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
        XCTAssertNil(keychain.string(account: "brokerage.acct-late.paper.r1.key"))
        XCTAssertNil(keychain.string(account: "brokerage.acct-late.paper.r1.secret"))
        XCTAssertTrue(keychain.accounts().isEmpty)
    }

    func testSuccessfulReplacePublishesGenerationOnce() async throws {
        let keychain = MemoryCredentialStore()
        let disk = DiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        let before = store.generation

        try await store.replace(key: "PK", secret: "SEC", environment: .paper)
        XCTAssertEqual(store.generation, before + 1)

        try await store.replace(key: "PK-2", secret: "SEC-2", environment: .paper)
        XCTAssertEqual(store.generation, before + 2)
    }

    func testFailedReplaceDoesNotPublishGeneration() async throws {
        let keychain = MemoryCredentialStore()
        let disk = DiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)
        let afterSuccess = store.generation

        validator.result = .failure(AppError.http(status: 401, message: "invalid", errorCode: nil))
        do {
            try await store.replace(key: "PK-NEW", secret: "SEC-NEW", environment: .paper)
            XCTFail("replace should fail")
        } catch {
            XCTAssertEqual(store.generation, afterSuccess)
        }
    }

    func testSecretWriteFailureDoesNotPublishGeneration() async throws {
        let keychain = FailingSecretCredentialStore()
        let disk = DiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = ScriptedBrokerageValidator()
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)
        try await store.replace(key: "PK-OLD", secret: "SEC-OLD", environment: .paper)
        let afterSuccess = store.generation

        keychain.failNextSecretWrite = true
        validator.result = .success(BrokerageAccount(id: "acct-1", provider: "alpaca", environment: .paper))
        do {
            try await store.replace(key: "PK-NEW", secret: "SEC-NEW", environment: .paper)
            XCTFail("secret write should fail")
        } catch {
            XCTAssertEqual(store.generation, afterSuccess)
        }
    }

    func testOverlappingReplaceDoesNotRollbackNewerAccount() async throws {
        let keychain = MemoryCredentialStore()
        let disk = DiskStore(folder: "MoneyknowsTests-brokerage-\(UUID().uuidString)")
        let validator = MultiGateValidator()
        let store = CurrentBrokerageStore(keychain: keychain, disk: disk, validator: validator)

        let first = Task {
            try await store.replace(key: "PK-A", secret: "SEC-A", environment: .paper)
        }
        await waitUntil { validator.waitingCount == 1 }

        let second = Task {
            try await store.replace(key: "PK-B", secret: "SEC-B", environment: .paper)
        }
        await waitUntil { validator.waitingCount == 2 }

        validator.finish(
            1,
            .success(BrokerageAccount(id: "acct-B", provider: "alpaca", environment: .paper))
        )
        try await second.value
        XCTAssertEqual(store.current?.id, "acct-B")
        XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-B")
        let generation = store.generation

        validator.finish(0, .failure(AppError.network))
        do {
            try await first.value
            XCTFail("stale replace must not succeed")
        } catch {
            XCTAssertEqual(error as? AppError, .cancelled)
        }

        XCTAssertEqual(store.current?.id, "acct-B")
        XCTAssertEqual(store.credentials(for: .paper)?.key, "PK-B")
        XCTAssertEqual(store.credentials(for: .paper)?.secret, "SEC-B")
        XCTAssertEqual(store.generation, generation)
    }
}

private struct BrokerageStateProbe: Codable {
    var pendingAccountIds: [String]?
    var writeEpoch: UInt64?
}

private struct BrokerageEpochProbe: Codable {
    var writeEpoch: UInt64?
}

private func writeBrokerageState(folder: String, json: String) throws {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
    let directory = base.appendingPathComponent(folder, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data(json.utf8).write(to: directory.appendingPathComponent("brokerage-state.json"))
}

private func writeBrokeragePendingDeletes(folder: String, json: String) throws {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
    let directory = base.appendingPathComponent(folder, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data(json.utf8).write(to: directory.appendingPathComponent("brokerage-pending-deletes.json"))
}

private final class FailingAccountsCredentialStore: CredentialStoring {
    var failAccounts = false
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

    func accounts() throws -> [String] {
        if failAccounts {
            throw AppError.decoding
        }
        return Array(values.keys)
    }
}

private final class StickyCredentialStore: CredentialStoring {
    var failDeletes = false
    var failAccounts = false
    var failNextSecretWrite = false
    var failStringReads = false
    private var values: [String: String] = [:]

    func set(_ value: String, account: String) throws {
        if failNextSecretWrite, account.hasSuffix(".secret") {
            failNextSecretWrite = false
            throw AppError.decoding
        }
        values[account] = value
    }

    func string(account: String) -> String? {
        if failStringReads {
            return nil
        }
        return values[account]
    }

    func stringIfPresent(account: String) throws -> String? {
        if failStringReads {
            throw AppError.decoding
        }
        return values[account]
    }

    func delete(account: String) {
        guard !failDeletes else { return }
        values.removeValue(forKey: account)
    }

    func accounts() throws -> [String] {
        if failAccounts {
            throw AppError.decoding
        }
        return Array(values.keys)
    }
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

private final class ScriptedDiskStore: DiskStoring {
    var failCheckedWrites = false
    var failCheckedNames: Set<String> = []
    var failCheckedVerifyOnceNames: Set<String> = []
    var failCheckedVerifyNames: Set<String> = []
    var failCheckedAfterSuccesses: [String: Int] = [:]
    var failDeleteNames: Set<String> = []
    var failReads = false
    var failReadsAfterSuccesses: [String: Int] = [:]
    var failExists = false
    var readSuccesses: [String: Int] = [:]
    var checkedWriteSuccesses: [String: Int] = [:]
    private let inner: DiskStore

    init(folder: String) {
        inner = DiskStore(folder: folder)
    }

    func resetIOCounts() {
        readSuccesses = [:]
        checkedWriteSuccesses = [:]
    }

    func peek<T: Decodable>(_ type: T.Type, name: String) throws -> T? {
        try inner.readIfPresent(type, name: name)
    }

    func write<T: Encodable>(_ value: T, name: String) {
        inner.write(value, name: name)
    }

    func writeChecked<T: Codable & Equatable>(_ value: T, name: String) throws {
        if failCheckedWrites || failCheckedNames.contains(name) {
            throw AppError.decoding
        }
        if failCheckedVerifyOnceNames.contains(name) {
            failCheckedVerifyOnceNames.remove(name)
            inner.write(value, name: name)
            throw AppError.decoding
        }
        if failCheckedVerifyNames.contains(name) {
            inner.write(value, name: name)
            throw AppError.decoding
        }
        if let limit = failCheckedAfterSuccesses[name], checkedWriteSuccesses[name, default: 0] >= limit {
            throw AppError.decoding
        }
        try inner.writeChecked(value, name: name)
        checkedWriteSuccesses[name, default: 0] += 1
    }

    func read<T: Decodable>(_ type: T.Type, name: String) -> T? {
        try? readIfPresent(type, name: name)
    }

    func readIfPresent<T: Decodable>(_ type: T.Type, name: String) throws -> T? {
        if failReads {
            throw AppError.decoding
        }
        if let limit = failReadsAfterSuccesses[name], readSuccesses[name, default: 0] >= limit {
            throw AppError.decoding
        }
        let value = try inner.readIfPresent(type, name: name)
        readSuccesses[name, default: 0] += 1
        return value
    }

    func exists(name: String) -> Bool {
        if failExists { return false }
        return inner.exists(name: name)
    }

    func delete(name: String) {
        if failDeleteNames.contains(name) { return }
        inner.delete(name: name)
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

@MainActor
private final class MultiGateValidator: BrokerageAccountValidating {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var results: [Int: Result<BrokerageAccount, Error>] = [:]

    var waitingCount: Int { waiters.count }

    func validate(key: String, secret: String, environment: BrokerageEnvironment) async throws -> BrokerageAccount {
        let index = waiters.count
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        return try results[index]!.get()
    }

    func finish(_ index: Int, _ result: Result<BrokerageAccount, Error>) {
        results[index] = result
        waiters[index].resume()
    }
}
