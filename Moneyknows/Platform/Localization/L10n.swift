import Foundation

enum L10n {
    private static var bundle: Bundle = .main

    static func string(_ key: String) -> String {
        localized(key)
    }

    static func apply(localeCode: String?) {
        switch localeCode {
        case "en":
            bundle = localizationBundle(code: "en") ?? .main
        case "zh":
            bundle = localizationBundle(code: "zh-Hans") ?? .main
        default:
            bundle = .main
        }
    }

    enum Common {
        static var retry: String { localized("common.retry") }
        static var cancel: String { localized("common.cancel") }
        static var confirm: String { localized("common.confirm") }
        static var done: String { localized("common.done") }
        static var close: String { localized("common.close") }
        static var next: String { localized("common.next") }
        static var save: String { localized("common.save") }
        static var logout: String { localized("common.logout") }
        static var enabled: String { localized("common.enabled") }
        static var disabled: String { localized("common.disabled") }
        static var language: String { localized("common.language") }
        static var followSystem: String { localized("common.followSystem") }
        static var appearance: String { localized("common.appearance") }
        static var notifications: String { localized("common.notifications") }
        static var about: String { localized("common.about") }
        static var version: String { localized("common.version") }
        static var build: String { localized("common.build") }
        static var none: String { localized("common.none") }
        static var aiDisclaimer: String { localized("common.aiDisclaimer") }
    }

    enum Errors {
        static var generic: String { localized("errors.generic") }
        static var network: String { localized("errors.network") }
    }

    enum Version {
        static var checking: String { localized("version.checking") }
        static var failed: String { localized("version.failed") }
        static var updateRequired: String { localized("version.updateRequired") }
        static var openStore: String { localized("version.openStore") }
    }

    enum Auth {
        static var loginTitle: String { localized("auth.login.title") }
        static var email: String { localized("auth.email") }
        static var password: String { localized("auth.password") }
        static var signIn: String { localized("auth.signIn") }
        static var goSignup: String { localized("auth.goSignup") }
        static var goForgot: String { localized("auth.goForgot") }
        static var signupTitle: String { localized("auth.signup.title") }
        static var confirmPassword: String { localized("auth.confirmPassword") }
        static var invitationCode: String { localized("auth.invitationCode") }
        static var nicknameOptional: String { localized("auth.nicknameOptional") }
        static var createAccount: String { localized("auth.createAccount") }
        static var invitationRequired: String { localized("auth.invitationRequired") }
        static var passwordMismatch: String { localized("auth.passwordMismatch") }
        static var passwordMin8: String { localized("auth.passwordMin8") }
        static var emailInvalid: String { localized("auth.emailInvalid") }
        static var forgotTitle: String { localized("auth.forgot.title") }
        static var sendCode: String { localized("auth.forgot.sendCode") }
        static var verificationCode: String { localized("auth.forgot.verificationCode") }
        static var verificationCodeRequired: String { localized("auth.forgot.verificationCodeRequired") }
        static var newPassword: String { localized("auth.forgot.newPassword") }
        static var resetPassword: String { localized("auth.forgot.reset") }
        static var resetSuccess: String { localized("auth.forgot.resetSuccess") }
        static var codeSent: String { localized("auth.forgot.codeSent") }
    }

    enum Tabs {
        static var home: String { localized("tabs.home") }
        static var trade: String { localized("tabs.trade") }
        static var settings: String { localized("tabs.settings") }
    }

    enum Home {
        static var placeholder: String { localized("home.placeholder") }
        static var comingSoon: String { localized("home.comingSoon") }
    }

    enum Dashboard {
        static var title: String { localized("dashboard.title") }
        static var search: String { localized("dashboard.search") }
        static var searchPlaceholder: String { localized("dashboard.searchPlaceholder") }
        static var overview: String { localized("dashboard.overview") }
        static var todayPnl: String { localized("dashboard.todayPnl") }
        static var positions: String { localized("dashboard.positions") }
        static var orders: String { localized("dashboard.orders") }
        static var noBrokerage: String { localized("dashboard.noBrokerage") }
        static var quickAccess: String { localized("dashboard.quickAccess") }
        static var screeners: String { localized("dashboard.screeners") }
        static var sentiment: String { localized("dashboard.sentiment") }
        static var events: String { localized("dashboard.events") }
        static var notifications: String { localized("dashboard.notifications") }
        static var news: String { localized("dashboard.news") }
        static var historical: String { localized("dashboard.historical") }
    }

