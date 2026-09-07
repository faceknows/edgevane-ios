import SwiftUI

struct OrdersView: View {
    @EnvironmentObject private var trading: TradingSession
    @EnvironmentObject private var orders: OrderStore
    @EnvironmentObject private var portfolio: PortfolioStore
    @EnvironmentObject private var brokerage: CurrentBrokerageStore
    @State private var filter: OrderListFilter = .all
    @State private var symbolFilter = ""
    @State private var pendingCancel: Order?
    @State private var pendingAmend: Order?
    @State private var cancelError: String?

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
                        if let environment = trading.environment ?? brokerage.current?.environment {
                            EnvironmentBanner(environment: environment)
                        }
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
                        TextField(L10n.Orders.symbolFilter, text: $symbolFilter)
                            .autocapitalization(.allCharacters)
                            .disableAutocorrection(true)
                    }
                    if let cancelError {
                        Section {
                            FormMessage(text: cancelError)
                        }
                    }
                    if orders.isLoading && orders.orders.isEmpty {
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
                            } else {
                                ForEach(visibleOrders) { order in
                                    OrderRow(
                                        order: order,
                                        onCancel: { pendingCancel = order },
                                        onAmend: { pendingAmend = order }
                                    )
                                }
                            }
                            if orders.hasMoreClosed {
                                Text(L10n.Orders.historyIncomplete)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                Button(L10n.Orders.loadMore) {
                                    Task { await trading.loadMoreClosed() }
                                }
                                .disabled(orders.isLoadingMore)
                                if orders.isLoadingMore {
                                    ProgressView().frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                }
                .refreshable { await trading.refresh() }
            }
        }
        .navigationTitle(L10n.Orders.title)
        .alert(L10n.Orders.cancelConfirmTitle, isPresented: cancelAlertBinding) {
            Button(L10n.Common.cancel, role: .cancel) {
                pendingCancel = nil
            }
            Button(L10n.Orders.cancelOrder, role: .destructive) {
                Task { await confirmCancel() }
            }
        } message: {
            if let pendingCancel {
                Text(cancelMessage(pendingCancel))
            }
        }
        .sheet(item: $pendingAmend) { order in
            NavigationView {
                AmendOrderView(order: order)
            }
            .navigationViewStyle(.stack)
        }
    }

    private var visibleOrders: [Order] {
        orders.filtered(filter, symbol: symbolFilter)
    }

    private var cancelAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingCancel != nil },
            set: { if !$0 { pendingCancel = nil } }
        )
    }

    private func cancelMessage(_ order: Order) -> String {
        let environment = trading.environment == .live ? L10n.Credentials.live : L10n.Credentials.paper
        let side = order.side == .sell ? L10n.Orders.sell : L10n.Orders.buy
        return L10n.Orders.cancelConfirmMessage(
            order.symbol,
            side,
            MarketFormat.quantity(order.quantity),
            environment
        )
    }

    private func confirmCancel() async {
        guard let order = pendingCancel else { return }
        pendingCancel = nil
        do {
            try await trading.cancel(orderId: order.id)
            cancelError = nil
        } catch {
            if error.isCancellation { return }
            cancelError = UserFacingError.message(from: error) ?? L10n.Orders.cancelFailed
        }
    }
}

