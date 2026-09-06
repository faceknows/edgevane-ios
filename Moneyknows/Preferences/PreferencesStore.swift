import Foundation

@MainActor
final class PreferencesStore: ObservableObject {
    @Published private(set) var values: UserPreferences
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var errorText: String?
    @Published private(set) var localeRevision = 0

    private let api: PreferencesAPI
    private let disk: DiskStore
    private var cachedUserId: String?
    private var fetchedForUserId: String?
    private var activeUserId: String?
    private var epoch: UInt64 = 0
    private var mutationCount: UInt64 = 0
    private var ioChain: Task<Void, Never>?
    private var inflightWrites = 0
    private let valuesFile = "user-preferences.json"
    private let metaFile = "user-preferences-meta.json"

    init(api: PreferencesAPI, disk: DiskStore = DiskStore()) {
        self.api = api
        self.disk = disk
        values = disk.read(UserPreferences.self, name: valuesFile) ?? .defaults
        cachedUserId = disk.read(PreferenceMeta.self, name: metaFile)?.userId
        applyLocalLocale()
    }

    func prepareForUser(_ userId: String) {
        if activeUserId != userId {
            epoch += 1
        }
        if cachedUserId != userId {
            values = .defaults
            cachedUserId = nil
            fetchedForUserId = nil
            persist()
            applyLocalLocale()
        }
        activeUserId = userId
    }

    func markSessionStale() {
        epoch += 1
        fetchedForUserId = nil
        activeUserId = nil
    }

    func refreshIfNeeded(userId: String) async {
        if fetchedForUserId == userId { return }
        await refresh(userId: userId)
    }

    func refresh(userId: String) async {
        bindUserIfNeeded(userId)
        let epoch = self.epoch
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        await enqueue {
            await self.performRefresh(userId: userId, epoch: epoch)
        }
    }

    func apply(_ transform: @escaping (inout UserPreferences) -> Void, patch: UserPreferencePatch, userId: String) async {
        guard activeUserId == userId else { return }
        let epoch = self.epoch
        inflightWrites += 1
        isSaving = true
        defer {
            inflightWrites -= 1
            isSaving = inflightWrites > 0
        }
        await enqueue {
            guard self.isCurrent(epoch: epoch, userId: userId) else { return }
            await self.performApply(transform, patch: patch, userId: userId, epoch: epoch)
        }
    }

    func restoreDefaults(userId: String) async {
        let defaults = UserPreferences.defaults
        await apply({ $0 = defaults }, patch: defaults.patch, userId: userId)
    }

    private func enqueue(_ work: @escaping () async -> Void) async {
        let predecessor = ioChain
        let task = Task { @MainActor in
            await predecessor?.value
            await work()
        }
        ioChain = task
        await task.value
    }

    private func performRefresh(userId: String, epoch: UInt64) async {
        let mutations = mutationCount
        do {
            let previousLocale = values.locale
            let dto = try await api.fetch()
            guard isCurrent(epoch: epoch, userId: userId) else { return }
            guard mutationCount == mutations else { return }
            values = UserPreferences.normalized(from: dto)
            cachedUserId = userId
            fetchedForUserId = userId
            persist()
            applyLocalLocaleIfNeeded(previous: previousLocale)
        } catch {
            guard isCurrent(epoch: epoch, userId: userId) else { return }
            if error.isCancellation { return }
            errorText = UserFacingError.message(from: error)
            AppLog.session.error("preferences refresh failed")
        }
    }

    private func performApply(
        _ transform: @escaping (inout UserPreferences) -> Void,
        patch: UserPreferencePatch,
        userId: String,
        epoch: UInt64
    ) async {
        let previous = values
        transform(&values)
        persist()
        applyLocalLocaleIfNeeded(previous: previous.locale)

        errorText = nil
        do {
            let dto = try await api.patch(patch)
            guard isCurrent(epoch: epoch, userId: userId) else { return }
            values = UserPreferences.normalized(from: dto, fallingBack: values)
            cachedUserId = userId
            fetchedForUserId = userId
            mutationCount += 1
            persist()
            applyLocalLocaleIfNeeded(previous: previous.locale)
        } catch {
            guard isCurrent(epoch: epoch, userId: userId) else { return }
            values = previous
            persist()
            applyLocalLocaleIfNeeded(previous: previous.locale)
            if error.isCancellation { return }
            errorText = UserFacingError.message(from: error)
            AppLog.session.error("preferences patch failed")
        }
    }

    private func bindUserIfNeeded(_ userId: String) {
        if activeUserId == nil {
            activeUserId = userId
        }
    }

    private func isCurrent(epoch: UInt64, userId: String) -> Bool {
        self.epoch == epoch && activeUserId == userId
    }

    private func persist() {
        disk.write(values, name: valuesFile)
        disk.write(PreferenceMeta(userId: cachedUserId), name: metaFile)
    }

    private func applyLocalLocale() {
        applyLocalLocaleIfNeeded(previous: nil, force: true)
    }

    private func applyLocalLocaleIfNeeded(previous: AppLocale?, force: Bool = false) {
        L10n.apply(localeCode: values.locale?.rawValue)
        if force || previous != values.locale {
            localeRevision += 1
        }
    }
}

private struct PreferenceMeta: Codable {
    var userId: String?
}

extension UserPreferences {
    var patch: UserPreferencePatch {
        UserPreferencePatch(
            valuePerTrade: valuePerTrade,
            allowTradeInMinutesAfterOpen: allowTradeInMinutesAfterOpen,
            showOTOAction: showOTOAction,
            showMarketTrade: showMarketTrade,
            autoTakeProfitPercent: autoTakeProfitPercent,
            autoStopLossPercent: autoStopLossPercent,
            showDailyBarInDetail: showDailyBarInDetail,
            showIndexBarInDetail: showIndexBarInDetail,
            notificationVolumeThreshold: notificationVolumeThreshold,
            locale: locale.map { .code($0.rawValue) } ?? .followSystem
        )
    }
}
