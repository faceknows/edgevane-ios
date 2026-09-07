import Foundation

@MainActor
final class CurrentBrokerageStore: ObservableObject {
    @Published private(set) var generation: UInt64 = 0
    @Published private(set) var current: BrokerageAccount?

    private let keychain: CredentialStoring
    private let disk: DiskStoring
    private let validator: BrokerageAccountValidating
    private let stateFile = "brokerage-state.json"
    private let tombstoneFile = "brokerage-logout.json"
    private let clearRetryNanoseconds: UInt64
    private let maxRetryNanoseconds: UInt64
    private var retryDelayNanoseconds: UInt64
    private var epoch: UInt64 = 0
    private var suppressed = false
    private var pendingEmptyPersist = false
    private var pendingTombstoneRemoval = false
    private var pendingCredentialDeletes: Set<CredentialSlot> = []
    private var ownerUserId: String?
    private var retryTask: Task<Void, Never>?
    private var isForeground = false
    private var pendingDeletesUnreadable = false
    private let pendingDeletesFile = "brokerage-pending-deletes.json"

    init(
        keychain: CredentialStoring = KeychainStore(service: "com.byteknows.moneyknows.brokerage"),
        disk: DiskStoring = DiskStore(),
        validator: BrokerageAccountValidating = AlpacaAccountValidator(),
        clearRetryNanoseconds: UInt64 = 500_000_000
    ) {
        self.keychain = keychain
        self.disk = disk
        self.validator = validator
        self.clearRetryNanoseconds = clearRetryNanoseconds
        self.maxRetryNanoseconds = max(clearRetryNanoseconds, 30_000_000_000)
        self.retryDelayNanoseconds = clearRetryNanoseconds
        restoreFromDisk()
    }

    deinit {
        retryTask?.cancel()
    }

    func setForeground(_ foreground: Bool) {
        let wasForeground = isForeground
        isForeground = foreground
        if foreground {
            if !wasForeground {
                do {
                    try runDeferredDiskCleanup()
                } catch {
                    schedulePersistRetry()
                    return
                }
                if hasPendingRetryWork, retryTask == nil {
                    retryPendingPersist()
                }
            }
            return
        }
        cancelPersistRetry()
    }

    func credentials(for environment: BrokerageEnvironment) -> (key: String, secret: String)? {
        if suppressed { return nil }
        let state: StoredBrokerageState
        do {
            state = try loadState()
        } catch {
            return nil
        }
        guard allows(state) else { return nil }
        guard let id = state.accountId(for: environment) else { return nil }
        return credentials(id: id, revision: state.revision(for: environment), environment: environment)
    }

    func prepareForUser(_ userId: String) {
        ownerUserId = userId
        if hasTombstone, !keepsStateOverTombstone() {
            if current != nil {
                current = nil
                generation += 1
            }
            return
        }
        let state: StoredBrokerageState
        do {
            state = try loadState()
        } catch {
            if current != nil {
                current = nil
                generation += 1
            }
            return
        }
        if let bound = state.ownerUserId, bound != userId {
            if current != nil {
                current = nil
                generation += 1
            }
            return
        }
        if state.ownerUserId == nil, state.hasAccount {
            var next = state
            next.ownerUserId = userId
            do {
                try persist(next, notify: false)
            } catch {
                if current != nil {
                    current = nil
                    generation += 1
                }
                return
            }
            if needsIsolationRecovery {
                do {
                    try recoverFromIsolationIfNeeded()
                } catch {
                    schedulePersistRetry()
                }
            }
            if current != state.current {
                current = state.current
            }
            generation += 1
            return
        }
        if needsIsolationRecovery {
            do {
                try recoverFromIsolationIfNeeded()
            } catch {
                if current != nil {
                    current = nil
                    generation += 1
                }
                schedulePersistRetry()
            }
            return
        }
        if current != state.current {
            current = state.current
            generation += 1
        }
    }

