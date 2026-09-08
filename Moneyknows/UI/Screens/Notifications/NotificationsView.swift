import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject private var notifications: NotificationStore
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: AppRouter

    private var volumeThreshold: Int {
        preferences.values.notificationVolumeThreshold
    }

    private var filterTaskID: String {
        "\(notifications.symbolFilter)|\(volumeThreshold)"
    }

    private var visible: [AppNotification] {
        notifications.visibleItems(volumeThreshold: volumeThreshold)
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            if let error = notifications.errorText {
                errorBanner(error)
            }
            content
        }
        .navigationTitle(L10n.Notifications.title)
        .onAppear { router.setViewingNotifications(true) }
        .onDisappear { router.setViewingNotifications(false) }
        .task {
            await notifications.refreshOnFocus(
                userId: session.user?.id,
                volumeThreshold: volumeThreshold
            )
        }
        .onChange(of: notifications.selectedType) { _ in
            Task {
                await notifications.refresh(
                    userId: session.user?.id,
                    volumeThreshold: volumeThreshold
                )
            }
        }
        .task(id: filterTaskID) {
            await notifications.continueThroughFilteredPages(
                userId: session.user?.id,
                volumeThreshold: volumeThreshold
            )
        }
        .refreshable {
            await notifications.refresh(
                userId: session.user?.id,
                volumeThreshold: volumeThreshold
            )
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            TextField(L10n.Notifications.symbolsPlaceholder, text: $notifications.symbolFilter)
                .textInputAutocapitalization(.characters)
                .disableAutocorrection(true)
                .textFieldStyle(.roundedBorder)
            Picker(L10n.Notifications.filterType, selection: $notifications.selectedType) {
                Text(L10n.Notifications.filterAll).tag(nil as NotificationKind?)
                Text(L10n.Notifications.filterTrendUp).tag(NotificationKind.marketTrendUpReversal as NotificationKind?)
                Text(L10n.Notifications.filterTrendDown).tag(NotificationKind.marketTrendDownReversal as NotificationKind?)
                Text(L10n.Notifications.filterIntradayHigh).tag(NotificationKind.intradayHighRetest as NotificationKind?)
                Text(L10n.Notifications.filterIntradayLow).tag(NotificationKind.intradayLowRetest as NotificationKind?)
                Text(L10n.Notifications.filterBreakout).tag(NotificationKind.intradayBreakout as NotificationKind?)
                Text(L10n.Notifications.filterWeakPullback).tag(NotificationKind.intradayWeakPullback as NotificationKind?)
            }
            .labelsHidden()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if notifications.isLoading && notifications.items.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visible.isEmpty {
            emptyState
        } else {
            List {
                ForEach(visible) { item in
                    NotificationRow(notification: item) {
                            router.handleNotification(
                                item,
                                versionPassed: true,
                                signedIn: session.isSignedIn,
                                currentUserId: session.user?.id,
                                alreadyShowingHistory: true
                            )
                    }
                    .onAppear {
                        if item.id == visible.last?.id {
                            Task { await loadMoreIfNeeded() }
                        }
                    }
                }
                if notifications.hasMore {
                    Color.clear
                        .frame(height: 1)
                        .listRowSeparator(.hidden)
                        .onAppear {
                            Task { await loadMoreIfNeeded() }
                        }
                }
                if notifications.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            if notifications.hasActiveFilters(volumeThreshold: volumeThreshold) {
                EmptyStateView(
                    title: L10n.Notifications.filteredEmptyTitle,
                    message: L10n.Notifications.filteredEmptyBody
                )
                Button(L10n.Notifications.filterAll) {
                    resetAllFilters()
                }
                .buttonStyle(.bordered)
                if notifications.hasMore {
                    Button(L10n.Notifications.loadMore) {
                        Task {
                            await notifications.loadMore(
                                userId: session.user?.id,
                                volumeThreshold: volumeThreshold
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                EmptyStateView(
                    title: L10n.Notifications.emptyTitle,
                    message: L10n.Notifications.emptyBody
                )
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadMoreIfNeeded() async {
        await notifications.loadMore(
            userId: session.user?.id,
            volumeThreshold: volumeThreshold
        )
    }

    private func resetAllFilters() {
        notifications.resetFilters()
        guard volumeThreshold > 0, let userId = session.user?.id else { return }
        Task {
            await preferences.apply(
                { $0.notificationVolumeThreshold = 0 },
                patch: UserPreferencePatch(notificationVolumeThreshold: 0),
                userId: userId
            )
        }
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.Notifications.loadFailed)
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundColor(.secondary)
            Button(L10n.Notifications.retry) {
                Task {
                    await notifications.refresh(
                        userId: session.user?.id,
                        volumeThreshold: volumeThreshold
                    )
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
    }
}

struct NotificationRow: View {
    var notification: AppNotification
    var onOpen: () -> Void
    @EnvironmentObject private var router: AppRouter

    private var parsed: ParsedNotification {
        NotificationParser.parse(notification)
    }

    private var title: String {
        NotificationParser.displayTitle(for: notification)
    }

    private var directionalColor: Color? {
        switch parsed.kind {
        case .intradayHighRetest, .marketTrendDownReversal:
            return .red
        case .intradayLowRetest, .marketTrendUpReversal:
            return .green
        default:
            return nil
        }
    }

    private var icon: String {
        switch parsed.kind {
        case .marketTrendUpReversal: return "↗"
        case .marketTrendDownReversal: return "↘"
        case .intradayHighRetest: return "⇧"
        case .intradayLowRetest: return "⇩"
        default: return "🔔"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(icon)
                            .font(.headline)
                            .foregroundColor(directionalColor ?? .accentColor)
                            .frame(width: 36, height: 36)
                            .background((directionalColor ?? .accentColor).opacity(0.12))
                            .clipShape(Circle())
                        Spacer()
                        Text(NewsTime.listLabel(for: notification.sentDate))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    Text(title)
                        .font(.headline)
                    if !parsed.body.isEmpty {
                        Text(parsed.body)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            symbolChips
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var symbolChips: some View {
        let ordered = orderedSymbols
        if !ordered.isEmpty {
            FlexibleSymbolChips(
                symbols: ordered,
                priority: Set(parsed.prioritySymbols),
                tint: directionalColor
            ) { symbol in
                router.openSymbol(symbol)
            }
        }
    }

    private var orderedSymbols: [String] {
        let priority = Set(parsed.prioritySymbols)
        return parsed.prioritySymbols.filter { parsed.symbols.contains($0) }
            + parsed.symbols.filter { !priority.contains($0) }
    }
}

private struct FlexibleSymbolChips: View {
    var symbols: [String]
    var priority: Set<String>
    var tint: Color?
    var onTap: (String) -> Void

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 56), spacing: 8, alignment: .leading)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(symbols, id: \.self) { symbol in
                Button {
                    onTap(symbol)
                } label: {
                    Text(symbol)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundColor(chipForeground(symbol))
                        .background(chipBackground(symbol))
                        .overlay(
                            Capsule().stroke(chipBorder(symbol), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func chipForeground(_ symbol: String) -> Color {
        if priority.contains(symbol) { return Color(red: 0.86, green: 0.15, blue: 0.15) }
        return tint ?? .accentColor
    }

    private func chipBackground(_ symbol: String) -> Color {
        if priority.contains(symbol) {
            return Color(red: 0.996, green: 0.886, blue: 0.886)
        }
        return (tint ?? .accentColor).opacity(0.08)
    }

    private func chipBorder(_ symbol: String) -> Color {
        if priority.contains(symbol) {
            return Color(red: 0.937, green: 0.267, blue: 0.267)
        }
        return (tint ?? .accentColor).opacity(0.4)
    }
}

extension NewsTime {
    static func listLabel(for date: Date, now: Date = Date()) -> String {
        "\(relative(date, now: now)) • \(absolute(date))"
    }
}
