import Foundation

enum MarketStreamEvent {
    static let trade = "trade"
    static let quote = "quote"
    static let secondTrade = "second-trade"
    static let tradeUpdates = "trade_updates"
}

@MainActor
final class MarketRealtimeSession: ObservableObject {
    @Published private(set) var socketStatus: SocketStatus = .closed

    let subscriptions: SubscriptionStore
    let quotes: QuoteStore
    let seconds: SecondBarStore

    private let socket: MarketSocketing
    private let barsAPI: BarsAPI
    private var snapshotTask: Task<Void, Never>?
    private var didBindSocket = false
    var onTradeUpdate: ((Data) -> Void)?

    init(
        subscriptions: SubscriptionStore,
        quotes: QuoteStore,
        seconds: SecondBarStore,
        socket: MarketSocketing,
        barsAPI: BarsAPI
    ) {
        self.subscriptions = subscriptions
        self.quotes = quotes
        self.seconds = seconds
        self.socket = socket
        self.barsAPI = barsAPI
        bindSocket()
    }

    var isSocketConnected: Bool { socketStatus.isConnected }

    func connect(token: String?) {
        guard let token, !token.isEmpty else {
            disconnect()
            return
        }
        socket.connect(token: token)
    }

    func reconnect(token: String?) {
        connect(token: token)
    }

    func disconnect() {
        snapshotTask?.cancel()
        snapshotTask = nil
        socket.disconnect()
    }

    func reset() {
        snapshotTask?.cancel()
        snapshotTask = nil
        subscriptions.reset()
        quotes.reset()
        seconds.reset()
        disconnect()
    }

    func refreshSubscriptions() async {
        let previous = Set(subscriptions.me)
        await subscriptions.refresh()
        dropRemoved(previous: previous)
        await refreshSnapshots()
        startSnapshotLoop()
    }

    func subscribe(_ symbols: [String]) async throws {
        let previous = Set(subscriptions.me)
        try await subscriptions.subscribe(symbols)
        dropRemoved(previous: previous)
        await refreshSnapshots()
        startSnapshotLoop()
    }

    func unsubscribe(_ symbols: [String]) async throws {
        let previous = Set(subscriptions.me)
        try await subscriptions.unsubscribe(symbols)
        dropRemoved(previous: previous)
        startSnapshotLoop()
    }

    func handle(event: String, data: Data) {
        switch event {
        case MarketStreamEvent.trade:
            guard let trade = MarketStreamPayload.trade(from: data),
                  subscriptions.contains(trade.symbol)
            else { return }
            quotes.applyTrade(symbol: trade.symbol, price: trade.price)
        case MarketStreamEvent.quote:
            guard let quote = MarketStreamPayload.quote(from: data),
                  subscriptions.contains(quote.symbol)
            else { return }
            quotes.applyQuote(quote)
        case MarketStreamEvent.secondTrade:
            guard let bar = MarketStreamPayload.secondBar(from: data),
                  subscriptions.contains(bar.symbol)
            else { return }
            seconds.apply(bar)
        case MarketStreamEvent.tradeUpdates:
            onTradeUpdate?(data)
        default:
            break
        }
    }

    private func bindSocket() {
        guard !didBindSocket else { return }
        didBindSocket = true
        socket.onStatusChange { [weak self] status in
            Task { @MainActor in
                self?.socketStatus = status
            }
        }
        socket.on(MarketStreamEvent.trade) { [weak self] data in
            Task { @MainActor in self?.handle(event: MarketStreamEvent.trade, data: data) }
        }
        socket.on(MarketStreamEvent.quote) { [weak self] data in
            Task { @MainActor in self?.handle(event: MarketStreamEvent.quote, data: data) }
        }
        socket.on(MarketStreamEvent.secondTrade) { [weak self] data in
            Task { @MainActor in self?.handle(event: MarketStreamEvent.secondTrade, data: data) }
        }
        socket.on(MarketStreamEvent.tradeUpdates) { [weak self] data in
            Task { @MainActor in self?.handle(event: MarketStreamEvent.tradeUpdates, data: data) }
        }
        socketStatus = socket.status
    }

    private func dropRemoved(previous: Set<String>) {
        let removed = previous.subtracting(subscriptions.me)
        guard !removed.isEmpty else { return }
        let symbols = Array(removed)
        quotes.remove(symbols)
        seconds.remove(symbols)
    }

    private func refreshSnapshots() async {
        let symbols = subscriptions.me
        guard !symbols.isEmpty else { return }
        do {
            let data = try await barsAPI.latestSnapshot(symbols: symbols)
            quotes.applySnapshot(
                quotes: MarketStreamPayload.snapshotQuotes(from: data),
                trades: MarketStreamPayload.snapshotTrades(from: data)
            )
        } catch {
            if error.isCancellation { return }
            AppLog.market.error("latest snapshot failed")
        }
    }

    private func startSnapshotLoop() {
        snapshotTask?.cancel()
        guard !subscriptions.me.isEmpty else { return }
        snapshotTask = Task { [weak self] in
            while !Task.isCancelled {
                let delay: UInt64 = MarketClock.isSessionActive(.regular) ? 5_000_000_000 : 15_000_000_000
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                await self?.refreshSnapshots()
            }
        }
    }
}
