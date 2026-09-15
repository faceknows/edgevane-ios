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

    var barTitle: String {
        switch self {
        case .buy: return L10n.Trading.buyAtBid
        case .sell: return L10n.Trading.sellAtAsk
        case .limitClose: return L10n.Trading.liquidateLimit
        case .stopLoss: return L10n.Trading.stop
        default: return title
        }
    }

    func isBuyTint(positionSide: PositionSide?) -> Bool {
        switch self {
        case .buy, .otoBuy, .slider:
            return true
        case .sell, .otoSell:
            return false
        case .takeProfit, .stopLoss, .limitClose, .marketClose:
            return positionSide == .short
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

private enum TradeBarPalette {
    static let buy = Color(red: 88 / 255, green: 86 / 255, blue: 214 / 255)
    static let sell = Color(red: 233 / 255, green: 78 / 255, blue: 142 / 255)
}

private struct TradeFilledLabel: View {
    var title: String
    var tint: Color
    var dimmed: Bool = false

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.75)
            .lineLimit(2)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(tint)
            .cornerRadius(10)
            .opacity(dimmed ? 0.45 : 1)
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
    @EnvironmentObject private var orders: OrderStore
    @EnvironmentObject private var quotes: QuoteStore
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var blacklist: AutoExitBlacklistStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                actionCard
                if preferences.values.isAutoTakeProfitOn || preferences.values.isAutoStopLossOn {
                    blacklistToggles
                }
            }
        }
    }

    private var position: Position? {
        positions.position(for: symbol)
    }

    private var openPosition: Position? {
        guard let position, position.absQuantity > 0 else { return nil }
        return position
    }

    private var tradingBlocked: Bool {
        portfolio.snapshot?.tradingBlocked == true
    }

    private var hasActionableOrders: Bool {
        let code = SymbolCode.normalize(symbol)
        return orders.orders.contains {
            $0.symbol == code && $0.status.showsOnDetailTradeBar
        }
    }

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let openPosition {
                positionPanel(openPosition)
            }
            buttonStack
        }
        .padding(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(uiColor: .separator), lineWidth: 1)
        )
    }

    private func positionPanel(_ position: Position) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.Trading.openPosition)
                    .foregroundColor(.secondary)
                Spacer(minLength: 8)
                Text(vsLiveText(for: position))
                    .fontWeight(.semibold)
                    .foregroundColor(vsLiveColor(for: position))
                    .multilineTextAlignment(.trailing)
            }
            .font(.caption)
            HStack(alignment: .top) {
                positionCell(
                    L10n.Trading.positionType,
                    position.side == .short ? L10n.Positions.short : L10n.Positions.long,
                    valueColor: position.side == .short ? .red : .green
                )
                positionCell(
                    L10n.Positions.quantity,
                    MarketFormat.quantity(position.signedQuantity)
                )
                positionCell(
                    L10n.Trading.filledAvg,
                    MarketFormat.price(position.averageEntry)
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemFill))
        .cornerRadius(10)
    }

    private func positionCell(_ label: String, _ value: String, valueColor: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body.weight(.semibold))
                .foregroundColor(valueColor)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var buttonStack: some View {
        VStack(spacing: 8) {
            if openPosition != nil {
                HStack(spacing: 8) {
                    tradeButton(.limitClose)
                    tradeButton(.takeProfit)
                    tradeButton(.stopLoss)
                }
                if preferences.values.showMarketTrade {
                    tradeButton(.marketClose)
                }
            }
            if hasActionableOrders {
                NavigationLink(destination: OrdersView(initialSymbol: symbol)) {
                    TradeFilledLabel(title: L10n.Orders.title, tint: TradeBarPalette.sell)
                }
            }
            HStack(spacing: 8) {
                if preferences.values.showOTOAction {
                    tradeButton(.otoBuy)
                    tradeButton(.otoSell)
                }
                tradeButton(.buy)
                tradeButton(.sell)
            }
        }
    }

    private func tradeButton(_ kind: TradeActionKind) -> some View {
        Button {
            presetPrice = nil
            action = kind
        } label: {
            TradeFilledLabel(
                title: kind.barTitle,
                tint: kind.isBuyTint(positionSide: openPosition?.side)
                    ? TradeBarPalette.buy
                    : TradeBarPalette.sell,
                dimmed: tradingBlocked
            )
        }
        .buttonStyle(.plain)
        .disabled(tradingBlocked)
    }

    private func vsLiveText(for position: Position) -> String {
        guard let live = quotes.quote(for: symbol)?.tapePrice,
              let percent = position.unrealizedPercent(versus: live) else {
            return L10n.Trading.waitingForPrice
        }
        return L10n.Trading.vsPrice(MarketFormat.percent(percent), MarketFormat.price(live))
    }

    private func vsLiveColor(for position: Position) -> Color {
        guard let live = quotes.quote(for: symbol)?.tapePrice,
              let percent = position.unrealizedPercent(versus: live) else {
            return .secondary
        }
        return MarketFormat.changeColor(percent)
    }

    @ViewBuilder
    private var blacklistToggles: some View {
        VStack(alignment: .leading, spacing: 8) {
            if preferences.values.isAutoTakeProfitOn {
                Toggle(L10n.Prefs.autoTakeProfit, isOn: takeProfitApplies)
            }
            if preferences.values.isAutoStopLossOn {
                Toggle(L10n.Prefs.autoStopLoss, isOn: stopLossApplies)
            }
        }
        .font(.footnote)
    }

    private var takeProfitApplies: Binding<Bool> {
        Binding(
            get: { !blacklist.isTakeProfitBlocked(symbol) },
            set: { enabled in
                if enabled {
                    blacklist.removeTakeProfit(symbol)
                } else {
                    blacklist.addTakeProfit(symbol)
                }
            }
        )
    }

    private var stopLossApplies: Binding<Bool> {
        Binding(
            get: { !blacklist.isStopLossBlocked(symbol) },
            set: { enabled in
                if enabled {
                    blacklist.removeStopLoss(symbol)
                } else {
                    blacklist.addStopLoss(symbol)
                }
            }
        )
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
    var onDismiss: (() -> Void)? = nil
    var onBusyChange: ((Bool) -> Void)? = nil

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
    @FocusState private var focusedField: TradeTicketField?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ticketHeader
                quoteStrip
                if let remaining = remainingProtection {
                    Text(L10n.Trading.protectionWindow(remaining))
                        .font(.footnote)
                        .foregroundColor(.red)
                }
                if action == .marketClose {
                    Toggle(L10n.Trading.cancelOpenOrders, isOn: $cancelOpenOrders)
                } else {
                    orderFields
                }
                if let errorText {
                    FormMessage(text: errorText)
                }
                actionButtons
            }
            .padding(20)
        }
        .frame(maxHeight: 620)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
        .padding(.horizontal, 18)
        .onAppear(perform: populate)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L10n.Common.done) {
                    focusedField = nil
                }
            }
        }
    }

    private var ticketHeader: some View {
        HStack(spacing: 8) {
            Text(actionLabel)
                .foregroundColor(actionTint)
            Text(SymbolCode.normalize(symbol))
                .foregroundColor(.primary)
            EnvironmentBanner(environment: environment)
            Spacer(minLength: 8)
            Button(L10n.Common.close, action: dismiss)
                .foregroundColor(.primary)
                .disabled(busy)
        }
        .font(.title3.weight(.bold))
    }

    private var quoteStrip: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(MarketFormat.price(quote?.last))
                .font(.title3.monospacedDigit())
            Spacer(minLength: 8)
            Text(L10n.Trading.quoteLabel)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            quoteValue(quote?.liveBid, size: quote?.displayBidSize)
            Text("|").foregroundColor(.secondary)
            quoteValue(quote?.liveAsk, size: quote?.displayAskSize)
        }
        .accessibilityElement(children: .combine)
    }

    private func quoteValue(_ price: Double?, size: Double?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(MarketFormat.price(price))
                .font(.headline.monospacedDigit())
            if let size {
                Text(MarketFormat.quantity(size))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var actionLabel: String {
        guard action != .slider else { return action.title }
        let side = resolvedSide == .buy ? L10n.Trading.buy : L10n.Trading.sell
        let wrapped = "(\(side.uppercased()))"
        if action == .buy || action == .sell {
            return wrapped
        }
        return "\(wrapped) \(action.title)"
    }

    private var actionTint: Color {
        action.isBuyTint(positionSide: position?.side) ? TradeBarPalette.buy : TradeBarPalette.sell
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 12) {
            EnvironmentBanner(environment: environment)
            if action == .slider {
                submitButton(title: L10n.Trading.buy, side: .buy, tint: TradeBarPalette.buy)
                submitButton(title: L10n.Trading.sell, side: .sell, tint: TradeBarPalette.sell)
            } else {
                submitButton(title: L10n.Common.confirm, side: resolvedSide, tint: actionTint)
            }
            Button(L10n.Common.cancel, action: dismiss)
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .padding(.horizontal, 8)
                .disabled(busy)
        }
    }

    private func submitButton(title: String, side: OrderSide, tint: Color) -> some View {
        Button {
            guard !busy else { return }
            setBusy(true)
            Task { await submit(side: side) }
        } label: {
            Group {
                if busy {
                    ProgressView().tint(.white)
                } else {
                    Text(title).fontWeight(.semibold)
                }
            }
            .frame(minWidth: 70)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .foregroundColor(.white)
            .background(tint)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel("\(title) · \(environment.title)")
    }

    @ViewBuilder
    private var orderFields: some View {
        VStack(spacing: 16) {
            if action != .stopLoss {
                HStack(spacing: 8) {
                    ForEach(OrderSizing.multipliers, id: \.label) { item in
                        Button(item.label) {
                            multiplier = item.value
                            applyMultiplier()
                        }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundColor(isSelected(item.value) ? .white : .secondary)
                        .background(isSelected(item.value) ? Color.accentColor : Color(uiColor: .secondarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                inputRow(
                    title: L10n.Trading.quantity,
                    text: $quantityInput,
                    field: .quantity,
                    decrement: { adjustQuantity(by: -1) },
                    increment: { adjustQuantity(by: 1) }
                )
            } else {
                Picker(L10n.Trading.quantity, selection: $stopMode) {
                    ForEach(StopQuantityMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: stopMode) { _ in applyStopQuantity() }
                inputRow(
                    title: L10n.Trading.quantity,
                    text: $quantityInput,
                    field: .quantity,
                    decrement: { adjustQuantity(by: -1) },
                    increment: { adjustQuantity(by: 1) }
                )
            }
            inputRow(
                title: L10n.Trading.price,
                text: $priceInput,
                field: .price,
                decrement: { adjustPrice(by: -OrderSizing.minimumPriceDelta) },
                increment: { adjustPrice(by: OrderSizing.minimumPriceDelta) }
            )
            if action == .otoBuy || action == .otoSell {
                inputRow(
                    title: L10n.Trading.takeProfitPrice,
                    text: $takeProfitInput,
                    field: .takeProfit,
                    decrement: { adjustTakeProfit(by: -OrderSizing.minimumPriceDelta) },
                    increment: { adjustTakeProfit(by: OrderSizing.minimumPriceDelta) }
                )
            }
            if showsExtendedHours {
                Toggle(L10n.Trading.extendedHours, isOn: $extendedHours)
            }
        }
    }

    private func inputRow(
        title: String,
        text: Binding<String>,
        field: TradeTicketField,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Text(title)
                .foregroundColor(.secondary)
                .frame(width: 112, alignment: .leading)
            TextField(title, text: text)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: field)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(Color(uiColor: .secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(uiColor: .separator), lineWidth: 1)
                )
            stepButton(systemName: "minus", action: decrement)
            stepButton(systemName: "plus", action: increment)
        }
    }

    private func stepButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline.weight(.bold))
                .frame(width: 30, height: 34)
        }
        .buttonStyle(.plain)
        .foregroundColor(.primary)
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

    private func isSelected(_ value: Double) -> Bool {
        abs(value - multiplier) < 0.0001
    }

    private func adjustQuantity(by delta: Double) {
        let current = TradeInput.parse(quantityInput) ?? 1
        quantityInput = format(max(1, current + delta))
        stopMode = action == .stopLoss ? .custom : stopMode
    }

    private func adjustPrice(by delta: Double) {
        let current = TradeInput.parse(priceInput) ?? quote?.referencePrice(for: resolvedSide) ?? 0
        priceInput = format(max(0.01, current + delta))
    }

    private func adjustTakeProfit(by delta: Double) {
        let current = TradeInput.parse(takeProfitInput) ?? TradeInput.parse(priceInput) ?? 0
        takeProfitInput = format(max(0.01, current + delta))
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

    private func submit(side: OrderSide) async {
        errorText = nil
        defer { setBusy(false) }
        do {
            let pending = try makePending(side: side)
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
            dismiss()
        } catch {
            if error.isCancellation { return }
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

    private func dismiss() {
        if let onDismiss {
            onDismiss()
        } else {
            presentationMode.wrappedValue.dismiss()
        }
    }

    private func setBusy(_ value: Bool) {
        busy = value
        onBusyChange?(value)
    }

    private func format(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }
}

private enum TradeTicketField: Hashable {
    case quantity
    case price
    case takeProfit
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
