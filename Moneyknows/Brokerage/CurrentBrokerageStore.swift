import Foundation

@MainActor
final class CurrentBrokerageStore: ObservableObject {
    @Published private(set) var current: BrokerageAccount?

    private let keychain: CredentialStoring
    private let disk: DiskStore
    private let validator: BrokerageAccountValidating
    private let stateFile = "brokerage-state.json"
    private var epoch: UInt64 = 0

    init(
        keychain: CredentialStoring = KeychainStore(service: "com.byteknows.moneyknows.brokerage"),
        disk: DiskStore = DiskStore(),
        validator: BrokerageAccountValidating = AlpacaAccountValidator()
    ) {
        self.keychain = keychain
        self.disk = disk
        self.validator = validator
        discardUnresolvedWrites()
        current = loadState().current
    }

    func credentials(for environment: BrokerageEnvironment) -> (key: String, secret: String)? {
        guard let id = accountId(for: environment),
              let key = keychain.string(account: Self.keyAccount(id)),
              let secret = keychain.string(account: Self.secretAccount(id)),
              !key.isEmpty,
              !secret.isEmpty
        else {
            return nil
        }
        return (key, secret)
    }

    func replace(key: String, secret: String, environment: BrokerageEnvironment) async throws {
        let epoch = self.epoch
        let previous = loadState()
        do {
            let account = try await validator.validate(key: key, secret: secret, environment: environment)
            guard self.epoch == epoch else {
                throw AppError.cancelled
            }
            try writeCredentials(id: account.id, key: key, secret: secret)

            var next = loadState()
            next.current = account
            switch environment {
            case .paper:
                next.paperAccountId = account.id
            case .live:
                next.liveAccountId = account.id
            }
            next.pendingAccountIds.removeAll { $0 == account.id }
            save(next)
            removeOrphanedCredentials(previous: previous, next: next)
            AppLog.brokerage.info("replaced brokerage account \(environment.rawValue, privacy: .public)")
        } catch {
            if self.epoch == epoch {
                save(previous)
                current = previous.current
                AppLog.brokerage.error("brokerage replace failed \(environment.rawValue, privacy: .public)")
            }
            throw error
        }
    }

    func clear(environment: BrokerageEnvironment) {
        var state = loadState()
        let removedId: String?
        switch environment {
        case .paper:
            removedId = state.paperAccountId
            state.paperAccountId = nil
        case .live:
            removedId = state.liveAccountId
            state.liveAccountId = nil
        }
        if state.current?.environment == environment {
            state.current = nil
        }
        if let removedId, !state.uses(removedId) {
            deleteCredentials(id: removedId)
        }
        save(state)
    }

    func clearAll() {
        epoch += 1
        let state = loadState()
        for account in keychain.accounts() {
            keychain.delete(account: account)
        }
        var ids = state.knownIds
        ids.formUnion(state.pendingAccountIds)
        ids.forEach(deleteCredentials(id:))
        disk.delete(name: stateFile)
        current = nil
        AppLog.brokerage.info("cleared brokerage credentials")
    }

    private func accountId(for environment: BrokerageEnvironment) -> String? {
        let state = loadState()
        switch environment {
        case .paper:
            return state.paperAccountId
        case .live:
            return state.liveAccountId
        }
    }

    private func loadState() -> StoredBrokerageState {
        disk.read(StoredBrokerageState.self, name: stateFile) ?? StoredBrokerageState()
    }

    private func save(_ state: StoredBrokerageState) {
        disk.write(state, name: stateFile)
        current = state.current
    }

    private func writeCredentials(id: String, key: String, secret: String) throws {
        let keyAccount = Self.keyAccount(id)
        let secretAccount = Self.secretAccount(id)
        let previousKey = keychain.string(account: keyAccount)
        let previousSecret = keychain.string(account: secretAccount)
        let pendingKey = Self.pendingAccount(keyAccount)
        let pendingSecret = Self.pendingAccount(secretAccount)

        markPending(id)
        do {
            try keychain.set(key, account: pendingKey)
            try keychain.set(secret, account: pendingSecret)
        } catch {
            deletePendingCredentials(id: id)
            unmarkPending(id)
            throw error
        }

        do {
            try keychain.set(key, account: keyAccount)
            try keychain.set(secret, account: secretAccount)
            deletePendingCredentials(id: id)
        } catch {
            deletePendingCredentials(id: id)
            try restorePair(
                key: previousKey,
                secret: previousSecret,
                keyAccount: keyAccount,
                secretAccount: secretAccount
            )
            unmarkPending(id)
            throw error
        }
    }

