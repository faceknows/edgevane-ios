import Foundation

@MainActor
final class TradingSession: ObservableObject {
    let portfolio = PortfolioStore()
    let positions = PositionStore()
    let orders = OrderStore()

    @Published private(set) var needsCredentials = false
    @Published private(set) var notice: String?

    var placement = OrderPlacement()
    var onEntryFill: ((Order) -> Void)?
    var onReset: (() -> Void)?

    private(set) var serving: BrokerageServing?
    private var pollTask: Task<Void, Never>?
    private var orderUpdatesTask: Task<Void, Never>?
    private var unauthorizedUpdatesTask: Task<Void, Never>?
    private var refreshWaiters: [CheckedContinuation<Void, Never>] = []
    private var isRefreshing = false
    private var refreshingEpoch: UInt64 = 0
    private var inFlightIncludesClosed = false
    private var epoch: UInt64 = 0
    private var ordersEpoch: UInt64 = 0
    private var historyLoaded = false
    private var closedBeforeOrderId: String?
    private var closedPageEpoch: UInt64 = 0
    private var isForeground = true
    private var announcedStatuses: [String: OrderStatus] = [:]
    private var knownFilledIds: Set<String> = []
    private var fillInference: [String: Position]?
    private var noticeTask: Task<Void, Never>?
    private let enablesPolling: Bool
    private let closedPageSize: Int
    private let recentClosedLimit: Int
    private let lookupRetryNanoseconds: UInt64
    private let lookupConcurrency: Int
    private let lookupMaxAttempts: Int

    var hasAccount: Bool { serving != nil }
    var environment: BrokerageEnvironment? { serving?.account.environment }
    var tradingBlocked: Bool { portfolio.snapshot?.tradingBlocked == true }
    var isPolling: Bool { pollTask != nil }
    var sessionEpoch: UInt64 { epoch }

    func fills(symbol: String, day: String) async throws -> [Fill] {
        guard let serving else { return [] }
        guard let date = MarketClock.date(fromUSDate: day) else { return [] }
        return try await serving.fills(symbol: symbol, day: date)
    }

    func positionBeforeFill(for raw: String) -> Position? {
        let symbol = SymbolCode.normalize(raw)
        if let snapshot = fillInference {
            return snapshot[symbol]
        }
        return positions.position(for: symbol)
    }

    init(
        enablesPolling: Bool = true,
        closedPageSize: Int = 500,
        recentClosedLimit: Int = 50,
        lookupRetryNanoseconds: UInt64 = 200_000_000,
        lookupConcurrency: Int = 4,
        lookupMaxAttempts: Int = 3
    ) {
        self.enablesPolling = enablesPolling
        self.closedPageSize = closedPageSize
        self.recentClosedLimit = recentClosedLimit
        self.lookupRetryNanoseconds = lookupRetryNanoseconds
        self.lookupConcurrency = max(1, lookupConcurrency)
        self.lookupMaxAttempts = max(1, lookupMaxAttempts)
    }

    func use(_ serving: BrokerageServing?) {
        objectWillChange.send()
        let previousID = self.serving?.account.id
        let previousEnv = self.serving?.account.environment
        epoch += 1
        ordersEpoch += 1
        historyLoaded = false
        closedBeforeOrderId = nil
        closedPageEpoch += 1
        needsCredentials = false
        notice = nil
        announcedStatuses = [:]
        knownFilledIds = []
        noticeTask?.cancel()
        noticeTask = nil
        onReset?()
        self.serving = serving
        if serving == nil {
            stopPolling()
            stopOrderUpdates()
            finishRefreshWaiters()
            clearStores()
            return
        }
        if serving?.account.id != previousID || serving?.account.environment != previousEnv {
            clearStores()
        }
        finishRefreshWaiters()
        if isForeground {
            startPolling()
        }
        if let serving {
            startOrderUpdates(epoch: epoch, serving: serving)
        }
        if enablesPolling {
            Task { await refresh() }
        }
    }