    enum Sentiment {
        static var title: String { localized("sentiment.title") }
        static var loading: String { localized("sentiment.loading") }
        static var loadFailed: String { localized("sentiment.loadFailed") }
        static var retry: String { localized("sentiment.retry") }
        static var unavailableTitle: String { localized("sentiment.unavailableTitle") }
        static var confidence: String { localized("sentiment.confidence") }
        static var intradayBias: String { localized("sentiment.intradayBias") }
        static var bestTradingStyle: String { localized("sentiment.bestTradingStyle") }
        static var scenarios: String { localized("sentiment.scenarios") }
        static var evidence: String { localized("sentiment.evidence") }
        static var confirmationAfterOpen: String { localized("sentiment.confirmationAfterOpen") }
        static var invalidation: String { localized("sentiment.invalidation") }
        static var keyDrivers: String { localized("sentiment.keyDrivers") }
        static var keyLevels: String { localized("sentiment.keyLevels") }
        static var plan: String { localized("sentiment.plan") }
        static var stayOutConditions: String { localized("sentiment.stayOutConditions") }
        static var risks: String { localized("sentiment.risks") }
        static var sources: String { localized("sentiment.sources") }
        static var noSources: String { localized("sentiment.noSources") }

        static func allowedWindow(_ value: String) -> String {
            String(format: localized("sentiment.allowedWindow"), value)
        }

        static func currentTime(_ value: String) -> String {
            String(format: localized("sentiment.currentTime"), value)
        }

        static func label(_ kind: MarketSentimentKind) -> String {
            switch kind {
            case .bullish: return localized("sentiment.bullish")
            case .bearish: return localized("sentiment.bearish")
            case .neutral: return localized("sentiment.neutral")
            case .mixed: return localized("sentiment.mixed")
            }
        }

        static func scenarioLabel(_ label: String) -> String {
            let key = "sentiment.scenario.\(label)"
            let value = localized(key)
            return value == key ? label.replacingOccurrences(of: "_", with: " ") : value
        }
    }

    enum Calendar {
        static var title: String { localized("calendar.title") }
        static var loading: String { localized("calendar.loading") }
        static var loadFailed: String { localized("calendar.loadFailed") }
        static var retry: String { localized("calendar.retry") }
        static var emptyTitle: String { localized("calendar.emptyTitle") }
        static var emptyBody: String { localized("calendar.emptyBody") }
        static var todayUsEvents: String { localized("calendar.todayUsEvents") }
        static var totalEvents: String { localized("calendar.totalEvents") }
        static var highImpact: String { localized("calendar.highImpact") }
        static var dayRisk: String { localized("calendar.dayRisk") }
        static var topEvents: String { localized("calendar.topEvents") }
        static var volatilityWindows: String { localized("calendar.volatilityWindows") }
        static var biasChangingEvents: String { localized("calendar.biasChangingEvents") }
        static var cautionNotes: String { localized("calendar.cautionNotes") }
        static var cleanerMarketPhase: String { localized("calendar.cleanerMarketPhase") }
        static var actual: String { localized("calendar.actual") }
        static var forecast: String { localized("calendar.forecast") }
        static var previous: String { localized("calendar.previous") }
        static var choppinessRisk: String { localized("calendar.choppinessRisk") }
        static var expectedMarketImpact: String { localized("calendar.expectedMarketImpact") }
        static var traderNote: String { localized("calendar.traderNote") }
        static var description: String { localized("calendar.description") }
        static var marketFocus: String { localized("calendar.marketFocus") }
        static var marketFocusFallback: String { localized("calendar.marketFocusFallback") }
        static var source: String { localized("calendar.source") }
    }

    enum News {
        static var title: String { localized("news.title") }
        static var emptyTitle: String { localized("news.emptyTitle") }
        static var emptyBody: String { localized("news.emptyBody") }
        static var fallbackSymbol: String { localized("news.fallbackSymbol") }
        static var justNow: String { localized("news.justNow") }
        static var detailTitle: String { localized("news.detailTitle") }
        static var untitled: String { localized("news.untitled") }
        static var notFoundTitle: String { localized("news.notFoundTitle") }
        static var notFoundBody: String { localized("news.notFoundBody") }
        static var openSymbol: String { localized("news.openSymbol") }
        static var openLink: String { localized("news.openLink") }

