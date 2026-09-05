import SwiftUI

struct FormMessage: View {
    var text: String?

    var body: some View {
        if let text, !text.isEmpty {
            Text(text)
                .font(.footnote)
                .foregroundColor(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct PrimaryButton: View {
    var title: String
    var busy: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            if busy {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .frame(maxWidth: .infinity)
            } else {
                Text(title)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(busy)
    }
}
