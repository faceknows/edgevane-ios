import Foundation

@MainActor
final class AppModel: ObservableObject {
    let session: SessionStore
    let versionGate: VersionGateModel
    let publicClient: HTTPClient
    let authAPI: AuthAPI
    let authorized: AuthorizedSession
    let userAPI: UserAPI
    let preferences: PreferencesStore
    let appearance: AppearanceStore
    let blacklist: AutoExitBlacklistStore
    let brokerage: CurrentBrokerageStore
    let profile: ProfileStore
    let pushPreference: PushPreferenceStore

    init() {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = AppEnvironment.apiTimeout
        sessionConfig.timeoutIntervalForResource = AppEnvironment.apiTimeout * 2
        let publicClient = HTTPClient(
            baseURL: AppEnvironment.apiURL,
            defaultHeaders: HTTPClient.appHeaders(),
            session: URLSession(configuration: sessionConfig),
            logsRequests: AppEnvironment.enableLogging,
            timeout: AppEnvironment.apiTimeout
        )
        let authAPI = AuthAPI(client: publicClient)
        self.publicClient = publicClient
        self.authAPI = authAPI
        session = SessionStore(
            keychain: KeychainStore(service: "com.byteknows.moneyknows.session"),
            disk: DiskStore(),
            refreshSession: authAPI.refresh(refreshToken:)
        )
        versionGate = VersionGateModel(api: VersionAPI(client: publicClient))
        authorized = AuthorizedSession(client: publicClient, session: session)
        userAPI = UserAPI(client: authorized)
        preferences = PreferencesStore(api: PreferencesAPI(client: authorized))
        appearance = AppearanceStore()
        blacklist = AutoExitBlacklistStore()
        brokerage = CurrentBrokerageStore()
        profile = ProfileStore(api: userAPI, session: session)
        pushPreference = PushPreferenceStore()
        session.cleanup.register { [weak brokerage] in
            brokerage?.clearAll()
        }
        session.cleanup.register { [weak profile] in
            profile?.reset()
        }
        session.cleanup.register { [weak preferences] in
            preferences?.markSessionStale()
        }
        session.runCleanupIfInactive()
    }

    func start() async {
        await versionGate.check()
        guard case .passed = versionGate.state else { return }
        do {
            try await session.restoreIfNeeded()
        } catch {
            AppLog.session.error("session restore failed")
        }
        if session.isSignedIn {
            await loadSignedInData()
        }
    }

    func didSignIn(_ dto: AuthSessionDTO) throws {
        try session.applySignIn(dto)
        Task { await loadSignedInData() }
    }

    func loadSignedInData() async {
        guard session.isSignedIn else { return }
        let generation = session.generation

        if let userId = session.user?.id {
            preferences.prepareForUser(userId)
            async let prefs: Void = preferences.refresh(userId: userId)
            async let role: Void = profile.refresh()
            _ = await (prefs, role)
            return
        }

        await profile.refresh()
        guard session.generation == generation, session.isSignedIn, let userId = session.user?.id else {
            return
        }
        preferences.prepareForUser(userId)
        await preferences.refresh(userId: userId)
    }
}
