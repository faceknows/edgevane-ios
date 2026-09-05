import Foundation

struct AppUser: Codable, Equatable {
    var id: String
    var email: String
    var nickname: String?
    var role: String?

    init(id: String, email: String, nickname: String?, role: String?) {
        self.id = id
        self.email = email
        self.nickname = nickname
        self.role = role
    }

    init(dto: AuthUserDTO) {
        id = dto.id
        email = dto.email
        nickname = dto.nickname
        role = dto.role
    }
}

struct SessionTokens: Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
}

enum SessionTime {
    static func date(fromExpiresAt value: Double) -> Date {
        if value > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: value / 1000)
        }
        return Date(timeIntervalSince1970: value)
    }
}
