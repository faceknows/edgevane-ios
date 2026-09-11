import SwiftUI

struct SymbolSearchField: View {
    enum Chrome {
        case bordered
        case inset
    }

    @Binding var text: String
    var placeholder: String
    var busy: Bool
    var chrome: Chrome = .bordered
    var isFocused: FocusState<Bool>.Binding
    var onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if chrome == .inset {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
            }
            field
            if busy {
                ProgressView()
            } else {
                Button(L10n.Market.search, action: dismissAndSubmit)
                    .disabled(SymbolCode.normalize(text).isEmpty)
            }
        }
        .padding(chrome == .inset ? 12 : 0)
        .background(chrome == .inset ? Color(uiColor: .tertiarySystemFill) : Color.clear)
        .cornerRadius(chrome == .inset ? 12 : 0)
    }

    @ViewBuilder
    private var field: some View {
        if chrome == .bordered {
            TextField(placeholder, text: $text)
                .autocapitalization(.allCharacters)
                .disableAutocorrection(true)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)
                .focused(isFocused)
                .onSubmit(dismissAndSubmit)
        } else {
            TextField(placeholder, text: $text)
                .autocapitalization(.allCharacters)
                .disableAutocorrection(true)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .focused(isFocused)
                .onSubmit(dismissAndSubmit)
        }
    }

    private func dismissAndSubmit() {
        isFocused.wrappedValue = false
        onSubmit()
    }
}