        static func minutesAgo(_ count: Int) -> String {
            String(format: localized("news.minutesAgo"), count)
        }

        static func hoursAgo(_ count: Int) -> String {
            String(format: localized("news.hoursAgo"), count)
        }

        static func daysAgo(_ count: Int) -> String {
            String(format: localized("news.daysAgo"), count)
        }

        static func published(_ value: String) -> String {
            String(format: localized("news.published"), value)
        }

        static func received(_ value: String) -> String {
            String(format: localized("news.received"), value)
        }

        static func source(_ value: String) -> String {
            String(format: localized("news.source"), value)
        }
    }

    enum Notifications {
        static var title: String { localized("notifications.title") }
        static var emptyTitle: String { localized("notifications.emptyTitle") }
        static var emptyBody: String { localized("notifications.emptyBody") }
        static var filteredEmptyTitle: String { localized("notifications.filteredEmptyTitle") }
        static var filteredEmptyBody: String { localized("notifications.filteredEmptyBody") }
        static var filterAll: String { localized("notifications.filters.all") }
        static var filterBreakout: String { localized("notifications.filters.breakout") }
        static var filterIntradayHigh: String { localized("notifications.filters.intradayHigh") }
        static var filterIntradayLow: String { localized("notifications.filters.intradayLow") }
        static var filterSymbols: String { localized("notifications.filters.symbols") }
        static var symbolsPlaceholder: String { localized("notifications.filters.symbolsPlaceholder") }
        static var filterTrendDown: String { localized("notifications.filters.trendDown") }
        static var filterTrendUp: String { localized("notifications.filters.trendUp") }
        static var filterType: String { localized("notifications.filters.type") }
        static var filterWeakPullback: String { localized("notifications.filters.weakPullback") }
        static var marketTrendUpReversalTitle: String { localized("notifications.marketTrendUpReversalTitle") }
        static var marketTrendDownReversalTitle: String { localized("notifications.marketTrendDownReversalTitle") }
        static var intradayHighRetestTitle: String { localized("notifications.intradayHighRetestTitle") }
        static var intradayLowRetestTitle: String { localized("notifications.intradayLowRetestTitle") }
        static var loadFailed: String { localized("notifications.loadFailed") }
        static var loadMore: String { localized("notifications.loadMore") }
        static var loadingMore: String { localized("notifications.loadingMore") }
        static var retry: String { localized("notifications.retry") }
        static var toastTitle: String { localized("notifications.toastTitle") }
    }

    enum Market {
        static var catalogTitle: String { localized("market.catalogTitle") }
        static var catalog: String { localized("market.catalog") }
        static var notificationSymbols: String { localized("market.notificationSymbols") }
        static var search: String { localized("market.search") }
        static var empty: String { localized("market.empty") }
        static var unknownSymbol: String { localized("market.unknownSymbol") }
        static var invalidSymbol: String { localized("market.invalidSymbol") }
        static var yahoo: String { localized("market.yahoo") }
        static var momentum: String { localized("market.momentum") }
        static var atr: String { localized("market.atr") }
        static var priceSlope: String { localized("market.priceSlope") }
        static var stair: String { localized("market.stair") }
        static var rsiAdx: String { localized("market.rsiAdx") }
        static var volume: String { localized("market.volume") }
        static var ibkr: String { localized("market.ibkr") }
        static var filters: String { localized("market.filters") }
        static var date: String { localized("market.date") }
        static var direction: String { localized("market.direction") }
        static var up: String { localized("market.up") }
        static var down: String { localized("market.down") }
        static var window: String { localized("market.window") }
        static var minPrice: String { localized("market.minPrice") }
        static var minVolume: String { localized("market.minVolume") }
        static var endTime: String { localized("market.endTime") }
        static var applyFilters: String { localized("market.applyFilters") }
        static var invalidEndTime: String { localized("market.invalidEndTime") }
        static var disconnected: String { localized("market.disconnected") }
        static func rsiValue(_ value: String) -> String {
            String(format: localized("market.rsiValue"), value)
        }
        static func adxValue(_ value: String) -> String {
            String(format: localized("market.adxValue"), value)
        }
        static func atrValue(_ value: String) -> String {
            String(format: localized("market.atrValue"), value)
        }
    }

