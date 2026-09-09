import Foundation

enum AlpacaTradeSocketRouting: Equatable {
    case authorized
    case listening
    case unauthorized
    case error
    case tradeUpdate
    case other
}

enum AlpacaTradeSocketFailure: Equatable {
    case retry
    case unauthorized
}

enum AlpacaTradeSocketEnvelope {
    static func decode(_ data: Data) -> [[String: Any]] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let dict = object as? [String: Any] {
            return [dict]
        }
        if let array = object as? [Any] {
            return array.compactMap { $0 as? [String: Any] }
        }
        return []
    }

    static func route(_ object: [String: Any]) -> AlpacaTradeSocketRouting {
        if isUnauthorized(object) { return .unauthorized }
        if isError(object) { return .error }
        if isAuthorized(object) { return .authorized }
        if isListening(object) { return .listening }
        if isTradeUpdate(object) { return .tradeUpdate }
        return .other
    }

    static func failure(for route: AlpacaTradeSocketRouting) -> AlpacaTradeSocketFailure? {
        switch route {
        case .unauthorized:
            return .unauthorized
        case .error:
            return .retry
        default:
            return nil
        }
    }

    static func encode(_ object: [String: Any]) -> Data? {
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        return try? JSONSerialization.data(withJSONObject: object)
    }

    static func authMessage(key: String, secret: String) -> Data {
        data(["action": "auth", "key": key, "secret": secret])
    }

    static func listenMessage() -> Data {
        data(["action": "listen", "data": ["streams": ["trade_updates"]]])
    }

    private static func isAuthorized(_ object: [String: Any]) -> Bool {
        let stream = string(object["stream"])
        let type = string(object["T"])
        let msg = string(object["msg"])
        let data = object["data"] as? [String: Any]
        let status = string(data?["status"])
        let action = string(data?["action"])
        return (stream == "authorization" && status == "authorized")
            || (type == "success" && msg == "authenticated")
            || (action == "authenticate" && status == "authorized")
    }

    private static func isUnauthorized(_ object: [String: Any]) -> Bool {
        let stream = string(object["stream"])
        let type = string(object["T"])
        let data = object["data"] as? [String: Any]
        let status = string(data?["status"]) ?? string(object["status"])
        let code = int(data?["code"]) ?? int(object["code"])
        let message = [
            string(data?["message"]),
            string(data?["msg"]),
            string(object["msg"]),
            string(object["message"]),
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
        if stream == "authorization" && status == "unauthorized" { return true }
        if status == "unauthorized" { return true }
        if code == 401 { return true }
        if message.contains("unauthorized") { return true }
        if message.contains("authentication") { return true }
        if message.contains("auth failed") { return true }
        if type == "error" && message.contains("auth") { return true }
        return false
    }

    private static func isListening(_ object: [String: Any]) -> Bool {
        guard string(object["stream"]) == "listening" else { return false }
        let data = object["data"] as? [String: Any]
        let streams = data?["streams"] as? [String] ?? []
        return streams.contains("trade_updates")
    }

    private static func isError(_ object: [String: Any]) -> Bool {
        if string(object["T"]) == "error" { return true }
        let stream = string(object["stream"])
        let msg = string(object["msg"])
        return stream == "error" || msg == "error"
    }

    private static func isTradeUpdate(_ object: [String: Any]) -> Bool {
        if string(object["stream"]) == "trade_updates" { return true }
        if string(object["T"]) == "trade_updates" { return true }
        if string(object["msg"]) == "trade_updates" { return true }
        if object["order"] is [String: Any] { return true }
        if let data = object["data"] as? [String: Any], data["order"] is [String: Any] {
            return true
        }
        return false
    }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let text = string(value), let value = Int(text) { return value }
        return nil
    }

    private static func data(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }
}

final class AlpacaTradeSocket {
    var onOrderData: ((Data) -> Void)?
    var onUnauthorized: (() -> Void)?

    private static let queueKey = DispatchSpecificKey<UInt8>()
    private let queue: DispatchQueue
    private let url: URL
    private let key: String
    private let secret: String
    private let session: URLSession
    private let reconnectNanoseconds: UInt64
    private let authTimeoutNanoseconds: UInt64
    private var task: URLSessionWebSocketTask?
    private var generation: UInt64 = 0
    private var manualClose = false
    private var unauthorized = false
    private var reconnectTask: Task<Void, Never>?
    private var authTimeoutTask: Task<Void, Never>?
    private var didAuthorize = false

    init(
        url: URL,
        key: String,
        secret: String,
        session: URLSession = .shared,
        reconnectNanoseconds: UInt64 = 3_000_000_000,
        authTimeoutNanoseconds: UInt64 = 5_000_000_000
    ) {
        self.url = url
        self.key = key
        self.secret = secret
        self.session = session
        self.reconnectNanoseconds = reconnectNanoseconds
        self.authTimeoutNanoseconds = authTimeoutNanoseconds
        queue = DispatchQueue(label: "com.byteknows.moneyknows.alpaca-trade-socket")
        queue.setSpecific(key: Self.queueKey, value: 1)
    }

    deinit {
        runSync { self.tearDownLocked(manual: true) }
    }

    func connect() {
        run {
            self.manualClose = false
            self.unauthorized = false
            self.openLocked()
        }
    }

