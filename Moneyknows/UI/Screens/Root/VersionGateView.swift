import SwiftUI
import UIKit

struct VersionGateView: View {
    @ObservedObject var model: VersionGateModel

    var body: some View {
        VStack(spacing: 16) {
            switch model.state {
            case .checking:
                ProgressView()
                Text(L10n.Version.checking)
                    .foregroundColor(.secondary)
            case let .failed(message):
                Text(message)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button(L10n.Common.retry) {
                    Task { await model.check() }
                }
                .buttonStyle(.borderedProminent)
            case let .blocked(message, storeURL):
                Text(message)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button(L10n.Version.openStore) {
                    UIApplication.shared.open(storeURL)
                }
                .buttonStyle(.borderedProminent)
            case .passed:
                ProgressView()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
