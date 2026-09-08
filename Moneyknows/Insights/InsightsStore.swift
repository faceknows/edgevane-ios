import Foundation

@MainActor
final class InsightsStore: ObservableObject {
    @Published private(set) var sentiment: MarketSentiment?
    @Published private(set) var sentimentLoading = false
    @Published private(set) var sentimentError: String?

    @Published private(set) var calendar: EconomicCalendar?
    @Published private(set) var calendarLoading = false
    @Published private(set) var calendarError: String?

    private let api: AIAPI
    private var sentimentEpoch: UInt64 = 0
    private var calendarEpoch: UInt64 = 0
    private var lastSentimentLanguage: String?
    private var lastCalendarLanguage: String?

    init(api: AIAPI) {
        self.api = api
    }

    func reset() {
        sentimentEpoch += 1
        calendarEpoch += 1
        sentiment = nil
        sentimentLoading = false
        sentimentError = nil
        calendar = nil
        calendarLoading = false
        calendarError = nil
        lastSentimentLanguage = nil
        lastCalendarLanguage = nil
    }

    func refreshSentiment(language: String) async {
        sentimentEpoch += 1
        let epoch = sentimentEpoch
        if lastSentimentLanguage != language {
            sentiment = nil
        }
        lastSentimentLanguage = language
        sentimentLoading = true
        sentimentError = nil
        do {
            let result = try await api.marketSentiment(language: language)
            guard epoch == sentimentEpoch else { return }
            sentiment = result
            sentimentLoading = false
        } catch {
            if error.isCancellation { return }
            guard epoch == sentimentEpoch else { return }
            sentimentError = UserFacingError.message(from: error) ?? L10n.Sentiment.loadFailed
            sentimentLoading = false
        }
    }

    func refreshCalendar(language: String) async {
        calendarEpoch += 1
        let epoch = calendarEpoch
        if lastCalendarLanguage != language {
            calendar = nil
        }
        lastCalendarLanguage = language
        calendarLoading = true
        calendarError = nil
        do {
            let result = try await api.economicCalendar(language: language)
            guard epoch == calendarEpoch else { return }
            calendar = result
            calendarLoading = false
        } catch {
            if error.isCancellation { return }
            guard epoch == calendarEpoch else { return }
            calendarError = UserFacingError.message(from: error) ?? L10n.Calendar.loadFailed
            calendarLoading = false
        }
    }
}
