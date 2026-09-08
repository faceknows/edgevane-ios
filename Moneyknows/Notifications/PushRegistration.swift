import Foundation
import Network

protocol PushTokenProviding: AnyObject {
    func currentToken() async -> String?
}

@MainActor
final class PushInbox {
    static let shared = PushInbox()

    var token: String?
    var onToken: ((String) -> Void)?
    var onForeground: ((AppNotification) -> Void)?
    var onOpen: ((AppNotification) -> Void)?
    private var pendingOpen: AppNotification?

    func setToken(_ token: String) {
        self.token = token
        onToken?(token)
    }

    func receiveForeground(_ notification: AppNotification) {
        if let onForeground {
            onForeground(notification)
        }
    }

    func receiveOpen(_ notification: AppNotification) {
        if let onOpen {
            onOpen(notification)
        } else {
            pendingOpen = notification
        }
    }

    func consumePendingOpen() -> AppNotification? {
        let value = pendingOpen
        pendingOpen = nil
        return value
    }
}

@MainActor
final class InboxPushTokenProvider: PushTokenProviding {
    func currentToken() async -> String? {
        PushInbox.shared.token
    }
}

@MainActor
final class FakePushTokenProvider: PushTokenProviding {
    var token: String?

    init(token: String? = "test-fcm-token") {
        self.token = token
    }

    func currentToken() async -> String? {
        token
    }
}

@MainActor
final class PushRegistration {
    private(set) var isRegistered = false
    var isSessionActive: () -> Bool = { true }
    var currentUserId: () -> String? = { nil }
    var allowsRegistration = true

