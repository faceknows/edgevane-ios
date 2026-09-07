import Foundation

protocol BrokerageServing: AnyObject {
    var account: BrokerageAccount { get }
    func portfolio() async throws -> Portfolio
    func positions() async throws -> [Position]
    func openOrders() async throws -> [Order]
    func closedOrders(limit: Int, beforeOrderId: String?) async throws -> OrderPage
    func order(id: String) async throws -> [Order]
    func cancel(orderId: String) async throws
    func place(_ order: NewOrder) async throws -> [Order]
    func replace(orderId: String, amendment: OrderAmendment) async throws -> [Order]
    func closePosition(symbol: String, percentage: Double, cancelOpenOrders: Bool) async throws -> [Order]
}

extension BrokerageServing {
    func closedOrders(limit: Int) async throws -> OrderPage {
        try await closedOrders(limit: limit, beforeOrderId: nil)
    }
}