    enum Detail {
        static var accountPnl: String { localized("detail.accountPnl") }
        static var indicators: String { localized("detail.indicators") }
        static var rsi: String { localized("detail.rsi") }
        static var adx: String { localized("detail.adx") }
        static var atr: String { localized("detail.atr") }
        static var chart: String { localized("detail.chart") }
        static var bid: String { localized("detail.bid") }
        static var ask: String { localized("detail.ask") }
        static var subscribe: String { localized("detail.subscribe") }
        static var unsubscribe: String { localized("detail.unsubscribe") }
    }

    enum Chart {
        static var interval: String { localized("chart.interval") }
        static var oneMinute: String { localized("chart.oneMinute") }
        static var threeMinutes: String { localized("chart.threeMinutes") }
        static var fiveMinutes: String { localized("chart.fiveMinutes") }
        static var candle: String { localized("chart.candle") }
        static var line: String { localized("chart.line") }
        static var vwap: String { localized("chart.vwap") }
        static var prevClose: String { localized("chart.prevClose") }
        static var sessionOpen: String { localized("chart.sessionOpen") }
        static var empty: String { localized("chart.empty") }
        static var loadFailed: String { localized("chart.loadFailed") }
        static var preMarket: String { localized("chart.preMarket") }
        static var afterMarket: String { localized("chart.afterMarket") }
        static var seconds: String { localized("chart.seconds") }
        static var oneSecond: String { localized("chart.oneSecond") }
        static var fiveSeconds: String { localized("chart.fiveSeconds") }
        static var tenSeconds: String { localized("chart.tenSeconds") }
        static var thirtySeconds: String { localized("chart.thirtySeconds") }
        static var nasdaq: String { localized("chart.nasdaq") }
    }

    enum Historical {
        static var title: String { localized("historical.title") }
        static var symbolPlaceholder: String { localized("historical.symbolPlaceholder") }
        static var fills: String { localized("historical.fills") }
        static var emptyFills: String { localized("historical.emptyFills") }
        static var listOnly: String { localized("historical.listOnly") }
    }

    enum Trade {
        static var placeholder: String { localized("trade.placeholder") }
        static var title: String { localized("trade.title") }
        static var add: String { localized("trade.add") }
        static var addPlaceholder: String { localized("trade.addPlaceholder") }
        static var empty: String { localized("trade.empty") }
        static var emptyBody: String { localized("trade.emptyBody") }
        static var subscribeFailed: String { localized("trade.subscribeFailed") }
        static var unsubscribeFailed: String { localized("trade.unsubscribeFailed") }
        static var symbolsRequired: String { localized("trade.symbolsRequired") }
    }

