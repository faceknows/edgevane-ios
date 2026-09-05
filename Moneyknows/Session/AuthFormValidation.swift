import Foundation

enum AuthFormValidation {
    enum ResetPasswordError: Equatable {
        case invalidEmail
        case verificationCodeRequired
        case passwordTooShort
        case passwordMismatch
    }

    static func isValidEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@"), let at = trimmed.firstIndex(of: "@") else { return false }
        let domain = trimmed[trimmed.index(after: at)...]
        return domain.contains(".")
    }

    static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func resetPasswordError(
        email: String,
        verificationCode: String,
        newPassword: String,
        confirmPassword: String
    ) -> ResetPasswordError? {
        guard isValidEmail(email) else { return .invalidEmail }
        guard !trimmed(verificationCode).isEmpty else { return .verificationCodeRequired }
        guard newPassword.count >= 8 else { return .passwordTooShort }
        guard newPassword == confirmPassword else { return .passwordMismatch }
        return nil
    }
}
