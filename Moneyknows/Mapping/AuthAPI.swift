import Foundation

struct AuthUserDTO: Decodable, Equatable {
    var id: String
    var email: String
    var username: String?
    var nickname: String?
    var role: String?
}

struct AuthSessionDTO: Decodable, Equatable {
    var accessToken: String
    var expiresAt: Double
    var refreshToken: String?
    var user: AuthUserDTO?
}

struct AuthAPI {
    var client: HTTPClient

    func signIn(email: String, password: String) async throws -> AuthSessionDTO {
        try await client.send(
            HTTPRequest(
                method: .post,
                path: "v1/users/email/signin",
                body: EmailPasswordBody(email: email, password: password)
            )
        )
    }

    func signUp(email: String, password: String, invitationCode: String, nickname: String?) async throws -> AuthSessionDTO {
        try await client.send(
            HTTPRequest(
                method: .post,
                path: "v1/users/email/signup",
                body: SignupBody(
                    email: email,
                    password: password,
                    nickname: nickname,
                    invitationCode: invitationCode
                )
            )
        )
    }

    func sendResetCode(email: String) async throws {
        try await client.send(
            HTTPRequest(
                method: .post,
                path: "v1/users/email/verification-code",
                body: VerificationCodeBody(email: email, type: "reset-password")
            )
        )
    }

    func resetPassword(email: String, verificationCode: String, newPassword: String) async throws {
        try await client.send(
            HTTPRequest(
                method: .post,
                path: "v1/users/email/reset-password",
                body: ResetPasswordBody(
                    email: email,
                    verificationCode: verificationCode,
                    newPassword: newPassword
                )
            )
        )
    }

    func refresh(refreshToken: String) async throws -> AuthSessionDTO {
        try await client.send(
            HTTPRequest(
                method: .post,
                path: "auth/refresh",
                body: RefreshBody(refreshToken: refreshToken)
            )
        )
    }
}

private struct EmailPasswordBody: Encodable {
    var email: String
    var password: String
}

private struct SignupBody: Encodable {
    var email: String
    var password: String
    var nickname: String?
    var invitationCode: String
}

private struct VerificationCodeBody: Encodable {
    var email: String
    var type: String
}

private struct ResetPasswordBody: Encodable {
    var email: String
    var verificationCode: String
    var newPassword: String
}

private struct RefreshBody: Encodable {
    var refreshToken: String
}
