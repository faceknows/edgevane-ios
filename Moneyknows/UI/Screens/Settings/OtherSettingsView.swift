import SwiftUI

struct OtherSettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var confirmDelete = false
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        List {
            Section(L10n.Other.account) {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.Other.deleteAccount)
                        Text(L10n.Other.deleteAccountHelp)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .disabled(busy)
            }

            if let errorText {
                Section {
                    Text(errorText).foregroundColor(.red)
                }
            }
        }
        .navigationTitle(L10n.Other.title)
        .confirmationDialog(L10n.Other.deleteConfirmTitle, isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L10n.Other.deleteConfirmAction, role: .destructive) {
                deleteAccount()
            }
            Button(L10n.Common.cancel, role: .cancel) {}
        } message: {
            Text(L10n.Other.deleteConfirmMessage)
        }
        .overlay {
            if busy {
                ProgressView()
            }
        }
    }

    private func deleteAccount() {
        guard !busy else { return }
        busy = true
        errorText = nil
        Task {
            defer { busy = false }
            let generation = appModel.session.generation
            do {
                try await appModel.userAPI.deleteMe()
                guard appModel.session.generation == generation else { return }
                appModel.session.signOut()
            } catch {
                guard appModel.session.generation == generation else { return }
                errorText = UserFacingError.message(from: error) ?? L10n.Errors.generic
            }
        }
    }
}