    func replace(key: String, secret: String, environment: BrokerageEnvironment) async throws {
        epoch += 1
        let operation = epoch
        cancelPersistRetry()
        resetRetryBackoff()
        let isolated = suppressed || hasTombstone
        let leftover = try loadCleanupState()
        let previous = isolated ? StoredBrokerageState() : (try usableReplaceState(leftover))
        var written: (id: String, revision: Int)?
        var committed = false
        do {
            let account = try await validator.validate(key: key, secret: secret, environment: environment)
            guard operation == epoch else {
                throw AppError.cancelled
            }
            let newRevision = try nextRevision(
                id: account.id,
                environment: environment,
                leftover: leftover,
                previous: previous
            )
            try writeCredentials(id: account.id, key: key, secret: secret, revision: newRevision, environment: environment)
            written = (account.id, newRevision)
            let writtenSlot = CredentialSlot(id: account.id, revision: newRevision, environment: environment)
            pendingCredentialDeletes.insert(writtenSlot)
            try persistPendingDeletes()
            guard operation == epoch else {
                abandonWrittenSlot(writtenSlot)
                throw AppError.cancelled
            }

            var next = isolated ? StoredBrokerageState() : (try usableReplaceState(try loadState()))
            next.current = account
            next.setAccount(id: account.id, revision: newRevision, environment: environment)
            next.pendingAccountIds.removeAll { $0 == account.id }
            next.ownerUserId = ownerUserId ?? next.ownerUserId
            collectObsoleteCredentials(from: leftover, keeping: next)
            try persistPendingDeletes()
            try persist(next, notify: true)
            written = nil
            committed = true
            pendingEmptyPersist = false
            suppressed = false
            pendingCredentialDeletes.remove(writtenSlot)
            try persistPendingDeletes()
            pendingTombstoneRemoval = hasTombstone
            try removeTombstone()
            retryPendingCredentialDeletes()
            AppLog.brokerage.info("replaced brokerage account \(environment.rawValue, privacy: .public)")
        } catch {
            if committed {
                pendingTombstoneRemoval = hasTombstone
                schedulePersistRetry()
                throw error
            }
            if let written {
                let slot = CredentialSlot(id: written.id, revision: written.revision, environment: environment)
                do {
                    if try adoptDurableWriteIfPresent(slot) {
                        return
                    }
                } catch {
                    isolateMemory()
                    pendingCredentialDeletes.insert(slot)
                    try? persistPendingDeletes()
                    schedulePersistRetry()
                    throw error
                }
                let discarded = abandonWrittenSlot(slot)
                guard operation == epoch else {
                    throw AppError.cancelled
                }
                if isolated {
                    schedulePersistRetry()
                } else if discarded {
                    try? persist(previous, notify: false)
                }
                AppLog.brokerage.error("brokerage replace failed \(environment.rawValue, privacy: .public)")
                throw error
            }
            guard operation == epoch else {
                throw AppError.cancelled
            }
            if isolated {
                schedulePersistRetry()
            } else {
                try? persist(previous, notify: false)
            }
            AppLog.brokerage.error("brokerage replace failed \(environment.rawValue, privacy: .public)")
            throw error
        }
    }

    func clear(environment: BrokerageEnvironment) throws {
        guard !suppressed, !hasTombstone else {
            throw AppError.cancelled
        }
        epoch += 1
        cancelPersistRetry()
        resetRetryBackoff()
        defer {
            if !pendingCredentialDeletes.isEmpty, retryTask == nil {
                schedulePersistRetry()
            }
        }
        let previous = try loadState()
        guard allows(previous) else {
            throw AppError.cancelled
        }
        var state = previous
        let removedId: String?
        let removedRevision: Int
        switch environment {
        case .paper:
            removedId = state.paperAccountId
            removedRevision = state.paperRevision
            state.paperAccountId = nil
            state.paperRevision = 0
        case .live:
            removedId = state.liveAccountId
            removedRevision = state.liveRevision
            state.liveAccountId = nil
            state.liveRevision = 0
        }
        if state.current?.environment == environment {
            state.current = nil
        }
        let previousPending = pendingCredentialDeletes
        let removedSlot: CredentialSlot? = {
            guard let removedId else { return nil }
            let slot = CredentialSlot(id: removedId, revision: removedRevision, environment: environment)
            guard !state.referencedSlots.contains(slot) else { return nil }
            rememberCredentialDelete(slot)
            return slot
        }()
        do {
            try persistPendingDeletes()
            try persist(state, notify: true)
        } catch {
            let attemptedPending = pendingCredentialDeletes
            recoverClearPersistFailure(previous: previous)
            pendingCredentialDeletes = suppressed ? attemptedPending : previousPending
            try? persistPendingDeletes()
            throw error
        }
        if let removedSlot {
            do {
                try deleteCredentialsChecked(removedSlot, keeping: state.referencedSlots)
                forgetCredentialDeletes(removedSlot)
                try persistPendingDeletes()
            } catch {
                AppLog.brokerage.error("cleared brokerage account keychain delete failed \(environment.rawValue, privacy: .public)")
                throw error
            }
        }
        retryPendingCredentialDeletes()
        AppLog.brokerage.info("cleared brokerage account \(environment.rawValue, privacy: .public)")
    }

    func clearAll() throws {
        epoch += 1
        cancelPersistRetry()
        resetRetryBackoff()
        isolateMemory()
        pendingEmptyPersist = true
        do {
            try commitLogout()
        } catch {
            schedulePersistRetry()
            throw error
        }
    }

    private func loadState() throws -> StoredBrokerageState {
        let state = try disk.readIfPresent(StoredBrokerageState.self, name: stateFile) ?? StoredBrokerageState()
        try state.validate()
        return state
    }

    private func loadCleanupState() throws -> StoredBrokerageState {
        try disk.readIfPresent(StoredBrokerageState.self, name: stateFile) ?? StoredBrokerageState()
    }

    private func usableReplaceState(_ state: StoredBrokerageState) throws -> StoredBrokerageState {
        try state.validate()
        if allows(state) {
            return state
        }
        if state.hasAccount {
            throw AppError.cancelled
        }
        return state
    }

    private var hasTombstone: Bool {
        disk.exists(name: tombstoneFile)
    }

    private func allows(_ state: StoredBrokerageState) -> Bool {
        if suppressed { return false }
        if isBlockedByTombstone(state) { return false }
        if let ownerUserId {
            guard let bound = state.ownerUserId, bound == ownerUserId else { return false }
        }
        return true
    }

    private func isBlockedByTombstone(_ state: StoredBrokerageState) -> Bool {
        guard hasTombstone else { return false }
        guard let epoch = tombstoneEpoch() else { return true }
        return !(state.hasAccount && state.writeEpoch > epoch)
    }

