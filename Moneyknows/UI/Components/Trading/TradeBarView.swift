import SwiftUI

enum TradeActionKind: String, Identifiable, Equatable {
    case buy
    case sell
    case otoBuy
    case otoSell
    case takeProfit
    case stopLoss
    case limitClose
    case marketClose
    case slider

    var id: String { rawValue }

    var title: String {
        switch self {
        case .buy: return L10n.Trading.buy
        case .sell: return L10n.Trading.sell
        case .otoBuy: return L10n.Trading.otoBuy
        case .otoSell: return L10n.Trading.otoSell
        case .takeProfit: return L10n.Trading.takeProfit
        case .stopLoss: return L10n.Trading.stopLoss
        case .limitClose: return L10n.Trading.limitClose
        case .marketClose: return L10n.Trading.marketClose
        case .slider: return L10n.Trading.sliderTitle
        }
    }

    var side: OrderSide? {
        switch self {
        case .buy, .otoBuy: return .buy
        case .sell, .otoSell: return .sell
        case .slider, .takeProfit, .stopLoss, .limitClose, .marketClose: return nil
        }
    }

    var usesPosition: Bool {
        switch self {
        case .takeProfit, .stopLoss, .limitClose, .marketClose:
            return true
        default:
            return false
        }
    }
}

struct TradeBarView: View {
    let symbol: String
    @Binding var action: TradeActionKind?
    @Binding var presetPrice: Double?

    @EnvironmentObject private var trading: TradingSession
    @EnvironmentObject private var brokerage: CurrentBrokerageStore
    @EnvironmentObject private var portfolio: PortfolioStore
    @EnvironmentObject private var positions: PositionStore
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var blacklist: AutoExitBlacklistStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let environment = trading.environment ?? brokerage.current?.environment {
                EnvironmentBanner(environment: environment)
            }
            if brokerage.current == nil {
                TradingCredentialsPrompt(
                    title: L10n.Dashboard.noBrokerage,
                    message: L10n.Trading.addCredentialsBody
                )
            } else if trading.needsCredentials {
                TradingCredentialsPrompt(
                    title: L10n.Trading.credentialsInvalid,
                    message: L10n.Trading.credentialsInvalidBody
                )
            } else {
                if portfolio.snapshot?.tradingBlocked == true {
                    TradingBlockedBanner()
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8)], spacing: 8) {
                    tradeButton(.buy)
                    tradeButton(.sell)
                    if preferences.values.showOTOAction {
                        tradeButton(.otoBuy)
                        tradeButton(.otoSell)
                    }
                    if position != nil {
                        tradeButton(.takeProfit)
                        tradeButton(.stopLoss)
                        tradeButton(.limitClose)
                        if preferences.values.showMarketTrade {
                            tradeButton(.marketClose)
                        }
                    }
                }
                blacklistToggles
            }
        }
        .sheet(item: $action) { item in
            NavigationView {
                TradeTicketView(symbol: symbol, action: item, presetPrice: presetPrice)
            }
            .navigationViewStyle(.stack)
        }
    }

    private var position: Position? {
        positions.position(for: symbol)
    }

    private func tradeButton(_ kind: TradeActionKind) -> some View {
        Button(kind.title) {
            presetPrice = nil
            action = kind
        }
        .buttonStyle(.bordered)
        .disabled(portfolio.snapshot?.tradingBlocked == true)
    }

    private var blacklistToggles: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(
                blacklist.isTakeProfitBlocked(symbol)
                    ? L10n.Trading.allowTakeProfit
                    : L10n.Trading.blockTakeProfit
            ) {
                if blacklist.isTakeProfitBlocked(symbol) {
                    blacklist.removeTakeProfit(symbol)
                } else {
                    blacklist.addTakeProfit(symbol)
                }
            }
            .font(.footnote)
            Button(
                blacklist.isStopLossBlocked(symbol)
                    ? L10n.Trading.allowStopLoss
                    : L10n.Trading.blockStopLoss
            ) {
                if blacklist.isStopLossBlocked(symbol) {
                    blacklist.removeStopLoss(symbol)
                } else {
                    blacklist.addStopLoss(symbol)
                }
            }
            .font(.footnote)
        }
    }
}

struct PriceSliderTradeView: View {
    var range: ClosedRange<Double>
    var onConfirm: (Double) -> Void

