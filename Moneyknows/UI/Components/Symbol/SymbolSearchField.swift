import SwiftUI

struct SymbolSearchField: View {
    @Binding var text: String
    var placeholder: String
    var busy: Bool
    var onSubmit: () -> Void

    var body: some View {
        HStack {
            TextField(placeholder, text: $text)
                .autocapitalization(.allCharacters)
                .disableAutocorrection(true)
                .textFieldStyle(.roundedBorder)
                .onSubmit(onSubmit)
            if busy {
                ProgressView()
            } else {
                Button(L10n.Market.search, action: onSubmit)
                    .disabled(SymbolCode.normalize(text).isEmpty)
            }
        }
    }
}
