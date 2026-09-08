import Foundation
import SocketIO

final class SocketCallbackGate {
    private var generation: UInt64 = 0

    func invalidate() {
        generation += 1
    }

    func snapshot() -> UInt64 {
        generation
    }

    func isCurrent(_ snapshot: UInt64) -> Bool {
        snapshot == generation
    }
}

final class GatewaySocket: MarketSocketing {
    private let host: URL
    private let namespace: String
    private let reconnectWait: Int
    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var eventHandlers: [String: [(Data) -> Void]] = [:]
    private var statusHandlers: [(SocketStatus) -> Void] = []
    private let callbacks = SocketCallbackGate()
    private(set) var status: SocketStatus = .closed

    init(
        host: URL = AppEnvironment.socketHost,
        namespace: String = "/alpaca-stream",
        reconnectWait: Int = 3
    ) {
        self.host = host
        self.namespace = namespace
        self.reconnectWait = reconnectWait
    }

    private var lastToken: String?

    func connect(token: String) {
        if lastToken == token, let status = socket?.status, status == .connected || status == .connecting {
            return
        }
        disconnect()
        lastToken = token
        setStatus(.connecting)
        let manager = SocketManager(
            socketURL: host,
            config: [
                .forceWebsockets(true),
                .reconnects(true),
                .reconnectWait(reconnectWait),
                .reconnectAttempts(-1),
                .connectParams(["token": token]),
                .log(false),
            ]
        )
        let socket = manager.socket(forNamespace: namespace)
        self.manager = manager
        self.socket = socket
        socket.on(clientEvent: .connect) { [weak self] _, _ in
            self?.setStatus(.open)
        }
        socket.on(clientEvent: .disconnect) { [weak self] _, _ in
            self?.setStatus(.closed)
        }
        socket.on(clientEvent: .reconnect) { [weak self] _, _ in
            self?.setStatus(.connecting)
        }
        socket.on(clientEvent: .reconnectAttempt) { [weak self] _, _ in
            self?.setStatus(.connecting)
        }
        socket.on(clientEvent: .error) { [weak self] _, _ in
            self?.setStatus(.error)
        }
        socket.on("ping") { [weak socket] _, _ in
            socket?.emit("pong")
        }
        for event in eventHandlers.keys {
            attach(event, on: socket)
        }
        socket.connect(withPayload: ["token": token])
        AppLog.socket.info("connecting \(self.namespace, privacy: .public)")
    }

    func disconnect() {
        callbacks.invalidate()
        socket?.removeAllHandlers()
        socket?.disconnect()
        manager?.disconnect()
        socket = nil
        manager = nil
        lastToken = nil
        if status != .closed {
            setStatus(.closed)
        }
    }

    func on(_ event: String, handler: @escaping (Data) -> Void) {
        eventHandlers[event, default: []].append(handler)
        if let socket {
            attach(event, on: socket)
        }
    }

    func onStatusChange(_ handler: @escaping (SocketStatus) -> Void) {
        statusHandlers.append(handler)
    }

    private func attach(_ event: String, on socket: SocketIOClient) {
        socket.on(event) { [weak self] data, _ in
            guard let self, let payload = Self.encode(data.first) else { return }
            let snapshot = self.callbacks.snapshot()
            let deliver = { [weak self] in
                guard let self, self.callbacks.isCurrent(snapshot) else { return }
                let handlers = self.eventHandlers[event] ?? []
                MainActor.assumeIsolated {
                    handlers.forEach { $0(payload) }
                }
            }
            if Thread.isMainThread {
                deliver()
            } else {
                DispatchQueue.main.async(execute: deliver)
            }
        }
    }

    private func setStatus(_ status: SocketStatus) {
        let apply = {
            guard self.status != status else { return }
            self.status = status
            AppLog.socket.info("socket \(status.rawValue, privacy: .public)")
            self.statusHandlers.forEach { $0(status) }
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    private static func encode(_ value: Any?) -> Data? {
        guard let value else { return nil }
        if JSONSerialization.isValidJSONObject(value) {
            return try? JSONSerialization.data(withJSONObject: value)
        }
        if let value = value as? String {
            return Data(value.utf8)
        }
        return nil
    }
}