    private func keepsStateOverTombstone() -> Bool {
        guard hasTombstone else { return false }
        guard let state = try? loadState() else { return false }
        return !isBlockedByTombstone(state)
    }

    private func tombstoneEpoch() -> UInt64? {
        try? disk.readIfPresent(BrokerageLogoutTombstone.self, name: tombstoneFile)?.epoch
    }

    private func nextWriteEpoch() throws -> UInt64 {
        let tombstone = try disk.readIfPresent(BrokerageLogoutTombstone.self, name: tombstoneFile)?.epoch ?? 0
        let stateEpoch = try disk.readIfPresent(StoredBrokerageState.self, name: stateFile)?.writeEpoch ?? 0
        let current = max(tombstone, stateEpoch)
        let (next, overflow) = current.addingReportingOverflow(1)
        guard !overflow else {
            throw AppError.decoding
        }
        return next
    }

    private func restoreFromDisk() {
        do {
            try loadPendingDeletes()
        } catch {
            pendingDeletesUnreadable = true
        }
        if hasTombstone, keepsStateOverTombstone() {
            suppressed = false
            pendingEmptyPersist = false
            pendingTombstoneRemoval = true
            do {
                current = try loadState().current
            } catch {
                current = nil
            }
            return
        }
        if hasTombstone {
            suppressed = true
            current = nil
            pendingEmptyPersist = true
            return
        }
        do {
            current = try loadState().current
        } catch {
            AppLog.brokerage.error("brokerage state unreadable")
            current = nil
        }
    }

    private func runDeferredDiskCleanup() throws {
        if !hasTombstone {
            pendingTombstoneRemoval = false
        }
        if pendingDeletesUnreadable {
            do {
                try loadPendingDeletes()
            } catch {
                pendingDeletesUnreadable = true
            }
        }
        if hasTombstone, keepsStateOverTombstone() {
            suppressed = false
            pendingEmptyPersist = false
            pendingTombstoneRemoval = true
            try reconcileUnresolvedCredentials()
            current = try loadState().current
            try removeTombstone()
            pendingTombstoneRemoval = false
            return
        }
        if pendingEmptyPersist || hasTombstone {
            suppressed = true
            current = nil
            pendingEmptyPersist = true
            try commitLogout()
            return
        }
        try reconcileUnresolvedCredentials()
        try recoverFromIsolationIfNeeded()
    }

    private func recoverClearPersistFailure(previous: StoredBrokerageState) {
        let diskState = try? loadState()
        let diverged = diskState.map { !$0.semanticallyMatches(previous) } ?? true
        guard diverged else { return }
        do {
            try persist(previous, notify: false)
        } catch {
            isolateMemory()
            schedulePersistRetry()
        }
    }

    private func recoverFromIsolationIfNeeded() throws {
        guard needsIsolationRecovery else { return }
        let state = try loadState()
        if let ownerUserId {
            guard let bound = state.ownerUserId, bound == ownerUserId else { return }
        }
        suppressed = false
        current = state.current
        generation += 1
    }

    private func persist(_ state: StoredBrokerageState, notify: Bool) throws {
        var next = state
        next.writeEpoch = try nextWriteEpoch()
        try disk.writeChecked(next, name: stateFile)
        let publishable = canPublish(next)
        if notify {
            if publishable {
                current = next.current
                generation += 1
            } else if current != nil {
                current = nil
                generation += 1
            }
            return
        }
        if publishable {
            if current != next.current {
                current = next.current
            }
            return
        }
        if current != nil {
            current = nil
            generation += 1
        }
    }

    private func canPublish(_ state: StoredBrokerageState) -> Bool {
        if isBlockedByTombstone(state) { return false }
        if let ownerUserId {
            guard let bound = state.ownerUserId, bound == ownerUserId else { return false }
        }
        return true
    }

    private func credentials(id: String, revision: Int, environment: BrokerageEnvironment) -> (key: String, secret: String)? {
        if let pair = credentialPair(
            keyAccount: Self.keyAccount(id, revision: revision, environment: environment),
            secretAccount: Self.secretAccount(id, revision: revision, environment: environment)
        ) {
            return pair
        }
        return credentialPair(
            keyAccount: Self.legacyKeyAccount(id, revision: revision),
            secretAccount: Self.legacySecretAccount(id, revision: revision)
        )
    }

    private func credentialPair(keyAccount: String, secretAccount: String) -> (key: String, secret: String)? {
        guard let key = keychain.string(account: keyAccount),
              let secret = keychain.string(account: secretAccount),
              !key.isEmpty,
              !secret.isEmpty
        else {
            return nil
        }
        return (key, secret)
    }

    private func writeCredentials(
        id: String,
        key: String,
        secret: String,
        revision: Int,
        environment: BrokerageEnvironment
    ) throws {
        guard try !slotHasCredentials(id: id, revision: revision, environment: environment) else {
            throw AppError.decoding
        }
        let keyAccount = Self.keyAccount(id, revision: revision, environment: environment)
        let secretAccount = Self.secretAccount(id, revision: revision, environment: environment)
        do {
            try keychain.set(key, account: keyAccount)
            try keychain.set(secret, account: secretAccount)
            guard keychain.string(account: keyAccount) == key,
                  keychain.string(account: secretAccount) == secret
            else {
                throw AppError.decoding
            }
        } catch {
            abandonWrittenSlot(CredentialSlot(id: id, revision: revision, environment: environment))
            throw error
        }
    }

