import SwiftUI

struct EconomicCalendarView: View {
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var insights: InsightsStore

    private var language: String {
        AILanguage.code(locale: preferences.values.locale)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InsightsDisclaimer()
                if let error = insights.calendarError {
                    EmptyStateView(
                        title: L10n.Calendar.loadFailed,
                        message: error,
                        retryTitle: L10n.Calendar.retry,
                        retry: { Task { await insights.refreshCalendar(language: language) } }
                    )
                }
                if insights.calendarLoading && insights.calendar == nil {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            ProgressView()
                            Text(L10n.Calendar.loading)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.top, 40)
                } else if let calendar = insights.calendar {
                    calendarContent(calendar)
                }
            }
            .padding()
        }
        .navigationTitle(L10n.Calendar.title)
        .task(id: language) {
            await insights.refreshCalendar(language: language)
        }
        .refreshable {
            await insights.refreshCalendar(language: language)
        }
    }

    @ViewBuilder
    private func calendarContent(_ calendar: EconomicCalendar) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(calendar.date)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(L10n.Calendar.todayUsEvents)
                .font(.title3.weight(.semibold))
            HStack(spacing: 12) {
                stat(L10n.Calendar.totalEvents, "\(calendar.events.count)")
                stat(L10n.Calendar.highImpact, "\(calendar.highImpactCount)", valueColor: .red)
            }
            if let dayRisk = calendar.dayRisk {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.Calendar.dayRisk)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(dayRisk)
                        .font(.subheadline.weight(.semibold))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(8)
            }
            if !calendar.topEvents.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.Calendar.topEvents)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(Array(calendar.topEvents.prefix(3).enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                if let time = item.time {
                                    Text(time)
                                        .font(.caption.weight(.semibold))
                                }
                            }
                            if let reason = item.reason {
                                Text(reason)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(10)
                        .background(Color(uiColor: .tertiarySystemFill))
                        .cornerRadius(8)
                    }
                }
            }
            InsightBulletList(title: L10n.Calendar.volatilityWindows, items: calendar.volatilityWindows)
            InsightBulletList(title: L10n.Calendar.biasChangingEvents, items: calendar.biasChangingEvents)
            if let phase = calendar.cleanerMarketPhase {
                labeled(L10n.Calendar.cleanerMarketPhase, phase)
            }
            InsightBulletList(title: L10n.Calendar.cautionNotes, items: calendar.cautionNotes)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)

        if calendar.events.isEmpty {
            EmptyStateView(title: L10n.Calendar.emptyTitle, message: L10n.Calendar.emptyBody)
        } else {
            ForEach(calendar.sortedEvents) { event in
                eventCard(event)
            }
        }
    }

    private func eventCard(_ event: EconomicCalendarEvent) -> some View {
        let accent = impactColor(event.impact)
        let meta = [event.country, event.currency].compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let time = event.time {
                    Text(time)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(uiColor: .tertiarySystemFill))
                        .cornerRadius(8)
                }
                if let impact = event.impact {
                    Text(impact.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundColor(accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(accent.opacity(0.15))
                        .cornerRadius(8)
                }
            }
            Text(event.title)
                .font(.headline)
            if !meta.isEmpty {
                Text(meta)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.Calendar.marketFocus)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(event.mainMarketAffected ?? L10n.Calendar.marketFocusFallback)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.opacity(0.08))
            .cornerRadius(8)
            dataPoints(event)
            labeled(L10n.Calendar.expectedMarketImpact, event.expectedMarketImpact)
            labeled(L10n.Calendar.traderNote, event.traderNote)
            labeled(L10n.Calendar.description, event.description)
            if let source = event.source {
                Text("\(L10n.Calendar.source): \(source)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accent, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func dataPoints(_ event: EconomicCalendarEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            point(L10n.Calendar.actual, event.actual)
            point(L10n.Calendar.forecast, event.forecast)
            point(L10n.Calendar.previous, event.previous)
            point(L10n.Calendar.choppinessRisk, event.choppinessRisk)
        }
    }

    @ViewBuilder
    private func point(_ title: String, _ value: String?) -> some View {
        if let value {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    @ViewBuilder
    private func labeled(_ title: String, _ value: String?) -> some View {
        if let value {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.subheadline)
            }
        }
    }

    private func stat(_ title: String, _ value: String, valueColor: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundColor(valueColor)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .tertiarySystemFill))
        .cornerRadius(8)
    }

    private func impactColor(_ impact: String?) -> Color {
        switch impact?.lowercased() {
        case "high": return .red
        case "medium": return .orange
        case "low": return .green
        default: return .blue
        }
    }
}
