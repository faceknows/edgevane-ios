import Foundation

@MainActor
final class AppModel: ObservableObject {
    let session: SessionStore
    let versionGate: VersionGateModel
    let publicClient: HTTPClient
    let authAPI: AuthAPI

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
    }

    func start() async {
        await versionGate.check()
        guard case .passed = versionGate.state else { return }
        do {
            try await session.restoreIfNeeded()
        } catch {
            AppLog.session.error("session restore failed")
        }
    }
}