    func reset() {
        objectWillChange.send()
        epoch += 1
        ordersEpoch += 1
        historyLoaded = false
        closedBeforeOrderId = nil
        closedPageEpoch += 1
        serving = nil
        needsCredentials = false
        notice = nil
        announcedStatuses = [:]
        knownFilledIds = []
        noticeTask?.cancel()
        noticeTask = nil
        onReset?()
        stopPolling()
        stopOrderUpdates()
        finishRefreshWaiters()
        clearStores()
    }

    func setForeground(_ foreground: Bool) {
        let wasForeground = isForeground
        isForeground = foreground
        if foreground {
            guard serving != nil, !needsCredentials else { return }
            startPolling()
            if enablesPolling, !wasForeground {
                Task { await refresh(includingClosed: false) }
            }
        } else {
            stopPolling()
        }
    }

    func refresh(includingClosed: Bool = true) async {
        guard serving != nil else { return }
        let epoch = self.epoch
        let loadClosed = includingClosed || !historyLoaded
        if isRefreshing, refreshingEpoch == epoch {
            if loadClosed && !inFlightIncludesClosed {
                await withCheckedContinuation { refreshWaiters.append($0) }
                if self.epoch != epoch {
                    await refresh(includingClosed: includingClosed)
                    return
                }
                await refresh(includingClosed: true)
                return
            }
            await withCheckedContinuation { refreshWaiters.append($0) }
            if self.epoch != epoch {
                await refresh(includingClosed: includingClosed)
            }
            return
        }
        if isRefreshing, refreshingEpoch != epoch {
            finishRefreshWaiters()
        }
        isRefreshing = true
        refreshingEpoch = epoch
        inFlightIncludesClosed = loadClosed
        await performRefresh(epoch: epoch, includingClosed: loadClosed)
        guard refreshingEpoch == epoch else { return }
        isRefreshing = false
        inFlightIncludesClosed = false
        finishRefreshWaiters()
    }

    func cancel(orderId: String) async throws {
        guard let serving else { return }
        try await cancelIds([orderId], serving: serving, epoch: epoch)
    }

    func cancelProtectiveExits(symbol: String, positionSide: PositionSide) async throws {
        guard let serving else { return }
        let ids = OrderSizing.openExitOrders(symbol: symbol, positionSide: positionSide, orders: orders.orders)
            .filter(\.isProtectiveExit)
            .map(\.id)
        try await cancelIds(ids, serving: serving, epoch: epoch)
    }

    func place(
        _ order: NewOrder,
        protectionMinutes: Int,
        maxOrderValue: Double?,
        submitRetries: Int = 0
    ) async throws -> Order {
        let epoch = self.epoch
        guard let serving else { throw TradingGuard.noAccount }
        let rows: [Order]
        do {
            try placement.validate(
                order,
                serving: serving,
                tradingBlocked: tradingBlocked,
                protectionMinutes: protectionMinutes,
                maxOrderValue: maxOrderValue
            )
            try throwIfStale(epoch)
            let release = protectiveReleaseIfNeeded(order)
            var didRelease = false
            do {
                try throwIfStale(epoch)
                if !release.ids.isEmpty {
                    try await cancelIds(release.ids, serving: serving, epoch: epoch) {
                        didRelease = true
                    }
                }
                try throwIfStale(epoch)
                rows = try await submitWithRetries(
                    order,
                    protectionMinutes: protectionMinutes,
                    maxOrderValue: maxOrderValue,
                    extraRetries: submitRetries,
                    serving: serving,
                    epoch: epoch
                )
            } catch {
                if didRelease, !release.snapshot.isEmpty {
                    do {
                        try await restoreProtectiveExits(
                            release.snapshot,
                            serving: serving,
                            extraRetries: submitRetries
                        )
                    } catch {
                        if error.isCancellation { throw error }
                        try throwIfStale(epoch)
                        postNotice(
                            L10n.Trading.protectionRestoreFailed(
                                order.symbol,
                                UserFacingError.message(from: error) ?? L10n.Errors.generic
                            )
                        )
                        throw TradingGuard.protectionRestoreFailed(symbol: order.symbol, error: error)
                    }
                }
                throw error
            }
        } catch {
            guard self.epoch == epoch else { throw AppError.cancelled }
            if error.isUnauthorized {
                markUnauthorized()
            }
            throw error
        }
        guard self.epoch == epoch else { throw AppError.cancelled }
        applyRows(rows, notifyFill: true)
        ordersEpoch += 1
        await loadOrders(serving, epoch: epoch, includingClosed: false)
        await loadPositions(serving, epoch: epoch)
        guard let first = rows.first else { throw AppError.decoding }
        return first
    }

