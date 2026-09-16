import Foundation

struct SymbolQuote: Equatable {
    var last: Double?
    var bid: Double?
    var ask: Double?
    var bidSize: Double?
    var askSize: Double?
    var snapshotBid: Double?
    var snapshotAsk: Double?
    var snapshotBidSize: Double?
    var snapshotAskSize: Double?

    var displayBid: Double? { bid ?? snapshotBid ?? last }
    var displayAsk: Double? { ask ?? snapshotAsk ?? last }
    var liveBid: Double? { bid ?? snapshotBid }
    var liveAsk: Double? { ask ?? snapshotAsk }
    var displayBidSize: Double? { size(livePrice: bid, liveSize: bidSize, snapshotPrice: snapshotBid, snapshotSize: snapshotBidSize) }
    var displayAskSize: Double? { size(livePrice: ask, liveSize: askSize, snapshotPrice: snapshotAsk, snapshotSize: snapshotAskSize) }

    var mid: Double? {
        if let bid = liveBid, let ask = liveAsk {
            return (bid + ask) / 2
        }
        return last
    }

    /// Position P&L vs the live book; does not fall back to last trade.
    var tapePrice: Double? {
        if let bid = liveBid, let ask = liveAsk {
            return (bid + ask) / 2
        }
        return liveAsk ?? liveBid
    }

    var hasTapeQuote: Bool {
        liveBid != nil && liveAsk != nil
    }

    func referencePrice(for side: OrderSide) -> Double? {
        switch side {
        case .buy: return displayBid
        case .sell: return displayAsk
        }
    }

    /// Size belongs to a price level. Snapshot size is only used when that side's
    /// displayed book price is still the snapshot, never with a newer socket price.
    private func size(
        livePrice: Double?,
        liveSize: Double?,
        snapshotPrice: Double?,
        snapshotSize: Double?
    ) -> Double? {
        if livePrice != nil { return liveSize }
        if snapshotPrice != nil { return snapshotSize }
        return nil
    }
}

@MainActor
final class QuoteStore: ObservableObject {
    @Published private(set) var quotes: [String: SymbolQuote] = [:]
    private var tradeGeneration: [String: UInt64] = [:]
    private var snapshotGeneration: [String: UInt64] = [:]

    func reset() {
        let symbols = Set(quotes.keys)
            .union(tradeGeneration.keys)
            .union(snapshotGeneration.keys)
        quotes = [:]
        invalidateGenerations(symbols)
    }

    func remove(_ symbols: [String]) {
        let normalized = Set(symbols.map(SymbolCode.normalize).filter { !$0.isEmpty })
        normalized.forEach { quotes[$0] = nil }
        invalidateGenerations(normalized)
    }

    func quote(for raw: String) -> SymbolQuote? {
        quotes[SymbolCode.normalize(raw)]
    }

    /// Socket `trade` count per symbol, captured before an in-flight snapshot request.
    func tradeGenerations(for symbols: [String]) -> [String: UInt64] {
        Dictionary(uniqueKeysWithValues: symbols.compactMap { raw in
            let symbol = SymbolCode.normalize(raw)
            guard !symbol.isEmpty else { return nil }
            return (symbol, tradeGeneration[symbol] ?? 0)
        })
    }

    /// Increments per-symbol snapshot request IDs. Capture the result before the REST call.
    func beginSnapshot(for symbols: [String]) -> [String: UInt64] {
        Dictionary(uniqueKeysWithValues: symbols.compactMap { raw in
            let symbol = SymbolCode.normalize(raw)
            guard !symbol.isEmpty else { return nil }
            let next = (snapshotGeneration[symbol] ?? 0) + 1
            snapshotGeneration[symbol] = next
            return (symbol, next)
        })
    }

    func applyTrade(symbol: String, price: Double) {
        guard price.isFinite, price > 0 else { return }
        let symbol = SymbolCode.normalize(symbol)
        guard !symbol.isEmpty else { return }
        tradeGeneration[symbol, default: 0] += 1
        setLast(symbol: symbol, price: price)
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
        if bid != nil {
            current.bidSize = quote.bidSize
        } else if let bidSize = quote.bidSize {
            current.bidSize = bidSize
        }
        if ask != nil {
            current.askSize = quote.askSize
        } else if let askSize = quote.askSize {
            current.askSize = askSize
        }
        quotes[symbol] = current
    }

    func applySnapshot(
        quotes incoming: [StreamQuote],
        trades: [(symbol: String, price: Double)],
        observedTradeGenerations: [String: UInt64] = [:],
        snapshotGenerations: [String: UInt64] = [:]
    ) {
        for quote in incoming {
            let symbol = SymbolCode.normalize(quote.symbol)
            guard !symbol.isEmpty, isCurrentSnapshot(symbol, snapshotGenerations) else { continue }
            var current = quotes[symbol] ?? SymbolQuote()
            if let bid = quote.bid {
                current.snapshotBid = bid
                current.snapshotBidSize = quote.bidSize
            } else if let bidSize = quote.bidSize {
                current.snapshotBidSize = bidSize
            }
            if let ask = quote.ask {
                current.snapshotAsk = ask
                current.snapshotAskSize = quote.askSize
            } else if let askSize = quote.askSize {
                current.snapshotAskSize = askSize
            }
            quotes[symbol] = current
        }
        for trade in trades {
            let symbol = SymbolCode.normalize(trade.symbol)
            guard !symbol.isEmpty, isCurrentSnapshot(symbol, snapshotGenerations) else { continue }
            let current = tradeGeneration[symbol] ?? 0
            let observed = observedTradeGenerations[symbol] ?? 0
            // Socket trade after the request started is newer than this REST payload.
            guard current == observed else { continue }
            setLast(symbol: symbol, price: trade.price)
        }
    }

    private func isCurrentSnapshot(_ symbol: String, _ observed: [String: UInt64]) -> Bool {
        (snapshotGeneration[symbol] ?? 0) == (observed[symbol] ?? 0)
    }

    private func invalidateGenerations(_ symbols: Set<String>) {
        for symbol in symbols {
            tradeGeneration[symbol, default: 0] += 1
            snapshotGeneration[symbol, default: 0] += 1
        }
    }

    private func setLast(symbol: String, price: Double) {
        guard price.isFinite, price > 0 else { return }
        var current = quotes[symbol] ?? SymbolQuote()
        guard current.last != price else { return }
        current.last = price
        quotes[symbol] = current
    }
}
