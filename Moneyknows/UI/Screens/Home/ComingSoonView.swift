import SwiftUI

struct ComingSoonView: View {
    var title: String

    var body: some View {
        EmptyStateView(title: title, message: L10n.Home.comingSoon)
            .padding()
            .navigationTitle(title)
    }
}
