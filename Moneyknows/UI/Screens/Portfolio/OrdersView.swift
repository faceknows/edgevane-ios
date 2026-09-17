import SwiftUI

struct OrdersView: View {
    @EnvironmentObject private var trading: TradingSession
    @EnvironmentObject private var orders: OrderStore
    @EnvironmentObject private var portfolio: PortfolioStore
    @EnvironmentObject private var brokerage: CurrentBrokerageStore
    @State private var filter: OrderListFilter = .all
    @State private var symbolFilter: String
    @State private var pendingCancel: Order?
    @State private var cancelError: String?

    init(initialSymbol: String = "") {
        _symbolFilter = State(initialValue: initialSymbol)
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
                                        onCancel: { pendingCancel = order }
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
        .alert(
            L10n.Orders.cancelConfirmTitle,
            isPresented: cancelAlertBinding,
            presenting: pendingCancel
        ) { order in
            Button(L10n.Common.cancel, role: .cancel) {}
            Button(L10n.Orders.cancelOrder, role: .destructive) {
                Task { await confirmCancel(order) }
            }
        } message: { order in
            Text(cancelMessage(order))
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

    private func confirmCancel(_ order: Order) async {
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
