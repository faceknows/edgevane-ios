import SwiftUI

struct OrdersView: View {
    @EnvironmentObject private var trading: TradingSession
    @EnvironmentObject private var orders: OrderStore
    @EnvironmentObject private var portfolio: PortfolioStore
    @EnvironmentObject private var brokerage: CurrentBrokerageStore
    @State private var filter: OrderListFilter = .all
    @State private var selectedTodaySymbol: String
    @State private var historyInput = ""
    @State private var historyTask: Task<Void, Never>?
    @State private var cancelPrompt: CancelPrompt?
    @State private var isCancelingAll = false
    @State private var cancelError: String?

    init(initialSymbol: String = "") {
        _selectedTodaySymbol = State(initialValue: SymbolCode.normalize(initialSymbol))
    }

    var body: some View {
        Group {
            if brokerage.current == nil {
                NoBrokerageView()
            } else if trading.needsCredentials, orders.orders.isEmpty {
                TradingCredentialsPrompt(
                    title: L10n.Trading.credentialsInvalid,
                    message: L10n.Trading.credentialsInvalidBody
                )
            } else {
                List {
                    Section {
                        if portfolio.snapshot?.tradingBlocked == true {
                            TradingBlockedBanner()
                        }
                        if !orders.orders.isEmpty {
                            TradingIssueBanner(errorText: orders.errorText) {
                                Task { await trading.refresh() }
                            }
                        }
                        Picker(L10n.Orders.filters, selection: $filter) {
                            ForEach(OrderListFilter.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                        symbolBar
                        if showsCancelAll {
                            HStack {
                                Spacer()
                                Button {
                                    cancelPrompt = .all
                                } label: {
                                    if isCancelingAll {
                                        ProgressView()
                                    } else {
                                        Text(L10n.Orders.cancelAll)
                                            .font(.body.weight(.semibold))
                                            .foregroundColor(.red)
                                    }
                                }
                                .buttonStyle(.borderless)
                                .disabled(isCancelAllDisabled)
                            }
                        }
                    }
                    if let cancelError {
                        Section {
                            FormMessage(text: cancelError)
                        }
                    }
                    if let historyError = orders.historyError {
                        Section {
                            FormMessage(text: historyError)
                        }
                    }
                    if orders.historyLoading {
                        Section {
                            ProgressView().frame(maxWidth: .infinity)
                        }
                    } else if orders.historySymbol != nil {
                        if visibleOrders.isEmpty, orders.historyError == nil {
                            Section {
                                EmptyStateView(
                                    title: L10n.Orders.empty,
                                    message: L10n.Orders.emptyBody
                                )
                            }
                        } else if !visibleOrders.isEmpty {
                            Section {
                                orderRows
                            }
                        }
                    } else if orders.isLoading && orders.orders.isEmpty {
                        Section {
                            ProgressView().frame(maxWidth: .infinity)
                        }
                    } else if let errorText = orders.errorText, orders.orders.isEmpty {
                        Section {
                            EmptyStateView(
                                title: L10n.Errors.generic,
                                message: errorText,
                                retry: { Task { await trading.refresh() } }
                            )
                        }
                    } else if orders.orders.isEmpty, !orders.hasMoreClosed {
                        Section {
                            EmptyStateView(
                                title: L10n.Orders.empty,
                                message: L10n.Orders.emptyBody
                            )
                        }
                    } else {
                        Section {
                            if visibleOrders.isEmpty {
                                EmptyStateView(
                                    title: L10n.Orders.empty,
                                    message: L10n.Orders.emptyBody
                                )
                                .onAppear { Task { await loadMoreIfNeeded() } }
                            } else {
                                orderRows
                            }
                            if orders.hasMoreClosed, orders.isLoadingMore {
                                ProgressView().frame(maxWidth: .infinity)
                            } else if orders.hasMoreClosed, orders.errorText == nil {
                                Color.clear
                                    .frame(height: 1)
                                    .listRowSeparator(.hidden)
                                    .onAppear { Task { await loadMoreIfNeeded() } }
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
                .refreshable { await trading.refresh() }
            }
        }
        .onChange(of: trading.sessionEpoch) { _ in
            historyTask?.cancel()
            historyTask = nil
            historyInput = ""
            selectedTodaySymbol = ""
            cancelError = nil
        }
        .navigationTitle(L10n.Orders.title)
        .alert(
            cancelPromptTitle,
            isPresented: cancelAlertBinding,
            presenting: cancelPrompt
        ) { prompt in
            Button(L10n.Orders.keep, role: .cancel) {}
            Button(L10n.Orders.revoke, role: .destructive) {
                Task { await confirmCancel(prompt) }
            }
        } message: { prompt in
            Text(cancelMessage(prompt))
        }
    }

    private enum CancelPrompt: Identifiable {
        case one(Order)
        case all

        var id: String {
            switch self {
            case .one(let order): return "one-\(order.id)"
            case .all: return "all"
            }
        }
    }

    @ViewBuilder
    private var orderRows: some View {
        ForEach(visibleOrders) { order in
            OrderRow(
                order: order,
                onCancel: { cancelPrompt = .one(order) }
            )
            .onAppear {
                guard order.id == visibleOrders.last?.id else { return }
                Task { await loadMoreIfNeeded() }
            }
        }
    }

    private var todaySymbols: [String] {
        orders.todayFilledSymbols()
    }

    @ViewBuilder
    private var symbolBar: some View {
        HStack(alignment: .center, spacing: 8) {
            if !todaySymbols.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(todaySymbols, id: \.self) { symbol in
                            Button {
                                selectToday(symbol)
                            } label: {
                                Text(symbol)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .foregroundColor(isSelected(symbol) ? .white : .accentColor)
                                    .background(isSelected(symbol) ? Color.accentColor : Color.accentColor.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityAddTraits(isSelected(symbol) ? .isSelected : [])
                        }
                    }
                }
            }
            TextField(L10n.Orders.historySymbol, text: $historyInput)
                .autocapitalization(.allCharacters)
                .disableAutocorrection(true)
                .keyboardType(.asciiCapable)
                .submitLabel(.go)
                .onSubmit { submitHistory() }
                .font(.caption)
                .multilineTextAlignment(.center)
                .frame(width: 76)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }

    private var visibleOrders: [Order] {
        if orders.historySymbol != nil {
            return orders.historyOrders.filter { $0.matches(filter) }
        }
        return orders.filtered(filter, symbol: selectedTodaySymbol)
    }

    private func isSelected(_ symbol: String) -> Bool {
        orders.historySymbol == nil && selectedTodaySymbol == symbol
    }

    private func selectToday(_ symbol: String) {
        historyTask?.cancel()
        historyTask = nil
        orders.clearHistory()
        if selectedTodaySymbol == symbol {
            selectedTodaySymbol = ""
        } else {
            selectedTodaySymbol = symbol
            historyInput = ""
        }
    }

    private func submitHistory() {
        let code = SymbolCode.normalize(historyInput)
        historyInput = code
        historyTask?.cancel()
        guard !code.isEmpty else {
            historyTask = nil
            orders.clearHistory()
            return
        }
        selectedTodaySymbol = ""
        historyTask = Task { await trading.lookupClosedOrders(symbol: code) }
    }

    private func loadMoreIfNeeded() async {
        guard orders.historySymbol == nil, filter != .new, orders.errorText == nil else { return }
        await trading.loadMoreClosed()
    }

    private var showsCancelAll: Bool {
        orders.historySymbol == nil && visibleOrders.contains(where: \.isCancellable)
    }

    private var isCancelAllDisabled: Bool {
        isCancelingAll || trading.needsCredentials
    }

    private var cancelScopeSymbol: String? {
        selectedTodaySymbol.isEmpty ? nil : selectedTodaySymbol
    }

    private var cancelPromptTitle: String {
        switch cancelPrompt {
        case .all: return L10n.Orders.cancelAllConfirmTitle
        default: return L10n.Orders.cancelConfirmTitle
        }
    }

    private var cancelAlertBinding: Binding<Bool> {
        Binding(
            get: { cancelPrompt != nil },
            set: { if !$0 { cancelPrompt = nil } }
        )
    }

    private func cancelMessage(_ prompt: CancelPrompt) -> String {
        let environment = trading.environment == .live ? L10n.Credentials.live : L10n.Credentials.paper
        switch prompt {
        case .one(let order):
            let side = order.side == .sell ? L10n.Orders.sell : L10n.Orders.buy
            return L10n.Orders.cancelConfirmMessage(
                order.symbol,
                side,
                MarketFormat.quantity(order.quantity),
                environment
            )
        case .all:
            let count = orders.cancellable(symbol: cancelScopeSymbol).count
            if let symbol = cancelScopeSymbol {
                return L10n.Orders.cancelAllConfirmMessageSymbol(symbol, count, environment)
            }
            return L10n.Orders.cancelAllConfirmMessage(count, environment)
        }
    }

    private func confirmCancel(_ prompt: CancelPrompt) async {
        cancelPrompt = nil
        switch prompt {
        case .one(let order):
            do {
                try await trading.cancel(orderId: order.id)
                cancelError = nil
            } catch {
                if error.isCancellation { return }
                cancelError = UserFacingError.message(from: error) ?? L10n.Orders.cancelFailed
            }
        case .all:
            isCancelingAll = true
            defer { isCancelingAll = false }
            do {
                try await trading.cancelCancellable(symbol: cancelScopeSymbol)
                cancelError = nil
            } catch {
                if error.isCancellation { return }
                cancelError = UserFacingError.message(from: error) ?? L10n.Orders.cancelFailed
            }
        }
    }
}

private struct OrderRow: View {
    var order: Order
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                HStack(alignment: .center, spacing: 6) {
                    Text(order.symbol)
                        .font(.headline.weight(.bold))
                    Text(order.side == .sell ? L10n.Orders.sell : L10n.Orders.buy)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(order.side == .sell ? .red : .green)
                    Text(verbatim: quantityPriceText)
                        .font(.subheadline.monospacedDigit())
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(summaryLabel)

                Spacer(minLength: 6)

                if order.isCancellable {
                    Button(action: onCancel) {
                        Text(L10n.Orders.revoke)
                            .font(.body.weight(.semibold))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    Spacer(minLength: 6)
                }

                Text(order.status.title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            if order.showsPartialFill {
                Text(L10n.Orders.partialFill(
                    MarketFormat.quantity(order.quantity),
                    MarketFormat.quantity(order.filledQuantity),
                    MarketFormat.quantity(order.remainingQuantity)
                ))
                .font(.caption)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2)
    }

    private var quantityPriceText: String {
        "\(MarketFormat.quantity(order.quantity)) | \(priceText)"
    }

    private var priceText: String {
        if let price = order.rowPrice {
            return MarketFormat.price(price)
        }
        if order.rowShowsMarketPrice {
            return L10n.Orders.priceMarket
        }
        return order.type.title
    }

    private var summaryLabel: String {
        var parts = [
            order.symbol,
            order.side == .sell ? L10n.Orders.sell : L10n.Orders.buy,
            quantityPriceText,
            order.status.title
        ]
        if order.showsPartialFill {
            parts.append(L10n.Orders.partialFill(
                MarketFormat.quantity(order.quantity),
                MarketFormat.quantity(order.filledQuantity),
                MarketFormat.quantity(order.remainingQuantity)
            ))
        }
        return parts.joined(separator: ", ")
    }
}
