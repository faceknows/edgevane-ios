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
