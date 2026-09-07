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
    let screeners: ScreenerStore
    let summaries: SymbolSummaryStore
    let bars: BarStore
    let realtime: MarketRealtimeSession
    let trading: TradingSession
    let autoExit: AutoExit
    let router: AppRouter
    private var isTradingForeground = false

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
        if let userId = session.user?.id {
            brokerage.prepareForUser(userId)
            blacklist.prepareForUser(userId)
        }
        profile = ProfileStore(api: userAPI, session: session)
        pushPreference = PushPreferenceStore()
        let screenerAPI = ScreenerAPI(client: authorized)
        screeners = ScreenerStore(api: screenerAPI)
        summaries = SymbolSummaryStore(api: screenerAPI)
        bars = BarStore(api: BarsAPI(client: authorized))
        let gatewayClient = HTTPClient(
            baseURL: AppEnvironment.socketHost,
            defaultHeaders: HTTPClient.appHeaders(),
            session: URLSession(configuration: sessionConfig),
            logsRequests: AppEnvironment.enableLogging,
            timeout: AppEnvironment.apiTimeout
        )
        let gatewayAuthorized = AuthorizedSession(client: gatewayClient, session: session)
        realtime = MarketRealtimeSession(
            subscriptions: SubscriptionStore(api: SubscribeAPI(client: gatewayAuthorized)),
            quotes: QuoteStore(),
            seconds: SecondBarStore(),
            socket: GatewaySocket(),
            barsAPI: BarsAPI(client: authorized)
        )
        trading = TradingSession()
        autoExit = AutoExit()
        router = AppRouter()
        bindTradingHooks()
        session.cleanup.register { [weak brokerage] in
            do {
                try brokerage?.clearAll()
            } catch {
                AppLog.brokerage.error("clear brokerage on logout failed")
            }
        }
        session.cleanup.register { [weak profile] in
            profile?.reset()
        }
        session.cleanup.register { [weak preferences] in
            preferences?.markSessionStale()
        }
        session.cleanup.register { [weak screeners] in
            screeners?.reset()
        }
        session.cleanup.register { [weak summaries] in
            summaries?.reset()
        }
        session.cleanup.register { [weak bars] in
            bars?.reset()
        }
        session.cleanup.register { [weak realtime] in
            realtime?.reset()
        }
        session.cleanup.register { [weak blacklist] in
            blacklist?.resetSession()
        }
        session.cleanup.register { [weak trading, weak autoExit] in
            autoExit?.reset()
            trading?.reset()
        }
        session.cleanup.register { [weak router] in
            router?.dismissOverlay()
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
        realtime.connect(token: session.accessToken)
        Task { await realtime.refreshSubscriptions() }
        if let userId = session.user?.id {
            brokerage.prepareForUser(userId)
            blacklist.prepareForUser(userId)
        }
        syncTrading()
        applyTradingForeground()

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
        brokerage.prepareForUser(userId)
        blacklist.prepareForUser(userId)
        syncTrading()
        applyTradingForeground()
        preferences.prepareForUser(userId)
        await preferences.refresh(userId: userId)
    }

    func ensureRealtimeConnected() {
        guard session.isSignedIn else { return }
        realtime.connect(token: session.accessToken)
    }

    func syncTrading() {
        guard session.isSignedIn,
              let account = brokerage.current,
              let credentials = brokerage.credentials(for: account.environment)
        else {
            trading.use(nil)
            return
        }
        trading.use(
            AlpacaBrokerage(
                account: account,
                key: credentials.key,
                secret: credentials.secret
            )
        )
    }

    func setTradingForeground(_ foreground: Bool) {
        isTradingForeground = foreground
        brokerage.setForeground(foreground)
        applyTradingForeground()
    }

    private func applyTradingForeground() {
        guard isTradingForeground, session.isSignedIn else {
            trading.setForeground(false)
            return
        }
        trading.setForeground(true)
    }

    private func bindTradingHooks() {
        autoExit.trading = trading
        autoExit.takeProfitPercent = { [weak preferences] in
            preferences?.values.autoTakeProfitPercent ?? 0
        }
        autoExit.stopLossPercent = { [weak preferences] in
            preferences?.values.autoStopLossPercent ?? 0
        }
        autoExit.protectionMinutes = { [weak preferences] in
            preferences?.values.allowTradeInMinutesAfterOpen ?? UserPreferences.defaults.allowTradeInMinutesAfterOpen
        }
        autoExit.maxOrderValue = { [weak profile] in
            profile?.roleConfiguration?.maxOrderValue
        }
        autoExit.isTakeProfitBlocked = { [weak blacklist] symbol in
            blacklist?.isTakeProfitBlocked(symbol) ?? false
        }
        autoExit.isStopLossBlocked = { [weak blacklist] symbol in
            blacklist?.isStopLossBlocked(symbol) ?? false
        }
        realtime.onTradeUpdate = { [weak trading] data in
            trading?.applyStreamData(data)
        }
        trading.onEntryFill = { [weak autoExit] order in
            autoExit?.scheduleFill(order)
        }
        trading.onReset = { [weak autoExit] in
            autoExit?.reset()
        }
    }
}