    private func isolateMemory() {
        suppressed = true
        current = nil
        generation += 1
    }

    private func nextRevision(
        id: String,
        environment: BrokerageEnvironment,
        leftover: StoredBrokerageState,
        previous: StoredBrokerageState
    ) throws -> Int {
        var highest = 0
        for state in [leftover, previous] {
            if state.accountId(for: environment) == id {
                highest = max(highest, state.revision(for: environment))
            }
        }
        let listed = try keychain.accounts()
        for account in listed {
            guard let slot = Self.parseSlot(from: account), slot.id == id else { continue }
            if slot.environment == environment || slot.environment == nil {
                highest = max(highest, slot.revision)
            }
        }
        var candidate = try incrementRevision(max(highest, 0))
        while try slotHasCredentials(id: id, revision: candidate, environment: environment) {
            candidate = try incrementRevision(candidate)
        }
        return candidate
    }

    private func incrementRevision(_ value: Int) throws -> Int {
        let (next, overflow) = value.addingReportingOverflow(1)
        guard !overflow else {
            throw AppError.decoding
        }
        return next
    }

    private func slotHasCredentials(id: String, revision: Int, environment: BrokerageEnvironment) throws -> Bool {
        if try keychain.stringIfPresent(account: Self.keyAccount(id, revision: revision, environment: environment)) != nil {
            return true
        }
        if try keychain.stringIfPresent(account: Self.secretAccount(id, revision: revision, environment: environment)) != nil {
            return true
        }
        if try keychain.stringIfPresent(account: Self.legacyKeyAccount(id, revision: revision)) != nil {
            return true
        }
        if try keychain.stringIfPresent(account: Self.legacySecretAccount(id, revision: revision)) != nil {
            return true
        }
        return false
    }

    private func adoptDurableWriteIfPresent(_ slot: CredentialSlot) throws -> Bool {
        guard let state = try disk.readIfPresent(StoredBrokerageState.self, name: stateFile) else {
            return false
        }
        try state.validate()
        guard isKept(slot, in: state.referencedSlots) else { return false }
        pendingCredentialDeletes.remove(slot)
        try? persistPendingDeletes()
        if canPublish(state) {
            current = state.current
            generation += 1
            suppressed = false
            pendingEmptyPersist = false
            pendingTombstoneRemoval = hasTombstone
            if hasTombstone {
                schedulePersistRetry()
            }
            retryPendingCredentialDeletes()
        } else {
            isolateMemory()
            pendingCredentialDeletes.insert(slot)
            try? persistPendingDeletes()
            schedulePersistRetry()
        }
        return true
    }

    @discardableResult
    private func abandonWrittenSlot(_ slot: CredentialSlot) -> Bool {
        pendingCredentialDeletes.insert(slot)
        do {
            try persistPendingDeletes()
        } catch {
            schedulePersistRetry()
        }
        let keep: Set<CredentialSlot>
        do {
            keep = try disk.readIfPresent(StoredBrokerageState.self, name: stateFile)?.referencedSlots ?? []
        } catch {
            isolateMemory()
            schedulePersistRetry()
            return false
        }
        if isKept(slot, in: keep) {
            isolateMemory()
            schedulePersistRetry()
            return false
        }
        do {
            try deleteRevisionChecked(slot, keeping: keep)
            pendingCredentialDeletes.remove(slot)
            try persistPendingDeletes()
        } catch {
            schedulePersistRetry()
        }
        return true
    }

    private func wipeKeychain(_ previous: StoredBrokerageState) throws {
        var firstError: Error?
        var slots = previous.referencedSlots
        slots.formUnion(pendingCredentialDeletes)
        for slot in slots {
            do {
                try deleteRevisionChecked(slot, keeping: [])
            } catch {
                firstError = firstError ?? error
            }
        }
        var ids = previous.knownIds
        ids.formUnion(previous.pendingAccountIds)
        ids.formUnion(pendingCredentialDeletes.map(\.id))
        for id in ids {
            do {
                try deleteRevisionChecked(CredentialSlot(id: id, revision: 0), keeping: [])
                try deletePendingCredentialsChecked(id: id)
            } catch {
                firstError = firstError ?? error
            }
        }
        do {
            for account in try keychain.accounts() {
                try keychain.deleteChecked(account: account)
            }
        } catch {
            firstError = firstError ?? error
        }
        if let firstError {
            throw firstError
        }
    }

    private func persistTombstone() throws {
        try disk.writeChecked(BrokerageLogoutTombstone(epoch: try nextWriteEpoch()), name: tombstoneFile)
    }

    private func removeTombstone() throws {
        guard hasTombstone else {
            pendingTombstoneRemoval = false
            return
        }
        disk.delete(name: tombstoneFile)
        if hasTombstone {
            throw AppError.decoding
        }
        pendingTombstoneRemoval = false
    }

