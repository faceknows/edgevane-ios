import Foundation

enum SocketStatus: String, Equatable {
    case connecting
    case open
    case closed
    case error

    var isConnected: Bool { self == .open }
}

protocol MarketSocketing: AnyObject {
    var status: SocketStatus { get }
    func connect(token: String)
    func disconnect()
    func on(_ event: String, handler: @escaping (Data) -> Void)
    func onStatusChange(_ handler: @escaping (SocketStatus) -> Void)
}
