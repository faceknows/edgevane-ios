import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var isSignedIn = false
    @Published private(set) var isRestoringSession = false
    @Published private(set) var user: AppUser?
    @Published private(set) var generation: UInt64 = 0

    let cleanup = LogoutCleanup()
    var willClearSession: (() -> Void)? {
        didSet { flushStartupClearIfPossible() }
    }
    var didDropSignedInSession: (() -> Void)?

    private let keychain: CredentialStoring
    private let disk: DiskStore
    private let refreshSession: (String) async throws -> AuthSessionDTO
    private let refreshSkew: TimeInterval = 5 * 60

    private enum Account {
        static let access = "session.accessToken"
        static let refresh = "session.refreshToken"
        static let expiry = "session.expiresAt"
    }

    private let userFile = "session-user.json"
    private var pendingStartupClearReason: String?

    init(
        keychain: CredentialStoring,
        disk: DiskStore,
        refreshSession: @escaping (String) async throws -> AuthSessionDTO
    ) {
        self.keychain = keychain
        self.disk = disk
        self.refreshSession = refreshSession
        prepareRestoration()
    }

    var accessToken: String? {
        keychain.string(account: Account.access)
    }

    func applySignIn(_ session: AuthSessionDTO) throws {
        guard let dto = session.user else { return }
        try persist(tokens: tokens(from: session), user: AppUser(dto: dto))
        generation += 1
        AppLog.session.info("signed in")
    }

    func applyUser(_ user: AppUser) {
        if let current = self.user, current.id != user.id {
            AppLog.session.error("ignored profile for a different user")
            return
        }
        disk.write(user, name: userFile)
        self.user = user
    }

    func signOut() {
        clearSession(reason: "signed out")
    }

    func runCleanupIfInactive() {
        guard !isSignedIn, !isRestoringSession else { return }
        cleanup.run()
    }

    func restoreIfNeeded() async throws {
        guard isRestoringSession else { return }
        let generation = self.generation
        defer { isRestoringSession = false }
        do {
            try await refresh()
        } catch {
            if self.generation == generation, !isSignedIn {
                clearSession(reason: "session restore failed")
            }
            throw error
        }
    }

    func refresh() async throws {
        let generation = self.generation
        guard isSignedIn || isRestoringSession else {
            throw AppError.cancelled
        }
        guard let refreshToken = keychain.string(account: Account.refresh), !refreshToken.isEmpty else {
            if generation == self.generation {
                signOut()
            }
            throw AppError.http(status: 401, message: nil, errorCode: nil)
        }
        do {
            let session = try await refreshSession(refreshToken)
            guard generation == self.generation else {
                throw AppError.cancelled
            }
            let nextUser = session.user.map(AppUser.init(dto:)) ?? user
            try persist(tokens: tokens(from: session), user: nextUser)
        } catch let error as AppError where error.isUnauthorized {
            if generation == self.generation {
                signOut()
            }
            throw error
        } catch {
            if !error.isCancellation,
               generation == self.generation,
               accessToken == nil || accessToken?.isEmpty == true
            {
                clearSession(reason: "session persist failed")
            }
            throw error
        }
    }

    private var needsRefresh: Bool {
        guard let raw = keychain.string(account: Account.expiry), let interval = TimeInterval(raw) else {
            return true
        }
        return Date() >= Date(timeIntervalSince1970: interval) - refreshSkew
    }

    private func prepareRestoration() {
        guard let token = accessToken, !token.isEmpty else { return }
        user = disk.read(AppUser.self, name: userFile)

        guard needsRefresh else {
            isSignedIn = true
            return
        }

        guard let refreshToken = keychain.string(account: Account.refresh), !refreshToken.isEmpty else {
            scheduleStartupClear(reason: "expired session without refresh")
            return
        }
        isRestoringSession = true
    }

    private func scheduleStartupClear(reason: String) {
        pendingStartupClearReason = reason
        user = nil
        isSignedIn = false
        isRestoringSession = false
        flushStartupClearIfPossible()
    }

    private func flushStartupClearIfPossible() {
        guard willClearSession != nil, let reason = pendingStartupClearReason else { return }
        pendingStartupClearReason = nil
        if user == nil {
            user = disk.read(AppUser.self, name: userFile)
        }
        clearSession(reason: reason)
    }

    private func persist(tokens: SessionTokens, user: AppUser?) throws {
        let previousAccess = keychain.string(account: Account.access)
        let previousRefresh = keychain.string(account: Account.refresh)
        let previousExpiry = keychain.string(account: Account.expiry)
        do {
            try keychain.set(tokens.accessToken, account: Account.access)
            if let refresh = tokens.refreshToken, !refresh.isEmpty {
                try keychain.set(refresh, account: Account.refresh)
            }
            try keychain.set(String(tokens.expiresAt.timeIntervalSince1970), account: Account.expiry)
            guard keychain.string(account: Account.access) == tokens.accessToken else {
                throw AppError.decoding
            }
        } catch {
            restoreSessionTokens(
                access: previousAccess,
                refresh: previousRefresh,
                expiry: previousExpiry
            )
            throw error
        }
        if let user {
            disk.write(user, name: userFile)
        }
        self.user = user
        isSignedIn = true
    }

    private func restoreSessionTokens(access: String?, refresh: String?, expiry: String?) {
        do {
            try writeSessionToken(access, account: Account.access)
            try writeSessionToken(refresh, account: Account.refresh)
            try writeSessionToken(expiry, account: Account.expiry)
            guard keychain.string(account: Account.access) == access,
                  keychain.string(account: Account.refresh) == refresh,
                  keychain.string(account: Account.expiry) == expiry
            else {
                throw AppError.decoding
            }
        } catch {
            keychain.delete(account: Account.access)
            keychain.delete(account: Account.refresh)
            keychain.delete(account: Account.expiry)
        }
    }

    private func writeSessionToken(_ value: String?, account: String) throws {
        if let value {
            try keychain.set(value, account: account)
        } else {
            keychain.delete(account: account)
        }
    }

    private func tokens(from session: AuthSessionDTO) -> SessionTokens {
        SessionTokens(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken ?? keychain.string(account: Account.refresh),
            expiresAt: SessionTime.date(fromExpiresAt: session.expiresAt)
        )
    }

    private func clearSession(reason: String) {
        let dropSignedInRoutes = !isRestoringSession
        generation += 1
        willClearSession?()
        keychain.delete(account: Account.access)
        keychain.delete(account: Account.refresh)
        keychain.delete(account: Account.expiry)
        disk.delete(name: userFile)
        user = nil
        isSignedIn = false
        isRestoringSession = false
        cleanup.run()
        if dropSignedInRoutes {
            didDropSignedInSession?()
        }
        AppLog.session.info("\(reason, privacy: .public)")
    }
}
