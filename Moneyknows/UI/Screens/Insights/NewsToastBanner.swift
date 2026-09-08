import SwiftUI

struct NewsToastBanner: View {
    @EnvironmentObject private var news: NewsStore
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        if let item = news.toast {
            Button {
                news.clearToast()
                router.openNews(item.id)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displaySymbol)
                        .font(.caption.weight(.semibold))
                    Text(item.displayHeadline)
                        .font(.footnote)
                        .lineLimit(2)
                }
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(uiColor: .secondarySystemBackground))
            }
            .buttonStyle(.plain)
        }
    }
}
