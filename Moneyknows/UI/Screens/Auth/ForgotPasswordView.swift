import SwiftUI

struct ForgotPasswordView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.presentationMode) private var presentationMode

    @State private var email = ""
    @State private var code = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var errorText: String?
    @State private var infoText: String?
    @State private var sending = false
    @State private var resetting = false
    @State private var showSuccess = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.Auth.forgotTitle)
                    .font(.largeTitle.bold())

                TextField(L10n.Auth.email, text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)

                PrimaryButton(title: L10n.Auth.sendCode, busy: sending, action: sendCode)

                TextField(L10n.Auth.verificationCode, text: $code)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)

                SecureField(L10n.Auth.newPassword, text: $newPassword)
                    .textContentType(.newPassword)
                    .textFieldStyle(.roundedBorder)

                SecureField(L10n.Auth.confirmPassword, text: $confirmPassword)
                    .textContentType(.newPassword)
                    .textFieldStyle(.roundedBorder)

                if let infoText {
                    Text(infoText)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                FormMessage(text: errorText)
                PrimaryButton(title: L10n.Auth.resetPassword, busy: resetting, action: reset)
            }
            .padding(24)
        }
        .navigationTitle(L10n.Auth.forgotTitle)
        .alert(Text(L10n.Auth.resetSuccess), isPresented: $showSuccess) {
            Button(L10n.Common.close) {
                presentationMode.wrappedValue.dismiss()
            }
        }
    }

    private func sendCode() {
        errorText = nil
        infoText = nil
        let email = AuthFormValidation.trimmed(self.email)
        guard AuthFormValidation.isValidEmail(email) else {
            errorText = L10n.Auth.emailInvalid
            return
        }
        sending = true
        Task {
            defer { sending = false }
            do {
                try await appModel.authAPI.sendResetCode(email: email)
                infoText = L10n.Auth.codeSent
            } catch {
                errorText = UserFacingError.message(from: error)
            }
        }
    }

    private func reset() {
        errorText = nil
        let email = AuthFormValidation.trimmed(self.email)
        let code = AuthFormValidation.trimmed(self.code)
        if let validationError = AuthFormValidation.resetPasswordError(
            email: email,
            verificationCode: code,
            newPassword: newPassword,
            confirmPassword: confirmPassword
        ) {
            switch validationError {
            case .invalidEmail:
                errorText = L10n.Auth.emailInvalid
            case .verificationCodeRequired:
                errorText = L10n.Auth.verificationCodeRequired
            case .passwordTooShort:
                errorText = L10n.Auth.passwordMin8
            case .passwordMismatch:
                errorText = L10n.Auth.passwordMismatch
            }
            return
        }
        resetting = true
        Task {
            defer { resetting = false }
            do {
                try await appModel.authAPI.resetPassword(
                    email: email,
                    verificationCode: code,
                    newPassword: newPassword
                )
                showSuccess = true
            } catch {
                errorText = UserFacingError.message(from: error)
            }
        }
    }
}