    @State private var price: Double
    @State private var lockedRange: ClosedRange<Double>
    @State private var lockUntil = Date.distantPast
    @State private var dragging = false

    init(range: ClosedRange<Double>, onConfirm: @escaping (Double) -> Void) {
        self.range = range
        self.onConfirm = onConfirm
        let bounds = OrderSizing.sliderBounds(range)
        _price = State(initialValue: (bounds.lowerBound + bounds.upperBound) / 2)
        _lockedRange = State(initialValue: bounds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.Trading.sliderHint)
                .font(.footnote)
                .foregroundColor(.secondary)
            HStack {
                Text(MarketFormat.price(activeRange.lowerBound))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                Slider(
                    value: clampedPrice,
                    in: activeRange,
                    step: step,
                    onEditingChanged: editingChanged
                )
                Text(MarketFormat.price(activeRange.upperBound))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            Text(MarketFormat.price(clampedPrice.wrappedValue))
                .font(.headline.monospacedDigit())
                .frame(maxWidth: .infinity)
        }
        .onChange(of: range.lowerBound) { _ in refreshRangeIfUnlocked() }
        .onChange(of: range.upperBound) { _ in refreshRangeIfUnlocked() }
    }

    private var activeRange: ClosedRange<Double> {
        let raw = dragging || Date() < lockUntil ? lockedRange : range
        return OrderSizing.sliderBounds(raw)
    }

    private var step: Double {
        OrderSizing.sliderStep(span: activeRange.upperBound - activeRange.lowerBound)
    }

    private var clampedPrice: Binding<Double> {
        Binding(
            get: { OrderSizing.clampSliderPrice(price, in: activeRange) },
            set: { price = $0 }
        )
    }

    private func editingChanged(_ editing: Bool) {
        if editing {
            dragging = true
            lockedRange = OrderSizing.sliderBounds(range)
            lockUntil = Date().addingTimeInterval(OrderSizing.sliderLockDuration)
            price = OrderSizing.clampSliderPrice(price, in: lockedRange)
        } else {
            dragging = false
            lockUntil = Date().addingTimeInterval(OrderSizing.sliderLockDuration)
            onConfirm(OrderSizing.clampSliderPrice(price, in: activeRange))
        }
    }

    private func refreshRangeIfUnlocked() {
        guard !dragging, Date() >= lockUntil else { return }
        lockedRange = OrderSizing.sliderBounds(range)
        price = OrderSizing.clampSliderPrice(price, in: lockedRange)
    }
}

struct TradeTicketView: View {
    let symbol: String
    let action: TradeActionKind
    var presetPrice: Double?