    private func commitLogout() throws {
        let previous = (try? loadState()) ?? StoredBrokerageState()
        collectObsoleteCredentials(from: previous, keeping: StoredBrokerageState())
        var firstError: Error?
        do {
            try persistTombstone()
        } catch {
            firstError = error
        }
        var pendingPersisted = pendingCredentialDeletes.isEmpty
        if !pendingCredentialDeletes.isEmpty {
            do {
                try persistPendingDeletes()
                pendingPersisted = true
            } catch {
                firstError = firstError ?? error
            }
        }
        do {
            try wipeKeychain(previous)
        } catch {
            firstError = firstError ?? error
        }
        if pendingPersisted {
            do {
                try persist(StoredBrokerageState(), notify: false)
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError {
            AppLog.brokerage.error("clear brokerage persist failed")
            throw firstError
        }
        pendingCredentialDeletes = []
        pendingDeletesUnreadable = false
        try persistPendingDeletes()
        try removeTombstone()
        pendingEmptyPersist = false
        pendingTombstoneRemoval = false
        suppressed = false
        AppLog.brokerage.info("cleared brokerage credentials")
    }

    private func cancelPersistRetry() {
        retryTask?.cancel()
        retryTask = nil
    }

    private func resetRetryBackoff() {
        retryDelayNanoseconds = clearRetryNanoseconds
    }

    private var hasPendingRetryWork: Bool {
        pendingTombstoneRemoval
            || pendingEmptyPersist
            || hasTombstone
            || !pendingCredentialDeletes.isEmpty
            || pendingDeletesUnreadable
            || needsIsolationRecovery
    }

    private var needsIsolationRecovery: Bool {
        suppressed && !pendingEmptyPersist && !hasTombstone
    }

    private func nextRetryDelay(after current: UInt64) -> UInt64 {
        if current >= maxRetryNanoseconds { return maxRetryNanoseconds }
        if current > maxRetryNanoseconds / 2 { return maxRetryNanoseconds }
        return min(current * 2, maxRetryNanoseconds)
    }

    private func schedulePersistRetry() {
        cancelPersistRetry()
        guard isForeground else { return }
        let delay = retryDelayNanoseconds
        retryDelayNanoseconds = nextRetryDelay(after: delay)
        retryTask = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled else { return }
            self?.retryPendingPersist()
        }
    }

    private func retryPendingPersist() {
        do {
            try runDeferredDiskCleanup()
        } catch {
            schedulePersistRetry()
            return
        }
        retryPendingCredentialDeletes()
        if hasPendingRetryWork {
            if retryTask == nil {
                schedulePersistRetry()
            }
            return
        }
        resetRetryBackoff()
    }

    private func retryPendingCredentialDeletes() {
        guard !pendingCredentialDeletes.isEmpty else { return }
        do {
            try flushPendingCredentialDeletes()
        } catch {
            schedulePersistRetry()
        }
    }

    private func rememberCredentialDelete(_ slot: CredentialSlot) {
        pendingCredentialDeletes.insert(slot)
        if slot.revision != 0 {
            pendingCredentialDeletes.insert(CredentialSlot(id: slot.id, revision: 0, environment: slot.environment))
        }
    }

    private func forgetCredentialDeletes(_ slot: CredentialSlot) {
        pendingCredentialDeletes = pendingCredentialDeletes.filter { pending in
            guard pending.id == slot.id else { return true }
            if let expected = slot.environment, let pendingEnvironment = pending.environment {
                return pendingEnvironment != expected
            }
            return false
        }
    }

    private func collectObsoleteCredentials(from leftover: StoredBrokerageState, keeping next: StoredBrokerageState) {
        let keepSlots = next.referencedSlots
        for slot in leftover.referencedSlots where !keepSlots.contains(slot) {
            rememberCredentialDelete(slot)
        }
        for id in leftover.knownIds.union(leftover.pendingAccountIds) where !next.uses(id) {
            if leftover.paperAccountId == id {
                rememberCredentialDelete(CredentialSlot(id: id, revision: 0, environment: .paper))
            }
            if leftover.liveAccountId == id {
                rememberCredentialDelete(CredentialSlot(id: id, revision: 0, environment: .live))
            }
            if leftover.paperAccountId != id, leftover.liveAccountId != id {
                rememberCredentialDelete(CredentialSlot(id: id, revision: 0))
            }
        }
    }

    private func flushPendingCredentialDeletes() throws {
        var firstError: Error?
        var remaining = pendingCredentialDeletes
        let keep: Set<CredentialSlot>
        if pendingEmptyPersist || (hasTombstone && !keepsStateOverTombstone()) {
            keep = []
        } else {
            guard let state = try? loadState() else {
                throw AppError.decoding
            }
            keep = state.referencedSlots
        }
        for slot in pendingCredentialDeletes {
            if isKept(slot, in: keep) {
                remaining.remove(slot)
                continue
            }
            do {
                try deleteRevisionChecked(slot, keeping: keep)
                remaining.remove(slot)
            } catch {
                firstError = firstError ?? error
            }
        }
        let keepIds = Set(keep.map(\.id))
        let obsoleteIds = Set(pendingCredentialDeletes.map(\.id)).subtracting(keepIds)
        for id in obsoleteIds {
            do {
                try deleteCredentialsChecked(CredentialSlot(id: id, revision: 0), keeping: keep)
                remaining = remaining.filter { $0.id != id }
            } catch {
                firstError = firstError ?? error
            }
        }
        pendingCredentialDeletes = remaining
        try persistPendingDeletes()
        if let firstError {
            throw firstError
        }
    }

    private func isKept(_ slot: CredentialSlot, in keep: Set<CredentialSlot>) -> Bool {
        if keep.contains(slot) { return true }
        if slot.environment == nil {
            return keep.contains { $0.id == slot.id && $0.revision == slot.revision }
        }
        return keep.contains { $0.environment == nil && $0.id == slot.id && $0.revision == slot.revision }
    }

    private func loadPendingDeletes() throws {
        do {
            let record = try disk.readIfPresent(BrokeragePendingDeletes.self, name: pendingDeletesFile)
            pendingCredentialDeletes = Set(record?.slots ?? [])
            pendingDeletesUnreadable = false
        } catch {
            pendingDeletesUnreadable = true
            throw error
        }
    }

    private func persistPendingDeletes() throws {
        if pendingDeletesUnreadable, pendingCredentialDeletes.isEmpty {
            return
        }
        let slots = pendingCredentialDeletes.sorted { lhs, rhs in
            if lhs.id != rhs.id { return lhs.id < rhs.id }
            if lhs.revision != rhs.revision { return lhs.revision < rhs.revision }
            return (lhs.environment?.rawValue ?? "") < (rhs.environment?.rawValue ?? "")
        }
        let record = BrokeragePendingDeletes(slots: slots)
        if slots.isEmpty {
            disk.delete(name: pendingDeletesFile)
            if disk.exists(name: pendingDeletesFile) {
                try disk.writeChecked(record, name: pendingDeletesFile)
            }
            pendingDeletesUnreadable = false
            return
        }
        try disk.writeChecked(record, name: pendingDeletesFile)
        pendingDeletesUnreadable = false
    }

    private func reconcileUnresolvedCredentials() throws {
        if !pendingCredentialDeletes.isEmpty {
            do {
                try flushPendingCredentialDeletes()
            } catch {
                if pendingDeletesUnreadable {
                    throw error
                }
                // Keep going so enumeration can still drop unreferenced leftovers.
            }
        }
        let state: StoredBrokerageState
        do {
            state = try loadState()
        } catch {
            if !pendingCredentialDeletes.isEmpty || pendingDeletesUnreadable {
                throw AppError.decoding
            }
            return
        }
        let referenced = state.referencedSlots
        let listed: [String]
        do {
            listed = try keychain.accounts()
            pendingDeletesUnreadable = false
        } catch {
            if !pendingCredentialDeletes.isEmpty || pendingDeletesUnreadable {
                throw error
            }
            return
        }
        var firstError: Error?
        for account in listed {
            if Self.isPending(account) {
                do {
                    try keychain.deleteChecked(account: account)
                } catch {
                    if let id = Self.pendingId(from: account) {
                        rememberCredentialDelete(CredentialSlot(id: id, revision: 0, environment: Self.pendingEnvironment(from: account)))
                    }
                    firstError = firstError ?? error
                }
                continue
            }
            if let slot = Self.parseSlot(from: account), !isKept(slot, in: referenced) {
                do {
                    try keychain.deleteChecked(account: account)
                } catch {
                    rememberCredentialDelete(slot)
                    firstError = firstError ?? error
                }
            }
        }
        try persistPendingDeletes()
        if !state.pendingAccountIds.isEmpty {
            var next = state
            next.pendingAccountIds = []
            try persist(next, notify: false)
        }
        if let firstError {
            throw firstError
        }
    }

    private func deleteRevisionChecked(_ slot: CredentialSlot, keeping keep: Set<CredentialSlot>) throws {
        guard !isKept(slot, in: keep) else { return }
        var firstError: Error?
        if let environment = slot.environment {
            do {
                try keychain.deleteChecked(account: Self.keyAccount(slot.id, revision: slot.revision, environment: environment))
                try keychain.deleteChecked(account: Self.secretAccount(slot.id, revision: slot.revision, environment: environment))
            } catch {
                firstError = error
            }
        }
        let keepLegacy = keep.contains { $0.id == slot.id && $0.revision == slot.revision }
        if slot.environment == nil || !keepLegacy {
            do {
                try keychain.deleteChecked(account: Self.legacyKeyAccount(slot.id, revision: slot.revision))
                try keychain.deleteChecked(account: Self.legacySecretAccount(slot.id, revision: slot.revision))
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError {
            throw firstError
        }
    }

    private func deletePendingCredentialsChecked(id: String, environment: BrokerageEnvironment? = nil) throws {
        var firstError: Error?
        if let environment {
            do {
                try keychain.deleteChecked(account: Self.pendingAccount(Self.keyAccount(id, revision: 0, environment: environment)))
                try keychain.deleteChecked(account: Self.pendingAccount(Self.secretAccount(id, revision: 0, environment: environment)))
            } catch {
                firstError = error
            }
        }
        do {
            try keychain.deleteChecked(account: Self.pendingAccount(Self.legacyKeyAccount(id, revision: 0)))
            try keychain.deleteChecked(account: Self.pendingAccount(Self.legacySecretAccount(id, revision: 0)))
        } catch {
            firstError = firstError ?? error
        }
        if let firstError {
            throw firstError
        }
    }

    private func deleteCredentialsChecked(_ slot: CredentialSlot, keeping keep: Set<CredentialSlot>) throws {
        var firstError: Error?
        do {
            try deleteRevisionChecked(slot, keeping: keep)
        } catch {
            firstError = error
        }
        if slot.revision != 0 {
            do {
                try deleteRevisionChecked(
                    CredentialSlot(id: slot.id, revision: 0, environment: slot.environment),
                    keeping: keep
                )
            } catch {
                firstError = firstError ?? error
            }
        }
        do {
            try deletePendingCredentialsChecked(id: slot.id, environment: slot.environment)
        } catch {
            firstError = firstError ?? error
        }
        do {
            for account in try keychain.accounts() {
                if Self.isPending(account) {
                    let pendingId = Self.pendingId(from: account)
                    let pendingEnvironment = Self.pendingEnvironment(from: account)
                    guard pendingId == slot.id else { continue }
                    if let expected = slot.environment, let pendingEnvironment, expected != pendingEnvironment {
                        continue
                    }
                } else if let parsed = Self.parseSlot(from: account) {
                    guard parsed.id == slot.id else { continue }
                    if let expected = slot.environment, let parsedEnvironment = parsed.environment, expected != parsedEnvironment {
                        continue
                    }
                    if isKept(parsed, in: keep) { continue }
                } else {
                    continue
                }
                do {
                    try keychain.deleteChecked(account: account)
                } catch {
                    firstError = firstError ?? error
                }
            }
        } catch {
            firstError = firstError ?? error
        }
        if let firstError {
            throw firstError
        }
    }

    private func deleteRevision(id: String, revision: Int, environment: BrokerageEnvironment) {
        keychain.delete(account: Self.keyAccount(id, revision: revision, environment: environment))
        keychain.delete(account: Self.secretAccount(id, revision: revision, environment: environment))
        let referenced: Bool
        do {
            referenced = try legacySlotIsReferenced(id: id, revision: revision)
        } catch {
            return
        }
        guard !referenced else { return }
        keychain.delete(account: Self.legacyKeyAccount(id, revision: revision))
        keychain.delete(account: Self.legacySecretAccount(id, revision: revision))
    }

    private func legacySlotIsReferenced(id: String, revision: Int) throws -> Bool {
        guard let state = try disk.readIfPresent(StoredBrokerageState.self, name: stateFile) else {
            return false
        }
        return state.referencedSlots.contains { $0.id == id && $0.revision == revision }
    }

    private static func keyAccount(_ id: String, revision: Int, environment: BrokerageEnvironment) -> String {
        if revision <= 0 {
            return "brokerage.\(id).\(environment.rawValue).key"
        }
        return "brokerage.\(id).\(environment.rawValue).r\(revision).key"
    }

    private static func secretAccount(_ id: String, revision: Int, environment: BrokerageEnvironment) -> String {
        if revision <= 0 {
            return "brokerage.\(id).\(environment.rawValue).secret"
        }
        return "brokerage.\(id).\(environment.rawValue).r\(revision).secret"
    }

    private static func legacyKeyAccount(_ id: String, revision: Int) -> String {
        if revision <= 0 {
            return "brokerage.\(id).key"
        }
        return "brokerage.\(id).r\(revision).key"
    }

    private static func legacySecretAccount(_ id: String, revision: Int) -> String {
        if revision <= 0 {
            return "brokerage.\(id).secret"
        }
        return "brokerage.\(id).r\(revision).secret"
    }

    private static func pendingAccount(_ account: String) -> String {
        account + ".pending"
    }

    private static func isPending(_ account: String) -> Bool {
        account.hasSuffix(".pending")
    }

    private static func pendingId(from account: String) -> String? {
        guard account.hasPrefix("brokerage.") else { return nil }
        for suffix in [".key.pending", ".secret.pending"] where account.hasSuffix(suffix) {
            var body = String(account.dropFirst("brokerage.".count).dropLast(suffix.count))
            _ = parseEnvironmentSuffix(&body)
            return body.isEmpty ? nil : body
        }
        return nil
    }

    private static func pendingEnvironment(from account: String) -> BrokerageEnvironment? {
        guard account.hasPrefix("brokerage.") else { return nil }
        for suffix in [".key.pending", ".secret.pending"] where account.hasSuffix(suffix) {
            var body = String(account.dropFirst("brokerage.".count).dropLast(suffix.count))
            return parseEnvironmentSuffix(&body)
        }
        return nil
    }

    private static func parseSlot(from account: String) -> CredentialSlot? {
        guard account.hasPrefix("brokerage.") else { return nil }
        let rest = String(account.dropFirst("brokerage.".count))
        let suffix: String
        if rest.hasSuffix(".key") {
            suffix = ".key"
        } else if rest.hasSuffix(".secret") {
            suffix = ".secret"
        } else {
            return nil
        }
        var body = String(rest.dropLast(suffix.count))
        guard !body.isEmpty else { return nil }
        if let revisionRange = body.range(of: #"\.r[0-9]+$"#, options: .regularExpression) {
            let revisionText = String(body[revisionRange].dropFirst(2))
            guard let revision = Int(revisionText) else { return nil }
            body = String(body[..<revisionRange.lowerBound])
            let environment = parseEnvironmentSuffix(&body)
            guard !body.isEmpty else { return nil }
            return CredentialSlot(id: body, revision: revision, environment: environment)
        }
        let environment = parseEnvironmentSuffix(&body)
        guard !body.isEmpty else { return nil }
        return CredentialSlot(id: body, revision: 0, environment: environment)
    }

    private static func parseEnvironmentSuffix(_ body: inout String) -> BrokerageEnvironment? {
        for environment in BrokerageEnvironment.allCases {
            let suffix = ".\(environment.rawValue)"
            if body.hasSuffix(suffix) {
                let id = String(body.dropLast(suffix.count))
                guard !id.isEmpty else { continue }
                body = id
                return environment
            }
        }
        return nil
    }
}

private struct BrokerageLogoutTombstone: Codable, Equatable {
    var version: Int = 1
    var epoch: UInt64 = 0
}

private struct BrokeragePendingDeletes: Codable, Equatable {
    var version: Int = 1
    var slots: [CredentialSlot]
}

private struct CredentialSlot: Codable, Hashable {
    var id: String
    var revision: Int
    var environment: BrokerageEnvironment?

    init(id: String, revision: Int, environment: BrokerageEnvironment? = nil) {
        self.id = id
        self.revision = revision
        self.environment = environment
    }
}

private struct StoredBrokerageState: Codable, Equatable {
    var current: BrokerageAccount?
    var paperAccountId: String?
    var liveAccountId: String?
    var paperRevision: Int
    var liveRevision: Int
    var pendingAccountIds: [String]
    var ownerUserId: String?
    var writeEpoch: UInt64

    init(
        current: BrokerageAccount? = nil,
        paperAccountId: String? = nil,
        liveAccountId: String? = nil,
        paperRevision: Int = 0,
        liveRevision: Int = 0,
        pendingAccountIds: [String] = [],
        ownerUserId: String? = nil,
        writeEpoch: UInt64 = 0
    ) {
        self.current = current
        self.paperAccountId = paperAccountId
        self.liveAccountId = liveAccountId
        self.paperRevision = paperRevision
        self.liveRevision = liveRevision
        self.pendingAccountIds = pendingAccountIds
        self.ownerUserId = ownerUserId
        self.writeEpoch = writeEpoch
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        current = try container.decodeIfPresent(BrokerageAccount.self, forKey: .current)
        paperAccountId = try container.decodeIfPresent(String.self, forKey: .paperAccountId)
        liveAccountId = try container.decodeIfPresent(String.self, forKey: .liveAccountId)
        paperRevision = try container.decodeIfPresent(Int.self, forKey: .paperRevision) ?? 0
        liveRevision = try container.decodeIfPresent(Int.self, forKey: .liveRevision) ?? 0
        pendingAccountIds = try container.decodeIfPresent([String].self, forKey: .pendingAccountIds) ?? []
        ownerUserId = try container.decodeIfPresent(String.self, forKey: .ownerUserId)
        writeEpoch = try container.decodeIfPresent(UInt64.self, forKey: .writeEpoch) ?? 0
    }

    var hasAccount: Bool {
        current != nil || paperAccountId != nil || liveAccountId != nil
    }

    var knownIds: Set<String> {
        Set([paperAccountId, liveAccountId, current?.id].compactMap { $0 })
    }

    var referencedSlots: Set<CredentialSlot> {
        var slots = Set<CredentialSlot>()
        if let paperAccountId {
            slots.insert(CredentialSlot(id: paperAccountId, revision: paperRevision, environment: .paper))
        }
        if let liveAccountId {
            slots.insert(CredentialSlot(id: liveAccountId, revision: liveRevision, environment: .live))
        }
        if let current {
            slots.insert(
                CredentialSlot(
                    id: current.id,
                    revision: revision(for: current.environment),
                    environment: current.environment
                )
            )
        }
        return slots
    }

    func semanticallyMatches(_ other: StoredBrokerageState) -> Bool {
        current == other.current
            && paperAccountId == other.paperAccountId
            && liveAccountId == other.liveAccountId
            && paperRevision == other.paperRevision
            && liveRevision == other.liveRevision
            && pendingAccountIds == other.pendingAccountIds
            && ownerUserId == other.ownerUserId
    }

    func uses(_ id: String) -> Bool {
        knownIds.contains(id)
    }

    func accountId(for environment: BrokerageEnvironment) -> String? {
        switch environment {
        case .paper: return paperAccountId
        case .live: return liveAccountId
        }
    }

    func revision(for environment: BrokerageEnvironment) -> Int {
        switch environment {
        case .paper: return paperRevision
        case .live: return liveRevision
        }
    }

    mutating func setAccount(id: String, revision: Int, environment: BrokerageEnvironment) {
        switch environment {
        case .paper:
            paperAccountId = id
            paperRevision = revision
        case .live:
            liveAccountId = id
            liveRevision = revision
        }
    }

    func validate() throws {
        if let current {
            guard !current.id.isEmpty else { throw AppError.decoding }
            guard current.provider == "alpaca" else { throw AppError.decoding }
            guard accountId(for: current.environment) == current.id else {
                throw AppError.decoding
            }
            guard revision(for: current.environment) >= 0 else { throw AppError.decoding }
        }
        if let paperAccountId {
            guard !paperAccountId.isEmpty, paperRevision >= 0 else { throw AppError.decoding }
        }
        if let liveAccountId {
            guard !liveAccountId.isEmpty, liveRevision >= 0 else { throw AppError.decoding }
        }
        if let ownerUserId {
            guard !ownerUserId.isEmpty else { throw AppError.decoding }
        }
    }
}
