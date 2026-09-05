import Foundation

enum L10n {
    enum Common {
        static var retry: String { localized("common.retry") }
        static var cancel: String { localized("common.cancel") }
        static var done: String { localized("common.done") }
        static var close: String { localized("common.close") }
        static var next: String { localized("common.next") }
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
    }

    enum Trade {
        static var placeholder: String { localized("trade.placeholder") }
    }

    enum Settings {
        static var title: String { localized("settings.title") }
        static var signOut: String { localized("settings.signOut") }
        static var signedInAs: String { localized("settings.signedInAs") }
        static var comingNext: String { localized("settings.comingNext") }
    }

    fileprivate static func localized(_ key: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: .main, value: key, comment: "")
    }
}
