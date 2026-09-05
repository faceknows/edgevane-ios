import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var isSignedIn = false
    @Published private(set) var isRestoringSession = false
    @Published private(set) var user: AppUser?

    let cleanup = LogoutCleanup()

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

    func applySignIn(_ session: AuthSessionDTO) {
        guard let dto = session.user else { return }
        persist(tokens: tokens(from: session), user: AppUser(dto: dto))
        AppLog.session.info("signed in")
    }

    func signOut() {
        keychain.delete(account: Account.access)
        keychain.delete(account: Account.refresh)
        keychain.delete(account: Account.expiry)
        disk.delete(name: userFile)
        user = nil
        isSignedIn = false
        cleanup.run()
        AppLog.session.info("signed out")
    }

    func restoreIfNeeded() async throws {
        guard isRestoringSession else { return }
        defer { isRestoringSession = false }
        try await refresh()
    }

    func refresh() async throws {
        guard let refreshToken = keychain.string(account: Account.refresh), !refreshToken.isEmpty else {
            signOut()
            throw AppError.http(status: 401, message: nil, errorCode: nil)
        }
        do {
            let session = try await refreshSession(refreshToken)
            let nextUser = session.user.map(AppUser.init(dto:)) ?? user
            persist(tokens: tokens(from: session), user: nextUser)
        } catch let error as AppError where error.isUnauthorized {
            signOut()
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
            clearStoredSession()
            return
        }
        isRestoringSession = true
    }

    private func persist(tokens: SessionTokens, user: AppUser?) {
        try? keychain.set(tokens.accessToken, account: Account.access)
        if let refresh = tokens.refreshToken, !refresh.isEmpty {
            try? keychain.set(refresh, account: Account.refresh)
        }
        try? keychain.set(String(tokens.expiresAt.timeIntervalSince1970), account: Account.expiry)
        if let user {
            disk.write(user, name: userFile)
        }
        self.user = user
        isSignedIn = true
    }

    private func tokens(from session: AuthSessionDTO) -> SessionTokens {
        SessionTokens(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken ?? keychain.string(account: Account.refresh),
            expiresAt: SessionTime.date(fromExpiresAt: session.expiresAt)
        )
    }

    private func clearStoredSession() {
        keychain.delete(account: Account.access)
        keychain.delete(account: Account.refresh)
        keychain.delete(account: Account.expiry)
        disk.delete(name: userFile)
        user = nil
        isSignedIn = false
        isRestoringSession = false
    }
}
