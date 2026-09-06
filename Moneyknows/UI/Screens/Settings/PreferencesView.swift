import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var blacklist: AutoExitBlacklistStore

    @State private var valuePerTradeInput = ""
    @State private var protectMinutesInput = ""
    @State private var takeProfitInput = ""
    @State private var stopLossInput = ""
    @State private var showLanguagePicker = false
    @State private var lastFocusedField: NumberField?
    @FocusState private var focusedField: NumberField?

    var body: some View {
        Form {
            if preferences.isLoading || preferences.isSaving || preferences.errorText != nil {
                Section {
                    if preferences.isLoading {
                        Text(L10n.Prefs.loading).foregroundColor(.secondary)
                    }
                    if preferences.isSaving {
                        Text(L10n.Prefs.saving).foregroundColor(.secondary)
                    }
                    if let error = preferences.errorText {
                        Text(error).foregroundColor(.red)
                    }
                }
            }

            Section(L10n.Common.language) {
                Button {
                    showLanguagePicker = true
                } label: {
                    HStack {
                        Text(L10n.Prefs.yourLanguage)
                            .foregroundColor(.primary)
                        Spacer()
                        Text(languageLabel)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section(L10n.Prefs.tradeSection) {
                TextField(L10n.Prefs.valuePerTrade(maxOrderText), text: $valuePerTradeInput)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .valuePerTrade)
                Text(L10n.Prefs.valuePerTradeHelp(maxOrderText))
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField(L10n.Prefs.protectMinutes, text: $protectMinutesInput)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .protectMinutes)
                Text(L10n.Prefs.protectMinutesHelp)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(L10n.Prefs.actionsSection) {
                Toggle(isOn: boolBinding(\.showOTOAction, patch: { UserPreferencePatch(showOTOAction: $0) })) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.Prefs.showOTO)
                        Text(L10n.Prefs.showOTOHelp).font(.caption).foregroundColor(.secondary)
                    }
                }

                Toggle(isOn: boolBinding(\.showMarketTrade, patch: { UserPreferencePatch(showMarketTrade: $0) })) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.Prefs.showMarketFlatten)
                        Text(L10n.Prefs.showMarketFlattenHelp).font(.caption).foregroundColor(.secondary)
                    }
                }

                Toggle(isOn: takeProfitEnabledBinding) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.Prefs.autoTakeProfit)
                        Text(L10n.Prefs.autoTakeProfitHelp).font(.caption).foregroundColor(.secondary)
                    }
                }
                if preferences.values.isAutoTakeProfitOn {
                    TextField(L10n.Prefs.protectionPercent, text: $takeProfitInput)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .takeProfit)
                    Text(L10n.Prefs.protectionError)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Toggle(isOn: stopLossEnabledBinding) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.Prefs.autoStopLoss)
                        Text(L10n.Prefs.autoStopLossHelp).font(.caption).foregroundColor(.secondary)
                    }
                }
                if preferences.values.isAutoStopLossOn {
                    TextField(L10n.Prefs.protectionPercent, text: $stopLossInput)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .stopLoss)
                    Text(L10n.Prefs.protectionError)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section(L10n.Prefs.chartSection) {
                Toggle(isOn: boolBinding(\.showIndexBarInDetail, patch: { UserPreferencePatch(showIndexBarInDetail: $0) })) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.Prefs.showIndexBar)
                        Text(L10n.Prefs.showIndexBarHelp).font(.caption).foregroundColor(.secondary)
                    }
                }
                Toggle(isOn: boolBinding(\.showDailyBarInDetail, patch: { UserPreferencePatch(showDailyBarInDetail: $0) })) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.Prefs.showDailyBar)
                        Text(L10n.Prefs.showDailyBarHelp).font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            Section {
                Picker(L10n.Prefs.volumeThreshold, selection: volumeBinding) {
                    ForEach(UserPreferences.volumeThresholds, id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                Text(L10n.Prefs.volumeThresholdHelp)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text(L10n.Prefs.notificationsSection)
            }

            Section(L10n.Prefs.takeProfitBlacklist) {
                if blacklist.values.takeProfit.isEmpty {
                    Text(L10n.Prefs.blacklistEmpty).foregroundColor(.secondary)
                }
                ForEach(blacklist.values.takeProfit, id: \.self) { symbol in
                    Text(symbol)
                }
                .onDelete { offsets in
                    offsets.map { blacklist.values.takeProfit[$0] }.forEach(blacklist.removeTakeProfit)
                }
            }

            Section(L10n.Prefs.stopLossBlacklist) {
                if blacklist.values.stopLoss.isEmpty {
                    Text(L10n.Prefs.blacklistEmpty).foregroundColor(.secondary)
                }
                ForEach(blacklist.values.stopLoss, id: \.self) { symbol in
                    Text(symbol)
                }
                .onDelete { offsets in
                    offsets.map { blacklist.values.stopLoss[$0] }.forEach(blacklist.removeStopLoss)
                }
            }

            Section {
                Button(L10n.Prefs.reset) {
                    guard let userId = appModel.session.user?.id else { return }
                    Task {
                        await preferences.restoreDefaults(userId: userId)
                        syncUnfocusedInputs()
                    }
                }
            }
        }
        .navigationTitle(L10n.Prefs.title)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L10n.Common.done) {
                    focusedField = nil
                }
            }
        }
        .onAppear {
            syncUnfocusedInputs()
            if let userId = appModel.session.user?.id {
                Task { await preferences.refreshIfNeeded(userId: userId) }
            }
        }
        .onDisappear {
            commit(lastFocusedField ?? focusedField)
        }
        .onChange(of: focusedField) { newValue in
            commit(lastFocusedField)
            lastFocusedField = newValue
        }
        .onChange(of: preferences.values) { _ in
            syncUnfocusedInputs()
        }
        .confirmationDialog(L10n.Common.language, isPresented: $showLanguagePicker, titleVisibility: .visible) {
            Button(L10n.Common.followSystem) { setLocale(nil) }
            Button(L10n.Settings.languageEnglish) { setLocale(.en) }
            Button(L10n.Settings.languageChinese) { setLocale(.zh) }
            Button(L10n.Common.cancel, role: .cancel) {}
        }
    }

    private var maxOrderValue: Double {
        profile.roleConfiguration?.maxOrderValue ?? 50
    }

    private var maxOrderText: String {
        if maxOrderValue.rounded() == maxOrderValue {
            return String(Int(maxOrderValue))
        }
        return String(maxOrderValue)
    }

    private var languageLabel: String {
        switch preferences.values.locale {
        case .en:
            return L10n.Settings.languageEnglish
        case .zh:
            return L10n.Settings.languageChinese
        case nil:
            return L10n.Common.followSystem
        }
    }

    private var volumeBinding: Binding<Int> {
        Binding(
            get: { preferences.values.notificationVolumeThreshold },
            set: { value in
                apply({ $0.notificationVolumeThreshold = value }, UserPreferencePatch(notificationVolumeThreshold: value))
            }
        )
    }

    private var takeProfitEnabledBinding: Binding<Bool> {
        Binding(
            get: { preferences.values.isAutoTakeProfitOn },
            set: { enabled in
                let value = enabled ? UserPreferences.protectionOrDefault(preferences.values.autoTakeProfitPercent) : 0
                apply({ $0.autoTakeProfitPercent = value }, UserPreferencePatch(autoTakeProfitPercent: value))
            }
        )
    }

    private var stopLossEnabledBinding: Binding<Bool> {
        Binding(
            get: { preferences.values.isAutoStopLossOn },
            set: { enabled in
                let value = enabled ? UserPreferences.protectionOrDefault(preferences.values.autoStopLossPercent) : 0
                apply({ $0.autoStopLossPercent = value }, UserPreferencePatch(autoStopLossPercent: value))
            }
        )
    }

    private func boolBinding(
        _ keyPath: WritableKeyPath<UserPreferences, Bool>,
        patch: @escaping (Bool) -> UserPreferencePatch
    ) -> Binding<Bool> {
        Binding(
            get: { preferences.values[keyPath: keyPath] },
            set: { value in
                apply({ $0[keyPath: keyPath] = value }, patch(value))
            }
        )
    }

    private func commit(_ field: NumberField?) {
        switch field {
        case .valuePerTrade:
            commitValuePerTrade()
        case .protectMinutes:
            commitProtectMinutes()
        case .takeProfit:
            commitTakeProfit()
        case .stopLoss:
            commitStopLoss()
        case nil:
            break
        }
    }

    private func commitValuePerTrade() {
        let parsed = Double(valuePerTradeInput.trimmingCharacters(in: .whitespacesAndNewlines))
        let value = UserPreferences.clampValuePerTrade(parsed ?? UserPreferences.defaults.valuePerTrade, maxOrderValue: maxOrderValue)
        valuePerTradeInput = format(value)
        guard value != preferences.values.valuePerTrade else { return }
        apply({ $0.valuePerTrade = value }, UserPreferencePatch(valuePerTrade: value))
    }

    private func commitProtectMinutes() {
        let parsed = Int(protectMinutesInput.trimmingCharacters(in: .whitespacesAndNewlines))
        let value = UserPreferences.clamp(parsed ?? 30, min: 0, max: 300)
        protectMinutesInput = String(value)
        guard value != preferences.values.allowTradeInMinutesAfterOpen else { return }
        apply({ $0.allowTradeInMinutesAfterOpen = value }, UserPreferencePatch(allowTradeInMinutesAfterOpen: value))
    }

    private func commitTakeProfit() {
        let parsed = Double(takeProfitInput.trimmingCharacters(in: .whitespacesAndNewlines))
        let value = UserPreferences.normalizeProtection(parsed ?? UserPreferences.protectionDefault)
        let next = value > 0 ? value : UserPreferences.protectionDefault
        takeProfitInput = format(next)
        guard next != preferences.values.autoTakeProfitPercent else { return }
        apply({ $0.autoTakeProfitPercent = next }, UserPreferencePatch(autoTakeProfitPercent: next))
    }

    private func commitStopLoss() {
        let parsed = Double(stopLossInput.trimmingCharacters(in: .whitespacesAndNewlines))
        let value = UserPreferences.normalizeProtection(parsed ?? UserPreferences.protectionDefault)
        let next = value > 0 ? value : UserPreferences.protectionDefault
        stopLossInput = format(next)
        guard next != preferences.values.autoStopLossPercent else { return }
        apply({ $0.autoStopLossPercent = next }, UserPreferencePatch(autoStopLossPercent: next))
    }

    private func setLocale(_ locale: AppLocale?) {
        apply({ $0.locale = locale }, UserPreferencePatch(
            locale: locale.map { .code($0.rawValue) } ?? .followSystem
        ))
    }

    private func apply(_ transform: @escaping (inout UserPreferences) -> Void, _ patch: UserPreferencePatch) {
        guard let userId = appModel.session.user?.id else { return }
        Task { await preferences.apply(transform, patch: patch, userId: userId) }
    }

    private func syncUnfocusedInputs() {
        let values = preferences.values
        if focusedField != .valuePerTrade {
            valuePerTradeInput = format(values.valuePerTrade)
        }
        if focusedField != .protectMinutes {
            protectMinutesInput = String(values.allowTradeInMinutesAfterOpen)
        }
        if focusedField != .takeProfit {
            takeProfitInput = format(UserPreferences.protectionOrDefault(values.autoTakeProfitPercent))
        }
        if focusedField != .stopLoss {
            stopLossInput = format(UserPreferences.protectionOrDefault(values.autoStopLossPercent))
        }
    }

    private enum NumberField: Hashable {
        case valuePerTrade
        case protectMinutes
        case takeProfit
        case stopLoss
    }

    private func format(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value)
    }
}