    enum Trading {
        static var blocked: String { localized("trading.blocked") }
        static var addCredentialsBody: String { localized("trading.addCredentialsBody") }
        static var goToCredentials: String { localized("trading.goToCredentials") }
        static var credentialsInvalid: String { localized("trading.credentialsInvalid") }
        static var credentialsInvalidBody: String { localized("trading.credentialsInvalidBody") }
        static func protectionWindow(_ minutes: Int) -> String {
            String(format: localized("trading.protectionWindow"), minutes)
        }
        static var invalidQuantity: String { localized("trading.invalidQuantity") }
        static var invalidPrice: String { localized("trading.invalidPrice") }
        static var invalidSymbol: String { localized("trading.invalidSymbol") }
        static var maxOrderValue: String { localized("trading.maxOrderValue") }
        static var otoSpread: String { localized("trading.otoSpread") }
        static var noPosition: String { localized("trading.noPosition") }
        static var buy: String { localized("trading.buy") }
        static var sell: String { localized("trading.sell") }
        static var otoBuy: String { localized("trading.otoBuy") }
        static var otoSell: String { localized("trading.otoSell") }
        static var takeProfit: String { localized("trading.takeProfit") }
        static var stopLoss: String { localized("trading.stopLoss") }
        static var limitClose: String { localized("trading.limitClose") }
        static var marketClose: String { localized("trading.marketClose") }
        static var extendedHours: String { localized("trading.extendedHours") }
        static var quantity: String { localized("trading.quantity") }
        static var price: String { localized("trading.price") }
        static var takeProfitPrice: String { localized("trading.takeProfitPrice") }
        static var confirmTitle: String { localized("trading.confirmTitle") }
        static func confirmMessage(
            _ symbol: String,
            _ side: String,
            _ price: String,
            _ quantity: String,
            _ environment: String
        ) -> String {
            String(format: localized("trading.confirmMessage"), symbol, side, price, quantity, environment)
        }
        static var submit: String { localized("trading.submit") }
        static var submitFailed: String { localized("trading.submitFailed") }
        static var stopQtyAvailable: String { localized("trading.stopQtyAvailable") }
        static var stopQtyTotal: String { localized("trading.stopQtyTotal") }
        static var stopQtyCustom: String { localized("trading.stopQtyCustom") }
        static var cancelOpenOrders: String { localized("trading.cancelOpenOrders") }
        static var blockTakeProfit: String { localized("trading.blockTakeProfit") }
        static var allowTakeProfit: String { localized("trading.allowTakeProfit") }
        static var blockStopLoss: String { localized("trading.blockStopLoss") }
        static var allowStopLoss: String { localized("trading.allowStopLoss") }
        static var sliderHint: String { localized("trading.sliderHint") }
        static var sliderTitle: String { localized("trading.sliderTitle") }
        static func orderFilled(_ symbol: String) -> String {
            String(format: localized("trading.orderFilled"), symbol)
        }
        static var orderHistoryIncomplete: String { localized("trading.orderHistoryIncomplete") }
        static func orderCanceled(_ symbol: String) -> String {
            String(format: localized("trading.orderCanceled"), symbol)
        }
        static func orderRejected(_ symbol: String) -> String {
            String(format: localized("trading.orderRejected"), symbol)
        }
        static var takeProfitKind: String { localized("trading.takeProfitKind") }
        static var stopLossKind: String { localized("trading.stopLossKind") }
        static var autoExitKind: String { localized("trading.autoExitKind") }
        static func autoExitPlaced(_ kind: String, _ symbol: String) -> String {
            String(format: localized("trading.autoExitPlaced"), kind, symbol)
        }
        static func autoExitFailed(_ kind: String, _ symbol: String, _ message: String) -> String {
            String(format: localized("trading.autoExitFailed"), kind, symbol, message)
        }
        static func protectionRestoreFailed(_ symbol: String, _ message: String) -> String {
            String(format: localized("trading.protectionRestoreFailed"), symbol, message)
        }
    }

    enum Portfolio {
        static var title: String { localized("portfolio.title") }
        static var todayPnl: String { localized("portfolio.todayPnl") }
        static var value: String { localized("portfolio.value") }
        static var account: String { localized("portfolio.account") }
        static var equity: String { localized("portfolio.equity") }
        static var lastEquity: String { localized("portfolio.lastEquity") }
        static var portfolioValue: String { localized("portfolio.portfolioValue") }
        static var buyingPower: String { localized("portfolio.buyingPower") }
        static var cash: String { localized("portfolio.cash") }
    }

    enum Positions {
        static var title: String { localized("positions.title") }
        static var empty: String { localized("positions.empty") }
        static var emptyBody: String { localized("positions.emptyBody") }
        static var quantity: String { localized("positions.quantity") }
        static var side: String { localized("positions.side") }
        static var long: String { localized("positions.long") }
        static var short: String { localized("positions.short") }
        static var entry: String { localized("positions.entry") }
        static var current: String { localized("positions.current") }
        static var marketValue: String { localized("positions.marketValue") }
        static var cost: String { localized("positions.cost") }
        static var unrealized: String { localized("positions.unrealized") }
        static var close: String { localized("positions.close") }
    }

