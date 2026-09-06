import Foundation

enum L10n {
    private static var bundle: Bundle = .main

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
