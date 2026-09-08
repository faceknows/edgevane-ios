import Foundation

struct AIAPI {
    var client: HTTPSending

    func marketSentiment(language: String) async throws -> MarketSentiment {
        let data = try await client.sendRaw(
            HTTPRequest(
                method: .get,
                path: "v1/ai/intraday-market-sentiment",
                query: ["language": language]
            )
        )
        return try Self.decodeSentiment(from: data)
    }

    func economicCalendar(language: String) async throws -> EconomicCalendar {
        let data = try await client.sendRaw(
            HTTPRequest(
                method: .get,
                path: "v1/ai/economic-calendar",
                query: ["language": language]
            )
        )
        return try Self.decodeCalendar(from: data)
    }

    static func decodeSentiment(from data: Data) throws -> MarketSentiment {
        let decoder = HTTPClient.makeDecoder()
        if let envelope = try? decoder.decode(JSONEnvelope<SentimentDTO>.self, from: data) {
            return try envelope.data.mapped()
        }
        if let payload = try? decoder.decode(SentimentDTO.self, from: data) {
            return try payload.mapped()
        }
        throw AppError.decoding
    }

    static func decodeCalendar(from data: Data) throws -> EconomicCalendar {
        let decoder = HTTPClient.makeDecoder()
        if let envelope = try? decoder.decode(JSONEnvelope<CalendarDTO>.self, from: data) {
            return envelope.data.mapped()
        }
        if let payload = try? decoder.decode(CalendarDTO.self, from: data) {
            return payload.mapped()
        }
        throw AppError.decoding
    }
}

private struct SentimentDTO: Decodable {
    var available: Bool?
    var market: String?
    var date: String?
    var language: String?
    var provider: String?
    var model: String?
    var sentiment: String?
    var summary: String?
    var confidence: String?
    var scenarios: [ScenarioDTO]?
    var keyDrivers: [String]?
    var intradayBias: String?
    var keyLevels: [String]?
    var bestTradingStyle: String?
    var stayOutConditions: [String]?
    var risks: [String]?
    var sources: [SourceDTO]?
    var message: String?
    var allowedRefetchWindow: String?
    var currentTimeET: String?
    var currentTimeEt: String?

    func mapped() throws -> MarketSentiment {
        guard let available else { throw AppError.decoding }
        if available {
            return .available(
                MarketSentiment.Available(
                    market: market ?? "",
                    date: date ?? "",
                    language: language ?? "",
                    provider: provider,
                    model: model,
                    sentiment: MarketSentimentKind(rawValue: sentiment ?? "") ?? .mixed,
                    summary: summary ?? "",
                    confidence: nonempty(confidence),
                    scenarios: (scenarios ?? []).map { $0.mapped() },
                    keyDrivers: keyDrivers ?? [],
                    intradayBias: nonempty(intradayBias),
                    keyLevels: keyLevels ?? [],
                    bestTradingStyle: nonempty(bestTradingStyle),
                    stayOutConditions: stayOutConditions ?? [],
                    risks: risks ?? [],
                    sources: (sources ?? []).compactMap { $0.mapped() }
                )
            )
        }
        return .unavailable(
            MarketSentiment.Unavailable(
                market: market ?? "",
                date: date ?? "",
                language: language ?? "",
                message: message ?? "",
                allowedRefetchWindow: allowedRefetchWindow ?? "",
                currentTimeET: currentTimeET ?? currentTimeEt ?? ""
            )
        )
    }
}

private struct ScenarioDTO: Decodable {
    var label: String?
    var probability: String?
    var evidence: [String]?
    var confirmationAfterOpen: [String]?
    var invalidation: [String]?

    func mapped() -> MarketSentimentScenario {
        MarketSentimentScenario(
            label: label ?? "",
            probability: probability ?? "",
            evidence: evidence ?? [],
            confirmationAfterOpen: confirmationAfterOpen ?? [],
            invalidation: invalidation ?? []
        )
    }
}

private struct SourceDTO: Decodable {
    var title: String?
    var url: String?

    func mapped() -> MarketSentimentSource? {
        guard let url, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return MarketSentimentSource(title: nonempty(title), url: url)
    }
}

private struct CalendarDTO: Decodable {
    var market: String?
    var date: String?
    var language: String?
    var provider: String?
    var model: String?
    var dayRisk: String?
    var volatilityWindows: [String]?
    var biasChangingEvents: [String]?
    var cleanerMarketPhase: String?
    var cautionNotes: [String]?
    var topEvents: [TopEventDTO]?
    var events: [EventDTO]?

    func mapped() -> EconomicCalendar {
        EconomicCalendar(
            market: market ?? "",
            date: date ?? "",
            language: language ?? "",
            provider: provider,
            model: model,
            dayRisk: nonempty(dayRisk),
            volatilityWindows: volatilityWindows ?? [],
            biasChangingEvents: biasChangingEvents ?? [],
            cleanerMarketPhase: nonempty(cleanerMarketPhase),
            cautionNotes: cautionNotes ?? [],
            topEvents: (topEvents ?? []).compactMap { $0.mapped() },
            events: (events ?? []).compactMap { $0.mapped() }
        )
    }
}

private struct TopEventDTO: Decodable {
    var title: String?
    var time: String?
    var reason: String?

    func mapped() -> EconomicCalendarTopEvent? {
        guard let title, !title.isEmpty else { return nil }
        return EconomicCalendarTopEvent(title: title, time: nonempty(time), reason: nonempty(reason))
    }
}

private struct EventDTO: Decodable {
    var title: String?
    var date: String?
    var time: String?
    var country: String?
    var currency: String?
    var impact: String?
    var actual: String?
    var forecast: String?
    var previous: String?
    var description: String?
    var mainMarketAffected: String?
    var expectedMarketImpact: String?
    var choppinessRisk: String?
    var traderNote: String?
    var source: String?

    func mapped() -> EconomicCalendarEvent? {
        guard let title, !title.isEmpty else { return nil }
        return EconomicCalendarEvent(
            title: title,
            date: date ?? "",
            time: nonempty(time),
            country: nonempty(country),
            currency: nonempty(currency),
            impact: nonempty(impact),
            actual: nonempty(actual),
            forecast: nonempty(forecast),
            previous: nonempty(previous),
            description: nonempty(description),
            mainMarketAffected: nonempty(mainMarketAffected),
            expectedMarketImpact: nonempty(expectedMarketImpact),
            choppinessRisk: nonempty(choppinessRisk),
            traderNote: nonempty(traderNote),
            source: nonempty(source)
        )
    }
}

private func nonempty(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