    enum Orders {
        static var title: String { localized("orders.title") }
        static var empty: String { localized("orders.empty") }
        static var emptyBody: String { localized("orders.emptyBody") }
        static var filters: String { localized("orders.filters") }
        static var filterAll: String { localized("orders.filterAll") }
        static var filterFilled: String { localized("orders.filterFilled") }
        static var filterNew: String { localized("orders.filterNew") }
        static var symbolFilter: String { localized("orders.symbolFilter") }
        static var loadMore: String { localized("orders.loadMore") }
        static func partialFill(_ filled: String, _ ordered: String, _ remaining: String) -> String {
            String(format: localized("orders.partialFill"), filled, ordered, remaining)
        }
        static func priceAverage(_ price: String) -> String {
            String(format: localized("orders.priceAverage"), price)
        }
        static func priceLimit(_ price: String) -> String {
            String(format: localized("orders.priceLimit"), price)
        }
        static func priceStop(_ price: String) -> String {
            String(format: localized("orders.priceStop"), price)
        }
        static var historyIncomplete: String { localized("orders.historyIncomplete") }
        static var buy: String { localized("orders.buy") }
        static var sell: String { localized("orders.sell") }
        static var cancelOrder: String { localized("orders.cancelOrder") }
        static var cancelConfirmTitle: String { localized("orders.cancelConfirmTitle") }
        static var cancelFailed: String { localized("orders.cancelFailed") }
        static var amendOrder: String { localized("orders.amendOrder") }
        static var amendConfirmTitle: String { localized("orders.amendConfirmTitle") }
        static var amendFailed: String { localized("orders.amendFailed") }
        static func amendConfirmMessage(
            _ symbol: String,
            _ side: String,
            _ quantity: String,
            _ price: String,
            _ environment: String
        ) -> String {
            String(format: localized("orders.amendConfirmMessage"), symbol, side, quantity, price, environment)
        }
        static var statusNew: String { localized("orders.status.new") }
        static var statusPartiallyFilled: String { localized("orders.status.partiallyFilled") }
        static var statusFilled: String { localized("orders.status.filled") }
        static var statusDoneForDay: String { localized("orders.status.doneForDay") }
        static var statusCanceled: String { localized("orders.status.canceled") }
        static var statusExpired: String { localized("orders.status.expired") }
        static var statusReplaced: String { localized("orders.status.replaced") }
        static var statusPendingCancel: String { localized("orders.status.pendingCancel") }
        static var statusPendingReplace: String { localized("orders.status.pendingReplace") }
        static var statusAccepted: String { localized("orders.status.accepted") }
        static var statusPendingNew: String { localized("orders.status.pendingNew") }
        static var statusAcceptedForBidding: String { localized("orders.status.acceptedForBidding") }
        static var statusStopped: String { localized("orders.status.stopped") }
        static var statusRejected: String { localized("orders.status.rejected") }
        static var statusSuspended: String { localized("orders.status.suspended") }
        static var statusCalculated: String { localized("orders.status.calculated") }
        static var statusHeld: String { localized("orders.status.held") }
        static var statusOther: String { localized("orders.status.other") }
        static var typeMarket: String { localized("orders.type.market") }
        static var typeLimit: String { localized("orders.type.limit") }
        static var typeStop: String { localized("orders.type.stop") }
        static var typeStopLimit: String { localized("orders.type.stopLimit") }
        static var typeTrailingStop: String { localized("orders.type.trailingStop") }
        static var typeOther: String { localized("orders.type.other") }
        static func cancelConfirmMessage(_ symbol: String, _ side: String, _ quantity: String, _ environment: String) -> String {
            String(format: localized("orders.cancelConfirmMessage"), symbol, side, quantity, environment)
        }
    }

    enum Settings {
        static var title: String { localized("settings.title") }
        static var signOut: String { localized("settings.signOut") }
        static var signedInAs: String { localized("settings.signedInAs") }
        static var comingNext: String { localized("settings.comingNext") }
        static var credentials: String { localized("settings.credentials") }
        static var manageCredentials: String { localized("settings.manageCredentials") }
        static var preferences: String { localized("settings.preferences") }
        static var profile: String { localized("settings.profile") }
        static var other: String { localized("settings.other") }
        static var pushNotifications: String { localized("settings.pushNotifications") }
        static var receivePush: String { localized("settings.receivePush") }
        static var permissionOff: String { localized("settings.permissionOff") }
        static var darkMode: String { localized("settings.darkMode") }
        static var appearanceSystem: String { localized("settings.appearance.system") }
        static var appearanceLight: String { localized("settings.appearance.light") }
        static var appearanceDark: String { localized("settings.appearance.dark") }
        static var languageEnglish: String { localized("settings.language.en") }
        static var languageChinese: String { localized("settings.language.zh") }
        static var logoutTitle: String { localized("settings.logout.title") }
        static var logoutMessage: String { localized("settings.logout.message") }
        static var notificationDeniedTitle: String { localized("settings.push.deniedTitle") }
        static var notificationDeniedMessage: String { localized("settings.push.deniedMessage") }
        static var footer: String { localized("settings.footer") }
    }

