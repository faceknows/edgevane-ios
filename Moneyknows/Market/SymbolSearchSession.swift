import Foundation

@MainActor
final class SymbolSearchSession: ObservableObject {
    @Published var errorText: String?

    private var generation: UInt64 = 0

    func submit(
        _ raw: String,
        lookup: (String) async throws -> SymbolSummary
    ) async -> String? {
        errorText = nil
        let symbol = SymbolCode.normalize(raw)
        generation += 1
        let started = generation
        guard SymbolCode.isValid(symbol) else {
            errorText = L10n.Market.invalidSymbol
            return nil
        }
        do {
            let summary = try await lookup(symbol)
            guard started == generation else { return nil }
            return summary.symbol
        } catch {
            guard started == generation else { return nil }
            if error.isCancellation { return nil }
            errorText = UserFacingError.message(from: error) ?? L10n.Market.unknownSymbol
            return nil
        }
    }
}