    private func discardUnresolvedWrites() {
        var state = loadState()
        var pendingIds = Set(state.pendingAccountIds)
        for account in keychain.accounts() {
            if let id = Self.pendingId(from: account) {
                pendingIds.insert(id)
                keychain.delete(account: account)
            }
        }
        for id in pendingIds where !state.uses(id) {
            deleteCredentials(id: id)
        }
        for id in pendingIds {
            deletePendingCredentials(id: id)
        }
        guard !state.pendingAccountIds.isEmpty else { return }
        state.pendingAccountIds = []
        save(state)
    }

    private func markPending(_ id: String) {
        var state = loadState()
        if !state.pendingAccountIds.contains(id) {
            state.pendingAccountIds.append(id)
            save(state)
        }
    }

    private func unmarkPending(_ id: String) {
        var state = loadState()
        let next = state.pendingAccountIds.filter { $0 != id }
        guard next != state.pendingAccountIds else { return }
        state.pendingAccountIds = next
        save(state)
    }

    private func restorePair(key: String?, secret: String?, keyAccount: String, secretAccount: String) throws {
        do {
            try writePair(key: key, secret: secret, keyAccount: keyAccount, secretAccount: secretAccount)
        } catch {
            keychain.delete(account: keyAccount)
            keychain.delete(account: secretAccount)
            do {
                try writePair(key: key, secret: secret, keyAccount: keyAccount, secretAccount: secretAccount)
            } catch {
                keychain.delete(account: keyAccount)
                keychain.delete(account: secretAccount)
                throw error
            }
        }
        let restoredKey = keychain.string(account: keyAccount)
        let restoredSecret = keychain.string(account: secretAccount)
        if restoredKey != key || restoredSecret != secret {
            keychain.delete(account: keyAccount)
            keychain.delete(account: secretAccount)
            throw AppError.decoding
        }
    }

    private func writePair(key: String?, secret: String?, keyAccount: String, secretAccount: String) throws {
        if let key {
            try keychain.set(key, account: keyAccount)
        } else {
            keychain.delete(account: keyAccount)
        }
        if let secret {
            try keychain.set(secret, account: secretAccount)
        } else {
            keychain.delete(account: secretAccount)
        }
    }

    private func deleteCredentials(id: String) {
        keychain.delete(account: Self.keyAccount(id))
        keychain.delete(account: Self.secretAccount(id))
        deletePendingCredentials(id: id)
    }

    private func deletePendingCredentials(id: String) {
        keychain.delete(account: Self.pendingAccount(Self.keyAccount(id)))
        keychain.delete(account: Self.pendingAccount(Self.secretAccount(id)))
    }

    private func removeOrphanedCredentials(previous: StoredBrokerageState, next: StoredBrokerageState) {
        let leftover = previous.knownIds.subtracting(next.knownIds)
        leftover.forEach(deleteCredentials(id:))
    }

    private static func keyAccount(_ id: String) -> String {
        "brokerage.\(id).key"
    }

    private static func secretAccount(_ id: String) -> String {
        "brokerage.\(id).secret"
    }

    private static func pendingAccount(_ account: String) -> String {
        account + ".pending"
    }

    private static func pendingId(from account: String) -> String? {
        guard account.hasPrefix("brokerage.") else { return nil }
        for suffix in [".key.pending", ".secret.pending"] where account.hasSuffix(suffix) {
            return String(account.dropFirst("brokerage.".count).dropLast(suffix.count))
        }
        return nil
    }
}

private struct StoredBrokerageState: Codable {
    var current: BrokerageAccount?
    var paperAccountId: String?
    var liveAccountId: String?
    var pendingAccountIds: [String]

    init(
        current: BrokerageAccount? = nil,
        paperAccountId: String? = nil,
        liveAccountId: String? = nil,
        pendingAccountIds: [String] = []
    ) {
        self.current = current
        self.paperAccountId = paperAccountId
        self.liveAccountId = liveAccountId
        self.pendingAccountIds = pendingAccountIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        current = try container.decodeIfPresent(BrokerageAccount.self, forKey: .current)
        paperAccountId = try container.decodeIfPresent(String.self, forKey: .paperAccountId)
        liveAccountId = try container.decodeIfPresent(String.self, forKey: .liveAccountId)
        pendingAccountIds = try container.decodeIfPresent([String].self, forKey: .pendingAccountIds) ?? []
    }

    var knownIds: Set<String> {
        Set([paperAccountId, liveAccountId, current?.id].compactMap { $0 })
    }

    func uses(_ id: String) -> Bool {
        knownIds.contains(id)
    }
}
