import Foundation

struct PushAPI {
    var client: HTTPSending

    static let pageSize = 20

    func register(token: String, deviceId: String? = nil) async throws {
        try await client.send(
            HTTPRequest(
                method: .post,
                path: "v1/users/fcm-token",
                body: StoreFCMTokenBody(
                    token: token,
                    platform: "ios",
                    deviceId: deviceId ?? token
                )
            )
        )
    }

    func unregister(token: String) async throws {
        try await client.send(
            HTTPRequest(
                method: .delete,
                path: "v1/users/fcm-token",
                body: DeleteFCMTokenBody(token: token)
            )
        )
    }

    func history(limit: Int = pageSize, lastTime: Int64? = nil, type: String? = nil) async throws -> [AppNotification] {
        let items = try await fetchHistory(limit: limit, lastTime: lastTime, type: type)
        if items.isEmpty, let lastTime, lastTime >= 1_000_000_000_000 {
            return try await fetchHistory(limit: limit, lastTime: lastTime / 1000, type: type)
        }
        return items
    }

    static func decodeHistory(from data: Data) -> [AppNotification] {
        NotificationHistory.decodeList(from: data)
    }

    private func fetchHistory(limit: Int, lastTime: Int64?, type: String?) async throws -> [AppNotification] {
        var query: [String: String] = ["limit": String(limit)]
        if let lastTime {
            query["lastTime"] = String(lastTime)
        }
        if let type, !type.isEmpty {
            query["type"] = type
        }
        let data = try await client.sendRaw(
            HTTPRequest(method: .get, path: "v1/notifications/history", query: query)
        )
        return Self.decodeHistory(from: data)
    }
}

private struct StoreFCMTokenBody: Encodable {
    var token: String
    var platform: String
    var deviceId: String?
}

private struct DeleteFCMTokenBody: Encodable {
    var token: String
}

struct PublicAuthorizedPushAPI {
    var client: HTTPSending
    var accessToken: String?

    func unregister(token: String) async throws {
        guard let accessToken, !accessToken.isEmpty else { return }
        try await client.send(
            HTTPRequest(
                method: .delete,
                path: "v1/users/fcm-token",
                body: DeleteFCMTokenBody(token: token),
                extraHeaders: ["Authorization": "Bearer \(accessToken)"]
            )
        )
    }
}
