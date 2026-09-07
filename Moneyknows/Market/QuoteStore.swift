import Foundation

struct SymbolQuote: Equatable {
    var last: Double?
    var bid: Double?
    var ask: Double?
    var bidSize: Double?
    var askSize: Double?
    var snapshotBid: Double?
    var snapshotAsk: Double?

    var displayBid: Double? { bid ?? snapshotBid ?? last }
    var displayAsk: Double? { ask ?? snapshotAsk ?? last }
    var liveBid: Double? { bid ?? snapshotBid }
    var liveAsk: Double? { ask ?? snapshotAsk }

    var mid: Double? {
        if let bid = liveBid, let ask = liveAsk {
            return (bid + ask) / 2
        }
        return last
    }

    func referencePrice(for side: OrderSide) -> Double? {
        switch side {
        case .buy: return displayBid
        case .sell: return displayAsk
        }
    }
}

@MainActor
final class QuoteStore: ObservableObject {
    @Published private(set) var quotes: [String: SymbolQuote] = [:]

    func reset() {
        quotes = [:]
    }

    func remove(_ symbols: [String]) {
        symbols.map(SymbolCode.normalize).forEach { quotes[$0] = nil }
    }

    func quote(for raw: String) -> SymbolQuote? {
        quotes[SymbolCode.normalize(raw)]
    }

    func applyTrade(symbol: String, price: Double) {
        guard price.isFinite, price > 0 else { return }
        let symbol = SymbolCode.normalize(symbol)
        var current = quotes[symbol] ?? SymbolQuote()
        guard current.last != price else { return }
        current.last = price
        quotes[symbol] = current
    }

    func applyQuote(_ quote: StreamQuote) {
        let symbol = SymbolCode.normalize(quote.symbol)
        var current = quotes[symbol] ?? SymbolQuote()
        let bid = quote.bid
        let ask = quote.ask
        if current.bid == bid, current.ask == ask, current.bidSize == quote.bidSize, current.askSize == quote.askSize {
            return
        }
        current.bid = bid ?? current.bid
        current.ask = ask ?? current.ask
        current.bidSize = quote.bidSize ?? current.bidSize
        current.askSize = quote.askSize ?? current.askSize
        quotes[symbol] = current
    }

    func applySnapshot(quotes incoming: [StreamQuote], trades: [(symbol: String, price: Double)]) {
        for quote in incoming {
            let symbol = SymbolCode.normalize(quote.symbol)
            guard !symbol.isEmpty else { continue }
            var current = quotes[symbol] ?? SymbolQuote()
            current.snapshotBid = quote.bid ?? current.snapshotBid
            current.snapshotAsk = quote.ask ?? current.snapshotAsk
            quotes[symbol] = current
        }
        for trade in trades {
            if quotes[trade.symbol]?.last == nil {
                applyTrade(symbol: trade.symbol, price: trade.price)
            }
        }
    }
}
