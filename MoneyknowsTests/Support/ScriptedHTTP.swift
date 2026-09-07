import Foundation
@testable import Moneyknows

@MainActor
final class ScriptedHTTP: HTTPSending {
    var rawResults: [Result<Data, Error>] = []
    var rawResultsByPath: [String: Data] = [:]
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
        if let data = rawResultsByPath[request.path] {
            result = .success(data)
        } else if rawResults.isEmpty {
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

private struct EncodableBox: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init(_ value: Encodable) {
        encodeClosure = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}

func jsonObject(from request: HTTPRequest) throws -> [String: Any] {
    guard let body = request.body else { return [:] }
    let data = try HTTPClient.makeEncoder().encode(EncodableBox(body))
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw AppError.decoding
    }
    return object
}
