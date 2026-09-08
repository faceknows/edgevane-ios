import Foundation

@MainActor
final class NotificationStore: ObservableObject {
    static let cacheName = "notifications-store.json"
    static let toastDuration: UInt64 = 6_000_000_000

    @Published private(set) var items: [AppNotification] = []
    @Published private(set) var toast: AppNotification?
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = true
    @Published private(set) var errorText: String?
    @Published var selectedType: NotificationKind?
    @Published var symbolFilter = ""
    private(set) var isActive = false
    private(set) var ownerUserId: String?

    private let api: PushAPI
    private let disk: DiskStoring
    private var lastRefreshedAt: Date?
    private var fetchedForUserId: String?
    private var fetchedFilterType: String?
    private var historyCursor: Int64?
    private var realtimeById: [String: AppNotification] = [:]
    private var toastTask: Task<Void, Never>?
    private var refreshEpoch: UInt64 = 0

    init(api: PushAPI, disk: DiskStoring = DiskStore()) {
        self.api = api
        self.disk = disk
    }

    static func cacheName(for userId: String) -> String {
        "notifications-store.\(sanitizedUserId(userId)).json"
    }

    func visibleItems(volumeThreshold: Int) -> [AppNotification] {
        NotificationVolume.filter(
            NotificationParser.filter(
                NotificationParser.filter(items, type: selectedType),
                symbols: symbolFilter
            ),
            threshold: volumeThreshold
        )
    }

    func hasActiveFilters(volumeThreshold: Int = 0) -> Bool {
        selectedType != nil
            || !symbolFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || volumeThreshold > 0
    }

    func resetFilters() {
        selectedType = nil
        symbolFilter = ""
    }

    func activate(userId: String) {
        prepareForUser(userId)
        isActive = true
    }

    func prepareForUser(_ userId: String) {
        if ownerUserId == userId { return }
        ownerUserId = userId
        items = NotificationHistory.sort(disk.read([AppNotification].self, name: Self.cacheName(for: userId)) ?? [])
            .filter { belongsToCurrentUser($0, userId: userId) }
            .map { stamped($0, userId: userId) }
        selectedType = nil
        symbolFilter = ""
        errorText = nil
        lastRefreshedAt = nil
        fetchedForUserId = nil
        fetchedFilterType = nil
        historyCursor = nil
        realtimeById = [:]
        hasMore = true
        clearToast()
    }

    func refreshIfNeeded(userId: String?, volumeThreshold: Int = 0) async {
        guard let userId else {
            reset()
            return
        }
        prepareForUser(userId)
        if fetchedForUserId == userId, lastRefreshedAt != nil, fetchedFilterType == currentFilterTypeKey {
            return
        }
        await refresh(userId: userId, volumeThreshold: volumeThreshold)
    }

    func refreshOnFocus(userId: String?, volumeThreshold: Int = 0) async {
        guard let userId else {
            reset()
            return
        }
        prepareForUser(userId)
        if fetchedForUserId == userId,
           fetchedFilterType == currentFilterTypeKey,
           let lastRefreshedAt,
           Date().timeIntervalSince(lastRefreshedAt) < 60
        {
            return
        }
        await refresh(userId: userId, volumeThreshold: volumeThreshold)
    }

    func refresh(userId: String?, volumeThreshold: Int = 0) async {
        guard let userId else {
            reset()
            return
        }
        prepareForUser(userId)
        refreshEpoch += 1
        let epoch = refreshEpoch
        let requestType = currentFilterTypeKey
        if fetchedFilterType != requestType {
            historyCursor = nil
            fetchedFilterType = nil
            hasMore = false
        }
        errorText = nil
        isLoadingMore = false
        if items.isEmpty {
            isLoading = true
        } else {
            isRefreshing = true
        }
        do {
            let next = try await api.history(limit: PushAPI.pageSize, type: historyTypeParam)
            guard epoch == refreshEpoch, ownerUserId == userId else { return }
            replace(next, userId: userId)
            isLoading = false
            isRefreshing = false
            await continueThroughFilteredPages(userId: userId, volumeThreshold: volumeThreshold)
        } catch {
            if error.isCancellation {
                if epoch == refreshEpoch {
                    isLoading = false
                    isRefreshing = false
                }
                return
            }
            guard epoch == refreshEpoch else { return }
            errorText = UserFacingError.message(from: error) ?? L10n.Notifications.loadFailed
            isLoading = false
            isRefreshing = false
        }
    }

    private func loadMorePage(userId: String, epoch: UInt64) async -> Bool {
        guard epoch == refreshEpoch, ownerUserId == userId, hasMore else {
            return false
        }
        guard let lastTime = historyCursor ?? items.last?.sentAt else {
            return false
        }
        do {
            let next = try await api.history(
                limit: PushAPI.pageSize,
                lastTime: lastTime,
                type: historyTypeParam
            )
            guard epoch == refreshEpoch, ownerUserId == userId else { return false }
            let owned = next.map { stamped($0, userId: userId) }.filter { belongsToCurrentUser($0, userId: userId) }
            let existing = Set(items.map(\.id))
            let unique = owned.filter { !existing.contains($0.id) }
            items = NotificationHistory.sort(items + unique)
            let previousCursor = historyCursor
            if let oldest = next.map(\.sentAt).min() {
                historyCursor = oldest
            }
            let cursorMoved = historyCursor != previousCursor
            hasMore = next.count == PushAPI.pageSize
            persist()
            return !unique.isEmpty || (hasMore && cursorMoved)
        } catch {
            if error.isCancellation {
                return false
            }
            guard epoch == refreshEpoch else { return false }
            errorText = UserFacingError.message(from: error) ?? L10n.Notifications.loadFailed
            return false
        }
    }

