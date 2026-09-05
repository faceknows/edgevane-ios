import Foundation

struct AppVersionInfo: Decodable, Equatable {
    var platform: String?
    var requestedAppVersion: String?
    var minSupportedAppVersion: String?
    var latestAppVersion: String?
    var forceUpgrade: Bool?
    var upgradeMessage: String?
    var storeUrl: String?
}

struct VersionAPI {
    var client: HTTPClient

    func check() async throws -> AppVersionInfo {
        try await client.send(
            HTTPRequest(method: .get, path: "app/version")
        )
    }
}
