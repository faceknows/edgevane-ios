import SwiftUI

struct SettingsHomeView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var appearance: AppearanceStore
    @EnvironmentObject private var pushPreference: PushPreferenceStore
    @State private var confirmLogout = false
    @State private var showLanguagePicker = false
    @State private var showPushDenied = false

    var body: some View {
        List {
            Section(L10n.Settings.signedInAs) {
                Text(appModel.session.user?.email ?? "—")
                if !AppEnvironment.isProduction {
                    Text(AppEnvironment.debugSummary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                NavigationLink(L10n.Settings.manageCredentials) {
                    CredentialsView()
                }
                NavigationLink(L10n.Settings.preferences) {
                    PreferencesView()
                }
                NavigationLink(L10n.Settings.profile) {
                    ProfileView()
                }
                NavigationLink(L10n.Settings.other) {
                    OtherSettingsView()
                }
            }

            Section(L10n.Common.notifications) {
                Toggle(isOn: pushBinding) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.Settings.pushNotifications)
                        Text(pushPreference.permissionDenied ? L10n.Settings.permissionOff : L10n.Settings.receivePush)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .disabled(pushPreference.isUpdating)
            }

            Section(L10n.Common.appearance) {
                Picker(L10n.Settings.darkMode, selection: $appearance.preference) {
                    Text(L10n.Settings.appearanceSystem).tag(AppearancePreference.system)
                    Text(L10n.Settings.appearanceLight).tag(AppearancePreference.light)
                    Text(L10n.Settings.appearanceDark).tag(AppearancePreference.dark)
                }
            }

            Section(L10n.Common.language) {
                Button(languageLabel) {
                    showLanguagePicker = true
                }
            }

            Section(L10n.Common.about) {
                HStack {
                    Text(L10n.Common.version)
                    Spacer()
                    Text(AppEnvironment.appVersion)
                        .foregroundColor(.secondary)
                }
                if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
                    HStack {
                        Text(L10n.Common.build)
                        Spacer()
                        Text(build)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section {
                Button(L10n.Settings.signOut, role: .destructive) {
                    confirmLogout = true
                }
            }

            Section {
                Text(L10n.Settings.footer)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(L10n.Settings.title)
        .confirmationDialog(L10n.Settings.logoutTitle, isPresented: $confirmLogout, titleVisibility: .visible) {
            Button(L10n.Common.logout, role: .destructive) {
                appModel.session.signOut()
            }
            Button(L10n.Common.cancel, role: .cancel) {}
        } message: {
            Text(L10n.Settings.logoutMessage)
        }
        .confirmationDialog(L10n.Common.language, isPresented: $showLanguagePicker, titleVisibility: .visible) {
            Button(L10n.Common.followSystem) { setLocale(nil) }
            Button(L10n.Settings.languageEnglish) { setLocale(.en) }
            Button(L10n.Settings.languageChinese) { setLocale(.zh) }
            Button(L10n.Common.cancel, role: .cancel) {}
        }
        .alert(L10n.Settings.notificationDeniedTitle, isPresented: $showPushDenied) {
            Button(L10n.Common.done, role: .cancel) {}
        } message: {
            Text(L10n.Settings.notificationDeniedMessage)
        }
        .onChange(of: pushPreference.permissionDenied) { denied in
            if denied {
                showPushDenied = true
            }
        }
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

    private var pushBinding: Binding<Bool> {
        Binding(
            get: { pushPreference.isEnabled },
            set: { newValue in
                Task { await pushPreference.setEnabled(newValue) }
            }
        )
    }

    private func setLocale(_ locale: AppLocale?) {
        guard let userId = appModel.session.user?.id else { return }
        Task {
            await preferences.apply({ $0.locale = locale }, patch: UserPreferencePatch(
                locale: locale.map { .code($0.rawValue) } ?? .followSystem
            ), userId: userId)
        }
    }
}