    func replace(
        orderId: String,
        amendment: OrderAmendment,
        original: Order,
        protectionMinutes: Int,
        maxOrderValue: Double?
    ) async throws -> Order {
        let epoch = self.epoch
        let rows: [Order]
        do {
            rows = try await placement.replace(
                orderId: orderId,
                amendment: amendment,
                original: original,
                serving: serving,
                tradingBlocked: tradingBlocked,
                protectionMinutes: protectionMinutes,
                maxOrderValue: maxOrderValue
            )
        } catch {
            guard self.epoch == epoch else { throw AppError.cancelled }
            if error.isUnauthorized {
                markUnauthorized()
            }
            throw error
        }
        guard self.epoch == epoch else { throw AppError.cancelled }
        applyRows(rows, notifyFill: false)
        ordersEpoch += 1
        if let serving {
            await loadOrders(serving, epoch: epoch, includingClosed: false)
        }
        guard let first = rows.first else { throw AppError.decoding }
        return first
    }

    func closePosition(
        _ command: ClosePositionCommand,
        protectionMinutes: Int
    ) async throws {
        let epoch = self.epoch
        let rows: [Order]
        do {
            rows = try await placement.close(
                command,
                serving: serving,
                tradingBlocked: tradingBlocked,
                protectionMinutes: protectionMinutes
            )
        } catch {
            guard self.epoch == epoch else { throw AppError.cancelled }
            if error.isUnauthorized {
                markUnauthorized()
            }
            throw error
        }
        guard self.epoch == epoch else { throw AppError.cancelled }
        applyRows(rows, notifyFill: false)
        ordersEpoch += 1
        if let serving {
            await loadOrders(serving, epoch: epoch, includingClosed: false)
            await loadPositions(serving, epoch: epoch)
            await loadPortfolio(serving, epoch: epoch)
        }
    }

    private struct ProtectiveRelease {
        var snapshot: [NewOrder]
        var ids: [String]
    }

    private func protectiveReleaseIfNeeded(_ order: NewOrder) -> ProtectiveRelease {
        guard let position = positions.position(for: order.symbol), position.quantity > 0 else {
            return ProtectiveRelease(snapshot: [], ids: [])
        }
        let exitSide: OrderSide = position.side == .short ? .buy : .sell
        guard order.side == exitSide else {
            return ProtectiveRelease(snapshot: [], ids: [])
        }
        let open = OrderSizing.openExitOrders(
            symbol: order.symbol,
            positionSide: position.side,
            orders: orders.orders
        ).filter(\.isProtectiveExit)
        return ProtectiveRelease(
            snapshot: ProtectiveExit.snapshots(
                from: orders.orders,
                symbol: order.symbol,
                positionSide: position.side
            ),
            ids: open.map(\.id)
        )
    }

