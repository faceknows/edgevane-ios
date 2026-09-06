import Foundation
@testable import Moneyknows

@MainActor
final class ScriptedHTTP: HTTPSending {
    var rawResults: [Result<Data, Error>] = []
    var requests: [HTTPRequest] = []
    var pauseSends = false

    private var paused: [CheckedContinuation<Void, Never>] = []

    func releasePaused() {
        pauseSends = false
        let pending = paused
        paused.removeAll()
        pending.forEach { $0.resume() }
    }

    func releaseNext() {
        guard !paused.isEmpty else { return }
        paused.removeFirst().resume()
        if paused.isEmpty {
            pauseSends = false
        }
    }

    func releaseLast() {
        guard let last = paused.popLast() else { return }
        last.resume()
        if paused.isEmpty {
            pauseSends = false
        }
    }

    func send<T: Decodable>(_ request: HTTPRequest) async throws -> T {
        let data = try await sendRaw(request)
        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }
        return try HTTPClient(baseURL: AppEnvironment.apiURL).decode(T.self, from: data)
    }

    func send(_ request: HTTPRequest) async throws {
        _ = try await sendRaw(request)
    }

    func sendRaw(_ request: HTTPRequest) async throws -> Data {
        requests.append(request)
        let result: Result<Data, Error>
        if rawResults.isEmpty {
            result = .failure(AppError.network)
        } else {
            result = rawResults.removeFirst()
        }
        if pauseSends {
            await withCheckedContinuation { paused.append($0) }
        }
        return try result.get()
    }
}
