import SwiftUI

struct EnvironmentBanner: View {
    var environment: BrokerageEnvironment

    var body: some View {
        Text(environment == .live ? L10n.Credentials.live : L10n.Credentials.paper)
            .font(.caption.weight(.semibold))
            .foregroundColor(environment == .live ? .red : .orange)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(backgroundColor)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        Color(uiColor: .separator),
                        lineWidth: tone == .warning ? 0 : 1
                    )
                )
                .accessibilityLabel("\(L10n.Detail.accountPnl) \(MarketFormat.signedPrice(portfolio.profitLoss))")
        }
    }

    private var tone: DailyPnL.Tone {
        DailyPnL.tone(percent: portfolio?.profitLossPercent)
    }

    private var valueColor: Color {
        switch tone {
        case .profit: return .green
        case .loss, .warning: return .red
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .warning: return Color.orange.opacity(0.85)
        case .profit, .loss: return Color(uiColor: .secondarySystemBackground)
        }
    }
}

struct DailyPnLText: View {
    var portfolio: Portfolio?
    var showsPercent = true

    var body: some View {
        if let portfolio {
            VStack(alignment: .trailing, spacing: 2) {
                Text(MarketFormat.signedPrice(portfolio.profitLoss))
                    .font(.headline.monospacedDigit())
                    .foregroundColor(color)
                if showsPercent {
                    Text(MarketFormat.percent(portfolio.profitLossPercent))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(color)
                }
            }
        } else {
            Text("—")
                .foregroundColor(.secondary)
        }
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
        if let notice = trading.notice, !notice.isEmpty {
            Button {
                trading.clearNotice()
            } label: {
                Text(notice)
                    .font(.footnote)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(Color(uiColor: .secondarySystemBackground))
            }
            .buttonStyle(.plain)
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
        L10n.Trading.confirmMessage(
            symbol,
            side == .sell ? L10n.Trading.sell : L10n.Trading.buy,
            MarketFormat.price(price),
            MarketFormat.quantity(quantity),
            environment.title
        )
    }
}