    private func cancelIds(
        _ ids: [String],
        serving: BrokerageServing,
        epoch: UInt64,
        onCancelled: (() -> Void)? = nil
    ) async throws {
        var seen = Set<String>()
        for id in ids where seen.insert(id).inserted {
            try throwIfStale(epoch)
            do {
                try await serving.cancel(orderId: id)
                onCancelled?()
            } catch {
                try throwIfStale(epoch)
                if error.isCancellation { throw error }
                if error.isNotFound { continue }
                if error.isUnauthorized {
                    markUnauthorized()
                }
                throw error
            }
            try throwIfStale(epoch)
            ordersEpoch += 1
            await loadOrders(serving, epoch: epoch, includingClosed: false)
        }
    }

    private func throwIfStale(_ epoch: UInt64) throws {
        guard self.epoch == epoch else { throw AppError.cancelled }
    }

    private func submitWithRetries(
        _ order: NewOrder,
        protectionMinutes: Int,
        maxOrderValue: Double?,
        extraRetries: Int,
        serving: BrokerageServing,
        epoch: UInt64?
    ) async throws -> [Order] {
        var lastError: Error?
        let attempts = max(0, extraRetries) + 1
        for attempt in 0..<attempts {
            if let epoch { try throwIfStale(epoch) }
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if let epoch { try throwIfStale(epoch) }
            }
            do {
                return try await placement.submit(
                    order,
                    serving: serving,
                    tradingBlocked: tradingBlocked,
                    protectionMinutes: protectionMinutes,
                    maxOrderValue: maxOrderValue
                )
            } catch {
                if error.isCancellation { throw error }
                if let epoch { try throwIfStale(epoch) }
                lastError = error
                if !Self.shouldRetrySubmit(error) { break }
            }
        }
        throw lastError ?? AppError.network
    }

    private func restoreProtectiveExits(
        _ snapshot: [NewOrder],
        serving: BrokerageServing,
        extraRetries: Int
    ) async throws {
        var lastError: Error?
        var restored = 0
        for order in snapshot {
            do {
                _ = try await submitWithRetries(
                    order,
                    protectionMinutes: 0,
                    maxOrderValue: nil,
                    extraRetries: extraRetries,
                    serving: serving,
                    epoch: nil
                )
                restored += 1
            } catch {
                if error.isCancellation { throw error }
                lastError = error
                AppLog.trading.error("restore protective exit failed")
            }
        }
        if restored == snapshot.count { return }
        throw lastError ?? AppError.network
    }

    private static func shouldRetrySubmit(_ error: Error) -> Bool {
        guard let appError = error as? AppError, case let .http(_, _, code) = appError else {
            return true
        }
        switch code {
        case "TRADING_PROTECTED", "TRADING_NO_ACCOUNT", "TRADING_BLOCKED",
             "TRADING_MAX_VALUE", "TRADING_INVALID_QTY", "TRADING_INVALID_PRICE",
             "TRADING_OTO_SPREAD", "TRADING_NO_POSITION", "TRADING_INVALID_SYMBOL",
             "TRADING_RESTORE_FAILED":
            return false
        default:
            return true
        }
    }

    func applyStreamData(_ data: Data) {
        guard serving != nil else { return }
        let parsed = MarketStreamPayload.orders(from: data)
        if parsed.isEmpty {
            AppLog.trading.error("trade update ignored")
            return
        }
        for stream in parsed {
            guard let order = Order(stream: stream) else {
                AppLog.trading.error("trade update ignored")
                continue
            }
            applyStream(order)
        }
    }

    func applyStream(_ order: Order) {
        applyRows([order], notifyFill: true)
    }

    func postNotice(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            self?.dismissNotice(text)
        }
    }

    func clearNotice() {
        noticeTask?.cancel()
        noticeTask = nil
        notice = nil
    }

    private func dismissNotice(_ text: String) {
        if notice == text {
            notice = nil
        }
    }

    private func applyRows(_ rows: [Order], notifyFill: Bool) {
        for order in rows {
            let result = orders.applyUpdate(order)
            guard result.accepted else { continue }
            if result.statusChanged, announcedStatuses[order.id] != order.status {
                announcedStatuses[order.id] = order.status
                if let toast = Self.toast(for: order) {
                    postNotice(toast)
                }
            }
            recordFill(order, fire: notifyFill)
        }
    }

    private func recordFill(_ order: Order, fire: Bool) {
        guard order.status == .filled else { return }
        guard knownFilledIds.insert(order.id).inserted else { return }
        if fire, !order.isAutoExit {
            onEntryFill?(order)
        }
    }

    private func harvestFills(fire: Bool) {
        for order in orders.orders {
            recordFill(order, fire: fire)
        }
    }

    private static func toast(for order: Order) -> String? {
        switch order.status {
        case .new, .pendingNew, .accepted, .acceptedForBidding:
            return L10n.Trading.orderAccepted(order.symbol)
        case .filled:
            return L10n.Trading.orderFilled(order.symbol)
        case .canceled:
            return L10n.Trading.orderCanceled(order.symbol)
        case .rejected:
            return L10n.Trading.orderRejected(order.symbol)
        default:
            return nil
        }
    }

    func loadMoreClosed() async {
        guard serving != nil, orders.hasMoreClosed else { return }
        if inFlightIncludesClosed {
            await withCheckedContinuation { refreshWaiters.append($0) }
        }
        guard let serving, orders.hasMoreClosed, !orders.isLoadingMore else { return }
        let epoch = self.epoch
        let ordersEpoch = self.ordersEpoch
        let pageEpoch = closedPageEpoch
        let beforeOrderId = closedBeforeOrderId
        orders.markLoadingMore(true)
        defer { orders.markLoadingMore(false) }
        do {
            let page = try await serving.closedOrders(limit: closedPageSize, beforeOrderId: beforeOrderId)
            guard self.epoch == epoch, self.ordersEpoch == ordersEpoch, self.closedPageEpoch == pageEpoch else {
                return
            }
            if page.hasMore, page.nextBeforeOrderId == beforeOrderId {
                orders.applyClosed(page.orders, replacingClosed: false, hasMore: false)
                return
            }
            orders.applyClosed(page.orders, replacingClosed: false, hasMore: page.hasMore)
            closedBeforeOrderId = page.nextBeforeOrderId
            harvestFills(fire: false)
        } catch {
            guard self.ordersEpoch == ordersEpoch, self.closedPageEpoch == pageEpoch else { return }
            fail(error, epoch: epoch, store: orders)
        }
    }

    private func performRefresh(epoch: UInt64, includingClosed: Bool) async {
        guard let serving, self.epoch == epoch else { return }
        fillInference = positions.positions.reduce(into: [:]) { $0[$1.symbol] = $1 }
        defer { fillInference = nil }
        needsCredentials = false
        let loadingEmpty = portfolio.snapshot == nil && positions.positions.isEmpty && orders.orders.isEmpty
        if loadingEmpty {
            portfolio.markLoading(true)
            positions.markLoading(true)
            orders.markLoading(true)
        }
        async let portfolioResult: Void = loadPortfolio(serving, epoch: epoch)
        async let positionsResult: Void = loadPositions(serving, epoch: epoch)
        async let ordersResult: Void = loadOrders(serving, epoch: epoch, includingClosed: includingClosed)
        _ = await (portfolioResult, positionsResult, ordersResult)
        guard self.epoch == epoch else { return }
        portfolio.markLoading(false)
        positions.markLoading(false)
        orders.markLoading(false)
        if needsCredentials {
            markUnauthorized()
            return
        }
        if isForeground {
            startPolling()
        }
    }

    private func loadPortfolio(_ serving: BrokerageServing, epoch: UInt64) async {
        do {
            let snapshot = try await serving.portfolio()
            guard self.epoch == epoch else { return }
            portfolio.apply(snapshot)
        } catch {
            fail(error, epoch: epoch, store: portfolio)
        }
    }

    private func loadPositions(_ serving: BrokerageServing, epoch: UInt64) async {
        do {
            let rows = try await serving.positions()
            guard self.epoch == epoch else { return }
            positions.apply(rows)
        } catch {
            fail(error, epoch: epoch, store: positions)
        }
    }

    private func loadOrders(_ serving: BrokerageServing, epoch: UInt64, includingClosed: Bool) async {
        let ordersEpoch = self.ordersEpoch
        do {
            let open = try await serving.openOrders()
            guard self.epoch == epoch, self.ordersEpoch == ordersEpoch else { return }
            let disappeared = orders.applyOpen(open)
            if includingClosed {
                closedPageEpoch += 1
                let pageEpoch = closedPageEpoch
                let page = try await serving.closedOrders(limit: closedPageSize, beforeOrderId: nil)
                guard self.epoch == epoch, self.ordersEpoch == ordersEpoch, self.closedPageEpoch == pageEpoch else {
                    return
                }
                orders.applyClosed(page.orders, replacingClosed: true, hasMore: page.hasMore)
                closedBeforeOrderId = page.nextBeforeOrderId
                let shouldFire = historyLoaded
                historyLoaded = true
                harvestFills(fire: shouldFire)
            } else {
                let recent = try await serving.closedOrders(limit: recentClosedLimit, beforeOrderId: nil)
                guard self.epoch == epoch, self.ordersEpoch == ordersEpoch else { return }
                orders.applyClosed(recent.orders, replacingClosed: false)
                harvestFills(fire: historyLoaded)
                let unresolved = disappeared.filter { id in
                    orders.orders.contains { $0.id == id && $0.status.isOpen }
                }
                if !unresolved.isEmpty {
                    await lookupOrders(serving, ids: unresolved, epoch: epoch, ordersEpoch: ordersEpoch)
                }
            }
        } catch {
            guard self.ordersEpoch == ordersEpoch else { return }
            fail(error, epoch: epoch, store: orders)
        }
    }

    private func lookupOrders(
        _ serving: BrokerageServing,
        ids: [String],
        epoch: UInt64,
        ordersEpoch: UInt64
    ) async {
        var pending = ids
        var lastError: Error?
        for attempt in 0..<lookupMaxAttempts {
            guard !pending.isEmpty else { return }
            guard self.epoch == epoch, self.ordersEpoch == ordersEpoch else { return }
            if attempt > 0, lookupRetryNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: lookupRetryNanoseconds)
                guard self.epoch == epoch, self.ordersEpoch == ordersEpoch else { return }
            }
            let round = await lookupRound(serving, ids: pending, epoch: epoch, ordersEpoch: ordersEpoch)
            if round.unauthorized {
                markUnauthorized()
                return
            }
            pending = round.failed
            lastError = round.error
        }
        guard self.epoch == epoch, self.ordersEpoch == ordersEpoch, !pending.isEmpty else { return }
        if let lastError {
            orders.errorText = UserFacingError.message(from: lastError)
            AppLog.trading.error("trading order lookup failed")
        }
    }

    private func lookupRound(
        _ serving: BrokerageServing,
        ids: [String],
        epoch: UInt64,
        ordersEpoch: UInt64
    ) async -> (failed: [String], error: Error?, unauthorized: Bool) {
        var failed: [String] = []
        var lastError: Error?
        var unauthorized = false
        for chunk in chunked(ids, size: lookupConcurrency) {
            guard self.epoch == epoch, self.ordersEpoch == ordersEpoch else {
                return (failed, lastError, unauthorized)
            }
            let outcomes = await withTaskGroup(of: LookupOutcome.self, returning: [LookupOutcome].self) { group in
                for id in chunk {
                    group.addTask {
                        do {
                            let rows = try await serving.order(id: id)
                            return LookupOutcome.success(id: id, orders: rows)
                        } catch {
                            return LookupOutcome.failure(id: id, error: error)
                        }
                    }
                }
                var rows: [LookupOutcome] = []
                for await outcome in group {
                    rows.append(outcome)
                }
                return rows
            }
            for outcome in outcomes {
                switch outcome {
                case let .success(_, rows):
                    guard self.epoch == epoch, self.ordersEpoch == ordersEpoch else { continue }
                    orders.applyClosed(rows, replacingClosed: false)
                    harvestFills(fire: historyLoaded)
                case let .failure(id, error):
                    if error.isUnauthorized {
                        unauthorized = true
                        lastError = error
                        continue
                    }
                    if let appError = error as? AppError, case let .http(status, _, _) = appError, status == 404 {
                        continue
                    }
                    failed.append(id)
                    lastError = error
                }
            }
            if unauthorized {
                return (failed, lastError, true)
            }
        }
        return (failed, lastError, unauthorized)
    }

    private func fail(_ error: Error, epoch: UInt64, store: TradingLoadStore) {
        guard self.epoch == epoch else { return }
        if error.isCancellation { return }
        if error.isUnauthorized {
            markUnauthorized()
            AppLog.trading.error("brokerage unauthorized")
            return
        }
        store.errorText = UserFacingError.message(from: error)
        AppLog.trading.error(
            "trading refresh failed \(String(describing: type(of: store)), privacy: .public) \(error.logCode, privacy: .public)"
        )
    }

    private func markUnauthorized() {
        let already = needsCredentials
        needsCredentials = true
        stopPolling()
        stopOrderUpdates()
        if !already {
            serving?.disconnectStreams()
        }
        let message = L10n.Trading.credentialsInvalid
        portfolio.errorText = message
        positions.errorText = message
        orders.errorText = message
    }

    private func finishRefreshWaiters() {
        let pending = refreshWaiters
        refreshWaiters.removeAll()
        pending.forEach { $0.resume() }
    }

    private func clearStores() {
        portfolio.reset()
        positions.reset()
        orders.reset()
        knownFilledIds = []
        fillInference = nil
    }

    private func startPolling() {
        pollTask?.cancel()
        guard enablesPolling, serving != nil, !needsCredentials else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let delay: UInt64 = MarketClock.isSessionActive(.regular) ? 3_000_000_000 : 15_000_000_000
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                await self?.refresh(includingClosed: false)
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func startOrderUpdates(epoch: UInt64, serving: BrokerageServing) {
        orderUpdatesTask?.cancel()
        unauthorizedUpdatesTask?.cancel()
        orderUpdatesTask = Task { [weak self] in
            for await order in serving.orderUpdates {
                guard let self, self.epoch == epoch else { return }
                self.applyStream(order)
            }
        }
        unauthorizedUpdatesTask = Task { [weak self] in
            for await _ in serving.unauthorizedUpdates {
                guard let self, self.epoch == epoch else { return }
                self.markUnauthorized()
            }
        }
    }

    private func stopOrderUpdates() {
        orderUpdatesTask?.cancel()
        orderUpdatesTask = nil
        unauthorizedUpdatesTask?.cancel()
        unauthorizedUpdatesTask = nil
    }
}

private enum LookupOutcome {
    case success(id: String, orders: [Order])
    case failure(id: String, error: Error)
}

private func chunked<T>(_ items: [T], size: Int) -> [[T]] {
    guard size > 0, !items.isEmpty else { return items.isEmpty ? [] : [items] }
    var pages: [[T]] = []
    var index = 0
    while index < items.count {
        let end = min(index + size, items.count)
        pages.append(Array(items[index..<end]))
        index = end
    }
    return pages
}

@MainActor
private protocol TradingLoadStore: AnyObject {
    var errorText: String? { get set }
}

extension PortfolioStore: TradingLoadStore {}
extension PositionStore: TradingLoadStore {}
extension OrderStore: TradingLoadStore {}
