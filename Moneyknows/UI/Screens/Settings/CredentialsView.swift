import SwiftUI

struct CredentialsView: View {
    @EnvironmentObject private var brokerage: CurrentBrokerageStore
    @State private var environment: BrokerageEnvironment = .paper
    @State private var apiKey = ""
    @State private var apiSecret = ""
    @State private var showSecret = false
    @State private var busy = false
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        Form {
            Section {
                Picker(L10n.Credentials.accountType, selection: $environment) {
                    Text(L10n.Credentials.paper).tag(BrokerageEnvironment.paper)
                    Text(L10n.Credentials.live).tag(BrokerageEnvironment.live)
                }
                .pickerStyle(.segmented)
                .onChange(of: environment) { _ in
                    loadFields()
                }
                Text(L10n.Credentials.accountTypeHelp)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                TextField(L10n.Credentials.apiKey, text: $apiKey)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .textContentType(.none)

                if showSecret {
                    TextField(L10n.Credentials.apiSecret, text: $apiSecret)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                } else {
                    SecureField(L10n.Credentials.apiSecret, text: $apiSecret)
                }

                Button(showSecret ? L10n.Credentials.hideSecret : L10n.Credentials.showSecret) {
                    showSecret.toggle()
                }
            } footer: {
                Text(currentStatus)
            }

            Section {
                PrimaryButton(title: L10n.Common.save, busy: busy, action: save)
                if isDirty {
                    Button(L10n.Common.cancel) {
                        loadFields()
                        message = nil
                    }
                }
            }

            Section {
                Text(L10n.Credentials.securityNotice)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            if let message {
                Section {
                    Text(message)
                        .foregroundColor(isError ? .red : .secondary)
                }
            }
        }
        .navigationTitle(L10n.Credentials.title)
        .onAppear {
            environment = brokerage.current?.environment ?? .paper
            loadFields()
        }
    }

    private var currentStatus: String {
        if let current = brokerage.current {
            let kind = current.environment == .live ? L10n.Credentials.live : L10n.Credentials.paper
            return "\(L10n.Credentials.currentAccount): \(kind)"
        }
        return L10n.Credentials.noAccount
    }

    private var isDirty: Bool {
        let saved = brokerage.credentials(for: environment)
        return apiKey.trimmingCharacters(in: .whitespacesAndNewlines) != (saved?.key ?? "")
            || apiSecret.trimmingCharacters(in: .whitespacesAndNewlines) != (saved?.secret ?? "")
            || environment != brokerage.current?.environment
    }

    private func loadFields() {
        let saved = brokerage.credentials(for: environment)
        apiKey = saved?.key ?? ""
        apiSecret = saved?.secret ?? ""
    }

    private func save() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = apiSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        message = nil
        isError = false

        if key.isEmpty != secret.isEmpty {
            message = L10n.Credentials.incomplete
            isError = true
            return
        }

        busy = true
        Task {
            defer { busy = false }
            do {
                if key.isEmpty {
                    try brokerage.clear(environment: environment)
                    loadFields()
                    message = L10n.Credentials.cleared
                } else {
                    try await brokerage.replace(key: key, secret: secret, environment: environment)
                    loadFields()
                    message = L10n.Credentials.saved
                }
            } catch {
                isError = true
                message = UserFacingError.message(from: error) ?? L10n.Errors.generic
            }
        }
    }
}
