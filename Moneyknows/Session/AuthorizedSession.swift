import Foundation

@MainActor
final class AuthorizedSession: HTTPSending {
    private let client: HTTPSending
    private let session: SessionStore
    private let decoder: JSONDecoder
    private var refreshTask: Task<Void, Error>?
    private var refreshGeneration: UInt64?

    init(
        client: HTTPSending,
        session: SessionStore,
        decoder: JSONDecoder = HTTPClient.makeDecoder()
    ) {
        self.client = client
        self.session = session
        self.decoder = decoder
    }

    func send<T: Decodable>(_ request: HTTPRequest) async throws -> T {
        let data = try await sendRaw(request)
        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }
        if data.isEmpty {
            throw AppError.decoding
        }
        return try decode(T.self, from: data)
    }

    func send(_ request: HTTPRequest) async throws {
        _ = try await sendRaw(request)
    }

    func sendRaw(_ request: HTTPRequest) async throws -> Data {
        let generation = session.generation
        var request = request
        try attachToken(&request)
        do {
            let data = try await client.sendRaw(request)
            guard session.generation == generation else {
                throw AppError.cancelled
            }
            return data
        } catch let error as AppError where error.isUnauthorized {
            try await refreshOnce()
            guard session.generation == generation, session.isSignedIn else {
                throw AppError.cancelled
            }
            try attachToken(&request)
            do {
                let data = try await client.sendRaw(request)
                guard session.generation == generation else {
                    throw AppError.cancelled
                }
                return data
            } catch let retry as AppError where retry.isUnauthorized {
                if session.generation == generation {
                    session.signOut()
                }
                throw retry
            }
        }
    }

    private func attachToken(_ request: inout HTTPRequest) throws {
        guard let token = session.accessToken, !token.isEmpty else {
            throw AppError.http(status: 401, message: nil, errorCode: nil)
        }
        request.extraHeaders["Authorization"] = "Bearer \(token)"
    }

    private func refreshOnce() async throws {
        let generation = session.generation
        if let refreshTask, refreshGeneration == generation {
            try await refreshTask.value
            return
        }
        let task = Task { try await session.refresh() }
        refreshTask = task
        refreshGeneration = generation
        defer {
            if refreshGeneration == generation {
                refreshTask = nil
                refreshGeneration = nil
            }
        }
        try await task.value
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if let value = try? decoder.decode(T.self, from: data) {
            return value
        }
        if let envelope = try? decoder.decode(JSONEnvelope<T>.self, from: data) {
            return envelope.data
        }
        throw AppError.decoding
    }
}
