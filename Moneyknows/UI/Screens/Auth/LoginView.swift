import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var email = ""
    @State private var password = ""
    @State private var errorText: String?
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.Auth.loginTitle)
                    .font(.largeTitle.bold())

                TextField(L10n.Auth.email, text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)

                SecureField(L10n.Auth.password, text: $password)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)

                FormMessage(text: errorText)
                PrimaryButton(title: L10n.Auth.signIn, busy: busy, action: submit)

                NavigationLink(L10n.Auth.goSignup, destination: SignupView())
                NavigationLink(L10n.Auth.goForgot, destination: ForgotPasswordView())

                if !AppEnvironment.isProduction {
                    Text(AppEnvironment.debugSummary)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(24)
        }
        .navigationTitle(L10n.Auth.loginTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() {
        errorText = nil
        let email = AuthFormValidation.trimmed(self.email)
        guard AuthFormValidation.isValidEmail(email) else {
            errorText = L10n.Auth.emailInvalid
            return
        }
        guard !password.isEmpty else {
            errorText = L10n.Auth.passwordMin8
            return
        }

        busy = true
        Task {
            defer { busy = false }
            do {
                let session = try await appModel.authAPI.signIn(email: email, password: password)
                guard session.user != nil else { throw AppError.decoding }
                try appModel.didSignIn(session)
            } catch let error as AppError where error.isUnauthorized {
                errorText = UserFacingError.message(from: error) ?? L10n.Errors.generic
            } catch {
                errorText = UserFacingError.message(from: error)
            }
        }
    }
}