    func loadMore(userId: String?, volumeThreshold: Int = 0) async {
        guard let userId,
              ownerUserId == userId,
              fetchedForUserId == userId,
              fetchedFilterType == currentFilterTypeKey,
              hasMore,
              !isLoading,
              !isRefreshing,
              !isLoadingMore,
              historyCursor != nil || items.last != nil
        else { return }
        isLoadingMore = true
        errorText = nil
        let epoch = refreshEpoch
        defer {
            if epoch == refreshEpoch {
                isLoadingMore = false
            }
        }
        while hasMore {
            let added = await loadMorePage(userId: userId, epoch: epoch)
            guard epoch == refreshEpoch else { return }
            guard added else { return }
            if !hasActiveFilters(volumeThreshold: volumeThreshold) { return }
            if visibleItems(volumeThreshold: volumeThreshold).count >= PushAPI.pageSize { return }
        }
    }

    func continueThroughFilteredPages(userId: String?, volumeThreshold: Int) async {
        guard hasActiveFilters(volumeThreshold: volumeThreshold),
              visibleItems(volumeThreshold: volumeThreshold).count < PushAPI.pageSize
        else { return }
        await loadMore(userId: userId, volumeThreshold: volumeThreshold)
    }

    func ingest(_ notification: AppNotification, showToast: Bool, volumeThreshold: Int, userId: String? = nil) {
        let owner = userId ?? ownerUserId
        guard isActive, let owner, ownerUserId == owner, !notification.id.isEmpty else { return }
        if let incoming = notification.ownerUserId, incoming != owner { return }
        let item = stamped(notification, userId: owner)
        realtimeById[item.id] = item
        items = NotificationHistory.sort([item] + items.filter { $0.id != item.id })
        persistUnfilteredCache(merging: item)
        if showToast, NotificationVolume.passes(item, threshold: volumeThreshold) {
            presentToast(item)
        }
    }

    func clearToast() {
        toastTask?.cancel()
        toastTask = nil
        toast = nil
    }

    func reset() {
        isActive = false
        refreshEpoch += 1
        if let ownerUserId {
            disk.delete(name: Self.cacheName(for: ownerUserId))
        }
        disk.delete(name: Self.cacheName)
        items = []
        selectedType = nil
        symbolFilter = ""
        isLoading = false
        isRefreshing = false
        isLoadingMore = false
        hasMore = true
        errorText = nil
        lastRefreshedAt = nil
        fetchedForUserId = nil
        fetchedFilterType = nil
        historyCursor = nil
        realtimeById = [:]
        ownerUserId = nil
        clearToast()
    }

    private func replace(_ next: [AppNotification], userId: String) {
        let fetched = NotificationHistory.sort(
            next.map { stamped($0, userId: userId) }.filter { belongsToCurrentUser($0, userId: userId) }
        )
        let fetchedIds = Set(fetched.map(\.id))
        realtimeById = realtimeById.filter { !fetchedIds.contains($0.key) }
        items = NotificationHistory.sort(fetched + Array(realtimeById.values))
        fetchedForUserId = userId
        fetchedFilterType = currentFilterTypeKey
        lastRefreshedAt = Date()
        hasMore = next.count == PushAPI.pageSize
        historyCursor = fetched.map(\.sentAt).min()
        persist()
    }

    private var currentFilterTypeKey: String {
        selectedType?.rawValue ?? ""
    }

    private var historyTypeParam: String? {
        selectedType?.rawValue
    }

    private func persist() {
        persistUnfilteredCache()
    }

    private func persistUnfilteredCache(merging extra: AppNotification? = nil) {
        guard let ownerUserId else { return }
        if selectedType == nil {
            disk.write(items, name: Self.cacheName(for: ownerUserId))
            return
        }
        guard let extra else { return }
        var cached = disk.read([AppNotification].self, name: Self.cacheName(for: ownerUserId)) ?? []
        cached = NotificationHistory.sort([extra] + cached.filter { $0.id != extra.id })
        disk.write(cached, name: Self.cacheName(for: ownerUserId))
    }

    private func belongsToCurrentUser(_ notification: AppNotification, userId: String) -> Bool {
        guard let incoming = notification.ownerUserId else { return true }
        return incoming == userId
    }

    private func stamped(_ notification: AppNotification, userId: String) -> AppNotification {
        var item = notification
        if item.ownerUserId == nil {
            item.userId = userId
        }
        return item
    }

    private func presentToast(_ notification: AppNotification) {
        toastTask?.cancel()
        toast = notification
        let id = notification.id
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.toastDuration)
            guard !Task.isCancelled else { return }
            if self?.toast?.id == id {
                self?.toast = nil
            }
        }
    }

    private static func sanitizedUserId(_ userId: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(userId.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }
}
