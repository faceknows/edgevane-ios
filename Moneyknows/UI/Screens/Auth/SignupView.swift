import SwiftUI

struct SignupView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var invitationCode = ""
    @State private var nickname = ""
    @State private var errorText: String?
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.Auth.signupTitle)
                    .font(.largeTitle.bold())

                TextField(L10n.Auth.email, text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)

                SecureField(L10n.Auth.password, text: $password)
                    .textContentType(.newPassword)
                    .textFieldStyle(.roundedBorder)

                SecureField(L10n.Auth.confirmPassword, text: $confirmPassword)
                    .textContentType(.newPassword)
                    .textFieldStyle(.roundedBorder)

                TextField(L10n.Auth.invitationCode, text: $invitationCode)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)

                TextField(L10n.Auth.nicknameOptional, text: $nickname)
                    .textFieldStyle(.roundedBorder)

                FormMessage(text: errorText)
                PrimaryButton(title: L10n.Auth.createAccount, busy: busy, action: submit)
            }
            .padding(24)
        }
        .navigationTitle(L10n.Auth.signupTitle)
    }

    private func submit() {
        errorText = nil
        let email = AuthFormValidation.trimmed(self.email)
        let invitation = AuthFormValidation.trimmed(invitationCode)
        let nickname = AuthFormValidation.trimmed(self.nickname)

        guard AuthFormValidation.isValidEmail(email) else {
            errorText = L10n.Auth.emailInvalid
            return
        }
        guard password.count >= 8 else {
            errorText = L10n.Auth.passwordMin8
            return
        }
        guard password == confirmPassword else {
            errorText = L10n.Auth.passwordMismatch
            return
        }
        guard !invitation.isEmpty else {
            errorText = L10n.Auth.invitationRequired
            return
        }

        busy = true
        Task {
            defer { busy = false }
            do {
                let session = try await appModel.authAPI.signUp(
                    email: email,
                    password: password,
                    invitationCode: invitation,
                    nickname: nickname.isEmpty ? nil : nickname
                )
                guard session.user != nil else { throw AppError.decoding }
                try appModel.didSignIn(session)
            } catch {
                errorText = UserFacingError.message(from: error)
            }
        }
    }
}
