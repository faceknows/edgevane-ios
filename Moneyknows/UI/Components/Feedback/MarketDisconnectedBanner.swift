import SwiftUI

struct MarketDisconnectedBanner: View {
    var body: some View {
        Text(L10n.Market.disconnected)
            .font(.caption.weight(.semibold))
            .foregroundColor(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
