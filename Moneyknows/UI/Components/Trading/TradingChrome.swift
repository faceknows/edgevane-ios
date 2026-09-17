import SwiftUI

struct EnvironmentBanner: View {
    var environment: BrokerageEnvironment

    var body: some View {
        Text(environment.title)
            .font(.caption2.weight(.semibold))
            .foregroundColor(environment == .live ? .red : .orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(
                Capsule().strokeBorder(
                    environment == .live ? Color.red.opacity(0.35) : Color.orange.opacity(0.35),
                    lineWidth: 1
                )
            )
            .clipShape(Capsule())
            .fixedSize()
    }
}

struct TradingBlockedBanner: View {
    var body: some View {
        Text(L10n.Trading.blocked)
            .font(.caption.weight(.semibold))
            .foregroundColor(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DailyPnLBadge: View {
    var portfolio: Portfolio?

    var body: some View {
        if let portfolio {
            Text(MarketFormat.signedPrice(portfolio.profitLoss))
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundColor(valueColor)
                .accessibilityLabel("\(L10n.Detail.accountPnl) \(MarketFormat.signedPrice(portfolio.profitLoss))")
        }
    }

    private var valueColor: Color {
        switch DailyPnL.tone(percent: portfolio?.profitLossPercent) {
        case .profit: return .green
        case .loss: return .red
        case .warning: return .orange
        }
    }
}

struct DailyPnLText: View {
    var portfolio: Portfolio?
    var showsPercent = true
    var alignment: HorizontalAlignment = .trailing
    var valueFont: Font = .headline.monospacedDigit()
    var percentFont: Font = .caption.monospacedDigit()

    var body: some View {
        Group {
            if let portfolio {
                VStack(alignment: alignment, spacing: 2) {
                    Text(MarketFormat.signedPrice(portfolio.profitLoss))
                        .font(valueFont)
                        .foregroundColor(color)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    if showsPercent {
                        Text(MarketFormat.percent(portfolio.profitLossPercent))
                            .font(percentFont)
                            .foregroundColor(color)
                            .minimumScaleFactor(0.8)
                            .lineLimit(1)
                    }
                }
            } else {
                Text("—")
                    .font(valueFont)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
        .accessibilityLabel(accessibilityText)
    }

    private var frameAlignment: Alignment {
        alignment == .leading ? .leading : .trailing
    }

    private var accessibilityText: String {
        guard let portfolio else { return "—" }
        if showsPercent {
            return "\(MarketFormat.signedPrice(portfolio.profitLoss)) \(MarketFormat.percent(portfolio.profitLossPercent))"
        }
        return MarketFormat.signedPrice(portfolio.profitLoss)
    }

    private var color: Color {
        switch DailyPnL.tone(percent: portfolio?.profitLossPercent) {
        case .profit: return .green
        case .loss: return .red
        case .warning: return .orange
        }
    }
}

struct TradingIssueBanner: View {
    var errorText: String?
    var retry: (() -> Void)? = nil

    @EnvironmentObject private var trading: TradingSession

    var body: some View {
        if trading.needsCredentials {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.Trading.credentialsInvalid)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
                NavigationLink(destination: CredentialsView()) {
                    Text(L10n.Trading.goToCredentials)
                }
                .font(.footnote)
            }
        } else if let errorText, !errorText.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(errorText)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
                if let retry {
                    Button(L10n.Common.retry, action: retry)
                        .font(.footnote)
                }
            }
        }
    }
}

struct NoBrokerageBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.Dashboard.noBrokerage)
                .font(.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink(destination: CredentialsView()) {
                Text(L10n.Trading.goToCredentials)
            }
            .font(.footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TradingCredentialsPrompt: View {
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 16) {
            EmptyStateView(title: title, message: message)
            NavigationLink(destination: CredentialsView()) {
                Text(L10n.Trading.goToCredentials)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

struct TradingNoticeBanner: View {
    @EnvironmentObject private var trading: TradingSession

    var body: some View {
        if let notice = trading.notice, !notice.text.isEmpty {
            ToastCard(id: notice.id, onDismiss: {
                if trading.notice?.id == notice.id {
                    trading.clearNotice()
                }
            }) {
                Text(notice.text)
                    .font(.footnote)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .opacity
            ))
        }
    }
}

struct QuantityMultiplierBar: View {
    var selected: Double
    var onSelect: (Double) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OrderSizing.multipliers, id: \.label) { item in
                Button(item.label) {
                    onSelect(item.value)
                }
                .buttonStyle(.bordered)
                .tint(abs(item.value - selected) < 0.0001 ? .accentColor : .secondary)
            }
        }
    }
}

extension BrokerageEnvironment {
    var title: String {
        self == .live ? L10n.Credentials.live : L10n.Credentials.paper
    }
}

enum TradeConfirmCopy {
    static func message(
        symbol: String,
        side: OrderSide,
        price: Double?,
        quantity: Double,
        environment: BrokerageEnvironment
    ) -> String {
        message(
            symbol: symbol,
            sideTitle: side == .sell ? L10n.Trading.sell : L10n.Trading.buy,
            price: price,
            quantity: quantity,
            environment: environment
        )
    }

    static func message(
        symbol: String,
        sideTitle: String,
        price: Double?,
        quantity: Double,
        environment: BrokerageEnvironment
    ) -> String {
        L10n.Trading.confirmMessage(
            symbol,
            sideTitle,
            MarketFormat.price(price),
            MarketFormat.quantity(quantity),
            environment.title
        )
    }
}
