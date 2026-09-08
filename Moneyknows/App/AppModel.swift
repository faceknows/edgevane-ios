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
    let insights: InsightsStore
    let news: NewsStore
    let notifications: NotificationStore
    let push: PushRegistration
    let router: AppRouter
    private let ibkrSocket: GatewaySocket
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
        insights = InsightsStore(api: AIAPI(client: authorized))
        news = NewsStore()
        notifications = NotificationStore(api: PushAPI(client: authorized))
        push = PushRegistration(
            api: PushAPI(client: authorized),
            publicClient: publicClient,
            preference: pushPreference,
            tokens: InboxPushTokenProvider(),
            credentials: KeychainStore(service: "com.byteknows.moneyknows.session")
        )
        router = AppRouter()
        ibkrSocket = GatewaySocket(namespace: "/ibkr-stream")
        push.isSessionActive = { [weak self] in self?.session.isSignedIn == true }
        push.currentUserId = { [weak self] in self?.session.user?.id }
        push.allowsRegistration = false
        push.startNetworkRecovery()
        bindTradingHooks()
        bindNewsHooks()
        bindPushHooks()
        session.willClearSession = { [weak self] in
            guard let self else { return }
            self.push.unregisterBestEffort(
                accessToken: self.session.accessToken,
                userId: self.session.user?.id
            )
        }
        session.didDropSignedInSession = { [weak self] in
            self?.router.clearPending()
        }
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
            router?.setViewingNotifications(false)
        }
        session.cleanup.register { [weak insights] in
            insights?.reset()
        }
        session.cleanup.register { [weak news] in
            news?.reset()
        }
        session.cleanup.register { [weak notifications] in
            notifications?.reset()
        }
        session.cleanup.register { [weak ibkrSocket] in
            ibkrSocket?.disconnect()
        }
        session.runCleanupIfInactive()
    }

    func start() async {
        Task { await push.retryPendingDeletes() }
        await versionGate.check()
        if case .passed = versionGate.state {
            push.allowsRegistration = true
            do {
                try await session.restoreIfNeeded()
            } catch {
                AppLog.session.error("session restore failed")
            }
            if session.isSignedIn {
                await loadSignedInData()
            }
        }
        consumeLaunchNotification()
    }

    func didSignIn(_ dto: AuthSessionDTO) throws {
        try session.applySignIn(dto)
        Task {
            await loadSignedInData()
            consumeLaunchNotification()
        }
    }

    func loadSignedInData() async {
        guard session.isSignedIn else { return }
        let generation = session.generation
        connectStreams()
        Task { await realtime.refreshSubscriptions() }
        if let userId = session.user?.id {
            prepareSignedInUser(userId)
        }
        syncTrading()
        applyTradingForeground()

        if let userId = session.user?.id {
            preferences.prepareForUser(userId)
            async let prefs: Void = preferences.refresh(userId: userId)
            async let role: Void = profile.refresh()
            _ = await (prefs, role)
            guard session.generation == generation, session.isSignedIn else { return }
            if let userId = session.user?.id {
                prepareSignedInUser(userId)
            }
            await finishSignedInLaunch()
            consumeLaunchNotification()
            return
        }

        await profile.refreshIdentity()
        guard session.generation == generation, session.isSignedIn, let userId = session.user?.id else {
            return
        }
        prepareSignedInUser(userId)
        syncTrading()
        applyTradingForeground()
        preferences.prepareForUser(userId)
        async let prefs: Void = preferences.refresh(userId: userId)
        async let role: Void = profile.refreshRoleConfiguration()
        _ = await (prefs, role)
        guard session.generation == generation, session.isSignedIn else { return }
        await finishSignedInLaunch()
        consumeLaunchNotification()
    }

    func ensureRealtimeConnected() {
        Task { await push.retryIfNeeded() }
        guard session.isSignedIn else { return }
        connectStreams()
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
        news.isForeground = foreground
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
        realtime.onNews = { [weak news] data in
            news?.ingest(data, source: .alpaca)
        }
        trading.onEntryFill = { [weak autoExit] order in
            autoExit?.scheduleFill(order)
        }
        trading.onReset = { [weak autoExit] in
            autoExit?.reset()
        }
    }

    private func bindNewsHooks() {
        ibkrSocket.on(MarketStreamEvent.news) { [weak news] data in
            news?.ingest(data, source: .ibkr)
        }
    }

    private func bindPushHooks() {
        PushInbox.shared.onToken = { [weak self] token in
            guard let self else { return }
            Task {
                await self.push.handleTokenRefresh(token, signedIn: self.session.isSignedIn)
            }
        }
        PushInbox.shared.onForeground = { [weak self] item in
            guard let self else { return }
            guard self.session.isSignedIn, self.pushPreference.isEnabled else { return }
            self.notifications.ingest(
                item,
                showToast: true,
                volumeThreshold: self.preferences.values.notificationVolumeThreshold,
                userId: self.session.user?.id
            )
        }
        PushInbox.shared.onOpen = { [weak self] item in
            guard let self else { return }
            if self.session.isSignedIn, self.pushPreference.isEnabled {
                self.notifications.ingest(
                    item,
                    showToast: false,
                    volumeThreshold: self.preferences.values.notificationVolumeThreshold,
                    userId: self.session.user?.id
                )
            }
            self.router.handleNotification(
                item,
                versionPassed: self.versionGate.state == .passed,
                signedIn: self.session.isSignedIn,
                currentUserId: self.session.user?.id,
                alreadyShowingHistory: self.router.isShowingNotificationHistory
            )
        }
        pushPreference.onEnabledChange = { [weak self] enabled in
            guard let self else { return }
            Task {
                await self.push.syncEnabled(enabled, signedIn: self.session.isSignedIn)
            }
        }
    }

    private func finishSignedInLaunch() async {
        guard session.isSignedIn else { return }
        await push.registerIfNeeded()
    }

    private func prepareSignedInUser(_ userId: String) {
        brokerage.prepareForUser(userId)
        blacklist.prepareForUser(userId)
        notifications.activate(userId: userId)
    }

    private func consumeLaunchNotification() {
        if let open = PushInbox.shared.consumePendingOpen() {
            router.handleNotification(
                open,
                versionPassed: versionGate.state == .passed,
                signedIn: session.isSignedIn,
                currentUserId: session.user?.id
            )
            return
        }
        router.consumePending(
            versionPassed: versionGate.state == .passed,
            signedIn: session.isSignedIn,
            currentUserId: session.user?.id
        )
    }

    private func connectStreams() {
        news.activate()
        if let userId = session.user?.id {
            notifications.activate(userId: userId)
        }
        realtime.connect(token: session.accessToken)
        connectIBKR()
    }

    private func connectIBKR() {
        guard let token = session.accessToken, !token.isEmpty else {
            ibkrSocket.disconnect()
            return
        }
        ibkrSocket.connect(token: token)
    }
}
