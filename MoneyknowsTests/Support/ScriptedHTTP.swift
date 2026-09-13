import Foundation
@testable import Moneyknows

@MainActor
final class ScriptedHTTP: HTTPSending {
    var rawResults: [Result<Data, Error>] = []
    var rawResultsByPath: [String: Data] = [:]
    var rawResultsBySymbol: [String: Data] = [:]
    var requests: [HTTPRequest] = []
    var pauseSends = false

    private var paused = PauseGate()
    private var nextPauseID: UInt64 = 0

    func releasePaused() {
        pauseSends = false
        paused.takeAll().forEach { $0.resume() }
    }

    func releaseNext() {
        guard let continuation = paused.takeFirst() else { return }
        continuation.resume()
        if paused.isEmpty {
            pauseSends = false
        }
    }

    func releaseLast() {
        guard let continuation = paused.takeLast() else { return }
        continuation.resume()
        if paused.isEmpty {
            pauseSends = false
        }
    }

    var pausedCount: Int { paused.count }

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
        if let symbol = request.query["symbol"], let data = rawResultsBySymbol[symbol] {
            result = .success(data)
        } else if let data = rawResultsByPath[request.path] {
            result = .success(data)
        } else if rawResults.isEmpty {
            result = .failure(AppError.network)
        } else {
            result = rawResults.removeFirst()
        }
        if pauseSends {
            try await waitIfPaused()
        }
        return try result.get()
    }

    private func waitIfPaused() async throws {
        nextPauseID += 1
        let id = nextPauseID
        let gate = paused
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    gate.add(id, continuation)
                }
            } onCancel: {
                gate.fail(id)
            }
        } catch {
            if paused.isEmpty {
                pauseSends = false
            }
            throw error
        }
        if paused.isEmpty {
            pauseSends = false
        }
    }
}

private final class PauseGate: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [UInt64: CheckedContinuation<Void, Error>] = [:]
    private var order: [UInt64] = []
    private var cancelled: Set<UInt64> = []

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return items.isEmpty
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return items.count
    }

    func add(_ id: UInt64, _ continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        if cancelled.remove(id) != nil {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        items[id] = continuation
        order.append(id)
        lock.unlock()
    }

    func fail(_ id: UInt64) {
        lock.lock()
        if let continuation = items.removeValue(forKey: id) {
            order.removeAll { $0 == id }
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        cancelled.insert(id)
        lock.unlock()
    }

    func takeAll() -> [CheckedContinuation<Void, Error>] {
        lock.lock()
        let pending = order.compactMap { items[$0] }
        items.removeAll()
        order.removeAll()
        cancelled.removeAll()
        lock.unlock()
        return pending
    }

    func takeFirst() -> CheckedContinuation<Void, Error>? {
        lock.lock()
        defer { lock.unlock() }
        guard let id = order.first else { return nil }
        order.removeFirst()
        return items.removeValue(forKey: id)
    }

    func takeLast() -> CheckedContinuation<Void, Error>? {
        lock.lock()
        defer { lock.unlock() }
        guard let id = order.popLast() else { return nil }
        return items.removeValue(forKey: id)
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