private struct OrderRow: View {
    var order: Order
    var onCancel: () -> Void
    var onAmend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(order.symbol).font(.headline)
                Text(order.side == .sell ? L10n.Orders.sell : L10n.Orders.buy)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(order.side == .sell ? .red : .green)
                Spacer()
                Text(order.status.title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(quantityLine)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                priceColumn
            }
            if order.isCancellable {
                HStack {
                    if order.isAmendable {
                        Button(L10n.Orders.amendOrder, action: onAmend)
                            .font(.caption)
                            .buttonStyle(.borderless)
                    }
                    Button(L10n.Orders.cancelOrder, role: .destructive, action: onCancel)
                        .font(.caption)
                        .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var quantityLine: String {
        if order.showsPartialFill {
            let fill = L10n.Orders.partialFill(
                MarketFormat.quantity(order.filledQuantity),
                MarketFormat.quantity(order.quantity),
                MarketFormat.quantity(order.remainingQuantity)
            )
            return "\(fill) · \(order.type.title)"
        }
        return "\(MarketFormat.quantity(order.listQuantity)) · \(order.type.title)"
    }

    @ViewBuilder
    private var priceColumn: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if order.showsPartialFill {
                if let avg = order.filledAvgPrice {
                    Text(L10n.Orders.priceAverage(MarketFormat.price(avg)))
                }
                if let limit = order.limitPrice {
                    Text(L10n.Orders.priceLimit(MarketFormat.price(limit)))
                }
                if let stop = order.stopPrice {
                    Text(L10n.Orders.priceStop(MarketFormat.price(stop)))
                }
            } else if let price = order.listPrice {
                Text(MarketFormat.price(price))
            }
        }
        .font(.caption.monospacedDigit())
    }
}

struct AmendOrderView: View {
    let order: Order
    @EnvironmentObject private var trading: TradingSession
    @EnvironmentObject private var brokerage: CurrentBrokerageStore
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.presentationMode) private var presentationMode

    @State private var quantityInput = ""
    @State private var priceInput = ""
    @State private var errorText: String?
    @State private var busy = false
    @State private var confirming = false

    var body: some View {
        Form {
            Section {
                if let environment = trading.environment ?? brokerage.current?.environment {
                    EnvironmentBanner(environment: environment)
                }
                TextField(L10n.Trading.quantity, text: $quantityInput)
                    .keyboardType(.decimalPad)
                TextField(L10n.Trading.price, text: $priceInput)
                    .keyboardType(.decimalPad)
            }
            if let errorText {
                Section {
                    FormMessage(text: errorText)
                }
            }
            Section {
                PrimaryButton(title: L10n.Orders.amendOrder, busy: busy) {
                    confirming = true
                }
            }
        }
        .navigationTitle(L10n.Orders.amendOrder)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.Common.cancel) {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
        .onAppear {
            if order.quantity == order.quantity.rounded() {
                quantityInput = String(Int(order.quantity))
            } else {
                quantityInput = String(format: "%.4f", order.quantity)
            }
            if let price = order.limitPrice ?? order.stopPrice {
                priceInput = String(format: "%.2f", price)
            }
        }
        .alert(L10n.Orders.amendConfirmTitle, isPresented: $confirming) {
            Button(L10n.Common.cancel, role: .cancel) {}
            Button(L10n.Common.confirm) {
                Task { await submit() }
            }
        } message: {
            Text(confirmMessage)
        }
    }

    private var environment: BrokerageEnvironment {
        trading.environment ?? brokerage.current?.environment ?? .paper
    }

    private var confirmMessage: String {
        L10n.Orders.amendConfirmMessage(
            order.symbol,
            order.side == .sell ? L10n.Orders.sell : L10n.Orders.buy,
            quantityInput,
            priceInput,
            environment.title
        )
    }

    private func submit() async {
        errorText = nil
        guard let quantity = TradeInput.parse(quantityInput), let price = TradeInput.parse(priceInput) else {
            errorText = L10n.Trading.invalidPrice
            return
        }
        var amendment = OrderAmendment()
        amendment.quantity = quantity
        if order.type == .stop {
            amendment.stopPrice = price
        } else {
            amendment.limitPrice = price
        }
        busy = true
        defer { busy = false }
        do {
            _ = try await trading.replace(
                orderId: order.id,
                amendment: amendment,
                original: order,
                protectionMinutes: preferences.values.allowTradeInMinutesAfterOpen,
                maxOrderValue: profile.roleConfiguration?.maxOrderValue
            )
            presentationMode.wrappedValue.dismiss()
        } catch {
            if error.isCancellation { return }
            errorText = UserFacingError.message(from: error) ?? L10n.Orders.amendFailed
        }
    }
}
