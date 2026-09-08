import SwiftUI

struct InsightsDisclaimer: View {
    var body: some View {
        Text(L10n.Common.aiDisclaimer)
            .font(.footnote)
            .foregroundColor(.red)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct InsightBulletList: View {
    var title: String
    var items: [String]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text("• \(item)")
                        .font(.subheadline)
                }
            }
        }
    }
}

struct MarketSentimentView: View {
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var insights: InsightsStore

    private var language: String {
        AILanguage.code(locale: preferences.values.locale)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InsightsDisclaimer()
                if let error = insights.sentimentError {
                    EmptyStateView(
                        title: L10n.Sentiment.loadFailed,
                        message: error,
                        retryTitle: L10n.Sentiment.retry,
                        retry: { Task { await insights.refreshSentiment(language: language) } }
                    )
                }
                if insights.sentimentLoading && insights.sentiment == nil {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            ProgressView()
                            Text(L10n.Sentiment.loading)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.top, 40)
                } else if let sentiment = insights.sentiment {
                    sentimentContent(sentiment)
                }
            }
            .padding()
        }
        .navigationTitle(L10n.Sentiment.title)
        .task(id: language) {
            await insights.refreshSentiment(language: language)
        }
        .refreshable {
            await insights.refreshSentiment(language: language)
        }
    }

    @ViewBuilder
    private func sentimentContent(_ sentiment: MarketSentiment) -> some View {
        switch sentiment {
        case let .unavailable(value):
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.Sentiment.unavailableTitle)
                    .font(.headline)
                Text(value.message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(L10n.Sentiment.allowedWindow(value.allowedRefetchWindow))
                    .font(.subheadline)
                Text(L10n.Sentiment.currentTime(value.currentTimeET))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(12)
        case let .available(value):
            availableContent(value)
        }
    }

    @ViewBuilder
    private func availableContent(_ value: MarketSentiment.Available) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(value.date)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack {
                Text(L10n.Sentiment.label(value.sentiment))
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(L10n.Sentiment.label(value.sentiment))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(color(value.sentiment))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(color(value.sentiment).opacity(0.15))
                    .cornerRadius(8)
            }
            Text(value.summary)
            metricRow(value)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)

        if !value.scenarios.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.Sentiment.scenarios)
                    .font(.headline)
                ForEach(Array(value.scenarios.enumerated()), id: \.offset) { _, scenario in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(L10n.Sentiment.scenarioLabel(scenario.label))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(scenario.probability)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        InsightBulletList(title: L10n.Sentiment.evidence, items: scenario.evidence)
                        InsightBulletList(title: L10n.Sentiment.confirmationAfterOpen, items: scenario.confirmationAfterOpen)
                        InsightBulletList(title: L10n.Sentiment.invalidation, items: scenario.invalidation)
                    }
                    .padding()
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(uiColor: .separator), lineWidth: 1)
                    )
                }
            }
        }

        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Sentiment.plan)
                .font(.headline)
            InsightBulletList(title: L10n.Sentiment.keyDrivers, items: value.keyDrivers)
            InsightBulletList(title: L10n.Sentiment.keyLevels, items: value.keyLevels)
            InsightBulletList(title: L10n.Sentiment.stayOutConditions, items: value.stayOutConditions)
            InsightBulletList(title: L10n.Sentiment.risks, items: value.risks)
        }

        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.Sentiment.sources)
                .font(.headline)
            if value.sources.isEmpty {
                Text(L10n.Sentiment.noSources)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(value.sources.enumerated()), id: \.offset) { _, source in
                    if let url = URL(string: source.url) {
                        Link(destination: url) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.title ?? source.url)
                                    .font(.subheadline.weight(.semibold))
                                Text(source.url)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func metricRow(_ value: MarketSentiment.Available) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let confidence = value.confidence {
                metric(L10n.Sentiment.confidence, confidence)
            }
            if let bias = value.intradayBias {
                metric(L10n.Sentiment.intradayBias, bias)
            }
            if let style = value.bestTradingStyle {
                metric(L10n.Sentiment.bestTradingStyle, style)
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .padding(8)
        .background(Color(uiColor: .tertiarySystemFill))
        .cornerRadius(8)
    }

    private func color(_ kind: MarketSentimentKind) -> Color {
        switch kind {
        case .bullish: return Color(red: 0.11, green: 0.54, blue: 0.35)
        case .bearish: return Color(red: 0.78, green: 0.30, blue: 0.24)
        case .neutral: return .secondary
        case .mixed: return Color(red: 0.75, green: 0.54, blue: 0)
        }
    }
}
