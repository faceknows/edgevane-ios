import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var profile: ProfileStore

    var body: some View {
        List {
            if let error = profile.errorText {
                Section {
                    Text(error).foregroundColor(.red)
                }
            }

            Section(L10n.Profile.title) {
                row(L10n.Profile.nickname, session.user?.nickname)
                row(L10n.Profile.email, session.user?.email)
                row(L10n.Profile.username, session.user?.username)
                row(L10n.Profile.role, session.user?.role)
            }

            Section(L10n.Profile.enabledFeatures) {
                enabledFeaturesSection
            }

            Section(L10n.Profile.roleConfiguration) {
                roleConfigurationSection
            }
        }
        .navigationTitle(L10n.Profile.title)
        .overlay {
            if profile.isLoading {
                ProgressView()
            }
        }
        .task {
            await profile.refresh()
        }
    }

    @ViewBuilder
    private var enabledFeaturesSection: some View {
        if let features = profile.roleConfiguration?.enabledFeatureKeys, !features.isEmpty {
            ForEach(features, id: \.self) { key in
                Text(key)
            }
        } else {
            Text(L10n.Common.none).foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var roleConfigurationSection: some View {
        if let entries = profile.roleConfiguration?.sortedEntries, !entries.isEmpty {
            ForEach(entries, id: \.key) { entry in
                HStack {
                    Text(entry.key)
                    Spacer()
                    Text(entry.value.displayText)
                        .foregroundColor(.secondary)
                }
            }
        } else {
            Text(L10n.Profile.noRoleConfiguration).foregroundColor(.secondary)
        }
    }

    private func row(_ title: String, _ value: String?) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value?.isEmpty == false ? value! : "—")
                .foregroundColor(.secondary)
        }
    }
}