    func disconnect() {
        runSync { self.tearDownLocked(manual: true) }
    }

    private var canReconnect: Bool { !manualClose && !unauthorized }

    private func openLocked() {
        generation += 1
        let generation = generation
        reconnectTask?.cancel()
        reconnectTask = nil
        authTimeoutTask?.cancel()
        authTimeoutTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        didAuthorize = false
        let socket = session.webSocketTask(with: url)
        task = socket
        socket.resume()
        AppLog.brokerage.info("trade socket connecting")
        sendLocked(AlpacaTradeSocketEnvelope.authMessage(key: key, secret: secret), generation: generation)
        listenLocked(generation: generation)
        startAuthTimeoutLocked(generation: generation)
    }

    private func listenLocked(generation: UInt64) {
        guard self.generation == generation, let task else { return }
        task.receive { [weak self] result in
            self?.run {
                self?.handleReceiveLocked(result, generation: generation)
            }
        }
    }

    private func handleReceiveLocked(_ result: Result<URLSessionWebSocketTask.Message, Error>, generation: UInt64) {
        guard self.generation == generation else { return }
        switch result {
        case let .success(message):
            handleMessageLocked(message, generation: generation)
            listenLocked(generation: generation)
        case .failure:
            scheduleReconnectLocked(generation: generation)
        }
    }

    private func handleMessageLocked(_ message: URLSessionWebSocketTask.Message, generation: UInt64) {
        guard self.generation == generation else { return }
        let data: Data?
        switch message {
        case let .string(text):
            data = Data(text.utf8)
        case let .data(value):
            data = value
        @unknown default:
            data = nil
        }
        guard let data, !data.isEmpty else { return }
        var sawTradeUpdate = false
        for object in AlpacaTradeSocketEnvelope.decode(data) {
            let route = AlpacaTradeSocketEnvelope.route(object)
            if let failure = AlpacaTradeSocketEnvelope.failure(for: route) {
                switch failure {
                case .unauthorized:
                    failUnauthorizedLocked()
                case .retry:
                    AppLog.brokerage.error("trade socket stream error")
                    scheduleReconnectLocked(generation: generation)
                }
                return
            }
            switch route {
            case .authorized:
                didAuthorize = true
                authTimeoutTask?.cancel()
                authTimeoutTask = nil
                sendLocked(AlpacaTradeSocketEnvelope.listenMessage(), generation: generation)
                AppLog.brokerage.info("trade socket authorized")
            case .listening:
                didAuthorize = true
                authTimeoutTask?.cancel()
                authTimeoutTask = nil
                AppLog.brokerage.info("trade socket listening")
            case .tradeUpdate:
                sawTradeUpdate = true
                let payload = AlpacaTradeSocketEnvelope.encode(object) ?? data
                notifyOrder(payload)
            case .unauthorized, .error, .other:
                break
            }
        }
        if sawTradeUpdate {
            didAuthorize = true
            authTimeoutTask?.cancel()
            authTimeoutTask = nil
        }
    }

    private func sendLocked(_ data: Data, generation: UInt64) {
        guard self.generation == generation, let task else { return }
        let text = String(data: data, encoding: .utf8) ?? ""
        task.send(.string(text)) { _ in }
    }

    private func startAuthTimeoutLocked(generation: UInt64) {
        authTimeoutTask?.cancel()
        authTimeoutTask = Task { [weak self] in
            let delay = self?.authTimeoutNanoseconds ?? 5_000_000_000
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            self?.run {
                self?.handleAuthTimeoutLocked(generation: generation)
            }
        }
    }

    private func handleAuthTimeoutLocked(generation: UInt64) {
        guard self.generation == generation, !didAuthorize else { return }
        AppLog.brokerage.error("trade socket auth timeout")
        scheduleReconnectLocked(generation: generation)
    }

    private func scheduleReconnectLocked(generation: UInt64) {
        guard canReconnect, self.generation == generation else { return }
        closeSocketLocked()
        let next = self.generation
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            let delay = self?.reconnectNanoseconds ?? 3_000_000_000
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            self?.run {
                self?.openIfCurrentLocked(generation: next)
            }
        }
    }

    private func openIfCurrentLocked(generation: UInt64) {
        guard canReconnect, self.generation == generation else { return }
        openLocked()
    }

    private func failUnauthorizedLocked() {
        guard !unauthorized else { return }
        unauthorized = true
        AppLog.brokerage.error("trade socket unauthorized")
        tearDownLocked(manual: false)
        let callback = onUnauthorized
        DispatchQueue.main.async { callback?() }
    }

    private func closeSocketLocked() {
        generation += 1
        authTimeoutTask?.cancel()
        authTimeoutTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        didAuthorize = false
    }

    private func tearDownLocked(manual: Bool) {
        if manual {
            manualClose = true
        }
        reconnectTask?.cancel()
        reconnectTask = nil
        closeSocketLocked()
    }

    private func notifyOrder(_ data: Data) {
        let callback = onOrderData
        DispatchQueue.main.async { callback?(data) }
    }

    private func run(_ body: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            body()
        } else {
            queue.async(execute: body)
        }
    }

    private func runSync(_ body: () -> Void) {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            body()
        } else {
            queue.sync(execute: body)
        }
    }
}
