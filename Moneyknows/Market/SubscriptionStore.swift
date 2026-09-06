import Foundation

@MainActor
final class SubscriptionStore: ObservableObject {
    @Published private(set) var me: [String] = []
    @Published private(set) var all: [String] = []
    @Published private(set) var isLoading = false
    @Published var errorText: String?

    private let api: SubscribeAPI
    private var epoch: UInt64 = 0
    private var inflight: Task<Void, Error>?

    init(api: SubscribeAPI) {
        self.api = api
    }

    func reset() {
        epoch += 1
        inflight?.cancel()
        inflight = nil
        me = []
        all = []
        isLoading = false
        errorText = nil
    }

    func contains(_ raw: String) -> Bool {
        me.contains(SymbolCode.normalize(raw))
    }

    func refresh() async {
        let epoch = self.epoch
        inflight?.cancel()
        isLoading = me.isEmpty
        errorText = nil
        let task = Task { @MainActor in
            let listed = try await api.list()
            guard self.epoch == epoch else { throw AppError.cancelled }
            apply(listed)
        }
        inflight = task
        do {
            try await task.value
        } catch {
            guard self.epoch == epoch else { return }
            if error.isCancellation { return }
            errorText = UserFacingError.message(from: error)
            AppLog.market.error("subscriptions refresh failed")
        }
        if self.epoch == epoch {
            isLoading = false
        }
    }

    func subscribe(_ raw: [String]) async throws {
        let symbols = Self.normalize(raw)
        guard !symbols.isEmpty else { return }
        let epoch = self.epoch
        try await api.subscribe(symbols: symbols)
        guard self.epoch == epoch else { throw AppError.cancelled }
        me = Self.normalize(me + symbols)
        await refresh()
    }

    func unsubscribe(_ raw: [String]) async throws {
        let symbols = Self.normalize(raw)
        guard !symbols.isEmpty else { return }
        let epoch = self.epoch
        try await api.unsubscribe(symbols: symbols)
        guard self.epoch == epoch else { throw AppError.cancelled }
        let removed = Set(symbols)
        me = me.filter { !removed.contains($0) }
        await refresh()
    }

    private func apply(_ dto: SubscriptionsDTO) {
        all = dto.all
        me = dto.me
        errorText = nil
    }

    private static func normalize(_ symbols: [String]) -> [String] {
        Array(Set(symbols.map(SymbolCode.normalize).filter { !$0.isEmpty })).sorted()
    }
}