    @EnvironmentObject private var trading: TradingSession
    @EnvironmentObject private var brokerage: CurrentBrokerageStore
    @EnvironmentObject private var portfolio: PortfolioStore
    @EnvironmentObject private var positions: PositionStore
    @EnvironmentObject private var orders: OrderStore
    @EnvironmentObject private var quotes: QuoteStore
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.presentationMode) private var presentationMode

    @State private var quantityInput = ""
    @State private var priceInput = ""
    @State private var takeProfitInput = ""
    @State private var multiplier = 1.0
    @State private var extendedHours = false
    @State private var cancelOpenOrders = true
    @State private var stopMode: StopQuantityMode = .available
    @State private var errorText: String?
    @State private var busy = false
    @State private var pending: PendingTrade?

    var body: some View {
        Form {
            if let environment = trading.environment ?? brokerage.current?.environment {
                Section {
                    EnvironmentBanner(environment: environment)
                    if portfolio.snapshot?.tradingBlocked == true {
                        TradingBlockedBanner()
                    }
                    if let remaining = remainingProtection {
                        Text(L10n.Trading.protectionWindow(remaining))
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
            }
            if action == .marketClose {
                marketCloseFields
            } else {
                orderFields
            }
            if let errorText {
                Section {
                    FormMessage(text: errorText)
                }
            }
            Section {
                if action == .slider {
                    PrimaryButton(title: L10n.Trading.buy, busy: busy) {
                        prepareConfirm(side: .buy)
                    }
                    Button(L10n.Trading.sell) {
                        prepareConfirm(side: .sell)
                    }
                    .buttonStyle(.bordered)
                    .disabled(busy)
                    .frame(maxWidth: .infinity)
                } else {
                    PrimaryButton(title: L10n.Trading.submit, busy: busy) {
                        prepareConfirm(side: resolvedSide)
                    }
                }
            }
        }
        .navigationTitle(action.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.Common.cancel) {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
        .onAppear(perform: populate)
        .alert(L10n.Trading.confirmTitle, isPresented: confirmBinding) {
            Button(L10n.Common.cancel, role: .cancel) {
                pending = nil
            }
            Button(L10n.Common.confirm) {
                Task { await submitPending() }
            }
        } message: {
            if let pending {
                Text(pending.confirmMessage(environment: environment))
            }
        }
    }

    @ViewBuilder
    private var orderFields: some View {
        Section {
            TextField(L10n.Trading.quantity, text: $quantityInput)
                .keyboardType(.decimalPad)
            if action != .stopLoss {
                QuantityMultiplierBar(selected: multiplier) { value in
                    multiplier = value
                    applyMultiplier()
                }
            } else {
                Picker(L10n.Trading.quantity, selection: $stopMode) {
                    ForEach(StopQuantityMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: stopMode) { _ in applyStopQuantity() }
            }
        }
        if action != .marketClose {
            Section {
                TextField(L10n.Trading.price, text: $priceInput)
                    .keyboardType(.decimalPad)
                if action == .otoBuy || action == .otoSell {
                    TextField(L10n.Trading.takeProfitPrice, text: $takeProfitInput)
                        .keyboardType(.decimalPad)
                }
                if showsExtendedHours {
                    Toggle(L10n.Trading.extendedHours, isOn: $extendedHours)
                }
            }
        }
    }

    private var marketCloseFields: some View {
        Section {
            Toggle(L10n.Trading.cancelOpenOrders, isOn: $cancelOpenOrders)
        }
    }

    private var showsExtendedHours: Bool {
        action != .stopLoss && action != .marketClose
    }

    private var position: Position? {
        positions.position(for: symbol)
    }

    private var quote: SymbolQuote? {
        quotes.quote(for: symbol)
    }

    private var environment: BrokerageEnvironment {
        trading.environment ?? brokerage.current?.environment ?? .paper
    }

    private var remainingProtection: Int? {
        MarketClock.remainingOpeningProtectionMinutes(
            minutes: preferences.values.allowTradeInMinutesAfterOpen
        )
    }

    private var maxOrderValue: Double? {
        profile.roleConfiguration?.maxOrderValue
    }

    private var resolvedSide: OrderSide {
        if let side = action.side { return side }
        if let position {
            return position.side == .short ? .buy : .sell
        }
        return .sell
    }

    private var confirmBinding: Binding<Bool> {
        Binding(
            get: { pending != nil },
            set: { if !$0 { pending = nil } }
        )
    }

    private func populate() {
        extendedHours = MarketClock.isExtendedHoursSession()
        if action.usesPosition, position == nil {
            errorText = L10n.Trading.noPosition
        }
        let side = resolvedSide
        let reference: Double?
        switch action {
        case .takeProfit, .stopLoss, .limitClose:
            reference = quote?.mid ?? position?.currentPrice
        case .slider:
            reference = presetPrice
        default:
            reference = quote?.referencePrice(for: side) ?? presetPrice
        }
        if let reference {
            priceInput = format(reference)
            if action == .otoBuy {
                takeProfitInput = format(reference + OrderSizing.minimumPriceDelta)
            } else if action == .otoSell {
                takeProfitInput = format(max(0.01, reference - OrderSizing.minimumPriceDelta))
            }
        }
        if action == .stopLoss {
            applyStopQuantity()
        } else if action.usesPosition, let position {
            quantityInput = format(position.quantity)
        } else if let reference {
            quantityInput = String(OrderSizing.shares(
                valuePerTrade: preferences.values.valuePerTrade,
                price: reference,
                multiplier: multiplier
            ))
        }
    }

    private func applyMultiplier() {
        let price = TradeInput.parse(priceInput) ?? quote?.referencePrice(for: resolvedSide)
        guard let price else { return }
        quantityInput = String(OrderSizing.shares(
            valuePerTrade: preferences.values.valuePerTrade,
            price: price,
            multiplier: multiplier
        ))
    }

    private func applyStopQuantity() {
        guard let position else {
            quantityInput = ""
            return
        }
        switch stopMode {
        case .available:
            quantityInput = format(OrderSizing.availableExitQuantity(position: position, openOrders: orders.orders))
        case .total:
            quantityInput = format(position.quantity)
        case .custom:
            if TradeInput.parse(quantityInput) == nil {
                quantityInput = format(position.quantity)
            }
        }
    }

    private func prepareConfirm(side: OrderSide?) {
        errorText = nil
        do {
            pending = try makePending(side: side ?? resolvedSide)
        } catch {
            errorText = UserFacingError.message(from: error) ?? L10n.Trading.submitFailed
        }
    }

    private func makePending(side: OrderSide) throws -> PendingTrade {
        if action == .marketClose {
            guard position != nil else { throw TradingGuard.noPosition }
            return .close(
                ClosePositionCommand(symbol: symbol, cancelOpenOrders: cancelOpenOrders),
                side: side,
                quantity: position?.quantity ?? 0,
                price: nil
            )
        }
        let quantity = try parsedQuantity()
        let price = try parsedPrice()
        let order: NewOrder
        switch action {
        case .buy, .sell, .slider, .limitClose, .takeProfit:
            order = NewOrder(
                symbol: symbol,
                side: side,
                kind: .limit,
                quantity: quantity,
                limitPrice: price,
                extendedHours: extendedHours
            )
        case .otoBuy, .otoSell:
            guard let takeProfit = TradeInput.parse(takeProfitInput) else { throw TradingGuard.invalidPrice }
            order = NewOrder(
                symbol: symbol,
                side: side,
                kind: .oto,
                quantity: quantity,
                limitPrice: price,
                takeProfitLimitPrice: takeProfit,
                extendedHours: extendedHours
            )
        case .stopLoss:
            order = NewOrder(
                symbol: symbol,
                side: side,
                kind: .stop,
                quantity: quantity,
                stopPrice: price,
                extendedHours: false
            )
        case .marketClose:
            throw TradingGuard.invalidPrice
        }
        try OrderPlacement().validate(
            order,
            serving: trading.serving,
            tradingBlocked: trading.tradingBlocked,
            protectionMinutes: preferences.values.allowTradeInMinutesAfterOpen,
            maxOrderValue: maxOrderValue
        )
        return .place(order)
    }

    private func parsedQuantity() throws -> Double {
        guard let quantity = TradeInput.parse(quantityInput), quantity >= 1 else {
            throw TradingGuard.invalidQuantity
        }
        return quantity
    }

    private func parsedPrice() throws -> Double {
        guard let price = TradeInput.parse(priceInput), price > 0 else {
            throw TradingGuard.invalidPrice
        }
        return price
    }

    private func submitPending() async {
        guard let pending else { return }
        self.pending = nil
        busy = true
        defer { busy = false }
        do {
            switch pending {
            case let .place(order):
                _ = try await trading.place(
                    order,
                    protectionMinutes: preferences.values.allowTradeInMinutesAfterOpen,
                    maxOrderValue: maxOrderValue
                )
            case let .close(command, _, _, _):
                try await trading.closePosition(
                    command,
                    protectionMinutes: preferences.values.allowTradeInMinutesAfterOpen
                )
            }
            errorText = nil
            presentationMode.wrappedValue.dismiss()
        } catch {
            if error.isCancellation { return }
            errorText = UserFacingError.message(from: error) ?? L10n.Trading.submitFailed
        }
    }

    private func format(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }
}

enum TradeInput {
    static func parse(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(trimmed), value.isFinite else { return nil }
        return value
    }
}

enum PendingTrade: Identifiable {
    case place(NewOrder)
    case close(ClosePositionCommand, side: OrderSide, quantity: Double, price: Double?)

    var id: String {
        switch self {
        case let .place(order):
            return "place-\(order.symbol)-\(order.side.rawValue)-\(order.quantity)"
        case let .close(command, _, _, _):
            return "close-\(command.symbol)"
        }
    }

    func confirmMessage(environment: BrokerageEnvironment) -> String {
        switch self {
        case let .place(order):
            return TradeConfirmCopy.message(
                symbol: order.symbol,
                side: order.side,
                price: order.displayPrice,
                quantity: order.quantity,
                environment: environment
            )
        case let .close(command, side, quantity, price):
            return TradeConfirmCopy.message(
                symbol: command.symbol,
                side: side,
                price: price,
                quantity: quantity,
                environment: environment
            )
        }
    }
}