    enum Credentials {
        static var title: String { localized("credentials.title") }
        static var subtitle: String { localized("credentials.subtitle") }
        static var accountType: String { localized("credentials.accountType") }
        static var accountTypeHelp: String { localized("credentials.accountTypeHelp") }
        static var paper: String { localized("credentials.paper") }
        static var live: String { localized("credentials.live") }
        static var apiKey: String { localized("credentials.apiKey") }
        static var apiSecret: String { localized("credentials.apiSecret") }
        static var showSecret: String { localized("credentials.showSecret") }
        static var hideSecret: String { localized("credentials.hideSecret") }
        static var incomplete: String { localized("credentials.incomplete") }
        static var saved: String { localized("credentials.saved") }
        static var cleared: String { localized("credentials.cleared") }
        static var securityNotice: String { localized("credentials.securityNotice") }
        static var currentAccount: String { localized("credentials.currentAccount") }
        static var noAccount: String { localized("credentials.noAccount") }
    }

    enum Prefs {
        static var title: String { localized("prefs.title") }
        static var loading: String { localized("prefs.loading") }
        static var saving: String { localized("prefs.saving") }
        static var reset: String { localized("prefs.reset") }
        static var yourLanguage: String { localized("prefs.yourLanguage") }
        static var tradeSection: String { localized("prefs.tradeSection") }
        static var actionsSection: String { localized("prefs.actionsSection") }
        static var chartSection: String { localized("prefs.chartSection") }
        static var notificationsSection: String { localized("prefs.notificationsSection") }
        static var blacklistSection: String { localized("prefs.blacklistSection") }
        static func valuePerTrade(_ max: String) -> String {
            String(format: localized("prefs.valuePerTrade"), max)
        }
        static func valuePerTradeHelp(_ max: String) -> String {
            String(format: localized("prefs.valuePerTradeHelp"), max)
        }
        static var protectMinutes: String { localized("prefs.protectMinutes") }
        static var protectMinutesHelp: String { localized("prefs.protectMinutesHelp") }
        static var showOTO: String { localized("prefs.showOTO") }
        static var showOTOHelp: String { localized("prefs.showOTOHelp") }
        static var showMarketFlatten: String { localized("prefs.showMarketFlatten") }
        static var showMarketFlattenHelp: String { localized("prefs.showMarketFlattenHelp") }
        static var autoTakeProfit: String { localized("prefs.autoTakeProfit") }
        static var autoTakeProfitHelp: String { localized("prefs.autoTakeProfitHelp") }
        static var autoStopLoss: String { localized("prefs.autoStopLoss") }
        static var autoStopLossHelp: String { localized("prefs.autoStopLossHelp") }
        static var protectionPercent: String { localized("prefs.protectionPercent") }
        static var protectionError: String { localized("prefs.protectionError") }
        static var showDailyBar: String { localized("prefs.showDailyBar") }
        static var showDailyBarHelp: String { localized("prefs.showDailyBarHelp") }
        static var showIndexBar: String { localized("prefs.showIndexBar") }
        static var showIndexBarHelp: String { localized("prefs.showIndexBarHelp") }
        static var volumeThreshold: String { localized("prefs.volumeThreshold") }
        static var volumeThresholdHelp: String { localized("prefs.volumeThresholdHelp") }
        static var takeProfitBlacklist: String { localized("prefs.takeProfitBlacklist") }
        static var stopLossBlacklist: String { localized("prefs.stopLossBlacklist") }
        static var blacklistEmpty: String { localized("prefs.blacklistEmpty") }
    }

    enum Profile {
        static var title: String { localized("profile.title") }
        static var nickname: String { localized("profile.nickname") }
        static var email: String { localized("profile.email") }
        static var username: String { localized("profile.username") }
        static var role: String { localized("profile.role") }
        static var enabledFeatures: String { localized("profile.enabledFeatures") }
        static var roleConfiguration: String { localized("profile.roleConfiguration") }
        static var noRoleConfiguration: String { localized("profile.noRoleConfiguration") }
    }

    enum Other {
        static var title: String { localized("other.title") }
        static var account: String { localized("other.account") }
        static var deleteAccount: String { localized("other.deleteAccount") }
        static var deleteAccountHelp: String { localized("other.deleteAccountHelp") }
        static var deleteConfirmTitle: String { localized("other.deleteConfirmTitle") }
        static var deleteConfirmMessage: String { localized("other.deleteConfirmMessage") }
        static var deleteConfirmAction: String { localized("other.deleteConfirmAction") }
    }

    fileprivate static func localized(_ key: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: bundle, value: key, comment: "")
    }

    private static func localizationBundle(code: String) -> Bundle? {
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }
}
