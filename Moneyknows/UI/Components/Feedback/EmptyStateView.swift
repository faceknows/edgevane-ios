import SwiftUI

struct EmptyStateView: View {
    var title: String
    var message: String?
    var retryTitle: String? = nil
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            if let message, !message.isEmpty {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let retry {
                Button(retryTitle ?? L10n.Common.retry, action: retry)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