    private let api: PushAPI
    private let publicClient: HTTPSending
    private let preference: PushPreferenceStore
    private let tokens: PushTokenProviding
    private let credentials: CredentialStoring?
    private var lastToken: String?
    private var registeredToken: String?
    private var registeredUserId: String?
    private var desiredRegistered = false
    private var pendingDeletes: [PendingDelete] = []
    private var pendingDeletesPersistFailed = false
    private var chain: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var pathWasSatisfied = true
    private var retryTask: Task<Void, Never>?
    private var retryAttempt = 0
    var retryDelayNanoseconds: (Int) -> UInt64 = { attempt in
        let shift = UInt64(min(max(attempt, 0), 5))
        return min(30_000_000_000, UInt64(1_000_000_000) << shift)
    }
    var waitForRetry: (UInt64) async -> Void = { nanoseconds in
        guard nanoseconds > 0 else { return }
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    init(
        api: PushAPI,
        publicClient: HTTPSending,
        preference: PushPreferenceStore,
        tokens: PushTokenProviding,
        credentials: CredentialStoring? = nil
    ) {
        self.api = api
        self.publicClient = publicClient
        self.preference = preference
        self.tokens = tokens
        self.credentials = credentials
        pendingDeletes = Self.readPendingDeletes(from: credentials)
        lastToken = credentials?.string(account: Self.lastTokenAccount)
        if lastToken?.isEmpty == true {
            lastToken = nil
        }
    }

    func startNetworkRecovery() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        pathWasSatisfied = true
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let recovered = satisfied && !self.pathWasSatisfied
                self.pathWasSatisfied = satisfied
                if recovered {
                    await self.retryIfNeeded()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "moneyknows.push.path"))
    }

    func registerIfNeeded() async {
        guard allowsRegistration else { return }
        guard isSessionActive() else {
            desiredRegistered = false
            await enqueueSync()
            return
        }
        guard preference.isEnabled else {
            desiredRegistered = false
            await enqueueSync()
            return
        }
        guard await preference.prepareForPush() else {
            guard isSessionActive(), preference.isEnabled else {
                desiredRegistered = false
                await enqueueSync()
                return
            }
            return
        }
        guard isSessionActive() else {
            desiredRegistered = false
            await enqueueSync()
            return
        }
        preference.armRemoteNotifications()
        let token = await tokens.currentToken() ?? lastToken ?? PushInbox.shared.token
        guard let token, !token.isEmpty else { return }
        rememberToken(token)
        desiredRegistered = true
        await enqueueSync()
    }

    func retryPendingDeletes() async {
        if pendingDeletesPersistFailed {
            persistPendingDeletes()
        }
        guard !pendingDeletes.isEmpty || pendingDeletesPersistFailed else { return }
        await enqueueSync()
    }

    func retryIfNeeded() async {
        if pendingDeletesPersistFailed {
            persistPendingDeletes()
        }
        if !pendingDeletes.isEmpty || pendingDeletesPersistFailed {
            await enqueueSync()
        }
        guard allowsRegistration else { return }
        guard isSessionActive() else { return }
        if desiredRegistered, needsRegister(token: lastToken, userId: currentUserId()) {
            await enqueueSync()
            return
        }
        if preference.isEnabled {
            await registerIfNeeded()
        }
    }

    func syncEnabled(_ enabled: Bool, signedIn: Bool) async {
        if enabled, signedIn {
            await registerIfNeeded()
            return
        }
        if !enabled {
            await unregister()
        }
    }

    func handleTokenRefresh(_ token: String, signedIn: Bool) async {
        rememberToken(token)
        guard allowsRegistration, signedIn, isSessionActive(), preference.isEnabled else {
            await enqueueSync()
            return
        }
        if let old = registeredToken, old != token {
            enqueueDelete(token: old, accessToken: nil, userId: currentUserId())
        }
        desiredRegistered = true
        await enqueueSync()
    }

    func unregister() async {
        desiredRegistered = false
        if let token = registeredToken ?? lastToken ?? PushInbox.shared.token {
            enqueueDelete(token: token, accessToken: nil, userId: currentUserId())
        }
        await enqueueSync()
    }

    func unregisterBestEffort(accessToken: String?, userId: String? = nil) {
        desiredRegistered = false
        let token = registeredToken ?? lastToken ?? PushInbox.shared.token ?? ""
        enqueueDelete(token: token, accessToken: accessToken, userId: userId)
        let previous = chain
        let task = Task { @MainActor in
            await previous?.value
            await self.syncToDesired()
        }
        chain = task
    }

    private func enqueueDelete(token: String, accessToken: String?, userId: String?) {
        if token.isEmpty, accessToken?.isEmpty != false {
            return
        }
        if let index = pendingDeletes.firstIndex(where: { $0.token == token && $0.userId == userId }) {
            if let accessToken, !accessToken.isEmpty {
                pendingDeletes[index].accessToken = accessToken
                persistPendingDeletes()
            }
            return
        }
        pendingDeletes.append(PendingDelete(token: token, accessToken: accessToken, userId: userId))
        persistPendingDeletes()
    }

    private func needsRegister(token: String?, userId: String?) -> Bool {
        guard let token, !token.isEmpty else { return false }
        return registeredToken != token || registeredUserId != userId
    }

    private func enqueueSync() async {
        let previous = chain
        let task = Task { @MainActor in
            await previous?.value
            await self.syncToDesired()
        }
        chain = task
        await task.value
    }

    private func syncToDesired() async {
        var skippedDeleteIdentities: Set<String> = []
        while true {
            if desiredRegistered, !isSessionActive() {
                desiredRegistered = false
            }
            if pendingDeletesPersistFailed {
                persistPendingDeletes()
            }

            dropSkippedPendingDeletes()

            if let pendingIndex = firstAttemptableDeleteIndex(excluding: skippedDeleteIdentities) {
                let pending = pendingDeletes[pendingIndex]
                do {
                    try await deleteToken(pending)
                    pendingDeletes.remove(at: pendingIndex)
                    persistPendingDeletes()
                    if skippedDeleteIdentities.isEmpty {
                        resetRetry()
                    }
                    if registeredToken == pending.token,
                       pending.token.isEmpty == false,
                       pending.userId == registeredUserId
                    {
                        registeredToken = nil
                        registeredUserId = nil
                        isRegistered = false
                    }
                    AppLog.push.info("fcm token unregistered")
                } catch {
                    if error.isUnauthorized, pending.accessToken?.isEmpty == false {
                        pendingDeletes[pendingIndex].accessToken = nil
                        persistPendingDeletes()
                        continue
                    }
                    if error.isCancellation { return }
                    AppLog.push.error("fcm unregister failed")
                    skippedDeleteIdentities.insert(pending.identity)
                    scheduleRetry()
                }
                continue
            }

            if desiredRegistered {
                guard let token = lastToken ?? PushInbox.shared.token, !token.isEmpty else { return }
                let userId = currentUserId()
                if needsRegister(token: token, userId: userId) {
                    do {
                        try await api.register(token: token, deviceId: token)
                        let stillCurrent = desiredRegistered
                            && isSessionActive()
                            && currentUserId() == userId
                            && lastToken == token
                        if !stillCurrent {
                            enqueueDelete(token: token, accessToken: nil, userId: userId)
                            continue
                        }
                        isRegistered = true
                        registeredToken = token
                        registeredUserId = userId
                        pendingDeletes.removeAll {
                            $0.token == token && (
                                $0.userId == userId
                                || ($0.userId == nil && ($0.accessToken == nil || $0.accessToken?.isEmpty == true))
                            )
                        }
                        persistPendingDeletes()
                        if skippedDeleteIdentities.isEmpty {
                            resetRetry()
                        }
                        AppLog.push.info("fcm token registered")
                    } catch {
                        if error.isCancellation { return }
                        if needsRegister(token: token, userId: userId) {
                            isRegistered = false
                        }
                        AppLog.push.error("fcm register failed")
                        scheduleRetry()
                        return
                    }
                    continue
                }
            }

            if !skippedDeleteIdentities.isEmpty {
                return
            }
            if pendingDeletes.contains(where: { !$0.token.isEmpty || $0.accessToken?.isEmpty == false }) {
                return
            }
            if !desiredRegistered {
                if let token = registeredToken {
                    enqueueDelete(token: token, accessToken: nil, userId: registeredUserId)
                    continue
                }
                isRegistered = false
                registeredUserId = nil
                resetRetry()
                return
            }
            isRegistered = registeredToken != nil
            resetRetry()
            return
        }
    }

    private func rememberToken(_ token: String) {
        guard !token.isEmpty else { return }
        lastToken = token
        PushInbox.shared.token = token
        fillEmptyPendingTokens(token)
        persistLastToken()
    }

    private func fillEmptyPendingTokens(_ token: String) {
        var changed = false
        for index in pendingDeletes.indices where pendingDeletes[index].token.isEmpty {
            pendingDeletes[index].token = token
            changed = true
        }
        if changed {
            persistPendingDeletes()
        }
    }

    private func persistLastToken() {
        guard let credentials else { return }
        if let lastToken, !lastToken.isEmpty {
            try? credentials.set(lastToken, account: Self.lastTokenAccount)
        }
    }

    private func dropSkippedPendingDeletes() {
        let remaining = pendingDeletes.filter { !shouldSkipPendingDelete($0) }
        guard remaining.count != pendingDeletes.count else { return }
        pendingDeletes = remaining
        persistPendingDeletes()
    }

    private func firstAttemptableDeleteIndex(excluding skipped: Set<String> = []) -> Int? {
        pendingDeletes.firstIndex {
            canAttemptDelete($0) && !shouldSkipPendingDelete($0) && !skipped.contains($0.identity)
        }
    }

    private func canAttemptDelete(_ pending: PendingDelete) -> Bool {
        guard !pending.token.isEmpty else { return false }
        if let access = pending.accessToken, !access.isEmpty {
            return true
        }
        guard isSessionActive() else { return false }
        if let owner = pending.userId {
            return owner == currentUserId()
        }
        if let current = currentUserId(), current == registeredUserId, pending.token == registeredToken {
            return false
        }
        if registeredUserId != nil, currentUserId() != nil, registeredUserId != currentUserId() {
            return false
        }
        return currentUserId() == nil || currentUserId() == registeredUserId
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        let delay = retryDelayNanoseconds(retryAttempt)
        retryAttempt = min(retryAttempt + 1, 8)
        retryTask = Task { @MainActor in
            await self.waitForRetry(delay)
            guard !Task.isCancelled else { return }
            await self.retryIfNeeded()
        }
    }

    private func resetRetry() {
        retryAttempt = 0
        retryTask?.cancel()
        retryTask = nil
    }

    private func persistPendingDeletes() {
        guard let credentials else { return }
        do {
            try writePendingDeletes(to: credentials)
            pendingDeletesPersistFailed = false
        } catch {
            pendingDeletesPersistFailed = true
            AppLog.push.error("pending deletes persist failed")
            if retryTask == nil {
                scheduleRetry()
            }
        }
    }

    private func writePendingDeletes(to credentials: CredentialStoring) throws {
        if pendingDeletes.isEmpty {
            try credentials.deleteChecked(account: Self.pendingDeletesAccount)
            return
        }
        let data: Data
        do {
            data = try JSONEncoder().encode(pendingDeletes)
        } catch {
            throw AppError.decoding
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw AppError.decoding
        }
        try credentials.set(text, account: Self.pendingDeletesAccount)
        guard credentials.string(account: Self.pendingDeletesAccount) == text else {
            throw AppError.decoding
        }
    }

    private func deleteToken(_ pending: PendingDelete) async throws {
        guard !pending.token.isEmpty else { return }
        if let access = pending.accessToken, !access.isEmpty {
            try await PublicAuthorizedPushAPI(client: publicClient, accessToken: access).unregister(token: pending.token)
        } else {
            try await api.unregister(token: pending.token)
        }
    }

    private static func readPendingDeletes(from credentials: CredentialStoring?) -> [PendingDelete] {
        guard let raw = credentials?.string(account: pendingDeletesAccount),
              let data = raw.data(using: .utf8),
              let items = try? JSONDecoder().decode([PendingDelete].self, from: data)
        else { return [] }
        return items.filter { !$0.token.isEmpty || $0.accessToken?.isEmpty == false }
    }

    private static let pendingDeletesAccount = "push.pendingDeletes"
    private static let lastTokenAccount = "push.lastFcmToken"

    private func shouldSkipPendingDelete(_ pending: PendingDelete) -> Bool {
        guard desiredRegistered, !pending.token.isEmpty, pending.token == registeredToken else {
            return false
        }
        if let lastToken, lastToken != registeredToken {
            return false
        }
        if let owner = pending.userId {
            return owner == registeredUserId && owner == currentUserId()
        }
        return pending.accessToken == nil || pending.accessToken?.isEmpty == true
    }
}

private struct PendingDelete: Codable {
    var token: String
    var accessToken: String?
    var userId: String?

    var identity: String {
        "\(token)|\(userId ?? "")|\(accessToken ?? "")"
    }
}
